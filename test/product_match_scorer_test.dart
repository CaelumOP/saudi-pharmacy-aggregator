import 'package:flutter_test/flutter_test.dart';
import 'package:pharmacy_app/domain/models/pharmacy_offer.dart';
import 'package:pharmacy_app/utils/product_match_scorer.dart';

void main() {
  group('ProductMatchScorer - Layer 1 Bilingual & Stopwords', () {
    test('matches Arabic brand and form to English equivalents', () {
      final score = ProductMatchScorer.score('غسول سيتافيل', 'Cetaphil Gentle Skin Cleanser 473ml');
      expect(score, greaterThanOrEqualTo(0.60));
    });

    test('matches Arabic Cetaphil moisturizing cream to English', () {
      final score = ProductMatchScorer.score('كريم مرطب سيتافيل', 'Cetaphil Moisturizing Cream 453g');
      expect(score, greaterThanOrEqualTo(0.60));
    });

    test('matches Arabic Panadol to English Panadol', () {
      final score = ProductMatchScorer.score('بنادول اكسترا', 'Panadol Extra 24 Tablets');
      expect(score, greaterThanOrEqualTo(0.60));
    });

    test('matches multi-word Arabic brands (La Roche Posay & Beauty of Joseon)', () {
      final score1 = ProductMatchScorer.score('لاروش بوزيه', 'La Roche Posay Effaclar');
      expect(score1, equals(1.0));

      final score2 = ProductMatchScorer.score('بيوتي اوف جوسون سيروم', 'Beauty of Joseon Glow Serum');
      expect(score2, greaterThanOrEqualTo(0.60));
    });
  });

  group('ProductMatchScorer - Layer 2 Form Conflict Blocker', () {
    test('rejects Shampoo vs Conditioner', () {
      final score = ProductMatchScorer.score('Ogx Shampoo', 'Ogx Conditioner 385ml');
      expect(score, equals(0.0));
    });

    test('rejects Cleanser vs Cream', () {
      final score = ProductMatchScorer.score('Cetaphil Cleanser', 'Cetaphil Moisturizing Cream 100g');
      expect(score, equals(0.0));
    });

    test('rejects Cleanser vs Sunscreen', () {
      final score = ProductMatchScorer.score('Cetaphil Cleanser', 'Cetaphil Sunblock SPF 50');
      expect(score, equals(0.0));
    });

    test('rejects Tablets vs Syrup', () {
      final score = ProductMatchScorer.score('Panadol Tablets', 'Panadol Baby Suspension Syrup 100ml');
      expect(score, equals(0.0));
    });

    test('handles compound rule: Argan Oil Shampoo has form shampoo, not standalone oil', () {
      // Comparing Argan Oil Shampoo against Standalone Argan Oil must reject
      final scoreOil = ProductMatchScorer.score('Argan Oil Shampoo', 'Argan Oil 100ml');
      expect(scoreOil, equals(0.0));

      // Comparing Ogx Shampoo against Ogx Argan Oil Shampoo must NOT reject
      final scoreShampoo = ProductMatchScorer.score('Ogx Shampoo', 'Ogx Argan Oil Shampoo 385ml');
      expect(scoreShampoo, greaterThanOrEqualTo(0.60));
    });
  });

  group('ProductMatchScorer - Layer 3 Mandatory Brand Lock', () {
    test('rejects candidate if mandatory brand is missing in reference comparison', () {
      const ref = PharmacyOffer(
        storeId: 'whites',
        pharmacyName: 'Whites',
        skuOrId: '123',
        productTitle: 'Cetaphil Gentle Skin Cleanser',
        singleUnitPrice: 89.0,
      );

      const candidateDifferentBrand = PharmacyOffer(
        storeId: 'nahdi',
        pharmacyName: 'Al-Nahdi',
        skuOrId: '456',
        productTitle: 'CeraVe Hydrating Cleanser',
        singleUnitPrice: 75.0,
      );

      final isSame = ProductMatchScorer.isSameCanonicalProduct(ref, candidateDifferentBrand);
      expect(isSame, isFalse);
    });

    test('accepts candidate with same brand and matching form', () {
      const ref = PharmacyOffer(
        storeId: 'whites',
        pharmacyName: 'Whites',
        skuOrId: '123',
        productTitle: 'Cetaphil Gentle Skin Cleanser 473ml',
        singleUnitPrice: 120.75,
      );

      const candidateSameBrand = PharmacyOffer(
        storeId: 'nahdi',
        pharmacyName: 'Al-Nahdi',
        skuOrId: '456',
        productTitle: 'Cetaphil Gentle Skin Cleanser - 473 ml',
        singleUnitPrice: 104.65,
      );

      final isSame = ProductMatchScorer.isSameCanonicalProduct(ref, candidateSameBrand);
      expect(isSame, isTrue);
    });
  });

  group('ProductMatchScorer - Layer 4 Distinctive Token Overlap Gate', () {
    test('1-word query: requires 1/1 match', () {
      expect(ProductMatchScorer.score('COSRX', 'COSRX Snail Essence'), equals(1.0));
      expect(ProductMatchScorer.score('COSRX', 'Cetaphil Cleanser'), equals(0.0));
    });

    test('2-word query: requires 2/2 match (never allow 1-word partial match)', () {
      // Query "Cetaphil Cleanser" (2 distinctive words: cetaphil, cleanser)
      // Candidate has both -> 1.0
      expect(ProductMatchScorer.score('Cetaphil Cleanser', 'Cetaphil Gentle Skin Cleanser'), equals(1.0));

      // Candidate has only "Cetaphil" (1 word match on 2-word query) -> STRICTLY 0.0
      expect(ProductMatchScorer.score('Cetaphil Cleanser', 'Cetaphil Daily Hydration'), equals(0.0));
    });

    test('3+ words query: requires at least 60% overlap and minimum 2 tokens', () {
      // 3 words: cetaphil, gentle, cleanser
      expect(ProductMatchScorer.score('Cetaphil Gentle Cleanser', 'Cetaphil Cleanser 473ml'), greaterThanOrEqualTo(0.60));
      expect(ProductMatchScorer.score('Cetaphil Gentle Cleanser', 'Cetaphil Bar 100g'), equals(0.0));
    });
  });

  group('ProductMatchScorer - Demographic Conflict & False Positive Rejections', () {
    test('rejects Nice One Baby Wash & Shampoo against adult Cetaphil Gentle Skin Cleanser', () {
      const refTitle = 'Cetaphil Gentle Skin Cleanser 473ml';
      const candidateTitle = 'غسول وشامبو الاطفال للوجه والجسم من سيتافيل - 400 مل';

      final score = ProductMatchScorer.score(refTitle, candidateTitle);
      expect(score, equals(0.0), reason: 'Baby wash must never match adult gentle cleanser');

      const refOffer = PharmacyOffer(
        storeId: 'whites',
        pharmacyName: 'Whites',
        skuOrId: '1001',
        productTitle: refTitle,
        singleUnitPrice: 104.0,
      );

      const candidateOffer = PharmacyOffer(
        storeId: 'nice_one',
        pharmacyName: 'Nice One',
        skuOrId: '2002',
        productTitle: candidateTitle,
        singleUnitPrice: 65.0,
      );

      final isSame = ProductMatchScorer.isSameCanonicalProduct(refOffer, candidateOffer);
      expect(isSame, isFalse);
    });

    test('rejects Adult Panadol against Panadol Baby / Infant Suspension', () {
      final score = ProductMatchScorer.score('Panadol Extra 500mg Tablets', 'Panadol Baby & Infant 100ml');
      expect(score, equals(0.0));
    });

    test('permits match when both items are in the baby/pediatric line', () {
      final score = ProductMatchScorer.score('سيتافيل شامبو اطفال 400 مل', 'Cetaphil Baby Wash and Shampoo 400ml');
      expect(score, greaterThanOrEqualTo(0.60));
    });
  });
}
