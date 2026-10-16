import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pharmacy_app/adapters/al_dawaa_adapter.dart';
import 'package:pharmacy_app/adapters/al_nahdi_adapter.dart';
import 'package:pharmacy_app/adapters/boots_adapter.dart';
import 'package:pharmacy_app/adapters/golden_scent_adapter.dart';
import 'package:pharmacy_app/adapters/lemon_pharmacy_adapter.dart';
import 'package:pharmacy_app/adapters/nice_one_adapter.dart';
import 'package:pharmacy_app/adapters/pharmacy_adapter.dart';
import 'package:pharmacy_app/adapters/shopify_store_adapter.dart';
import 'package:pharmacy_app/adapters/united_pharmacy_adapter.dart';
import 'package:pharmacy_app/adapters/whites_adapter.dart';
import 'package:pharmacy_app/services/barcode_lookup_service.dart';

import 'test_helpers.dart';

void main() {
  group('AlNahdiAdapter Contract Tests', () {
    test('parses al_nahdi_panadol.json fixture accurately', () async {
      final mockDio = createMockDio(MockHttpAdapter.fromFixture('al_nahdi_panadol.json'));
      final adapter = AlNahdiAdapter(dio: mockDio);

      final offers = await adapter.searchByKeyword('Panadol');
      expect(offers, isNotEmpty);
      expect(offers.length, equals(5));

      final first = offers.first;
      expect(first.storeId, equals('al_nahdi'));
      expect(first.skuOrId, equals('100015980'));
      expect(first.productTitle, equals('Panadol Extra Tablet 24 pcs'));
      expect(first.singleUnitPrice, equals(8.0));
      expect(first.isVatInclusive, isTrue);
      expect(first.isSfdaRegulated, isTrue);
      expect(first.unitQuantity, equals(24.0));
      expect(first.unitMetric, equals('tabs'));
      expect(first.pricePerBaseUnit, equals(3.33));
      expect(first.multiBuyPromos, isNotEmpty);
      expect(first.multiBuyPromos.first.label, contains('Bundle Deal'));
    });

    test('parses al_nahdi_cetaphil.json fixture with volume units', () async {
      final mockDio = createMockDio(MockHttpAdapter.fromFixture('al_nahdi_cetaphil.json'));
      final adapter = AlNahdiAdapter(dio: mockDio);

      final offers = await adapter.searchByKeyword('Cetaphil');
      expect(offers, isNotEmpty);

      final twinPack = offers.first;
      expect(twinPack.productTitle, contains('Cetaphil Moisturizing Cream 566gm'));
      expect(twinPack.singleUnitPrice, equals(164.99));
      expect(twinPack.unitQuantity, equals(566.0));
      expect(twinPack.unitMetric, equals('g'));
      expect(twinPack.isSfdaRegulated, isFalse);
    });

    test('returns empty list for non-indexed barcode lookup (al_nahdi_barcode.json)', () async {
      final mockDio = createMockDio(MockHttpAdapter.fromFixture('al_nahdi_barcode.json'));
      final adapter = AlNahdiAdapter(dio: mockDio);

      final offers = await adapter.searchByBarcode('3499320017046');
      expect(offers, isEmpty);
    });
  });

  group('UnitedPharmacyAdapter Contract Tests', () {
    test('parses united_pharmacy_panadol.json fixture accurately', () async {
      final mockDio = createMockDio(MockHttpAdapter.fromFixture('united_pharmacy_panadol.json'));
      final adapter = UnitedPharmacyAdapter(dio: mockDio);

      final offers = await adapter.searchByKeyword('Panadol');
      expect(offers, isNotEmpty);
      expect(offers.length, equals(5));

      final first = offers.first;
      expect(first.storeId, equals('united_pharmacy'));
      expect(first.productTitle, equals('Panadol Advance 24 Tablets'));
      expect(first.singleUnitPrice, equals(6.95));
      expect(first.isSfdaRegulated, isTrue);
      expect(first.unitQuantity, equals(24.0));
      expect(first.unitMetric, equals('tabs'));
    });

    test('parses united_pharmacy_cetaphil.json with promo discounts', () async {
      final mockDio = createMockDio(MockHttpAdapter.fromFixture('united_pharmacy_cetaphil.json'));
      final adapter = UnitedPharmacyAdapter(dio: mockDio);

      final offers = await adapter.searchByKeyword('Cetaphil');
      expect(offers, isNotEmpty);

      final cleanser = offers.first;
      expect(cleanser.productTitle, equals('Cetaphil Moisturizing Cream 453Gm'));
      expect(cleanser.singleUnitPrice, equals(197.80));
      expect(cleanser.unitQuantity, equals(453.0));
      expect(cleanser.unitMetric, equals('g'));
      expect(cleanser.isSfdaRegulated, isFalse);
    });

    test('returns empty list for non-indexed barcode lookup (united_pharmacy_barcode.json)', () async {
      final mockDio = createMockDio(MockHttpAdapter.fromFixture('united_pharmacy_barcode.json'));
      final adapter = UnitedPharmacyAdapter(dio: mockDio);

      final offers = await adapter.searchByBarcode('3499320017046');
      expect(offers, isEmpty);
    });
  });

  group('WhitesAdapter Contract Tests', () {
    test('resolves barcode via direct GTIN match (whites_barcode.json)', () async {
      final mockDio = createMockDio(MockHttpAdapter.fromFixture('whites_barcode.json'));
      final adapter = WhitesAdapter(dio: mockDio);

      final offers = await adapter.searchByBarcode('6285096003799');
      expect(offers, isNotEmpty);
      expect(offers.length, equals(1));

      final offer = offers.first;
      expect(offer.storeId, equals('whites'));
      expect(offer.productTitle, equals('Panadol Extra 500Mg 24Tablets'));
      expect(offer.singleUnitPrice, equals(8.00));
      expect(offer.unitQuantity, equals(24.0));
      expect(offer.unitMetric, equals('tabs'));
      expect(offer.isOnlineInStock, isTrue);
      expect(offer.isSfdaRegulated, isTrue);
    });

    test('parses whites_panadol.json keyword search accurately', () async {
      final mockDio = createMockDio(MockHttpAdapter.fromFixture('whites_panadol.json'));
      final adapter = WhitesAdapter(dio: mockDio);

      final offers = await adapter.searchByKeyword('Panadol');
      expect(offers, isNotEmpty);
      expect(offers.length, equals(5));

      final first = offers.first;
      expect(first.storeId, equals('whites'));
      expect(first.productTitle, equals('Panadol Extra 500Mg 24Tablets'));
      expect(first.singleUnitPrice, equals(8.00));
      expect(first.isSfdaRegulated, isTrue);
      expect(first.unitQuantity, equals(24.0));
      expect(first.unitMetric, equals('tabs'));
      expect(first.pricePerBaseUnit, equals(3.33));
    });

    test('parses whites_cetaphil.json keyword search with promotions', () async {
      final mockDio = createMockDio(MockHttpAdapter.fromFixture('whites_cetaphil.json'));
      final adapter = WhitesAdapter(dio: mockDio);

      final offers = await adapter.searchByKeyword('Cetaphil');
      expect(offers, isNotEmpty);

      final first = offers.first;
      expect(first.productTitle, equals('Cetaphil Face & Body Moisturizing Cream Jar - 453G'));
      expect(first.singleUnitPrice, equals(148.27));
      expect(first.unitQuantity, equals(453.0));
      expect(first.unitMetric, equals('g'));
    });
  });

  group('AlDawaaAdapter Contract Tests', () {
    test('parses al_dawaa_panadol.json keyword fixture accurately', () async {
      final mockDio = createMockDio(MockHttpAdapter.fromFixture('al_dawaa_panadol.json'));
      final adapter = AlDawaaAdapter(dio: mockDio);

      final offers = await adapter.searchByKeyword('Panadol');
      expect(offers, isNotEmpty);
      expect(offers.length, equals(5));

      final first = offers.first;
      expect(first.storeId, equals('al_dawaa'));
      expect(first.productTitle, contains('Panadol'));
      expect(first.singleUnitPrice, equals(16.05));
      expect(first.isSfdaRegulated, isTrue);
      expect(first.unitQuantity, equals(24.0));
      expect(first.unitMetric, equals('tabs'));
      expect(first.pricePerBaseUnit, equals(6.69));
      expect(first.isOnlineInStock, isTrue);
    });

    test('parses al_dawaa_cetaphil.json keyword fixture with 15% VAT and unit calculation', () async {
      final mockDio = createMockDio(MockHttpAdapter.fromFixture('al_dawaa_cetaphil.json'));
      final adapter = AlDawaaAdapter(dio: mockDio);

      final offers = await adapter.searchByKeyword('Cetaphil');
      expect(offers, isNotEmpty);

      final first = offers.first;
      expect(first.productTitle, equals('Cetaphil, Moisturizing Cream, For Face & Body - 453 G'));
      expect(first.singleUnitPrice, equals(106.09));
      expect(first.unitQuantity, equals(453.0));
      expect(first.unitMetric, equals('g'));
      expect(first.isSfdaRegulated, isFalse);
    });

    test('returns empty list for non-indexed barcode lookup (al_dawaa_barcode.json)', () async {
      final mockDio = createMockDio(MockHttpAdapter.fromFixture('al_dawaa_barcode.json'));
      final adapter = AlDawaaAdapter(dio: mockDio);

      final offers = await adapter.searchByBarcode('3499320017046');
      expect(offers, isEmpty);
    });

    test('detects Cloudflare 403 challenge and throws CloudflareChallengeException', () async {
      final cfHtml = loadFixture('al_dawaa_cloudflare_403.html');
      final mockDio = createMockDio(
        MockHttpAdapter((options) async {
          return ResponseBody.fromString(
            cfHtml,
            403,
            headers: {
              'cf-mitigated': ['challenge'],
              Headers.contentTypeHeader: ['text/html'],
            },
          );
        }),
      );
      final adapter = AlDawaaAdapter(dio: mockDio);

      expect(
        () => adapter.searchByKeyword('Panadol'),
        throwsA(isA<CloudflareChallengeException>().having(
          (e) => e.storeId,
          'storeId',
          equals('al_dawaa'),
        )),
      );
    });
  });

  group('ShopifyStoreAdapter Contract Tests (Seoul House seoulhouse)', () {
    test('cascades from 417 /search/suggest.json to /en/search/suggest.json returning SAR products', () async {
      final mockDio = createMockDio(
        MockHttpAdapter((options) async {
          final uriStr = options.uri.toString();
          if (uriStr.contains('/search/suggest.json') && !uriStr.contains('/en/')) {
            // Emulate Shopify 417 unsupported buyer locale
            return ResponseBody.fromString(
              '{"status":417,"message":"Expectation Failed","description":"Unsupported buyer locale"}',
              417,
              headers: {Headers.contentTypeHeader: [Headers.jsonContentType]},
            );
          }
          if (uriStr.contains('/en/search/suggest.json')) {
            return ResponseBody.fromString(
              '''{
                "resources": {
                  "results": {
                    "products": [
                      {
                        "id": 15662716649820,
                        "title": "Anua Heartleaf 70% Intense Calming Cream 50ml",
                        "price": "95.00",
                        "compare_at_price_max": "120.00",
                        "available": true,
                        "url": "/en/products/heartleaf-70-intense-calming-cream-50ml",
                        "featured_image": {
                          "url": "https://cdn.shopify.com/s/files/anua.png"
                        }
                      }
                    ]
                  }
                }
              }''',
              200,
              headers: {Headers.contentTypeHeader: [Headers.jsonContentType]},
            );
          }
          return ResponseBody.fromString('{}', 404);
        }),
      );

      final adapter = ShopifyStoreAdapter(
        storeId: 'seoulhouse',
        storeName: 'Seoul House',
        domain: 'seoulhouseglobal.com',
        dio: mockDio,
      );

      final offers = await adapter.searchByKeyword('Anua');
      expect(offers, isNotEmpty);
      final first = offers.first;
      expect(first.storeId, equals('seoulhouse'));
      expect(first.pharmacyName, equals('Seoul House'));
      expect(first.productTitle, equals('Anua Heartleaf 70% Intense Calming Cream 50ml'));
      expect(first.singleUnitPrice, equals(95.00));
      expect(first.unitQuantity, equals(50.0));
      expect(first.unitMetric, equals('ml'));
      expect(first.isOnlineInStock, isTrue);
      expect(first.productUrl, equals('https://seoulhouseglobal.com/en/products/heartleaf-70-intense-calming-cream-50ml'));
      expect(first.multiBuyPromos, isNotEmpty);
      expect(first.multiBuyPromos.first.label, contains('Off Sale'));
    });

    test('falls back to /products.json?limit=250 catalogue when predictive search is empty', () async {
      final mockDio = createMockDio(
        MockHttpAdapter((options) async {
          final uriStr = options.uri.toString();
          if (uriStr.contains('/suggest.json')) {
            return ResponseBody.fromString('{"resources":{"results":{"products":[]}}}', 200, headers: {
              Headers.contentTypeHeader: [Headers.jsonContentType],
            });
          }
          if (uriStr.contains('/products.json')) {
            return ResponseBody.fromString(
              '''{
                "products": [
                  {
                    "id": 15859487179100,
                    "title": "SKIN1004 Madagascar Centella Cream 75ml",
                    "handle": "skin1004-madagascar-centella-cream-75ml",
                    "vendor": "SKIN1004",
                    "product_type": "Cream",
                    "body_html": "<p>Soothing cream</p>",
                    "variants": [
                      {
                        "id": 59330635497820,
                        "sku": "8809576260441",
                        "price": "79.00",
                        "compare_at_price": null,
                        "available": true
                      }
                    ],
                    "images": [
                      {"src": "https://cdn.shopify.com/s/files/centella.png"}
                    ]
                  }
                ]
              }''',
              200,
              headers: {Headers.contentTypeHeader: [Headers.jsonContentType]},
            );
          }
          return ResponseBody.fromString('{}', 404);
        }),
      );

      final adapter = ShopifyStoreAdapter(
        storeId: 'seoulhouse',
        storeName: 'Seoul House',
        domain: 'seoulhouseglobal.com',
        dio: mockDio,
      );

      final offers = await adapter.searchByKeyword('SKIN1004');
      expect(offers, isNotEmpty);
      final first = offers.first;
      expect(first.storeId, equals('seoulhouse'));
      expect(first.productTitle, contains('SKIN1004 Madagascar Centella Cream'));
      expect(first.singleUnitPrice, equals(79.00));
      expect(first.skuOrId, equals('8809576260441'));
    });

    test('resolves product barcode via /products.json variant SKU match', () async {
      final mockDio = createMockDio(
        MockHttpAdapter((options) async {
          if (options.uri.toString().contains('/products.json')) {
            return ResponseBody.fromString(
              '''{
                "products": [
                  {
                    "id": 15662717632860,
                    "title": "Peach 77 Niacin Conditioning Milk 150ml",
                    "handle": "peach-77-milk",
                    "variants": [
                      {
                        "sku": "8809640731174",
                        "price": "89.00",
                        "available": true
                      }
                    ],
                    "images": []
                  }
                ]
              }''',
              200,
              headers: {Headers.contentTypeHeader: [Headers.jsonContentType]},
            );
          }
          return ResponseBody.fromString('{}', 404);
        }),
      );

      final adapter = ShopifyStoreAdapter(
        storeId: 'seoulhouse',
        storeName: 'Seoul House',
        domain: 'seoulhouseglobal.com',
        dio: mockDio,
      );

      final barcodeOffers = await adapter.searchByBarcode('8809640731174');
      expect(barcodeOffers, isNotEmpty);
      expect(barcodeOffers.first.skuOrId, equals('8809640731174'));
      expect(barcodeOffers.first.productTitle, contains('Peach 77'));
      expect(barcodeOffers.first.singleUnitPrice, equals(89.00));
    });
  });

  group('BootsAdapter Contract Tests', () {
    test('returns empty list for non-indexed barcode lookup (boots_barcode.json)', () async {
      final mockDio = createMockDio(MockHttpAdapter.fromFixture('boots_barcode.json'));
      final adapter = BootsAdapter(dio: mockDio);

      final offers = await adapter.searchByBarcode('3499320017046');
      expect(offers, isEmpty);
    });

    test('parses boots_panadol.json keyword search accurately', () async {
      final mockDio = createMockDio(MockHttpAdapter.fromFixture('boots_panadol.json'));
      final adapter = BootsAdapter(dio: mockDio);

      final offers = await adapter.searchByKeyword('Panadol');
      expect(offers, isNotEmpty);
      expect(offers.length, equals(5));

      final first = offers.first;
      expect(first.storeId, equals('boots'));
      expect(first.productTitle, contains('Panadol Cold + Flu, 24 Caplets'));
      expect(first.singleUnitPrice, equals(12.30));
      expect(first.unitQuantity, equals(24.0));
      expect(first.unitMetric, equals('tabs'));
    });
  });

  group('NiceOneAdapter Contract Tests', () {
    test('parses niceone_cosrx.html fixture accurately', () async {
      final html = loadFixture('niceone_cosrx.html');
      final mockDio = createMockDio(
        MockHttpAdapter((options) async {
          return ResponseBody.fromString(html, 200, headers: {
            Headers.contentTypeHeader: ['text/html'],
          });
        }),
      );
      final adapter = NiceOneAdapter(dio: mockDio);

      final offers = await adapter.searchByKeyword('COSRX');
      expect(offers, isNotEmpty);
      expect(offers.length, equals(5));

      final first = offers.first;
      expect(first.storeId, equals('nice_one'));
      expect(first.pharmacyName, equals('Nice One'));
      expect(first.productTitle, contains('مستخلص موسين باور 96'));
      expect(first.singleUnitPrice, equals(54.0));
      expect(first.skuOrId, equals('n22459'));
      expect(first.isOnlineInStock, isTrue);
    });
  });

  group('BarcodeLookupService Contract Tests', () {
    test('parses openbeautyfacts_cetaphil.json fixture', () async {
      final mockDio = createMockDio(MockHttpAdapter.fromFixture('openbeautyfacts_cetaphil.json'));
      final service = BarcodeLookupService(dio: mockDio);

      final info = await service.lookup('8906005274106');
      expect(info, isNotNull);
      expect(info!.gtin, equals('8906005274106'));
      expect(info.brand, equals('Cetaphil'));
      expect(info.productName, equals('Gentle Skin Cleanser'));
      expect(info.canonicalTitle, equals('Cetaphil Gentle Skin Cleanser 125ml'));
      expect(info.quantity, equals('125ml'));
    });

    test('parses openfoodfacts_omega3.json fixture', () async {
      final mockDio = createMockDio(MockHttpAdapter.fromFixture('openfoodfacts_omega3.json'));
      final service = BarcodeLookupService(dio: mockDio);

      final info = await service.lookup('733739016522');
      expect(info, isNotNull);
      expect(info!.brand, equals('St-Hubert, St hubert omega 3'));
      expect(info.productName, equals('Oméga 3® Doux'));
    });

    test('parses duckduckgo_cetaphil.html fallback fixture', () async {
      final ddgHtml = loadFixture('duckduckgo_cetaphil.html');
      final mockDio = createMockDio(
        MockHttpAdapter((options) async {
          if (options.uri.host.contains('duckduckgo.com')) {
            return ResponseBody.fromString(ddgHtml, 200, headers: {
              Headers.contentTypeHeader: ['text/html'],
            });
          }
          return ResponseBody.fromString('{}', 404);
        }),
      );
      final service = BarcodeLookupService(dio: mockDio);

      final info = await service.lookup('3499320017046');
      expect(info, isNotNull);
      expect(info!.productName, equals('Cetaphil Gentle Skin Cleanser 473 ml'));
      expect(info.canonicalTitle, contains('Cetaphil Gentle Skin Cleanser 473 ml'));
      expect(info.quantity, contains('473 ml'));
    });
  });

  group('LemonPharmacyAdapter Contract Tests', () {
    test('parses lemon_panadol.json Algolia fixture accurately', () async {
      final mockDio = createMockDio(MockHttpAdapter.fromFixture('lemon_panadol.json'));
      final adapter = LemonPharmacyAdapter(dio: mockDio);

      final offers = await adapter.searchByKeyword('Panadol');
      expect(offers, isNotEmpty);
      expect(offers.length, equals(2));

      final first = offers.first;
      expect(first.storeId, equals('lemon'));
      expect(first.pharmacyName, equals('Lemon Pharmacy'));
      expect(first.skuOrId, equals('2474'));
      expect(first.productTitle, equals('Panadol Advance 24 Tablets'));
      expect(first.singleUnitPrice, equals(6.05));
      expect(first.unitQuantity, equals(24.0));
      expect(first.unitMetric, equals('tabs'));
      expect(first.isSfdaRegulated, isFalse);
    });
  });

  group('GoldenScentAdapter Contract Tests', () {
    test('parses goldenscent_perfume.html fixture accurately', () async {
      final html = loadFixture('goldenscent_perfume.html');
      final mockDio = createMockDio(
        MockHttpAdapter((options) async {
          return ResponseBody.fromString(html, 200, headers: {
            Headers.contentTypeHeader: ['text/html'],
          });
        }),
      );
      final adapter = GoldenScentAdapter(dio: mockDio);

      final offers = await adapter.searchByKeyword('Kaaf');
      expect(offers, isNotEmpty);
      expect(offers.length, equals(1));

      final first = offers.first;
      expect(first.storeId, equals('golden_scent'));
      expect(first.pharmacyName, equals('Golden Scent'));
      expect(first.skuOrId, equals('65088'));
      expect(first.productTitle, equals('Ahmed Perfume Kaaf EDP 100ml'));
      expect(first.singleUnitPrice, equals(110.0));
      expect(first.unitQuantity, equals(100.0));
      expect(first.unitMetric, equals('ml'));
      expect(first.imageUrl, contains('goldenscent.com'));
    });
  });
}
