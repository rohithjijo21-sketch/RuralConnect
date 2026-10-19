import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ruralconnect_mobile/ruralconnect_mobile.dart';

void main() {
  testWidgets(
    'Driver preview shows sample auto without issuing a session or accepting mutations',
    (tester) async {
      final api = DemoApi(mode: 'driver');
      await tester.pumpWidget(
        ProviderScope(
          overrides: [apiProvider.overrideWithValue(api)],
          child: const MaterialApp(
            home: Home(mode: 'driver', title: 'RuralConnect Driver'),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('DEMO AUTO 001'), findsOneWidget);
      expect(find.textContaining('UI DEMO'), findsOneWidget);
      expect(find.text('Request sandbox challenge'), findsNothing);
      expect(api.access, isNull);
      await expectLater(
        api.request(
          '/driver/availability',
          method: 'POST',
          data: {'online': true},
        ),
        throwsStateError,
      );
      final manage = find.text('Manage share-auto trips');
      await tester.ensureVisible(manage);
      await tester.tap(manage);
      await tester.pumpAndSettle();
      expect(find.text('Your services'), findsOneWidget);
      expect(find.textContaining('Kothamangalam'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
