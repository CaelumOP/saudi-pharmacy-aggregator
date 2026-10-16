/// Utility for cleaning noisy promotional titles and extracting standardized dosage/volume metrics.
///
/// Ensures clean title queries for cross-store fallback searches and normalizes package sizes
/// into comparative base pricing (e.g., SAR per 100ml, SAR per 100g, or SAR per 10 tablets).
class TitleSanitizer {
  TitleSanitizer._();

  static final List<RegExp> _promotionalPatterns = [
    // Multi-buy & promotional phrases in parentheses or brackets
    RegExp(r'\([^\)]*(?:1\+1|2\+1|free|offer|promo|خصم|مجانا|وفّر)[^\)]*\)', caseSensitive: false),
    RegExp(r'\[[^\]]*(?:1\+1|2\+1|free|offer|promo|خصم|مجانا|وفّر)[^\]]*\]', caseSensitive: false),

    // Freeform promotional noise
    RegExp(r'\b(?:\d+\s*\+\s*\d+)\s*(?:free|free\b)?', caseSensitive: false),
    RegExp(r'\b(?:buy\s+\d+\s+get\s+\d+(?:\s+free)?)\b', caseSensitive: false),
    RegExp(r'\b(?:special\s+offer|promo\s+pack|twin\s+pack|value\s+pack|bonus\s+pack)\b', caseSensitive: false),
    RegExp(r'\b(?:save\s+\d+%\s*|(?:\d+%\s*(?:off|خصم)))\b', caseSensitive: false),
    RegExp(r'\bx\d+\s+bundle\b', caseSensitive: false),

    // Arabic promotional strings
    RegExp(r'(?:عرض\s+خاص|عبوة\s+توفيرية|عبوة\s+ترويجية|مجاناً|مجانا)', caseSensitive: false),
  ];

