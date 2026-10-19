import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'live_socket.dart';
import 'api.dart';

const forest = Color(0xFF14634D);

class PassengerScreen extends StatefulWidget {
  final Api api;
  final VoidCallback onConnectionSettings;
  const PassengerScreen({
    super.key,
    required this.api,
    required this.onConnectionSettings,
  });
  @override
  State<PassengerScreen> createState() => _PassengerScreenState();
}

class _PassengerScreenState extends State<PassengerScreen> {
  final origin = TextEditingController(),
      destination = TextEditingController(),
      phone = TextEditingController(),
      key = TextEditingController(),
      otp = TextEditingController();
  int tab = 0, transport = 0;
  bool busy = false, offline = false, consent = false;
  String? error, challenge;
  String name = '';
  List<dynamic> buses = [], shared = [], history = [], reservations = [];
  DateTime? synced;
  Timer? poll;
  Set<String> favorites = {};
  final Map<String, String> reservationKeys = {};
  Api get api => widget.api;
  bool get browsing => api.isDemo || api.access != null;
  @override
  void initState() {
    super.initState();
    if (browsing) {
      unawaited(run(load));
    }
    poll = Timer.periodic(const Duration(seconds: 10), (_) {
      if (browsing && !busy && !api.isDemo) {
        unawaited(run(load, showBusy: false));
      }
    });
  }

  @override
  void dispose() {
    poll?.cancel();
    for (final c in [origin, destination, phone, key, otp]) {
      c.dispose();
    }
    super.dispose();
  }

  String get today {
    final n = DateTime.now().toUtc().add(const Duration(hours: 5, minutes: 30));
    return '${n.year}-${n.month.toString().padLeft(2, '0')}-${n.day.toString().padLeft(2, '0')}';
  }

  Future<void> run(Future<void> Function() work, {bool showBusy = true}) async {
    if (busy) return;
    if (showBusy) setState(() => busy = true);
    setState(() => error = null);
    try {
      await work();
    } catch (e) {
      if (mounted) setState(() => error = readableError(e));
    } finally {
      if (mounted && showBusy) setState(() => busy = false);
    }
  }

  Future<void> load() async {
    if (!browsing) return;
    try {
      final search =
          origin.text.trim().isNotEmpty && destination.text.trim().isNotEmpty
          ? '&origin=${Uri.encodeComponent(origin.text.trim())}&destination=${Uri.encodeComponent(destination.text.trim())}'
          : '';
      final data = await api.request('/bus/trips?date=$today$search') as List;
      final services = await api.request('/shared-trips') as List;
      final profile = await api.request('/me') as Map;
      final prefs = await SharedPreferences.getInstance();
      if (!mounted) return;
      setState(() {
        buses = data;
        shared = services;
        name = profile['name']?.toString() ?? '';
        synced = DateTime.now();
        offline = false;
        favorites =
            (prefs.getStringList('favorites:${api.dio.options.baseUrl}') ?? [])
                .toSet();
      });
      if (!api.isDemo) {
        await prefs.setString(
          'passenger_schedule:${api.dio.options.baseUrl}',
          jsonEncode({
            'date': today,
            'items': data
                .map(
                  (t) => {
                    ...Map<String, dynamic>.from(t as Map),
                    'lat': null,
                    'lng': null,
                    'locationQuality': 'CACHED_SCHEDULE',
                  },
                )
                .toList(),
          }),
        );
      }
      if (tab == 1) await loadHistory();
    } catch (e) {
      if (mounted) setState(() => offline = true);
      if (!api.isDemo) {
        final prefs = await SharedPreferences.getInstance();
        final raw = prefs.getString(
          'passenger_schedule:${api.dio.options.baseUrl}',
        );
        if (raw != null) {
          final cache = jsonDecode(raw) as Map;
          if (cache['date'] == today && mounted) {
            setState(() => buses = cache['items'] as List);
          }
        }
      }
      rethrow;
    }
  }

  Future<void> loadHistory() async {
    final b = await api.request('/bookings') as List;
    final r = await api.request('/me/reservations') as List;
    if (mounted) {
      setState(() {
        history = b;
        reservations = r;
      });
    }
  }

