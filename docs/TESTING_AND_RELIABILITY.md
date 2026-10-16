# Testing and Reliability Strategy

## 1. Testing Framework & Philosophy
The project enforces test-driven quality assurance using `flutter_test`. Tests are divided into:
- **Contract Tests (`test/adapters_fixtures_test.dart`)**: Verify each adapter parses raw HTTP JSON/HTML payloads accurately against captured fixtures.
- **Cascade Integration Tests (`test/orchestrator_cascade_test.dart`)**: Verify the decoupled 3-stage barcode cascade, Stage 1.5 external lookup, and Stage 3 fallback size-tolerance ranking.
- **Chaos Beta Tests (`test/chaos_beta_test.dart`)**: Test mangled queries, typo tolerance, fat-finger errors, and Arabic/English query cross-matching.
- **Widget & Settings Tests (`test/settings_and_localization_test.dart`, `test/widget_test.dart`)**: Test UI state, language toggling, store roster filtering, and Hive persistence migration.

## 2. "Seen-to-Fail" Verification Rule (Mutation Testing)
Every critical test has been verified against deliberate production mutations:

| Test Name | Targeted Module | Injected Mutation | Observed Red Result | Restored Green Result |
|---|---|---|---|---|
| `ShopifyStoreAdapter Contract Tests: cascades from 417` | `lib/adapters/shopify_store_adapter.dart` | Disabled `/en/search/suggest.json` fallback | `Expected: non-empty, Actual: []` (Exit code 1) | `All tests passed!` (Exit code 0) |
| `AppSettingsRepository: initializes with all 9 stores` | `lib/services/app_settings_repository.dart` | Omitted `'seoulhouse'` from `kAllStoreIds` | `Expected: <9>, Actual: <8>`, `Found 0 widgets with text "9 / 9"` | `All tests passed!` (Exit code 0) |
| `Orchestrator: Stage 3 fallback prioritizes size` | `lib/services/pharmacy_aggregator_orchestrator.dart` | Inverted tolerance comparator `return 1` vs `return -1` | `Expected: <473.0>, Actual: <118.0>` | `All tests passed!` (Exit code 0) |

## 3. Reliability Metrics
- Total Unit & Integration Tests: 107
- Passing Rate: 100% (107/107)
- Static Analysis: 0 issues (`flutter analyze`)
- Network Timeouts: 6,000ms connect timeout, 8,000ms receive timeout per Dio adapter request.
