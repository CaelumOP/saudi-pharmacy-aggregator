import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:dio/dio.dart';

/// Comprehensive result of 4-stage query resolution and recovery.
class ResolvedQuery {
  /// The raw user query before correction.
  final String originalQuery;

  /// Repaired Arabic query (e.g. "بانتين تطاير").
  final String repairedArabicQuery;

  /// Repaired English query (e.g. "Pantene Frizz").
  final String repairedEnglishQuery;

  /// Extracted canonical brand if detected (e.g. "pantene" / "بانتين").
  final String? brand;

  /// Extracted form or attribute/effect (e.g. "frizz" / "تطاير", "cleanser" / "غسول").
  final String? formOrAttribute;

  /// True if any typo was corrected in the query.
  final bool wasCorrected;

  /// Search suggestions from Google Suggest and local dictionary.
  final List<String> suggestions;

  /// Confidence score between 0.0 and 1.0.
  final double confidence;

  const ResolvedQuery({
    required this.originalQuery,
    required this.repairedArabicQuery,
    required this.repairedEnglishQuery,
    this.brand,
    this.formOrAttribute,
    required this.wasCorrected,
    this.suggestions = const [],
    this.confidence = 1.0,
  });

  /// The primary repaired query matching the user's input language script.
  String get primaryQuery =>
      RegExp(r'[\u0600-\u06FF]').hasMatch(originalQuery)
          ? repairedArabicQuery
          : repairedEnglishQuery;

  /// Arabic brand alias if a brand was detected.
  String? get arabicBrand =>
      brand != null ? (SmartQueryCorrector.englishToArabicTerms[brand!.toLowerCase()] ?? brand) : null;

  /// Canonical English brand display if a brand was detected.
  String? get englishBrand =>
      brand != null ? SmartQueryCorrector.canonicalDisplay(brand!) : null;

  @override
  String toString() =>
      'ResolvedQuery(orig: "$originalQuery", ar: "$repairedArabicQuery", en: "$repairedEnglishQuery", brand: $brand, attr: $formOrAttribute, wasCorrected: $wasCorrected)';
}

/// Backward-compatible query correction result.
class QueryCorrectionResult {
  final String originalQuery;
  final String correctedQuery;
  final bool wasCorrected;
  final List<String> suggestions;

  const QueryCorrectionResult({
    required this.originalQuery,
    required this.correctedQuery,
    required this.wasCorrected,
    this.suggestions = const [],
  });

  @override
  String toString() =>
      'QueryCorrectionResult(original: "$originalQuery", corrected: "$correctedQuery", wasCorrected: $wasCorrected)';
}

/// Intelligent 4-Stage "Extreme Mangling" Query Correction and Recovery Engine.
///
/// Features:
/// - Stage A: Keyboard-Proximity Damerau-Levenshtein (transposition cost 0.5, adjacent key cost 0.4)
///   + Character Multiset/Bag-of-Letters + Bigram/Anchor similarity scoring.
/// - Stage B: 2-Pass Brand-Anchored Google Suggest Recovery (`suggestqueries.google.com`).
/// - Stage C: Live Google Neural Translate (`translate.googleapis.com`) + Bilingual Domain Mapping.
class SmartQueryCorrector {
  final Dio _dio;

  /// Singleton instance.
  static final SmartQueryCorrector instance = SmartQueryCorrector();

  /// Creates a [SmartQueryCorrector] with an optional [dio] client.
  SmartQueryCorrector({Dio? dio})
      : _dio = dio ??
            Dio(
              BaseOptions(
                connectTimeout: const Duration(milliseconds: 1200),
                receiveTimeout: const Duration(milliseconds: 1200),
                headers: {
                  'User-Agent':
                      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/122.0.0.0 Safari/537.36',
                  'Accept': 'application/json',
                },
              ),
            );

  // ===========================================================================
  // Physical Keyboard Adjacency Clusters & Phonetic Map
  // ===========================================================================

