import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../domain/models/pharmacy_offer.dart';
import '../../domain/models/promo_deal.dart';
import '../../services/pharmacy_aggregator_orchestrator.dart';
import 'waf_challenge_sheet.dart';

/// Card widget rendering a single pharmacy's search lane in a two-tier comparison layout.
///
/// Tier 1 displays instant Single-Unit Cash Price and normalized base pricing (SAR/100ml or SAR/10 tabs).
/// Tier 2 details active Multi-Buy promotional rules, cash outlays, and effective unit prices.
/// Limits multi-offer lanes to the top matching item by default with a clean expand/collapse toggle.
class PharmacyLaneCard extends StatefulWidget {
  /// Result data for this pharmacy lane.
  final StoreSearchResult laneResult;

  /// Optional callback to trigger manual WAF Turnstile verification.
  final VoidCallback? onVerifyChallenge;

  /// Optional callback to pin/unpin an offer in the local watchlist.
  final void Function(PharmacyOffer offer)? onToggleWatchlist;

  /// Whether an offer is currently pinned in the watchlist.
  final bool Function(PharmacyOffer offer)? isPinnedChecker;

  /// Creates a [PharmacyLaneCard].
  const PharmacyLaneCard({
    super.key,
    required this.laneResult,
    this.onVerifyChallenge,
    this.onToggleWatchlist,
    this.isPinnedChecker,
  });

  @override
  State<PharmacyLaneCard> createState() => _PharmacyLaneCardState();
}

