# System Architecture

## 1. High-Level Architecture Diagram

```mermaid
flowchart TD
    UI[HomeComparisonScreen / UI Layer] --> Orchestrator[PharmacyAggregatorOrchestrator]
    Settings[AppSettingsRepository / Hive] --> Orchestrator
    
    subgraph Data & Adapters Layer
        Orchestrator --> Nahdi[AlNahdiAdapter]
        Orchestrator --> United[UnitedPharmacyAdapter]
        Orchestrator --> Whites[WhitesAdapter]
        Orchestrator --> Dawaa[AlDawaaAdapter]
        Orchestrator --> Boots[BootsAdapter]
        Orchestrator --> Lemon[LemonPharmacyAdapter]
        Orchestrator --> NiceOne[NiceOneAdapter]
        Orchestrator --> GoldenScent[GoldenScentAdapter]
        Orchestrator --> SeoulHouse[ShopifyStoreAdapter (seoulhouse)]
        Orchestrator --> BarcodeSvc[BarcodeLookupService]
    end

    subgraph Core Utilities
        Matcher[ProductMatchScorer]
        Sanitizer[TitleSanitizer]
        UnitCalc[UnitMetricsCalculator]
        Dawaa --> UnitCalc
        SeoulHouse --> Matcher
        Orchestrator --> Sanitizer
        Orchestrator --> Matcher
    end
```

## 2. Layered Responsibilities
1. **UI Layer (`lib/ui/`)**:
   - `HomeComparisonScreen`: Search bar with active autocomplete chips, barcode scanner trigger, external marketplace quick-checks (Amazon.sa, Noon KSA), and dynamic Price Ladder.
   - `SettingsBottomSheet`: Dual-language toggle (EN/AR), walk-in vs. online filter presets, and individual store toggles.
2. **Orchestration Layer (`lib/services/`)**:
   - `PharmacyAggregatorOrchestrator`: Coordinates parallel asynchronous requests across all 9 stores via Dart streams (`Stream<StoreSearchResult>`).
   - Implements decoupled 3-stage barcode cascade with package size ±10% tolerance ranking.
   - Manages store health, fallback timeouts, and Cloudflare challenge propagation.
3. **Store Adapters (`lib/adapters/`)**:
   - `PharmacyAdapter`: Abstract base interface defining `searchByKeyword`, `searchByBarcode`, and store metadata.
   - `ShopifyStoreAdapter`: Multi-tiered query strategy for Shopify stores:
     - Tier 1: `/search/suggest.json`
     - Tier 2: `/en/search/suggest.json` (resolves HTTP 417 locale restriction)
     - Tier 3: `/products.json?limit=250` with in-memory caching and `ProductMatchScorer`.
4. **Data Models (`lib/models/`)**:
   - `PharmacyOffer`: Canonical product representation including prices, unit volumes, discounts, SFDA regulation flags, and match scores.
   - `StoreSearchResult`: Stream event carrying store status, error state, or discovered offers.
5. **Persistence (`lib/services/app_settings_repository.dart`)**:
   - Hive box storage for language preference and active store selections, with auto-migration to purge legacy store IDs and guarantee `seoulhouse` activation.
