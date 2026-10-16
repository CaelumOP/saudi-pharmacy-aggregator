import 'dart:async';
import 'dart:math' as math;
import '../adapters/al_dawaa_adapter.dart';
import '../adapters/al_nahdi_adapter.dart';
import '../adapters/boots_adapter.dart';
import '../adapters/golden_scent_adapter.dart';
import '../adapters/lemon_pharmacy_adapter.dart';
import '../adapters/nice_one_adapter.dart';
import '../adapters/pharmacy_adapter.dart';
import '../adapters/shopify_store_adapter.dart';
import '../adapters/united_pharmacy_adapter.dart';
import '../adapters/whites_adapter.dart';
import '../domain/models/pharmacy_offer.dart';
import '../utils/product_match_scorer.dart';
import '../utils/title_sanitizer.dart';
import 'barcode_lookup_service.dart';
import 'smart_query_corrector.dart';

/// State of a single pharmacy search lane during streaming query execution.
enum StoreLaneStatus {
  /// Search has not yet started for this store.
  idle,

  /// Store is actively fetching data over the network.
  loading,

  /// Store requires human verification via Cloudflare Turnstile modal.
  challengeRequired,

  /// Store completed query and returned results (or 0 hits).
  completed,

  /// Network error or unrecoverable failure occurred.
  error,
}

/// Represents search results and status emitted by a specific pharmacy lane.
class StoreSearchResult {
  /// Identifier of the reporting pharmacy chain.
  final String storeId;

  /// Display name of the pharmacy.
  final String storeName;

  /// Brick-and-mortar physical presence vs online-only operation.
  final StorePresenceType presenceType;

  /// Product catalog specialty focus.
  final StoreSpecialty specialty;

  /// Current lifecycle state of this store lane.
  final StoreLaneStatus status;

  /// List of matched pharmacy offers.
  final List<PharmacyOffer> offers;

  /// Error message if [status] is [StoreLaneStatus.error].
  final String? errorMessage;

  /// Cloudflare challenge URL if [status] is [StoreLaneStatus.challengeRequired].
  final String? challengeUrl;

  /// True if results were produced via Stage 3 sanitized title fallback.
  final bool isFallbackSearch;

  /// Creates an immutable [StoreSearchResult] update event.
  const StoreSearchResult({
    required this.storeId,
    required this.storeName,
    this.presenceType = StorePresenceType.physicalAndOnline,
    this.specialty = StoreSpecialty.pharmacyAndCare,
    required this.status,
    this.offers = const [],
    this.errorMessage,
    this.challengeUrl,
    this.isFallbackSearch = false,
  });

  @override
  String toString() =>
      'StoreSearchResult($storeId: $status, offers: ${offers.length}, fallback: $isFallbackSearch)';
}

/// Alias for [StoreSearchResult] exposing lane metadata and status to UI components.
typedef StoreLaneState = StoreSearchResult;

/// Orchestrator coordinating asynchronous parallel searches, the Multi-Stage Barcode Cascade,
/// and decoupled store enable/disable filtering.
class PharmacyAggregatorOrchestrator {
  final List<PharmacyAdapter> _adapters;
  final BarcodeLookupService _barcodeLookupService;
  Set<String>? _enabledStoreIds;

  /// Returns the complete registry of default 9 store adapters.
  static List<PharmacyAdapter> defaultAdapters() => [
        AlNahdiAdapter(),
        UnitedPharmacyAdapter(),
        WhitesAdapter(),
        AlDawaaAdapter(),
        BootsAdapter(),
        LemonPharmacyAdapter(),
        NiceOneAdapter(),
        GoldenScentAdapter(),
        ShopifyStoreAdapter(
          storeId: 'seoulhouse',
          storeName: 'Seoul House',
          domain: 'seoulhouseglobal.com',
          presenceType: StorePresenceType.onlineOnly,
          specialty: StoreSpecialty.kBeautyAndSkincare,
        ),
      ];

