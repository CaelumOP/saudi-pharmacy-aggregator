import 'package:flutter/material.dart';
import '../../adapters/pharmacy_adapter.dart';
import '../../domain/models/pharmacy_offer.dart';
import '../../l10n/app_strings.dart';
import '../../services/app_settings_repository.dart';
import '../../services/pharmacy_aggregator_orchestrator.dart';

/// High-density Price Ladder Row rendering a single store's matching offer.
///
/// Displays rank, store branding, presence type, truncated title, size, stock,
/// active promo badge, bold SAR price, base unit rate, and quick link to external store.
class PriceLadderRow extends StatelessWidget {
  /// Rank position in current sort view (1-based, e.g. 1 for cheapest).
  final int rank;

  /// Store metadata and search result status.
  final StoreSearchResult laneResult;

  /// The specific pharmacy offer being compared.
  final PharmacyOffer offer;

  /// Optional localization strings dictionary.
  final AppStrings? strings;

  /// Tap callback to inspect full offer details in a bottom sheet.
  final VoidCallback onTap;

  /// Tap callback to launch the storefront URL in an external browser.
  final VoidCallback? onOpenStore;

  /// Creates a [PriceLadderRow].
  const PriceLadderRow({
    super.key,
    required this.rank,
    required this.laneResult,
    required this.offer,
    this.strings,
    required this.onTap,
    this.onOpenStore,
  });

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
      case 'boots':
        return const Color(0xFF003865); // Boots Navy
      case 'nice_one':
        return const Color(0xFFD81B60); // Nice One Pink
      case 'iherb':
        return const Color(0xFF2E7D32); // iHerb Olive Green
      case 'kstyleseoul':
        return const Color(0xFF7C3AED); // K-Style Violet
      case 'seoul_eun':
        return const Color(0xFF0D9488); // Seoul Eun Teal
      default:
        return const Color(0xFF0F766E);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = strings ?? AppStrings(AppSettingsRepository.instance.state.language);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isWinner = rank == 1;

    final rowBg = isDark
        ? (isWinner ? const Color(0xFF132A20) : const Color(0xFF1E293B))
        : (isWinner ? const Color(0xFFF0FDF4) : Colors.white);

    final rowBorder = isDark
        ? (isWinner ? const Color(0xFF059669) : Colors.white12)
        : (isWinner ? const Color(0xFF86EFAC) : Colors.grey.shade200);