  static final Map<String, Set<String>> _keyboardAdjacency = {
    // Arabic Home Row
    'ش': {'س', 'ي', 'ئ', 'ض'},
    'س': {'ش', 'ي', 'ب', 'ء', 'ص'},
    'ي': {'س', 'ب', 'ل', 'ؤ', 'ث'},
    'ب': {'ي', 'ل', 'ا', 'ر', 'ق'},
    'ل': {'ب', 'ا', 'ت', 'لا', 'ف'},
    'ا': {'ل', 'ت', 'ن', 'ى', 'غ'},
    'ت': {'ا', 'ن', 'م', 'ة', 'ع', 'ب'},
    'ن': {'ت', 'م', 'ك', 'و', 'ه'},
    'م': {'ن', 'ك', 'ط', 'ز', 'خ'},
    'ك': {'م', 'ط', 'ظ', 'ح', 'ج'},
    'ط': {'ك', 'د', 'ج'},

    // Arabic Top Row
    'ض': {'ص', 'ش'},
    'ص': {'ض', 'ث', 'س'},
    'ث': {'ص', 'ق', 'ي'},
    'ق': {'ث', 'ف', 'ب'},
    'ف': {'ق', 'غ', 'ل'},
    'غ': {'ف', 'ع', 'ا'},
    'ع': {'غ', 'ه', 'ت'},
    'ه': {'ع', 'خ', 'ن'},
    'خ': {'ه', 'ح', 'م'},
    'ح': {'خ', 'ج', 'ك'},
    'ج': {'ح', 'د', 'ط'},
    'د': {'ج', 'ط', 'ذ'},

    // Arabic Bottom Row
    'ئ': {'ء', 'ش'},
    'ء': {'ئ', 'ؤ', 'س'},
    'ؤ': {'ء', 'ر', 'ي'},
    'ر': {'ؤ', 'لا', 'ب'},
    'لا': {'ر', 'ى', 'ل'},
    'ى': {'لا', 'ة', 'ا'},
    'ة': {'ى', 'و', 'ت'},
    'و': {'ة', 'ز', 'ن'},
    'ز': {'و', 'ظ', 'م'},
    'ظ': {'ز', 'ك'},

    // English QWERTY Top Row
    'q': {'w', 'a', 's'},
    'w': {'q', 'e', 'a', 's', 'd'},
    'e': {'w', 'r', 's', 'd', 'f'},
    'r': {'e', 't', 'd', 'f', 'g'},
    't': {'r', 'y', 'f', 'g', 'h'},
    'y': {'t', 'u', 'g', 'h', 'j'},
    'u': {'y', 'i', 'h', 'j', 'k'},
    'i': {'u', 'o', 'j', 'k', 'l'},
    'o': {'i', 'p', 'k', 'l'},
    'p': {'o', 'l'},

    // English QWERTY Home Row
    'a': {'q', 'w', 's', 'z'},
    's': {'a', 'w', 'e', 'd', 'z', 'x'},
    'd': {'s', 'e', 'r', 'f', 'x', 'c'},
    'f': {'d', 'r', 't', 'g', 'c', 'v'},
    'g': {'f', 't', 'y', 'h', 'v', 'b'},
    'h': {'g', 'y', 'u', 'j', 'b', 'n'},
    'j': {'h', 'u', 'i', 'k', 'n', 'm'},
    'k': {'j', 'i', 'o', 'l', 'm'},
    'l': {'k', 'o', 'p'},

    // English QWERTY Bottom Row
    'z': {'a', 's', 'x'},
    'x': {'z', 's', 'd', 'c'},
    'c': {'x', 'd', 'f', 'v'},
    'v': {'c', 'f', 'g', 'b'},
    'b': {'v', 'g', 'h', 'n'},
    'n': {'b', 'h', 'j', 'm'},
    'm': {'n', 'j', 'k'},
  };

  static bool _isPhoneticallyClose(String c1, String c2) {
    if (c1 == c2) return true;
    final pair = '$c1$c2';
    const phoneticPairs = {
      // Arabic phonetic swaps
      'تط', 'طت', 'سص', 'صس', 'كق', 'قك', 'ذز', 'زذ', 'ظض', 'ضظ',
      'هح', 'حه', 'ثس', 'سث', 'دض', 'ضد', 'من', 'نم', 'تب', 'بت',
      'كز', 'زك', 'كس', 'سك', 'وس', 'سو',
      // English phonetic swaps
      'ck', 'kc', 'cs', 'sc', 'sz', 'zs', 'fv', 'vf', 'dt', 'td',
      'pb', 'bp', 'gj', 'jg',
    };
    return phoneticPairs.contains(pair);
  }

  /// Returns true if [c1] and [c2] are physically adjacent or phonetically close.
  static bool isKeyboardAdjacentOrPhonetic(String c1, String c2) {
    if (c1 == c2) return true;
    if (_isPhoneticallyClose(c1, c2)) return true;
    return _keyboardAdjacency[c1]?.contains(c2) == true ||
        _keyboardAdjacency[c2]?.contains(c1) == true;
  }

  // ===========================================================================
  // Local Vocabulary & Domain Synonyms (Brands, Attributes & Concerns)
  // ===========================================================================

