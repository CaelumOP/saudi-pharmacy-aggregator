import 'package:hive/hive.dart';

/// Persistent domain entity representing a previously scanned or watchlisted pharmacy item.
///
/// Stored in on-device Hive storage to enable instant re-queries without the physical box.
class SavedItem {
  /// Scanned GTIN barcode or normalized canonical query key.
  final String gtin;

  /// Cleaned product title for display and cross-store search re-execution.
  final String canonicalTitle;

  /// Optional brand name (e.g., 'Panadol', 'Cetaphil').
  final String? brand;

  /// Photo thumbnail URL.
  final String? thumbnailUrl;

  /// Timestamp of the most recent scan or query.
  final DateTime lastScannedTimestamp;

  /// True if explicitly pinned by the user to the Watchlist tab.
  final bool isPinnedToWatchlist;

  /// Lowest price recorded across stores at time of scan.
  final double? lowestObservedPrice;

  /// Pharmacy chain that offered [lowestObservedPrice].
  final String? winningStoreName;

  /// Creates a [SavedItem] record.
  const SavedItem({
    required this.gtin,
    required this.canonicalTitle,
    this.brand,
    this.thumbnailUrl,
    required this.lastScannedTimestamp,
    this.isPinnedToWatchlist = false,
    this.lowestObservedPrice,
    this.winningStoreName,
  });

  /// Serializes the item to a JSON-compatible map for Hive storage.
  Map<String, dynamic> toMap() {
    return {
      'gtin': gtin,
      'canonicalTitle': canonicalTitle,
      'brand': brand,
      'thumbnailUrl': thumbnailUrl,
      'lastScannedTimestamp': lastScannedTimestamp.toIso8601String(),
      'isPinnedToWatchlist': isPinnedToWatchlist,
      'lowestObservedPrice': lowestObservedPrice,
      'winningStoreName': winningStoreName,
    };
  }

  /// Deserializes a map from Hive into a [SavedItem] instance.
  factory SavedItem.fromMap(Map<dynamic, dynamic> map) {
    return SavedItem(
      gtin: map['gtin']?.toString() ?? '',
      canonicalTitle: map['canonicalTitle']?.toString() ?? '',
      brand: map['brand']?.toString(),
      thumbnailUrl: map['thumbnailUrl']?.toString(),
      lastScannedTimestamp: map['lastScannedTimestamp'] != null
          ? DateTime.tryParse(map['lastScannedTimestamp'].toString()) ?? DateTime.now()
          : DateTime.now(),
      isPinnedToWatchlist: map['isPinnedToWatchlist'] == true,
      lowestObservedPrice: map['lowestObservedPrice'] != null
          ? (map['lowestObservedPrice'] as num).toDouble()
          : null,
      winningStoreName: map['winningStoreName']?.toString(),
    );
  }

  /// Returns an updated copy with modified fields.
  SavedItem copyWith({
    String? gtin,
    String? canonicalTitle,
    String? brand,
    String? thumbnailUrl,
    DateTime? lastScannedTimestamp,
    bool? isPinnedToWatchlist,
    double? lowestObservedPrice,
    String? winningStoreName,
  }) {
    return SavedItem(
      gtin: gtin ?? this.gtin,
      canonicalTitle: canonicalTitle ?? this.canonicalTitle,
      brand: brand ?? this.brand,
      thumbnailUrl: thumbnailUrl ?? this.thumbnailUrl,
      lastScannedTimestamp: lastScannedTimestamp ?? this.lastScannedTimestamp,
      isPinnedToWatchlist: isPinnedToWatchlist ?? this.isPinnedToWatchlist,
      lowestObservedPrice: lowestObservedPrice ?? this.lowestObservedPrice,
      winningStoreName: winningStoreName ?? this.winningStoreName,
    );
  }

  @override
  String toString() =>
      'SavedItem(gtin: $gtin, title: "$canonicalTitle", pinned: $isPinnedToWatchlist, last: $lastScannedTimestamp)';
}

/// Manual Hive [TypeAdapter] for [SavedItem] avoiding fragile code-generation build steps.
class SavedItemAdapter extends TypeAdapter<SavedItem> {
  @override
  final int typeId = 0;

  @override
  SavedItem read(BinaryReader reader) {
    final map = reader.readMap();
    return SavedItem.fromMap(map);
  }

  @override
  void write(BinaryWriter writer, SavedItem obj) {
    writer.writeMap(obj.toMap());
  }
}