  Future<void> auth() async {
    if (api.betaAuth) {
      await api.redeemInvite(phone.text, key.text, consent);
      key.clear();
      await load();
      return;
    }
    if (challenge == null) {
      var number = phone.text.trim();
      if (RegExp(r'^[6-9][0-9]{9}$').hasMatch(number)) number = '+91$number';
      if (!RegExp(r'^\+91[6-9][0-9]{9}$').hasMatch(number)) {
        throw const FormatException('Enter a valid Indian mobile number.');
      }
      final r = await api.request(
        '/auth/otp/request',
        method: 'POST',
        data: {'phone': number},
        headers: {'X-Sandbox-Key': key.text},
      );
      if (mounted) setState(() => challenge = r['challengeId'] as String);
    } else {
      if (!consent) {
        throw StateError('Accept the test privacy notice to continue.');
      }
      if (!RegExp(r'^[0-9]{6}$').hasMatch(otp.text)) {
        throw const FormatException('Enter the six-digit test code.');
      }
      final r = await api.request(
        '/auth/otp/verify',
        method: 'POST',
        data: {
          'challengeId': challenge,
          'code': otp.text,
          'consentVersion': 'development-v1',
        },
      );
      await api.save(Map<String, dynamic>.from(r as Map));
      key.clear();
      otp.clear();
      await load();
    }
  }

  Future<void> favorite(Map t) async {
    final id = t['id'].toString();
    setState(
      () => favorites.contains(id) ? favorites.remove(id) : favorites.add(id),
    );
    final p = await SharedPreferences.getInstance();
    await p.setStringList(
      'favorites:${api.dio.options.baseUrl}',
      favorites.toList(),
    );
  }