  /// Common Arabic phonetic and colloquial spellings mapped to canonical terms.
  static const Map<String, String> _arabicPhoneticMap = {
    'بندول': 'بنادول',
    'سيتافل': 'سيتافيل',
    'ستافيل': 'سيتافيل',
    'كوزركس': 'كوسركس',
    'لاروش بوزي': 'لاروش بوزيه',
    'لاروش': 'لاروش بوزيه',
    'سيراف': 'سيرافي',
    'سيرف': 'سيرافي',
    'يوسرين': 'يوسيرين',
    'يوسيرن': 'يوسيرين',
    'بايوديرما': 'بيوديرما',
    'بايودرما': 'بيوديرما',
    'بيودرما': 'بيوديرما',
    'بيبانثين': 'بيبانثين',
    'بيبانثول': 'بيبانثين',
    'فولتارين': 'فولتارين',
    'بروفين': 'بروفين',
    'فازلين': 'فازلين',
    'بانتين': 'بانتين',
  };

  /// Arabic canonical dictionary of brands, attributes, concerns, and forms.
  static const Map<String, String> arabicToEnglishTerms = {
    // Top Brands
    'بانتين': 'pantene',
    'فازلين': 'vaseline',
    'سيتافيل': 'cetaphil',
    'بنادول': 'panadol',
    'سيرافي': 'cerave',
    'بيوديرما': 'bioderma',
    'يوسيرين': 'eucerin',
    'لاروش بوزيه': 'laroche posay',
    'لاروش': 'laroche posay',
    'كوسركس': 'cosrx',
    'انوا': 'anua',
    'جوسون': 'beauty of joseon',
    'بيوتي اوف جوسون': 'beauty of joseon',
    'ميديكيوب': 'medicube',
    'سوم باي مي': 'some by mi',
    'سكين 1004': 'skin1004',
    'نيتروجينا': 'neutrogena',
    'دوف': 'dove',
    'غارنييه': 'garnier',
    'لوريال': 'loreal',
    'افين': 'avene',
    'فيشي': 'vichy',
    'بيبانثين': 'bepanthen',
    'فولتارين': 'voltaren',
    'بروفين': 'brufen',
    'او جي اكس': 'ogx',
    'كيو في': 'qv',

    // Hair / Skin Concerns & Attributes
    'تطاير': 'frizz',
    'هيشان': 'frizz',
    'تقصف': 'split ends',
    'تساقط': 'hair fall',
    'قشره': 'dandruff',
    'قشرة': 'dandruff',
    'جفاف': 'dryness',
    'ترطيب': 'moisture',
    'تفتيح': 'brightening',
    'تبييض': 'whitening',
    'مقاوم': 'anti',
    'انسيابي': 'smooth',
    'كيرلي': 'curly',
    'مجعد': 'curly',
    'متموج': 'wavy',
    'مصبوغ': 'colored',
    'تالف': 'damaged',
    'حلزون': 'snail',
    'هايلورونيك': 'hyaluronic',
    'نياسيناميد': 'niacinamide',
    'ريتينول': 'retinol',
    'فيتامين': 'vitamin',
    'كولاجين': 'collagen',

    // Forms
    'غسول': 'cleanser',
    'منظف': 'cleanser',
    'شامبو': 'shampoo',
    'بلسم': 'conditioner',
    'مرطب': 'moisturizer',
    'لوشن': 'lotion',
    'كريم': 'cream',
    'سيروم': 'serum',
    'تونر': 'toner',
    'زيت': 'oil',
    'واقي شمس': 'sunscreen',
    'اكسترا': 'extra',
    'اقراص': 'tablets',
    'حبوب': 'tablets',
    'كبسولات': 'capsules',
    'شراب': 'syrup',
  };

  /// English to Arabic canonical mapping.
  static const Map<String, String> englishToArabicTerms = {
    'pantene': 'بانتين',
    'vaseline': 'فازلين',
    'cetaphil': 'سيتافيل',
    'panadol': 'بنادول',
    'cerave': 'سيرافي',
    'bioderma': 'بيوديرما',
    'eucerin': 'يوسيرين',
    'cosrx': 'كوسركس',
    'bepanthen': 'بيبانثين',
    'frizz': 'تطاير',
    'smooth': 'انسيابي',
    'curly': 'كيرلي',
    'snail': 'حلزون',
    'cleanser': 'غسول',
    'cream': 'كريم',
    'lotion': 'لوشن',
    'moisturizer': 'مرطب',
    'shampoo': 'شامبو',
    'conditioner': 'بلسم',
    'sunscreen': 'واقي شمس',
    'extra': 'اكسترا',
  };

