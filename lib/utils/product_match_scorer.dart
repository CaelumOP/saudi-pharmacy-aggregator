import 'dart:math';
import '../domain/models/pharmacy_offer.dart';

/// 4-Layer Semantic Anti-False-Positive Engine.
///
/// Prevents false matches across pharmacy catalogs by enforcing:
/// 1. Bilingual normalization (Arabic <-> English) and generic stopword elimination.
/// 2. Product form conflict blocking (e.g., Shampoo vs Oil, Cleanser vs Cream, Tablets vs Syrup).
/// 3. Mandatory brand locking when validating against a reference product.
/// 4. Distinctive token overlap gating (1-word: 100%, 2-word: 100%, 3+ words: >= 60% with min 2 tokens).
class ProductMatchScorer {
  ProductMatchScorer._();

  static const Set<String> _babyPediatricTokens = {
    'baby',
    'kids',
    'kid',
    'infant',
    'infants',
    'children',
    'child',
    'junior',
    'pediatric',
    'newborn',
    'اطفال',
    'أطفال',
    'الاطفال',
    'الأطفال',
    'للاطفال',
    'للأطفال',
    'بالاطفال',
    'بالأطفال',
    'بيبي',
    'رضع',
    'الرضع',
    'للرضع',
    'مواليد',
    'المواليد',
  };

  static const Set<String> _stopwords = {
    'for',
    'with',
    'and',
    'the',
    'to',
    'in',
    'of',
    'on',
    'by',
    'from',
    'skin',
    'face',
    'body',
    'hair',
    'care',
    'daily',
    'all',
    'types',
    'normal',
    'dry',
    'oily',
    'sensitive',
    'combination',
    'new',
    'pack',
    'offer',
    'special',
    'free',
    'ml',
    'mg',
    'gm',
    'g',
    'l',
    'oz',
    'tabs',
    'tablets',
    'tablet',
    'tab',
    'capsules',
    'capsule',
    'caplets',
    'caplet',
    'pcs',
    'للبشرة',
    'للشعر',
    'للوجه',
    'للجسم',
    'مع',
    'من',
    'في',
    'كل',
    'انواع',
    'العادية',
    'الجافة',
    'الدهنية',
    'الحساسة',
    'مل',
    'جم',
  };

  static const Map<String, String> _multiWordReplacements = {
    'لاروش بوزيه': 'laroche',
    'la roche posay': 'laroche',
    'la roche': 'laroche',
    'بيوتي اوف جوسون': 'joseon',
    'beauty of joseon': 'joseon',
    'سوم باي مي': 'somebymi',
    'some by mi': 'somebymi',
    'سكين 1004': 'skin1004',
    'skin 1004': 'skin1004',
    'اوجي اكس': 'ogx',
    'ogx': 'ogx',
    'واقي شمس': 'sunscreen',
    'sun block': 'sunscreen',
  };

  static const Map<String, String> _bilingualMap = {
    // Brands
    'بانتين': 'pantene',
    'فازلين': 'vaseline',
    'سيتافيل': 'cetaphil',
    'بنادول': 'panadol',
    'بيوديرما': 'bioderma',
    'سيرافي': 'cerave',
    'لاروش': 'laroche',
    'يوسيرين': 'eucerin',
    'افين': 'avene',
    'فيشي': 'vichy',
    'كوسركس': 'cosrx',
    'انوا': 'anua',
    'جوسون': 'joseon',
    'ميديكيوب': 'medicube',
    'ناو': 'now',
    // Modifiers & Concerns
    'اكسترا': 'extra',
    'ادفانس': 'advance',
    'نايت': 'night',
    'تطاير': 'frizz',
    'هيشان': 'frizz',
    'كيرلي': 'curly',
    'كرلي': 'curly',
    'مجعد': 'curly',
    'انسيابي': 'smooth',
    'حلزون': 'snail',
    // Forms
    'غسول': 'cleanser',
    'وغسول': 'cleanser',
    'منظف': 'cleanser',
    'ومنظف': 'cleanser',
    'مرطب': 'moisturizer',
    'ومرطب': 'moisturizer',
    'كريم': 'cream',
    'وكريم': 'cream',
    'لوشن': 'lotion',
    'ولوشن': 'lotion',
    'سيروم': 'serum',
    'وسيروم': 'serum',
    'تونر': 'toner',
    'شامبو': 'shampoo',
    'وشامبو': 'shampoo',
    'بلسم': 'conditioner',
    'وبلسم': 'conditioner',
    'زيت': 'oil',
    'وزيت': 'oil',
    'اقراص': 'tablets',
    'حبوب': 'tablets',
    'كبسولات': 'capsules',
    'شراب': 'syrup',
    'tablet': 'tablets',
    'caplet': 'caplets',
    'capsule': 'capsules',
  };