    final rankBg = isWinner
        ? const Color(0xFF10B981) // Emerald
        : (isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0));

    final rankTextColor = isWinner ? Colors.white : (isDark ? const Color(0xFFCBD5E1) : const Color(0xFF475569));

    final storeColor = _getStoreColor(offer.storeId);
    final titleColor = isDark ? Colors.white : const Color(0xFF0F172A);
    final subtitleColor = isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B);
    final priceColor = isWinner
        ? (isDark ? const Color(0xFF4ADE80) : const Color(0xFF047857))
        : (isDark ? Colors.white : const Color(0xFF0F172A));

    final isWalkIn = laneResult.presenceType == StorePresenceType.physicalAndOnline;
    final localizedStoreName = l10n.storeName(offer.storeId, defaultName: offer.pharmacyName);

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      decoration: BoxDecoration(
        color: rowBg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: rowBorder, width: isWinner ? 1.5 : 1.0),
        boxShadow: [
          if (isWinner)
            BoxShadow(
              color: const Color(0xFF10B981).withValues(alpha: isDark ? 0.2 : 0.1),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            child: Row(
              children: [
                // 1. Rank Badge
                Container(
                  width: 28,
                  height: 28,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: rankBg,
                    shape: BoxShape.circle,
                  ),
                  child: Text(
                    '#$rank',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      color: rankTextColor,
                    ),
                  ),
                ),
                const SizedBox(width: 8),

                // 2. Store Avatar
                CircleAvatar(
                  radius: 14,
                  backgroundColor: storeColor.withValues(alpha: 0.15),
                  child: Text(
                    localizedStoreName.isNotEmpty ? localizedStoreName.substring(0, 1) : 'S',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: storeColor,
                    ),
                  ),
                ),
                const SizedBox(width: 10),

                // 3. Center Info (Store Name, Presence, Title, Size, Stock, Promos)
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Store Name + Presence Chip + Stock Dot
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              localizedStoreName,
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.bold,
                                color: titleColor,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                            decoration: BoxDecoration(
                              color: isWalkIn
                                  ? (isDark ? const Color(0xFF1E3A8A) : const Color(0xFFEFF6FF))
                                  : (isDark ? const Color(0xFF3B0764) : const Color(0xFFFAF5FF)),
                              borderRadius: BorderRadius.circular(4),
                              border: Border.all(
                                color: isWalkIn
                                    ? (isDark ? const Color(0xFF2563EB) : const Color(0xFFBFDBFE))
                                    : (isDark ? const Color(0xFF7E22CE) : const Color(0xFFE9D5FF)),
                              ),
                            ),
                            child: Text(
                              isWalkIn ? l10n.walkInPresence : l10n.onlinePresence,
                              style: TextStyle(
                                fontSize: 9,
                                fontWeight: FontWeight.w600,
                                color: isWalkIn
                                    ? (isDark ? const Color(0xFF93C5FD) : const Color(0xFF1D4ED8))
                                    : (isDark ? const Color(0xFFD8B4FE) : const Color(0xFF7E22CE)),
                              ),
                            ),
                          ),
                          const SizedBox(width: 6),
                          // Stock Indicator Dot
                          Container(
                            width: 6,
                            height: 6,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: offer.isOnlineInStock ? const Color(0xFF10B981) : Colors.red,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 2),

                      // Truncated Product Title
                      Text(
                        offer.productTitle,
                        style: TextStyle(
                          fontSize: 11,
                          color: subtitleColor,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),

                      // Size Badge & Promo Pill
                      Row(
                        children: [
                          if (offer.unitQuantity != null && offer.unitMetric != null) ...[
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                              decoration: BoxDecoration(
                                color: isDark ? const Color(0xFF334155) : Colors.grey.shade200,
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                '${offer.unitQuantity!.toStringAsFixed(0)} ${offer.unitMetric}',
                                style: TextStyle(
                                  fontSize: 9,
                                  fontWeight: FontWeight.w500,
                                  color: isDark ? const Color(0xFFCBD5E1) : const Color(0xFF334155),
                                ),
                              ),
                            ),
                            const SizedBox(width: 4),
                          ],
                          if (offer.multiBuyPromos.isNotEmpty)
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                              decoration: BoxDecoration(
                                color: isDark ? const Color(0xFF451A03) : const Color(0xFFFEF3C7),
                                borderRadius: BorderRadius.circular(4),
                                border: Border.all(
                                  color: isDark ? const Color(0xFFD97706) : const Color(0xFFFDE68A),
                                ),
                              ),
                              child: Text(
                                offer.multiBuyPromos.first.label,
                                style: TextStyle(
                                  fontSize: 9,
                                  fontWeight: FontWeight.bold,
                                  color: isDark ? const Color(0xFFFBBF24) : const Color(0xFFB45309),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),

                // 4. Right Side: Price, Base Rate, and External Link
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '${offer.singleUnitPrice.toStringAsFixed(2)} ${l10n.currency}',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w900,
                        color: priceColor,
                      ),
                    ),
                    if (offer.pricePerBaseUnit != null && offer.pricePerBaseUnit! > 0)
                      Text(
                        '${offer.pricePerBaseUnit!.toStringAsFixed(2)}${l10n.pricePerBaseUnit(offer.baseUnitDisplayMetric)}',
                        style: TextStyle(
                          fontSize: 9,
                          fontWeight: FontWeight.w600,
                          color: isDark ? const Color(0xFF38BDF8) : const Color(0xFF0284C7),
                        ),
                      ),
                  ],
                ),
                if (offer.productUrl != null) ...[
                  const SizedBox(width: 4),
                  IconButton(
                    icon: Icon(
                      Icons.open_in_new,
                      size: 16,
                      color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
                    ),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                    tooltip: 'Open in Store',
                    onPressed: onOpenStore,
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
