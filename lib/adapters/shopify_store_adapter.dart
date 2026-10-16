import 'package:dio/dio.dart';
import '../domain/models/pharmacy_offer.dart';
import '../domain/models/promo_deal.dart';
import '../utils/product_match_scorer.dart';
import '../utils/title_sanitizer.dart';
import 'pharmacy_adapter.dart';

/// Universal search adapter for Shopify-backed personal care and K-Beauty stores.
///
/// Dispatches queries against Shopify's high-speed storefront predictive search endpoint
/// (`/search/suggest.json` with fallback to `/en/search/suggest.json`), parsing multi-variant
/// pricing, stock availability, and compare-at discount prices in Saudi Riyals (SAR).
/// If predictive search returns 0 products, automatically cascades to `/products.json?limit=250`
/// with client-side semantic matching via [ProductMatchScorer].
class ShopifyStoreAdapter implements PharmacyAdapter {
  @override
  final String storeId;

  @override
  final String storeName;

  final String _domain;

  @override
  final StorePresenceType presenceType;

  @override
  final StoreSpecialty specialty;

  final Dio _dio;

  List<Map>? _cachedCatalogue;
  DateTime? _catalogueCacheExpiry;

  /// Creates a [ShopifyStoreAdapter] for a target Shopify storefront.
  ShopifyStoreAdapter({
    required this.storeId,
    required this.storeName,
    required String domain,
    this.presenceType = StorePresenceType.onlineOnly,
    this.specialty = StoreSpecialty.kBeautyAndSkincare,
    Dio? dio,
  })  : _domain = domain.replaceAll(RegExp(r'^https?://'), '').replaceAll(RegExp(r'/.*$'), ''),
        _dio = dio ?? Dio();

  @override
  String get baseUrl => 'https://$_domain';

  @override
  Map<String, String> get defaultHeaders => {
        'Accept': 'application/json',
        'User-Agent':
            'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36',
      };

  @override
  Future<List<PharmacyOffer>> searchByBarcode(String gtin) async {
    final cleanGtin = gtin.trim();
    if (cleanGtin.isEmpty) return const [];

    try {
      final products = await _fetchCatalogue();
      for (final p in products) {
        final variants = p['variants'] is List ? p['variants'] as List : const [];
        for (final v in variants) {
          if (v is Map && v['sku']?.toString().trim() == cleanGtin) {
            return [_parseCatalogueProduct(p, matchedVariant: v)];
          }
        }
      }
    } catch (_) {
      // Fall through to empty list to trigger Stage 3 title fallback
    }

    return const [];
  }

  @override
  Future<List<PharmacyOffer>> searchByKeyword(String query, {int limit = 5}) async {
    final cleanQuery = query.trim();
    if (cleanQuery.isEmpty) return const [];
    return _queryShopify(cleanQuery, limit: limit);
  }

  Future<List<PharmacyOffer>> _queryShopify(String query, {required int limit}) async {
    // 1. Primary endpoint: /search/suggest.json
    final primarySuggest = await _fetchSuggestProducts('https://$_domain/search/suggest.json', query);
    if (primarySuggest.isNotEmpty) {
      return primarySuggest.take(limit).map((p) => _parseProduct(p)).toList();
    }

    // 2. Locale fallback endpoint: /en/search/suggest.json
    final enSuggest = await _fetchSuggestProducts('https://$_domain/en/search/suggest.json', query);
    if (enSuggest.isNotEmpty) {
      return enSuggest.take(limit).map((p) => _parseProduct(p)).toList();
    }

    // 3. Complete catalogue fallback: /products.json?limit=250
    return _queryCatalogue(query, limit: limit);
  }

  Future<List<Map>> _fetchSuggestProducts(String endpoint, String query) async {
    final queryParams = {
      'q': query,
      'resources[type]': 'product',
      'resources[options][unavailable_products]': 'show',
      'resources[options][fields]': 'title,product_type,variants.title,vendor,tag,variants.sku',
    };

    try {
      final response = await _dio.get(
        endpoint,
        queryParameters: queryParams,
        options: Options(
          headers: defaultHeaders,
          validateStatus: (status) => status != null && status < 500,
        ),
      );

      if (response.statusCode != 200 || response.data == null) {
        return const [];
      }

      final data = response.data is Map ? response.data as Map : {};
      final resources = data['resources'] is Map ? data['resources'] as Map : {};
      final results = resources['results'] is Map ? resources['results'] as Map : {};
      final products = results['products'] is List ? results['products'] as List : const [];

      return products.whereType<Map>().toList();
    } catch (_) {
      return const [];
    }
  }

  Future<List<Map>> _fetchCatalogue() async {
    if (_cachedCatalogue != null &&
        _catalogueCacheExpiry != null &&
        DateTime.now().isBefore(_catalogueCacheExpiry!)) {
      return _cachedCatalogue!;
    }

    final endpoint = 'https://$_domain/products.json?limit=250';
    try {
      final response = await _dio.get(
        endpoint,
        options: Options(
          headers: defaultHeaders,
          validateStatus: (status) => status != null && status < 500,
        ),
      );

      if (response.statusCode != 200 || response.data == null) {
        return const [];
      }

      final data = response.data is Map ? response.data as Map : {};
      final products = data['products'] is List ? data['products'] as List : const [];
      final list = products.whereType<Map>().toList();

      _cachedCatalogue = list;
      _catalogueCacheExpiry = DateTime.now().add(const Duration(minutes: 5));
      return list;
    } catch (_) {
      return const [];
    }
  }

