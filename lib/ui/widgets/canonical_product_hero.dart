import 'package:flutter/material.dart';
import '../../domain/models/pharmacy_offer.dart';
import '../../domain/models/promo_deal.dart';
import '../../l10n/app_strings.dart';
import '../../services/app_settings_repository.dart';
import '../../services/pharmacy_aggregator_orchestrator.dart';
import '../../utils/product_match_scorer.dart';

/// Canonical Product Hero Card displayed at the top of search comparisons.
///
/// Highlights product identity (photo, canonical title, size, barcode) and surfaces
/// three compact high-contrast winner badges: Lowest Single Price, Best Unit Value,
/// and Best Bulk / Promo Deal.
class CanonicalProductHero extends StatelessWidget {
  /// Map of all store lane results.
  final Map<String, StoreSearchResult> laneResults;

  /// Active search query (free-text or GTIN barcode).
  final String activeQuery;

  /// Whether this canonical product is pinned in the watchlist.
  final bool isPinned;

  /// Optional localization strings dictionary.
  final AppStrings? strings;

  /// Callback when user taps the pin/unpin star.
  final VoidCallback onTogglePin;

  /// Creates a [CanonicalProductHero].
  const CanonicalProductHero({
    super.key,
    required this.laneResults,
    required this.activeQuery,
    required this.isPinned,
    this.strings,
    required this.onTogglePin,
  });

  PharmacyOffer? _findReferenceOffer(List<PharmacyOffer> allOffers) {
    for (final offer in allOffers) {
      if (!offer.isFallbackMatch) {
        return offer;
      }
    }
    for (final result in laneResults.values) {
      if (result.status == StoreLaneStatus.completed && result.offers.isNotEmpty) {
        return result.offers.first;
      }
    }
    return allOffers.isNotEmpty ? allOffers.first : null;
  }

