import 'package:flutter_test/flutter_test.dart';
import 'package:pharmacy_app/domain/models/pharmacy_offer.dart';
import 'package:pharmacy_app/adapters/pharmacy_adapter.dart';
import 'package:pharmacy_app/services/pharmacy_aggregator_orchestrator.dart';
import 'package:pharmacy_app/services/smart_query_corrector.dart';
import 'package:pharmacy_app/utils/product_match_scorer.dart';

class MockTestAdapter implements PharmacyAdapter {
  @override
  final String storeId;
  @override
  final String storeName;
  @override
  final StorePresenceType presenceType;
  @override
  final StoreSpecialty specialty;

  final Map<String, List<PharmacyOffer>> mockResponses;

  MockTestAdapter({
    required this.storeId,
    required this.storeName,
    this.presenceType = StorePresenceType.physicalAndOnline,
    this.specialty = StoreSpecialty.pharmacyAndCare,
    required this.mockResponses,
  });

  @override
  String get baseUrl => 'https://mock.$storeId.com';

  @override
  Map<String, String> get defaultHeaders => {};

  @override
  Future<List<PharmacyOffer>> searchByBarcode(String gtin) async => const [];

  @override
  Future<List<PharmacyOffer>> searchByKeyword(String query, {int limit = 5}) async {
    final q = query.trim().toLowerCase();
    for (final entry in mockResponses.entries) {
      if (entry.key.toLowerCase() == q) {
        return entry.value;
      }
    }
    return const [];
  }
}