  static const Set<String> knownBrands = {
    'pantene',
    'vaseline',
    'cetaphil',
    'panadol',
    'bioderma',
    'cerave',
    'laroche',
    'eucerin',
    'avene',
    'vichy',
    'cosrx',
    'anua',
    'joseon',
    'medicube',
    'somebymi',
    'skin1004',
    'ogx',
    'now',
  };

  static const Set<String> _hairSkinConcernTokens = {
    'frizz',
    'curly',
    'smooth',
    'damage',
    'repair',
    'split',
    'hairfall',
    'dandruff',
    'snail',
    'moisture',
    'dryness',
  };

  static const Set<String> _hairFrizzRelatedTokens = {
    'frizz',
    'smooth',
    'control',
    'antifrizz',
    'curly',
    'repair',
    'تطاير',
    'هيشان',
    'انسيابي',
    'كيرلي',
    'بديل',
    'الزيت',
    'ناعم',
    'تمليس',
    'حماية',
  };

  static const Set<String> _cleanserFamily = {'cleanser', 'wash', 'foaming', 'micellar'};
  static const Set<String> _moisturizerFamily = {'lotion', 'moisturizer'};
  static const Set<String> _creamFamily = {'cream', 'balm', 'ointment'};
  static const Set<String> _sunscreenFamily = {'sunscreen', 'spf', 'sunblock'};
  static const Set<String> _serumFamily = {'serum', 'ampoule', 'toner'};

  static const Set<String> _solidOralFamily = {'tablet', 'tablets', 'caplet', 'caplets', 'capsule', 'capsules'};
  static const Set<String> _liquidOralFamily = {'syrup', 'suspension', 'drops', 'spray'};
  static const Set<String> _rectalFamily = {'suppository', 'suppositories'};

  /// Computes a semantic match score between [queryOrRefTitle] and [candidateTitle].
  ///
  /// Returns a value between `0.0` (rejected) and `1.0` (high confidence match).
  /// Rejects candidate with `0.0` if:
  /// - Form conflict is detected (Layer 2)
  /// - Brand mismatch occurs on reference comparison (Layer 3)
  /// - Distinctive token overlap falls below threshold (Layer 4)
  static double score(
    String queryOrRefTitle,
    String candidateTitle, {
    bool isReferenceComparison = false,
  }) {
    final queryTokens = _extractDistinctiveTokens(queryOrRefTitle);
    final candidateTokens = _extractDistinctiveTokens(candidateTitle);

    if (queryTokens.isEmpty || candidateTokens.isEmpty) {
      return 0.0;
    }

    // Layer 1.5: Demographic Line Conflict Blocker (Baby / Kids vs Adult)
    if (_hasDemographicConflict(queryOrRefTitle, candidateTitle)) {
      return 0.0;
    }

    // Layer 2: Product Form Conflict Blocker
    if (_hasFormConflict(queryOrRefTitle, candidateTitle)) {
      return 0.0;
    }

    // Layer 3: Mandatory Brand Lock
    final refBrand = _detectBrand(queryTokens);
    if (refBrand != null) {
      if (!candidateTokens.any((c) => _tokensMatch(refBrand, c))) {
        return 0.0;
      }
    } else if (isReferenceComparison) {
      // First distinctive token is treated as brand/anchor
      final mandatoryAnchor = queryTokens.first;
      if (!candidateTokens.any((c) => _tokensMatch(mandatoryAnchor, c))) {
        return 0.0;
      }
    }

    // Layer 4: Distinctive Token Overlap Gate
    final matchingTokens = queryTokens.where((t) => candidateTokens.any((c) => _tokensMatch(t, c))).toSet();

    if (queryTokens.length == 1) {
      // 1-word query: require 100% (1/1) match
      return matchingTokens.length == 1 ? 1.0 : 0.0;
    } else if (queryTokens.length == 2) {
      // 2-word query: require BOTH tokens (2/2 = 100%) to match by default.
      if (matchingTokens.length == 2) {
        return 1.0;
      }
      // If brand matched AND second word is a hair/skin concern/attribute (e.g. "Pantene Frizz")
      if (refBrand != null && matchingTokens.contains(refBrand)) {
        final secondToken = queryTokens.firstWhere((t) => t != refBrand);
        if (_hairSkinConcernTokens.contains(secondToken)) {
          // If candidate contains related frizz/smooth/curly/attribute words -> 0.85
          if (candidateTokens.any(_hairFrizzRelatedTokens.contains)) {
            return 0.85;
          }
          // Otherwise keep brand hair/skin care items at 0.62 baseline score so the user NEVER gets an empty 0-store screen!
          return 0.62;
        }
      }
      return 0.0;
    } else {
      // 3+ distinctive words: require at least 60% overlap and minimum 2 tokens
      if (matchingTokens.length < 2) {
        return 0.0;
      }
      final overlap = matchingTokens.length / queryTokens.length;
      return overlap >= 0.60 ? overlap : 0.0;
    }
  }

