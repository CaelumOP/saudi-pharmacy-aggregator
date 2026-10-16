// ignore_for_file: avoid_print
import 'dart:async';
import 'package:pharmacy_app/domain/models/pharmacy_offer.dart';
import 'package:pharmacy_app/domain/models/promo_deal.dart';
import 'package:pharmacy_app/services/pharmacy_aggregator_orchestrator.dart';
import 'package:pharmacy_app/utils/product_match_scorer.dart';

void main(List<String> args) async {
  String? barcode;
  String? query;

  for (int i = 0; i < args.length; i++) {
    if (args[i] == '--barcode' && i + 1 < args.length) {
      barcode = args[i + 1];
    } else if (args[i] == '--query' && i + 1 < args.length) {
      query = args[i + 1];
    }
  }

  // Default to Cetaphil Gentle Cleanser barcode if no arguments provided
  if (barcode == null && query == null) {
    barcode = '3499320017046';
  }

  final isBarcodeSearch = barcode != null;
  final searchTerm = isBarcodeSearch ? barcode : query!;

  print('========================================================================');
  print('  SAUDI PHARMACY PRICE & PROMO AGGREGATOR — LIVE CLI RECON SCAN');
  print('========================================================================');
  print('Target Mode : ${isBarcodeSearch ? "GTIN Barcode Lookup (Two-Stage Cascade)" : "Keyword Search"}');
  print('Search Term : $searchTerm');
  final orchestrator = PharmacyAggregatorOrchestrator();
  print('Streaming live responses from ${orchestrator.adapters.map((a) => a.storeName).join(", ")}...\n');

  final stream = isBarcodeSearch
      ? orchestrator.searchByBarcode(searchTerm)
      : orchestrator.searchByKeyword(
          searchTerm,
          onCorrection: (res) {
            if (res.wasCorrected) {
              print('>> [SMART AUTO-CORRECT] "${res.originalQuery}" -> "${res.correctedQuery}"\n');
            }
          },
        );

  final completedLanes = <String, StoreSearchResult>{};

  final completer = Completer<void>();

  stream.listen(
    (update) {
      if (update.status == StoreLaneStatus.completed) {
        completedLanes[update.storeId] = update;
        print('>> [LANE RESPONDED] ${update.storeName}');
        if (update.offers.isEmpty) {
          print('   Status: No matches found ${update.isFallbackSearch ? "(after title fallback)" : ""}');
        } else {
          for (final offer in update.offers) {
            print('   • Product    : ${offer.productTitle}');
            print('     SKU / ID   : ${offer.skuOrId}');
            print('     Stock      : ${offer.isOnlineInStock ? "IN STOCK" : "OUT OF STOCK"}');
            print('     Match Type : ${offer.isFallbackMatch ? "Stage 3 Title Fallback" : "Direct Barcode/Query Match"}');
            print('     Tax / SFDA : ${offer.isSfdaRegulated ? "0% VAT (SFDA Drug)" : "15% VAT Included"}');

            // Tier 1 Pricing
            final basePriceStr = offer.pricePerBaseUnit != null && offer.unitMetric != null
                ? ' (${offer.pricePerBaseUnit!.toStringAsFixed(2)} SAR / ${offer.baseUnitDisplayMetric})'
                : '';
            print('     [TIER 1] Single Cash Price : ${offer.singleUnitPrice.toStringAsFixed(2)} SAR$basePriceStr');

            // Tier 2 Promotions
            if (offer.multiBuyPromos.isNotEmpty) {
              for (final promo in offer.multiBuyPromos) {
                print('     [TIER 2] Active Promo      : "${promo.label}" -> Buy ${promo.requiredQuantity} for ${promo.totalCheckoutCost.toStringAsFixed(2)} SAR (Effective: ${promo.effectiveUnitPrice.toStringAsFixed(2)} SAR/unit)');
              }
            } else {
              print('     [TIER 2] Active Promo      : None');
            }
          }
        }
        print('');
      } else if (update.status == StoreLaneStatus.challengeRequired) {
        completedLanes[update.storeId] = update;
        print('>> [CHALLENGE REQUIRED] ${update.storeName}');
        print('   Cloudflare Turnstile challenge triggered: ${update.challengeUrl}\n');
      } else if (update.status == StoreLaneStatus.error) {
        completedLanes[update.storeId] = update;
        print('>> [ERROR] ${update.storeName}: ${update.errorMessage}\n');
      }
    },
    onDone: () => completer.complete(),
    onError: (err) {
      print('Stream error: $err');
      completer.complete();
    },
  );

  await completer.future;

  print('========================================================================');
  print('  COMPARISON SUMMARY');
  print('========================================================================');

  // Collect all offers across completed lanes
  final allOffers = <PharmacyOffer>[];
  for (final result in completedLanes.values) {
    allOffers.addAll(result.offers.where((o) => o.singleUnitPrice > 0));
  }

  // Detect reference package size (direct barcode match takes precedence)
  PharmacyOffer? refOffer;
  for (final result in completedLanes.values) {
    for (final offer in result.offers) {
      if (!offer.isFallbackMatch && offer.unitQuantity != null && offer.unitMetric != null) {
        refOffer = offer;
        break;
      }
    }
    if (refOffer != null) break;
  }

  final topOffers = completedLanes.values
      .where((r) => r.offers.isNotEmpty)
      .map((r) => r.offers.first)
      .where((o) => o.unitQuantity != null && o.unitMetric != null)
      .toList();

  if (refOffer == null && topOffers.isNotEmpty) {
    refOffer = topOffers.first;
  }

  // Canonical brand and form consistency filter via ProductMatchScorer
  List<PharmacyOffer> brandFilteredOffers = allOffers;
  final currentRef = refOffer;
  if (currentRef != null) {
    final matches = allOffers
        .where((o) => ProductMatchScorer.isSameCanonicalProduct(currentRef, o))
        .toList();
    if (matches.isNotEmpty) {
      brandFilteredOffers = matches;
    }
  }

  final targetQty = refOffer?.unitQuantity;
  final targetMetric = refOffer?.unitMetric?.toLowerCase().trim();
  final hasTargetSize = targetQty != null && targetMetric != null;

  final sizeMatchedOffers = hasTargetSize
      ? brandFilteredOffers.where((o) {
          if (o.unitMetric?.toLowerCase().trim() != targetMetric || o.unitQuantity == null) return false;
          final diff = (o.unitQuantity! - targetQty).abs() / targetQty;
          return diff <= 0.10;
        }).toList()
      : <PharmacyOffer>[];

  final candidateSingleOffers = isBarcodeSearch
      ? (sizeMatchedOffers.isNotEmpty ? sizeMatchedOffers : brandFilteredOffers)
      : allOffers;

  // 1. Lowest Single Unit Cash Price
  PharmacyOffer? lowestSingleOffer;
  for (final offer in candidateSingleOffers) {
    if (lowestSingleOffer == null || offer.singleUnitPrice < lowestSingleOffer.singleUnitPrice) {
      lowestSingleOffer = offer;
    }
  }

  // 2. Best Value per Base Unit (100ml / 100g / 10 tabs)
  PharmacyOffer? bestBaseUnitOffer;
  for (final offer in allOffers) {
    if (offer.pricePerBaseUnit != null && offer.pricePerBaseUnit! > 0) {
      if (bestBaseUnitOffer == null || offer.pricePerBaseUnit! < bestBaseUnitOffer.pricePerBaseUnit!) {
        bestBaseUnitOffer = offer;
      }
    }
  }

  // 3. Lowest Bulk Deal (strictly cheaper than winning Single-Unit Cash Price)
  PromoDeal? lowestBulkDeal;
  PharmacyOffer? lowestBulkOffer;
  final candidateBulkOffers = sizeMatchedOffers.any((o) => o.multiBuyPromos.isNotEmpty)
      ? sizeMatchedOffers
      : allOffers;

  for (final offer in candidateBulkOffers) {
    for (final promo in offer.multiBuyPromos) {
      if (lowestSingleOffer != null && promo.effectiveUnitPrice >= lowestSingleOffer.singleUnitPrice) {
        continue; // Must be strictly cheaper than winning Single-Unit Cash Price
      }
      if (lowestBulkDeal == null || promo.effectiveUnitPrice < lowestBulkDeal.effectiveUnitPrice) {
        lowestBulkDeal = promo;
        lowestBulkOffer = offer;
      }
    }
  }

  if (lowestSingleOffer != null) {
    final sizeDesc = lowestSingleOffer.unitQuantity != null && lowestSingleOffer.unitMetric != null
        ? ' (${lowestSingleOffer.unitQuantity!.toStringAsFixed(0)} ${lowestSingleOffer.unitMetric})'
        : '';
    print('WINNER (Lowest Single Unit Price) : ${lowestSingleOffer.pharmacyName} at ${lowestSingleOffer.singleUnitPrice.toStringAsFixed(2)} SAR$sizeDesc');
  }

  if (bestBaseUnitOffer != null && bestBaseUnitOffer.pricePerBaseUnit != null) {
    final sizeDesc = bestBaseUnitOffer.unitQuantity != null && bestBaseUnitOffer.unitMetric != null
        ? ' (${bestBaseUnitOffer.unitQuantity!.toStringAsFixed(0)} ${bestBaseUnitOffer.unitMetric})'
        : '';
    print('WINNER (Best Value / Base Unit)   : ${bestBaseUnitOffer.pharmacyName} at ${bestBaseUnitOffer.pricePerBaseUnit!.toStringAsFixed(2)} SAR / ${bestBaseUnitOffer.baseUnitDisplayMetric}$sizeDesc');
  }

  if (lowestBulkDeal != null && lowestBulkOffer != null) {
    print('WINNER (Lowest Bulk Unit Price)   : ${lowestBulkOffer.pharmacyName} at ${lowestBulkDeal.effectiveUnitPrice.toStringAsFixed(2)} SAR/ea (${lowestBulkDeal.label})');
  }
  print('========================================================================\n');
}