  Future<List<PharmacyOffer>> _queryCatalogue(String query, {required int limit}) async {
    final products = await _fetchCatalogue();
    if (products.isEmpty) return const [];

    final cleanQuery = query.toLowerCase().trim();
    final scored = <({double score, PharmacyOffer offer})>[];

    for (final p in products) {
      final title = (p['title'] ?? '').toString();
      final vendor = (p['vendor'] ?? '').toString();
      final body = (p['body_html'] ?? '').toString();

      final matchScore = ProductMatchScorer.score(query, title);
      final vendorMatch = vendor.toLowerCase().contains(cleanQuery) || cleanQuery.contains(vendor.toLowerCase());
      final titleContains = title.toLowerCase().contains(cleanQuery);
      final bodyContains = body.toLowerCase().contains(cleanQuery);

      if (matchScore >= 0.50 || vendorMatch || titleContains || bodyContains) {
        final offer = _parseCatalogueProduct(p);
        final effectiveScore = matchScore > 0 ? matchScore : (vendorMatch ? 0.75 : 0.60);
        scored.add((score: effectiveScore, offer: offer.copyWith(matchScore: effectiveScore)));
      }
    }

    scored.sort((a, b) => b.score.compareTo(a.score));
    return scored.take(limit).map((e) => e.offer).toList();
  }

  PharmacyOffer _parseProduct(Map product) {
    final title = (product['title'] ?? '').toString();
    final id = (product['id'] ?? '').toString();
    final relativeUrl = product['url']?.toString();
    final productUrl = relativeUrl != null
        ? (relativeUrl.startsWith('http') ? relativeUrl : 'https://$_domain$relativeUrl')
        : null;

    String? imageUrl = product['image']?.toString();
    if (imageUrl == null && product['featured_image'] is Map) {
      imageUrl = product['featured_image']['url']?.toString();
    }

    final singlePrice = _parseDouble(product['price']);
    final origPrice = _parseDouble(product['compare_at_price_max'] ?? product['compare_at_price_min']);
    final inStock = product['available'] == true;

    // Unit parsing
    final unitInfo = TitleSanitizer.extractUnitInfo(title);
    final pricePerBase = TitleSanitizer.calculatePricePerBaseUnit(
      price: singlePrice,
      quantity: unitInfo.quantity,
      metric: unitInfo.metric,
    );

    // Multi-buy or discount promotions
    final promos = <PromoDeal>[];
    if (origPrice > singlePrice && singlePrice > 0) {
      final discountPct = (((origPrice - singlePrice) / origPrice) * 100).round();
      if (discountPct > 0) {
        promos.add(
          PromoDeal.create(
            label: '$discountPct% Off Sale',
            requiredQuantity: 1,
            totalCheckoutCost: singlePrice,
          ),
        );
      }
    }

    return PharmacyOffer(
      storeId: storeId,
      pharmacyName: storeName,
      skuOrId: id,
      productTitle: title,
      imageUrl: imageUrl,
      productUrl: productUrl,
      singleUnitPrice: singlePrice,
      isVatInclusive: true,
      isSfdaRegulated: false,
      unitQuantity: unitInfo.quantity,
      unitMetric: unitInfo.metric,
      pricePerBaseUnit: pricePerBase,
      isOnlineInStock: inStock,
      multiBuyPromos: promos,
    );
  }

  PharmacyOffer _parseCatalogueProduct(Map product, {Map? matchedVariant}) {
    final title = (product['title'] ?? '').toString();
    final id = (product['id'] ?? '').toString();
    final handle = (product['handle'] ?? '').toString();
    final productUrl = handle.isNotEmpty ? 'https://$_domain/en/products/$handle' : null;

    final images = product['images'] is List ? product['images'] as List : const [];
    String? imageUrl = images.isNotEmpty && images.first is Map ? images.first['src']?.toString() : null;

    final variants = product['variants'] is List ? product['variants'] as List : const [];
    final variant = matchedVariant ?? (variants.isNotEmpty && variants.first is Map ? variants.first as Map : null);

    final singlePrice = variant != null ? _parseDouble(variant['price']) : 0.0;
    final origPrice = variant != null ? _parseDouble(variant['compare_at_price']) : 0.0;
    final inStock = variant != null ? variant['available'] == true : true;
    final sku = variant != null && variant['sku'] != null && variant['sku'].toString().isNotEmpty
        ? variant['sku'].toString()
        : id;

    // Unit parsing
    final unitInfo = TitleSanitizer.extractUnitInfo(title);
    final pricePerBase = TitleSanitizer.calculatePricePerBaseUnit(
      price: singlePrice,
      quantity: unitInfo.quantity,
      metric: unitInfo.metric,
    );

    // Multi-buy or discount promotions
    final promos = <PromoDeal>[];
    if (origPrice > singlePrice && singlePrice > 0) {
      final discountPct = (((origPrice - singlePrice) / origPrice) * 100).round();
      if (discountPct > 0) {
        promos.add(
          PromoDeal.create(
            label: '$discountPct% Off Sale',
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
      isSfdaRegulated: false,
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
