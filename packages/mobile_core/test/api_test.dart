import 'package:flutter_test/flutter_test.dart';
import 'package:ruralconnect_mobile/ruralconnect_mobile.dart';
import 'package:dio/dio.dart';

class DisconnectedApi extends Api {
  bool cleared = false;
  @override
  Future<dynamic> request(
    String path, {
    String method = 'GET',
    dynamic data,
    Map<String, String>? headers,
    bool retry = true,
  }) async {
    throw DioException(
      requestOptions: RequestOptions(path: path),
      type: DioExceptionType.connectionError,
    );
  }

  @override
  Future<void> clear() async {
    access = null;
    cleared = true;
  }
}

void main() {
  test(
    'Offline logout clears local credentials while reporting server revocation failure',
    () async {
      final api = DisconnectedApi()..access = 'fixture-access';
      await expectLater(api.logout(), throwsA(isA<DioException>()));
      expect(api.access, isNull);
      expect(api.cleared, isTrue);
    },
  );
}