  /// Canonical vocabulary of English words.
  static const List<String> canonicalVocabulary = [
    // Top Brands
    'pantene',
    'vaseline',
    'cetaphil',
    'panadol',
    'cerave',
    'bioderma',
    'eucerin',
    'laroche',
    'posay',
    'avene',
    'vichy',
    'cosrx',
    'anua',
    'joseon',
    'medicube',
    'somebymi',
    'skin1004',
    'neutrogena',
    'ogx',
    'qv',
    'bebanthol',
    'bepanthen',
    'voltaren',
    'brufen',
    'augmentin',
    'claritin',
    'zyrtec',
    'omeprazole',
    'nexium',
    'centrum',
    'solgar',
    'vitabiotics',
    'jamieson',
    'sebamed',
    'uriage',
    'isdin',
    'ducray',
    'nivea',
    'garnier',
    'loreal',
    'dettol',
    'differin',

    // Attributes & Concerns
    'frizz',
    'curly',
    'smooth',
    'snail',
    'cleanser',
    'moisturizer',
    'sunscreen',
    'shampoo',
    'conditioner',
    'serum',
    'toner',
    'lotion',
    'cream',
    'essence',
    'mucin',
    'foaming',
    'wash',
    'mask',
    'oil',
    'tablets',
    'capsules',
    'syrup',
    'extra',
    'daily',
    'gentle',
    'night',
    'hydrating',
    'repair',
    'niacinamide',
    'retinol',
    'hyaluronic',
    'collagen',
  ];

  static final Set<String> _canonicalSet = Set<String>.unmodifiable(canonicalVocabulary);

  /// Preferred display casing for common brands and terms.
  static const Map<String, String> _canonicalDisplayMap = {
    'pantene': 'Pantene',
    'vaseline': 'Vaseline',
    'cetaphil': 'Cetaphil',
    'panadol': 'Panadol',
    'cerave': 'CeraVe',
    'bioderma': 'Bioderma',
    'eucerin': 'Eucerin',
    'laroche': 'La Roche Posay',
    'posay': 'Posay',
    'avene': 'Avene',
    'vichy': 'Vichy',
    'cosrx': 'COSRX',
    'anua': 'Anua',
    'joseon': 'Beauty of Joseon',
    'medicube': 'Medicube',
    'somebymi': 'Some By Mi',
    'skin1004': 'SKIN1004',
    'neutrogena': 'Neutrogena',
    'ogx': 'OGX',
    'qv': 'QV',
    'bepanthen': 'Bepanthen',
    'bebanthol': 'Bebanthol',
    'voltaren': 'Voltaren',
    'brufen': 'Brufen',
    'frizz': 'Frizz',
    'curly': 'Curly',
    'smooth': 'Smooth',
    'snail': 'Snail',
    'cleanser': 'Cleanser',
    'cream': 'Cream',
    'lotion': 'Lotion',
    'extra': 'Extra',
    'essence': 'Essence',
    'sunscreen': 'Sunscreen',
    'shampoo': 'Shampoo',
    'serum': 'Serum',
    'tablets': 'Tablets',
    'capsules': 'Capsules',
    'syrup': 'Syrup',
  };

  /// Formats term with preferred display casing.
  static String canonicalDisplay(String term) {
    return _canonicalDisplayMap[term.toLowerCase()] ?? term;
  }

  // ===========================================================================
  // Mathematical Similarity Algorithms
  // ===========================================================================

  /// Normalizes Arabic orthographic letters (Alef forms, Taa Marbuta, Alif Maqsura, diacritics).
  static String normalizeArabicOrthography(String input) {
    var text = input;
    text = text.replaceAll('\u0640', ''); // Strip tatweel
    text = text.replaceAll(RegExp(r'[\u064B-\u065F\u0670]'), ''); // Strip diacritics
    text = text.replaceAll(RegExp(r'[أإآ]'), 'ا'); // Normalize Alef
    text = text.replaceAll('ة', 'ه'); // Normalize Taa Marbuta
    text = text.replaceAll('ى', 'ي'); // Normalize Alif Maqsura
    return text.trim();
  }