  /// Creates an orchestrator instance with injected or default pharmacy adapters.
  PharmacyAggregatorOrchestrator({
    List<PharmacyAdapter>? adapters,
    BarcodeLookupService? barcodeLookupService,
    Set<String>? enabledStoreIds,
  })  : _adapters = adapters ?? defaultAdapters(),
        _barcodeLookupService = barcodeLookupService ?? BarcodeLookupService(),
        _enabledStoreIds = enabledStoreIds != null ? Set.from(enabledStoreIds) : null;

  /// List of registered store adapters.
  List<PharmacyAdapter> get adapters => List.unmodifiable(_adapters);

  /// Active enabled store identifiers for price comparison.
  ///
  /// When not set, all registered adapters are enabled by default.
  Set<String> get enabledStoreIds =>
      _enabledStoreIds ?? _adapters.map((a) => a.storeId).toSet();

  set enabledStoreIds(Set<String>? ids) {
    _enabledStoreIds = ids != null ? Set.from(ids) : null;
  }

  QueryCorrectionResult? _lastCorrectionResult;
  ResolvedQuery? _lastResolvedQuery;

  /// The most recent query auto-correction result, if any.
  QueryCorrectionResult? get lastCorrectionResult => _lastCorrectionResult;

  /// The most recent full query resolution result, if any.
  ResolvedQuery? get lastResolvedQuery => _lastResolvedQuery;

  /// Streams real-time search results for a text keyword query across enabled stores,
  /// optionally correcting typos via [SmartQueryCorrector],
  /// and filtering candidate offers through the 4-Layer [ProductMatchScorer].
  Stream<StoreSearchResult> searchByKeyword(
    String query, {
    int limit = 5,
    bool autoCorrect = true,
    void Function(QueryCorrectionResult)? onCorrection,
  }) {
    final controller = StreamController<StoreSearchResult>();
    final activeAdapters = _adapters.where((a) => enabledStoreIds.contains(a.storeId)).toList();

    var pendingStores = activeAdapters.length;
    if (pendingStores == 0) {
      controller.close();
      return controller.stream;
    }

    for (final adapter in activeAdapters) {
      controller.add(
        StoreSearchResult(
          storeId: adapter.storeId,
          storeName: adapter.storeName,
          presenceType: adapter.presenceType,
          specialty: adapter.specialty,
          status: StoreLaneStatus.loading,
        ),
      );
    }

    _dispatchKeywordSearch(
      query: query,
      limit: limit,
      autoCorrect: autoCorrect,
      onCorrection: onCorrection,
      activeAdapters: activeAdapters,
      controller: controller,
    );

    return controller.stream;
  }

