import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pharmacy_app/adapters/al_dawaa_adapter.dart';
import 'package:pharmacy_app/adapters/al_nahdi_adapter.dart';
import 'package:pharmacy_app/adapters/united_pharmacy_adapter.dart';
import 'package:pharmacy_app/adapters/whites_adapter.dart';
import 'package:pharmacy_app/services/pharmacy_aggregator_orchestrator.dart';

import 'test_helpers.dart';

void main() {
  group('PharmacyAggregatorOrchestrator - Keyword Search', () {
    test('emits loading and completed states asynchronously across all stores', () async {
      final nahdiDio = createMockDio(MockHttpAdapter.fromFixture('al_nahdi_panadol.json'));
      final unitedDio = createMockDio(MockHttpAdapter.fromFixture('united_pharmacy_panadol.json'));
      final whitesDio = createMockDio(MockHttpAdapter.fromFixture('whites_panadol.json'));
      final dawaaDio = createMockDio(MockHttpAdapter.fromFixture('al_dawaa_panadol.json'));

      final orchestrator = PharmacyAggregatorOrchestrator(
        adapters: [
          AlNahdiAdapter(dio: nahdiDio),
          UnitedPharmacyAdapter(dio: unitedDio),
          WhitesAdapter(dio: whitesDio),
          AlDawaaAdapter(dio: dawaaDio),
        ],
      );

      final events = <StoreSearchResult>[];
      await for (final event in orchestrator.searchByKeyword('Panadol')) {
        events.add(event);
      }

      // Check all 4 stores emitted loading
      final loadingStores = events.where((e) => e.status == StoreLaneStatus.loading).map((e) => e.storeId).toSet();
      expect(loadingStores, containsAll(['al_nahdi', 'united_pharmacy', 'whites', 'al_dawaa']));

      // Check all 4 stores emitted completed with offers
      final completedEvents = events.where((e) => e.status == StoreLaneStatus.completed).toList();
      expect(completedEvents.length, equals(4));

      for (final event in completedEvents) {
        expect(event.offers, isNotEmpty, reason: '${event.storeId} should contain offers');
        expect(event.isFallbackSearch, isFalse);
      }
    });

    test('propagates Cloudflare Turnstile challenge as challengeRequired status', () async {
      final nahdiDio = createMockDio(MockHttpAdapter.fromFixture('al_nahdi_panadol.json'));
      final cfHtml = loadFixture('al_dawaa_cloudflare_403.html');
      final dawaaDio = createMockDio(
        MockHttpAdapter.jsonResponse(
          cfHtml,
          statusCode: 403,
          headers: {'cf-mitigated': ['challenge']},
        ),
      );

      final orchestrator = PharmacyAggregatorOrchestrator(
        adapters: [
          AlNahdiAdapter(dio: nahdiDio),
          AlDawaaAdapter(dio: dawaaDio),
        ],
      );

      final events = <StoreSearchResult>[];
      await for (final event in orchestrator.searchByKeyword('Panadol')) {
        events.add(event);
      }

      final dawaaEvent = events.firstWhere(
        (e) => e.storeId == 'al_dawaa' && e.status == StoreLaneStatus.challengeRequired,
      );
      expect(dawaaEvent.challengeUrl, equals('https://www.al-dawaa.com'));

      final nahdiCompleted = events.firstWhere(
        (e) => e.storeId == 'al_nahdi' && e.status == StoreLaneStatus.completed,
      );
      expect(nahdiCompleted.offers, isNotEmpty);
    });
  });

  group('PharmacyAggregatorOrchestrator - Two-Stage Barcode Cascade', () {
    test('executes Stage 1 barcode lookup and Stage 3 fallback cascade using Stage 2 sanitized title', () async {
      // Setup:
      // Whites matches GTIN '6285096003799' directly in Stage 1 with 'Panadol Extra 500Mg 24Tablets'
      // Nahdi, United, and Al-Dawaa return 0 hits for the barcode in Stage 1,
      // but return hits when queried by keyword in Stage 3!
      final whitesDio = createMockDio(MockHttpAdapter((options) async {
        return MockHttpAdapter.fromFixture('whites_barcode.json').fetch(options, null, null);
      }));

      final nahdiDio = createMockDio(MockHttpAdapter((options) async {
        final query = (options.data as Map?)?['query']?.toString();
        if (query == '6285096003799') {
          return MockHttpAdapter.fromFixture('al_nahdi_barcode.json').fetch(options, null, null);
        } else {
          // Fallback keyword query
          return MockHttpAdapter.fromFixture('al_nahdi_panadol.json').fetch(options, null, null);
        }
      }));

      final unitedDio = createMockDio(MockHttpAdapter((options) async {
        final query = (options.data as Map?)?['query']?.toString();
        if (query == '6285096003799') {
          return MockHttpAdapter.fromFixture('united_pharmacy_barcode.json').fetch(options, null, null);
        } else {
          // Fallback keyword query
          return MockHttpAdapter.fromFixture('united_pharmacy_panadol.json').fetch(options, null, null);
        }
      }));

      final dawaaDio = createMockDio(MockHttpAdapter((options) async {
        final query = options.queryParameters['query']?.toString();
        if (query == '6285096003799') {
          return MockHttpAdapter.fromFixture('al_dawaa_barcode.json').fetch(options, null, null);
        } else {
          // Fallback keyword query
          return MockHttpAdapter.fromFixture('al_dawaa_panadol.json').fetch(options, null, null);
        }
      }));

      final orchestrator = PharmacyAggregatorOrchestrator(
        adapters: [
          WhitesAdapter(dio: whitesDio),
          AlNahdiAdapter(dio: nahdiDio),
          UnitedPharmacyAdapter(dio: unitedDio),
          AlDawaaAdapter(dio: dawaaDio),
        ],
      );

      final events = <StoreSearchResult>[];
      await for (final event in orchestrator.searchByBarcode('6285096003799')) {
        events.add(event);
      }

      // 1. Whites must have completed in Stage 1 without fallback
      final whitesResult = events.firstWhere(
        (e) => e.storeId == 'whites' && e.status == StoreLaneStatus.completed,
      );
      expect(whitesResult.offers, isNotEmpty);
      expect(whitesResult.isFallbackSearch, isFalse);
      expect(whitesResult.offers.first.isFallbackMatch, isFalse);
      expect(whitesResult.offers.first.productTitle, equals('Panadol Extra 500Mg 24Tablets'));

      // 2. Nahdi, United, and Al-Dawaa must have cascaded to Stage 3 with isFallbackSearch = true
      final fallbackResults = events
          .where((e) => e.status == StoreLaneStatus.completed && e.isFallbackSearch)
          .toList();
      expect(fallbackResults.length, equals(3));

      final fallbackStoreIds = fallbackResults.map((e) => e.storeId).toSet();
      expect(fallbackStoreIds, equals({'al_nahdi', 'united_pharmacy', 'al_dawaa'}));

      // Verify all offers from fallback have isFallbackMatch = true
      for (final result in fallbackResults) {
        expect(result.offers, isNotEmpty, reason: '${result.storeId} fallback should yield offers');
        for (final offer in result.offers) {
          expect(offer.isFallbackMatch, isTrue, reason: 'Offer from ${result.storeId} must have isFallbackMatch=true');
        }
      }
    });

    test('handles unknown barcode where all stores return 0 hits cleanly', () async {
      final nahdiDio = createMockDio(MockHttpAdapter.fromFixture('al_nahdi_barcode.json'));
      final unitedDio = createMockDio(MockHttpAdapter.fromFixture('united_pharmacy_barcode.json'));
      final dawaaDio = createMockDio(MockHttpAdapter.fromFixture('al_dawaa_barcode.json'));

      final orchestrator = PharmacyAggregatorOrchestrator(
        adapters: [
          AlNahdiAdapter(dio: nahdiDio),
          UnitedPharmacyAdapter(dio: unitedDio),
          AlDawaaAdapter(dio: dawaaDio),
        ],
      );

      final events = <StoreSearchResult>[];
      await for (final event in orchestrator.searchByBarcode('9999999999999')) {
        events.add(event);
      }

      final completedEvents = events.where((e) => e.status == StoreLaneStatus.completed).toList();
      expect(completedEvents.length, equals(3));
      for (final event in completedEvents) {
        expect(event.offers, isEmpty);
      }
    });

    test('Stage 3 fallback prioritizes offers matching target size (within ±10% tolerance) to rank first', () async {
      // Whites matches barcode directly with 473ml Cetaphil
      final whitesDio = createMockDio(MockHttpAdapter((options) async {
        return ResponseBody.fromString(
          '''{
            "hits": [{
              "id": "65061",
              "title": "Cetaphil Gentle Skin Cleanser 473 Ml",
              "price": "120.75 SAR",
              "gtin": "3499320017046"
            }]
          }''',
          200,
          headers: {Headers.contentTypeHeader: [Headers.jsonContentType]},
        );
      }));

      // Al-Dawaa fallback returns a list with 118ml first, then 473ml second
      final dawaaDio = createMockDio(MockHttpAdapter((options) async {
        if (options.queryParameters['query'] == '3499320017046') {
          return MockHttpAdapter.fromFixture('al_dawaa_barcode.json').fetch(options, null, null);
        }
        return ResponseBody.fromString(
          '''{
            "products": [
              {
                "code": "103075",
                "name": "Cetaphil Gentle Skin Cleanser 118ml",
                "price": {"value": 29.90}
              },
              {
                "code": "103851",
                "name": "Cetaphil Gentle Skin Cleanser 473ml",
                "price": {"value": 104.65}
              }
            ]
          }''',
          200,
          headers: {Headers.contentTypeHeader: [Headers.jsonContentType]},
        );
      }));

      final orchestrator = PharmacyAggregatorOrchestrator(
        adapters: [
          WhitesAdapter(dio: whitesDio),
          AlDawaaAdapter(dio: dawaaDio),
        ],
      );

      final events = <StoreSearchResult>[];
      await for (final event in orchestrator.searchByBarcode('3499320017046')) {
        events.add(event);
      }

      final dawaaResult = events.firstWhere(
        (e) => e.storeId == 'al_dawaa' && e.status == StoreLaneStatus.completed,
      );

      // Al-Dawaa originally returned 118ml first, but because target is 473ml, 473ml must be ranked first!
      expect(dawaaResult.offers, isNotEmpty);
      expect(dawaaResult.offers.first.unitQuantity, equals(473.0));
      expect(dawaaResult.offers.first.unitMetric, equals('ml'));
      expect(dawaaResult.offers.first.singleUnitPrice, equals(104.65));
    });

    test('proves decoupled enabledStoreIds: disabled store resolves barcode silently without emitting lane results', () async {
      // Whites has barcode hit for '3499320017046'
      final whitesDio = createMockDio(MockHttpAdapter.fromFixture('whites_barcode.json'));

      // Al-Nahdi has no barcode hit, but matches keyword fallback
      final nahdiDio = createMockDio(MockHttpAdapter((options) async {
        final query = (options.data as Map?)?['query']?.toString();
        if (query == '3499320017046') {
          return MockHttpAdapter.fromFixture('al_nahdi_barcode.json').fetch(options, null, null);
        } else {
          return MockHttpAdapter.fromFixture('al_nahdi_panadol.json').fetch(options, null, null);
        }
      }));

      final orchestrator = PharmacyAggregatorOrchestrator(
        adapters: [
          WhitesAdapter(dio: whitesDio),
          AlNahdiAdapter(dio: nahdiDio),
        ],
      );

      // Disable Whites by only enabling Al-Nahdi
      orchestrator.enabledStoreIds = {'al_nahdi'};

      final events = <StoreSearchResult>[];
      await for (final event in orchestrator.searchByBarcode('3499320017046')) {
        events.add(event);
      }

      // Whites must NOT be present in emitted events
      final whitesEvents = events.where((e) => e.storeId == 'whites').toList();
      expect(whitesEvents, isEmpty, reason: 'Whites is disabled in enabledStoreIds and should not emit events');

      // Al-Nahdi must have received the resolved product title from Whites silently and completed with offers
      final nahdiEvents = events.where((e) => e.storeId == 'al_nahdi').toList();
      expect(nahdiEvents, isNotEmpty);
      final nahdiCompleted = nahdiEvents.firstWhere((e) => e.status == StoreLaneStatus.completed);
      expect(nahdiCompleted.offers, isNotEmpty);
      expect(nahdiCompleted.isFallbackSearch, isTrue);
    });
  });
}
