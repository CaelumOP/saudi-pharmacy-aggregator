import 'package:flutter/material.dart';
import '../../domain/models/pharmacy_offer.dart';
import '../../domain/models/promo_deal.dart';
import '../../services/pharmacy_aggregator_orchestrator.dart';
import '../../utils/product_match_scorer.dart';

/// Highlights top saving opportunities across pharmacy lanes with dark-mode native contrast.
///
/// Compares Single-Unit Cash Prices (restricted to the same brand and matching package sizes),
/// Best Value per Base Unit (SAR per 100ml/100g/10 tabs), and Effective Multi-Buy Unit Prices.
class BestDealBanner extends StatelessWidget {
  /// Search results across all pharmacy lanes.
  final Map<String, StoreSearchResult> laneResults;

  /// Creates a [BestDealBanner] dynamically calculating winning offers.
  const BestDealBanner({
    super.key,
    required this.laneResults,
  });


  /// Finds the reference offer established by barcode lookup or top completed lane.
  PharmacyOffer? _findReferenceOffer(List<PharmacyOffer> allOffers) {
    // 1. Direct barcode hit takes absolute precedence
    for (final offer in allOffers) {
      if (!offer.isFallbackMatch) {
        return offer;
      }
    }

    // 2. Reference established by top offer of completed lanes
    for (final result in laneResults.values) {
      if (result.status == StoreLaneStatus.completed && result.offers.isNotEmpty) {
        return result.offers.first;
      }
    }

    return allOffers.isNotEmpty ? allOffers.first : null;
  }

