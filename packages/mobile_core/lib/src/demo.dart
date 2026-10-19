import 'api.dart';

/// Read-only sample schedules. This never confirms a booking or creates a session.
class DemoApi extends Api {
  final String mode;
  DemoApi({this.mode = 'passenger'}) {
    endpointConfirmed = true;
  }
  @override
  bool get isDemo => true;
  @override
  Future<void> restore() async {}
  @override
  Future<dynamic> request(
    String path, {
    String method = 'GET',
    dynamic data,
    Map<String, String>? headers,
    bool retry = true,
  }) async {
    if (method != 'GET') {
      throw StateError(
        'This is a read-only UI demo. Connect to your test server for real actions.',
      );
    }
    if (path == '/me') {
      return {
        'name': '',
        'language': 'en',
        'roles': [mode == 'driver' ? 'DRIVER' : 'PASSENGER'],
      };
    }
    if (path.startsWith('/bus/trips?')) {
      final q = Uri.parse(path).queryParameters;
      return schedules.where((t) {
        final names = (t['stops'] as List)
            .map((s) => s['name'].toString().toLowerCase())
            .join(' ');
        return names.contains((q['origin'] ?? '').toLowerCase()) &&
            names.contains((q['destination'] ?? '').toLowerCase());
      }).toList();
    }
    if (path.startsWith('/bus/trips/')) {
      return schedules.firstWhere((t) => t['id'] == path.split('/')[3]);
    }
    if (mode == 'driver' && path == '/driver/vehicles') {
      return [
        {
          'id': 'sample-auto-1',
          'registration': 'DEMO AUTO 001',
          'category': 'AUTO',
          'capacity': 3,
          'approved': true,
        },
      ];
    }
    if (mode == 'driver' && path == '/driver/shared-trips') {
      return [
        {
          'id': 'sample-shared-1',
          'status': 'PUBLISHED',
          'departure_at': DateTime.now()
              .add(const Duration(hours: 1))
              .toIso8601String(),
          'capacity': 3,
          'fare_paise': 2000,
          'stops': [
            {'name': 'Kothamangalam', 'sequence': 0},
            {'name': 'Nellikuzhi', 'sequence': 1},
            {'name': 'Muvattupuzha', 'sequence': 2},
          ],
          'reservations': [],
        },
      ];
    }
    if (path == '/bookings' || path == '/me/reservations') return [];
    if (path == '/shared-trips') return [];
    throw StateError('This feature requires a connected test server.');
  }

  List<Map<String, dynamic>> get schedules => [
    trip(
      'sample-bus-1',
      'Kothamangalam → Muvattupuzha',
      'DEMO · Kerala service',
      18,
      20,
      [
        {'name': 'Kothamangalam', 'sequence': 0, 'offsetMinutes': 0},
        {'name': 'Nellikuzhi', 'sequence': 1, 'offsetMinutes': 10},
        {'name': 'Muvattupuzha', 'sequence': 2, 'offsetMinutes': 35},
      ],
    ),
    trip(
      'sample-bus-2',
      'Kothamangalam → Perumbavoor',
      'DEMO · Rural connector',
      18,
      45,
      [
        {'name': 'Kothamangalam', 'sequence': 0, 'offsetMinutes': 0},
        {'name': 'Kuruppampady', 'sequence': 1, 'offsetMinutes': 25},
        {'name': 'Perumbavoor', 'sequence': 2, 'offsetMinutes': 45},
      ],
    ),
  ];
  Map<String, dynamic> trip(
    String id,
    String route,
    String registration,
    int hour,
    int minute,
    List<Map<String, dynamic>> stops,
  ) {
    final now = DateTime.now();
    return {
      'id': id,
      'route_name': route,
      'registration': registration,
      'status': 'SCHEDULED',
      'version': 1,
      'departure_at': DateTime(
        now.year,
        now.month,
        now.day,
        hour,
        minute,
      ).toIso8601String(),
      'locationQuality': 'UNAVAILABLE',
      'recorded_at': null,
      'lat': null,
      'lng': null,
      'delay_minutes': 0,
      'stops': stops,
      'timeSource': 'SCHEDULED',
    };
  }
}
