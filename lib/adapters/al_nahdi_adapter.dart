import 'package:dio/dio.dart';
import '../domain/models/pharmacy_offer.dart';
import '../domain/models/promo_deal.dart';
import '../utils/title_sanitizer.dart';
import 'pharmacy_adapter.dart';

/// Adapter for querying the live Al-Nahdi search index via Algolia.
///
/// Communicates directly with the distributed search cluster to achieve low latency
/// while extracting pricing, bundle indicators, and SFDA medication tax exemptions.
class AlNahdiAdapter implements PharmacyAdapter {
  static const String _appId = 'H9X4IH7M99';
  static const String _apiKey = '2bbce1340a1cab2ccebe0307b1310881';
  static const String _indexName = 'prod_en_products';

  final Dio _dio;

  /// Creates an [AlNahdiAdapter] instance with an optional mockable [Dio] client.
  AlNahdiAdapter({Dio? dio}) : _dio = dio ?? Dio();

  @override
  String get storeId => 'al_nahdi';

  @override
  String get storeName => 'Al-Nahdi';

  @override
  String get baseUrl => 'https://www.nahdionline.com';

  @override
  StorePresenceType get presenceType => StorePresenceType.physicalAndOnline;

  @override
  StoreSpecialty get specialty => StoreSpecialty.pharmacyAndCare;

  @override
  Map<String, String> get defaultHeaders => {
        'Content-Type': 'application/json',
        'X-Algolia-Application-Id': _appId,
        'X-Algolia-API-Key': _apiKey,
        'Accept': 'application/json',
      };

  @override
  Future<List<PharmacyOffer>> searchByBarcode(String gtin) async {
    return _queryAlgolia(gtin, limit: 5);
  }

  @override
  Future<List<PharmacyOffer>> searchByKeyword(String query, {int limit = 5}) async {
    return _queryAlgolia(query, limit: limit);
  }

  Future<List<PharmacyOffer>> _queryAlgolia(String query, {required int limit}) async {
    final endpoint = 'https://$_appId-dsn.algolia.net/1/indexes/$_indexName/query';
    final payload = {
      'query': query,
      'hitsPerPage': limit,
    };

    try {
      final response = await _dio.post(
        endpoint,
        data: payload,
        options: Options(headers: defaultHeaders),
      );

      if (response.statusCode != 200 || response.data == null) {
        return const [];
      }

      final data = response.data is Map ? response.data as Map : {};
      final hits = data['hits'] is List ? data['hits'] as List : const [];

      return hits.map((hit) => _parseHit(hit as Map)).toList();
    } catch (_) {
      return const [];
    }
  }

  PharmacyOffer _parseHit(Map hit) {
    final title = (hit['name'] ?? '').toString();
    final sku = (hit['sku'] ?? hit['objectID'] ?? '').toString();
    final imageUrl = hit['image_url']?.toString();
    final productUrl = hit['url']?.toString();

    // Price extraction
    final sarPrice = hit['price'] is Map ? hit['price']['SAR'] : null;
    double singlePrice = 0.0;
    if (sarPrice is Map && sarPrice['default'] != null) {
      final rawPrice = sarPrice['default'];
      singlePrice = rawPrice is num ? rawPrice.toDouble() : double.tryParse(rawPrice.toString()) ?? 0.0;
    }

    // SFDA classification
    final imfClass = (hit['imf_class'] ?? '').toString().toUpperCase();
    final isSfda = imfClass.contains('ANALGESIC') ||
        imfClass.contains('MEDICATION') ||
        imfClass.contains('DRUG') ||
        hit['rx_items'] == 'Yes';

    // Base unit normalization
    final unitInfo = TitleSanitizer.extractUnitInfo(title);
    final pricePerBase = TitleSanitizer.calculatePricePerBaseUnit(
      price: singlePrice,
      quantity: unitInfo.quantity,
      metric: unitInfo.metric,
    );

    // Multi-buy & promotional extraction
    final promos = <PromoDeal>[];
    final bundleSku = hit['bundle_skus']?.toString();
    if (bundleSku != null && bundleSku.isNotEmpty && bundleSku != '0') {
      promos.add(
        PromoDeal.create(
          label: 'Bundle Deal (SKU: $bundleSku)',
          requiredQuantity: 2,
          totalCheckoutCost: singlePrice * 1.5,
        ),
      );
    }

    return PharmacyOffer(
      storeId: storeId,
      pharmacyName: storeName,
      skuOrId: sku,
      productTitle: title,
      imageUrl: imageUrl,
      productUrl: productUrl,
      singleUnitPrice: singlePrice,
      isVatInclusive: true,
      isSfdaRegulated: isSfda,
      unitQuantity: unitInfo.quantity,
      unitMetric: unitInfo.metric,
      pricePerBaseUnit: pricePerBase,
      isOnlineInStock: true,
      multiBuyPromos: promos,
    );
  }
}
