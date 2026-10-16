import 'package:dio/dio.dart';
import '../domain/models/pharmacy_offer.dart';
import '../domain/models/promo_deal.dart';
import '../utils/title_sanitizer.dart';
import 'pharmacy_adapter.dart';

/// Adapter for querying United Pharmacy search catalog via Algolia.
///
/// Handles Magento 2 attribute structures, stock flags, promotional labels,
/// and SFDA category classification while strictly ignoring Maksab loyalty points.
class UnitedPharmacyAdapter implements PharmacyAdapter {
  static const String _appId = 'Y1GOQ9DTV8';
  static const String _apiKey = 'NGFkYzM5MDgzYjA0YmI2YzdlYjk4YjIwNDFjZjQzZTg2ZDQ4M2Q0ZGM5ZTVjYTgxYTNjZWRlMjllZDg0YTg3Y3RhZ0ZpbHRlcnM9';
  static const String _indexName = 'unitedpharmacy_liveen_products';

  final Dio _dio;

  /// Creates a [UnitedPharmacyAdapter] instance with an optional mockable [Dio] client.
  UnitedPharmacyAdapter({Dio? dio}) : _dio = dio ?? Dio();

  @override
  String get storeId => 'united_pharmacy';

  @override
  String get storeName => 'United Pharmacy';

  @override
  String get baseUrl => 'https://unitedpharmacy.sa';

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
    final imageUrl = (hit['image_url'] ?? hit['thumbnail_url'])?.toString();
    final productUrl = hit['url']?.toString();

    // Price extraction
    final sarPrice = hit['price'] is Map ? hit['price']['SAR'] : null;
    double singlePrice = 0.0;
    if (sarPrice is Map && sarPrice['default'] != null) {
      final rawPrice = sarPrice['default'];
      singlePrice = rawPrice is num ? rawPrice.toDouble() : double.tryParse(rawPrice.toString()) ?? 0.0;
    }

    // In stock status
    final inStock = hit['in_stock'] == 1 || hit['custom_in_stock'] == true;

    // SFDA classification: level0: ["Medications"]
    final categories = hit['categories'] is Map ? hit['categories']['level0'] : null;
    final isSfda = categories is List && categories.any((cat) => cat.toString().contains('Medications'));

    // Base unit normalization
    final unitInfo = TitleSanitizer.extractUnitInfo(title);
    final pricePerBase = TitleSanitizer.calculatePricePerBaseUnit(
      price: singlePrice,
      quantity: unitInfo.quantity,
      metric: unitInfo.metric,
    );

    // Promotional math
    final promos = <PromoDeal>[];
    final offerLabel = (hit['offer_label'] ?? '').toString().trim();
    if (offerLabel.isNotEmpty) {
      if (offerLabel.contains('1+1') || offerLabel.toLowerCase().contains('buy 1 get 1')) {
        promos.add(
          PromoDeal(
            label: offerLabel,
            requiredQuantity: 2,
            totalCheckoutCost: singlePrice,
            effectiveUnitPrice: double.parse((singlePrice / 2).toStringAsFixed(2)),
          ),
        );
      } else {
        promos.add(
          PromoDeal.create(
            label: offerLabel,
            requiredQuantity: 1,
            totalCheckoutCost: singlePrice,
          ),
        );
      }
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
      isOnlineInStock: inStock,
      multiBuyPromos: promos,
    );
  }
}
