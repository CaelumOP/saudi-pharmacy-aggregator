import 'package:dio/dio.dart';
import '../domain/models/pharmacy_offer.dart';
import '../utils/title_sanitizer.dart';
import 'pharmacy_adapter.dart';

/// Adapter for Golden Scent (`goldenscent.com`), Saudi Arabia's premier fragrance & beauty platform.
///
/// Parses live catalog prices in SAR currency from server-rendered product hydration states.
class GoldenScentAdapter implements PharmacyAdapter {
  final Dio _dio;

  /// Creates a [GoldenScentAdapter] with optional mockable [Dio].
  GoldenScentAdapter({Dio? dio}) : _dio = dio ?? Dio();

  @override
  String get storeId => 'golden_scent';

  @override
  String get storeName => 'Golden Scent';

  @override
  String get baseUrl => 'https://www.goldenscent.com';

  @override
  StorePresenceType get presenceType => StorePresenceType.onlineOnly;

  @override
  StoreSpecialty get specialty => StoreSpecialty.kBeautyAndSkincare;

  @override
  Map<String, String> get defaultHeaders => {
        'Accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
        'User-Agent':
            'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36',
        'Accept-Language': 'en-US,en;q=0.9',
      };

  @override
  Future<List<PharmacyOffer>> searchByBarcode(String gtin) async {
    // Golden Scent storefront does not index 13-digit retail GTIN barcodes directly.
    return const [];
  }

  @override
  Future<List<PharmacyOffer>> searchByKeyword(String query, {int limit = 5}) async {
    final cleanQuery = query.trim();
    if (cleanQuery.isEmpty) return const [];

    final endpoint = 'https://www.goldenscent.com/en/search.html?q=${Uri.encodeComponent(cleanQuery)}';

    try {
      final response = await _dio.get(
        endpoint,
        options: Options(
          headers: defaultHeaders,
          validateStatus: (status) => status != null && status < 500,
          responseType: ResponseType.plain,
        ),
      );

      if (response.statusCode != 200 || response.data == null) {
        return const [];
      }

      final html = response.data.toString();
      final offers = <PharmacyOffer>[];

      // Regex matching Golden Scent hydration product entities
      final pattern = RegExp(
        r'\\"brand\\":\\"([^"\\]+)\\",.*?\\"currency\\":\\"SAR\\",\\"currentPrice\\":\\"SAR[^\d]*([\d.]+)\\",.*?\\"externalId\\":\\"([^"\\]+)\\",.*?\\"imageUrl\\":\\"([^"\\]+)\\",.*?\\"name\\":\\"([^"\\]+)\\"',
        dotAll: true,
      );

      final matches = pattern.allMatches(html);

      for (final match in matches.take(limit)) {
        final brand = match.group(1)?.trim() ?? '';
        final priceStr = match.group(2) ?? '0';
        final sku = match.group(3) ?? '';
        final rawImg = match.group(4) ?? '';
        final name = match.group(5)?.trim() ?? '';

        final price = double.tryParse(priceStr) ?? 0.0;
        if (price <= 0 || name.isEmpty) continue;

        var title = name;
        if (brand.isNotEmpty && !title.toLowerCase().startsWith(brand.toLowerCase())) {
          title = '$brand $title';
        }

        final imageUrl = rawImg.replaceAll(r'\/', '/');
        final productUrl = sku.isNotEmpty
            ? 'https://www.goldenscent.com/en/p/$sku.html'
            : 'https://www.goldenscent.com/en/search.html?q=${Uri.encodeComponent(name)}';

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
            skuOrId: sku,
            productTitle: title,
            imageUrl: imageUrl,
            productUrl: productUrl,
            singleUnitPrice: price,
            isVatInclusive: true,
            isSfdaRegulated: false,
            unitQuantity: unitInfo.quantity,
            unitMetric: unitInfo.metric,
            pricePerBaseUnit: pricePerBase,
            isOnlineInStock: true,
            isFallbackMatch: true,
          ),
        );
      }

      return offers;
    } catch (_) {
      return const [];
    }
  }
}
