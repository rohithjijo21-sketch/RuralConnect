import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ruralconnect_mobile/ruralconnect_mobile.dart';

class BetaFixture extends Api {
  final String role;
  final bool reject;
  final List<String> calls = [];
  BetaFixture(this.role, {this.reject = false});
  @override
  bool get betaAuth => true;
  @override
  Future<void> restore() async {}
  @override
  Future<void> save(Map<String, dynamic> result) async {
    access = result['accessToken'];
  }

  @override
  Future<dynamic> request(
    String path, {
    String method = 'GET',
    dynamic data,
    Map<String, String>? headers,
    bool retry = true,
  }) async {
    calls.add(path);
    if (path == '/auth/beta/redeem') {
      if (reject) {
        throw StateError('Invitation invalid, expired or already used');
      }
      return {
        'accessToken': 'server-issued-session',
        'refreshToken': 'server-refresh',
        'expiresIn': 900,
      };
    }
    if (path == '/me') {
      return {
        'name': 'Beta tester',
        'roles': [role],
        'language': 'en',
      };
    }
    return [];
  }
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  for (final role in ['PASSENGER', 'DRIVER', 'BUS_CREW']) {
    testWidgets('$role beta sign-in uses invitation and never requests SMS', (
      tester,
    ) async {
      final api = BetaFixture(role);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [apiProvider.overrideWithValue(api)],
          child: MaterialApp(
            home: role == 'PASSENGER'
                ? PassengerScreen(api: api, onConnectionSettings: () {})
                : Home(
                    mode: role == 'DRIVER' ? 'driver' : 'bus',
                    title: 'Beta',
                  ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Private invitation code'), findsOneWidget);
      expect(find.text('Configured six-digit OTP'), findsNothing);
      await tester.enterText(find.byType(TextField).at(0), '9000000011');
      await tester.enterText(find.byType(TextField).at(1), 'a' * 43);
      await tester.ensureVisible(find.byType(CheckboxListTile));
      await tester.tap(find.byType(CheckboxListTile));
      await tester.pump();
      final join = find.text('Join private beta');
      await tester.ensureVisible(join);
      await tester.tap(join);
      await tester.pumpAndSettle();
      expect(api.access, 'server-issued-session');
      expect(api.calls, contains('/auth/beta/redeem'));
      expect(api.calls.any((p) => p.contains('/otp/')), false);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }
  test('Rejected invitation never creates a local session', () async {
    final api = BetaFixture('PASSENGER', reject: true);
    await expectLater(
      api.redeemInvite('9000000011', 'a' * 43, true),
      throwsStateError,
    );
    expect(api.access, isNull);
  });
}