  void message(String text) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  Future<void> reserve(Map t) async {
    if (api.isDemo) {
      message('Connect to your test server to reserve real seats.');
      return;
    }
    final stops = t['stops'] as List;
    if (stops.length < 2) {
      throw StateError('This service has no valid pickup and drop-off stops.');
    }
    int seats = 1;
    final available = (t['availableSeats'] as num?)?.toInt() ?? 0;
    final confirmed = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => StatefulBuilder(
        builder: (context, update) => Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Reserve your seats',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 12),
              Text('${stops.first['name']} → ${stops.last['name']}'),
              Text(
                '₹${((t['fare_paise'] as num) * seats / 100).toStringAsFixed(2)} · ${timeText(t['departure_at'])} departure',
              ),
              const SizedBox(height: 20),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('Passengers'),
                  Row(
                    children: [
                      IconButton(
                        onPressed: seats > 1
                            ? () => update(() => seats--)
                            : null,
                        icon: const Icon(Icons.remove_circle_outline),
                      ),
                      Text('$seats'),
                      IconButton(
                        onPressed: seats < available
                            ? () => update(() => seats++)
                            : null,
                        icon: const Icon(Icons.add_circle_outline),
                      ),
                    ],
                  ),
                ],
              ),
              const Text(
                'Seats are confirmed only after the server checks current capacity.',
              ),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: available > 0
                    ? () => Navigator.pop(context, true)
                    : null,
                child: const Text('Request seats'),
              ),
            ],
          ),
        ),
      ),
    );
    if (confirmed != true) return;
    final requestKey = reservationKeys.putIfAbsent(
      '${t['id']}:$seats',
      () => 'seat-${DateTime.now().microsecondsSinceEpoch}',
    );
    final r = await api.request(
      '/shared-trips/${t['id']}/reservations',
      method: 'POST',
      headers: {'Idempotency-Key': requestKey},
      data: {
        'seats': seats,
        'pickupSequence': stops.first['sequence'],
        'dropoffSequence': stops.last['sequence'],
      },
    );
    if (!mounted) return;
    message('Server confirmed reservation ${r['id']}');
    await load();
  }

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final palette = ColorScheme.fromSeed(
      seedColor: forest,
      brightness: dark ? Brightness.dark : Brightness.light,
    );
    final bg = dark ? const Color(0xFF101E19) : const Color(0xFFF5F7F2);
    return Theme(
      data: ThemeData(
        useMaterial3: true,
        colorScheme: palette,
        scaffoldBackgroundColor: bg,
        appBarTheme: AppBarTheme(
          backgroundColor: bg,
          surfaceTintColor: Colors.transparent,
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: palette.surface,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide(color: palette.outlineVariant),
          ),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 15,
          ),
        ),
        filledButtonTheme: FilledButtonThemeData(
          style: FilledButton.styleFrom(
            backgroundColor: forest,
            foregroundColor: Colors.white,
            minimumSize: const Size.fromHeight(52),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
          ),
        ),
      ),
      child: Builder(
        builder: (context) {
          if (!browsing) return login(context);
          return Scaffold(
            appBar: AppBar(
              title: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: forest,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(
                      Icons.route_rounded,
                      color: Colors.white,
                      size: 24,
                    ),
                  ),
                  const SizedBox(width: 10),
                  const Text(
                    'RuralConnect',
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 22,
                      letterSpacing: -.8,
                    ),
                  ),
                ],
              ),
              actions: [
                IconButton(
                  tooltip: 'Server connection settings',
                  onPressed: widget.onConnectionSettings,
                  icon: const Icon(Icons.settings_ethernet_rounded),
                ),
                const SizedBox(width: 8),
              ],
            ),
            body: SafeArea(
              bottom: false,
              child: RefreshIndicator(
                onRefresh: () => run(load),
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(20, 6, 20, 24),
                  children: [
                    if (api.isDemo)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 10,
                        ),
                        decoration: BoxDecoration(
                          color: palette.secondaryContainer,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.science_outlined, size: 18),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'UI DEMO · Sample schedules only',
                                style: TextStyle(
                                  color: palette.onSecondaryContainer,
                                  fontWeight: FontWeight.w600,
                                  fontSize: 12,
                                ),
                              ),
                            ),
                            TextButton(
                              onPressed: widget.onConnectionSettings,
                              child: const Text('Connect'),
                            ),
                          ],
                        ),
                      ),
                    if (offline)
                      Container(
                        margin: const EdgeInsets.only(top: 10),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: palette.errorContainer,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Text(
                          'Offline · Cached schedules only. Bookings require a server connection.',
                        ),
                      ),
                    if (error != null)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        child: Text(
                          error!,
                          style: TextStyle(color: palette.error),
                          semanticsLabel: 'Error: $error',
                        ),
                      ),
                    if (busy)
                      const Padding(
                        padding: EdgeInsets.only(top: 8),
                        child: LinearProgressIndicator(),
                      ),
                    if (tab == 0) ...home(context),
                    if (tab == 1) ...trips(context),
                    if (tab == 2) ...account(context),
                  ],
                ),
              ),
            ),
            bottomNavigationBar: NavigationBar(
              selectedIndex: tab,
              onDestinationSelected: (value) {
                setState(() => tab = value);
                if (value == 1) unawaited(run(loadHistory));
              },
              backgroundColor: palette.surface,
              indicatorColor: palette.primaryContainer,
              destinations: const [
                NavigationDestination(
                  icon: Icon(Icons.explore_outlined),
                  selectedIcon: Icon(Icons.explore),
                  label: 'Explore',
                ),
                NavigationDestination(
                  icon: Icon(Icons.confirmation_number_outlined),
                  selectedIcon: Icon(Icons.confirmation_number),
                  label: 'My trips',
                ),
                NavigationDestination(
                  icon: Icon(Icons.person_outline),
                  selectedIcon: Icon(Icons.person),
                  label: 'Account',
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget login(BuildContext context) => Scaffold(
    appBar: AppBar(
      actions: [
        TextButton.icon(
          onPressed: widget.onConnectionSettings,
          icon: const Icon(Icons.dns_outlined),
          label: const Text('Server settings'),
        ),
      ],
    ),
    body: SafeArea(
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 460),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Icon(Icons.route_rounded, color: forest, size: 64),
                const SizedBox(height: 20),
                const Text(
                  'Your journey,\nconnected.',
                  style: TextStyle(
                    fontSize: 38,
                    height: 1.08,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -1.5,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  'Buses, shared autos and better connections across Kerala.',
                  style: Theme.of(context).textTheme.bodyLarge,
                ),
                const SizedBox(height: 24),
                Text(
                  api.betaAuth
                      ? 'Private beta · invitation only · no SMS required'
                      : 'Development sandbox · no SMS sent',
                ),
                TextField(
                  controller: phone,
                  keyboardType: TextInputType.phone,
                  decoration: const InputDecoration(
                    labelText: 'Phone number (+91)',
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: key,
                  obscureText: true,
                  decoration: InputDecoration(
                    labelText: api.betaAuth
                        ? 'Private invitation code'
                        : 'Local sandbox access key',
                  ),
                ),
                if (!api.betaAuth && challenge != null) ...[
                  const SizedBox(height: 12),
                  TextField(
                    controller: otp,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Configured six-digit OTP',
                    ),
                  ),
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    value: consent,
                    onChanged: (v) => setState(() => consent = v ?? false),
                    title: const Text(
                      'I accept the development privacy/terms notice. Use fixture data only.',
                    ),
                  ),
                ],
                if (api.betaAuth)
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    value: consent,
                    onChanged: (v) => setState(() => consent = v ?? false),
                    title: const Text(
                      'I understand this is a private beta and my phone number is not SMS verified.',
                    ),
                  ),
                if (error != null)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    child: Text(
                      error!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: busy ? null : () => run(auth),
                  child: Text(
                    busy
                        ? 'Connecting…'
                        : api.betaAuth
                        ? 'Join private beta'
                        : challenge == null
                        ? 'Request sandbox challenge'
                        : 'Sign in',
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
  List<Widget> home(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return [
      const SizedBox(height: 24),
      Row(
        children: [
          Icon(Icons.location_on_outlined, color: colors.primary, size: 18),
          const SizedBox(width: 5),
          Text(
            'KERALA  /  MANUAL STOP SEARCH',
            style: TextStyle(
              color: colors.onSurfaceVariant,
              fontSize: 11,
              fontWeight: FontWeight.w600,
              letterSpacing: 1,
            ),
          ),
        ],
      ),
      const SizedBox(height: 12),
      Text(
        name.isEmpty
            ? 'Your next stop,\ncloser to home.'
            : 'Hi, ${name.split(' ').first}.\nWhere to today?',
        style: TextStyle(
          fontSize: 32,
          height: 1.13,
          fontWeight: FontWeight.w800,
          letterSpacing: -1,
          color: colors.onSurface,
        ),
      ),
      const SizedBox(height: 18),
      Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: colors.surface,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(
            color: colors.outlineVariant.withValues(alpha: .55),
          ),
        ),
        child: Column(
          children: [
            TextField(
              controller: origin,
              decoration: const InputDecoration(
                labelText: 'From',
                hintText: 'Your pickup stop',
                prefixIcon: Icon(Icons.trip_origin_rounded),
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: destination,
              decoration: InputDecoration(
                labelText: 'To',
                hintText: 'Where are you going?',
                prefixIcon: const Icon(Icons.location_on_outlined),
                suffixIcon: IconButton(
                  tooltip: 'Swap stops',
                  onPressed: () {
                    final a = origin.text;
                    origin.text = destination.text;
                    destination.text = a;
                  },
                  icon: const Icon(Icons.swap_vert_rounded),
                ),
              ),
            ),
            const SizedBox(height: 14),
            FilledButton.icon(
              onPressed: busy
                  ? null
                  : () => run(() async {
                      if (origin.text.trim().isEmpty !=
                          destination.text.trim().isEmpty) {
                        throw StateError(
                          'Enter both origin and destination, or leave both empty.',
                        );
                      }
                      await load();
                    }),
              icon: const Icon(Icons.search_rounded),
              label: const Text(
                'Find a bus',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
          ],
        ),
      ),
      const SizedBox(height: 20),
      Row(
        children: [
          Expanded(
            child: modeTile(context, Icons.directions_bus_rounded, 'Bus', 0),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: modeTile(
              context,
              Icons.airport_shuttle_outlined,
              'Share auto',
              1,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: OutlinedButton(
              onPressed: () => message(
                'Private auto and taxi rides are not available in this test build.',
              ),
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
              child: const Column(
                children: [
                  Icon(Icons.local_taxi_outlined),
                  SizedBox(height: 5),
                  Text('Taxi / auto', style: TextStyle(fontSize: 12)),
                ],
              ),
            ),
          ),
        ],
      ),
      const SizedBox(height: 24),
      Wrap(
        alignment: WrapAlignment.spaceBetween,
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 12,
        runSpacing: 6,
        children: [
          Text(
            transport == 0 ? 'Bus services' : 'Share-auto departures',
            style: const TextStyle(
              fontWeight: FontWeight.w800,
              fontSize: 20,
              letterSpacing: -.4,
            ),
          ),
          Text(
            api.isDemo
                ? 'SAMPLE TIMETABLE'
                : synced == null
                ? ''
                : 'Synced ${timeText(synced!.toIso8601String())}',
            style: TextStyle(
              color: colors.onSurfaceVariant,
              fontSize: 10,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
      const SizedBox(height: 5),
      Text(
        transport == 0
            ? 'Scheduled times. Live GPS appears only when available.'
            : 'Available seats are checked again when you reserve.',
        style: TextStyle(fontSize: 12, color: colors.onSurfaceVariant),
      ),
      const SizedBox(height: 12),
      if (transport == 0 && buses.isEmpty)
        empty(
          context,
          'No matching bus services',
          'Try different stops or ask your operator to publish today’s service.',
        ),
      if (transport == 0)
        for (final t in buses) busCard(context, t as Map),
      if (transport == 1 && shared.isEmpty)
        empty(
          context,
          'No shared autos announced',
          'Published driver services appear here. Demo mode does not invent availability.',
        ),
      if (transport == 1)
        for (final t in shared) sharedCard(context, t as Map),
      const SizedBox(height: 16),
      Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: colors.primaryContainer.withValues(alpha: .5),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.location_off_outlined, color: colors.primary),
            const SizedBox(width: 12),
            const Expanded(
              child: Text(
                'Browse without GPS permission. Choose your stops manually and keep location sharing in your control.',
                style: TextStyle(fontSize: 12, height: 1.5),
              ),
            ),
          ],
        ),
      ),
    ];
  }

  Widget modeTile(
    BuildContext context,
    IconData icon,
    String label,
    int value,
  ) {
    final c = Theme.of(context).colorScheme;
    final selected = transport == value;
    return InkWell(
      onTap: () => setState(() => transport = value),
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          color: selected ? forest : c.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: selected ? forest : c.outlineVariant),
        ),
        child: Column(
          children: [
            Icon(icon, color: selected ? Colors.white : c.onSurface),
            const SizedBox(height: 7),
            Text(
              label,
              style: TextStyle(
                color: selected ? Colors.white : c.onSurface,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget busCard(BuildContext context, Map t) {
    final c = Theme.of(context).colorScheme;
    final route = t['route_name']
        .toString()
        .replaceFirst('DEMO · ', '')
        .replaceAll('→', 'to');
    final live = !offline && t['locationQuality'] == 'LIVE';
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: c.outlineVariant.withValues(alpha: .6)),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) =>
                BusDetail(api: api, initial: Map<String, dynamic>.from(t)),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 12, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(9),
                    decoration: BoxDecoration(
                      color: c.primaryContainer,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(
                      Icons.directions_bus_outlined,
                      color: c.primary,
                      size: 22,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          t['registration']?.toString() ?? 'Bus service',
                          style: TextStyle(
                            fontSize: 11,
                            color: c.onSurfaceVariant,
                          ),
                        ),
                        Text(
                          route,
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: 'Save route',
                    onPressed: () => favorite(t),
                    icon: Icon(
                      favorites.contains(t['id'])
                          ? Icons.bookmark
                          : Icons.bookmark_border,
                      color: c.primary,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Text(
                    timeText(t['departure_at']),
                    style: const TextStyle(
                      fontSize: 23,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -.5,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      t['status'] == 'CANCELLED'
                          ? 'Cancelled'
                          : live
                          ? 'Live location available'
                          : offline
                          ? 'Cached schedule'
                          : 'Scheduled departure',
                      style: TextStyle(
                        color: t['status'] == 'CANCELLED'
                            ? c.error
                            : c.onSurfaceVariant,
                        fontSize: 11,
                      ),
                    ),
                  ),
                  const Icon(Icons.arrow_forward_rounded, size: 19),
                ],
              ),
              if ((t['delay_minutes'] as num? ?? 0) > 0)
                Text(
                  'Reported delay: ${t['delay_minutes']} min',
                  style: TextStyle(color: c.error, fontSize: 12),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget sharedCard(BuildContext context, Map t) {
    final stops = t['stops'] as List;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              '${stops.first['name']} → ${stops.last['name']}',
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            Text(
              '${timeText(t['departure_at'])} · ${t['availableSeats']} seats available · ₹${((t['fare_paise'] as num) / 100).toStringAsFixed(2)} / seat',
            ),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: busy || offline ? null : () => run(() => reserve(t)),
              child: const Text('Choose seats'),
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> trips(BuildContext context) => [
    const SizedBox(height: 24),
    const Text(
      'Your journeys',
      style: TextStyle(fontSize: 30, fontWeight: FontWeight.w800),
    ),
    const SizedBox(height: 12),
    if (api.isDemo)
      empty(
        context,
        'No demo bookings',
        'This preview never fabricates reservations or payments. Connect to your server to make a real test booking.',
      ),
    if (!api.isDemo && history.isEmpty && reservations.isEmpty)
      empty(
        context,
        'No trips yet',
        'Confirmed server bookings and shared-auto reservations will appear here.',
      ),
    for (final r in reservations)
      Card(
        child: ListTile(
          leading: const Icon(Icons.airport_shuttle_outlined),
          title: Text('${r['pickup_name']} → ${r['dropoff_name']}'),
          subtitle: Text('${r['status']} · ${r['seats']} seat(s)'),
          trailing: r['status'] == 'CONFIRMED'
              ? TextButton(
                  onPressed: busy
                      ? null
                      : () => run(() async {
                          await api.request(
                            '/reservations/${r['id']}',
                            method: 'DELETE',
                          );
                          await loadHistory();
                        }),
                  child: const Text('Cancel'),
                )
              : null,
        ),
      ),
    for (final b in history)
      Card(
        child: ListTile(
          leading: const Icon(Icons.local_taxi_outlined),
          title: Text('Ride ${b['id'].toString().substring(0, 8)}'),
          subtitle: Text(
            '${b['status']} · ₹${((b['fare_paise'] as num) / 100).toStringAsFixed(2)}',
          ),
          trailing: ['REQUESTED', 'ACCEPTED', 'ARRIVED'].contains(b['status'])
              ? TextButton(
                  onPressed: busy
                      ? null
                      : () => run(() async {
                          await api.request(
                            '/bookings/${b['id']}/status',
                            method: 'POST',
                            data: {
                              'status': 'CANCELLED',
                              'version': b['version'],
                            },
                          );
                          await loadHistory();
                        }),
                  child: const Text('Cancel'),
                )
              : null,
        ),
      ),
  ];
  List<Widget> account(BuildContext context) => [
    const SizedBox(height: 24),
    const Text(
      'Your account',
      style: TextStyle(fontSize: 30, fontWeight: FontWeight.w800),
    ),
    const SizedBox(height: 16),
    if (api.isDemo)
      empty(
        context,
        'You’re exploring a demo',
        'No passenger account or booking has been created.',
      ),
    if (!api.isDemo) ...[
      Text(
        name.isEmpty ? 'Passenger' : name,
        style: Theme.of(context).textTheme.headlineSmall,
      ),
      const SizedBox(height: 16),
      OutlinedButton.icon(
        onPressed: () => editProfile(context),
        icon: const Icon(Icons.edit_outlined),
        label: const Text('Edit profile'),
      ),
      const SizedBox(height: 8),
      OutlinedButton(
        onPressed: () => run(() async {
          await api.request(
            '/me/data-requests',
            method: 'POST',
            data: {'kind': 'EXPORT'},
          );
          if (mounted) message('Export request saved. Processing is pending.');
        }),
        child: const Text('Request my data export'),
      ),
      const SizedBox(height: 8),
      OutlinedButton(
        onPressed: () => requestDeletion(context),
        child: const Text('Request account deletion'),
      ),
      const SizedBox(height: 8),
      TextButton.icon(
        onPressed: () => run(() async {
          try {
            await api.logout();
          } finally {
            if (mounted) {
              setState(() {
                buses = [];
                history = [];
                reservations = [];
                challenge = null;
              });
            }
          }
        }),
        icon: const Icon(Icons.logout),
        label: const Text('Sign out'),
      ),
    ],
    const SizedBox(height: 20),
    OutlinedButton.icon(
      onPressed: widget.onConnectionSettings,
      icon: const Icon(Icons.dns_outlined),
      label: Text(api.isDemo ? 'Connect to a test server' : 'Change server'),
    ),
    const SizedBox(height: 16),
    Text(
      'RuralConnect · Android testing\n${api.isDemo ? 'Offline UI demo' : api.dio.options.baseUrl}',
      style: Theme.of(context).textTheme.bodySmall,
    ),
  ];
  Future<void> editProfile(BuildContext context) async {
    var editedName = name;
    String language = 'en';
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Edit profile'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextFormField(
              initialValue: editedName,
              onChanged: (value) => editedName = value,
              decoration: const InputDecoration(labelText: 'Your name'),
            ),
            DropdownButtonFormField<String>(
              initialValue: language,
              items: const [
                DropdownMenuItem(value: 'en', child: Text('English')),
                DropdownMenuItem(value: 'ml', child: Text('മലയാളം')),
              ],
              onChanged: (v) => language = v ?? 'en',
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (ok == true) {
      await run(() async {
        await api.request(
          '/me',
          method: 'PATCH',
          data: {'name': editedName.trim(), 'language': language},
        );
        await load();
      });
    }
  }

  Future<void> requestDeletion(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Request account deletion?'),
        content: const Text(
          'This submits a request for review. Your data is not deleted immediately.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Keep account'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Submit request'),
          ),
        ],
      ),
    );
    if (ok == true) {
      await run(() async {
        await api.request(
          '/me/data-requests',
          method: 'POST',
          data: {'kind': 'DELETE'},
        );
        if (mounted) message('Deletion request saved. Review is pending.');
      });
    }
  }
}

String timeText(dynamic value) {
  final d = DateTime.tryParse(value?.toString() ?? '')?.toLocal();
  if (d == null) return 'Time unavailable';
  final h = d.hour % 12 == 0 ? 12 : d.hour % 12;
  return '$h:${d.minute.toString().padLeft(2, '0')} ${d.hour < 12 ? 'AM' : 'PM'}';
}

Widget empty(BuildContext context, String title, String body) => Container(
  margin: const EdgeInsets.symmetric(vertical: 12),
  padding: const EdgeInsets.all(24),
  decoration: BoxDecoration(
    color: Theme.of(context).colorScheme.surface,
    borderRadius: BorderRadius.circular(20),
  ),
  child: Column(
    children: [
      Icon(
        Icons.route_outlined,
        size: 36,
        color: Theme.of(context).colorScheme.primary,
      ),
      const SizedBox(height: 12),
      Text(
        title,
        style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 17),
        textAlign: TextAlign.center,
      ),
      const SizedBox(height: 8),
      Text(
        body,
        textAlign: TextAlign.center,
        style: Theme.of(context).textTheme.bodySmall,
      ),
    ],
  ),
);

class BusDetail extends StatefulWidget {
  final Api api;
  final Map<String, dynamic> initial;
  const BusDetail({super.key, required this.api, required this.initial});
  @override
  State<BusDetail> createState() => _BusDetailState();
}

class _BusDetailState extends State<BusDetail> {
  late Map<String, dynamic> trip = {...widget.initial};
  Timer? timer, retry;
  WebSocketChannel? socket;
  StreamSubscription<dynamic>? subscription;
  String cursor = '0';
  String? error;
  bool refreshing = false;
  int attempts = 0;
  @override
  void initState() {
    super.initState();
    if (!widget.api.isDemo) {
      unawaited(refresh());
      timer = Timer.periodic(
        const Duration(seconds: 5),
        (_) => unawaited(refresh()),
      );
      connect();
    }
  }

  Future<void> refresh() async {
    if (refreshing) return;
    refreshing = true;
    try {
      final t = await widget.api.request('/bus/trips/${trip['id']}') as Map;
      if (mounted) {
        setState(() {
          trip = {...trip, ...Map<String, dynamic>.from(t)};
          error = null;
        });
      }
    } catch (e) {
      if (mounted) setState(() => error = readableError(e));
    } finally {
      refreshing = false;
    }
  }

  void connect() {
    if (!mounted || widget.api.access == null) return;
    final url = Uri.parse(
      '${widget.api.dio.options.baseUrl.replaceFirst(RegExp(r'^http'), 'ws')}/live',
    ).replace(queryParameters: {'tripId': trip['id'].toString(), 'after': cursor});
    socket = connectLiveSocket(url, widget.api.access!);
    if (socket == null) return;
    subscription = socket!.stream.listen(
      (raw) {
        try {
          final e = jsonDecode(raw as String) as Map;
          final next = e['id'].toString();
          if (BigInt.parse(next) > BigInt.parse(cursor)) {
            cursor = next;
            attempts = 0;
            unawaited(refresh());
          }
        } catch (_) {
          unawaited(refresh());
        }
      },
      onError: (Object e) {
        if (mounted) {
          setState(
            () => error =
                'Live connection interrupted. Refetching service status.',
          );
        }
      },
      onDone: () {
        if (!mounted) return;
        retry = Timer(
          Duration(seconds: 1 << attempts.clamp(0, 5).toInt()),
          connect,
        );
        attempts++;
      },
    );
  }

  @override
  void dispose() {
    timer?.cancel();
    retry?.cancel();
    unawaited(subscription?.cancel());
    unawaited(socket?.sink.close());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).colorScheme;
    final stops = trip['stops'] as List? ?? [];
    return Scaffold(
      appBar: AppBar(title: const Text('Bus service')),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          if (widget.api.isDemo)
            const Text(
              'UI DEMO · Sample timetable. No real vehicle tracking.',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
          const SizedBox(height: 16),
          Text(
            trip['route_name'].toString(),
            style: Theme.of(context).textTheme.headlineMedium,
          ),
          const SizedBox(height: 12),
          Text(trip['registration']?.toString() ?? 'Bus service'),
          const SizedBox(height: 16),
          Chip(label: Text(trip['status'].toString())),
          Text('Scheduled departure: ${timeText(trip['departure_at'])}'),
          Text('Reported delay: ${trip['delay_minutes']} min'),
          const SizedBox(height: 20),
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: c.primaryContainer,
              borderRadius: BorderRadius.circular(18),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'GPS: ${error != null ? 'UNAVAILABLE' : trip['locationQuality']}',
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                Text(
                  'Last reported: ${trip['recorded_at'] ?? 'No position received'}',
                ),
                if (error == null &&
                    trip['locationQuality'] == 'LIVE' &&
                    trip['lat'] != null)
                  Text('${trip['lat']}, ${trip['lng']}'),
                const Text(
                  'Arrival estimate unavailable. Scheduled information is shown separately.',
                ),
              ],
            ),
          ),
          if (error != null) Text(error!, style: TextStyle(color: c.error)),
          const SizedBox(height: 24),
          const Text(
            'Stops on this route',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
          ),
          for (final s in stops)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: CircleAvatar(
                radius: 16,
                child: Text(
                  '${(s['sequence'] as num) + 1}',
                  style: const TextStyle(fontSize: 12),
                ),
              ),
              title: Text(s['name'].toString()),
              subtitle: Text(
                '${s['offsetMinutes']} minutes from origin · scheduled',
              ),
            ),
          const SizedBox(height: 20),
          FilledButton.icon(
            onPressed: () => follow(context),
            icon: const Icon(Icons.notifications_active_outlined),
            label: const Text('Follow service alerts'),
          ),
        ],
      ),
    );
  }

  Future<void> follow(BuildContext context) async {
    if (widget.api.isDemo) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Connect to your server to follow a real service.'),
        ),
      );
      return;
    }
    try {
      await widget.api.request(
        '/bus/trips/${trip['id']}/subscribe',
        method: 'POST',
      );
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Subscription saved. External push delivery is not configured.',
            ),
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(readableError(e))));
      }
    }
  }
}
