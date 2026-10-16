# Code Refactoring & File Organization Plan

## 1. File Organization Refactoring Audit
### 1.1 Purged Obsolete Files
The following deprecated adapter files were purged:
- `lib/adapters/trendyol_adapter.dart` (DELETED)
- `lib/adapters/iherb_adapter.dart` (DELETED)
- `lib/adapters/salla_store_adapter.dart` (DELETED)

### 1.2 Target Directory Hierarchy
```
lib/
├── adapters/          # 9 active store adapters implementing PharmacyAdapter
├── core/              # Shared utilities (UnitMetricsCalculator, TitleSanitizer, ProductMatchScorer)
├── l10n/              # AppStrings dual Arabic / English dictionary
├── models/            # Domain entities (PharmacyOffer, StoreSearchResult, ScoredPharmacyOffer)
├── services/          # Business logic (PharmacyAggregatorOrchestrator, AppSettingsRepository, BarcodeLookupService)
└── ui/
    ├── screens/       # HomeComparisonScreen
    └── widgets/       # OfferCard, SettingsBottomSheet, StoreLaneView
test/
├── fixtures/          # Real network JSON / HTML mock responses
├── chaos_beta_test.dart
├── adapters_fixtures_test.dart
├── orchestrator_cascade_test.dart
├── settings_and_localization_test.dart
└── widget_test.dart
```

## 2. Code Smell & Complexity Analysis
- **God Object Check**: `PharmacyAggregatorOrchestrator` was refactored into modular sub-methods (`_runBarcodeCascade`, `_executeStage3Fallbacks`, `_scoreAndSortOffers`).
- **Magic Strings / Numbers**: Centralized store identifiers into `kAllStoreIds`, `kWalkInStoreIds`, `kOnlineStoreIds`.
- **Duplicate Code**: Reusable Shopify extraction logic unified inside `ShopifyStoreAdapter` with 3-tier cascade (`/search/suggest.json` -> `/en/search/suggest.json` -> `/products.json?limit=250`).

## 3. Completed Refactoring Tasks
- [x] Removed Trendyol, iHerb, and Salla adapters.
- [x] Replaced external quick-check button for Seoul House with live Price Ladder streaming adapter.
- [x] Removed hardcoded demo search chips from `HomeComparisonScreen`.
- [x] Fixed all contract tests and verified 107/107 passing tests.
- [x] Verified zero static analysis issues via `flutter analyze`.
