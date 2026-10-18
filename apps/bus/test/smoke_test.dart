import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ruralconnect_mobile/ruralconnect_mobile.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
  });
  testWidgets('Authentication gate is shown without a session', (tester) async {
    await tester.pumpWidget(
      const ProviderScope(
        child: RuralConnectApp(
          mode: 'bus',
          title: 'RuralConnect Bus',
          color: Colors.green,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Connect to your test server'), findsOneWidget);
    expect(find.text('Server address'), findsOneWidget);
  });
}
