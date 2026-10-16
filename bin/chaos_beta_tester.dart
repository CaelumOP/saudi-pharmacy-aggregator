// ignore_for_file: avoid_print
import 'dart:async';
import 'package:pharmacy_app/services/pharmacy_aggregator_orchestrator.dart';
import 'package:pharmacy_app/services/smart_query_corrector.dart';

Future<void> main(List<String> args) async {
  print('================================================================================');
  print('  CHAOS BETA-TESTER: VECTOR 1B BRUTAL MULTI-WORD & FAT-FINGER TORTURE RUNNER');
  print('================================================================================\n');

  final orchestrator = PharmacyAggregatorOrchestrator();
  final corrector = SmartQueryCorrector.instance;

  final testCases = [
    {
      'query': 'بامنيت تكاير',
      'expectedBrand': 'pantene',
      'expectedAttr': 'frizz',
      'expectedAr': 'بانتين تطاير',
      'expectedEn': 'Pantene Frizz',
      'minOffers': 1,
    },
    {
      'query': 'بنتين كرلي',
      'expectedBrand': 'pantene',
      'expectedAttr': 'curly',
      'expectedAr': 'بانتين كيرلي',
      'expectedEn': 'Pantene Curly',
      'minOffers': 1,
    },
    {
      'query': 'سيتفايل غسلو',
      'expectedBrand': 'cetaphil',
      'expectedAttr': 'cleanser',
      'expectedAr': 'سيتافيل غسول',
      'expectedEn': 'Cetaphil Cleanser',
      'minOffers': 1,
    },
    {
      'query': 'بنادلو اكسرتا',
      'expectedBrand': 'panadol',
      'expectedAttr': 'extra',
      'expectedAr': 'بنادول اكسترا',
      'expectedEn': 'Panadol Extra',
      'minOffers': 1,
    },
    {
      'query': 'كوزركس حلوزن',
      'expectedBrand': 'cosrx',
      'expectedAttr': 'snail',
      'expectedAr': 'كوسركس حلزون',
      'expectedEn': 'COSRX Snail',
      'minOffers': 1,
    },
    {
      'query': 'فزالين',
      'expectedBrand': 'vaseline',
      'expectedAttr': null,
      'expectedAr': 'فازلين',
      'expectedEn': 'Vaseline',
      'minOffers': 5,
    },
    {
      'query': 'pnatene frziz',
      'expectedBrand': 'pantene',
      'expectedAttr': 'frizz',
      'expectedAr': 'بانتين تطاير',
      'expectedEn': 'Pantene Frizz',
      'minOffers': 1,
    },
    {
      'query': 'cetfial clenaser',
      'expectedBrand': 'cetaphil',
      'expectedAttr': 'cleanser',
      'expectedAr': 'سيتافيل غسول',
      'expectedEn': 'Cetaphil Cleanser',
      'minOffers': 1,
    },
  ];

  var allPassed = true;
  final results = <Map<String, dynamic>>[];

  for (final tc in testCases) {
    final query = tc['query'] as String;
    final expectedBrand = tc['expectedBrand'] as String?;
    final minOffers = tc['minOffers'] as int;

    final stopwatch = Stopwatch()..start();
    final resolved = await corrector.resolveQuery(query);
    stopwatch.stop();

    print('--------------------------------------------------------------------------------');
    print('Testing query: "$query"');
    print('  - Resolution Time: ${stopwatch.elapsedMilliseconds}ms');
    print('  - Repaired Arabic: "${resolved.repairedArabicQuery}"');
    print('  - Repaired English: "${resolved.repairedEnglishQuery}"');
    print('  - Extracted Brand: ${resolved.brand} (Arabic: ${resolved.arabicBrand}, English: ${resolved.englishBrand})');
    print('  - Extracted Form/Attr: ${resolved.formOrAttribute}');
    print('  - Was Corrected: ${resolved.wasCorrected}');

    // Execute search across orchestrator
    final searchSw = Stopwatch()..start();
    final laneResults = await orchestrator.searchByKeyword(query, limit: 5).toList();
    searchSw.stop();

    final completedLanes = laneResults.where((r) => r.status == StoreLaneStatus.completed).toList();
    final storesWithOffers = completedLanes.where((r) => r.offers.isNotEmpty).toList();
    final totalOffers = completedLanes.fold<int>(0, (acc, r) => acc + r.offers.length);

    print('  - Search Duration: ${searchSw.elapsedMilliseconds}ms');
    print('  - Responding Stores: ${completedLanes.length} / ${orchestrator.adapters.length}');
    print('  - Stores with Matches: ${storesWithOffers.length} (${storesWithOffers.map((s) => s.storeId).join(', ')})');
    print('  - Total Ranked Offers: $totalOffers');

    if (storesWithOffers.isNotEmpty) {
      final topLane = storesWithOffers.first;
      final topOffer = topLane.offers.first;
      print('  - Sample Top Match [${topLane.storeName}]: "${topOffer.productTitle}" @ ${topOffer.singleUnitPrice.toStringAsFixed(2)} SAR (Score: ${topOffer.matchScore.toStringAsFixed(2)})');
    }

    final brandMatch = resolved.brand == expectedBrand;
    final correctionMatch = resolved.wasCorrected;
    final offersMatch = totalOffers >= minOffers;

    final isPass = brandMatch && correctionMatch && offersMatch;
    if (!isPass) {
      allPassed = false;
      print('  ❌ FAILURE: brandMatch=$brandMatch, correctionMatch=$correctionMatch, offersMatch=$offersMatch (min: $minOffers, got: $totalOffers)');
    } else {
      print('  ✅ PASS: All Vector 1B criteria satisfied');
    }

    results.add({
      'query': query,
      'repairedAr': resolved.repairedArabicQuery,
      'repairedEn': resolved.repairedEnglishQuery,
      'brand': resolved.brand,
      'attr': resolved.formOrAttribute,
      'storesWithMatches': storesWithOffers.length,
      'totalOffers': totalOffers,
      'status': isPass ? 'PASS' : 'FAIL',
    });
  }

  print('\n================================================================================');
  print('  VECTOR 1B SCORECARD TABLE');
  print('================================================================================');
  print('| Input Query       | Repaired AR       | Repaired EN       | Brand    | Matches | Offers | Status |');
  print('|-------------------|-------------------|-------------------|----------|---------|--------|--------|');
  for (final r in results) {
    final q = (r['query'] as String).padRight(17);
    final ar = (r['repairedAr'] as String).padRight(17);
    final en = (r['repairedEn'] as String).padRight(17);
    final brand = (r['brand'] as String? ?? '-').padRight(8);
    final stores = (r['storesWithMatches'].toString()).padRight(7);
    final offers = (r['totalOffers'].toString()).padRight(6);
    final status = r['status'] as String;
    print('| $q | $ar | $en | $brand | $stores | $offers | $status   |');
  }
  print('================================================================================');

  if (allPassed) {
    print('🎉 ALL 8 TORTURE TESTS PASSED WITH 100% RECOVERY!');
  } else {
    print('⚠️ SOME TORTURE TESTS FAILED');
  }
}
