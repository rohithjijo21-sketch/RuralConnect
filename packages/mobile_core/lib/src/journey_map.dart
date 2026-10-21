import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';

/// Only validated coordinates enter a map. Missing positions stay missing.
LatLng? mapPoint(dynamic lat, dynamic lng) {
  final a = double.tryParse('$lat'), b = double.tryParse('$lng');
  if (a == null ||
      b == null ||
      !a.isFinite ||
      !b.isFinite ||
      a.abs() > 90 ||
      b.abs() > 180) {
    return null;
  }
  return LatLng(a, b);
}

class JourneyPin {
  final String name;
  final LatLng point;
  final bool vehicle;
  final IconData? icon;
  final DateTime? recordedAt;
  final VoidCallback? onTap;
  const JourneyPin(
    this.name,
    this.point, {
    this.vehicle = false,
    this.onTap,
    this.recordedAt,
    this.icon,
  });
}

List<JourneyPin> servicePins(
  List services, {
  bool live = true,
  void Function(Map)? onTrip,
}) {
  final pins = <JourneyPin>[];
  final seen = <String>{};
  for (final service in services.whereType<Map>()) {
    for (final stop in (service['stops'] as List? ?? []).whereType<Map>()) {
      final point = mapPoint(stop['lat'], stop['lng']);
      final key = '${stop['name']}:$point';
      if (point != null && seen.add(key)) {
        pins.add(JourneyPin('${stop['name']}', point));
      }
    }
    final position = mapPoint(service['lat'], service['lng']);
    final at = DateTime.tryParse('${service['recorded_at']}');
    final age = at == null
        ? null
        : DateTime.now().toUtc().difference(at.toUtc());
    if (live &&
        service['locationQuality'] == 'LIVE' &&
        position != null &&
        age != null &&
        !age.isNegative &&
        age.inSeconds <= 60 &&
        [
          'RUNNING',
          'DELAYED',
          'STOPPED',
          'DIVERTED',
        ].contains(service['status'])) {
      pins.add(
        JourneyPin(
          '${service['route_name'] ?? 'Bus'} · Live',
          position,
          vehicle: true,
          recordedAt: at,
          onTap: onTrip == null ? null : () => onTrip(service),
        ),
      );
    }
  }
  return pins;
}

Future<void> openDirections(BuildContext context, LatLng point) async {
  final uri = Uri.https('www.google.com', '/maps/dir/', {
    'api': '1',
    'destination': '${point.latitude},${point.longitude}',
  });
  try {
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      throw StateError('No navigation app could open');
    }
  } catch (_) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not open directions. Please try again.'),
        ),
      );
    }
  }
}

/// On-demand network tiles; no bulk download or offline region prefetch.
/// flutter_map 8.3 uses its native built-in HTTP-aware tile cache.
class JourneyMap extends StatefulWidget {
  final List<JourneyPin> pins;
  final bool picker;
  final LatLng? initial;
  final ValueChanged<LatLng>? onPick;
  final String emptyLabel;
  final bool loadTiles;
  final bool compact;
  final Future<List<JourneyPin>> Function()? refreshPins;
  const JourneyMap({
    super.key,
    this.pins = const [],
    this.picker = false,
    this.initial,
    this.onPick,
    this.loadTiles = true,
    this.compact = false,
    this.refreshPins,
    this.emptyLabel = 'Explore the map. Services appear when published.',
  });
  @override
  State<JourneyMap> createState() => _JourneyMapState();
}

class _JourneyMapState extends State<JourneyMap> {
  final controller = MapController();
  LatLng? current, picked;
  bool locating = false, tileError = false;
  String? locationError;
  Timer? refreshTimer;
  List<JourneyPin>? refreshed;
  bool refreshing = false;
  List<JourneyPin> get visiblePins => (refreshed ?? widget.pins).where((p) {
    if (!p.vehicle) return true;
    final at = p.recordedAt;
    if (at == null) return false;
    final age = DateTime.now().toUtc().difference(at.toUtc());
    return !age.isNegative && age.inSeconds <= 60;
  }).toList();
  Future<void> refresh() async {
    if (!mounted || refreshing) return;
    if (widget.refreshPins == null) {
      setState(() {});
      return;
    }
    refreshing = true;
    try {
      final next = await widget.refreshPins!();
      if (mounted) setState(() => refreshed = next);
    } catch (_) {
      if (mounted) {
        setState(
          () => refreshed = visiblePins.where((p) => !p.vehicle).toList(),
        );
      }
    } finally {
      refreshing = false;
    }
  }

  @override
  void initState() {
    super.initState();
    picked = widget.initial;
    refreshTimer = Timer.periodic(
      const Duration(seconds: 10),
      (_) => refresh(),
    );
  }

