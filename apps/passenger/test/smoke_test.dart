import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ruralconnect_mobile/ruralconnect_mobile.dart';

void main() {
  testWidgets('Authentication gate is shown without a session', (tester) async {
    await tester.pumpWidget(
      const ProviderScope(
        child: RuralConnectApp(
          mode: 'passenger',
          title: 'RuralConnect Passenger',
          color: Colors.green,
        ),
      ),
    );
    await tester.pump();
    expect(find.text('Phone number (+91)'), findsOneWidget);
    expect(find.text('Development sandbox · no SMS sent'), findsOneWidget);
  });
}
