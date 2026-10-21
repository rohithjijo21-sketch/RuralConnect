import 'dart:async';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'api.dart';
import 'journey_map.dart';
import 'design.dart';

String rideMoney(dynamic value) =>
    '₹${((value as num? ?? 0) / 100).toStringAsFixed(2)}';
bool activeRide(Map b) => !['CANCELLED', 'COMPLETED'].contains(b['status']);

class PrivateRidesScreen extends StatefulWidget {
  final Api api;
  final bool driver;
  final List vehicles;
  const PrivateRidesScreen({
    super.key,
    required this.api,
    this.driver = false,
    this.vehicles = const [],
  });
  @override
  State<PrivateRidesScreen> createState() => _PrivateRidesState();
}

class _PrivateRidesState extends State<PrivateRidesScreen>
    with WidgetsBindingObserver {
  final pickupName = TextEditingController(),
      destinationName = TextEditingController();
  LatLng? pickup, destination;
  String category = 'AUTO';
  String? error, requestKey;
  Map? quote, ride;
  List rides = [], offers = [];
  bool appActive = true, locatingHeartbeat = false;
  int locationGeneration = 0;
  bool busy = false,
      fetching = false,
      tracking = false,
      sendingLocation = false;
  Timer? timer;
  DateTime? lastSent;
  StreamSubscription<Position>? locations;
  Api get api => widget.api;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(run(load));
    timer = Timer.periodic(const Duration(seconds: 5), (_) {
      if (!busy && !fetching) unawaited(refresh());
      if (tracking &&
          appActive &&
          !locatingHeartbeat &&
          !sendingLocation &&
          (lastSent == null ||
              DateTime.now().difference(lastSent!).inSeconds >= 20)) {
        locatingHeartbeat = true;
        unawaited(
          Geolocator.getCurrentPosition(
                locationSettings: const LocationSettings(
                  accuracy: LocationAccuracy.high,
                  timeLimit: Duration(seconds: 15),
                ),
              )
              .then(sendLocation)
              .catchError((Object e) {
                if (mounted) setState(() => error = readableError(e));
              })
              .whenComplete(() => locatingHeartbeat = false),
        );
      }
    });
  }

  Future<void> refresh() async {
    try {
      await load();
    } catch (e) {
      if (mounted) {
        setState(() {
          error = readableError(e);
          if (ride != null) {
            ride = {...ride!, 'driver_lat': null, 'driver_lng': null};
          }
        });
      }
    }
  }

  Future<void> load() async {
    if (api.isDemo) return;
    fetching = true;
    try {
      final data =
          await api.request(
                '/bookings?as=${widget.driver ? 'driver' : 'passenger'}',
              )
              as List;
      final nextOffers = widget.driver
          ? await api.request('/driver/offers') as List
          : <dynamic>[];
      if (!mounted) return;
      setState(() {
        rides = data;
        offers = nextOffers;
        if (ride != null) {
          final matches = data.where((b) => b['id'] == ride!['id']);
          if (matches.isNotEmpty) ride = matches.first as Map;
        } else {
          final active = data.where((b) => activeRide(b as Map));
          if (active.isNotEmpty) ride = active.first as Map;
        }
        error = null;
      });
    } finally {
      fetching = false;
    }
  }

  Future<void> run(Future<void> Function() action) async {
    if (busy) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await action();
    } catch (e) {
      if (mounted) setState(() => error = readableError(e));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    appActive = state == AppLifecycleState.resumed;
    if (!appActive) unawaited(stopLocation());
  }

  Future<void> stopLocation() async {
    locationGeneration++;
    await locations?.cancel();
    locations = null;
    if (mounted) setState(() => tracking = false);
  }

  Future<void> shareLocation() async {
    final generation = ++locationGeneration;
    if (api.isDemo) {
      throw StateError('Preview only. Connect to the beta API for real rides.');
    }
    if (!await Geolocator.isLocationServiceEnabled()) {
      throw StateError('Turn on device location to receive nearby requests.');
    }
    var p = await Geolocator.checkPermission();
    if (p == LocationPermission.denied) {
      p = await Geolocator.requestPermission();
    }
    if (p == LocationPermission.denied ||
        p == LocationPermission.deniedForever) {
      throw StateError('Location permission is needed for nearby offers.');
    }
    await api.request(
      '/driver/availability',
      method: 'POST',
      data: {'online': true},
    );
    final first = await Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        timeLimit: Duration(seconds: 20),
      ),
    );
    if (!mounted || !appActive || generation != locationGeneration) return;
    await sendLocation(first);
    if (!mounted || !appActive || generation != locationGeneration) return;
    await locations?.cancel();
    locations =
        Geolocator.getPositionStream(
          locationSettings: const LocationSettings(
            accuracy: LocationAccuracy.high,
            distanceFilter: 0,
          ),
        ).listen(
          (p) {
            if (!sendingLocation) {
              unawaited(
                sendLocation(p).catchError((Object e) {
                  if (mounted) setState(() => error = readableError(e));
                }),
              );
            }
          },
          onError: (Object e) {
            unawaited(stopLocation());
            if (mounted) setState(() => error = readableError(e));
          },
        );
    if (mounted) setState(() => tracking = true);
    await load();
  }

  Future<void> sendLocation(Position p) async {
    if (!mounted || !appActive) return;
    if (p.accuracy > 100) {
      throw StateError(
        'GPS accuracy is low. Move somewhere with a clearer signal.',
      );
    }
    sendingLocation = true;
    try {
      await api.request(
        '/driver/location',
        method: 'POST',
        data: {
          'lat': p.latitude,
          'lng': p.longitude,
          'accuracyM': p.accuracy.ceil().clamp(0, 100),
          'recordedAt': p.timestamp.toUtc().toIso8601String(),
        },
      );
      lastSent = DateTime.now();
    } finally {
      sendingLocation = false;
    }
  }

  Future<void> pick(bool from) async {
    final point = await Navigator.of(context).push<LatLng>(
      MaterialPageRoute(
        builder: (_) => MapLocationPicker(initial: from ? pickup : destination),
      ),
    );
    if (point == null || !mounted) return;
    setState(() {
      if (from) {
        pickup = point;
      } else {
        destination = point;
      }
      quote = null;
      requestKey = null;
    });
  }

  Map<String, dynamic> get journey => {
    'pickup': {'lat': pickup!.latitude, 'lng': pickup!.longitude},
    'dropoff': {'lat': destination!.latitude, 'lng': destination!.longitude},
    'category': category,
  };
  Future<void> estimate() async {
    if (pickup == null || destination == null) {
      throw StateError('Choose pickup and destination on the map.');
    }
    final result =
        await api.request('/bookings/quote', method: 'POST', data: journey)
            as Map;
    if (mounted) setState(() => quote = result);
  }

  Future<void> request() async {
    if (quote == null) return;
    requestKey ??= 'ride-${DateTime.now().microsecondsSinceEpoch}';
    final result =
        await api.request(
              '/bookings',
              method: 'POST',
              headers: {'Idempotency-Key': requestKey!},
              data: {
                ...journey,
                'pickupLabel': pickupName.text.trim().isEmpty
                    ? 'Pickup'
                    : pickupName.text.trim(),
                'dropoffLabel': destinationName.text.trim().isEmpty
                    ? 'Destination'
                    : destinationName.text.trim(),
                'expectedFarePaise': quote!['farePaise'],
              },
            )
            as Map;
    if (!mounted) return;
    setState(() {
      ride = result;
      quote = null;
      requestKey = null;
    });
    await load();
  }

  Future<void> status(String next) async {
    await api.request(
      '/bookings/${ride!['id']}/status',
      method: 'POST',
      data: {'status': next, 'version': ride!['version']},
    );
    await load();
  }

  Future<void> accept(Map offer) async {
    final choices = widget.vehicles
        .where(
          (v) => v['approved'] == true && v['category'] == offer['category'],
        )
        .toList();
    if (choices.isEmpty) {
      throw StateError('An approved vehicle of this type is required.');
    }
    final vehicle = await showDialog<String>(
      context: context,
      builder: (dialog) => SimpleDialog(
        title: const Text('Choose your vehicle'),
        children: [
          for (final v in choices)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(dialog, '${v['id']}'),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Text('${v['registration']}'),
              ),
            ),
        ],
      ),
    );
    if (vehicle == null) return;
    final result =
        await api.request(
              '/bookings/${offer['id']}/accept',
              method: 'POST',
              data: {'vehicleId': vehicle},
            )
            as Map;
    if (mounted) setState(() => ride = result);
    await load();
  }

  Future<void> confirmPickup() async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: const Text('Are you in the right vehicle?'),
        content: Text(
          'Check ${ride!['registration'] ?? 'the registration'} and your driver before confirming.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialog, false),
            child: const Text('Not yet'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialog, true),
            child: const Text('Confirm pickup'),
          ),
        ],
      ),
    );
    if (yes != true) return;
    await api.request(
      '/bookings/${ride!['id']}/confirm-pickup',
      method: 'POST',
      data: {'version': ride!['version']},
    );
    await load();
  }

  @override
  void dispose() {
    timer?.cancel();
    unawaited(locations?.cancel());
    WidgetsBinding.instance.removeObserver(this);
    pickupName.dispose();
    destinationName.dispose();
    super.dispose();
  }

  List<JourneyPin> pins(Map? b) {
    final result = <JourneyPin>[];
    final a = b == null ? pickup : mapPoint(b['pickup_lat'], b['pickup_lng']);
    final z = b == null
        ? destination
        : mapPoint(b['dropoff_lat'], b['dropoff_lng']);
    if (a != null) result.add(JourneyPin('Pickup', a));
    if (z != null) result.add(JourneyPin('Destination', z));
    if (b != null && activeRide(b)) {
      final point = mapPoint(b['driver_lat'], b['driver_lng']);
      final at = DateTime.tryParse('${b['driver_recorded_at']}');
      if (point != null && at != null) {
        result.add(
          JourneyPin(
            'Your driver',
            point,
            vehicle: true,
            recordedAt: at,
            icon: Icons.local_taxi_rounded,
          ),
        );
      }
    }
    return result;
  }

  Widget action(String label, Future<void> Function() fn) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 6),
    child: FilledButton(
      onPressed: busy ? null : () => run(fn),
      child: Text(label),
    ),
  );
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(widget.driver ? 'Private rides' : 'Taxi / Auto'),
    ),
    body: SafeArea(
      child: RefreshIndicator(
        onRefresh: () => run(load),
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            if (api.isDemo)
              const Padding(
                padding: EdgeInsets.only(bottom: 12),
                child: Text(
                  'UI DEMO · Explore location selection. Real quotes, requests and offers require a server connection.',
                ),
              ),
            if (busy) const LinearProgressIndicator(),
            if (error != null)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Text(
                  error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
            if (ride == null)
              PremiumHeading(
                eyebrow: widget.driver
                    ? 'Private rides'
                    : 'Made for your plans',
                title: widget.driver
                    ? 'Your next journey.'
                    : 'A ride of your own.',
                subtitle: widget.driver
                    ? 'Nearby requests. Clear fares. You’re in control.'
                    : 'Choose pickup and destination to get started.',
              ),
            SizedBox(
              height: 220,
              child: JourneyMap(
                compact: true,
                pins: pins(ride),
                refreshPins: ride == null || api.isDemo
                    ? null
                    : () async => pins(
                        await api.request('/bookings/${ride!['id']}') as Map,
                      ),
              ),
            ),
            const SizedBox(height: 16),
            if (ride != null) ...rideView(context),
            if (ride == null && !widget.driver) ...[
              Text(
                'Your own ride, door to door.',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 12),
              SegmentedButton<String>(
                segments: const [
                  ButtonSegment(
                    value: 'AUTO',
                    label: Text('Auto'),
                    icon: Icon(Icons.electric_rickshaw),
                  ),
                  ButtonSegment(
                    value: 'TAXI',
                    label: Text('Taxi'),
                    icon: Icon(Icons.local_taxi),
                  ),
                ],
                selected: {category},
                onSelectionChanged: busy
                    ? null
                    : (v) => setState(() {
                        category = v.first;
                        quote = null;
                        requestKey = null;
                      }),
              ),
              const SizedBox(height: 12),
              ListTile(
                leading: const Icon(Icons.trip_origin),
                title: const Text('Pickup'),
                subtitle: Text(
                  pickup == null
                      ? 'Choose on map'
                      : 'Location chosen · Tap to change',
                ),
                onTap: busy ? null : () => pick(true),
              ),
              TextField(
                controller: pickupName,
                maxLength: 120,
                decoration: const InputDecoration(
                  labelText: 'Pickup landmark (optional)',
                ),
              ),
              ListTile(
                leading: const Icon(Icons.location_on_outlined),
                title: const Text('Destination'),
                subtitle: Text(
                  destination == null
                      ? 'Choose on map'
                      : 'Location chosen · Tap to change',
                ),
                onTap: busy ? null : () => pick(false),
              ),
              TextField(
                controller: destinationName,
                maxLength: 120,
                decoration: const InputDecoration(
                  labelText: 'Destination name (optional)',
                ),
              ),
              action('Get fare estimate', estimate),
              if (quote != null)
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(18),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          rideMoney(quote!['farePaise']),
                          style: Theme.of(context).textTheme.headlineMedium,
                        ),
                        Text(
                          '${quote!['betaPrice'] == true ? 'Temporary beta fare · ' : ''}Cash only. Based on straight-line distance, not road distance. No live arrival estimate.',
                        ),
                        action(
                          'Request ${category == 'AUTO' ? 'auto' : 'taxi'}',
                          request,
                        ),
                      ],
                    ),
                  ),
                ),
            ],
            if (widget.driver) ...[
              action(
                tracking
                    ? 'Stop location sharing'
                    : 'Go online & share location',
                () async {
                  if (tracking) {
                    await stopLocation();
                    await api.request(
                      '/driver/availability',
                      method: 'POST',
                      data: {'online': false},
                    );
                    await load();
                  } else {
                    await shareLocation();
                  }
                },
              ),
              const Text(
                'Keep this page open to share your location. Offers need approved driver/vehicle details and fresh GPS within 8 km of pickup.',
              ),
              if (ride == null) ...[
                const SizedBox(height: 20),
                Text(
                  'Nearby requests',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                if (offers.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 20),
                    child: Text('No requests right now.'),
                  ),
                for (final o in offers)
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(
                            '${o['category']} · ${rideMoney(o['fare_paise'])}',
                            style: Theme.of(context).textTheme.titleLarge,
                          ),
                          Text('${o['pickup_label']} → ${o['dropoff_label']}'),
                          Text(
                            '${o['pickup_distance_m']} m to pickup · Straight-line distance',
                          ),
                          action('Accept ride', () => accept(o as Map)),
                          TextButton(
                            onPressed: busy
                                ? null
                                : () => run(() async {
                                    await api.request(
                                      '/bookings/${o['id']}/reject',
                                      method: 'POST',
                                    );
                                    await load();
                                  }),
                            child: const Text('Decline'),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ],
            if (rides.any((b) => !activeRide(b as Map)))
              ExpansionTile(
                title: const Text('Past rides'),
                children: [
                  for (final b in rides.where((b) => !activeRide(b as Map)))
                    ListTile(
                      title: Text(
                        '${b['pickup_label']} → ${b['dropoff_label']}',
                      ),
                      subtitle: Text(
                        '${b['status']} · ${rideMoney(b['fare_paise'])}',
                      ),
                      onTap: () => setState(() => ride = b as Map),
                    ),
                ],
              ),
          ],
        ),
      ),
    ),
  );
  List<Widget> rideView(BuildContext context) {
    final b = ride!, state = b['status'];
    return [
      Text(
        {
              'REQUESTED': 'Finding a driver…',
              'ACCEPTED': 'Driver on the way',
              'ARRIVED': 'Driver has arrived',
              'IN_PROGRESS': 'On your way',
              'COMPLETED': 'Ride complete',
              'CANCELLED': 'Ride cancelled',
            }[state] ??
            '$state',
        style: Theme.of(context).textTheme.headlineSmall,
      ),
      const SizedBox(height: 8),
      Text(
        '${b['pickup_label'] ?? 'Pickup'} → ${b['dropoff_label'] ?? 'Destination'}',
      ),
      Text('${rideMoney(b['fare_paise'])} · Cash'),
      if (!widget.driver && b['registration'] != null)
        Text('${b['driver_name'] ?? 'Your driver'} · ${b['registration']}'),
      if (state == 'REQUESTED')
        const Text(
          'Only nearby available drivers receive this request. It expires after 3 minutes if nobody accepts.',
        ),
      if (!widget.driver &&
          ['ACCEPTED', 'ARRIVED', 'IN_PROGRESS'].contains(state) &&
          b['driver_lat'] == null)
        const Text('Driver location unavailable. No live arrival estimate.'),
      if (widget.driver &&
          ['ACCEPTED', 'ARRIVED', 'IN_PROGRESS'].contains(state)) ...[
        OutlinedButton.icon(
          onPressed: () {
            final p = state == 'IN_PROGRESS'
                ? mapPoint(b['dropoff_lat'], b['dropoff_lng'])
                : mapPoint(b['pickup_lat'], b['pickup_lng']);
            if (p != null) openDirections(context, p);
          },
          icon: const Icon(Icons.near_me),
          label: Text(
            state == 'IN_PROGRESS'
                ? 'Directions to destination'
                : 'Directions to pickup',
          ),
        ),
        if (state == 'ACCEPTED')
          action('I’ve arrived', () => status('ARRIVED')),
        if (state == 'ARRIVED' && b['pickup_confirmed_at'] == null)
          const Text(
            'Waiting for the passenger to confirm pickup in their app.',
          ),
        if (state == 'ARRIVED' && b['pickup_confirmed_at'] != null)
          action('Start trip', () => status('IN_PROGRESS')),
        if (state == 'IN_PROGRESS')
          action('Complete trip', () => status('COMPLETED')),
      ],
      if (!widget.driver &&
          state == 'ARRIVED' &&
          b['pickup_confirmed_at'] == null)
        action('I’m in the vehicle', confirmPickup),
      if (['REQUESTED', 'ACCEPTED', 'ARRIVED'].contains(state))
        TextButton(
          onPressed: busy ? null : () => run(() => status('CANCELLED')),
          child: const Text('Cancel ride'),
        ),
      if (state == 'COMPLETED') ...[
        if (b['cash_recorded'] == true)
          const Text('Driver recorded cash received.'),
        if (widget.driver && b['cash_recorded'] != true)
          action('Confirm cash received', () async {
            await api.request(
              '/bookings/${b['id']}/cash',
              method: 'POST',
              headers: {'Idempotency-Key': 'cash-${b['id']}'},
            );
            await load();
          }),
      ],
      if (!activeRide(b))
        action(
          widget.driver ? 'Back to requests' : 'Book another ride',
          () async {
            setState(() {
              ride = null;
              quote = null;
            });
          },
        ),
      const SizedBox(height: 16),
    ];
  }
}