  /// Calculates Damerau-Levenshtein distance with keyboard-adjacency and transposition costs.
  static double weightedDamerauLevenshtein(String s1, String s2) {
    if (s1 == s2) return 0.0;
    if (s1.isEmpty) return s2.length.toDouble();
    if (s2.isEmpty) return s1.length.toDouble();

    final len1 = s1.length;
    final len2 = s2.length;
    final d = List.generate(len1 + 1, (_) => List<double>.filled(len2 + 1, 0.0));

    for (var i = 0; i <= len1; i++) {
      d[i][0] = i.toDouble();
    }
    for (var j = 0; j <= len2; j++) {
      d[0][j] = j.toDouble();
    }

    for (var i = 1; i <= len1; i++) {
      for (var j = 1; j <= len2; j++) {
        final c1 = s1[i - 1];
        final c2 = s2[j - 1];

        final double subCost;
        if (c1 == c2) {
          subCost = 0.0;
        } else if (isKeyboardAdjacentOrPhonetic(c1, c2)) {
          subCost = 0.4; // Keyboard adjacency cost
        } else {
          subCost = 1.0;
        }

        var minCost = d[i - 1][j] + 1.0; // Deletion
        final insertCost = d[i][j - 1] + 1.0; // Insertion
        if (insertCost < minCost) minCost = insertCost;
        final matchOrSubCost = d[i - 1][j - 1] + subCost; // Match or substitution
        if (matchOrSubCost < minCost) minCost = matchOrSubCost;

        // Transposition cost = 0.5 (swapping two adjacent letters)
        if (i > 1 && j > 1 && s1[i - 1] == s2[j - 2] && s1[i - 2] == s2[j - 1]) {
          final transCost = d[i - 2][j - 2] + 0.5;
          if (transCost < minCost) minCost = transCost;
        }

        d[i][j] = minCost;
      }
    }

    return d[len1][len2];
  }

  /// Calculates Character Multiset / Bag-of-Letters Overlap.
  static double bagOfLettersSimilarity(String s1, String s2) {
    if (s1.isEmpty || s2.isEmpty) return 0.0;
    final counts1 = <String, int>{};
    final counts2 = <String, int>{};

    for (var i = 0; i < s1.length; i++) {
      final ch = s1[i];
      counts1[ch] = (counts1[ch] ?? 0) + 1;
    }
    for (var i = 0; i < s2.length; i++) {
      final ch = s2[i];
      counts2[ch] = (counts2[ch] ?? 0) + 1;
    }

    var shared = 0;
    counts1.forEach((ch, cnt1) {
      final cnt2 = counts2[ch] ?? 0;
      shared += min(cnt1, cnt2);
    });

    final maxLen = max(s1.length, s2.length);
    return shared / maxLen;
  }

  /// Calculates Character Bigram Dice Coefficient + First/Last Letter Anchor Bonus.
  static double bigramAnchorSimilarity(String s1, String s2) {
    if (s1 == s2) return 1.0;
    if (s1.length < 2 || s2.length < 2) {
      return s1.isNotEmpty && s2.isNotEmpty && s1[0] == s2[0] ? 0.5 : 0.0;
    }

    final bigrams1 = <String, int>{};
    for (var i = 0; i < s1.length - 1; i++) {
      final bg = s1.substring(i, i + 2);
      bigrams1[bg] = (bigrams1[bg] ?? 0) + 1;
    }

    final bigrams2 = <String, int>{};
    for (var i = 0; i < s2.length - 1; i++) {
      final bg = s2.substring(i, i + 2);
      bigrams2[bg] = (bigrams2[bg] ?? 0) + 1;
    }

    var matches = 0;
    bigrams1.forEach((bg, count1) {
      final count2 = bigrams2[bg] ?? 0;
      matches += min(count1, count2);
    });

    final totalBigrams = (s1.length - 1) + (s2.length - 1);
    var dice = (2.0 * matches) / totalBigrams;

    // Anchor bonuses for first and last letters
    if (s1[0] == s2[0]) dice += 0.15;
    if (s1[s1.length - 1] == s2[s2.length - 1]) dice += 0.10;

    return dice.clamp(0.0, 1.0);
  }

  /// Computes the 3-Signal Extreme Token Similarity score (Stage A).
  ///
  /// Blends:
  /// - 50% Weighted Keyboard Damerau-Levenshtein
  /// - 25% Character Multiset / Bag-of-Letters
  /// - 25% Bigram + First/Last Letter Anchor
  static double computeExtremeTokenSimilarity(String input, String candidate) {
    final normIn = normalizeArabicOrthography(input.toLowerCase().trim());
    final normCand = normalizeArabicOrthography(candidate.toLowerCase().trim());

    if (normIn == normCand) return 1.0;
    if (normIn.isEmpty || normCand.isEmpty) return 0.0;

    final maxLen = max(normIn.length, normCand.length);
    final dist = weightedDamerauLevenshtein(normIn, normCand);
    final damerauSim = max(0.0, 1.0 - (dist / maxLen));

    final bagSim = bagOfLettersSimilarity(normIn, normCand);
    final bigramSim = bigramAnchorSimilarity(normIn, normCand);

    return (0.50 * damerauSim) + (0.25 * bagSim) + (0.25 * bigramSim);
  }

  /// Calculates simple Levenshtein distance (for backward compatibility).
  static int levenshtein(String s1, String s2) {
    return weightedDamerauLevenshtein(s1, s2).round();
  }

  // ===========================================================================
  // 4-Stage Recovery Pipeline
  // ===========================================================================

