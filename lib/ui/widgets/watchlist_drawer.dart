import 'package:flutter/material.dart';
import '../../domain/models/saved_item.dart';
import '../../services/watchlist_repository.dart';

/// Navigation drawer showing on-device Pinned Watchlist items and Recent Scans.
///
/// Enables 1-tap re-querying of previously scanned products without requiring the physical box.
class WatchlistDrawer extends StatefulWidget {
  /// Backing repository for local persistence.
  final WatchlistRepository repository;

  /// Callback when user taps an item to execute a new search query.
  final ValueChanged<String> onSelectQuery;

  /// Creates a [WatchlistDrawer].
  const WatchlistDrawer({
    super.key,
    required this.repository,
    required this.onSelectQuery,
  });

  @override
  State<WatchlistDrawer> createState() => _WatchlistDrawerState();
}

class _WatchlistDrawerState extends State<WatchlistDrawer> {
  List<SavedItem> _pinnedItems = [];
  List<SavedItem> _recentScans = [];

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  void _refresh() {
    setState(() {
      _pinnedItems = widget.repository.getPinnedWatchlist();
      _recentScans = widget.repository.getRecentScans();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Drawer(
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Drawer Header
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
              child: Row(
                children: [
                  Icon(Icons.history, color: Theme.of(context).colorScheme.primary),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text(
                      'Watchlist & Scans',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (_recentScans.isNotEmpty)
                    IconButton(
                      icon: const Icon(Icons.delete_sweep_outlined, size: 20),
                      tooltip: 'Clear Non-Pinned History',
                      visualDensity: VisualDensity.compact,
                      onPressed: () async {
                        await widget.repository.clearHistory(preservePinned: true);
                        _refresh();
                      },
                    ),
                ],
              ),
            ),
            const Divider(height: 1),

            // Content List
            Expanded(
              child: _recentScans.isEmpty
                  ? const Center(
                      child: Text(
                        'No scanned items yet.\nScan a barcode to save to history.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.black54, fontSize: 13),
                      ),
                    )
                  : ListView(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      children: [
                        // Pinned Watchlist Section
                        if (_pinnedItems.isNotEmpty) ...[
                          const Padding(
                            padding: EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                            child: Text(
                              'PINNED WATCHLIST',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                color: Colors.amber,
                                letterSpacing: 0.8,
                              ),
                            ),
                          ),
                          ..._pinnedItems.map((item) => _buildItemTile(item, isPinnedSection: true)),
                          const Divider(height: 16),
                        ],

                        // Recent Scans Section
                        const Padding(
                          padding: EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                          child: Text(
                            'RECENT SCANS',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              color: Colors.black54,
                              letterSpacing: 0.8,
                            ),
                          ),
                        ),
                        ..._recentScans.map((item) => _buildItemTile(item, isPinnedSection: false)),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildItemTile(SavedItem item, {required bool isPinnedSection}) {
    return ListTile(
      dense: true,
      leading: CircleAvatar(
        radius: 18,
        backgroundColor: Colors.teal.shade50,
        child: Icon(Icons.qr_code_2, size: 20, color: Colors.teal.shade800),
      ),
      title: Text(
        item.canonicalTitle,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
      ),
      subtitle: Row(
        children: [
          Expanded(
            child: Text(
              item.gtin,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 11, color: Colors.black54),
            ),
          ),
          if (item.lowestObservedPrice != null) ...[
            const SizedBox(width: 4),
            Text(
              '${item.lowestObservedPrice!.toStringAsFixed(2)} SAR',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.bold,
                color: Colors.green.shade800,
              ),
            ),
          ],
        ],
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            visualDensity: VisualDensity.compact,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
            icon: Icon(
              item.isPinnedToWatchlist ? Icons.star : Icons.star_border,
              size: 20,
              color: item.isPinnedToWatchlist ? Colors.amber : Colors.grey,
            ),
            onPressed: () async {
              await widget.repository.togglePin(item.gtin);
              _refresh();
            },
          ),
          const SizedBox(width: 6),
          IconButton(
            visualDensity: VisualDensity.compact,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
            icon: const Icon(Icons.close, size: 16, color: Colors.black45),
            onPressed: () async {
              await widget.repository.deleteItem(item.gtin);
              _refresh();
            },
          ),
        ],
      ),
      onTap: () {
        Navigator.of(context).pop();
        widget.onSelectQuery(item.gtin);
      },
    );
  }
}
