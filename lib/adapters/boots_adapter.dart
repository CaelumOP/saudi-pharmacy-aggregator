import 'package:dio/dio.dart';
import '../domain/models/pharmacy_offer.dart';
import '../domain/models/promo_deal.dart';
import '../utils/title_sanitizer.dart';
import 'pharmacy_adapter.dart';

/// Adapter for Boots Pharmacy Saudi Arabia (`sa.boots.com`) via Algolia.
///
/// Connects directly to Boots KSA's Algolia DSN search index (`bp_prod_sa_en`),
/// retrieving live cash prices in SAR and leveraging direct commercial GTIN barcode indexing
/// (`attr_aims_barcode`) for instant Stage 1 physical barcode lookups.
class BootsAdapter implements PharmacyAdapter {
  static const String _appId = 'LQE0C6VCY3';
  static const String _apiKey = 'f12de14eaa992a4ae3a13f40b61c3978';
  static const String _indexName = 'bp_prod_sa_en';

  final Dio _dio;

  /// Creates a [BootsAdapter] instance with optional mockable [Dio] client.
  BootsAdapter({Dio? dio}) : _dio = dio ?? Dio();

  @override
  String get storeId => 'boots';

  @override
  String get storeName => 'Boots';

  @override
  String get baseUrl => 'https://sa.boots.com';

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
    final title = (hit['title'] ?? hit['name'] ?? '').toString();
    final sku = (hit['sku'] ?? hit['objectID'] ?? '').toString();
    final relativeUrl = hit['url']?.toString();
    final productUrl = relativeUrl != null
        ? (relativeUrl.startsWith('http') ? relativeUrl : 'https://sa.boots.com$relativeUrl')
        : 'https://sa.boots.com/en/search?q=$sku';

    // Image URL resolution
    String? imageUrl;
    if (hit['media'] is List && (hit['media'] as List).isNotEmpty) {
      final firstMedia = (hit['media'] as List).first;
      if (firstMedia is Map && firstMedia['url'] != null) {
        imageUrl = firstMedia['url'].toString();
      }
    }

    final singlePrice = _parseDouble(hit['final_price'] ?? hit['price']);
    final origPrice = _parseDouble(hit['original_price'] ?? hit['price']);

    // In stock determination
    final inStockRaw = hit['in_stock'];
    final inStock = inStockRaw == 1 || inStockRaw == true || (hit['stock_quantity'] != null && _parseDouble(hit['stock_quantity']) > 0);

    // SFDA medication check
    final lowerTitle = title.toLowerCase();
    final isSfda = lowerTitle.contains('panadol') ||
        lowerTitle.contains('paracetamol') ||
        lowerTitle.contains('analgesic') ||
        lowerTitle.contains('medication') ||
        lowerTitle.contains('caplet') ||
        lowerTitle.contains('tablet');

    // Unit info
    final unitInfo = TitleSanitizer.extractUnitInfo(title);
    final pricePerBase = TitleSanitizer.calculatePricePerBaseUnit(
      price: singlePrice,
      quantity: unitInfo.quantity,
      metric: unitInfo.metric,
    );

    // Promos
    final promos = <PromoDeal>[];
    if (origPrice > singlePrice && singlePrice > 0) {
      final discountPct = (((origPrice - singlePrice) / origPrice) * 100).round();
      if (discountPct > 0) {
        promos.add(
          PromoDeal.create(
            label: '$discountPct% Off Boots Deal',
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

  double _parseDouble(dynamic val) {
    if (val == null) return 0.0;
    if (val is num) return val.toDouble();
    final cleaned = val.toString().replaceAll(RegExp(r'[^\d.]'), '');
    return double.tryParse(cleaned) ?? 0.0;
  }
}