  /// Evaluates whether [candidate] is the same canonical product as [ref].
  ///
  /// Requires matching brand, compatible forms, and a match score >= 0.60.
  static bool isSameCanonicalProduct(PharmacyOffer ref, PharmacyOffer candidate) {
    final s = score(ref.productTitle, candidate.productTitle, isReferenceComparison: true);
    return s >= 0.60;
  }

  /// Filters candidate offers to ensure they match the canonical reference offer
  /// (Layer 2 form conflict check, Layer 3 brand lock, Layer 4 overlap >= 0.60),
  /// scoring each offer and sorting descending by match score.
  static List<PharmacyOffer> filterAndRankByReference(
    PharmacyOffer canonicalRef,
    List<PharmacyOffer> candidates,
  ) {
    final filtered = <PharmacyOffer>[];
    for (final candidate in candidates) {
      if (isSameCanonicalProduct(canonicalRef, candidate)) {
        final matchScore = score(
          canonicalRef.productTitle,
          candidate.productTitle,
          isReferenceComparison: true,
        );
        filtered.add(candidate.copyWith(matchScore: matchScore));
      }
    }
    filtered.sort((a, b) => b.matchScore.compareTo(a.matchScore));
    return filtered;
  }

  /// Returns the Arabic equivalent for a known English brand/term, or null if unmapped.
  static String? getArabicAlias(String query) {
    final lower = query.toLowerCase().trim();
    for (final entry in _bilingualMap.entries) {
      if (entry.value == lower && RegExp(r'[\u0600-\u06FF]').hasMatch(entry.key)) {
        return entry.key;
      }
    }
    for (final entry in _multiWordReplacements.entries) {
      if (entry.value == lower && RegExp(r'[\u0600-\u06FF]').hasMatch(entry.key)) {
        return entry.key;
      }
    }
    return null;
  }

  /// Normalizes string, applies bilingual dictionary, and strips stopwords.
  static List<String> _extractDistinctiveTokens(String raw) {
    final text = _normalizeText(raw);
    final rawTokens = text.split(RegExp(r'\s+')).where((w) => w.isNotEmpty);
    final distinctive = <String>[];

    for (final token in rawTokens) {
      final normalized = _bilingualMap[token] ?? token;
      if (_stopwords.contains(normalized)) {
        continue;
      }
      // Also ignore pure measurement digits (e.g. "100", "473") from distinctive brand/form calculations
      if (RegExp(r'^\d+$').hasMatch(normalized)) {
        continue;
      }
      distinctive.add(normalized);
    }

    return distinctive;
  }

  /// Normalizes text by replacing multi-word phrases, separating glued digits/units, and stripping punctuation.
  static String _normalizeText(String raw) {
    var text = raw.toLowerCase().trim();

    // Replace multi-word phrases first
    for (final entry in _multiWordReplacements.entries) {
      text = text.replaceAll(entry.key, entry.value);
    }

    // Separate attached digits and letters/units (e.g., "500mg" -> "500 mg", "24tablets" -> "24 tablets")
    // Preserving composite brands like "skin1004"
    text = text.replaceAllMapped(
      RegExp(r'(\d+)\s*([a-zA-Z\u0600-\u06FF]+)'),
      (m) {
        if (m[0] == 'skin1004') return 'skin1004';
        return '${m[1]} ${m[2]}';
      },
    );
    text = text.replaceAllMapped(
      RegExp(r'([a-zA-Z\u0600-\u06FF]+)\s*(\d+)'),
      (m) {
        if (m[0] == 'skin1004') return 'skin1004';
        return '${m[1]} ${m[2]}';
      },
    );

    // Replace punctuation with space
    text = text.replaceAll(RegExp(r'[^a-z0-9\u0600-\u06FF\s]'), ' ');

    // Normalize Arabic alef variants [أإآ] -> ا
    text = text.replaceAll(RegExp(r'[أإآ]'), 'ا');

    // Separate Arabic "و" (and) when prefixed to known forms/words
    text = text.replaceAllMapped(
      RegExp(r'(^|\s)و(شامبو|غسول|كريم|لوشن|بلسم|زيت|صابون|منظف|سيروم|تونر|اقراص|حبوب|كبسولات|شراب)(\s|$)'),
      (m) => '${m[1]}و ${m[2]}${m[3]}',
    );

    return text;
  }

