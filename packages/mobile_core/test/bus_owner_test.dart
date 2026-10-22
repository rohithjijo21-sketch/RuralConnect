import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ruralconnect_mobile/src/api.dart';
import 'package:ruralconnect_mobile/src/bus_owner.dart';

class OwnerFixture extends Api {
  bool created = false, reject = false;
  final calls = <String>[];
  @override
  Future<dynamic> request(
    String path, {
    String method = 'GET',
    dynamic data,
    Map<String, String>? headers,
    bool retry = true,
  }) async {
    calls.add(path);
    if (path == '/bus-owner/apply') {
      if (reject) throw StateError('Owner registration failed');
      created = true;
      return {'status': 'PENDING'};
    }
    return {
      'owner': created
          ? {
              'name': 'Test owner',
              'operator_id': 'operator-id',
              'status': 'PENDING',
            }
          : null,
      'vehicles': [],
      'routes': [],
      'plans': created
          ? [
              {
                'id': 'plan-id',
                'name': 'Morning service',
                'departure_time': '09:00',
                'start_date': '2030-01-07',
                'end_date': '2030-01-07',
                'weekdays': [1],
                'excluded_dates': [],
                'published_trips': 0,
              },
            ]
          : [],
      'crew': [],
    };
  }
}

class RevisionFixture extends Api {
  Map? submitted;
  @override
  Future<dynamic> request(
    String path, {
    String method = 'GET',
    dynamic data,
    Map<String, String>? headers,
    bool retry = true,
  }) async {
    submitted = Map.from(data as Map);
    throw StateError('Revision save rejected');
  }
}

void main() {
  testWidgets(
    'Timetable revision prefills the original and preserves edits when the server rejects save',
    (tester) async {
      final api = RevisionFixture();
      await tester.pumpWidget(
        MaterialApp(
          home: BusSetupForm(
            api: api,
            kind: 'plan',
            workspace: const {
              'vehicles': [
                {'id': 'bus-id', 'registration': 'TEST-BUS'},
              ],
              'routes': [
                {'id': 'route-id', 'name': 'TEST route'},
              ],
              'crew': [
                {'id': 'crew-id', 'name': 'TEST crew'},
              ],
            },
            previousPlan: const {
              'id': 'original-id',
              'name': 'Morning service',
              'vehicle_id': 'bus-id',
              'route_version_id': 'route-id',
              'crew_id': 'crew-id',
              'departure_time': '09:15:00',
              'start_date': '2030-01-07',
              'end_date': '2030-01-09',
              'weekdays': [1, 3],
              'excluded_dates': ['2030-01-08'],
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Morning service'), findsOneWidget);
      await tester.enterText(
        find.byType(TextFormField).first,
        'Revised service',
      );
      await tester.scrollUntilVisible(
        find.text('Save details'),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.text('Save details'));
      await tester.pumpAndSettle();
      expect(api.submitted?['previousPlanId'], 'original-id');
      expect(api.submitted?['departureTime'], '09:15');
      expect(api.submitted?['weekdays'], [1, 3]);
      expect(api.submitted?['excludedDates'], ['2030-01-08']);
      expect(api.submitted?['name'], 'Revised service');
      expect(find.text('Save details'), findsOneWidget);
    },
  );
  testWidgets(
    'Owner registration persists only after server success and pending owner cannot publish',
    (tester) async {
      final api = OwnerFixture();
      await tester.pumpWidget(MaterialApp(home: BusOwnerScreen(api: api)));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Create owner workspace'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextFormField).first, 'Test owner');
      await tester.tap(find.text('Save details'));
      await tester.pumpAndSettle();
      expect(api.created, true);
      expect(find.text('Add bus'), findsOneWidget);
      await tester.tap(find.text('Timetables'));
      await tester.pumpAndSettle();
      final publish = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'Publish dated trips'),
      );
      expect(publish.onPressed, isNull);
      expect(api.calls.any((p) => p.endsWith('/publish')), false);
    },
  );
  testWidgets('Rejected owner application keeps form and exposes error', (
    tester,
  ) async {
    final api = OwnerFixture()..reject = true;
    await tester.pumpWidget(
      MaterialApp(
        home: BusSetupForm(api: api, kind: 'owner', workspace: const {}),
      ),
    );
    await tester.enterText(find.byType(TextFormField).first, 'Test owner');
    await tester.tap(find.text('Save details'));
    await tester.pumpAndSettle();
    expect(api.created, false);
    expect(find.textContaining('Owner registration failed'), findsOneWidget);
    expect(find.text('Save details'), findsOneWidget);
  });
}
