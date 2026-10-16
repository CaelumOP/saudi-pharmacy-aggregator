import 'dart:convert';
import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pharmacy_app/services/smart_query_corrector.dart';

class MockDioAdapter implements HttpClientAdapter {
  final Future<ResponseBody> Function(RequestOptions options) handler;

  MockDioAdapter(this.handler);

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) {
    return handler(options);
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  group('SmartQueryCorrector - Layer A Arabic Orthography & Phonetics', () {
    final corrector = SmartQueryCorrector();

    test('normalizes Arabic alef variants, taa marbuta, alif maqsura, and diacritics', () {
      // أ / إ / آ -> ا
      expect(SmartQueryCorrector.normalizeArabicOrthography('أدول'), equals('ادول'));
      expect(SmartQueryCorrector.normalizeArabicOrthography('إيبوبروفين'), equals('ايبوبروفين'));
      expect(SmartQueryCorrector.normalizeArabicOrthography('آسبرين'), equals('اسبرين'));

      // ة -> ه, ى -> ي
      expect(SmartQueryCorrector.normalizeArabicOrthography('عناية'), equals('عنايه'));
      expect(SmartQueryCorrector.normalizeArabicOrthography('مرضى'), equals('مرضي'));

      // Strips tatweel and harakat
      expect(SmartQueryCorrector.normalizeArabicOrthography('بَنَـادُولْ'), equals('بنادول'));
    });

    test('corrects common Arabic phonetic misspellings to canonical terms', () {
      expect(corrector.correctLocalOnly('بندول'), equals('بنادول'));
      expect(corrector.correctLocalOnly('سيتافل'), equals('سيتافيل'));
      expect(corrector.correctLocalOnly('ستافيل'), equals('سيتافيل'));
      expect(corrector.correctLocalOnly('كوزركس'), equals('كوسركس'));
      expect(corrector.correctLocalOnly('لاروش بوزي'), equals('لاروش بوزيه'));
      expect(corrector.correctLocalOnly('سيراف'), equals('سيرافي'));
      expect(corrector.correctLocalOnly('يوسرين'), equals('يوسيرين'));
      expect(corrector.correctLocalOnly('بايوديرما'), equals('بيوديرما'));
    });
  });

  group('SmartQueryCorrector - Layer A English Local Fuzzy Dictionary', () {
    final corrector = SmartQueryCorrector();

    test('corrects 1-character typos in brand names', () {
      expect(corrector.correctLocalOnly('panadool'), equals('Panadol'));
      expect(corrector.correctLocalOnly('ceravie'), equals('CeraVe'));
      expect(corrector.correctLocalOnly('bioderma'), equals('Bioderma'));
      expect(corrector.correctLocalOnly('eucerine'), equals('Eucerin'));
    });

    test('corrects 2-character typos in longer brand names', () {
      expect(corrector.correctLocalOnly('cetafil'), equals('Cetaphil'));
      expect(corrector.correctLocalOnly('cosrex'), equals('COSRX'));
      expect(corrector.correctLocalOnly('bepanthenn'), equals('Bepanthen'));
    });

    test('corrects multi-word query typos (brand + form)', () {
      expect(corrector.correctLocalOnly('cetafil clenser'), equals('Cetaphil Cleanser'));
      expect(corrector.correctLocalOnly('panadool extra'), equals('Panadol Extra'));
      expect(corrector.correctLocalOnly('cosrex snail'), equals('COSRX Snail'));
    });

    test('leaves correctly spelled queries untouched', () {
      expect(corrector.correctLocalOnly('Panadol Extra'), equals('Panadol Extra'));
      expect(corrector.correctLocalOnly('Cetaphil Cleanser'), equals('Cetaphil Cleanser'));
      expect(corrector.correctLocalOnly('COSRX'), equals('COSRX'));
    });
  });

  group('SmartQueryCorrector - Layer B Google Suggest & Fallbacks', () {
    test('uses Google Suggest response to correct phrase-level typo', () async {
      final dio = Dio();
      dio.httpClientAdapter = MockDioAdapter((options) async {
        if (options.queryParameters['q'] == 'la rosh posay') {
          final payload = jsonEncode([
            'la rosh posay',
            ['la roche posay', 'la roche posay effaclar', 'la roche posay cleanser'],
          ]);
          return ResponseBody.fromString(
            payload,
            200,
            headers: {
              Headers.contentTypeHeader: [Headers.jsonContentType],
            },
          );
        }
        return ResponseBody.fromString('[]', 200);
      });

      final corrector = SmartQueryCorrector(dio: dio);
      final result = await corrector.correctQuery('la rosh posay');

      expect(result.wasCorrected, isTrue);
      expect(result.correctedQuery, equals('la roche posay'));
      expect(result.suggestions, contains('la roche posay'));
    });

    test('falls back gracefully on network error or timeout', () async {
      final dio = Dio();
      dio.httpClientAdapter = MockDioAdapter((options) async {
        throw DioException(
          requestOptions: options,
          error: 'Network unreachable',
          type: DioExceptionType.connectionError,
        );
      });

      final corrector = SmartQueryCorrector(dio: dio);
      // "cetafil clenser" should still be corrected by Layer A local dictionary
      final result = await corrector.correctQuery('cetafil clenser');

      expect(result.wasCorrected, isTrue);
      expect(result.correctedQuery, equals('Cetaphil Cleanser'));
    });
  });

  group('SmartQueryCorrector - Autocomplete Suggestions Generation', () {
    test('blends local prefix suggestions with external suggestions', () async {
      final dio = Dio();
      dio.httpClientAdapter = MockDioAdapter((options) async {
        final payload = jsonEncode([
          'ceta',
          ['cetaphil moisturizing cream', 'cetaphil gentle cleanser'],
        ]);
        return ResponseBody.fromString(
          payload,
          200,
          headers: {
            Headers.contentTypeHeader: [Headers.jsonContentType],
          },
        );
      });

      final corrector = SmartQueryCorrector(dio: dio);
      final suggestions = await corrector.getSuggestions('ceta');

      expect(suggestions, isNotEmpty);
      expect(suggestions.any((s) => s.toLowerCase().contains('cetaphil')), isTrue);
    });

    test('returns local brand completions instantly even without network', () async {
      final dio = Dio();
      dio.httpClientAdapter = MockDioAdapter((options) async {
        throw DioException(
          requestOptions: options,
          error: 'Offline',
          type: DioExceptionType.connectionError,
        );
      });

      final corrector = SmartQueryCorrector(dio: dio);
      final suggestions = await corrector.getSuggestions('pana');

      expect(suggestions, contains('panadol'));
    });
  });
}
