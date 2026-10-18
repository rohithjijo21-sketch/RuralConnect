import 'dart:async';
import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

class Api {
  final Dio dio;
  final FlutterSecureStorage storage;
  String? access;
  bool endpointConfirmed = false;
  Future<void>? _refreshing;
  bool get isDemo => false;
  Api({Dio? client, FlutterSecureStorage? secureStorage})
    : dio =
          client ??
          Dio(
            BaseOptions(
              baseUrl: const String.fromEnvironment(
                'API_URL',
                defaultValue: '',
              ),
              connectTimeout: const Duration(seconds: 10),
              receiveTimeout: const Duration(seconds: 15),
            ),
          ),
      storage = secureStorage ?? const FlutterSecureStorage();
  Future<void> restore() async {
    final p = await SharedPreferences.getInstance();
    final saved = p.getString('api_endpoint');
    if (saved != null) {
      dio.options.baseUrl = saved;
      endpointConfirmed = true;
    }
    access = await storage.read(key: 'access');
  }

  static String validateEndpoint(String value) {
    final uri = Uri.tryParse(value.trim());
    if (uri == null ||
        !uri.hasAuthority ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty ||
        uri.hasQuery ||
        uri.hasFragment) {
      throw const FormatException(
        'Enter a server address such as http://192.168.1.10:3001/v1',
      );
    }
    final parts = uri.host.split('.').map(int.tryParse).toList();
    final privateV4 =
        parts.length == 4 &&
        parts.every((n) => n != null && n >= 0 && n <= 255) &&
        (parts[0] == 10 ||
            parts[0] == 127 ||
            (parts[0] == 192 && parts[1] == 168) ||
            (parts[0] == 172 && parts[1]! >= 16 && parts[1]! <= 31));
    if (uri.scheme != 'https' &&
        !(uri.scheme == 'http' && (privateV4 || uri.host == 'localhost'))) {
      throw const FormatException(
        'Use HTTPS for a hosted server. HTTP is allowed only on a private test network.',
      );
    }
    final path = uri.path.replaceFirst(RegExp(r'/+$'), '');
    if (path.isNotEmpty && path != '/v1') {
      throw const FormatException('The API address must end in /v1');
    }
    return uri.replace(path: '/v1').toString();
  }

  Future<void> connect(String value) async {
    final url = validateEndpoint(value);
    final probe = Dio(
      BaseOptions(
        baseUrl: url,
        connectTimeout: const Duration(seconds: 8),
        receiveTimeout: const Duration(seconds: 10),
      ),
    );
    try {
      final h = await probe.get('/health');
      final r = await probe.get('/ready');
      if (h.data is! Map ||
          h.data['status'] != 'ok' ||
          r.data is! Map ||
          r.data['status'] != 'ready') {
        throw StateError('This address is not a ready RuralConnect API.');
      }
    } finally {
      probe.close();
    }
    if (dio.options.baseUrl != url) {
      if (access != null) {
        try {
          await logout();
        } catch (_) {
          await clear();
        }
      } else {
        await clear();
      }
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('bus_cache');
    }
    dio.options.baseUrl = url;
    final p = await SharedPreferences.getInstance();
    await p.setString('api_endpoint', url);
    endpointConfirmed = true;
  }

  Future<void> save(Map<String, dynamic> data) async {
    await storage.write(key: 'refresh', value: data['refreshToken'] as String);
    await storage.write(key: 'access', value: data['accessToken'] as String);
    access = data['accessToken'] as String;
  }

  Future<void> clear() async {
    access = null;
    await storage.delete(key: 'refresh');
    await storage.delete(key: 'access');
  }

  Future<void> _refresh() async {
    final refresh = await storage.read(key: 'refresh');
    if (refresh == null) throw StateError('Please sign in again');
    try {
      final r = await dio.post(
        '/auth/refresh',
        data: {'refreshToken': refresh},
      );
      await save(Map<String, dynamic>.from(r.data as Map));
    } catch (_) {
      await clear();
      rethrow;
    }
  }

  Future<dynamic> request(
    String path, {
    String method = 'GET',
    dynamic data,
    Map<String, String>? headers,
    bool retry = true,
  }) async {
    try {
      return (await dio.request(
        path,
        data: data,
        options: Options(
          method: method,
          headers: {
            if (access != null) 'Authorization': 'Bearer $access',
            ...?headers,
          },
        ),
      )).data;
    } on DioException catch (e) {
      if (e.response?.statusCode == 401 && retry && access != null) {
        _refreshing ??= _refresh().whenComplete(() => _refreshing = null);
        await _refreshing;
        return request(
          path,
          method: method,
          data: data,
          headers: headers,
          retry: false,
        );
      }
      rethrow;
    }
  }

  Future<void> logout() async {
    try {
      await request('/auth/logout', method: 'POST');
    } finally {
      await clear();
    }
  }
}

String readableError(Object error) {
  if (error is DioException) {
    final data = error.response?.data;
    if (data is Map && data['message'] != null) {
      return data['message'].toString();
    }
    return 'Network unavailable. Nothing has been confirmed. Try again.';
  }
  return error.toString();
}
