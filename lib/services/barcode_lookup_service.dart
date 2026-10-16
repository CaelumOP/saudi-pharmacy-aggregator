import 'dart:convert';
import 'package:dio/dio.dart';
import '../utils/title_sanitizer.dart';

/// Normalized product information retrieved from barcode catalog lookups.
class BarcodeProductInfo {
  /// The GTIN/EAN barcode looked up.
  final String gtin;

  /// Commercial brand name (e.g. "Cetaphil", "Panadol", "Solgar").
  final String? brand;

  /// Commercial product name (e.g. "Gentle Skin Cleanser", "Extra Tablets").
  final String? productName;

  /// Package volume/weight string (e.g. "125ml", "473 ml", "90 softgels").
  final String? quantity;

  /// Primary product image URL if available.
  final String? imageUrl;

  /// Creates a [BarcodeProductInfo] instance.
  const BarcodeProductInfo({
    required this.gtin,
    this.brand,
    this.productName,
    this.quantity,
    this.imageUrl,
  });

  /// Assembled canonical search title (e.g. "Cetaphil Gentle Skin Cleanser 473 ml").
  String get canonicalTitle {
    final parts = <String>[];
    if (brand != null && brand!.trim().isNotEmpty) {
      parts.add(brand!.trim());
    }
    if (productName != null && productName!.trim().isNotEmpty) {
      final pName = productName!.trim();
      // Avoid duplicating brand if product name already begins with it
      if (brand != null && pName.toLowerCase().startsWith(brand!.trim().toLowerCase())) {
        parts.clear();
      }
      parts.add(pName);
    }
    if (quantity != null && quantity!.trim().isNotEmpty) {
      final qStr = quantity!.trim();
      final current = parts.join(' ');
      if (!current.toLowerCase().contains(qStr.toLowerCase())) {
        parts.add(qStr);
      }
    }
    return parts.join(' ');
  }

  @override
  String toString() => 'BarcodeProductInfo(gtin: $gtin, title: "$canonicalTitle")';
}

/// 4-Tier Super Barcode-to-Name Resolver.
///
/// Resolves raw numeric GTIN/EAN retail barcodes into canonical product titles
/// across a resilient multi-tier cascade:
/// - Tier 1: Handled in Orchestrator Stage 1 (Store GTIN indexes: Whites, Boots, Al-Nahdi, Trendyol).
/// - Tier 2: Trendyol KSA marketplace and UPCitemdb JSON endpoints.
/// - Tier 3: OpenBeautyFacts & OpenFoodFacts v2 global open databases.
/// - Tier 4: DuckDuckGo HTML web search fallback for retail products.
class BarcodeLookupService {
  final Dio _dio;

  /// Creates a [BarcodeLookupService] with optional mockable [Dio].
  BarcodeLookupService({Dio? dio})
      : _dio = dio ??
            Dio(
              BaseOptions(
                connectTimeout: const Duration(seconds: 3),
                receiveTimeout: const Duration(seconds: 3),
                headers: {
                  'User-Agent':
                      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36',
                  'Accept': 'application/json, text/html, */*',
                },
                validateStatus: (status) => status != null && status < 500,
              ),
            );

  /// Executes the 4-tier barcode lookup cascade.
  Future<BarcodeProductInfo?> lookup(String gtin) async {
    final cleanGtin = gtin.trim();
    if (cleanGtin.isEmpty) return null;

    // Tier 2: Trendyol KSA & UPCitemdb Marketplaces
    final tier2 = await _queryTier2Marketplaces(cleanGtin);
    if (tier2 != null) return tier2;

    // Tier 3: OpenBeautyFacts & OpenFoodFacts Databases
    final tier3 = await _queryTier3Databases(cleanGtin);
    if (tier3 != null) return tier3;

    // Tier 4: DuckDuckGo HTML Search Fallback
    final tier4 = await _queryTier4DuckDuckGo(cleanGtin);
    if (tier4 != null) return tier4;

    return null;
  }

  // ==========================================
  // TIER 2: MARKETPLACE LOOKUP (Trendyol & UPCitemdb)
  // ==========================================

