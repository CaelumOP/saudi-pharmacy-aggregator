import 'package:hive/hive.dart';
import '../domain/models/saved_item.dart';

/// Repository managing local scan history and user-pinned watchlist items backed by Hive.
///
/// Handles persistence, timestamp updates, deduplication by GTIN/query, and pin state toggles.
class WatchlistRepository {
  static const String defaultBoxName = 'pharmacy_watchlist_box';

  Box<dynamic>? _box;
  Map<String, dynamic>? _inMemoryStore;

  /// Creates a [WatchlistRepository] with an optional pre-opened Hive box.
  WatchlistRepository({Box<dynamic>? box}) {
    _box = box;
    _inMemoryStore = <String, dynamic>{};
  }

  /// Initializes Hive storage and opens the backing box.
  Future<void> init({String boxName = defaultBoxName}) async {
    if (!Hive.isAdapterRegistered(0)) {
      Hive.registerAdapter(SavedItemAdapter());
    }
    _box = await Hive.openBox<dynamic>(boxName);
  }

  /// Initializes an in-memory fallback store when disk persistence is locked or unavailable.
  void initInMemory() {
    _inMemoryStore ??= <String, dynamic>{};
  }

  /// Whether the repository is backed by an open box or an in-memory fallback.
  bool get isReady => (_box != null && _box!.isOpen) || _inMemoryStore != null;

  dynamic _getValue(String key) {
    if (_box != null && _box!.isOpen) {
      return _box!.get(key);
    }
    if (_inMemoryStore != null) {
      return _inMemoryStore![key];
    }
    throw StateError(
      'WatchlistRepository is not initialized. Call init() or initInMemory() before accessing data.',
    );
  }

  Future<void> _putValue(String key, dynamic val) async {
    if (_box != null && _box!.isOpen) {
      await _box!.put(key, val);
      return;
    }
    if (_inMemoryStore != null) {
      _inMemoryStore![key] = val;
      return;
    }
    throw StateError(
      'WatchlistRepository is not initialized. Call init() or initInMemory() before accessing data.',
    );
  }

  Iterable<dynamic> _getValues() {
    if (_box != null && _box!.isOpen) {
      return _box!.values;
    }
    if (_inMemoryStore != null) {
      return _inMemoryStore!.values;
    }
    throw StateError(
      'WatchlistRepository is not initialized. Call init() or initInMemory() before accessing data.',
    );
  }

  Future<void> _deleteValue(String key) async {
    if (_box != null && _box!.isOpen) {
      await _box!.delete(key);
      return;
    }
    if (_inMemoryStore != null) {
      _inMemoryStore!.remove(key);
      return;
    }
    throw StateError(
      'WatchlistRepository is not initialized. Call init() or initInMemory() before accessing data.',
    );
  }

  Future<void> _deleteAllKeys(Iterable<dynamic> keys) async {
    if (_box != null && _box!.isOpen) {
      await _box!.deleteAll(keys);
      return;
    }
    if (_inMemoryStore != null) {
      for (final k in keys) {
        _inMemoryStore!.remove(k);
      }
      return;
    }
    throw StateError(
      'WatchlistRepository is not initialized. Call init() or initInMemory() before accessing data.',
    );
  }

  Map<dynamic, dynamic> _getMap() {
    if (_box != null && _box!.isOpen) {
      return _box!.toMap();
    }
    if (_inMemoryStore != null) {
      return Map<dynamic, dynamic>.from(_inMemoryStore!);
    }
    throw StateError(
      'WatchlistRepository is not initialized. Call init() or initInMemory() before accessing data.',
    );
  }

  Future<void> _clearAllValues() async {
    if (_box != null && _box!.isOpen) {
      await _box!.clear();
      return;
    }
    if (_inMemoryStore != null) {
      _inMemoryStore!.clear();
      return;
    }
    throw StateError(
      'WatchlistRepository is not initialized. Call init() or initInMemory() before accessing data.',
    );
  }

