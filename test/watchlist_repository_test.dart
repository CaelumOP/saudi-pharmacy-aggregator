import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:pharmacy_app/services/watchlist_repository.dart';

void main() {
  group('WatchlistRepository Unit Tests', () {
    late Directory tempDir;
    late WatchlistRepository repository;

    setUp(() async {
      tempDir = Directory.systemTemp.createTempSync('hive_watchlist_test_');
      Hive.init(tempDir.path);
      repository = WatchlistRepository();
      await repository.init(boxName: 'test_watchlist_box');
    });

    tearDown(() async {
      await Hive.close();
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    });

    test('records new scanned item and retrieves via getRecentScans', () async {
      final item = await repository.recordScan(
        gtinOrQuery: '6285096003799',
        canonicalTitle: 'Panadol Extra 24 Tablets',
        brand: 'Panadol',
        lowestPrice: 8.0,
        storeName: 'Whites',
      );

      expect(item.gtin, equals('6285096003799'));
      expect(item.canonicalTitle, equals('Panadol Extra 24 Tablets'));
      expect(item.isPinnedToWatchlist, isFalse);

      final recent = repository.getRecentScans();
      expect(recent.length, equals(1));
      expect(recent.first.canonicalTitle, equals('Panadol Extra 24 Tablets'));
    });

    test('deduplicates recurring scan and preserves pin status', () async {
      await repository.recordScan(
        gtinOrQuery: '6285096003799',
        canonicalTitle: 'Panadol Extra 24 Tablets',
        lowestPrice: 8.0,
      );

      // Pin the item
      final pinned = await repository.togglePin('6285096003799');
      expect(pinned, isTrue);

      // Re-scan with updated price
      await repository.recordScan(
        gtinOrQuery: '6285096003799',
        canonicalTitle: 'Panadol Extra 24 Tablets',
        lowestPrice: 6.95,
        storeName: 'United Pharmacy',
      );

      final recent = repository.getRecentScans();
      expect(recent.length, equals(1), reason: 'Should not create duplicate entries for same GTIN');
      expect(recent.first.lowestObservedPrice, equals(6.95));
      expect(recent.first.winningStoreName, equals('United Pharmacy'));
      expect(recent.first.isPinnedToWatchlist, isTrue, reason: 'Pin status must be preserved on re-scan');
    });

    test('toggles and filters pinned watchlist items', () async {
      await repository.recordScan(
        gtinOrQuery: '3499320017046',
        canonicalTitle: 'Cetaphil Gentle Skin Cleanser 473 ml',
        lowestPrice: 104.65,
      );

      await repository.recordScan(
        gtinOrQuery: '6285096003799',
        canonicalTitle: 'Panadol Extra 24 Tablets',
        lowestPrice: 8.0,
      );

      expect(repository.getPinnedWatchlist(), isEmpty);

      // Pin Cetaphil
      await repository.setPinned('3499320017046', true);
      final pinnedList = repository.getPinnedWatchlist();
      expect(pinnedList.length, equals(1));
      expect(pinnedList.first.gtin, equals('3499320017046'));

      // Unpin Cetaphil via toggle
      await repository.togglePin('3499320017046');
      expect(repository.getPinnedWatchlist(), isEmpty);
    });

    test('sorts recent scans newest first', () async {
      await repository.recordScan(
        gtinOrQuery: 'SKU_1',
        canonicalTitle: 'First Item',
      );

      // Brief delay to ensure different timestamps
      await Future.delayed(const Duration(milliseconds: 20));

      await repository.recordScan(
        gtinOrQuery: 'SKU_2',
        canonicalTitle: 'Second Item',
      );

      final recent = repository.getRecentScans();
      expect(recent.length, equals(2));
      expect(recent[0].canonicalTitle, equals('Second Item'));
      expect(recent[1].canonicalTitle, equals('First Item'));
    });

    test('deletes individual item by key', () async {
      await repository.recordScan(
        gtinOrQuery: 'DEL_SKU',
        canonicalTitle: 'Disposable Item',
      );
      expect(repository.getRecentScans().length, equals(1));

      await repository.deleteItem('DEL_SKU');
      expect(repository.getRecentScans(), isEmpty);
    });

    test('clears history while preserving pinned watchlist items', () async {
      await repository.recordScan(
        gtinOrQuery: 'ITEM_REGULAR',
        canonicalTitle: 'Regular Scan',
      );

      await repository.recordScan(
        gtinOrQuery: 'ITEM_PINNED',
        canonicalTitle: 'Favorite Deal',
      );
      await repository.setPinned('ITEM_PINNED', true);

      expect(repository.getRecentScans().length, equals(2));

      await repository.clearHistory(preservePinned: true);

      final remaining = repository.getRecentScans();
      expect(remaining.length, equals(1));
      expect(remaining.first.gtin, equals('ITEM_PINNED'));
      expect(remaining.first.isPinnedToWatchlist, isTrue);

      // Clear all
      await repository.clearAll();
      expect(repository.getRecentScans(), isEmpty);
    });
  });
}
