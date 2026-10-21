import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ruralconnect_mobile/src/api.dart';
import 'package:ruralconnect_mobile/src/private_rides.dart';

class RideFixture extends Api {
  final bool driver;
  Map<String, dynamic>? current;
  bool rejectAccept = false;
  final calls = <String>[];
  RideFixture({this.driver = false, String? status}) {
    if (status != null) current = {...fixtureRide, 'status': status};
  }
  @override
  Future<dynamic> request(
    String path, {
    String method = 'GET',
    dynamic data,
    Map<String, String>? headers,
    bool retry = true,
  }) async {
    calls.add('$method $path');
    if (path.startsWith('/bookings?')) return current == null ? [] : [current];
    if (path == '/driver/offers') return current == null ? [fixtureRide] : [];
    if (path == '/bookings/ride-test/accept') {
      if (rejectAccept) throw StateError('Another driver accepted this ride');
      current = {...fixtureRide, 'status': 'ACCEPTED'};
      return current;
    }
    if (path == '/bookings/ride-test/confirm-pickup') {
      current = {
        ...current!,
        'pickup_confirmed_at': '2026-10-21T15:00:00Z',
        'version': 2,
      };
      return current;
    }
    if (path == '/bookings/ride-test/status') {
      current = {...current!, 'status': data['status'], 'version': 2};
      return current;
    }
    if (path == '/bookings/ride-test/cash') {
      current = {...current!, 'cash_recorded': true};
      return {'id': 'payment-test'};
    }
    throw StateError('Unexpected fixture request $path');
  }
}

final fixtureRide = <String, dynamic>{
  'id': 'ride-test',
  'status': 'REQUESTED',
  'version': 1,
  'category': 'AUTO',
  'fare_paise': 6000,
  'pickup_label': 'Fixture pickup',
  'dropoff_label': 'Fixture destination',
  'pickup_lat': 10.06,
  'pickup_lng': 76.63,
  'dropoff_lat': 10.08,
  'dropoff_lng': 76.64,
  'registration': 'TEST AUTO',
  'pickup_distance_m': 200,
  'cash_recorded': false,
};

Future<void> reveal(WidgetTester t, String text) async {
  await t.scrollUntilVisible(
    find.text(text),
    150,
    scrollable: find.byType(Scrollable).first,
  );
}

void main() {
  testWidgets(
    'Passenger sees real request state, cancellation is server acknowledged',
    (t) async {
      t.view.physicalSize = const Size(430, 1200);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.resetPhysicalSize);
      addTearDown(t.view.resetDevicePixelRatio);
      final api = RideFixture(status: 'REQUESTED');
      await t.pumpWidget(MaterialApp(home: PrivateRidesScreen(api: api)));
      await t.pumpAndSettle();
      await reveal(t, 'Cancel ride');
      expect(find.text('Finding a driver…'), findsOneWidget);
      expect(find.textContaining('Driver on the way'), findsNothing);
      await t.tap(find.text('Cancel ride'));
      await t.pumpAndSettle();
      expect(api.calls, contains('POST /bookings/ride-test/status'));
      expect(find.text('Ride cancelled'), findsOneWidget);
      await t.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'Passenger checks vehicle then confirms pickup; never starts the trip',
    (t) async {
      t.view.physicalSize = const Size(430, 1200);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.resetPhysicalSize);
      addTearDown(t.view.resetDevicePixelRatio);
      final api = RideFixture(status: 'ARRIVED');
      await t.pumpWidget(MaterialApp(home: PrivateRidesScreen(api: api)));
      await t.pumpAndSettle();
      await reveal(t, 'I’m in the vehicle');
      await t.tap(find.text('I’m in the vehicle'));
      await t.pump(const Duration(milliseconds: 400));
      expect(find.textContaining('Check TEST AUTO'), findsOneWidget);
      await t.tap(find.text('Confirm pickup'));
      await t.pumpAndSettle();
      expect(api.calls, contains('POST /bookings/ride-test/confirm-pickup'));
      expect(api.calls, isNot(contains('POST /bookings/ride-test/status')));
      await t.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'Driver accepts through the API and competing rejection is never shown as accepted',
    (t) async {
      t.view.physicalSize = const Size(430, 1200);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.resetPhysicalSize);
      addTearDown(t.view.resetDevicePixelRatio);
      final api = RideFixture(driver: true)..rejectAccept = true;
      await t.pumpWidget(
        MaterialApp(
          home: PrivateRidesScreen(
            api: api,
            driver: true,
            vehicles: const [
              {
                'id': 'vehicle-test',
                'category': 'AUTO',
                'registration': 'TEST AUTO',
                'approved': true,
              },
            ],
          ),
        ),
      );
      await t.pumpAndSettle();
      await reveal(t, 'Accept ride');
      await t.tap(find.text('Accept ride'));
      await t.pump(const Duration(milliseconds: 400));
      await t.tap(find.text('TEST AUTO'));
      await t.pumpAndSettle();
      expect(api.current, isNull);
      expect(find.text('Driver on the way'), findsNothing);
      expect(
        find.textContaining('Another driver accepted this ride'),
        findsOneWidget,
      );
      await t.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'Driver cannot start before passenger pickup confirmation and cash is explicit',
    (t) async {
      t.view.physicalSize = const Size(430, 1200);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.resetPhysicalSize);
      addTearDown(t.view.resetDevicePixelRatio);
      final api = RideFixture(driver: true, status: 'ARRIVED');
      await t.pumpWidget(
        MaterialApp(home: PrivateRidesScreen(api: api, driver: true)),
      );
      await t.pumpAndSettle();
      await reveal(
        t,
        'Waiting for the passenger to confirm pickup in their app.',
      );
      expect(find.text('Start trip'), findsNothing);
      await t.pumpWidget(const SizedBox());
      await t.pump();
      final completed = RideFixture(driver: true, status: 'COMPLETED');
      await t.pumpWidget(
        MaterialApp(home: PrivateRidesScreen(api: completed, driver: true)),
      );
      await t.pumpAndSettle();
      await reveal(t, 'Past rides');
      await t.tap(find.text('Past rides'));
      await t.pumpAndSettle();
      await reveal(t, 'Fixture pickup → Fixture destination');
      await t.tap(find.text('Fixture pickup → Fixture destination'));
      await t.pumpAndSettle();
      await reveal(t, 'Confirm cash received');
      expect(find.text('Driver recorded cash received.'), findsNothing);
      await t.tap(find.text('Confirm cash received'));
      await t.pumpAndSettle();
      expect(completed.calls, contains('POST /bookings/ride-test/cash'));
      expect(find.text('Driver recorded cash received.'), findsOneWidget);
      await t.pumpWidget(const SizedBox());
    },
  );
}