  ({double? quantity, String? metric}) _detectReferenceSize(List<PharmacyOffer> allOffers) {
    for (final offer in allOffers) {
      if (!offer.isFallbackMatch && offer.unitQuantity != null && offer.unitMetric != null) {
        return (quantity: offer.unitQuantity, metric: offer.unitMetric!.toLowerCase().trim());
      }
    }
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
    final l10n = strings ?? AppStrings(AppSettingsRepository.instance.state.language);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final allOffers = <PharmacyOffer>[];
    for (final result in laneResults.values) {
      if (result.status == StoreLaneStatus.completed) {
        allOffers.addAll(result.offers.where((o) => o.singleUnitPrice > 0));
      }
    }

    if (allOffers.isEmpty) {
      return const SizedBox.shrink();
    }

    final refOffer = _findReferenceOffer(allOffers);
    if (refOffer == null) return const SizedBox.shrink();

    // Candidate offers that are brand & form consistent with reference
    List<PharmacyOffer> brandFilteredOffers = allOffers;
    final matches = allOffers.where((o) => ProductMatchScorer.isSameCanonicalProduct(refOffer, o)).toList();
    if (matches.isNotEmpty) {
      brandFilteredOffers = matches;
    }

    final refSize = _detectReferenceSize(brandFilteredOffers);
    final hasRefSize = refSize.quantity != null && refSize.metric != null;

    final sizeMatchedOffers = hasRefSize
        ? brandFilteredOffers.where((o) {
            if (o.unitMetric?.toLowerCase().trim() != refSize.metric || o.unitQuantity == null) return false;
            final diff = (o.unitQuantity! - refSize.quantity!).abs() / refSize.quantity!;
            return diff <= 0.10;
          }).toList()
        : <PharmacyOffer>[];

    final isBarcodeSearch = RegExp(r'^\d{8,14}$').hasMatch(activeQuery.trim());
    final isSpecificProduct = isBarcodeSearch ||
        (refOffer.matchScore >= 0.85 && brandFilteredOffers.length >= 2);

    final candidateSingleOffers = isSpecificProduct && sizeMatchedOffers.isNotEmpty
        ? sizeMatchedOffers
        : (isSpecificProduct ? brandFilteredOffers : allOffers);

    // Pick winning lowest single price
    PharmacyOffer? lowestSingleOffer;
    for (final offer in candidateSingleOffers) {
      if (lowestSingleOffer == null || offer.singleUnitPrice < lowestSingleOffer.singleUnitPrice) {
        lowestSingleOffer = offer;
      }
    }

    // Pick best unit value
    final candidateValueOffers = isSpecificProduct ? brandFilteredOffers : allOffers;
    PharmacyOffer? bestValueOffer;
    for (final offer in candidateValueOffers) {
      if (offer.pricePerBaseUnit != null && offer.pricePerBaseUnit! > 0) {
        if (bestValueOffer == null || offer.pricePerBaseUnit! < bestValueOffer.pricePerBaseUnit!) {
          bestValueOffer = offer;
        }
      }
    }

    // Pick best bulk / promo deal strictly cheaper than lowest single price
    PromoDeal? lowestBulkDeal;
    PharmacyOffer? lowestBulkOffer;
    final candidateBulkOffers =
        sizeMatchedOffers.any((o) => o.multiBuyPromos.isNotEmpty) ? sizeMatchedOffers : brandFilteredOffers;

    for (final offer in candidateBulkOffers) {
      for (final promo in offer.multiBuyPromos) {
        if (lowestSingleOffer != null && promo.effectiveUnitPrice >= lowestSingleOffer.singleUnitPrice) {
          continue;
        }
        if (lowestBulkDeal == null || promo.effectiveUnitPrice < lowestBulkDeal.effectiveUnitPrice) {
          lowestBulkDeal = promo;
          lowestBulkOffer = offer;
        }
      }
    }

    // Product photo from highest scoring offer with image
    final candidateWithImage = brandFilteredOffers.where((o) => o.imageUrl != null && o.imageUrl!.isNotEmpty).toList()
      ..sort((a, b) => b.matchScore.compareTo(a.matchScore));
    final displayImageUrl = candidateWithImage.firstOrNull?.imageUrl;

    final isBarcode = isBarcodeSearch;

    // Theme Palette
    final cardBg = isDark ? const Color(0xFF131D2A) : Colors.white;
    final cardBorder = isDark ? const Color(0xFF1E293B) : Colors.grey.shade200;
    final titleColor = isDark ? Colors.white : const Color(0xFF0F172A);
    final subtitleColor = isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B);

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: cardBorder, width: 1.2),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.3 : 0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Top Row: Thumbnail, Identity & Pin Action
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Thumbnail
                Container(
                  width: 64,
                  height: 64,
                  decoration: BoxDecoration(
                    color: isDark ? const Color(0xFF1E293B) : Colors.grey.shade100,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: isDark ? Colors.white12 : Colors.grey.shade300),
                  ),
                  child: displayImageUrl != null
                      ? ClipRRect(
                          borderRadius: BorderRadius.circular(12),
                          child: Image.network(
                            displayImageUrl,
                            fit: BoxFit.contain,
                            errorBuilder: (ctx, err, stack) =>
                                Icon(Icons.medication, color: isDark ? Colors.white38 : Colors.grey),
                          ),
                        )
                      : Icon(Icons.medication, color: isDark ? Colors.white38 : Colors.grey),
                ),
                const SizedBox(width: 12),

                // Canonical Title & Meta Chips
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        refOffer.productTitle,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: titleColor,
                          height: 1.2,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 6,
                        runSpacing: 4,
                        children: [
                          if (hasRefSize)
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: isDark ? const Color(0xFF0F291E) : const Color(0xFFE8F5E9),
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(color: isDark ? const Color(0xFF1B5E20) : const Color(0xFFA5D6A7)),
                              ),
                              child: Text(
                                '${refSize.quantity!.toStringAsFixed(0)} ${refSize.metric}',
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                  color: isDark ? const Color(0xFF81C784) : const Color(0xFF2E7D32),
                                ),
                              ),
                            ),
                          if (isBarcode)
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: isDark ? const Color(0xFF1E293B) : Colors.grey.shade200,
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.qr_code, size: 10, color: subtitleColor),
                                  const SizedBox(width: 3),
                                  Text(
                                    activeQuery.trim(),
                                    style: TextStyle(fontSize: 10, color: subtitleColor, fontFamily: 'monospace'),
                                  ),
                                ],
                              ),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),

                // Watchlist Pin Star
                IconButton(
                  icon: Icon(
                    isPinned ? Icons.star : Icons.star_border,
                    color: isPinned ? Colors.amber : (isDark ? Colors.white38 : Colors.grey),
                    size: 24,
                  ),
                  tooltip: isPinned ? l10n.pinnedToWatchlist : l10n.addToWatchlist,
                  onPressed: onTogglePin,
                ),
              ],
            ),
            const SizedBox(height: 12),

            // 3 Compact Winner Badges (Horizontal scroll or responsive wrap)
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              physics: const BouncingScrollPhysics(),
              child: Row(
                children: [
                  if (lowestSingleOffer != null)
                    _buildWinnerBadge(
                      context,
                      isDark: isDark,
                      icon: Icons.attach_money,
                      category: l10n.lowestSinglePriceWinner,
                      store: l10n.storeName(lowestSingleOffer.storeId, defaultName: lowestSingleOffer.pharmacyName),
                      value: '${lowestSingleOffer.singleUnitPrice.toStringAsFixed(2)} ${l10n.currency}',
                      badgeColor: const Color(0xFF10B981), // Emerald
                    ),
                  if (bestValueOffer != null && bestValueOffer.pricePerBaseUnit != null) ...[
                    const SizedBox(width: 8),
                    _buildWinnerBadge(
                      context,
                      isDark: isDark,
                      icon: Icons.balance,
                      category: l10n.bestUnitValueWinner,
                      store: l10n.storeName(bestValueOffer.storeId, defaultName: bestValueOffer.pharmacyName),
                      value:
                          '${bestValueOffer.pricePerBaseUnit!.toStringAsFixed(2)} ${l10n.currency}${l10n.pricePerBaseUnit(bestValueOffer.baseUnitDisplayMetric)}',
                      badgeColor: const Color(0xFF0EA5E9), // Sky Blue
                    ),
                  ],
                  if (lowestBulkDeal != null && lowestBulkOffer != null) ...[
                    const SizedBox(width: 8),
                    _buildWinnerBadge(
                      context,
                      isDark: isDark,
                      icon: Icons.local_offer,
                      category: l10n.bestBulkDealWinner,
                      store: l10n.storeName(lowestBulkOffer.storeId, defaultName: lowestBulkOffer.pharmacyName),
                      value: '${lowestBulkDeal.effectiveUnitPrice.toStringAsFixed(2)} ${l10n.currency}${l10n.isArabic ? '/قطعة' : '/ea'}',
                      badgeColor: const Color(0xFFF59E0B), // Amber
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildWinnerBadge(
    BuildContext context, {
    required bool isDark,
    required IconData icon,
    required String category,
    required String store,
    required String value,
    required Color badgeColor,
  }) {
    final bg = isDark ? badgeColor.withValues(alpha: 0.15) : badgeColor.withValues(alpha: 0.08);
    final border = isDark ? badgeColor.withValues(alpha: 0.4) : badgeColor.withValues(alpha: 0.3);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          CircleAvatar(
            radius: 10,
            backgroundColor: badgeColor,
            child: Icon(icon, size: 12, color: Colors.white),
          ),
          const SizedBox(width: 6),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                category.toUpperCase(),
                style: TextStyle(
                  fontSize: 9,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.4,
                  color: isDark ? Colors.white70 : const Color(0xFF475569),
                ),
              ),
              Row(
                children: [
                  Text(
                    '$store • ',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w500,
                      color: isDark ? Colors.white : const Color(0xFF0F172A),
                    ),
                  ),
                  Text(
                    value,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      color: badgeColor,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }
}
