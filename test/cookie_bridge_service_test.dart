import 'package:cookie_jar/cookie_jar.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pharmacy_app/adapters/network_client_helper.dart';
import 'package:pharmacy_app/services/cookie_bridge_service.dart';

import 'test_helpers.dart';

void main() {
  group('CookieBridgeService Unit Tests', () {
    late CookieBridgeService service;
    late CookieJar testJar;

    setUp(() {
      testJar = CookieJar();
      service = CookieBridgeService.withJar(testJar);
    });

    test('initializes with default mobile User-Agent and allows updating', () {
      expect(service.currentUserAgent, contains('Mozilla/5.0'));
      expect(service.currentUserAgent, contains('Mobile'));

      const customUa = 'CustomChromiumBrowser/130.0.0.0 Mobile';
      service.setUserAgent(customUa);
      expect(service.currentUserAgent, equals(customUa));
    });

    test('saves and loads cookies for target domain', () async {
      final uri = Uri.parse('https://www.al-dawaa.com/occ/v2');
      final cookie = Cookie('session_id', 'xyz123')
        ..domain = 'al-dawaa.com'
        ..path = '/';

      await service.saveCookies(uri, [cookie]);
      final loaded = await service.loadCookies(uri);

      expect(loaded, isNotEmpty);
      expect(loaded.first.name, equals('session_id'));
      expect(loaded.first.value, equals('xyz123'));
    });

    test('detects presence of Cloudflare cf_clearance cookie', () async {
      final uri = Uri.parse('https://www.al-dawaa.com');
      expect(await service.hasCfClearance(uri), isFalse);

      final cfCookie = Cookie('cf_clearance', 'clearance_secret_token_abc')
        ..domain = 'al-dawaa.com'
        ..path = '/';

      await service.saveCookies(uri, [cfCookie]);
      expect(await service.hasCfClearance(uri), isTrue);
    });

    test('clears cookies completely when requested', () async {
      final uri = Uri.parse('https://unitedpharmacy.sa');
      await service.saveCookies(uri, [Cookie('test_token', 'val')]);
      expect(await service.loadCookies(uri), isNotEmpty);

      await service.clearCookies();
      expect(await service.loadCookies(uri), isEmpty);
    });

    test('attaches User-Agent and cookie interceptor to Dio client via NetworkClientHelper', () async {
      final uri = Uri.parse('https://www.al-dawaa.com/test');
      await service.saveCookies(uri, [Cookie('cf_clearance', 'active_token')]);
      service.setUserAgent('MatchedBrowser/124.0');

      final dio = NetworkClientHelper.createDefaultClient(cookieBridge: service);
      RequestOptions? interceptedOptions;

      dio.httpClientAdapter = MockHttpAdapter((options) async {
        interceptedOptions = options;
        return ResponseBody.fromString('{"ok":true}', 200, headers: {
          Headers.contentTypeHeader: [Headers.jsonContentType],
        });
      });

      await dio.get('https://www.al-dawaa.com/test');

      expect(interceptedOptions, isNotNull);
      expect(interceptedOptions!.headers['User-Agent'], equals('MatchedBrowser/124.0'));
      expect(interceptedOptions!.headers['cookie'], contains('cf_clearance=active_token'));
    });
  });
}
