import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ruralconnect_mobile/ruralconnect_mobile.dart';
import 'package:dio/dio.dart';

class FixtureApi extends Api {
  final bool failNetwork;
  bool rejectSeat;
  final List<Map<String, dynamic>> requests = [];
  FixtureApi({
    bool signedIn = false,
    this.failNetwork = false,
    this.rejectSeat = false,
  }) {
    endpointConfirmed = true;
    if (signedIn) access = 'fixture-access';
  }
  @override
  Future<void> restore() async {}
  @override
  Future<void> save(Map<String, dynamic> data) async {
    access = data['accessToken'] as String;
  }

  @override
  Future<dynamic> request(
    String path, {
    String method = 'GET',
    dynamic data,
    Map<String, String>? headers,
    bool retry = true,
  }) async {
    requests.add({
      'path': path,
      'method': method,
      'data': data,
      'headers': headers,
    });
    if (failNetwork) {
      throw DioException(
        requestOptions: RequestOptions(path: path),
        type: DioExceptionType.connectionError,
      );
    }
    if (path == '/auth/otp/request') {
      return {'challengeId': 'fixture-challenge'};
    }
    if (path == '/auth/otp/verify') {
      return {
        'accessToken': 'fixture-access',
        'refreshToken': 'fixture-refresh',
      };
    }
    if (path == '/me') return {'name': '', 'language': 'en'};
    if (path == '/shared-trips' ||
        path == '/bookings' ||
        path == '/me/reservations') {
      return [];
    }
    if (path.startsWith('/bus/trips?')) return [fixtureTrip];
    if (path.startsWith('/shared-trips/') && path.endsWith('/reservations')) {
      if (rejectSeat) {
        throw DioException(
          requestOptions: RequestOptions(path: path),
          response: Response(
            requestOptions: RequestOptions(path: path),
            statusCode: 409,
            data: {'message': 'Insufficient seats'},
          ),
        );
      }
      return {'id': 'fixture-confirmed-reservation'};
    }
    throw StateError('Unexpected fixture request: $path');
  }
}

final fixtureTrip = {
  'id': 'fixture-trip',
  'route_name': 'Fixture Kerala bus',
  'status': 'SCHEDULED',
  'version': 1,
  'departure_at': '2026-10-18T03:30:00Z',
  'locationQuality': 'UNAVAILABLE',
  'recorded_at': null,
  'lat': null,
  'lng': null,
  'delay_minutes': 0,
};
final fixtureShared = {
  'id': 'fixture-shared',
  'stops': [
    {'sequence': 0, 'name': 'A'},
    {'sequence': 1, 'name': 'B'},
  ],
  'departure_at': '2026-10-18T04:30:00Z',
  'fare_paise': 2000,
  'availableSeats': 1,
};
void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  testWidgets(
    'Passenger signs in and receives bus schedule without requesting GPS',
    (tester) async {
      final api = FixtureApi();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [apiProvider.overrideWithValue(api)],
          child: const RuralConnectApp(
            mode: 'passenger',
            title: 'Fixture Passenger',
            color: Colors.green,
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextField, 'Phone number (+91)'),
        '+919000000001',
      );
      await tester.enterText(
        find.widgetWithText(TextField, 'Local sandbox access key'),
        'fixture-key',
      );
      await tester.tap(find.text('Request sandbox challenge'));
      await tester.pumpAndSettle();
      expect(find.text('Configured six-digit OTP'), findsOneWidget);
      await tester.enterText(
        find.widgetWithText(TextField, 'Configured six-digit OTP'),
        '123456',
      );
      await tester.ensureVisible(find.byType(CheckboxListTile));
      await tester.tap(find.byType(CheckboxListTile));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Sign in'));
      await tester.tap(find.text('Sign in'));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.text('Fixture Kerala bus'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('Fixture Kerala bus'), findsOneWidget);
      await tester.scrollUntilVisible(
        find.textContaining('Browse without GPS permission'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      expect(
        find.textContaining('Browse without GPS permission'),
        findsOneWidget,
      );
      expect(
        api.requests.any((r) => r['path'].toString().contains('/location')),
        isFalse,
      );
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
    },
  );
  testWidgets(
    'Network failure shows explicit offline state and no confirmation',
    (tester) async {
      final api = FixtureApi(signedIn: true, failNetwork: true);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [apiProvider.overrideWithValue(api)],
          child: const RuralConnectApp(
            mode: 'passenger',
            title: 'Fixture Passenger',
            color: Colors.green,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('Network unavailable.'), findsOneWidget);
      expect(
        find.textContaining('Offline · Cached schedules only.'),
        findsOneWidget,
      );
      expect(find.textContaining('Server confirmed reservation'), findsNothing);
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
    },
  );
  testWidgets(
    'Rejected reservation never appears confirmed and retries keep the same key',
    (tester) async {
      final api = FixtureApi(signedIn: true, rejectSeat: true);
      await tester.pumpWidget(
        MaterialApp(
          home: SharedList(api: api, trips: [fixtureShared]),
        ),
      );
      await tester.tap(
        find.text('Request 1 seat — server confirmation required'),
      );
      await tester.pumpAndSettle();
      expect(find.text('Insufficient seats'), findsOneWidget);
      expect(find.textContaining('Server confirmed reservation'), findsNothing);
      await tester.tap(
        find.text('Request 1 seat — server confirmation required'),
      );
      await tester.pumpAndSettle();
      expect(
        api.requests[0]['headers']['Idempotency-Key'],
        api.requests[1]['headers']['Idempotency-Key'],
      );
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'Seat confirmation displays the acknowledged backend reservation id',
    (tester) async {
      final api = FixtureApi(signedIn: true);
      await tester.pumpWidget(
        MaterialApp(
          home: SharedList(api: api, trips: [fixtureShared]),
        ),
      );
      await tester.tap(
        find.text('Request 1 seat — server confirmation required'),
      );
      await tester.pumpAndSettle();
      expect(
        find.textContaining(
          'Server confirmed reservation fixture-confirmed-reservation',
        ),
        findsOneWidget,
      );
      await tester.pumpWidget(const SizedBox());
    },
  );
}
