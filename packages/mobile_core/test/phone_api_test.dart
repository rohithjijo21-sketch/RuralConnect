import 'dart:convert';
import 'dart:io';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ruralconnect_mobile/ruralconnect_mobile.dart';

void main() {
  test(
    'Dio mobile client connects, signs in and reads live test-server schedules',
    () async {
      final config =
          jsonDecode(
                await File(
                  Platform.environment['PHONE_CONFIG_PATH']!,
                ).readAsString(),
              )
              as Map;
      SharedPreferences.setMockInitialValues({});
      FlutterSecureStorage.setMockInitialValues({});
      final api = Api();
      await api.connect(Platform.environment['PHONE_API_URL']!);
      expect(api.endpointConfirmed, isTrue);
      final challenge = await api.request(
        '/auth/otp/request',
        method: 'POST',
        data: {'phone': '+919000000001'},
        headers: {'X-Sandbox-Key': config['sandboxKey'].toString()},
      );
      final session = await api.request(
        '/auth/otp/verify',
        method: 'POST',
        data: {
          'challengeId': challenge['challengeId'],
          'code': config['otp'],
          'consentVersion': 'phone-test-v1',
        },
      );
      await api.save(Map<String, dynamic>.from(session as Map));
      final me = await api.request('/me') as Map;
      expect(me['roles'], contains('PASSENGER'));
      final now = DateTime.now().toUtc().add(
        const Duration(hours: 5, minutes: 30),
      );
      final day =
          '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
      final trips = await api.request('/bus/trips?date=$day') as List;
      expect(trips, isNotEmpty);
      expect(trips.first['lat'], isNull);
      expect(await api.request('/me/reservations'), isList);
      await api.logout();
      expect(api.access, isNull);
    },
    skip: Platform.environment['RUN_PHONE_API_TESTS'] != '1',
  );
}