  /// Cleans [rawTitle] by stripping promotional strings while retaining brand,
  /// core product name, and volume/dosage metrics for cross-store query fallback.
  static String clean(String rawTitle) {
    if (rawTitle.isEmpty) return '';

    String cleaned = rawTitle;

    for (final pattern in _promotionalPatterns) {
      cleaned = cleaned.replaceAll(pattern, ' ');
    }

    // Clean dangling separators, punctuation, and collapsed spaces
    cleaned = cleaned
        .replaceAll(RegExp(r'[\(\)\[\]\{\}]'), ' ')
        .replaceAll(RegExp(r'\s*[-–—]\s*(?:$|\s)'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();

    // Remove trailing dashes or commas
    cleaned = cleaned.replaceAll(RegExp(r'^[-–—,\s]+|[-–—,\s]+$'), '');

    return cleaned;
  }

  /// Builds a concise, focused core product query for Stage 3 title fallback searches.
  ///
  /// Strips package volumes/weights/counts (e.g. "473 ml", "500 mg", "24 tablets")
  /// and verbose marketing fillers (e.g. "for dry to normal skin", "for face & body")
  /// returning a high-recall 3-to-4 word core query (e.g. "Cetaphil Gentle Skin Cleanser").
  static String buildStage3SearchQuery(String rawTitle) {
    if (rawTitle.isEmpty) return '';

    var q = clean(rawTitle);

    // 1. Strip unit and volume specifications (e.g. "473 ml", "1000 mg", "90 softgels")
    q = q.replaceAll(
      RegExp(
        r'\b\d+(?:\.\d+)?\s*(?:ml|milliliters?|liters?|ltr|l|gm|g|grams?|kg|mg|tablets?|tabs?|caplets?|capsules?|caps?|softgels?|sachets?|pcs|pieces?|pills?|مل|لتر|غ|جم|جرام|كيلو|حبة|حبات|قرص|اقراص|كبسولة|كبسولات)\b',
        caseSensitive: false,
      ),
      ' ',
    );

    // 2. Strip filler / skin type / application phrases
    final fillers = [
      RegExp(r'\bfor\s+(?:dry|normal|sensitive|oily|combination|all)\s+(?:to\s+[a-z]+\s+)?skin\b', caseSensitive: false),
      RegExp(r'\bdry\s+normal\s+(?:and\s+)?sensitive\s+skin\b', caseSensitive: false),
      RegExp(r'\bfor\s+face\s*(?:&|and)\s*body\b', caseSensitive: false),
      RegExp(r'\bface\s*(?:&|and)\s*body\b', caseSensitive: false),
      RegExp(r'\bfor\s+all\s+skin\s+types\b', caseSensitive: false),
      RegExp(r'\bdaily\s+(?:skin\s+)?care\b', caseSensitive: false),
      RegExp(r'\bfor\s+(?:men|women|kids|adults)\b', caseSensitive: false),
      RegExp(r'(?:للبشرة\s+(?:الجافة|العادية|الحساسة|الدهنية|المختلطة|لجميع\s+أنواع\s+البشرة))', caseSensitive: false),
      RegExp(r'(?:للوجه\s+والجسم|للعناية\s+بالبشرة)', caseSensitive: false),
    ];

    for (final filler in fillers) {
      q = q.replaceAll(filler, ' ');
    }

    // 3. Remove punctuation, symbols, and excess spaces
    q = q
        .replaceAll(RegExp(r'[\(\)\[\]\{\}\-–—+&,;:]'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();

    // 4. If query is still long, retain the first 4 core words
    final words = q.split(' ').where((w) => w.trim().isNotEmpty).toList();
    if (words.length > 4) {
      q = words.take(4).join(' ');
    }

    return q.isNotEmpty ? q : clean(rawTitle);
  }

  /// Extracts numeric package volume or tablet count and canonical unit metric.
  ///
  /// Standardizes volume units to 'ml', weight to 'g', and tablet/caplet counts to 'tabs'.
  static ({double? quantity, String? metric}) extractUnitInfo(String title) {
    // Strip or mask nutrient/vitamin designations (e.g., "Omega 3", "Vitamin D3", "B12")
    // so their suffix numbers do not falsely bind to trailing forms like "3 Capsules".
    final sanitizedForUnit = title.replaceAll(
      RegExp(r'\b(?:omega\s*[-]?\s*[369]|vitamin\s*[-]?\s*[a-z0-9]+|d3|b12|b6|k2|coq10)\b', caseSensitive: false),
      ' ',
    );

    // 1. Liquids (ml, l, مل, لتر)
    final liquidRegex = RegExp(
      r'(\d+(?:\.\d+)?)\s*(?:(ml|milliliters?|liters?|ltr|l)\b|(مل|لتر)(?![a-zA-Z\u0600-\u06FF0-9]))',
      caseSensitive: false,
    );
    final liquidMatch = liquidRegex.firstMatch(sanitizedForUnit);
    if (liquidMatch != null) {
      final val = double.tryParse(liquidMatch.group(1)!);
      if (val != null) {
        final rawUnit = (liquidMatch.group(2) ?? liquidMatch.group(3))!.toLowerCase();
        if (rawUnit == 'l' || rawUnit.startsWith('liter') || rawUnit == 'ltr' || rawUnit == 'لتر') {
          return (quantity: val * 1000.0, metric: 'ml');
        }
        return (quantity: val, metric: 'ml');
      }
    }

    // 2. Weights (g, gm, kg, غ, جم, جرام, كيلو)
    final weightRegex = RegExp(
      r'(\d+(?:\.\d+)?)\s*(?:(gm|g|grams?|kg|kilograms?)\b|(غ|جم|جرام|كيلو(?:غرام|جرام)?)(?![a-zA-Z\u0600-\u06FF0-9]))',
      caseSensitive: false,
    );
    final weightMatch = weightRegex.firstMatch(sanitizedForUnit);
    if (weightMatch != null) {
      final val = double.tryParse(weightMatch.group(1)!);
      if (val != null) {
        final rawUnit = (weightMatch.group(2) ?? weightMatch.group(3))!.toLowerCase();
        if (rawUnit == 'kg' || rawUnit.startsWith('kilo') || rawUnit.startsWith('كيلو')) {
          return (quantity: val * 1000.0, metric: 'g');
        }
        return (quantity: val, metric: 'g');
      }
    }

    // 3. Oral solid counts (tablets, caplets, capsules, softgels, sachets, pcs, pills, حبة, قرص, كبسولة)
    final countRegex = RegExp(
      r'(\d+)\s*(?:(tablets?|tabs?|caplets?|capsules?|caps?|softgels?|sachets?|pcs|pieces?|pills?)\b|(حبة|حبات|قرص|اقراص|كبسولة|كبسولات)(?![a-zA-Z\u0600-\u06FF0-9]))',
      caseSensitive: false,
    );
    final countMatch = countRegex.firstMatch(sanitizedForUnit);
    if (countMatch != null) {
      final val = double.tryParse(countMatch.group(1)!);
      if (val != null) {
        return (quantity: val, metric: 'tabs');
      }
    }

    return (quantity: null, metric: null);
  }

  /// Calculates the standardized price per base unit:
  /// - Liquids: SAR per 100ml
  /// - Creams / Solids: SAR per 100g
  /// - Tablets / Caplets: SAR per 10 tablets
  static double? calculatePricePerBaseUnit({
    required double price,
    required double? quantity,
    required String? metric,
  }) {
    if (quantity == null || quantity <= 0 || metric == null) return null;

    double calculated;
    switch (metric.toLowerCase()) {
      case 'ml':
      case 'g':
        // Base is 100 units (100ml or 100g)
        calculated = (price / quantity) * 100.0;
        break;
      case 'tabs':
      case 'pcs':
        // Base is 10 tablets/pieces
        calculated = (price / quantity) * 10.0;
        break;
      default:
        return null;
    }

    return double.parse(calculated.toStringAsFixed(2));
  }
}
