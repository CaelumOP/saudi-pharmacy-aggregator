# Project Overview: Saudi Pharmacy & Beauty Aggregator

## 1. Executive Summary
The Saudi Pharmacy & Beauty Aggregator is a high-performance cross-platform mobile and desktop application developed in Flutter/Dart. It delivers real-time parallel price comparisons across leading Saudi retail pharmacies and beauty marketplaces.

## 2. Core Capabilities
- **Parallel Multi-Store Search**: Concurrently searches 9 Saudi retail pharmacies and specialized beauty stores in real time.
- **Decoupled 3-Stage Barcode Cascade**:
  - **Stage 1 (Barcode Discovery)**: Queries enabled and barcode-capable stores (`whites`, `boots`, `al_nahdi`, `lemon`, `seoulhouse`) for GTIN barcode matches.
  - **Stage 1.5 (External GTIN Resolver)**: Queries OpenBeautyFacts, OpenFoodFacts, and DuckDuckGo when store indices yield zero direct hits.
  - **Stage 2 (Title & Unit Extraction)**: Extracts sanitized product title, volume/weight, and metric unit.
  - **Stage 3 (Semantic Fallback Search)**: Dispatches fallback searches to missing stores using `ProductMatchScorer` with package size ±10% tolerance ranking.
- **Interactive Price Ladder**: Real-time streaming lanes ranking offers from lowest to highest price in Saudi Riyals (SAR).
- **Localized UI**: Dual-language support (Saudi Arabic and English) with Right-to-Left (RTL) mirroring and persisted user settings.

## 3. Active 9-Store Roster
1. **Al-Nahdi** (`al_nahdi`): Saudi Arabia's largest retail pharmacy chain.
2. **United Pharmacy** (`united_pharmacy`): Major nationwide community pharmacy network.
3. **Whites** (`whites`): Leading beauty, wellness, and pharmacy chain.
4. **Al-Dawaa** (`al_dawaa`): Nationwide pharmacy chain with SAP Hybris backend.
5. **Boots KSA** (`boots`): International health & beauty retailer with SAP Commerce Cloud API.
6. **Lemon Pharmacy** (`lemon`): Algolia-powered retail pharmacy.
7. **Nice One** (`nice_one`): Top Saudi cosmetics and beauty ecommerce platform.
8. **Golden Scent** (`golden_scent`): Saudi fragrance and luxury beauty marketplace.
9. **Seoul House** (`seoulhouse`): Specialized Korean skincare & K-Beauty retailer (`seoulhouseglobal.com`) providing live SAR prices.

## 4. Operational Maturity
- **Phase**: Active Personal Beta-Testing (single owner/developer).
- **Test Coverage**: 100% test pass rate across 107 test cases (contract tests, widget tests, orchestrator cascade tests, chaos beta tests).
- **Static Analysis**: 0 warnings, 0 errors via `flutter analyze`.
