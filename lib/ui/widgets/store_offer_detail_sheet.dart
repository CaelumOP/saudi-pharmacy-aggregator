import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../domain/models/pharmacy_offer.dart';
import '../../domain/models/promo_deal.dart';
import '../../l10n/app_strings.dart';
import '../../services/app_settings_repository.dart';
import '../../services/pharmacy_aggregator_orchestrator.dart';

/// Modal bottom sheet presenting in-depth pricing, tax classification, match confidence,
/// Tier 2 promo mechanics, and size variants for a store's product offer.
class StoreOfferDetailSheet extends StatelessWidget {
  /// Result data for the reporting store lane.
  final StoreSearchResult laneResult;

  /// The active offer selected by the user.
  final PharmacyOffer offer;

  /// Optional localization strings dictionary.
  final AppStrings? strings;

  /// Optional callback when switching to a different variant from the same store.
  final void Function(PharmacyOffer variant)? onSelectVariant;

  /// Creates a [StoreOfferDetailSheet].
  const StoreOfferDetailSheet({
    super.key,
    required this.laneResult,
    required this.offer,
    this.strings,
    this.onSelectVariant,
  });

  /// Displays the modal sheet.
  static Future<void> show(
    BuildContext context, {
    required StoreSearchResult laneResult,
    required PharmacyOffer offer,
    AppStrings? strings,
    void Function(PharmacyOffer variant)? onSelectVariant,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StoreOfferDetailSheet(
        laneResult: laneResult,
        offer: offer,
        strings: strings,
        onSelectVariant: onSelectVariant,
      ),
    );
  }

  void _launchStoreUrl(String url) async {
    final uri = Uri.tryParse(url);
    if (uri != null) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = strings ?? AppStrings(AppSettingsRepository.instance.state.language);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final maxSheetHeight = MediaQuery.of(context).size.height * 0.85;

    final sheetBg = isDark ? const Color(0xFF0F172A) : Colors.white;
    final titleColor = isDark ? Colors.white : const Color(0xFF0F172A);
    final subtitleColor = isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B);
    final sectionBg = isDark ? const Color(0xFF1E293B) : const Color(0xFFF8FAFC);
    final sectionBorder = isDark ? Colors.white12 : const Color(0xFFE2E8F0);

    final localizedStoreName = l10n.storeName(laneResult.storeId, defaultName: laneResult.storeName);

    final matchTypeLabel = !offer.isFallbackMatch
        ? l10n.exactBarcodeMatch
        : l10n.smartTitleMatch(offer.matchScore);

    final variants = laneResult.offers.where((o) => o.skuOrId != offer.skuOrId).toList();