  ({double? quantity, String? metric}) _detectReferenceSize(List<PharmacyOffer> allOffers) {
    // 1. Direct barcode hit takes absolute precedence
    for (final offer in allOffers) {
      if (!offer.isFallbackMatch && offer.unitQuantity != null && offer.unitMetric != null) {
        return (quantity: offer.unitQuantity, metric: offer.unitMetric!.toLowerCase().trim());
      }
    }

    // 2. Reference established by majority among top completed offers
    final topOffers = laneResults.values
        .where((r) => r.status == StoreLaneStatus.completed && r.offers.isNotEmpty)
        .map((r) => r.offers.first)
        .where((o) => o.unitQuantity != null && o.unitMetric != null)
        .toList();

    if (topOffers.isNotEmpty) {
      for (final ref in topOffers) {
        final matchingCount = topOffers.where((other) {
          if (other.unitMetric?.toLowerCase().trim() != ref.unitMetric?.toLowerCase().trim()) return false;
          final diff = (other.unitQuantity! - ref.unitQuantity!).abs() / ref.unitQuantity!;
          return diff <= 0.10;
        }).length;

        if (matchingCount >= (topOffers.length / 2).ceil()) {
          return (quantity: ref.unitQuantity, metric: ref.unitMetric!.toLowerCase().trim());
        }
      }
      return (quantity: topOffers.first.unitQuantity, metric: topOffers.first.unitMetric!.toLowerCase().trim());
    }

    return (quantity: null, metric: null);
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    // Collect all in-stock offers across completed lanes
    final allOffers = <PharmacyOffer>[];
    for (final result in laneResults.values) {
      if (result.status == StoreLaneStatus.completed) {
        allOffers.addAll(result.offers.where((o) => o.singleUnitPrice > 0));
      }
    }

    if (allOffers.isEmpty) {
      return const SizedBox.shrink();
    }

    // 1. Brand consistency filter: candidate offers must be same canonical product as reference
    final refOffer = _findReferenceOffer(allOffers);

    List<PharmacyOffer> brandFilteredOffers = allOffers;
    if (refOffer != null) {
      final matches = allOffers.where((o) {
        return ProductMatchScorer.isSameCanonicalProduct(refOffer, o);
      }).toList();
      if (matches.isNotEmpty) {
        brandFilteredOffers = matches;
      }
    }

    // 2. Package size matching filter (within ±10% tolerance)
    final refSize = _detectReferenceSize(brandFilteredOffers);
    final hasRefSize = refSize.quantity != null && refSize.metric != null;

    final sizeMatchedOffers = hasRefSize
        ? brandFilteredOffers.where((o) {
            if (o.unitMetric?.toLowerCase().trim() != refSize.metric || o.unitQuantity == null) return false;
            final diff = (o.unitQuantity! - refSize.quantity!).abs() / refSize.quantity!;
            return diff <= 0.10;
          }).toList()
        : <PharmacyOffer>[];

    final candidateSingleOffers = sizeMatchedOffers.isNotEmpty ? sizeMatchedOffers : brandFilteredOffers;

    // 3. Winning Single-Unit Cash Price
    PharmacyOffer? lowestSingleOffer;
    for (final offer in candidateSingleOffers) {
      if (lowestSingleOffer == null || offer.singleUnitPrice < lowestSingleOffer.singleUnitPrice) {
        lowestSingleOffer = offer;
      }
    }

    // 4. Winning Base Unit Price (SAR per 100ml / 100g / 10 tabs across brand-consistent offers)
    PharmacyOffer? bestValueOffer;
    for (final offer in brandFilteredOffers) {
      if (offer.pricePerBaseUnit != null && offer.pricePerBaseUnit! > 0) {
        if (bestValueOffer == null || offer.pricePerBaseUnit! < bestValueOffer.pricePerBaseUnit!) {
          bestValueOffer = offer;
        }
      }
    }

    // 5. Winning Multi-Buy Bulk Deal (strictly cheaper than winning single-unit cash price)
    PromoDeal? lowestBulkDeal;
    PharmacyOffer? lowestBulkOffer;
    final candidateBulkOffers = sizeMatchedOffers.any((o) => o.multiBuyPromos.isNotEmpty)
        ? sizeMatchedOffers
        : brandFilteredOffers;

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

    final hasBulkAdvantage = lowestBulkDeal != null && lowestBulkOffer != null;

    // Theme-Aware Color Palette
    final cardBg = isDark ? const Color(0xFF1E2926) : Colors.teal.shade50;
    final cardBorder = isDark ? const Color(0xFF2DD4BF).withValues(alpha: 0.3) : Colors.teal.shade300;
    final headerColor = isDark ? const Color(0xFF2DD4BF) : Colors.teal.shade900;
    final primaryTextColor = isDark ? Colors.white : const Color(0xFF111827);
    final secondaryTextColor = isDark ? const Color(0xFF94A3B8) : const Color(0xFF4B5563);
    final innerBoxBg = isDark ? const Color(0xFF13221E) : Colors.white;
    final innerBoxBorder = isDark ? Colors.white12 : Colors.teal.shade100;
    final winningPriceColor = isDark ? const Color(0xFF4ADE80) : Colors.teal.shade900;
    final bulkBoxBg = isDark ? const Color(0xFF2A2016) : Colors.amber.shade50;
    final bulkBoxBorder = isDark ? Colors.amber.shade800.withValues(alpha: 0.4) : Colors.amber.shade200;

    return Card(
      elevation: 2,
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: cardBorder, width: 1.5),
      ),
      color: cardBg,
      child: Padding(
        padding: const EdgeInsets.all(14.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.stars, color: headerColor, size: 22),
                const SizedBox(width: 8),
                Text(
                  'Best Price Comparison Summary',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                    color: headerColor,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),

            // Tier 1 Winner (Lowest Single Unit)
            if (lowestSingleOffer != null)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                decoration: BoxDecoration(
                  color: innerBoxBg,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: innerBoxBorder),
                ),
                child: Row(
                  children: [
                    Icon(Icons.looks_one, color: isDark ? const Color(0xFF2DD4BF) : Colors.teal, size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Lowest Single Unit: ${lowestSingleOffer.pharmacyName}',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 13,
                              color: primaryTextColor,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            lowestSingleOffer.productTitle,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(fontSize: 11, color: secondaryTextColor),
                          ),
                          if (lowestSingleOffer.unitQuantity != null && lowestSingleOffer.unitMetric != null)
                            Text(
                              'Size: ${lowestSingleOffer.unitQuantity!.toStringAsFixed(0)} ${lowestSingleOffer.unitMetric}',
                              style: TextStyle(fontSize: 11, color: secondaryTextColor),
                            ),
                        ],
                      ),
                    ),
                    Text(
                      '${lowestSingleOffer.singleUnitPrice.toStringAsFixed(2)} SAR',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 15,
                        color: winningPriceColor,
                      ),
                    ),
                  ],
                ),
              ),

            // Base Unit Winner (Best Value per 100ml / 100g / 10 tabs)
            if (bestValueOffer != null && bestValueOffer.pricePerBaseUnit != null) ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                decoration: BoxDecoration(
                  color: innerBoxBg,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: innerBoxBorder),
                ),
                child: Row(
                  children: [
                    Icon(Icons.balance, color: isDark ? const Color(0xFF2DD4BF) : Colors.teal.shade700, size: 18),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Best Value: ${bestValueOffer.pharmacyName}',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 13,
                              color: primaryTextColor,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            bestValueOffer.productTitle,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(fontSize: 11, color: secondaryTextColor),
                          ),
                        ],
                      ),
                    ),
                    Text(
                      '${bestValueOffer.pricePerBaseUnit!.toStringAsFixed(2)} SAR / ${bestValueOffer.baseUnitDisplayMetric}',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                        color: isDark ? const Color(0xFF4ADE80) : Colors.green.shade800,
                      ),
                    ),
                  ],
                ),
              ),
            ],

            // Tier 2 Winner (if bulk deal has per-unit price advantage)
            if (hasBulkAdvantage) ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                decoration: BoxDecoration(
                  color: bulkBoxBg,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: bulkBoxBorder),
                ),
                child: Row(
                  children: [
                    Icon(Icons.local_offer, color: isDark ? Colors.amber.shade400 : Colors.amber.shade900, size: 18),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Best Bulk Deal: ${lowestBulkOffer.pharmacyName}',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 13,
                              color: primaryTextColor,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            '${lowestBulkOffer.productTitle} (${lowestBulkDeal.label})',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(fontSize: 11, color: secondaryTextColor),
                          ),
                          Text(
                            'Buy ${lowestBulkDeal.requiredQuantity} for ${lowestBulkDeal.totalCheckoutCost.toStringAsFixed(2)} SAR total',
                            style: TextStyle(fontSize: 11, color: secondaryTextColor),
                          ),
                        ],
                      ),
                    ),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          '${lowestBulkDeal.effectiveUnitPrice.toStringAsFixed(2)} SAR',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                            color: isDark ? const Color(0xFF4ADE80) : Colors.green.shade800,
                          ),
                        ),
                        Text(
                          '/ unit',
                          style: TextStyle(fontSize: 10, color: secondaryTextColor),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