  Future<BarcodeProductInfo?> _queryTier2Marketplaces(String gtin) async {
    // 1. Try Trendyol KSA barcode index
    try {
      final trendyolUrl = 'https://www.trendyol.com/en/sr?q=$gtin';
      final response = await _dio.get(
        trendyolUrl,
        options: Options(
          headers: {
            'Cookie': 'countryCode=SA;language=en;currency=SAR;',
            'Accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
          },
          responseType: ResponseType.plain,
        ),
      );

      if (response.statusCode == 200 && response.data != null) {
        final html = response.data.toString();
        const marker = 'window["__single-search-result__PROPS"]';
        final idx = html.indexOf(marker);
        if (idx != -1) {
          final eqIdx = html.indexOf('=', idx);
          final scriptEnd = html.indexOf('</script>', eqIdx);
          if (eqIdx != -1 && scriptEnd != -1) {
            var rawJson = html.substring(eqIdx + 1, scriptEnd).trim();
            if (rawJson.endsWith(';')) {
              rawJson = rawJson.substring(0, rawJson.length - 1).trim();
            }
            final decoded = json.decode(rawJson);
            if (decoded is Map) {
              final data = decoded['data'] is Map ? decoded['data'] as Map : {};
              final products = data['products'] is List ? data['products'] as List : const [];
              if (products.isNotEmpty && products.first is Map) {
                final first = products.first as Map;
                final name = first['name']?.toString() ?? '';
                final brandRaw = first['brand'];
                final brand = brandRaw is Map ? brandRaw['name']?.toString() : brandRaw?.toString();
                final image = first['image']?.toString();
                final unitInfo = TitleSanitizer.extractUnitInfo(name);

                if (name.isNotEmpty) {
                  return BarcodeProductInfo(
                    gtin: gtin,
                    brand: brand,
                    productName: name,
                    quantity: unitInfo.quantity != null && unitInfo.metric != null
                        ? '${unitInfo.quantity!.toStringAsFixed(0)} ${unitInfo.metric}'
                        : null,
                    imageUrl: image,
                  );
                }
              }
            }
          }
        }
      }
    } catch (_) {}

    // 2. Try UPCitemdb Trial API
    try {
      final upcUrl = 'https://api.upcitemdb.com/prod/trial/lookup?upc=$gtin';
      final response = await _dio.get(upcUrl);
      if (response.statusCode == 200 && response.data is Map) {
        final data = response.data as Map;
        final items = data['items'] is List ? data['items'] as List : const [];
        if (items.isNotEmpty && items.first is Map) {
          final item = items.first as Map;
          final title = item['title']?.toString() ?? '';
          final brand = item['brand']?.toString();
          final images = item['images'] is List ? item['images'] as List : const [];
          final imageUrl = images.isNotEmpty ? images.first.toString() : null;
          final unitInfo = TitleSanitizer.extractUnitInfo(title);

          if (title.isNotEmpty) {
            return BarcodeProductInfo(
              gtin: gtin,
              brand: brand,
              productName: title,
              quantity: unitInfo.quantity != null && unitInfo.metric != null
                  ? '${unitInfo.quantity!.toStringAsFixed(0)} ${unitInfo.metric}'
                  : null,
              imageUrl: imageUrl,
            );
          }
        }
      }
    } catch (_) {}

    return null;
  }

  // ==========================================
  // TIER 3: OPEN DATABASES (OpenBeautyFacts / OpenFoodFacts)
  // ==========================================

  Future<BarcodeProductInfo?> _queryTier3Databases(String gtin) async {
    // 1. Try OpenBeautyFacts first
    final obfResult = await _queryOpenDb(
      'https://world.openbeautyfacts.org/api/v2/product/$gtin.json',
      gtin,
    );
    if (obfResult != null) return obfResult;

    // 2. Fall back to OpenFoodFacts (for nutritional supplements, vitamins, wellness)
    final offResult = await _queryOpenDb(
      'https://world.openfoodfacts.org/api/v2/product/$gtin.json',
      gtin,
    );
    return offResult;
  }

