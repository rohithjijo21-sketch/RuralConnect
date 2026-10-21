import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:ruralconnect_mobile/src/journey_map.dart';

void main() {
  test(
    'Missing, invalid and stale coordinates cannot create live vehicles',
    () {
      expect(mapPoint(null, 76), isNull);
      expect(mapPoint('NaN', 76), isNull);
      expect(mapPoint(91, 76), isNull);
      expect(mapPoint(10, 181), isNull);
      expect(mapPoint('10.2', '76.3'), const LatLng(10.2, 76.3));
      final trip = <String, dynamic>{
        'route_name': 'Test route',
        'status': 'RUNNING',
        'locationQuality': 'LIVE',
        'lat': 10,
        'lng': 76,
        'recorded_at': DateTime.now().toUtc().toIso8601String(),
        'stops': [
          {'name': 'Test stop', 'lat': 10.1, 'lng': 76.1},
        ],
      };
      expect(servicePins([trip]).where((p) => p.vehicle), hasLength(1));
      expect(servicePins([trip], live: false).where((p) => p.vehicle), isEmpty);
      expect(
        servicePins([
          {...trip, 'status': 'COMPLETED'},
        ]).where((p) => p.vehicle),
        isEmpty,
      );
      expect(
        servicePins([
          {
            ...trip,
            'recorded_at': DateTime.now()
                .subtract(const Duration(minutes: 2))
                .toIso8601String(),
          },
        ]).where((p) => p.vehicle),
        isEmpty,
      );
      expect(
        servicePins([
          {...trip, 'locationQuality': 'CACHED_SCHEDULE'},
        ]).where((p) => p.vehicle),
        isEmpty,
      );
      expect(
        servicePins([
          {...trip, 'lat': null},
        ]).where((p) => p.vehicle),
        isEmpty,
      );
      expect(servicePins([trip, trip]).where((p) => !p.vehicle), hasLength(1));
    },
  );
  testWidgets(
    'Map loads without requesting location and retains visible attribution',
    (tester) async {
      await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: JourneyMap(loadTiles: false))),
      );
      await tester.pumpAndSettle();
      expect(find.text('© OpenStreetMap contributors'), findsOneWidget);
      expect(find.byTooltip('Use my location'), findsOneWidget);
      expect(find.textContaining('Location is off'), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'Tapping the picker map sets a location; normal browsing does not',
    (tester) async {
      LatLng? chosen;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: JourneyMap(
              loadTiles: false,
              picker: true,
              onPick: (p) => chosen = p,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tapAt(const Offset(400, 300));
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pumpAndSettle();
      expect(chosen, isNotNull);
      expect(chosen!.latitude, inInclusiveRange(-90, 90));
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'Passenger must choose two distinct published stops before searching',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: PublishedStopPicker(
            pins: const [
              JourneyPin('Pickup test', LatLng(10, 76)),
              JourneyPin('Destination test', LatLng(10.1, 76.1)),
            ],
          ),
        ),
      );
      await tester.pumpAndSettle();
      FilledButton button() =>
          tester.widget(find.widgetWithText(FilledButton, 'Find services'));
      expect(button().onPressed, isNull);
      await tester.tap(find.text('Pickup test'));
      await tester.pump();
      expect(button().onPressed, isNull);
      await tester.tap(find.text('Pickup test'));
      await tester.pump();
      expect(button().onPressed, isNull);
      await tester.tap(find.text('Destination test'));
      await tester.pump();
      expect(button().onPressed, isNotNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
