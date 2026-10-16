import 'promo_deal.dart';

/// Normalized domain representation of a pharmacy product listing and pricing.
///
/// Unifies divergent API response formats across Saudi pharmacy chains, standardizing
/// cash prices, SFDA/VAT tax compliance, package sizes, and multi-buy promotions.
class PharmacyOffer {
  /// Unique identifier of the store (e.g., 'al_nahdi', 'united_pharmacy', 'whites', 'al_dawaa').
  final String storeId;

  /// Human-readable pharmacy name.
  final String pharmacyName;

  /// Primary SKU or catalog ID used by the pharmacy chain.
  final String skuOrId;

  /// Full product title as published by the store.
  final String productTitle;

  /// Direct URL to product photo.
  final String? imageUrl;

  /// Deep link URL to the product's storefront page.
  final String? productUrl;

  /// Single-unit instant checkout cash price (including 15% VAT or 0% SFDA tax).
  final double singleUnitPrice;

  /// Indicates whether the price is confirmed to include all applicable taxes.
  final bool isVatInclusive;

  /// True if item is a government price-fixed medication exempt from 15% VAT (0% SFDA rate).
  final bool isSfdaRegulated;

  /// Extracted numerical package volume or tablet count (e.g., 400.0, 24.0).
  final double? unitQuantity;

  /// Extracted metric unit (e.g., 'ml', 'g', 'tabs', 'pcs').
  final String? unitMetric;

  /// Price normalized to standardized base unit (SAR per 100ml, SAR per 100g, or SAR per 10 tabs).
  final double? pricePerBaseUnit;

  /// Online inventory availability flag.
  final bool isOnlineInStock;

  /// True if offer was resolved via Stage 2 sanitized title fallback rather than direct barcode hit.
  final bool isFallbackMatch;

  /// Active multi-buy promotions calculated for this item.
  final List<PromoDeal> multiBuyPromos;

  /// Semantic match score computed by [ProductMatchScorer] (0.0 to 1.0).
  final double matchScore;

  /// Creates a complete [PharmacyOffer] domain entity.
  const PharmacyOffer({
    required this.storeId,
    required this.pharmacyName,
    required this.skuOrId,
    required this.productTitle,
    this.imageUrl,
    this.productUrl,
    required this.singleUnitPrice,
    this.isVatInclusive = true,
    this.isSfdaRegulated = false,
    this.unitQuantity,
    this.unitMetric,
    this.pricePerBaseUnit,
    this.isOnlineInStock = true,
    this.isFallbackMatch = false,
    this.multiBuyPromos = const [],
    this.matchScore = 1.0,
  });

  /// Returns a copy with updated attributes, primarily used when attaching fallback flags or base pricing.
  PharmacyOffer copyWith({
    String? storeId,
    String? pharmacyName,
    String? skuOrId,
    String? productTitle,
    String? imageUrl,
    String? productUrl,
    double? singleUnitPrice,
    bool? isVatInclusive,
    bool? isSfdaRegulated,
    double? unitQuantity,
    String? unitMetric,
    double? pricePerBaseUnit,
    bool? isOnlineInStock,
    bool? isFallbackMatch,
    List<PromoDeal>? multiBuyPromos,
    double? matchScore,
  }) {
    return PharmacyOffer(
      storeId: storeId ?? this.storeId,
      pharmacyName: pharmacyName ?? this.pharmacyName,
      skuOrId: skuOrId ?? this.skuOrId,
      productTitle: productTitle ?? this.productTitle,
      imageUrl: imageUrl ?? this.imageUrl,
      productUrl: productUrl ?? this.productUrl,
      singleUnitPrice: singleUnitPrice ?? this.singleUnitPrice,
      isVatInclusive: isVatInclusive ?? this.isVatInclusive,
      isSfdaRegulated: isSfdaRegulated ?? this.isSfdaRegulated,
      unitQuantity: unitQuantity ?? this.unitQuantity,
      unitMetric: unitMetric ?? this.unitMetric,
      pricePerBaseUnit: pricePerBaseUnit ?? this.pricePerBaseUnit,
      isOnlineInStock: isOnlineInStock ?? this.isOnlineInStock,
      isFallbackMatch: isFallbackMatch ?? this.isFallbackMatch,
      multiBuyPromos: multiBuyPromos ?? this.multiBuyPromos,
      matchScore: matchScore ?? this.matchScore,
    );
  }

  /// Formatted base unit denominator (e.g., '100ml', '100g', '10 tabs').
  String get baseUnitDisplayMetric {
    final m = unitMetric?.toLowerCase().trim();
    switch (m) {
      case 'ml':
        return '100ml';
      case 'g':
      case 'gm':
        return '100g';
      case 'tabs':
      case 'pcs':
        return '100 tabs';
      default:
        return m ?? 'unit';
    }
  }

  @override
  String toString() =>
      'PharmacyOffer($storeId: "$productTitle", singlePrice: $singleUnitPrice SAR, stock: $isOnlineInStock, fallback: $isFallbackMatch)';
}