  Future<BarcodeProductInfo?> _queryOpenDb(String url, String gtin) async {
    try {
      final response = await _dio.get(
        url,
        options: Options(
          headers: {
            'User-Agent': 'PharmacyApp-KSA-v2 (contact@pharmacytracker.sa)',
            'Accept': 'application/json',
          },
        ),
      );
      if (response.statusCode != 200 || response.data == null) {
        return null;
      }

      final data = response.data is Map ? response.data as Map : {};
      final status = data['status'];
      if (status != 1) {
        return null;
      }

      final product = data['product'] is Map ? data['product'] as Map : null;
      if (product == null) return null;

      String? brand = product['brands']?.toString();
      if (brand == null || brand.trim().isEmpty) {
        brand = product['brand']?.toString();
      }

      String? productName = product['product_name_en']?.toString();
      if (productName == null || productName.trim().isEmpty) {
        productName = product['product_name']?.toString();
      }
      if (productName == null || productName.trim().isEmpty) {
        productName = product['generic_name_en']?.toString();
      }
      if (productName == null || productName.trim().isEmpty) {
        productName = product['generic_name']?.toString();
      }

      final quantity = product['quantity']?.toString();
      final imageUrl = (product['image_front_url'] ?? product['image_url'])?.toString();

      if ((brand == null || brand.trim().isEmpty) && (productName == null || productName.trim().isEmpty)) {
        return null;
      }

      return BarcodeProductInfo(
        gtin: gtin,
        brand: brand,
        productName: productName,
        quantity: quantity,
        imageUrl: imageUrl,
      );
    } catch (_) {
      return null;
    }
  }

  // ==========================================
  // TIER 4: DUCKDUCKGO HTML WEB FALLBACK
  // ==========================================

  Future<BarcodeProductInfo?> _queryTier4DuckDuckGo(String gtin) async {
    try {
      final ddgUrl = 'https://html.duckduckgo.com/html/?q=${Uri.encodeComponent(gtin)}';
      final response = await _dio.get(
        ddgUrl,
        options: Options(
          headers: {
            'User-Agent':
                'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36',
            'Accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
          },
          responseType: ResponseType.plain,
        ),
      );

      if (response.statusCode != 200 || response.data == null) {
        return null;
      }

      final html = response.data.toString();
      final titleRegex = RegExp(r'class=["' "']result__title[\"'][^>]*>(.*?)</h2>", dotAll: true);
      final matches = titleRegex.allMatches(html);

      for (final match in matches) {
        final rawTitle = match.group(1)?.replaceAll(RegExp(r'<[^>]+>'), '').trim() ?? '';
        if (rawTitle.isEmpty) continue;

        // Strip store/domain marketing suffixes
        var cleanTitle = rawTitle;
        final suffixPatterns = [
          RegExp(
            r'\s*[-|–—]\s*(?:Amazon(?:\.sa)?|Nahdi|Whites|Boots|Trendyol|Nice One|iHerb|INCI Beauty|Wlidaty|Open Food Facts|Open Beauty Facts|Carrefour|Lulu|Noon|Danube|BinDawood|Al-Dawaa|United Pharmacy|ePharmacy).*$',
            caseSensitive: false,
          ),
          RegExp(r'\s*[-|–—]\s*#?\d+.*$'),
          RegExp(r'\s*[-|–—]\s*Buy Online.*$', caseSensitive: false),
          RegExp(r'\s*\|\s*.*$'),
        ];

        for (final pat in suffixPatterns) {
          cleanTitle = cleanTitle.replaceAll(pat, '').trim();
        }

        if (cleanTitle.isNotEmpty && cleanTitle.length > 5) {
          final unitInfo = TitleSanitizer.extractUnitInfo(cleanTitle);
          return BarcodeProductInfo(
            gtin: gtin,
            productName: cleanTitle,
            quantity: unitInfo.quantity != null && unitInfo.metric != null
                ? '${unitInfo.quantity!.toStringAsFixed(0)} ${unitInfo.metric}'
                : null,
          );
        }
      }
    } catch (_) {}

    return null;
  }
}

