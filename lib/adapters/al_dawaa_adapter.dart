import 'package:dio/dio.dart';
import '../domain/models/pharmacy_offer.dart';
import '../domain/models/promo_deal.dart';
import '../utils/title_sanitizer.dart';
import 'network_client_helper.dart';
import 'pharmacy_adapter.dart';

/// Adapter for querying Al-Dawaa Pharmacy via SAP Commerce Cloud (Hybris) OCC v2 REST APIs.
///
/// Configured with host-scoped certificate support for the live OCC backend, detects
/// Cloudflare Turnstile 403 anti-bot challenges, and ignores Arbahi loyalty point figures.
class AlDawaaAdapter implements PharmacyAdapter {
  static const String _defaultApiHost = 'https://stgprevapi.al-dawaa.com';
  static const String _webHost = 'https://www.al-dawaa.com';

  final Dio _dio;
  final String _occBaseUrl;

  /// Creates an [AlDawaaAdapter] instance with host-scoped TLS handling or injected test client.
  AlDawaaAdapter({Dio? dio, String? occBaseUrl})
      : _dio = dio ?? NetworkClientHelper.createAlDawaaClient(),
        _occBaseUrl = occBaseUrl ?? _defaultApiHost;

  @override
  String get storeId => 'al_dawaa';

  @override
  String get storeName => 'Al-Dawaa';

  @override
  String get baseUrl => _webHost;

  @override
  StorePresenceType get presenceType => StorePresenceType.physicalAndOnline;

  @override
  StoreSpecialty get specialty => StoreSpecialty.pharmacyAndCare;

  @override
  Map<String, String> get defaultHeaders => {
        'Accept': 'application/json',
        'Accept-Language': 'en-SA,en;q=0.9',
        'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36',
      };

  @override
  Future<List<PharmacyOffer>> searchByBarcode(String gtin) async {
    return _queryOcc(gtin, limit: 5);
  }

  @override
  Future<List<PharmacyOffer>> searchByKeyword(String query, {int limit = 5}) async {
    return _queryOcc(query, limit: limit);
  }

  Future<List<PharmacyOffer>> _queryOcc(String query, {required int limit}) async {
    final endpoint = '$_occBaseUrl/occ/v2/aldawaa/products/search';
    final queryParams = {
      'query': query,
      'lang': 'en',
      'curr': 'SAR',
      'pageSize': limit,
    };

    try {
      final response = await _dio.get(
        endpoint,
        queryParameters: queryParams,
        options: Options(headers: defaultHeaders),
      );

      // Check for Cloudflare 403 or Turnstile challenge
      if (response.statusCode == 403 || _isCloudflareChallenge(response)) {
        throw CloudflareChallengeException(
          storeId: storeId,
          challengeUrl: _webHost,
          message: 'Received Cloudflare Turnstile WAF challenge for Al-Dawaa',
        );
      }

      if (response.statusCode != 200 || response.data == null) {
        return const [];
      }

      final data = response.data is Map ? response.data as Map : {};
      final products = data['products'] is List ? data['products'] as List : const [];

      return products.map((p) => _parseProduct(p as Map)).toList();
    } on CloudflareChallengeException {
      rethrow;
    } on DioException catch (dioErr) {
      if (dioErr.response?.statusCode == 403 ||
          _isCloudflareChallenge(dioErr.response)) {
        throw CloudflareChallengeException(
          storeId: storeId,
          challengeUrl: _webHost,
          message: 'Cloudflare 403 challenge encountered: ${dioErr.message}',
        );
      }
      return const [];
    } catch (_) {
      return const [];
    }
  }

  bool _isCloudflareChallenge(Response? response) {
    if (response == null) return false;
    final headers = response.headers.map;
    if (headers['cf-mitigated']?.contains('challenge') == true) return true;

    final bodyStr = response.data?.toString().toLowerCase() ?? '';
    return bodyStr.contains('challenges.cloudflare.com') ||
        bodyStr.contains('attention required! | cloudflare') ||
        bodyStr.contains('just a moment...');
  }

  PharmacyOffer _parseProduct(Map p) {
    final title = (p['name'] ?? '').toString();
    final sku = (p['code'] ?? '').toString();

    // Image URL resolution
    String? imageUrl;
    final rawImg = p['imageUrl'];
    if (rawImg is String && rawImg.isNotEmpty) {
      imageUrl = rawImg.startsWith('http') ? rawImg : '$_occBaseUrl$rawImg';
    } else if (rawImg is List && rawImg.isNotEmpty) {
      final first = rawImg.first;
      if (first is Map && first['value'] != null) {
        final val = first['value'].toString();
        imageUrl = val.startsWith('http') ? val : '$_occBaseUrl$val';
      }
    }

    // Product deep link
    final urlPath = p['url']?.toString();
    final productUrl = urlPath != null ? '$_webHost/en$urlPath' : null;

    // Price extraction: check simulated discount price first, then standard price
    double singlePrice = 0.0;
    double originalPrice = 0.0;

    final standardPriceObj = p['price'] is Map ? p['price'] : null;
    if (standardPriceObj != null && standardPriceObj['value'] != null) {
      final val = standardPriceObj['value'];
      originalPrice = val is num ? val.toDouble() : double.tryParse(val.toString()) ?? 0.0;
      singlePrice = originalPrice;
    }

    final simulatedPriceObj = p['simulatedDiscountPrice'] is Map ? p['simulatedDiscountPrice'] : null;
    if (simulatedPriceObj != null && simulatedPriceObj['value'] != null) {
      final val = simulatedPriceObj['value'];
      final simVal = val is num ? val.toDouble() : double.tryParse(val.toString()) ?? 0.0;
      if (simVal > 0) {
        singlePrice = simVal;
      }
    }

    // SFDA medication check
    final isPrescription = p['prescription'] == true;
    final lowerTitle = title.toLowerCase();
    final isSfda = isPrescription ||
        lowerTitle.contains('panadol') ||
        lowerTitle.contains('paracetamol') ||
        lowerTitle.contains('analgesic');

    // Stock check
    final stockObj = p['stock'] is Map ? p['stock'] : null;
    final stockStatus = stockObj?['stockLevelStatus']?.toString();
    final inStock = stockStatus == 'inStock';

    // Base unit normalization
    final unitInfo = TitleSanitizer.extractUnitInfo(title);
    final pricePerBase = TitleSanitizer.calculatePricePerBaseUnit(
      price: singlePrice,
      quantity: unitInfo.quantity,
      metric: unitInfo.metric,
    );

    // Multi-buy promos
    final promos = <PromoDeal>[];
    if (originalPrice > singlePrice && singlePrice > 0) {
      final discountPct = (((originalPrice - singlePrice) / originalPrice) * 100).round();
      promos.add(
        PromoDeal.create(
          label: '$discountPct% Off Instant Discount',
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
}
