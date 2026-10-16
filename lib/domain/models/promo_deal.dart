/// Represents a multi-buy promotional deal (e.g. 1+1 Free, 2nd at 50% Off).
///
/// Encapsulates required minimum purchase quantities, total cash expenditure at checkout,
/// and effective per-unit pricing to allow mathematical comparison across store promotions.
class PromoDeal {
  /// Promotional banner or badge text describing the deal.
  final String label;

  /// Number of units required to qualify for this promotional deal.
  final int requiredQuantity;

  /// Total SAR payable at register for [requiredQuantity] units.
  final double totalCheckoutCost;

  /// Effective unit price calculated as [totalCheckoutCost] divided by [requiredQuantity].
  final double effectiveUnitPrice;

  /// Creates a validated promotional deal structure.
  const PromoDeal({
    required this.label,
    required this.requiredQuantity,
    required this.totalCheckoutCost,
    required this.effectiveUnitPrice,
  });

  /// Factory constructor to automatically derive [effectiveUnitPrice] from checkout cost.
  factory PromoDeal.create({
    required String label,
    required int requiredQuantity,
    required double totalCheckoutCost,
  }) {
    final effectivePrice = requiredQuantity > 0
        ? (totalCheckoutCost / requiredQuantity)
        : totalCheckoutCost;
    return PromoDeal(
      label: label,
      requiredQuantity: requiredQuantity,
      totalCheckoutCost: totalCheckoutCost,
      effectiveUnitPrice: double.parse(effectivePrice.toStringAsFixed(2)),
    );
  }

  @override
  String toString() =>
      'PromoDeal(label: $label, qty: $requiredQuantity, total: $totalCheckoutCost SAR, effective: $effectiveUnitPrice SAR/ea)';
}
