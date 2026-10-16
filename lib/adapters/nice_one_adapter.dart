import 'dart:convert';
import 'package:dio/dio.dart';
import '../domain/models/pharmacy_offer.dart';
import '../utils/title_sanitizer.dart';
import 'pharmacy_adapter.dart';

/// Adapter for Nice One Saudi Arabia (`niceonesa.com`).
///
/// Parses high-accuracy server-rendered Schema.org JSON-LD `ItemList` product graphs
/// from Nice One's Nuxt storefront, extracting live SAR prices, stock states, and deep links.
class NiceOneAdapter implements PharmacyAdapter {
  final Dio _dio;

  /// Creates a [NiceOneAdapter] with optional mockable [Dio].
  NiceOneAdapter({Dio? dio}) : _dio = dio ?? Dio();

  @override
  String get storeId => 'nice_one';

  @override
  String get storeName => 'Nice One';

  @override
  String get baseUrl => 'https://niceonesa.com';

  @override
  StorePresenceType get presenceType => StorePresenceType.onlineOnly;

  @override
  StoreSpecialty get specialty => StoreSpecialty.kBeautyAndSkincare;

  @override
  Map<String, String> get defaultHeaders => {
        'Accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
        'User-Agent':
            'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36',
      };

  @override
  Future<List<PharmacyOffer>> searchByBarcode(String gtin) async {
    // Nice One storefront HTML search does not index 13-digit physical GTIN barcodes.
    // Return empty list immediately to trigger Stage 3 title fallback.
    return const [];
  }

  @override
  Future<List<PharmacyOffer>> searchByKeyword(String query, {int limit = 5}) async {
    final endpoint = 'https://niceonesa.com/search?q=${Uri.encodeComponent(query)}';

    try {
      final response = await _dio.get(
        endpoint,
        options: Options(headers: defaultHeaders, responseType: ResponseType.plain),
      );

      if (response.statusCode != 200 || response.data == null) {
        return const [];
      }

      final html = response.data.toString();
      return _parseJsonLdFromHtml(html, limit: limit);
    } catch (_) {
      return const [];
    }
  }

  List<PharmacyOffer> _parseJsonLdFromHtml(String html, {required int limit}) {
    final jsonLdRegex = RegExp(r'<script\s+type=["' "']application/ld\\+json[\"'][^>]*>(.*?)</script>", dotAll: true);
    final matches = jsonLdRegex.allMatches(html);

    for (final match in matches) {
      final rawJson = match.group(1);
      if (rawJson == null || rawJson.trim().isEmpty) continue;

      try {
        final decoded = json.decode(rawJson);
        if (decoded is Map && decoded['@type'] == 'ItemList') {
          final items = decoded['itemListElement'] is List ? decoded['itemListElement'] as List : const [];
          return items.take(limit).map((item) => _parseItem(item as Map)).where((o) => o != null).cast<PharmacyOffer>().toList();
        }
      } catch (_) {
        continue;
      }
    }

    return const [];
  }

  PharmacyOffer? _parseItem(Map item) {
    final title = (item['name'] ?? '').toString().trim();
    if (title.isEmpty) return null;

    final imageUrl = item['image']?.toString();
    final offers = item['offers'] is Map ? item['offers'] as Map : {};
    final singlePrice = _parseDouble(offers['price']);

    final productUrl = offers['url']?.toString();
    final inStock = offers['availability']?.toString().contains('InStock') ?? true;

    // Extract SKU from URL (e.g. https://niceonesa.com/ar/...-n22459)
    String sku = '';
    if (productUrl != null) {
      final skuMatch = RegExp(r'-([a-zA-Z0-9]+)$').firstMatch(productUrl);
      if (skuMatch != null) {
        sku = skuMatch.group(1)!;
      }
    }
    if (sku.isEmpty) {
      sku = (item['sku'] ?? item['id'] ?? title.hashCode.toString()).toString();
    }

    // Unit parsing
    final unitInfo = TitleSanitizer.extractUnitInfo(title);
    final pricePerBase = TitleSanitizer.calculatePricePerBaseUnit(
      price: singlePrice,
      quantity: unitInfo.quantity,
      metric: unitInfo.metric,
    );

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
      multiBuyPromos: const [],
    );
  }

  double _parseDouble(dynamic val) {
    if (val == null) return 0.0;
    if (val is num) return val.toDouble();
    final cleaned = val.toString().replaceAll(RegExp(r'[^\d.]'), '');
    return double.tryParse(cleaned) ?? 0.0;
  }
}