  /// Detects whether [queryTitle] and [candidateTitle] exhibit a product form conflict.
  static bool _hasFormConflict(String titleA, String titleB) {
    final formsA = _detectForms(titleA);
    final formsB = _detectForms(titleB);

    // If either side has no recognizable forms, cannot determine conflict
    if (formsA.isEmpty || formsB.isEmpty) {
      return false;
    }

    // 1. Hair & Oils Conflict
    final isShampooA = formsA.contains('shampoo');
    final isShampooB = formsB.contains('shampoo');
    final isConditionerA = formsA.contains('conditioner');
    final isConditionerB = formsB.contains('conditioner');
    final isMaskA = formsA.contains('mask');
    final isMaskB = formsB.contains('mask');
    final isOilA = formsA.contains('oil');
    final isOilB = formsB.contains('oil');

    final hasHairFormA = isShampooA || isConditionerA || isMaskA || isOilA;
    final hasHairFormB = isShampooB || isConditionerB || isMaskB || isOilB;

    if (hasHairFormA && hasHairFormB) {
      if (isShampooA && !isShampooB) return true;
      if (isShampooB && !isShampooA) return true;
      if (isConditionerA && !isConditionerB) return true;
      if (isConditionerB && !isConditionerA) return true;
      if (isMaskA && !isMaskB) return true;
      if (isMaskB && !isMaskA) return true;
      if (isOilA && !isOilB) return true;
      if (isOilB && !isOilA) return true;
    }

    // 1.5. Cleanser vs Shampoo Conflict (e.g. Facial Cleanser vs Body Wash & Shampoo)
    final isCleanserA = formsA.any(_cleanserFamily.contains);
    final isCleanserB = formsB.any(_cleanserFamily.contains);
    if (isCleanserA && !isShampooA && isShampooB) return true;
    if (isCleanserB && !isShampooB && isShampooA) return true;

    // 2. Skincare Topicals Conflict
    final topicalsA = _getTopicalFamilies(formsA);
    final topicalsB = _getTopicalFamilies(formsB);
    if (topicalsA.isNotEmpty && topicalsB.isNotEmpty && topicalsA.intersection(topicalsB).isEmpty) {
      return true;
    }

    // 3. Oral vs Liquid vs Rectal Route Conflict
    final routesA = _getAdministrationRoutes(formsA);
    final routesB = _getAdministrationRoutes(formsB);
    if (routesA.isNotEmpty && routesB.isNotEmpty && routesA.intersection(routesB).isEmpty) {
      return true;
    }

    return false;
  }

  /// Detects demographic line mismatch (Adult vs Baby/Kids/Pediatric).
  static bool _hasDemographicConflict(String titleA, String titleB) {
    final normA = _normalizeText(titleA);
    final normB = _normalizeText(titleB);
    final tokensA = normA.split(RegExp(r'\s+')).toSet();
    final tokensB = normB.split(RegExp(r'\s+')).toSet();

    final isBabyA = tokensA.any(_babyPediatricTokens.contains) ||
        _babyPediatricTokens.any((t) => normA.contains(' $t ') || normA.startsWith('$t ') || normA.endsWith(' $t') || normA == t);
    final isBabyB = tokensB.any(_babyPediatricTokens.contains) ||
        _babyPediatricTokens.any((t) => normB.contains(' $t ') || normB.startsWith('$t ') || normB.endsWith(' $t') || normB == t);

    return isBabyA != isBabyB;
  }

