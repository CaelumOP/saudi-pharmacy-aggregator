import 'dart:convert';
import 'package:dio/dio.dart';
import '../domain/models/pharmacy_offer.dart';
import '../utils/product_match_scorer.dart';
import '../utils/title_sanitizer.dart';
import 'pharmacy_adapter.dart';

/// Adapter for Lemon Pharmacy (`lemon.sa`) retail pharmacy chain across Saudi Arabia.
///
/// Direct integration with Lemon Pharmacy's Algolia DSN search catalog, parsing live
/// cash prices, OTC pharmaceuticals, and personal care products in SAR currency.
class LemonPharmacyAdapter implements PharmacyAdapter {
  final Dio _dio;

  static const String _appId = 'ZEU2NEOJN8';
  static const String _apiKey = '0d3928c0f3a533082e5daf03872349e2';
  static const String _indexName = 'products2024';

  /// Creates a [LemonPharmacyAdapter] with optional mockable [Dio].
  LemonPharmacyAdapter({Dio? dio}) : _dio = dio ?? Dio();

  @override
  String get storeId => 'lemon';

  @override
  String get storeName => 'Lemon Pharmacy';

  @override
  String get baseUrl => 'https://lemon.sa';

  @override
  StorePresenceType get presenceType => StorePresenceType.physicalAndOnline;

  @override
  StoreSpecialty get specialty => StoreSpecialty.pharmacyAndCare;

  @override
  Map<String, String> get defaultHeaders => {
        'X-Algolia-Application-Id': _appId,
        'X-Algolia-API-Key': _apiKey,
        'Content-Type': 'application/json',
        'Accept': 'application/json',
      };

  @override
  Future<List<PharmacyOffer>> searchByBarcode(String gtin) async {
    final cleanGtin = gtin.trim();
    if (cleanGtin.isEmpty) return const [];

    return _queryAlgolia(cleanGtin, isBarcode: true, limit: 3);
  }

  @override
  Future<List<PharmacyOffer>> searchByKeyword(String query, {int limit = 5}) async {
    final cleanQuery = query.trim();
    if (cleanQuery.isEmpty) return const [];

    final initialOffers = await _queryAlgolia(cleanQuery, isBarcode: false, limit: limit);
    if (initialOffers.isNotEmpty) return initialOffers;

    // Bilingual Arabic fallback if English query returns 0 hits
    final directAlias = ProductMatchScorer.getArabicAlias(cleanQuery);
    if (directAlias != null && directAlias.isNotEmpty) {
      final aliasOffers = await _queryAlgolia(directAlias, isBarcode: false, limit: limit);
      if (aliasOffers.isNotEmpty) return aliasOffers;
    }

    // Inspect individual tokens (e.g. "Cetaphil" in "Cetaphil Gentle Skin Cleanser")
    final tokens = cleanQuery.split(RegExp(r'\s+'));
    for (final token in tokens) {
      final tokenAlias = ProductMatchScorer.getArabicAlias(token);
      if (tokenAlias != null && tokenAlias.isNotEmpty && tokenAlias != directAlias) {
        final tokenOffers = await _queryAlgolia(tokenAlias, isBarcode: false, limit: limit);
        if (tokenOffers.isNotEmpty) return tokenOffers;
      }
    }

    return const [];
  }

  Future<List<PharmacyOffer>> _queryAlgolia(
    String term, {
    required bool isBarcode,
    required int limit,
  }) async {
    final endpoint = 'https://$_appId-dsn.algolia.net/1/indexes/$_indexName/query';

    try {
      final payload = json.encode({
        'query': term,
        'hitsPerPage': limit,
      });

      final response = await _dio.post(
        endpoint,
        data: payload,
        options: Options(
          headers: defaultHeaders,
          validateStatus: (status) => status != null && status < 500,
        ),
      );

      if (response.statusCode != 200 || response.data == null) {
        return const [];
      }

      final data = response.data is Map ? response.data as Map : {};
      final hits = data['hits'] is List ? data['hits'] as List : const [];

      final offers = <PharmacyOffer>[];

      for (final hit in hits) {
        if (hit is! Map) continue;

        final productId = hit['product_id']?.toString() ?? hit['objectID']?.toString() ?? '';
        final nameAr = hit['name_ar']?.toString() ?? hit['name(ar)']?.toString() ?? '';
        final nameEn = hit['name_en']?.toString() ?? hit['name(en)']?.toString() ?? '';
        final title = nameEn.isNotEmpty ? nameEn : (nameAr.isNotEmpty ? nameAr : (hit['name']?.toString() ?? ''));

        if (title.isEmpty) continue;

        // Parse price from special_SAR or price_SAR (strip HTML svg/spans)
        final rawSpecial = hit['special_SAR']?.toString();
        final rawPrice = hit['price_SAR']?.toString();

        var price = _parseCleanPrice(rawSpecial);
        if (price <= 0) {
          price = _parseCleanPrice(rawPrice);
        }

        if (price <= 0) continue;

        final image = hit['image']?.toString();
        final productUrl = productId.isNotEmpty
            ? 'https://lemon.sa/index.php?route=product/product&product_id=$productId'
            : null;

        final unitInfo = TitleSanitizer.extractUnitInfo(title);
        final pricePerBase = TitleSanitizer.calculatePricePerBaseUnit(
          price: price,
          quantity: unitInfo.quantity,
          metric: unitInfo.metric,
        );

        offers.add(
          PharmacyOffer(
            storeId: storeId,
            pharmacyName: storeName,
            skuOrId: productId,
            productTitle: title,
            imageUrl: image,
            productUrl: productUrl,
            singleUnitPrice: price,
            isVatInclusive: true,
            isSfdaRegulated: false,
            unitQuantity: unitInfo.quantity,
            unitMetric: unitInfo.metric,
            pricePerBaseUnit: pricePerBase,
            isOnlineInStock: true,
            isFallbackMatch: !isBarcode,
          ),
        );
      }

      return offers;
    } catch (_) {
      return const [];
    }
  }

  double _parseCleanPrice(String? raw) {
    if (raw == null || raw.trim().isEmpty) return 0.0;
    // Strip HTML tags and symbols, retain digits and decimal point
    final stripped = raw.replaceAll(RegExp(r'<[^>]+>'), ' ');
    final cleaned = stripped.replaceAll(RegExp(r'[^\d.]'), '');
    return double.tryParse(cleaned) ?? 0.0;
  }
}