  Future<void> _dispatchKeywordSearch({
    required String query,
    required int limit,
    required bool autoCorrect,
    required void Function(QueryCorrectionResult)? onCorrection,
    required List<PharmacyAdapter> activeAdapters,
    required StreamController<StoreSearchResult> controller,
  }) async {
    final trimmed = query.trim();
    ResolvedQuery? resolved;
    if (autoCorrect && trimmed.isNotEmpty) {
      try {
        resolved = await SmartQueryCorrector.instance.resolveQuery(trimmed);
        _lastCorrectionResult = QueryCorrectionResult(
          originalQuery: resolved.originalQuery,
          correctedQuery: resolved.primaryQuery,
          wasCorrected: resolved.wasCorrected,
          suggestions: resolved.suggestions,
        );
        _lastResolvedQuery = resolved;
        onCorrection?.call(_lastCorrectionResult!);
      } catch (_) {
        // Fall back gracefully to original query on any network/format issue
      }
    } else {
      _lastCorrectionResult = null;
      _lastResolvedQuery = null;
    }

    final effectivePrimary = resolved?.primaryQuery ?? trimmed;
    final effectiveArabic = resolved?.repairedArabicQuery ?? trimmed;
    final effectiveEnglish = resolved?.repairedEnglishQuery ?? trimmed;
    final detectedBrand = resolved?.brand;

    var pendingStores = activeAdapters.length;

    const englishPreferredStores = {
      'seoulhouse',
      'boots',
    };
    const arabicPreferredStores = {
      'lemon',
    };

    for (final adapter in activeAdapters) {
      // Determine store-specific query and fallback brand based on linguistic capability
      String storeQuery;
      String? storeBrandFallback;

      if (englishPreferredStores.contains(adapter.storeId)) {
        storeQuery = effectiveEnglish.isNotEmpty ? effectiveEnglish : effectivePrimary;
        storeBrandFallback = resolved?.englishBrand ?? detectedBrand;
      } else if (arabicPreferredStores.contains(adapter.storeId)) {
        storeQuery = effectiveArabic.isNotEmpty ? effectiveArabic : effectivePrimary;
        storeBrandFallback = resolved?.arabicBrand ?? detectedBrand;
      } else {
        storeQuery = effectivePrimary;
        final isArabic = RegExp(r'[\u0600-\u06FF]').hasMatch(storeQuery);
        storeBrandFallback = isArabic
            ? (resolved?.arabicBrand ?? detectedBrand)
            : (resolved?.englishBrand ?? detectedBrand);
      }

      _executeStoreKeywordSearch(
        adapter: adapter,
        primaryStoreQuery: storeQuery,
        brandFallbackQuery: storeBrandFallback,
        originalUserQuery: query,
        effectiveQuery: effectivePrimary,
        limit: limit,
      ).then((result) {
        if (!controller.isClosed) {
          controller.add(result);
        }
      }).catchError((error) {
        if (!controller.isClosed) {
          if (error is CloudflareChallengeException) {
            controller.add(
              StoreSearchResult(
                storeId: adapter.storeId,
                storeName: adapter.storeName,
                presenceType: adapter.presenceType,
                specialty: adapter.specialty,
                status: StoreLaneStatus.challengeRequired,
                challengeUrl: error.challengeUrl,
                errorMessage: error.message,
              ),
            );
          } else {
            controller.add(
              StoreSearchResult(
                storeId: adapter.storeId,
                storeName: adapter.storeName,
                presenceType: adapter.presenceType,
                specialty: adapter.specialty,
                status: StoreLaneStatus.error,
                errorMessage: error.toString(),
              ),
            );
          }
        }
      }).whenComplete(() {
        pendingStores--;
        if (pendingStores == 0 && !controller.isClosed) {
          controller.close();
        }
      });
    }
  }

  Future<StoreSearchResult> _executeStoreKeywordSearch({
    required PharmacyAdapter adapter,
    required String primaryStoreQuery,
    required String? brandFallbackQuery,
    required String originalUserQuery,
    required String effectiveQuery,
    required int limit,
  }) async {
    List<PharmacyOffer> offers = [];
    bool isFallback = false;

    try {
      offers = await adapter.searchByKeyword(primaryStoreQuery, limit: limit);
    } catch (e) {
      if (e is CloudflareChallengeException) rethrow;
    }

    // Filter and score primary offers
    var scoredOffers = _scoreAndFilterOffers(
      offers,
      primaryStoreQuery: primaryStoreQuery,
      effectiveQuery: effectiveQuery,
      originalUserQuery: originalUserQuery,
    );

    // Multi-stage fallback on 0 hits if brand was identified
    if (scoredOffers.isEmpty &&
        brandFallbackQuery != null &&
        brandFallbackQuery.isNotEmpty &&
        brandFallbackQuery.toLowerCase() != primaryStoreQuery.toLowerCase()) {
      try {
        final fallbackOffers = await adapter.searchByKeyword(brandFallbackQuery, limit: limit);
        if (fallbackOffers.isNotEmpty) {
          final fallbackScored = _scoreAndFilterOffers(
            fallbackOffers,
            primaryStoreQuery: primaryStoreQuery,
            effectiveQuery: effectiveQuery,
            originalUserQuery: originalUserQuery,
          );
          if (fallbackScored.isNotEmpty) {
            scoredOffers = fallbackScored;
            isFallback = true;
          }
        }
      } catch (e) {
        if (e is CloudflareChallengeException) rethrow;
      }
    }

    return StoreSearchResult(
      storeId: adapter.storeId,
      storeName: adapter.storeName,
      presenceType: adapter.presenceType,
      specialty: adapter.specialty,
      status: StoreLaneStatus.completed,
      offers: scoredOffers,
      isFallbackSearch: isFallback,
    );
  }