void main() {
  group('Vector 1B: Brutal Multi-Word Mangling & Keyboard Fat-Finger Torture Test', () {
    final corrector = SmartQueryCorrector();

    test('Case 1: "بامنيت تكاير" recovers to Pantene Frizz / بانتين تطاير', () async {
      final res = await corrector.resolveQuery('بامنيت تكاير');
      expect(res.wasCorrected, isTrue);
      expect(res.brand, equals('pantene'));
      expect(res.formOrAttribute, equals('frizz'));
      expect(res.repairedArabicQuery, equals('بانتين تطاير'));
      expect(res.repairedEnglishQuery, equals('Pantene Frizz'));
    });

    test('Case 2: "بنتين كرلي" recovers to Pantene Curly / بانتين كيرلي', () async {
      final res = await corrector.resolveQuery('بنتين كرلي');
      expect(res.wasCorrected, isTrue);
      expect(res.brand, equals('pantene'));
      expect(res.formOrAttribute, equals('curly'));
      expect(res.repairedArabicQuery, equals('بانتين كيرلي'));
      expect(res.repairedEnglishQuery, equals('Pantene Curly'));
    });

    test('Case 3: "سيتفايل غسلو" recovers to Cetaphil Cleanser / سيتافيل غسول', () async {
      final res = await corrector.resolveQuery('سيتفايل غسلو');
      expect(res.wasCorrected, isTrue);
      expect(res.brand, equals('cetaphil'));
      expect(res.formOrAttribute, equals('cleanser'));
      expect(res.repairedArabicQuery, equals('سيتافيل غسول'));
      expect(res.repairedEnglishQuery, equals('Cetaphil Cleanser'));
    });

    test('Case 4: "بنادلو اكسرتا" recovers to Panadol Extra / بنادول اكسترا', () async {
      final res = await corrector.resolveQuery('بنادلو اكسرتا');
      expect(res.wasCorrected, isTrue);
      expect(res.brand, equals('panadol'));
      expect(res.formOrAttribute, equals('extra'));
      expect(res.repairedArabicQuery, equals('بنادول اكسترا'));
      expect(res.repairedEnglishQuery, equals('Panadol Extra'));
    });

    test('Case 5: "كوزركس حلوزن" recovers to COSRX Snail / كوسركس حلزون', () async {
      final res = await corrector.resolveQuery('كوزركس حلوزن');
      expect(res.wasCorrected, isTrue);
      expect(res.brand, equals('cosrx'));
      expect(res.formOrAttribute, equals('snail'));
      expect(res.repairedArabicQuery, equals('كوسركس حلزون'));
      expect(res.repairedEnglishQuery, equals('COSRX Snail'));
    });

    test('Case 6: "فزالين" recovers to Vaseline / فازلين', () async {
      final res = await corrector.resolveQuery('فزالين');
      expect(res.wasCorrected, isTrue);
      expect(res.brand, equals('vaseline'));
      expect(res.repairedArabicQuery, equals('فازلين'));
      expect(res.repairedEnglishQuery, equals('Vaseline'));
    });

    test('Case 7: "pnatene frziz" recovers to Pantene Frizz / بانتين تطاير', () async {
      final res = await corrector.resolveQuery('pnatene frziz');
      expect(res.wasCorrected, isTrue);
      expect(res.brand, equals('pantene'));
      expect(res.formOrAttribute, equals('frizz'));
      expect(res.repairedArabicQuery, equals('بانتين تطاير'));
      expect(res.repairedEnglishQuery, equals('Pantene Frizz'));
    });

    test('Case 8: "cetfial clenaser" recovers to Cetaphil Cleanser / سيتافيل غسول', () async {
      final res = await corrector.resolveQuery('cetfial clenaser');
      expect(res.wasCorrected, isTrue);
      expect(res.brand, equals('cetaphil'));
      expect(res.formOrAttribute, equals('cleanser'));
      expect(res.repairedArabicQuery, equals('سيتافيل غسول'));
      expect(res.repairedEnglishQuery, equals('Cetaphil Cleanser'));
    });
  });

  group('Vector 1B: Orchestrator Fallback & Attribute Matching', () {
    test('Orchestrator dispatches brand fallback when store has 0 hits for 2-word query', () async {
      final mockAdapter = MockTestAdapter(
        storeId: 'al_nahdi',
        storeName: 'Al-Nahdi',
        mockResponses: {
          // Store has 0 hits for "بانتين تطاير", but returns items on fallback "بانتين"
          'بانتين': [
            PharmacyOffer(
              storeId: 'al_nahdi',
              pharmacyName: 'Al-Nahdi',
              skuOrId: 'nahdi-1',
              productTitle: 'بديل الزيت بانتين حماية من تطاير الشعر 350 مل',
              productUrl: 'https://nahdi.sa/pantene-frizz',
              imageUrl: '',
              singleUnitPrice: 24.50,
              unitQuantity: 350,
              unitMetric: 'ml',
              isOnlineInStock: true,
            ),
            PharmacyOffer(
              storeId: 'al_nahdi',
              pharmacyName: 'Al-Nahdi',
              skuOrId: 'nahdi-2',
              productTitle: 'شامبو بانتين للشعر الجاف 400 مل',
              productUrl: 'https://nahdi.sa/pantene-dry',
              imageUrl: '',
              singleUnitPrice: 22.00,
              unitQuantity: 400,
              unitMetric: 'ml',
              isOnlineInStock: true,
            ),
          ],
        },
      );

      final orchestrator = PharmacyAggregatorOrchestrator(
        adapters: [mockAdapter],
        enabledStoreIds: {'al_nahdi'},
      );

      final results = await orchestrator.searchByKeyword('بامنيت تكاير').toList();
      final completed = results.where((r) => r.status == StoreLaneStatus.completed).toList();

      expect(completed.isNotEmpty, isTrue);
      final lane = completed.first;
      expect(lane.isFallbackSearch, isTrue);
      expect(lane.offers.length, equals(2));

      // Anti-frizz item matches both tokens (1.0) and ranks #1
      expect(lane.offers.first.productTitle, contains('تطاير'));
      expect(lane.offers.first.matchScore, equals(1.0));

      // General brand item must score 0.62 baseline and rank #2
      expect(lane.offers.last.matchScore, equals(0.62));
    });

    test('ProductMatchScorer rejects form conflicts while supporting concern matching', () {
      // Rejects Shampoo vs Oil
      expect(ProductMatchScorer.score('شامبو بانتين', 'زيت شعر بانتين'), equals(0.0));
      // Rejects Cleanser vs Cream
      expect(ProductMatchScorer.score('غسول سيتافيل', 'كريم سيتافيل'), equals(0.0));
      // Exact 2-token match
      expect(ProductMatchScorer.score('بانتين تطاير', 'بديل الزيت بانتين حماية من تطاير الشعر'), equals(1.0));
      // Concern related match (frizz query -> smooth product) gives 0.85
      expect(ProductMatchScorer.score('Pantene Frizz', 'Pantene Pro-V Smooth & Sleek Shampoo'), equals(0.85));
      // Baseline 0.62 for same-brand hair care item without frizz/smooth
      expect(ProductMatchScorer.score('Pantene Frizz', 'Pantene Pro-V Classic Clean Shampoo'), equals(0.62));
    });
  });
}
