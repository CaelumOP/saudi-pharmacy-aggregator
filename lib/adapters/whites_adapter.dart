import 'package:dio/dio.dart';
import '../domain/models/pharmacy_offer.dart';
import '../domain/models/promo_deal.dart';
import '../utils/title_sanitizer.dart';
import 'pharmacy_adapter.dart';

/// Adapter for Whites Pharmacy search catalog via Algolia.
///
/// Features direct commercial GTIN barcode indexing, allowing Stage 1 camera scans
/// to immediately retrieve canonical product titles, packaging volumes, and checkout prices.
class WhitesAdapter implements PharmacyAdapter {
  static const String _appId = 'AHYKO0TELX';
  static const String _apiKey = 'b0bbe4982fcf187041bf7bfb53afbfb1';
  static const String _indexName = 'whites_extensions_prod';

  final Dio _dio;

  /// Creates a [WhitesAdapter] instance with an optional mockable [Dio] client.
  WhitesAdapter({Dio? dio}) : _dio = dio ?? Dio();

  @override
  String get storeId => 'whites';

  @override
  String get storeName => 'Whites';

  @override
  String get baseUrl => 'https://www.whites.sa';

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
    final title = (hit['title'] ?? hit['description'] ?? '').toString();
    final sku = (hit['sku'] ?? hit['id'] ?? hit['objectID'] ?? '').toString();
    final imageUrl = hit['image_link']?.toString();
    final productUrl = hit['url']?.toString() ?? 'https://www.whites.sa/en-sa/p/$sku';

    // Parse sale price or regular price (e.g. "8.00 SAR" or "120.75 SAR")
    final priceStr = (hit['sale_price'] ?? hit['price'] ?? '').toString();
    final singlePrice = _parseCurrencyString(priceStr);

    final origPriceStr = (hit['price'] ?? '').toString();
    final origPrice = _parseCurrencyString(origPriceStr);

    // Stock
    final stockVal = int.tryParse((hit['stock'] ?? '0').toString()) ?? 0;
    final inStock = stockVal > 0;

    // SFDA check: medication markers
    final lowerTitle = title.toLowerCase();
    final isSfda = lowerTitle.contains('panadol') ||
        lowerTitle.contains('paracetamol') ||
        lowerTitle.contains('analgesic') ||
        lowerTitle.contains('medication');

    // Base unit normalization
    final unitInfo = TitleSanitizer.extractUnitInfo(title);
    final pricePerBase = TitleSanitizer.calculatePricePerBaseUnit(
      price: singlePrice,
      quantity: unitInfo.quantity,
      metric: unitInfo.metric,
    );

    // Promotional deal math
    final promos = <PromoDeal>[];
    if (origPrice > singlePrice && singlePrice > 0) {
      final discountPct = (((origPrice - singlePrice) / origPrice) * 100).round();
      promos.add(
        PromoDeal.create(
          label: '$discountPct% Off Special',
          requiredQuantity: 1,
          totalCheckoutCost: singlePrice,
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
      isOnlineInStock: inStock,
      multiBuyPromos: promos,
    );
  }

  double _parseCurrencyString(String raw) {
    if (raw.isEmpty) return 0.0;
    final cleaned = raw.replaceAll(RegExp(r'[^\d.]'), '');
    return double.tryParse(cleaned) ?? 0.0;
  }
}