  List<PharmacyOffer> _scoreAndFilterOffers(
    List<PharmacyOffer> offers, {
    required String primaryStoreQuery,
    required String effectiveQuery,
    required String originalUserQuery,
  }) {
    final scoredOffers = <PharmacyOffer>[];
    for (final offer in offers) {
      final score = [
        ProductMatchScorer.score(effectiveQuery, offer.productTitle),
        ProductMatchScorer.score(originalUserQuery, offer.productTitle),
        ProductMatchScorer.score(primaryStoreQuery, offer.productTitle),
      ].reduce(math.max);

      if (score >= 0.60) {
        scoredOffers.add(offer.copyWith(matchScore: score));
      }
    }

    // Sort descending by matchScore, then ascending by price
    scoredOffers.sort((a, b) {
      final sComp = b.matchScore.compareTo(a.matchScore);
      if (sComp != 0) return sComp;
      return a.singleUnitPrice.compareTo(b.singleUnitPrice);
    });

    return scoredOffers;
  }

  /// Executes the Decoupled Multi-Stage Barcode Cascade:
  ///
  /// - Stage 1 (Barcode Discovery): Queries enabled stores and silently leverages disabled
  ///   barcode-capable stores (Whites, Boots, Trendyol, Al-Nahdi, Lemon) in the background to
  ///   resolve the GTIN to a canonical reference product without emitting them to UI lanes.
  /// - Stage 1.5: If 0 hits across all stores, falls back to [BarcodeLookupService] (Trendyol, UPCitemdb, OpenFoodFacts, DuckDuckGo).
  /// - Stage 2: Extracts sanitized product title and reference package size.
  /// - Stage 3: Dispatches fallback searches ONLY to enabled stores that lack direct barcode matches.
  Stream<StoreSearchResult> searchByBarcode(String gtin, {int fallbackLimit = 3}) {
    final controller = StreamController<StoreSearchResult>();

    _runBarcodeCascade(gtin, controller, fallbackLimit: fallbackLimit);

    return controller.stream;
  }

