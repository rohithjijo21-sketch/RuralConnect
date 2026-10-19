library;

import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:geolocator/geolocator.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'src/live_socket.dart';

import 'src/api.dart';
import 'src/connection.dart';
import 'src/passenger.dart';
export 'src/passenger.dart';
export 'src/demo.dart';
export 'src/api.dart';

final apiProvider = Provider<Api>((ref) => Api());

class RuralConnectApp extends ConsumerStatefulWidget {
  final String mode, title;
  final Color color;
  const RuralConnectApp({
    super.key,
    required this.mode,
    required this.title,
    required this.color,
  });
  @override
  ConsumerState<RuralConnectApp> createState() => _AppState();
}

class _AppState extends ConsumerState<RuralConnectApp> {
  late final GoRouter router = GoRouter(
    routes: [
      GoRoute(
        path: '/',
        builder: (context, state) => ConnectionGate(
          api: ref.read(apiProvider),
          mode: widget.mode,
          title: widget.title,
          builder: (api, settings) => widget.mode == 'passenger'
              ? PassengerScreen(api: api, onConnectionSettings: settings)
              : ProviderScope(
                  overrides: [apiProvider.overrideWithValue(api)],
                  child: Home(
                    mode: widget.mode,
                    title: widget.title,
                    onConnectionSettings: settings,
                  ),
                ),
        ),
      ),
    ],
  );
  @override
  void dispose() {
    router.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => MaterialApp.router(
    title: widget.title,
    debugShowCheckedModeBanner: false,
    routerConfig: router,
    supportedLocales: const [Locale('en'), Locale('ml')],
    localizationsDelegates: GlobalMaterialLocalizations.delegates,
    theme: ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(seedColor: widget.color),
      cardTheme: const CardThemeData(margin: EdgeInsets.symmetric(vertical: 8)),
    ),
    darkTheme: ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(
        seedColor: widget.color,
        brightness: Brightness.dark,
      ),
    ),
  );
}

class Home extends ConsumerStatefulWidget {
  final String mode, title;
  final VoidCallback? onConnectionSettings;
  const Home({
    super.key,
    required this.mode,
    required this.title,
    this.onConnectionSettings,
  });
  @override
  ConsumerState<Home> createState() => _HomeState();
}

