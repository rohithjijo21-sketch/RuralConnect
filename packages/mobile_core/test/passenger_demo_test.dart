import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ruralconnect_mobile/ruralconnect_mobile.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  testWidgets(
    'Passenger demo is clearly labelled and never creates a booking',
    (tester) async {
      tester.view.physicalSize = const Size(430, 1050);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final fontDir = Platform.environment['UI_FONT_DIR'];
      if (fontDir != null) {
        await tester.runAsync(() async {
          for (final family in ['Roboto', 'MaterialIcons']) {
            final files = family == 'Roboto'
                ? ['roboto-regular.ttf', 'roboto-bold.ttf', 'roboto-black.ttf']
                : ['materialicons-regular.otf'];
            final loader = FontLoader(family);
            for (final name in files) {
              loader.addFont(
                File('$fontDir/$name').readAsBytes().then(ByteData.sublistView),
              );
            }
            await loader.load();
          }
        });
      }
      final boundary = GlobalKey();
      final api = DemoApi();
      await tester.pumpWidget(
        RepaintBoundary(
          key: boundary,
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: ThemeData(fontFamily: 'Roboto'),
            home: PassengerScreen(api: api, onConnectionSettings: () {}),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('UI DEMO · Sample schedules only'), findsOneWidget);
      expect(find.text('Find a bus'), findsOneWidget);
      final screenshot = Platform.environment['UI_SCREENSHOT_PATH'];
      if (screenshot != null) {
        await tester.runAsync(() async {
          final image =
              await (boundary.currentContext!.findRenderObject()
                      as RenderRepaintBoundary)
                  .toImage(pixelRatio: 2);
          final data = await image.toByteData(format: ui.ImageByteFormat.png);
          await File(screenshot).writeAsBytes(data!.buffer.asUint8List());
          image.dispose();
        });
      }
      await expectLater(
        api.request(
          '/shared-trips/sample/reservations',
          method: 'POST',
          data: {'seats': 1},
        ),
        throwsStateError,
      );
      await tester.tap(find.text('My trips'));
      await tester.pumpAndSettle();
      expect(find.text('No demo bookings'), findsOneWidget);
      expect(find.textContaining('confirmed reservation'), findsNothing);
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
    },
  );
  test(
    'Phone endpoint validation accepts private Wi-Fi and HTTPS, rejects insecure public hosts',
    () {
      expect(
        Api.validateEndpoint('http://192.168.1.20:3001'),
        'http://192.168.1.20:3001/v1',
      );
      expect(
        Api.validateEndpoint('http://10.64.218.54:3001/v1/'),
        'http://10.64.218.54:3001/v1',
      );
      expect(
        Api.validateEndpoint('https://api.example.com/v1'),
        'https://api.example.com/v1',
      );
      for (final url in [
        'http://example.com',
        'ftp://192.168.1.2',
        'https://user:pass@example.com',
        'https://example.com/v1?token=x',
        'http://172.32.1.2',
        '192.168.1.2:3001',
      ]) {
        expect(() => Api.validateEndpoint(url), throwsFormatException);
      }
    },
  );
}