  Future<void> _runBarcodeCascade(
    String gtin,
    StreamController<StoreSearchResult> controller, {
    required int fallbackLimit,
  }) async {
    final activeEnabled = enabledStoreIds;
    final enabledAdapters = _adapters.where((a) => activeEnabled.contains(a.storeId)).toList();

    // Announce loading ONLY for user-enabled stores
    for (final adapter in enabledAdapters) {
      controller.add(
        StoreSearchResult(
          storeId: adapter.storeId,
          storeName: adapter.storeName,
          presenceType: adapter.presenceType,
          specialty: adapter.specialty,
          status: StoreLaneStatus.loading,
        ),
      );
    }

    // Barcode-capable stores that can resolve GTINs into canonical product titles
    const barcodeCapableStoreIds = {'whites', 'boots', 'al_nahdi', 'lemon'};

    // Query all enabled stores PLUS any disabled barcode-capable stores silently in background
    final stage1Adapters = _adapters
        .where((a) => activeEnabled.contains(a.storeId) || barcodeCapableStoreIds.contains(a.storeId))
        .toList();

    final stage1Results = <PharmacyAdapter, List<PharmacyOffer>>{};
    final emptyAdapters = <PharmacyAdapter>[];
    PharmacyOffer? winningOffer;

    final stage1Futures = stage1Adapters.map((adapter) async {
      final isEnabled = activeEnabled.contains(adapter.storeId);
      try {
        final offers = await adapter.searchByBarcode(gtin);
        stage1Results[adapter] = offers;
      } on CloudflareChallengeException catch (cfError) {
        if (isEnabled && !controller.isClosed) {
          controller.add(
            StoreSearchResult(
              storeId: adapter.storeId,
              storeName: adapter.storeName,
              presenceType: adapter.presenceType,
              specialty: adapter.specialty,
              status: StoreLaneStatus.challengeRequired,
              challengeUrl: cfError.challengeUrl,
              errorMessage: cfError.message,
            ),
          );
        }
      } catch (err) {
        if (isEnabled && !controller.isClosed) {
          controller.add(
            StoreSearchResult(
              storeId: adapter.storeId,
              storeName: adapter.storeName,
              presenceType: adapter.presenceType,
              specialty: adapter.specialty,
              status: StoreLaneStatus.error,
              errorMessage: err.toString(),
            ),
          );
        }
      }
    });

    await Future.wait(stage1Futures);

    // Pick canonical winning reference offer (prioritizing stores that physically index GTINs)
    for (final adapter in stage1Adapters) {
      if ((adapter.storeId == 'whites' || adapter.storeId == 'boots' || adapter.storeId == 'al_nahdi') &&
          stage1Results[adapter] != null &&
          stage1Results[adapter]!.isNotEmpty) {
        winningOffer = stage1Results[adapter]!.first;
        break;
      }
    }
    winningOffer ??= stage1Results.values
        .where((list) => list.isNotEmpty)
        .map((list) => list.first)
        .firstOrNull;

    // Filter Stage 1 hits against winning reference offer, emitting results ONLY for enabled adapters
    for (final adapter in enabledAdapters) {
      final hits = stage1Results[adapter];
      if (hits != null && hits.isNotEmpty) {
        final validHits = winningOffer != null
            ? ProductMatchScorer.filterAndRankByReference(winningOffer, hits)
            : hits;

        if (validHits.isNotEmpty) {
          if (!controller.isClosed) {
            controller.add(
              StoreSearchResult(
                storeId: adapter.storeId,
                storeName: adapter.storeName,
                presenceType: adapter.presenceType,
                specialty: adapter.specialty,
                status: StoreLaneStatus.completed,
                offers: validHits,
                isFallbackSearch: false,
              ),
            );
          }
        } else {
          emptyAdapters.add(adapter);
        }
      } else {
        emptyAdapters.add(adapter);
      }
    }

    String? sanitizedQuery;
    double? targetQuantity;
    String? targetMetric;

    // Stage 1.5: If 0 hits across all stores, attempt 4-tier lookup (Trendyol, UPCitemdb, OpenFoodFacts, DDG)
    if (winningOffer == null) {
      final lookupInfo = await _barcodeLookupService.lookup(gtin);
      if (lookupInfo != null && lookupInfo.canonicalTitle.trim().isNotEmpty) {
        sanitizedQuery = TitleSanitizer.clean(lookupInfo.canonicalTitle);
        final refUnitInfo = TitleSanitizer.extractUnitInfo(lookupInfo.canonicalTitle);
        targetQuantity = refUnitInfo.quantity;
        targetMetric = refUnitInfo.metric?.toLowerCase().trim();
      }
    } else {
      // Stage 2: Extract from winning offer
      sanitizedQuery = TitleSanitizer.clean(winningOffer.productTitle);
      final refUnitInfo = TitleSanitizer.extractUnitInfo(winningOffer.productTitle);
      targetQuantity = winningOffer.unitQuantity ?? refUnitInfo.quantity;
      targetMetric = (winningOffer.unitMetric ?? refUnitInfo.metric)?.toLowerCase().trim();
    }

    // Stage 3: Cascade to missing ENABLED stores using sanitized title
    if (sanitizedQuery != null && sanitizedQuery.isNotEmpty && emptyAdapters.isNotEmpty) {
      final finalSanitizedQuery = sanitizedQuery;
      final stage3Query = TitleSanitizer.buildStage3SearchQuery(sanitizedQuery);
      final fallbackFutures = emptyAdapters.map((adapter) async {
        try {
          final fallbackOffers = await adapter.searchByKeyword(
            stage3Query,
            limit: fallbackLimit,
          );

          // Score and filter fallback offers through ProductMatchScorer
          final scoredOffers = <PharmacyOffer>[];
          for (final offer in fallbackOffers) {
            final score = ProductMatchScorer.score(finalSanitizedQuery, offer.productTitle);
            if (score >= 0.60) {
              scoredOffers.add(offer.copyWith(isFallbackMatch: true, matchScore: score));
            }
          }

          // Sort fallback offers so items matching target size (within ±10% tolerance) rank first
          if (targetQuantity != null && targetMetric != null && targetQuantity > 0) {
            final refQty = targetQuantity;
            final refMetric = targetMetric;
            scoredOffers.sort((a, b) {
              final aMetric = a.unitMetric?.toLowerCase().trim();
              final bMetric = b.unitMetric?.toLowerCase().trim();
              final aMatchesMetric = aMetric == refMetric && a.unitQuantity != null && a.unitQuantity! > 0;
              final bMatchesMetric = bMetric == refMetric && b.unitQuantity != null && b.unitQuantity! > 0;

              if (aMatchesMetric && bMatchesMetric) {
                final aDiff = (a.unitQuantity! - refQty).abs() / refQty;
                final bDiff = (b.unitQuantity! - refQty).abs() / refQty;
                final aWithinTol = aDiff <= 0.10;
                final bWithinTol = bDiff <= 0.10;

                if (aWithinTol && !bWithinTol) return -1;
                if (!aWithinTol && bWithinTol) return 1;
                return aDiff.compareTo(bDiff);
              } else if (aMatchesMetric) {
                return -1;
              } else if (bMatchesMetric) {
                return 1;
              }
              return 0;
            });
          }

          if (!controller.isClosed) {
            controller.add(
              StoreSearchResult(
                storeId: adapter.storeId,
                storeName: adapter.storeName,
                presenceType: adapter.presenceType,
                specialty: adapter.specialty,
                status: StoreLaneStatus.completed,
                offers: scoredOffers,
                isFallbackSearch: true,
              ),
            );
          }
        } on CloudflareChallengeException catch (cfError) {
          if (!controller.isClosed) {
            controller.add(
              StoreSearchResult(
                storeId: adapter.storeId,
                storeName: adapter.storeName,
                presenceType: adapter.presenceType,
                specialty: adapter.specialty,
                status: StoreLaneStatus.challengeRequired,
                challengeUrl: cfError.challengeUrl,
                errorMessage: cfError.message,
                isFallbackSearch: true,
              ),
            );
          }
        } catch (err) {
          if (!controller.isClosed) {
            controller.add(
              StoreSearchResult(
                storeId: adapter.storeId,
                storeName: adapter.storeName,
                presenceType: adapter.presenceType,
                specialty: adapter.specialty,
                status: StoreLaneStatus.error,
                errorMessage: err.toString(),
                isFallbackSearch: true,
              ),
            );
          }
        }
      });

      await Future.wait(fallbackFutures);
    } else {
      // If no barcode match and Stage 1.5 failed, emit completed with empty lists for enabled adapters
      for (final adapter in emptyAdapters) {
        if (!controller.isClosed) {
          controller.add(
            StoreSearchResult(
              storeId: adapter.storeId,
              storeName: adapter.storeName,
              presenceType: adapter.presenceType,
              specialty: adapter.specialty,
              status: StoreLaneStatus.completed,
              offers: const [],
            ),
          );
        }
      }
    }

    if (!controller.isClosed) {
      await controller.close();
    }
  }
}