class _HomeState extends ConsumerState<Home> with WidgetsBindingObserver {
  final phone = TextEditingController(),
      sandbox = TextEditingController(),
      code = TextEditingController(),
      origin = TextEditingController(),
      destination = TextEditingController(),
      reason = TextEditingController();
  String? challenge, error;
  bool busy = false, ready = false, consent = false, offline = false;
  List<dynamic> items = [];
  Timer? timer;
  Map<String, dynamic>? selected;
  StreamSubscription<Position>? gps;
  WebSocketChannel? socket;
  StreamSubscription<dynamic>? socketSub;
  Timer? reconnect;
  String cursor = '0';
  int reconnectAttempt = 0;
  bool disposed = false, ml = false;
  Api get api => ref.read(apiProvider);
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(restore());
  }

  Future<void> restore() async {
    try {
      await api.restore();
      if (api.access != null || api.isDemo) await load();
    } catch (e) {
      if (mounted) setState(() => error = readableError(e));
    }
    if (!mounted) return;
    setState(() => ready = true);
    timer = Timer.periodic(const Duration(seconds: 5), (_) {
      if (api.access != null && !busy) {
        unawaited(
          load().catchError((Object e) {
            if (mounted) {
              setState(() {
                offline = true;
                error = readableError(e);
              });
            }
          }),
        );
      }
    });
  }

  Future<void> action(Future<void> Function() work) async {
    if (busy) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await work();
    } catch (e) {
      if (mounted) setState(() => error = readableError(e));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  String get today {
    final now = DateTime.now().toUtc().add(
      const Duration(hours: 5, minutes: 30),
    );
    return '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
  }

  Future<void> load() async {
    final path = widget.mode == 'bus'
        ? '/crew/trips'
        : widget.mode == 'driver'
        ? '/driver/vehicles'
        : '/bus/trips?date=$today${origin.text.trim().isNotEmpty && destination.text.trim().isNotEmpty ? '&origin=${Uri.encodeComponent(origin.text.trim())}&destination=${Uri.encodeComponent(destination.text.trim())}' : ''}';
    try {
      final data = await api.request(path) as List;
      if (!mounted) return;
      setState(() {
        items = data;
        offline = false;
        error = null;
      });
      if (widget.mode == 'passenger') {
        final prefs = await SharedPreferences.getInstance();
        final cached = data
            .map(
              (r) => {
                ...Map<String, dynamic>.from(r as Map),
                'lat': null,
                'lng': null,
                'locationQuality': 'CACHED_SCHEDULE',
              },
            )
            .toList();
        await prefs.setString(
          'bus_cache',
          jsonEncode({
            'date': today,
            'cachedAt': DateTime.now().toIso8601String(),
            'items': cached,
          }),
        );
      }
      if (selected != null && widget.mode != 'driver') {
        final updated = await api.request('/bus/trips/${selected!['id']}');
        if (mounted) {
          setState(() => selected = Map<String, dynamic>.from(updated as Map));
        }
        if (![
          'RUNNING',
          'DELAYED',
          'STOPPED',
          'DIVERTED',
        ].contains(selected?['status'])) {
          await stopTracking();
        }
      }
    } catch (e) {
      if (mounted) setState(() => offline = true);
      if (widget.mode == 'passenger') {
        final prefs = await SharedPreferences.getInstance();
        final raw = prefs.getString('bus_cache');
        if (raw != null) {
          final cache = jsonDecode(raw) as Map;
          if (cache['date'] == today && mounted) {
            setState(() {
              items = cache['items'] as List;
              offline = true;
            });
          }
        }
      }
      rethrow;
    }
  }

  Future<void> login() async {
    if (api.betaAuth) {
      await api.redeemInvite(phone.text, sandbox.text, consent);
      sandbox.clear();
      await load();
      return;
    }
    if (challenge == null) {
      final r = await api.request(
        '/auth/otp/request',
        method: 'POST',
        data: {'phone': phone.text.trim()},
        headers: {'X-Sandbox-Key': sandbox.text},
      );
      setState(() => challenge = r['challengeId'] as String);
    } else {
      if (!consent) throw StateError('Consent required');
      final r = await api.request(
        '/auth/otp/verify',
        method: 'POST',
        data: {
          'challengeId': challenge,
          'code': code.text,
          'consentVersion': 'development-v1',
        },
      );
      await api.save(Map<String, dynamic>.from(r as Map));
      sandbox.clear();
      await load();
    }
  }

  Future<void> selectTrip(Map<String, dynamic> trip) async {
    await stopTracking();
    await socketSub?.cancel();
    await socket?.sink.close();
    reconnect?.cancel();
    cursor = '0';
    reconnectAttempt = 0;
    setState(() => selected = trip);
    await load();
    connectTrip();
  }

  void connectTrip() {
    if (disposed || selected == null || api.access == null) return;
    final url =
        Uri.parse(
          '${api.dio.options.baseUrl.replaceFirst(RegExp(r'^http'), 'ws')}/live',
        ).replace(
          queryParameters: {
            'tripId': selected!['id'].toString(),
            'after': cursor,
          },
        );
    socket = connectLiveSocket(url, api.access!);
    if (socket == null) return;
    socketSub = socket!.stream.listen(
      (raw) {
        try {
          final event = jsonDecode(raw as String) as Map;
          final next = event['id'].toString();
          if (BigInt.parse(next) <= BigInt.parse(cursor)) return;
          cursor = next;
          reconnectAttempt = 0;
          unawaited(
            load().catchError((Object e) {
              if (mounted) setState(() => error = readableError(e));
            }),
          );
        } catch (_) {
          unawaited(load());
        }
      },
      onError: (Object e) {
        if (mounted) {
          setState(
            () => error =
                'Live connection interrupted. Refetching every 5 seconds.',
          );
        }
      },
      onDone: () {
        if (disposed || selected == null) return;
        final seconds = 1 << reconnectAttempt.clamp(0, 5).toInt();
        reconnectAttempt++;
        reconnect = Timer(Duration(seconds: seconds), connectTrip);
      },
    );
  }

  Future<void> updateStatus(String status) async {
    if (offline) throw StateError('Reconnect before changing service status');
    if (reason.text.trim().isEmpty) {
      throw StateError('Enter an incident reason');
    }
    await api.request(
      '/bus/trips/${selected!['id']}/status',
      method: 'POST',
      data: {
        'status': status,
        'reason': reason.text.trim(),
        'delayMinutes': status == 'DELAYED' ? 10 : 0,
        'version': selected!['version'],
      },
    );
    if (status == 'COMPLETED' || status == 'CANCELLED') await stopTracking();
    await load();
  }

  Future<void> stopTracking() async {
    await gps?.cancel();
    gps = null;
  }

  Future<void> startTracking() async {
    if (selected == null ||
        ![
          'RUNNING',
          'DELAYED',
          'STOPPED',
          'DIVERTED',
        ].contains(selected!['status'])) {
      throw StateError('Start the assigned service before sharing GPS');
    }
    if (!await Geolocator.isLocationServiceEnabled()) {
      throw StateError('Enable device location services');
    }
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      throw StateError(
        'Location permission denied. Scheduled information remains available.',
      );
    }
    await stopTracking();
    gps =
        Geolocator.getPositionStream(
          locationSettings: const LocationSettings(
            accuracy: LocationAccuracy.high,
            distanceFilter: 25,
          ),
        ).listen(
          (p) {
            if (selected == null || p.accuracy > 100) return;
            unawaited(
              api
                  .request(
                    '/bus/trips/${selected!['id']}/location',
                    method: 'POST',
                    data: {
                      'lat': p.latitude,
                      'lng': p.longitude,
                      'accuracyM': p.accuracy.round().clamp(0, 1000),
                      'recordedAt': p.timestamp.toUtc().toIso8601String(),
                    },
                  )
                  .catchError((Object e) {
                    if (mounted) setState(() => error = readableError(e));
                    return null;
                  }),
            );
          },
          onError: (Object e) {
            if (mounted) setState(() => error = readableError(e));
          },
        );
    setState(() {});
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) unawaited(stopTracking());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    disposed = true;
    timer?.cancel();
    reconnect?.cancel();
    unawaited(gps?.cancel());
    unawaited(socketSub?.cancel());
    unawaited(socket?.sink.close());
    for (final c in [phone, sandbox, code, origin, destination, reason]) {
      c.dispose();
    }
    super.dispose();
  }

  Widget field(
    TextEditingController controller,
    String label, {
    bool secret = false,
    TextInputType? keyboard,
  }) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 8),
    child: TextField(
      controller: controller,
      obscureText: secret,
      keyboardType: keyboard,
      decoration: InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
      ),
    ),
  );
  Widget button(String label, Future<void> Function() fn) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 5),
    child: FilledButton(
      onPressed: busy ? null : () => unawaited(action(fn)),
      style: FilledButton.styleFrom(
        minimumSize: const Size(double.infinity, 52),
      ),
      child: Text(label),
    ),
  );
  @override
  Widget build(BuildContext context) {
    final signedIn = api.access != null || api.isDemo;
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
        actions: [
          if (widget.onConnectionSettings != null)
            IconButton(
              tooltip: 'Server connection settings',
              onPressed: widget.onConnectionSettings,
              icon: const Icon(Icons.dns_outlined),
            ),
          if (signedIn && !api.isDemo)
            IconButton(
              tooltip: 'Sign out',
              icon: const Icon(Icons.logout),
              onPressed: () => unawaited(
                action(() async {
                  await stopTracking();
                  await socketSub?.cancel();
                  await socket?.sink.close();
                  reconnect?.cancel();
                  await api.logout();
                  setState(() {
                    items = [];
                    selected = null;
                    challenge = null;
                  });
                }),
              ),
            ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            if (api.isDemo)
              const Card(
                child: Padding(
                  padding: EdgeInsets.all(16),
                  child: Text(
                    'UI DEMO - Sample auto and service only. No real driver verification, availability, bookings or earnings. Connect to your server for real actions.',
                  ),
                ),
              ),
            if (busy) const LinearProgressIndicator(),
            if (error != null)
              Card(
                color: Theme.of(context).colorScheme.errorContainer,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(error!, semanticsLabel: 'Error: $error'),
                ),
              ),
            if (!signedIn) ...[
              Text(
                ml ? 'നിങ്ങളുടെ യാത്ര, ഒരുമിച്ച്' : 'Your journey, connected.',
                style: Theme.of(context).textTheme.headlineMedium,
              ),
              const SizedBox(height: 16),
              Text(
                api.betaAuth
                    ? 'Private beta · invitation only · no SMS required'
                    : 'Development sandbox · no SMS sent',
              ),
              field(phone, 'Phone number (+91)', keyboard: TextInputType.phone),
              field(
                sandbox,
                api.betaAuth
                    ? 'Private invitation code'
                    : 'Local sandbox access key',
                secret: true,
              ),
              if (!api.betaAuth && challenge != null) ...[
                field(
                  code,
                  'Configured six-digit OTP',
                  keyboard: TextInputType.number,
                ),
                CheckboxListTile(
                  value: consent,
                  onChanged: (v) => setState(() => consent = v ?? false),
                  title: const Text(
                    'I accept the development privacy/terms notice. Use fixture data only.',
                  ),
                ),
              ],
              if (api.betaAuth)
                CheckboxListTile(
                  value: consent,
                  onChanged: (v) => setState(() => consent = v ?? false),
                  title: const Text(
                    'I understand this is a private beta and my phone number is not SMS verified.',
                  ),
                ),
              button(
                api.betaAuth
                    ? 'Join private beta'
                    : challenge == null
                    ? 'Request sandbox challenge'
                    : 'Sign in',
                login,
              ),
            ] else ...[
              SwitchListTile(
                title: const Text('മലയാളം / Malayalam headings'),
                subtitle: const Text('Full translation review is pending'),
                value: ml,
                onChanged: (v) => setState(() => ml = v),
              ),
              if (offline)
                const Card(
                  child: Padding(
                    padding: EdgeInsets.all(16),
                    child: Text(
                      'Offline · cached schedule only. GPS and availability are not live. Bookings require server confirmation.',
                    ),
                  ),
                ),
              if (widget.mode == 'passenger') ...[
                Text(
                  ml ? 'ബസ് കണ്ടെത്തുക' : 'Find your bus',
                  style: Theme.of(context).textTheme.headlineMedium,
                ),
                field(origin, 'Origin stop'),
                field(destination, 'Destination stop'),
                button('Search scheduled services', load),
                const Text(
                  'Browse without GPS permission. Times are scheduled; no live ETA is inferred.',
                ),
                button('Find share-auto services', () async {
                  final data = await api.request('/shared-trips') as List;
                  if (!context.mounted) {
                    return;
                  }
                  await Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => SharedList(api: api, trips: data),
                    ),
                  );
                }),
              ],
              if (widget.mode == 'bus') ...[
                Text(
                  ml ? 'ഇന്നത്തെ സർവീസുകൾ' : 'Assigned services',
                  style: Theme.of(context).textTheme.headlineMedium,
                ),
                const Text(
                  'Only use controls while safely stopped. A conductor may report incidents.',
                ),
                button('Refresh assigned services', load),
              ],
              if (widget.mode == 'driver') ...[
                Text(
                  'Your approved vehicles',
                  style: Theme.of(context).textTheme.headlineMedium,
                ),
                button('Go online', () async {
                  await api.request(
                    '/driver/availability',
                    method: 'POST',
                    data: {'online': true},
                  );
                }),
                button('Go offline', () async {
                  await api.request(
                    '/driver/availability',
                    method: 'POST',
                    data: {'online': false},
                  );
                }),
                button('Manage share-auto trips', () async {
                  await Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) =>
                          SharedDriverPage(api: api, vehicles: items),
                    ),
                  );
                }),
                const Text(
                  'Private offers and document onboarding UI are pending. Online status alone does not confirm any booking.',
                ),
              ],
              if (items.isEmpty && !busy)
                const Card(
                  child: Padding(
                    padding: EdgeInsets.all(24),
                    child: Text(
                      'No services or vehicles found. Check assignments, date and search stops.',
                    ),
                  ),
                ),
              for (final item in items)
                Card(
                  child: ListTile(
                    title: Text(
                      (item['route_name'] ?? item['registration'] ?? 'Service')
                          .toString(),
                    ),
                    subtitle: Text(
                      widget.mode == 'driver'
                          ? '${item['category']} · ${item['approved'] == true ? 'Approved' : 'Approval pending'}'
                          : '${item['status']} · ${item['departure_at']}\nGPS: ${offline ? 'CACHED' : item['locationQuality'] ?? 'Open service for freshness'}',
                    ),
                    isThreeLine: widget.mode != 'driver',
                    trailing: widget.mode == 'driver'
                        ? null
                        : const Icon(Icons.chevron_right),
                    onTap: widget.mode == 'driver'
                        ? null
                        : () => unawaited(
                            action(
                              () => selectTrip(
                                Map<String, dynamic>.from(item as Map),
                              ),
                            ),
                          ),
                  ),
                ),
              if (selected != null) ...[
                const Divider(),
                Text(
                  selected!['route_name']?.toString() ?? 'Service detail',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                Text(
                  'Status: ${selected!['status']} · v${selected!['version']}',
                ),
                Text(
                  'GPS: ${offline ? 'UNAVAILABLE OFFLINE' : selected!['locationQuality']} · Last reported: ${selected!['recorded_at'] ?? 'Never'}',
                ),
                if (!offline && selected!['lat'] != null)
                  Text(
                    'Reported coordinates: ${selected!['lat']}, ${selected!['lng']}',
                  ),
                Text(
                  'Reported delay: ${selected!['delay_minutes']} min · Arrival estimate unavailable',
                ),
                if (widget.mode == 'passenger')
                  button('Follow service alerts', () async {
                    await api.request(
                      '/bus/trips/${selected!['id']}/subscribe',
                      method: 'POST',
                    );
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text(
                            'Subscription saved. Push delivery requires provider setup.',
                          ),
                        ),
                      );
                    }
                  }),
                if (widget.mode == 'bus') ...[
                  field(reason, 'Incident reason (when safely stopped)'),
                  for (final status in [
                    'BOARDING',
                    'RUNNING',
                    'DELAYED',
                    'BREAKDOWN',
                    'CANCELLED',
                    'COMPLETED',
                  ])
                    button(
                      status == 'DELAYED'
                          ? 'Report 10 minute estimated delay'
                          : status,
                      () => updateStatus(status),
                    ),
                  button(
                    'Share foreground GPS for active service',
                    startTracking,
                  ),
                  button('Stop GPS sharing', () async {
                    await stopTracking();
                    setState(() {});
                  }),
                  const Text(
                    'Foreground tracking only. Background tracking and store permission review are not implemented.',
                  ),
                ],
              ],
            ],
          ],
        ),
      ),
    );
  }
}