  /// Normalizes English digraphs and phonetic variations (ph -> f, ck -> k, double letters).
  static String normalizeEnglishPhonetic(String word) {
    return word
        .toLowerCase()
        .replaceAll('ph', 'f')
        .replaceAll('ck', 'k')
        .replaceAllMapped(RegExp(r'(.)\1+'), (m) => m[1]!);
  }

  /// Stage A: Repairs a single mangled token using local phonetic map and 3-signal similarity.
  String _repairTokenStageA(String rawToken, {bool isArabic = false}) {
    final token = rawToken.trim();
    if (token.isEmpty) return token;

    if (isArabic) {
      final norm = normalizeArabicOrthography(token);
      // Check direct phonetic map
      final mapped = _arabicPhoneticMap[norm] ?? _arabicPhoneticMap[token];
      if (mapped != null) return mapped;

      // Scan Arabic terms
      String? bestCandidate;
      var bestScore = 0.0;

      for (final candidate in arabicToEnglishTerms.keys) {
        final sim = computeExtremeTokenSimilarity(norm, candidate);
        if (sim > bestScore) {
          bestScore = sim;
          bestCandidate = candidate;
        }
      }

      // 0.68 threshold for extreme recovery
      if (bestCandidate != null && bestScore >= 0.68) {
        return bestCandidate;
      }

      return token;
    } else {
      final lower = token.toLowerCase();
      // Keep short numbers / exact words
      if (_canonicalSet.contains(lower) || lower.length < 4 || RegExp(r'^\d+$').hasMatch(lower)) {
        return _canonicalDisplayMap[lower] ?? token;
      }

      String? bestCandidate;
      var bestScore = 0.0;
      final normLower = normalizeEnglishPhonetic(lower);

      for (final candidate in canonicalVocabulary) {
        final rawSim = computeExtremeTokenSimilarity(lower, candidate);
        final normCand = normalizeEnglishPhonetic(candidate);
        final phonSim = computeExtremeTokenSimilarity(normLower, normCand);
        final sim = max(rawSim, phonSim);

        if (sim > bestScore) {
          bestScore = sim;
          bestCandidate = candidate;
        }
      }

      if (bestCandidate != null && bestScore >= 0.68) {
        return _canonicalDisplayMap[bestCandidate] ?? bestCandidate;
      }

      return token;
    }
  }