  /// Returns true if [qToken] matches [cToken] via exact, prefix, or fuzzy Levenshtein similarity.
  static bool _tokensMatch(String qToken, String cToken) {
    if (qToken == cToken) return true;
    if (qToken.length >= 4 && cToken.startsWith(qToken)) return true;
    if (cToken.length >= 4 && qToken.startsWith(cToken)) return true;

    // Latin fuzzy Levenshtein match
    final isLatinQ = RegExp(r'^[a-z0-9]+$').hasMatch(qToken);
    final isLatinC = RegExp(r'^[a-z0-9]+$').hasMatch(cToken);
    if (isLatinQ && isLatinC && qToken.isNotEmpty && cToken.isNotEmpty && qToken[0] == cToken[0]) {
      final len = min(qToken.length, cToken.length);
      if (len >= 8) {
        if (_levenshtein(qToken, cToken) <= 2) return true;
      } else if (len >= 5) {
        if (_levenshtein(qToken, cToken) <= 1) return true;
      }
    }
    return false;
  }

  /// Calculates Levenshtein edit distance between [s1] and [s2].
  static int _levenshtein(String s1, String s2) {
    if (s1 == s2) return 0;
    if (s1.isEmpty) return s2.length;
    if (s2.isEmpty) return s1.length;

    var prev = List<int>.generate(s2.length + 1, (i) => i);
    var curr = List<int>.filled(s2.length + 1, 0);

    for (var i = 0; i < s1.length; i++) {
      curr[0] = i + 1;
      for (var j = 0; j < s2.length; j++) {
        final cost = s1[i] == s2[j] ? 0 : 1;
        final insertion = curr[j] + 1;
        final deletion = prev[j + 1] + 1;
        final substitution = prev[j] + cost;
        curr[j + 1] = min(insertion, min(deletion, substitution));
      }
      final temp = prev;
      prev = curr;
      curr = temp;
    }

    return prev[s2.length];
  }

  static Set<int> _getTopicalFamilies(Set<String> forms) {
    final families = <int>{};
    if (forms.any(_cleanserFamily.contains)) families.add(1);
    if (forms.any(_moisturizerFamily.contains)) families.add(2);
    if (forms.any(_creamFamily.contains)) families.add(3);
    if (forms.any(_sunscreenFamily.contains)) families.add(4);
    if (forms.any(_serumFamily.contains)) families.add(5);
    return families;
  }

  static Set<int> _getAdministrationRoutes(Set<String> forms) {
    final routes = <int>{};
    if (forms.any(_solidOralFamily.contains)) routes.add(1);
    if (forms.any(_liquidOralFamily.contains)) routes.add(2);
    if (forms.any(_rectalFamily.contains)) routes.add(3);
    return routes;
  }

  /// Extracts canonical form tokens with compound rule evaluation.
  static Set<String> _detectForms(String rawTitle) {
    final text = _normalizeText(rawTitle);
    final tokens = text.split(RegExp(r'\s+')).map((t) => _bilingualMap[t] ?? t).toSet();
    final detected = <String>{};

    // Hair checks
    if (tokens.contains('shampoo')) detected.add('shampoo');
    if (tokens.contains('conditioner')) detected.add('conditioner');
    if (tokens.contains('mask') || tokens.contains('masque')) detected.add('mask');

    // Compound rule for oil: "Argan Oil Shampoo" has form shampoo, NOT standalone oil.
    // Only classify as standalone oil if 'oil' appears WITHOUT shampoo, conditioner, cleanser, wash, lotion, cream, or serum.
    if (tokens.contains('oil')) {
      final hasCompoundOther = tokens.contains('shampoo') ||
          tokens.contains('conditioner') ||
          tokens.contains('cleanser') ||
          tokens.contains('wash') ||
          tokens.contains('lotion') ||
          tokens.contains('cream') ||
          tokens.contains('serum');
      if (!hasCompoundOther) {
        detected.add('oil');
      }
    }

    // Topicals
    for (final t in _cleanserFamily) {
      if (tokens.contains(t)) detected.add(t);
    }
    for (final t in _moisturizerFamily) {
      if (tokens.contains(t)) detected.add(t);
    }
    for (final t in _creamFamily) {
      if (tokens.contains(t)) detected.add(t);
    }
    for (final t in _sunscreenFamily) {
      if (tokens.contains(t)) detected.add(t);
    }
    for (final t in _serumFamily) {
      if (tokens.contains(t)) detected.add(t);
    }

    // Oral / Routes
    for (final t in _solidOralFamily) {
      if (tokens.contains(t)) detected.add(t);
    }
    for (final t in _liquidOralFamily) {
      if (tokens.contains(t)) detected.add(t);
    }
    for (final t in _rectalFamily) {
      if (tokens.contains(t)) detected.add(t);
    }

    return detected;
  }

  static String? _detectBrand(List<String> tokens) {
    for (final t in tokens) {
      if (knownBrands.contains(t)) {
        return t;
      }
    }
    return null;
  }
}
