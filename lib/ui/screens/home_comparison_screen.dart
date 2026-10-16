import 'dart:async';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../adapters/pharmacy_adapter.dart';
import '../../domain/models/pharmacy_offer.dart';
import '../../l10n/app_strings.dart';
import '../../services/app_settings_repository.dart';
import '../../services/pharmacy_aggregator_orchestrator.dart';
import '../../services/smart_query_corrector.dart';
import '../../services/watchlist_repository.dart';
import '../widgets/barcode_scanner_modal.dart';
import '../widgets/canonical_product_hero.dart';
import '../widgets/price_ladder_row.dart';
import '../widgets/settings_bottom_sheet.dart';
import '../widgets/store_offer_detail_sheet.dart';
import '../widgets/watchlist_drawer.dart';

/// Filter categories for the store comparison list.
enum StoreFilterCategory {
  /// All stores with matching inventory.
  all,

  /// Physical retail chains with walk-in branches.
  walkIn,

  /// Digital-only and K-Beauty specialty e-commerce.
  onlineOnly,

  /// Stores offering active multi-buy or bulk promotions.
  promosOnly,
}

/// Dynamic sort order for the Price Ladder.
enum StoreSortMode {
  /// Sorted strictly by Single-Unit Cash Price ascending.
  lowestPrice,

  /// Sorted by normalized SAR per 100ml / 100g / 10 tabs ascending.
  unitValue,

  /// Sorted by lowest effective multi-buy promo price.
  bulkDeal,
}

/// Main comparison screen rendering the Canonical Product Hero and the Compact Price Ladder.
class HomeComparisonScreen extends StatefulWidget {
  /// Orchestrator coordinating cross-store search streams.
  final PharmacyAggregatorOrchestrator orchestrator;

  /// Backing repository for local persistence.
  final WatchlistRepository watchlistRepository;

  /// Optional app settings repository.
  final AppSettingsRepository? settingsRepository;

  /// Creates a [HomeComparisonScreen].
  const HomeComparisonScreen({
    super.key,
    required this.orchestrator,
    required this.watchlistRepository,
    this.settingsRepository,
  });

  @override
  State<HomeComparisonScreen> createState() => _HomeComparisonScreenState();
}

class _HomeComparisonScreenState extends State<HomeComparisonScreen> {
  final TextEditingController _searchController = TextEditingController();
  final Map<String, StoreSearchResult> _laneResults = {};

  late final AppSettingsRepository _settingsRepo;
  StreamSubscription<StoreSearchResult>? _searchSubscription;
  Timer? _debounceTimer;
  List<String> _suggestions = [];
  QueryCorrectionResult? _lastCorrection;
  bool _isSearching = false;
  String _activeQuery = '';

  StoreFilterCategory _selectedCategory = StoreFilterCategory.all;
  StoreSortMode _selectedSortMode = StoreSortMode.lowestPrice;
  bool _isZeroMatchesExpanded = false;

  @override
  void initState() {
    super.initState();
    _settingsRepo = widget.settingsRepository ?? AppSettingsRepository.instance;
    _settingsRepo.addListener(_onSettingsChanged);
    _searchController.addListener(_onSearchInputChanged);
    widget.orchestrator.enabledStoreIds = _settingsRepo.state.enabledStoreIds;
    _initializeLanes();
  }

  void _onSettingsChanged() {
    widget.orchestrator.enabledStoreIds = _settingsRepo.state.enabledStoreIds;
    setState(() {});
  }

  void _onSearchInputChanged() {
    _debounceTimer?.cancel();
    final query = _searchController.text.trim();
    if (query.length < 2) {
      if (_suggestions.isNotEmpty) {
        setState(() {
          _suggestions = [];
        });
      }
      return;
    }
    _debounceTimer = Timer(const Duration(milliseconds: 250), () async {
      final results = await SmartQueryCorrector.instance.getSuggestions(query);
      if (mounted && _searchController.text.trim() == query) {
        setState(() {
          _suggestions = results;
        });
      }
    });
  }