  /// Fetches Google Search Suggestions from `suggestqueries.google.com` (1200ms timeout).
  Future<List<String>> fetchGoogleSuggestions(String query) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) return const [];

    try {
      final response = await _dio.get<String>(
        'https://suggestqueries.google.com/complete/search',
        queryParameters: {
          'client': 'firefox',
          'gl': 'sa',
          'q': trimmed,
        },
        options: Options(responseType: ResponseType.plain),
      );

      if (response.statusCode == 200 && response.data != null) {
        final decoded = jsonDecode(response.data!);
        if (decoded is List && decoded.length >= 2 && decoded[1] is List) {
          return (decoded[1] as List)
              .map((e) => e.toString().trim())
              .where((s) => s.isNotEmpty)
              .toList();
        }
      }
    } catch (_) {}

    return const [];
  }

  /// Translates text via Google Neural Translate (`translate.googleapis.com`).
  Future<String?> translateViaGoogle(String text, {String targetLang = 'en'}) async {
    try {
      final response = await _dio.get<dynamic>(
        'https://translate.googleapis.com/translate_a/single',
        queryParameters: {
          'client': 'gtx',
          'sl': 'auto',
          'tl': targetLang,
          'dt': 't',
          'q': text,
        },
      );
      if (response.statusCode == 200 && response.data != null) {
        final data = response.data;
        if (data is List && data.isNotEmpty && data[0] is List) {
          final segments = data[0] as List;
          final translated = segments.map((s) => s[0]?.toString() ?? '').join(' ').trim();
          if (translated.isNotEmpty) return translated;
        }
      }
    } catch (_) {}
    return null;
  }

  /// Resolves an extremely mangled user query using the 4-Stage Recovery Pipeline.
  Future<ResolvedQuery> resolveQuery(String rawQuery) async {
    final trimmed = rawQuery.trim();
    if (trimmed.isEmpty) {
      return ResolvedQuery(
        originalQuery: rawQuery,
        repairedArabicQuery: rawQuery,
        repairedEnglishQuery: rawQuery,
        wasCorrected: false,
      );
    }

    final isArabic = RegExp(r'[\u0600-\u06FF]').hasMatch(trimmed);

    // -------------------------------------------------------------------------
    // Stage A: 0ms Local Keyboard Damerau + Bag-of-Letters + Bigram Similarity
    // -------------------------------------------------------------------------
    var stageAQuery = trimmed;
    var wasCorrected = false;

    if (isArabic) {
      final norm = normalizeArabicOrthography(trimmed);
      if (_arabicPhoneticMap.containsKey(norm)) {
        stageAQuery = _arabicPhoneticMap[norm]!;
        wasCorrected = stageAQuery != trimmed;
      } else if (_arabicPhoneticMap.containsKey(trimmed)) {
        stageAQuery = _arabicPhoneticMap[trimmed]!;
        wasCorrected = stageAQuery != trimmed;
      }
    }

    List<String> stageATokens = [];
    if (!wasCorrected) {
      var text = trimmed;
      if (isArabic) {
        final multiWordEntries = _arabicPhoneticMap.entries.where((e) => e.key.contains(' ')).toList();
        for (final entry in multiWordEntries) {
          if (text.contains(entry.key)) {
            text = text.replaceAll(entry.key, entry.value);
            wasCorrected = true;
          }
        }
      }

      final tokenList = text.split(RegExp(r'\s+')).where((t) => t.isNotEmpty).toList();
      for (var i = 0; i < tokenList.length; i++) {
        final t = tokenList[i];
        if (t == 'لاروش' && i + 1 < tokenList.length && (tokenList[i + 1] == 'بوزيه' || tokenList[i + 1] == 'بوزي')) {
          stageATokens.add(t);
        } else {
          stageATokens.add(_repairTokenStageA(t, isArabic: isArabic));
        }
      }
      stageAQuery = stageATokens.join(' ');
      if (stageAQuery.toLowerCase() != trimmed.toLowerCase()) {
        wasCorrected = true;
      }
    } else {
      stageATokens = stageAQuery.split(RegExp(r'\s+')).where((t) => t.isNotEmpty).toList();
    }

    // -------------------------------------------------------------------------
    // Stage B: 2-Pass Brand-Anchored Google Suggest Recovery
    // -------------------------------------------------------------------------
    List<String> suggestions = [];
    try {
      // Pass 1: Raw query
      suggestions = await fetchGoogleSuggestions(trimmed);

      // Pass 2: If Pass 1 empty/weak, use Stage A repaired brand + remaining word
      if (suggestions.isEmpty && stageATokens.isNotEmpty) {
        suggestions = await fetchGoogleSuggestions(stageAQuery);
      }

      // Pass 3: Brand anchor check if 2+ words and word 2 wasn't repaired
      if (suggestions.isEmpty && stageATokens.length >= 2) {
        suggestions = await fetchGoogleSuggestions(stageATokens.first);
      }
    } catch (_) {}

    // Evaluate Google suggestions if Stage A didn't fully resolve
    if (suggestions.isNotEmpty && !wasCorrected) {
      final top = suggestions.first.toLowerCase().trim();
      final lowerRaw = trimmed.toLowerCase();
      if (top != lowerRaw) {
        final rawWords = lowerRaw.split(RegExp(r'\s+'));
        final suggWords = top.split(RegExp(r'\s+'));
        if (rawWords.length == suggWords.length) {
          final sim = computeExtremeTokenSimilarity(lowerRaw, top);
          if (sim >= 0.65) {
            stageAQuery = top;
            wasCorrected = true;
          }
        }
      }
    }

    // -------------------------------------------------------------------------
    // Stage C: Cross-Language Bilingual Resolution (Arabic <-> English)
    // -------------------------------------------------------------------------
    String repairedAr;
    String repairedEn;
    String? detectedBrand;
    String? detectedAttr;

    if (isArabic) {
      repairedAr = stageAQuery;

      // Extract brand and attribute from Arabic tokens
      final arTokens = stageAQuery.split(RegExp(r'\s+'));
      final enTokens = <String>[];

      for (final tok in arTokens) {
        final normTok = normalizeArabicOrthography(tok);
        final enWord = arabicToEnglishTerms[normTok] ?? arabicToEnglishTerms[tok];
        if (enWord != null) {
          enTokens.add(enWord);
          if (_isKnownBrand(enWord)) {
            detectedBrand ??= enWord;
          } else {
            detectedAttr ??= enWord;
          }
        } else {
          enTokens.add(tok);
        }
      }

      // If domain mapping covered tokens, build English query; else try Neural Translate
      if (enTokens.isNotEmpty && enTokens.any((t) => !RegExp(r'[\u0600-\u06FF]').hasMatch(t))) {
        repairedEn = enTokens.map((t) => _canonicalDisplayMap[t] ?? t).join(' ');
      } else {
        final gTrans = await translateViaGoogle(repairedAr, targetLang: 'en');
        repairedEn = gTrans ?? repairedAr;
      }
    } else {
      repairedEn = stageAQuery;

      // Extract brand and attribute from English tokens
      final enTokens = stageAQuery.toLowerCase().split(RegExp(r'\s+'));
      final arTokens = <String>[];

      for (final tok in enTokens) {
        final arWord = englishToArabicTerms[tok];
        if (arWord != null) {
          arTokens.add(arWord);
          if (_isKnownBrand(tok)) {
            detectedBrand ??= tok;
          } else {
            detectedAttr ??= tok;
          }
        } else {
          arTokens.add(tok);
        }
      }

      if (arTokens.isNotEmpty && arTokens.any((t) => RegExp(r'[\u0600-\u06FF]').hasMatch(t))) {
        repairedAr = arTokens.join(' ');
      } else {
        final gTrans = await translateViaGoogle(repairedEn, targetLang: 'ar');
        repairedAr = gTrans ?? repairedEn;
      }
    }

    return ResolvedQuery(
      originalQuery: trimmed,
      repairedArabicQuery: repairedAr,
      repairedEnglishQuery: repairedEn,
      brand: detectedBrand,
      formOrAttribute: detectedAttr,
      wasCorrected: wasCorrected,
      suggestions: suggestions,
    );
  }

  static bool _isKnownBrand(String word) {
    const brands = {
      'pantene', 'vaseline', 'cetaphil', 'panadol', 'cerave', 'bioderma',
      'eucerin', 'cosrx', 'bepanthen', 'neutrogena', 'dove', 'loreal',
      'garnier', 'vichy', 'avene', 'voltaren', 'brufen', 'ogx', 'qv'
    };
    return brands.contains(word.toLowerCase());
  }

  /// Backward-compatible method calling [resolveQuery].
  Future<QueryCorrectionResult> correctQuery(String rawQuery) async {
    final resolved = await resolveQuery(rawQuery);
    return QueryCorrectionResult(
      originalQuery: resolved.originalQuery,
      correctedQuery: resolved.primaryQuery,
      wasCorrected: resolved.wasCorrected,
      suggestions: resolved.suggestions,
    );
  }

  /// Backward-compatible local-only correction.
  String correctLocalOnly(String query) {
    final trimmed = query.trim();
    if (trimmed.isEmpty) return trimmed;
    final isArabic = RegExp(r'[\u0600-\u06FF]').hasMatch(trimmed);

    if (isArabic) {
      final norm = normalizeArabicOrthography(trimmed);
      if (_arabicPhoneticMap.containsKey(norm)) {
        return _arabicPhoneticMap[norm]!;
      }
      if (_arabicPhoneticMap.containsKey(trimmed)) {
        return _arabicPhoneticMap[trimmed]!;
      }
    }

    var text = trimmed;
    if (isArabic) {
      final multiWordEntries = _arabicPhoneticMap.entries.where((e) => e.key.contains(' ')).toList();
      for (final entry in multiWordEntries) {
        if (text.contains(entry.key)) {
          text = text.replaceAll(entry.key, entry.value);
        }
      }
    }

    final tokenList = text.split(RegExp(r'\s+')).where((t) => t.isNotEmpty).toList();
    final repaired = <String>[];
    for (var i = 0; i < tokenList.length; i++) {
      final t = tokenList[i];
      if (t == 'لاروش' && i + 1 < tokenList.length && (tokenList[i + 1] == 'بوزيه' || tokenList[i + 1] == 'بوزي')) {
        repaired.add(t);
      } else {
        repaired.add(_repairTokenStageA(t, isArabic: isArabic));
      }
    }
    return repaired.join(' ');
  }

  /// Autocompletes user input by blending instant local brand matches with Google suggestions.
  Future<List<String>> getSuggestions(String query) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) return const [];

    final lower = trimmed.toLowerCase();
    final results = <String>[];

    // 1. Instant local brand/keyword suggestions
    for (final word in canonicalVocabulary) {
      if (word.startsWith(lower) && word != lower) {
        results.add(word);
        if (results.length >= 3) break;
      }
    }

    // Arabic instant completions
    if (RegExp(r'[\u0600-\u06FF]').hasMatch(trimmed)) {
      final norm = normalizeArabicOrthography(trimmed);
      for (final entry in arabicToEnglishTerms.keys) {
        if (entry.startsWith(norm) && entry != norm) {
          results.add(entry);
          if (results.length >= 3) break;
        }
      }
    }

    // 2. Fetch live Google suggestions in parallel
    final googleSuggestions = await fetchGoogleSuggestions(trimmed);
    for (final s in googleSuggestions) {
      if (!results.contains(s) && s.toLowerCase() != lower) {
        results.add(s);
      }
      if (results.length >= 6) break;
    }

    return results;
  }
}