  /// Records a scanned barcode or searched keyword item into recent history.
  ///
  /// Deduplicates by [gtinOrQuery], updating the scan timestamp while preserving existing pin status.
  Future<SavedItem> recordScan({
    required String gtinOrQuery,
    required String canonicalTitle,
    String? brand,
    String? thumbnailUrl,
    double? lowestPrice,
    String? storeName,
  }) async {
    final key = gtinOrQuery.trim();
    if (key.isEmpty) {
      throw ArgumentError('gtinOrQuery cannot be empty');
    }

    final existingRaw = _getValue(key);

    SavedItem item;
    if (existingRaw != null) {
      final existing = existingRaw is SavedItem
          ? existingRaw
          : SavedItem.fromMap(existingRaw as Map);

      item = existing.copyWith(
        canonicalTitle: canonicalTitle,
        brand: brand ?? existing.brand,
        thumbnailUrl: thumbnailUrl ?? existing.thumbnailUrl,
        lastScannedTimestamp: DateTime.now(),
        lowestObservedPrice: lowestPrice ?? existing.lowestObservedPrice,
        winningStoreName: storeName ?? existing.winningStoreName,
      );
    } else {
      item = SavedItem(
        gtin: key,
        canonicalTitle: canonicalTitle,
        brand: brand,
        thumbnailUrl: thumbnailUrl,
        lastScannedTimestamp: DateTime.now(),
        isPinnedToWatchlist: false,
        lowestObservedPrice: lowestPrice,
        winningStoreName: storeName,
      );
    }

    await _putValue(key, item.toMap());
    return item;
  }

  /// Toggles the pinned watchlist state for [gtinOrQuery].
  Future<bool> togglePin(String gtinOrQuery) async {
    final key = gtinOrQuery.trim();
    final raw = _getValue(key);
    if (raw == null) return false;

    final item = raw is SavedItem ? raw : SavedItem.fromMap(raw as Map);
    final newPinnedState = !item.isPinnedToWatchlist;
    final updated = item.copyWith(isPinnedToWatchlist: newPinnedState);
    await _putValue(key, updated.toMap());
    return newPinnedState;
  }

  /// Explicitly sets the pinned state for [gtinOrQuery].
  Future<void> setPinned(String gtinOrQuery, bool isPinned) async {
    final key = gtinOrQuery.trim();
    final raw = _getValue(key);
    if (raw == null) return;

    final item = raw is SavedItem ? raw : SavedItem.fromMap(raw as Map);
    final updated = item.copyWith(isPinnedToWatchlist: isPinned);
    await _putValue(key, updated.toMap());
  }

  /// Retrieves recent scans sorted by [SavedItem.lastScannedTimestamp] descending.
  List<SavedItem> getRecentScans({int limit = 30}) {
    final items = <SavedItem>[];

    for (final value in _getValues()) {
      if (value != null) {
        items.add(value is SavedItem ? value : SavedItem.fromMap(value as Map));
      }
    }

    items.sort((a, b) => b.lastScannedTimestamp.compareTo(a.lastScannedTimestamp));

    if (items.length > limit) {
      return items.sublist(0, limit);
    }
    return items;
  }

  /// Retrieves all items currently pinned to the user's Watchlist, newest first.
  List<SavedItem> getPinnedWatchlist() {
    return getRecentScans(limit: 1000)
        .where((item) => item.isPinnedToWatchlist)
        .toList();
  }

  /// Deletes a specific item by its GTIN or query key.
  Future<void> deleteItem(String gtinOrQuery) async {
    await _deleteValue(gtinOrQuery.trim());
  }

  /// Clears recent scan history while optionally preserving pinned watchlist items.
  Future<void> clearHistory({bool preservePinned = true}) async {
    if (!preservePinned) {
      await _clearAllValues();
      return;
    }

    final keysToDelete = <dynamic>[];
    for (final entry in _getMap().entries) {
      final value = entry.value;
      final item = value is SavedItem ? value : SavedItem.fromMap(value as Map);
      if (!item.isPinnedToWatchlist) {
        keysToDelete.add(entry.key);
      }
    }

    await _deleteAllKeys(keysToDelete);
  }

  /// Completely empties the storage box.
  Future<void> clearAll() async {
    await _clearAllValues();
  }

  /// Closes the backing Hive storage box to release file handles cleanly.
  Future<void> close() async {
    final box = _box;
    if (box != null && box.isOpen) {
      await box.close();
    }
    _inMemoryStore?.clear();
  }
}