class _PharmacyLaneCardState extends State<PharmacyLaneCard> {
  bool _isExpanded = false;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final cardBg = isDark ? const Color(0xFF1E293B) : Colors.white;
    final cardBorder = isDark ? Colors.white12 : Colors.grey.shade200;

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      elevation: 1.5,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: cardBorder),
      ),
      color: cardBg,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Lane Header: Pharmacy Name and Status Badge
            _buildLaneHeader(context, isDark),
            const SizedBox(height: 8),

            // Lane Body: Content depending on Status
            _buildLaneContent(context, isDark),
          ],
        ),
      ),
    );
  }

  Widget _buildLaneHeader(BuildContext context, bool isDark) {
    final storeColor = _getStoreColor(widget.laneResult.storeId);
    final titleColor = isDark ? Colors.white : const Color(0xFF0F172A);

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Row(
          children: [
            CircleAvatar(
              radius: 14,
              backgroundColor: storeColor.withValues(alpha: 0.15),
              child: Text(
                widget.laneResult.storeName.substring(0, 1),
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                  color: storeColor,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Text(
              widget.laneResult.storeName,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: titleColor,
              ),
            ),
          ],
        ),
        _buildStatusBadge(isDark),
      ],
    );
  }

  Widget _buildStatusBadge(bool isDark) {
    switch (widget.laneResult.status) {
      case StoreLaneStatus.idle:
        return const SizedBox.shrink();
      case StoreLaneStatus.loading:
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 12,
              height: 12,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: isDark ? const Color(0xFF2DD4BF) : Colors.teal,
              ),
            ),
            const SizedBox(width: 6),
            Text(
              'Searching...',
              style: TextStyle(fontSize: 11, color: isDark ? const Color(0xFF94A3B8) : Colors.grey.shade600),
            ),
          ],
        );
      case StoreLaneStatus.challengeRequired:
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF451A03) : Colors.orange.shade50,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: isDark ? Colors.orange.shade800 : Colors.orange.shade300),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.shield, size: 12, color: isDark ? Colors.orange.shade300 : Colors.orange.shade800),
              const SizedBox(width: 4),
              Text(
                'WAF Challenge',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  color: isDark ? Colors.orange.shade300 : Colors.orange.shade800,
                ),
              ),
            ],
          ),
        );
      case StoreLaneStatus.completed:
        if (widget.laneResult.offers.isEmpty) {
          return Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF334155) : Colors.grey.shade100,
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              'No Matches',
              style: TextStyle(fontSize: 11, color: isDark ? const Color(0xFFCBD5E1) : Colors.black54),
            ),
          );
        }
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF064E3B) : Colors.green.shade50,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: isDark ? const Color(0xFF059669) : Colors.green.shade200),
          ),
          child: Text(
            '${widget.laneResult.offers.length} found',
            style: TextStyle(
              fontSize: 11,
              color: isDark ? const Color(0xFF6EE7B7) : Colors.green.shade800,
              fontWeight: FontWeight.w600,
            ),
          ),
        );
      case StoreLaneStatus.error:
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF450A0A) : Colors.red.shade50,
            borderRadius: BorderRadius.circular(6),
          ),
          child: Text(
            'Error',
            style: TextStyle(fontSize: 11, color: isDark ? Colors.red.shade300 : Colors.red),
          ),
        );
    }
  }

  Widget _buildLaneContent(BuildContext context, bool isDark) {
    if (widget.laneResult.status == StoreLaneStatus.loading && widget.laneResult.offers.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Center(
          child: SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: isDark ? const Color(0xFF2DD4BF) : Colors.teal,
            ),
          ),
        ),
      );
    }

    if (widget.laneResult.status == StoreLaneStatus.challengeRequired) {
      return Container(
        margin: const EdgeInsets.symmetric(vertical: 6),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF451A03) : Colors.orange.shade50,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: isDark ? Colors.orange.shade800 : Colors.orange.shade200),
        ),
        child: Row(
          children: [
            Icon(Icons.lock_outline, color: isDark ? Colors.orange.shade300 : Colors.orange),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Cloudflare Turnstile verification required to view live prices.',
                style: TextStyle(
                  fontSize: 12,
                  color: isDark ? Colors.orange.shade100 : const Color(0xFF374151),
                ),
              ),
            ),
            FilledButton.tonal(
              onPressed: () {
                if (widget.laneResult.challengeUrl != null) {
                  WafChallengeSheet.show(
                    context,
                    storeName: widget.laneResult.storeName,
                    challengeUrl: widget.laneResult.challengeUrl!,
                  );
                }
                widget.onVerifyChallenge?.call();
              },
              child: const Text('Verify'),
            ),
          ],
        ),
      );
    }

    if (widget.laneResult.status == StoreLaneStatus.completed && widget.laneResult.offers.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Text(
          widget.laneResult.isFallbackSearch
              ? 'No match found even with title fallback.'
              : 'No matches found in this store.',
          style: TextStyle(
            fontSize: 12,
            color: isDark ? const Color(0xFF94A3B8) : Colors.grey.shade600,
            fontStyle: FontStyle.italic,
          ),
        ),
      );
    }

    final offers = widget.laneResult.offers;
    final displayedOffers = _isExpanded ? offers : offers.take(1).toList();

    return Column(
      children: [
        ...displayedOffers.map((offer) => _buildOfferCard(context, offer, isDark)),
        if (offers.length > 1) ...[
          const SizedBox(height: 6),
          InkWell(
            onTap: () => setState(() => _isExpanded = !_isExpanded),
            borderRadius: BorderRadius.circular(8),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    _isExpanded
                        ? 'Show less'
                        : 'Show ${offers.length - 1} more offers from ${widget.laneResult.storeName}',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: isDark ? const Color(0xFF2DD4BF) : Colors.teal.shade800,
                    ),
                  ),
                  Icon(
                    _isExpanded ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down,
                    size: 18,
                    color: isDark ? const Color(0xFF2DD4BF) : Colors.teal.shade800,
                  ),
                ],
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildOfferCard(BuildContext context, PharmacyOffer offer, bool isDark) {
    final isPinned = widget.isPinnedChecker?.call(offer) ?? false;

    final offerCardBg = isDark ? const Color(0xFF0F172A) : Colors.grey.shade50;
    final offerCardBorder = isDark ? Colors.white10 : Colors.grey.shade200;
    final titleColor = isDark ? Colors.white : const Color(0xFF111827);
    final singlePriceColor = isDark ? const Color(0xFF4ADE80) : Colors.green.shade900;
    final baseBadgeBg = isDark ? const Color(0xFF064E3B) : Colors.teal.shade50;
    final baseBadgeBorder = isDark ? const Color(0xFF059669) : Colors.teal.shade200;
    final baseBadgeText = isDark ? const Color(0xFF6EE7B7) : Colors.teal.shade900;
    final promoTrayBg = isDark ? const Color(0xFF2E1C0A) : Colors.amber.shade50.withValues(alpha: 0.5);
    final promoTrayBorder = isDark ? Colors.amber.shade800.withValues(alpha: 0.5) : Colors.amber.shade200;
    final promoHeaderText = isDark ? Colors.amber.shade300 : Colors.amber.shade900;

    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: offerCardBg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: offerCardBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Meta Badges (Fallback Match / SFDA / Stock)
          Wrap(
            spacing: 6,
            runSpacing: 4,
            children: [
              if (offer.isFallbackMatch)
                _buildChip(
                  'Matched via Title Fallback',
                  isDark ? Colors.amber.shade300 : Colors.amber.shade800,
                  isDark ? const Color(0xFF451A03) : Colors.amber.shade50,
                ),
              if (offer.isSfdaRegulated)
                _buildChip(
                  '0% VAT (SFDA Drug)',
                  isDark ? Colors.blue.shade300 : Colors.blue.shade800,
                  isDark ? const Color(0xFF1E3A8A) : Colors.blue.shade50,
                )
              else
                _buildChip(
                  '15% VAT Included',
                  isDark ? const Color(0xFFCBD5E1) : Colors.grey.shade700,
                  isDark ? const Color(0xFF334155) : Colors.grey.shade100,
                ),
              if (!offer.isOnlineInStock)
                _buildChip(
                  'Out of Stock',
                  isDark ? Colors.red.shade300 : Colors.red.shade800,
                  isDark ? const Color(0xFF450A0A) : Colors.red.shade50,
                ),
            ],
          ),
          const SizedBox(height: 6),

          // TIER 1: Core Single-Unit Price & Title
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Product Photo Thumbnail
              if (offer.imageUrl != null)
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Image.network(
                    offer.imageUrl!,
                    width: 50,
                    height: 50,
                    fit: BoxFit.contain,
                    errorBuilder: (context, error, stackTrace) =>
                        const Icon(Icons.medication, size: 40, color: Colors.grey),
                  ),
                )
              else
                Container(
                  width: 50,
                  height: 50,
                  decoration: BoxDecoration(
                    color: isDark ? const Color(0xFF1E293B) : Colors.grey.shade200,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(Icons.medication, color: Colors.grey),
                ),
              const SizedBox(width: 10),

              // Title and Price Block
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      offer.productTitle,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                        color: titleColor,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Text(
                          '${offer.singleUnitPrice.toStringAsFixed(2)} SAR',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w900,
                            color: singlePriceColor,
                          ),
                        ),
                        if (offer.pricePerBaseUnit != null && offer.unitMetric != null) ...[
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: baseBadgeBg,
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(color: baseBadgeBorder),
                            ),
                            child: Text(
                              '${offer.pricePerBaseUnit!.toStringAsFixed(2)} SAR / ${_formatMetric(offer.unitMetric!)}',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: baseBadgeText,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),

              // Pin Star Action
              IconButton(
                icon: Icon(
                  isPinned ? Icons.star : Icons.star_border,
                  color: isPinned ? Colors.amber : (isDark ? Colors.white38 : Colors.grey),
                ),
                onPressed: () => widget.onToggleWatchlist?.call(offer),
              ),
            ],
          ),

          // TIER 2: Active Multi-Buy Promotions Tray
          if (offer.multiBuyPromos.isNotEmpty) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: promoTrayBg,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: promoTrayBorder),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.local_offer_outlined, size: 14, color: promoHeaderText),
                      const SizedBox(width: 4),
                      Text(
                        'Active Multi-Buy Promotions:',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: promoHeaderText,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  ...offer.multiBuyPromos.map((deal) => _buildPromoRow(deal, isDark)),
                ],
              ),
            ),
          ],

          // Footer Action: Open in Store
          if (offer.productUrl != null) ...[
            const SizedBox(height: 6),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                style: TextButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  foregroundColor: isDark ? const Color(0xFF2DD4BF) : Colors.teal.shade800,
                ),
                icon: const Icon(Icons.open_in_new, size: 14),
                label: const Text('Open in Store', style: TextStyle(fontSize: 12)),
                onPressed: () => _openStoreUrl(offer.productUrl!),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildChip(String label, Color textColor, Color bgColor) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        label,
        style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: textColor),
      ),
    );
  }

  Widget _buildPromoRow(PromoDeal deal, bool isDark) {
    final dealTextColor = isDark ? Colors.white : const Color(0xFF111827);
    final mathTextColor = isDark ? const Color(0xFF94A3B8) : const Color(0xFF374151);
    final effPriceColor = isDark ? const Color(0xFF4ADE80) : Colors.green.shade800;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  deal.label,
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: dealTextColor),
                ),
                Text(
                  'Buy ${deal.requiredQuantity} for ${deal.totalCheckoutCost.toStringAsFixed(2)} SAR',
                  style: TextStyle(fontSize: 10, color: mathTextColor),
                ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '${deal.effectiveUnitPrice.toStringAsFixed(2)} SAR',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: effPriceColor,
                ),
              ),
              Text(
                '/ unit',
                style: TextStyle(fontSize: 9, color: mathTextColor),
              ),
            ],
          ),
        ],
      ),
    );
  }

  String _formatMetric(String metric) {
    final lower = metric.toLowerCase().trim();
    if (lower == 'ml') return '100ml';
    if (lower == 'g' || lower == 'gm') return '100g';
    if (lower == 'tablet' || lower == 'tablets' || lower == 'caplet' || lower == 'piece') return '10 tabs';
    return '100 units';
  }

  Color _getStoreColor(String storeId) {
    switch (storeId) {
      case 'al_nahdi':
        return const Color(0xFF007A3D); // Nahdi Green
      case 'united_pharmacy':
        return const Color(0xFF005BAC); // United Blue
      case 'whites':
        return const Color(0xFF8B1E41); // Whites Burgundy
      case 'al_dawaa':
        return const Color(0xFFE2001A); // Dawaa Red
      default:
        return Colors.teal;
    }
  }

  void _openStoreUrl(String url) async {
    final uri = Uri.tryParse(url);
    if (uri != null) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }
}