    return Container(
      constraints: BoxConstraints(maxHeight: maxSheetHeight),
      decoration: BoxDecoration(
        color: sheetBg,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Drag handle
          Center(
            child: Container(
              margin: const EdgeInsets.only(top: 10, bottom: 6),
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: isDark ? Colors.white24 : Colors.grey.shade300,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),

          // Header: Store Name & Close Button
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    const Icon(Icons.storefront, size: 20, color: Color(0xFF10B981)),
                    const SizedBox(width: 8),
                    Text(
                      localizedStoreName,
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: titleColor,
                      ),
                    ),
                  ],
                ),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
          ),
          const Divider(height: 1),

          // Scrollable Offer Content
          Flexible(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              physics: const BouncingScrollPhysics(),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Photo & Title Row
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: 80,
                        height: 80,
                        decoration: BoxDecoration(
                          color: isDark ? const Color(0xFF1E293B) : Colors.grey.shade100,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: sectionBorder),
                        ),
                        child: offer.imageUrl != null
                            ? ClipRRect(
                                borderRadius: BorderRadius.circular(12),
                                child: Image.network(
                                  offer.imageUrl!,
                                  fit: BoxFit.contain,
                                  errorBuilder: (_, _, _) =>
                                      Icon(Icons.medication, size: 40, color: subtitleColor),
                                ),
                              )
                            : Icon(Icons.medication, size: 40, color: subtitleColor),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              offer.productTitle,
                              style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.bold,
                                color: titleColor,
                                height: 1.25,
                              ),
                            ),
                            const SizedBox(height: 6),
                            if (offer.skuOrId.isNotEmpty)
                              Text(
                                '${l10n.skuLabel}: ${offer.skuOrId}',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: subtitleColor,
                                  fontFamily: 'monospace',
                                ),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),

                  // Pricing & Base Unit Box
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: sectionBg,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: sectionBorder),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              l10n.singleUnitPriceLabel,
                              style: TextStyle(fontSize: 11, color: subtitleColor),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              '${offer.singleUnitPrice.toStringAsFixed(2)} ${l10n.currency}',
                              style: const TextStyle(
                                fontSize: 22,
                                fontWeight: FontWeight.w900,
                                color: Color(0xFF10B981),
                              ),
                            ),
                          ],
                        ),
                        if (offer.pricePerBaseUnit != null && offer.unitMetric != null)
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Text(
                                l10n.baseUnitPriceLabel,
                                style: TextStyle(fontSize: 11, color: subtitleColor),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                '${offer.pricePerBaseUnit!.toStringAsFixed(2)} ${l10n.currency}',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                  color: isDark ? const Color(0xFF38BDF8) : const Color(0xFF0284C7),
                                ),
                              ),
                              Text(
                                '${l10n.isArabic ? "لكل" : "per"} ${offer.baseUnitDisplayMetric}',
                                style: TextStyle(fontSize: 10, color: subtitleColor),
                              ),
                            ],
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),

                  // Compliance & Matching Badges
                  Wrap(
                    spacing: 8,
                    runSpacing: 6,
                    children: [
                      _buildDetailChip(
                        icon: Icons.verified_outlined,
                        label: matchTypeLabel,
                        isDark: isDark,
                        tint: !offer.isFallbackMatch ? const Color(0xFF10B981) : const Color(0xFFF59E0B),
                      ),
                      _buildDetailChip(
                        icon: Icons.receipt_long,
                        label: offer.isSfdaRegulated ? l10n.vat0SfdaRegulated : l10n.vat15Inclusive,
                        isDark: isDark,
                        tint: offer.isSfdaRegulated ? const Color(0xFF3B82F6) : const Color(0xFF64748B),
                      ),
                      _buildDetailChip(
                        icon: offer.isOnlineInStock ? Icons.check_circle_outline : Icons.cancel_outlined,
                        label: offer.isOnlineInStock ? l10n.inStock : l10n.outOfStock,
                        isDark: isDark,
                        tint: offer.isOnlineInStock ? const Color(0xFF10B981) : const Color(0xFFEF4444),
                      ),
                      if (offer.unitQuantity != null && offer.unitMetric != null)
                        _buildDetailChip(
                          icon: Icons.scale,
                          label: '${offer.unitQuantity!.toStringAsFixed(0)} ${offer.unitMetric}',
                          isDark: isDark,
                          tint: const Color(0xFF8B5CF6),
                        ),
                    ],
                  ),

                  // Tier 2 Promotions Breakdown Table
                  if (offer.multiBuyPromos.isNotEmpty) ...[
                    const SizedBox(height: 20),
                    Text(
                      l10n.activePromosLabel,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: titleColor,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Container(
                      decoration: BoxDecoration(
                        color: sectionBg,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: sectionBorder),
                      ),
                      child: Column(
                        children: offer.multiBuyPromos.asMap().entries.map((entry) {
                          final idx = entry.key;
                          final promo = entry.value;
                          return Column(
                            children: [
                              if (idx > 0) Divider(height: 1, color: sectionBorder),
                              _buildPromoDetailRow(promo, isDark),
                            ],
                          );
                        }).toList(),
                      ),
                    ),
                  ],

                  // Other Sizes / Variants in Same Store
                  if (variants.isNotEmpty) ...[
                    const SizedBox(height: 20),
                    Text(
                      l10n.isArabic ? 'خيارات أخرى من $localizedStoreName' : 'Other Options from $localizedStoreName',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: titleColor,
                      ),
                    ),
                    const SizedBox(height: 8),
                    ...variants.map((v) => Container(
                          margin: const EdgeInsets.only(bottom: 6),
                          decoration: BoxDecoration(
                            color: sectionBg,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: sectionBorder),
                          ),
                          child: ListTile(
                            dense: true,
                            title: Text(
                              v.productTitle,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: titleColor),
                            ),
                            subtitle: Text(
                              '${v.singleUnitPrice.toStringAsFixed(2)} ${l10n.currency}'
                              '${v.unitQuantity != null && v.unitMetric != null ? " • ${v.unitQuantity!.toStringAsFixed(0)} ${v.unitMetric}" : ""}',
                              style: const TextStyle(fontSize: 11, color: Color(0xFF10B981)),
                            ),
                            trailing: TextButton(
                              child: Text(l10n.isArabic ? 'عرض' : 'View', style: const TextStyle(fontSize: 12)),
                              onPressed: () {
                                Navigator.of(context).pop();
                                onSelectVariant?.call(v);
                              },
                            ),
                          ),
                        )),
                  ],
                ],
              ),
            ),
          ),

          // Bottom Bar: Prominent "Open in Store" Button
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
            decoration: BoxDecoration(
              color: sheetBg,
              border: Border(top: BorderSide(color: sectionBorder)),
            ),
            child: SizedBox(
              width: double.infinity,
              height: 48,
              child: FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF10B981),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                icon: const Icon(Icons.open_in_new, size: 18),
                label: Text(
                  l10n.isArabic ? 'فتح في $localizedStoreName' : 'Open in $localizedStoreName',
                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                ),
                onPressed: offer.productUrl != null ? () => _launchStoreUrl(offer.productUrl!) : null,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDetailChip({
    required IconData icon,
    required String label,
    required bool isDark,
    required Color tint,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: tint.withValues(alpha: isDark ? 0.15 : 0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: tint.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: tint),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: isDark ? Colors.white : const Color(0xFF1E293B),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPromoDetailRow(PromoDeal promo, bool isDark) {
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                promo.label,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                  color: isDark ? Colors.white : const Color(0xFF0F172A),
                ),
              ),
              const SizedBox(height: 2),
              Text(
                'Buy ${promo.requiredQuantity} items for ${promo.totalCheckoutCost.toStringAsFixed(2)} SAR total',
                style: TextStyle(
                  fontSize: 11,
                  color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
                ),
              ),
            ],
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '${promo.effectiveUnitPrice.toStringAsFixed(2)} SAR',
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w900,
                  color: Color(0xFF10B981),
                ),
              ),
              Text(
                'effective / unit',
                style: TextStyle(
                  fontSize: 10,
                  color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