  void _initializeLanes() {
    for (final adapter in widget.orchestrator.adapters) {
      if (_settingsRepo.state.isStoreEnabled(adapter.storeId)) {
        _laneResults[adapter.storeId] = StoreSearchResult(
          storeId: adapter.storeId,
          storeName: adapter.storeName,
          presenceType: adapter.presenceType,
          specialty: adapter.specialty,
          status: StoreLaneStatus.idle,
        );
      }
    }
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    _searchController.removeListener(_onSearchInputChanged);
    _settingsRepo.removeListener(_onSettingsChanged);
    _searchSubscription?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  void _executeSearch(String query, {bool allowAutoCorrect = true}) {
    final trimmed = query.trim();
    if (trimmed.isEmpty) return;

    _debounceTimer?.cancel();
    _searchSubscription?.cancel();
    widget.orchestrator.enabledStoreIds = _settingsRepo.state.enabledStoreIds;

    setState(() {
      _suggestions = [];
      if (!allowAutoCorrect) {
        _lastCorrection = null;
      }
      _isSearching = true;
      _activeQuery = trimmed;
      _searchController.text = trimmed;

      for (final adapter in widget.orchestrator.adapters) {
        if (_settingsRepo.state.isStoreEnabled(adapter.storeId)) {
          _laneResults[adapter.storeId] = StoreSearchResult(
            storeId: adapter.storeId,
            storeName: adapter.storeName,
            presenceType: adapter.presenceType,
            specialty: adapter.specialty,
            status: StoreLaneStatus.loading,
          );
        }
      }
    });

    final isBarcode = RegExp(r'^\d{8,14}$').hasMatch(trimmed);
    final stream = isBarcode
        ? widget.orchestrator.searchByBarcode(trimmed)
        : widget.orchestrator.searchByKeyword(
            trimmed,
            autoCorrect: allowAutoCorrect,
            onCorrection: (correction) {
              if (mounted) {
                setState(() {
                  _lastCorrection = correction.wasCorrected ? correction : null;
                });
              }
            },
          );

    _searchSubscription = stream.listen(
      (update) {
        setState(() {
          _laneResults[update.storeId] = update;
        });

        if (update.status == StoreLaneStatus.completed && update.offers.isNotEmpty) {
          final topOffer = update.offers.first;
          widget.watchlistRepository.recordScan(
            gtinOrQuery: trimmed,
            canonicalTitle: topOffer.productTitle,
            lowestPrice: topOffer.singleUnitPrice,
            storeName: topOffer.pharmacyName,
          );
        }
      },
      onDone: () {
        setState(() {
          _isSearching = false;
        });
      },
      onError: (_) {
        setState(() {
          _isSearching = false;
        });
      },
    );
  }

  void _openBarcodeScanner() async {
    final scannedCode = await BarcodeScannerModal.show(context);
    if (scannedCode != null && scannedCode.isNotEmpty) {
      _executeSearch(scannedCode);
    }
  }

  bool _isHeroPinned() {
    final pinned = widget.watchlistRepository.getPinnedWatchlist();
    return pinned.any((p) => p.gtin == _activeQuery);
  }

  void _toggleHeroPin() async {
    // Find canonical title & lowest price from current results
    final allOffers = _laneResults.values
        .where((r) => r.status == StoreLaneStatus.completed)
        .expand((r) => r.offers)
        .toList();

    if (allOffers.isEmpty) return;

    final topOffer = allOffers.first;
    await widget.watchlistRepository.recordScan(
      gtinOrQuery: _activeQuery,
      canonicalTitle: topOffer.productTitle,
      lowestPrice: topOffer.singleUnitPrice,
      storeName: topOffer.pharmacyName,
    );
    await widget.watchlistRepository.togglePin(_activeQuery);
    setState(() {});
  }

  void _openStoreUrl(String? url) async {
    if (url == null) return;
    final uri = Uri.tryParse(url);
    if (uri != null) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings(_settingsRepo.state.language);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    // Collate matching stores
    final matchingLanes = <({StoreSearchResult lane, PharmacyOffer offer})>[];
    final zeroMatchLanes = <StoreSearchResult>[];

    var completedCount = 0;
    final activeLanes = _laneResults.values.where((l) => _settingsRepo.state.isStoreEnabled(l.storeId)).toList();
    var totalCount = activeLanes.length;

    for (final lane in activeLanes) {
      if (lane.status == StoreLaneStatus.completed) {
        completedCount++;
        if (lane.offers.isNotEmpty) {
          matchingLanes.add((lane: lane, offer: lane.offers.first));
        } else {
          zeroMatchLanes.add(lane);
        }
      } else if (lane.status == StoreLaneStatus.error || lane.status == StoreLaneStatus.challengeRequired) {
        completedCount++;
        zeroMatchLanes.add(lane);
      }
    }

    // Filter matching lanes
    final filteredLanes = matchingLanes.where((item) {
      switch (_selectedCategory) {
        case StoreFilterCategory.all:
          return true;
        case StoreFilterCategory.walkIn:
          return item.lane.presenceType == StorePresenceType.physicalAndOnline;
        case StoreFilterCategory.onlineOnly:
          return item.lane.presenceType == StorePresenceType.onlineOnly;
        case StoreFilterCategory.promosOnly:
          return item.offer.multiBuyPromos.isNotEmpty;
      }
    }).toList();

    // Sort matching lanes
    filteredLanes.sort((a, b) {
      switch (_selectedSortMode) {
        case StoreSortMode.lowestPrice:
          return a.offer.singleUnitPrice.compareTo(b.offer.singleUnitPrice);
        case StoreSortMode.unitValue:
          final aVal = a.offer.pricePerBaseUnit;
          final bVal = b.offer.pricePerBaseUnit;
          if (aVal != null && bVal != null) {
            return aVal.compareTo(bVal);
          } else if (aVal != null) {
            return -1;
          } else if (bVal != null) {
            return 1;
          }
          return a.offer.singleUnitPrice.compareTo(b.offer.singleUnitPrice);
        case StoreSortMode.bulkDeal:
          final aDealPrice = a.offer.multiBuyPromos.isNotEmpty
              ? a.offer.multiBuyPromos.map((d) => d.effectiveUnitPrice).reduce((x, y) => x < y ? x : y)
              : a.offer.singleUnitPrice;
          final bDealPrice = b.offer.multiBuyPromos.isNotEmpty
              ? b.offer.multiBuyPromos.map((d) => d.effectiveUnitPrice).reduce((x, y) => x < y ? x : y)
              : b.offer.singleUnitPrice;
          return aDealPrice.compareTo(bDealPrice);
      }
    });

    final hasResults = matchingLanes.isNotEmpty;

    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            const Icon(Icons.local_pharmacy, color: Color(0xFF10B981)),
            const SizedBox(width: 8),
            Text(
              strings.appTitle,
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.qr_code_scanner),
            tooltip: strings.scanBarcodeTooltip,
            onPressed: _openBarcodeScanner,
          ),
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            tooltip: strings.settingsTooltip,
            onPressed: () => SettingsBottomSheet.show(context, repository: _settingsRepo),
          ),
          Builder(
            builder: (ctx) => IconButton(
              icon: const Icon(Icons.bookmarks_outlined),
              tooltip: strings.watchlistTooltip,
              onPressed: () => Scaffold.of(ctx).openEndDrawer(),
            ),
          ),
        ],
      ),
      endDrawer: WatchlistDrawer(
        repository: widget.watchlistRepository,
        onSelectQuery: (q) => _executeSearch(q),
      ),
      body: SafeArea(
        top: false,
        bottom: true,
        child: Column(
          children: [
            // Search Input Field
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _searchController,
                      decoration: InputDecoration(
                        hintText: strings.searchHint,
                        prefixIcon: const Icon(Icons.search),
                        suffixIcon: _searchController.text.isNotEmpty
                            ? IconButton(
                                icon: const Icon(Icons.clear),
                                tooltip: strings.clearSearchTooltip,
                                onPressed: () {
                                  _searchController.clear();
                                  setState(() {});
                                },
                              )
                            : null,
                        isDense: true,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                      ),
                      onSubmitted: (val) => _executeSearch(val),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton.filled(
                    style: IconButton.styleFrom(backgroundColor: const Color(0xFF10B981)),
                    icon: _isSearching
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                          )
                        : const Icon(Icons.arrow_forward),
                    onPressed: _isSearching ? null : () => _executeSearch(_searchController.text),
                  ),
                ],
              ),
            ),

            // Live Autocomplete Suggestions (Google Suggest + Local Brands)
            if (_suggestions.isNotEmpty)
              Container(
                height: 38,
                margin: const EdgeInsets.only(bottom: 6),
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: _suggestions.length,
                  separatorBuilder: (_, _) => const SizedBox(width: 8),
                  itemBuilder: (ctx, idx) {
                    final sugg = _suggestions[idx];
                    return ActionChip(
                      avatar: const Icon(Icons.search, size: 14, color: Color(0xFF10B981)),
                      label: Text(sugg, style: const TextStyle(fontSize: 12)),
                      backgroundColor: isDark ? const Color(0xFF1E293B) : const Color(0xFFF1F5F9),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                      side: BorderSide(color: isDark ? const Color(0xFF334155) : const Color(0xFFCBD5E1)),
                      onPressed: () {
                        _searchController.text = sugg;
                        _executeSearch(sugg);
                      },
                    );
                  },
                ),
              ),

            // Main Content Area: Hero + Filter/Sort Controls + Price Ladder List
            Expanded(
              child: ListView(
                padding: const EdgeInsets.only(top: 4, bottom: 32),
                children: [
                  // 0. Auto-Corrected / Did You Mean Banner
                  if (_lastCorrection != null && _lastCorrection!.wasCorrected)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        decoration: BoxDecoration(
                          color: isDark
                              ? const Color(0xFF064E3B).withValues(alpha: 0.4)
                              : const Color(0xFFECFDF5),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: isDark ? const Color(0xFF059669) : const Color(0xFFA7F3D0),
                          ),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.auto_fix_high, size: 16, color: Color(0xFF10B981)),
                            const SizedBox(width: 8),
                            Expanded(
                              child: RichText(
                                text: TextSpan(
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: isDark ? const Color(0xFFD1FAE5) : const Color(0xFF065F46),
                                  ),
                                  children: [
                                    TextSpan(
                                      text: '${strings.showingResultsFor(_lastCorrection!.correctedQuery)}   ',
                                      style: const TextStyle(fontWeight: FontWeight.w600),
                                    ),
                                    TextSpan(
                                      text: strings.searchInsteadFor(_lastCorrection!.originalQuery),
                                      style: TextStyle(
                                        color: isDark ? const Color(0xFF34D399) : const Color(0xFF047857),
                                        decoration: TextDecoration.underline,
                                        fontWeight: FontWeight.bold,
                                      ),
                                      recognizer: TapGestureRecognizer()
                                        ..onTap = () {
                                          _executeSearch(_lastCorrection!.originalQuery, allowAutoCorrect: false);
                                        },
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),

                  // 1. Streaming Progress Row (if active search)
                  if (_isSearching)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: isDark ? const Color(0xFF1E293B) : Colors.teal.shade50,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          children: [
                            const SizedBox(
                              width: 12,
                              height: 12,
                              child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF10B981)),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              strings.comparingStores(totalCount, completedCount),
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: isDark ? const Color(0xFF6EE7B7) : Colors.teal.shade900,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),

                  // 2. Canonical Product Hero Card
                  if (hasResults)
                    CanonicalProductHero(
                      laneResults: _laneResults,
                      activeQuery: _activeQuery,
                      isPinned: _isHeroPinned(),
                      strings: strings,
                      onTogglePin: _toggleHeroPin,
                    ),

                  // 4. Category Filter Chips & Sort Switcher
                  if (hasResults) ...[
                    // Filter Chips Bar
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      physics: const BouncingScrollPhysics(),
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                      child: Row(
                        children: [
                          _buildFilterChip(
                            label: '${strings.filterAll} (${matchingLanes.length})',
                            category: StoreFilterCategory.all,
                            isDark: isDark,
                          ),
                          const SizedBox(width: 6),
                          _buildFilterChip(
                            label: strings.filterWalkIn,
                            category: StoreFilterCategory.walkIn,
                            isDark: isDark,
                          ),
                          const SizedBox(width: 6),
                          _buildFilterChip(
                            label: strings.filterOnline,
                            category: StoreFilterCategory.onlineOnly,
                            isDark: isDark,
                          ),
                          const SizedBox(width: 6),
                          _buildFilterChip(
                            label: strings.filterPromos,
                            category: StoreFilterCategory.promosOnly,
                            isDark: isDark,
                          ),
                        ],
                      ),
                    ),

                    // 1-Tap Sort Segmented Control
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                      child: Row(
                        children: [
                          Text(
                            strings.isArabic ? 'الترتيب:' : 'SORT BY:',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                              color: isDark ? const Color(0xFF64748B) : const Color(0xFF94A3B8),
                              letterSpacing: 0.5,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: SegmentedButton<StoreSortMode>(
                              showSelectedIcon: false,
                              style: const ButtonStyle(
                                visualDensity: VisualDensity.compact,
                                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                              ),
                              segments: [
                                ButtonSegment(
                                  value: StoreSortMode.lowestPrice,
                                  label: Text(strings.sortLowestPrice, style: const TextStyle(fontSize: 11)),
                                ),
                                ButtonSegment(
                                  value: StoreSortMode.unitValue,
                                  label: Text(strings.sortUnitValue, style: const TextStyle(fontSize: 11)),
                                ),
                                ButtonSegment(
                                  value: StoreSortMode.bulkDeal,
                                  label: Text(strings.sortBulkDeal, style: const TextStyle(fontSize: 11)),
                                ),
                              ],
                              selected: {_selectedSortMode},
                              onSelectionChanged: (newSelection) {
                                setState(() {
                                  _selectedSortMode = newSelection.first;
                                });
                              },
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],

                  // 5. The Compact Price Ladder Rows
                  if (filteredLanes.isNotEmpty) ...[
                    ...filteredLanes.asMap().entries.map((entry) {
                      final rank = entry.key + 1;
                      final item = entry.value;
                      return PriceLadderRow(
                        rank: rank,
                        laneResult: item.lane,
                        offer: item.offer,
                        strings: strings,
                        onTap: () {
                          StoreOfferDetailSheet.show(
                            context,
                            laneResult: item.lane,
                            offer: item.offer,
                            strings: strings,
                            onSelectVariant: (variant) {
                              // Variant selected
                            },
                          );
                        },
                        onOpenStore: () => _openStoreUrl(item.offer.productUrl),
                      );
                    }),
                  ] else if (hasResults) ...[
                    Padding(
                      padding: const EdgeInsets.all(24.0),
                      child: Center(
                        child: Text(
                          strings.isArabic ? 'لا توجد متاجر تطابق التصنيف المختار.' : 'No stores match the selected filter.',
                          style: TextStyle(
                            fontSize: 13,
                            color: isDark ? const Color(0xFF94A3B8) : Colors.grey.shade600,
                          ),
                        ),
                      ),
                    ),
                  ],

                  // 6. Zero Matches Collapsible Section
                  if (zeroMatchLanes.isNotEmpty && !_isSearching) ...[
                    const SizedBox(height: 12),
                    Center(
                      child: TextButton.icon(
                        style: TextButton.styleFrom(
                          visualDensity: VisualDensity.compact,
                          foregroundColor: isDark ? const Color(0xFF64748B) : Colors.grey.shade600,
                        ),
                        icon: Icon(
                          _isZeroMatchesExpanded ? Icons.expand_less : Icons.expand_more,
                          size: 16,
                        ),
                        label: Text(
                          strings.noMatchesFoundStores(zeroMatchLanes.length),
                          style: const TextStyle(fontSize: 11),
                        ),
                        onPressed: () {
                          setState(() {
                            _isZeroMatchesExpanded = !_isZeroMatchesExpanded;
                          });
                        },
                      ),
                    ),
                    if (_isZeroMatchesExpanded)
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 4),
                        child: Wrap(
                          spacing: 6,
                          runSpacing: 4,
                          alignment: WrapAlignment.center,
                          children: zeroMatchLanes.map((lane) {
                            final localizedStore = strings.storeName(lane.storeId, defaultName: lane.storeName);
                            return Chip(
                              visualDensity: VisualDensity.compact,
                              labelPadding: const EdgeInsets.symmetric(horizontal: 4),
                              label: Text(
                                '$localizedStore: ${strings.isArabic ? "لا توجد نتائج" : "No match"}',
                                style: TextStyle(
                                  fontSize: 10,
                                  color: isDark ? const Color(0xFF94A3B8) : Colors.grey.shade700,
                                ),
                              ),
                              backgroundColor: isDark ? const Color(0xFF1E293B) : Colors.grey.shade100,
                            );
                          }).toList(),
                        ),
                      ),
                  ],

                  // 7. External Marketplaces Quick-Check Bar
                  if (_activeQuery.trim().isNotEmpty) ...[
                    const SizedBox(height: 16),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.open_in_new,
                                size: 14,
                                color: isDark ? const Color(0xFF94A3B8) : Colors.grey.shade600,
                              ),
                              const SizedBox(width: 6),
                              Text(
                                strings.isArabic
                                    ? 'فحص سريع في المتاجر الكبرى:'
                                    : 'Quick check on major marketplaces:',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                  color: isDark ? const Color(0xFF94A3B8) : Colors.grey.shade600,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 8,
                            runSpacing: 6,
                            alignment: WrapAlignment.center,
                            children: [
                              OutlinedButton.icon(
                                style: OutlinedButton.styleFrom(
                                  visualDensity: VisualDensity.compact,
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                ),
                                icon: const Icon(Icons.shopping_bag_outlined, size: 14),
                                label: const Text('Amazon.sa', style: TextStyle(fontSize: 11)),
                                onPressed: () {
                                  final q = Uri.encodeComponent(_activeQuery);
                                  _openStoreUrl('https://www.amazon.sa/s?k=$q');
                                },
                              ),
                              OutlinedButton.icon(
                                style: OutlinedButton.styleFrom(
                                  visualDensity: VisualDensity.compact,
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                ),
                                icon: const Icon(Icons.flash_on_outlined, size: 14),
                                label: const Text('Noon KSA', style: TextStyle(fontSize: 11)),
                                onPressed: () {
                                  final q = Uri.encodeComponent(_activeQuery);
                                  _openStoreUrl('https://www.noon.com/saudi-en/search/?q=$q');
                                },
                              ),
                            ],
                          ),
                          const SizedBox(height: 24),
                        ],
                      ),
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

  Widget _buildFilterChip({
    required String label,
    required StoreFilterCategory category,
    required bool isDark,
  }) {
    final isSelected = _selectedCategory == category;
    return ChoiceChip(
      visualDensity: VisualDensity.compact,
      label: Text(label, style: const TextStyle(fontSize: 11)),
      selected: isSelected,
      selectedColor: isDark ? const Color(0xFF064E3B) : const Color(0xFFD1FAE5),
      labelStyle: TextStyle(
        fontSize: 11,
        fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
        color: isSelected
            ? (isDark ? const Color(0xFF6EE7B7) : const Color(0xFF065F46))
            : (isDark ? Colors.white70 : const Color(0xFF334155)),
      ),
      onSelected: (val) {
        if (val) {
          setState(() {
            _selectedCategory = category;
          });
        }
      },
    );
  }
}