class SharedList extends StatefulWidget {
  final Api api;
  final List<dynamic> trips;
  const SharedList({super.key, required this.api, required this.trips});
  @override
  State<SharedList> createState() => _SharedListState();
}

class _SharedListState extends State<SharedList> {
  String? message;
  bool busy = false;
  final Map<String, String> requestKeys = {};
  Future<void> reserve(Map trip) async {
    setState(() {
      busy = true;
      message = null;
    });
    try {
      final stops = trip['stops'] as List;
      final key = requestKeys.putIfAbsent(
        trip['id'].toString(),
        () => 'reserve-${DateTime.now().microsecondsSinceEpoch}',
      );
      final result = await widget.api.request(
        '/shared-trips/${trip['id']}/reservations',
        method: 'POST',
        headers: {'Idempotency-Key': key},
        data: {
          'seats': 1,
          'pickupSequence': stops.first['sequence'],
          'dropoffSequence': stops.last['sequence'],
        },
      );
      if (mounted) {
        setState(
          () =>
              message = 'Server confirmed reservation ${result['id']} · 1 seat',
        );
      }
    } catch (e) {
      if (mounted) setState(() => message = readableError(e));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Share-auto services')),
    body: ListView(
      padding: const EdgeInsets.all(20),
      children: [
        const Text(
          'One seat, first stop to final stop. Capacity is checked transactionally by the server. Fare per seat is set by the driver; approved fare policy review is pending.',
        ),
        if (message != null) Text(message!),
        if (widget.trips.isEmpty)
          const Text('No published share-auto services.'),
        for (final t in widget.trips)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${(t['stops'] as List).first['name']} → ${(t['stops'] as List).last['name']}',
                  ),
                  Text(
                    '${t['departure_at']} · ₹${(t['fare_paise'] as num) / 100} / seat · ${t['availableSeats']} seats across the full route (refresh at booking)',
                  ),
                  FilledButton(
                    onPressed: busy ? null : () => reserve(t as Map),
                    child: const Text(
                      'Request 1 seat — server confirmation required',
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    ),
  );
}

class SharedDriverPage extends StatefulWidget {
  final Api api;
  final List<dynamic> vehicles;
  const SharedDriverPage({
    super.key,
    required this.api,
    required this.vehicles,
  });
  @override
  State<SharedDriverPage> createState() => _SharedDriverPageState();
}

class _SharedDriverPageState extends State<SharedDriverPage> {
  final stops = TextEditingController(),
      capacity = TextEditingController(text: '3'),
      fare = TextEditingController();
  String? vehicle, error;
  bool busy = false;
  List<dynamic> trips = [];
  Timer? timer;
  DateTime departure = DateTime.now().add(const Duration(hours: 1));
  @override
  void initState() {
    super.initState();
    unawaited(run(load));
    timer = Timer.periodic(const Duration(seconds: 5), (_) {
      if (!busy) unawaited(run(load));
    });
  }

  @override
  void dispose() {
    timer?.cancel();
    for (final c in [stops, capacity, fare]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> run(Future<void> Function() task) async {
    if (busy) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await task();
    } catch (e) {
      if (mounted) setState(() => error = readableError(e));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> load() async {
    final data = await widget.api.request('/driver/shared-trips') as List;
    if (mounted) setState(() => trips = data);
  }

  Future<void> publish() async {
    if (vehicle == null) throw StateError('Select an approved auto');
    final count = int.tryParse(capacity.text), paise = int.tryParse(fare.text);
    if (count == null || count < 1 || paise == null || paise < 0) {
      throw StateError('Enter integer capacity and fare in paise');
    }
    final points = stops.text.split('\n').where((l) => l.trim().isNotEmpty).map(
      (line) {
        final parts = line.split(',');
        if (parts.length != 3) {
          throw StateError('Each stop requires name,latitude,longitude');
        }
        return {
          'name': parts[0].trim(),
          'lat': double.parse(parts[1]),
          'lng': double.parse(parts[2]),
        };
      },
    ).toList();
    await widget.api.request(
      '/shared-trips',
      method: 'POST',
      data: {
        'vehicleId': vehicle,
        'departureAt': departure.toUtc().toIso8601String(),
        'capacity': count,
        'farePaise': paise,
        'stops': points,
      },
    );
    await load();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Shared service published by the backend. No broadcast notification was sent.',
          ),
        ),
      );
    }
  }

  Future<void> state(Map trip, String status) async {
    await widget.api.request(
      '/shared-trips/${trip['id']}/status',
      method: 'POST',
      data: {'status': status},
    );
    await load();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Shared service management')),
    body: ListView(
      padding: const EdgeInsets.all(20),
      children: [
        const Text(
          'Manage services only while safely stopped. Use approved routes and fares. Digital payment and broadcast delivery are not enabled.',
        ),
        if (error != null)
          Text(
            error!,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        if (busy) const LinearProgressIndicator(),
        DropdownButtonFormField<String>(
          initialValue: vehicle,
          decoration: const InputDecoration(labelText: 'Approved auto'),
          items: [
            for (final v in widget.vehicles)
              if (v['category'] == 'AUTO' && v['approved'] == true)
                DropdownMenuItem(
                  value: v['id'].toString(),
                  child: Text(v['registration'].toString()),
                ),
          ],
          onChanged: (value) => setState(() => vehicle = value),
        ),
        TextField(
          controller: stops,
          minLines: 3,
          maxLines: 8,
          decoration: const InputDecoration(
            labelText: 'Ordered stops: name,latitude,longitude (one per line)',
          ),
        ),
        TextField(
          controller: capacity,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(labelText: 'Seat capacity'),
        ),
        TextField(
          controller: fare,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(
            labelText: 'Fare per seat, integer paise (₹1 = 100)',
          ),
        ),
        ListTile(
          title: const Text('Departure (device local time)'),
          subtitle: Text(departure.toString()),
          trailing: const Icon(Icons.schedule),
          onTap: () async {
            final day = await showDatePicker(
              context: context,
              initialDate: departure,
              firstDate: DateTime.now(),
              lastDate: DateTime.now().add(const Duration(days: 30)),
            );
            if (day == null || !context.mounted) return;
            final time = await showTimePicker(
              context: context,
              initialTime: TimeOfDay.fromDateTime(departure),
            );
            if (time != null && mounted) {
              setState(
                () => departure = DateTime(
                  day.year,
                  day.month,
                  day.day,
                  time.hour,
                  time.minute,
                ),
              );
            }
          },
        ),
        FilledButton(
          onPressed: busy ? null : () => unawaited(run(publish)),
          child: const Text('Publish shared service'),
        ),
        const Divider(),
        Text('Your services', style: Theme.of(context).textTheme.titleLarge),
        if (trips.isEmpty) const Text('No shared services published.'),
        for (final trip in trips)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${(trip['stops'] as List).first['name']} → ${(trip['stops'] as List).last['name']}',
                  ),
                  Text('${trip['status']} · ${trip['departure_at']}'),
                  Wrap(
                    spacing: 8,
                    children: [
                      for (final status in [
                        'BOARDING',
                        'IN_PROGRESS',
                        'COMPLETED',
                        'CANCELLED',
                      ])
                        OutlinedButton(
                          onPressed: busy
                              ? null
                              : () => unawaited(
                                  run(() => state(trip as Map, status)),
                                ),
                          child: Text(status),
                        ),
                    ],
                  ),
                  for (final r in trip['reservations'] as List)
                    ListTile(
                      title: Text(
                        '${r['passenger_name']} · ${r['seats']} seat(s)',
                      ),
                      subtitle: Text(
                        '${r['status']} · stop ${r['pickup_sequence']} → ${r['dropoff_sequence']}',
                      ),
                      trailing: r['status'] == 'CONFIRMED'
                          ? PopupMenuButton<String>(
                              onSelected: (status) => unawaited(
                                run(() async {
                                  await widget.api.request(
                                    '/reservations/${r['id']}/boarding',
                                    method: 'POST',
                                    data: {'status': status},
                                  );
                                  await load();
                                }),
                              ),
                              itemBuilder: (_) => const [
                                PopupMenuItem(
                                  value: 'BOARDED',
                                  child: Text('Confirm boarding'),
                                ),
                                PopupMenuItem(
                                  value: 'NO_SHOW',
                                  child: Text('Mark no-show after departure'),
                                ),
                              ],
                            )
                          : null,
                    ),
                ],
              ),
            ),
          ),
      ],
    ),
  );
}