  @override
  void didUpdateWidget(covariant JourneyMap oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.pins != oldWidget.pins) refreshed = null;
  }

  @override
  void dispose() {
    refreshTimer?.cancel();
    controller.dispose();
    super.dispose();
  }

  void fit() {
    final points = visiblePins.map((p) => p.point).toList();
    if (current != null) points.add(current!);
    if (picked != null) points.add(picked!);
    if (points.isEmpty) return;
    if (points.length == 1) {
      controller.move(points.first, 14);
    } else {
      controller.fitCamera(
        CameraFit.bounds(
          bounds: LatLngBounds.fromPoints(points),
          padding: const EdgeInsets.all(48),
          maxZoom: 15,
        ),
      );
    }
  }

  Future<void> locate() async {
    if (locating) return;
    setState(() {
      locating = true;
      locationError = null;
    });
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        throw StateError('Turn on location, or choose a place on the map.');
      }
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        throw StateError(
          'Location is off. You can still choose places on the map.',
        );
      }
      final p = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          timeLimit: Duration(seconds: 20),
        ),
      );
      if (!mounted) return;
      setState(() => current = LatLng(p.latitude, p.longitude));
      controller.move(current!, 15);
      if (widget.picker) {
        setState(() => picked = current);
        widget.onPick?.call(current!);
      }
    } catch (e) {
      if (mounted) {
        setState(() => locationError = '$e'.replaceFirst('Bad state: ', ''));
      }
    } finally {
      if (mounted) setState(() => locating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final points = visiblePins.map((p) => p.point).toList();
    return ClipRRect(
      borderRadius: BorderRadius.circular(24),
      child: Stack(
        children: [
          FlutterMap(
            mapController: controller,
            options: MapOptions(
              initialCenter:
                  widget.initial ??
                  (points.isEmpty ? const LatLng(10.25, 76.35) : points.first),
              initialZoom: points.isEmpty && widget.initial == null ? 8 : 13,
              initialCameraFit: points.length < 2
                  ? null
                  : CameraFit.bounds(
                      bounds: LatLngBounds.fromPoints(points),
                      padding: const EdgeInsets.all(48),
                      maxZoom: 14,
                    ),
              interactionOptions: InteractionOptions(
                flags: widget.compact
                    ? InteractiveFlag.none
                    : InteractiveFlag.all & ~InteractiveFlag.rotate,
              ),
              onTap: widget.picker
                  ? (_, point) {
                      setState(() => picked = point);
                      widget.onPick?.call(point);
                    }
                  : null,
            ),
            children: [
              if (widget.loadTiles)
                TileLayer(
                  urlTemplate: const String.fromEnvironment(
                    'MAP_TILE_URL',
                    defaultValue:
                        'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                  ),
                  userAgentPackageName: 'in.ruralconnect.mobile',
                  panBuffer: 0,
                  maxNativeZoom: 19,
                  errorTileCallback: (_, _, _) {
                    if (!tileError && mounted) {
                      WidgetsBinding.instance.addPostFrameCallback((_) {
                        if (mounted) setState(() => tileError = true);
                      });
                    }
                  },
                ),
              MarkerLayer(
                markers: [
                  for (final pin in visiblePins)
                    Marker(
                      point: pin.point,
                      width: 48,
                      height: 48,
                      child: IconButton.filled(
                        tooltip: pin.name,
                        style: IconButton.styleFrom(
                          backgroundColor: pin.vehicle
                              ? const Color(0xFF142A24)
                              : Colors.white,
                          foregroundColor: pin.vehicle
                              ? Colors.white
                              : const Color(0xFF14634D),
                        ),
                        onPressed:
                            pin.onTap ??
                            () => showModalBottomSheet<void>(
                              context: context,
                              showDragHandle: true,
                              builder: (sheet) => SafeArea(
                                child: Padding(
                                  padding: const EdgeInsets.fromLTRB(
                                    24,
                                    0,
                                    24,
                                    24,
                                  ),
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    crossAxisAlignment:
                                        CrossAxisAlignment.stretch,
                                    children: [
                                      Text(
                                        pin.name,
                                        style: Theme.of(
                                          context,
                                        ).textTheme.titleLarge,
                                      ),
                                      const SizedBox(height: 20),
                                      FilledButton.icon(
                                        onPressed: () {
                                          Navigator.pop(sheet);
                                          openDirections(context, pin.point);
                                        },
                                        icon: const Icon(
                                          Icons.near_me_outlined,
                                        ),
                                        label: const Text('Get directions'),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                        icon: Icon(
                          pin.icon ??
                              (pin.vehicle
                                  ? Icons.directions_bus_rounded
                                  : Icons.location_on_rounded),
                        ),
                      ),
                    ),
                  if (current != null)
                    Marker(
                      point: current!,
                      width: 24,
                      height: 24,
                      child: const Tooltip(
                        message: 'Your location',
                        child: Icon(
                          Icons.my_location,
                          color: Color(0xFF1C64F2),
                        ),
                      ),
                    ),
                  if (picked != null)
                    Marker(
                      point: picked!,
                      width: 44,
                      height: 44,
                      child: const Icon(
                        Icons.location_pin,
                        color: Color(0xFF14634D),
                        size: 44,
                      ),
                    ),
                ],
              ),
              Align(
                alignment: Alignment.bottomLeft,
                child: Material(
                  color: Colors.white,
                  child: InkWell(
                    onTap: () => launchUrl(
                      Uri.parse('https://www.openstreetmap.org/copyright'),
                    ),
                    child: const Padding(
                      padding: EdgeInsets.all(5),
                      child: Text(
                        '© OpenStreetMap contributors',
                        style: TextStyle(fontSize: 10, color: Colors.black87),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
          if (locationError != null ||
              tileError ||
              (visiblePins.isEmpty && !widget.picker))
            Positioned(
              top: 12,
              left: 12,
              right: 60,
              child: Material(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                child: Padding(
                  padding: const EdgeInsets.all(10),
                  child: Text(
                    locationError ??
                        (tileError
                            ? 'Map tiles unavailable. Check your connection.'
                            : widget.emptyLabel),
                    style: const TextStyle(color: Colors.black87, fontSize: 12),
                  ),
                ),
              ),
            ),
          if (widget.compact)
            Positioned(
              top: 12,
              right: 12,
              child: IconButton.filledTonal(
                tooltip: 'Open full map',
                icon: const Icon(Icons.open_in_full),
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => Scaffold(
                      appBar: AppBar(title: const Text('Map')),
                      body: SafeArea(
                        child: JourneyMap(
                          pins: visiblePins,
                          refreshPins: widget.refreshPins,
                          loadTiles: widget.loadTiles,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          Positioned(
            right: 12,
            bottom: 34,
            child: Column(
              children: [
                IconButton.filledTonal(
                  tooltip: 'Show all stops',
                  onPressed: fit,
                  icon: const Icon(Icons.fit_screen),
                ),
                const SizedBox(height: 8),
                IconButton.filled(
                  tooltip: 'Use my location',
                  onPressed: locating ? null : locate,
                  icon: locating
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.my_location),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class MapLocationPicker extends StatefulWidget {
  final LatLng? initial;
  const MapLocationPicker({super.key, this.initial});
  @override
  State<MapLocationPicker> createState() => _MapLocationPickerState();
}

class _MapLocationPickerState extends State<MapLocationPicker> {
  LatLng? selected;
  @override
  void initState() {
    super.initState();
    selected = widget.initial;
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Choose stop location')),
    body: SafeArea(
      child: Column(
        children: [
          const Padding(
            padding: EdgeInsets.all(16),
            child: Text('Tap the map at the stop, then confirm.'),
          ),
          Expanded(
            child: JourneyMap(
              initial: widget.initial,
              picker: true,
              onPick: (p) => setState(() => selected = p),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(20),
            child: FilledButton(
              onPressed: selected == null
                  ? null
                  : () => Navigator.pop(context, selected),
              child: const Text('Confirm location'),
            ),
          ),
        ],
      ),
    ),
  );
}

/// Passenger search uses published stop names, never an invented geocoding result.
class PublishedStopPicker extends StatefulWidget {
  final List<JourneyPin> pins;
  const PublishedStopPicker({super.key, required this.pins});
  @override
  State<PublishedStopPicker> createState() => _PublishedStopPickerState();
}

class _PublishedStopPickerState extends State<PublishedStopPicker> {
  JourneyPin? from, to;
  String query = '';
  void choose(JourneyPin p) => setState(() {
    if (from == null || to != null) {
      from = p;
      to = null;
    } else if (p.name != from!.name) {
      to = p;
    }
  });
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Choose your stops')),
    body: SafeArea(
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              from == null
                  ? 'Choose your pickup stop'
                  : to == null
                  ? 'From ${from!.name} · Choose destination'
                  : '${from!.name} → ${to!.name}',
            ),
          ),
          SizedBox(
            height: 240,
            child: JourneyMap(
              pins: [
                for (final p in widget.pins)
                  JourneyPin(p.name, p.point, onTap: () => choose(p)),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(12),
            child: TextField(
              decoration: const InputDecoration(
                hintText: 'Search published stops',
                prefixIcon: Icon(Icons.search),
              ),
              onChanged: (v) => setState(() => query = v.toLowerCase()),
            ),
          ),
          Expanded(
            child: ListView(
              children: [
                if (widget.pins.isEmpty)
                  const ListTile(
                    title: Text(
                      'No published stop locations yet. You can search by name on the home screen.',
                    ),
                  ),
                for (final p in widget.pins.where(
                  (p) => p.name.toLowerCase().contains(query),
                ))
                  ListTile(
                    leading: Icon(
                      from == p
                          ? Icons.trip_origin
                          : to == p
                          ? Icons.flag
                          : Icons.location_on_outlined,
                    ),
                    title: Text(p.name),
                    selected: from == p || to == p,
                    onTap: () => choose(p),
                  ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: FilledButton(
              onPressed: from == null || to == null
                  ? null
                  : () => Navigator.pop(context, [from!.name, to!.name]),
              child: const Text('Find services'),
            ),
          ),
        ],
      ),
    ),
  );
}
