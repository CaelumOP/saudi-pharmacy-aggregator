# Pharmacy Price & Promo Aggregator — Engineering Specification (v1.1)

## 1. Problem Statement
Comparing prices and promotional discounts for healthcare and personal care items across major Saudi pharmacy chains (Al-Nahdi, United Pharmacy, Al-Dawaa, and Whites) requires manually navigating multiple sluggish storefronts and calculating complex multi-buy promotions (e.g., 1+1 Free, 2nd at 50% off). Standard mobile web scraping attempts fail due to Cloudflare/WAF anti-bot protections, inconsistent product naming between Arabic and English catalogs, undisclosed VAT inclusion across different item classifications (SFDA 0% medication vs. 15% standard cosmetics), and mismatched package volume sizes.

## 2. Solution
A 100% self-contained Android application built in Flutter (Dart) that queries Saudi pharmacy search APIs directly from the device and streams real-time price and discount comparisons onto a single screen.

The app supports native camera barcode scanning (GTIN/EAN) with automatic sanitized text fallback when a pharmacy lacks barcode indexing, as well as direct keyword search. Network traffic is routed through a Chromium-aligned HTTP transport bridge (`cronet_http` / headless WebView JavaScript execution) to match browser TLS signatures and bypass Cloudflare WAF silently, with an interactive one-tap modal sheet for manual Turnstile challenges. Results stream into a two-tier visual layout (Single-Unit Cash Price on top, Active Multi-Buy Math below), normalizing VAT and unit volume (`SAR per 100ml` / `SAR per 10 tabs`), recording scans to a persistent local watchlist, and deep-linking directly into the winning store's checkout page.

## 3. User Stories
1. **As a pharmacy shopper**, I want to scan an item's barcode using my phone's camera, so that I can immediately pull the exact same SKU across Al-Nahdi, United Pharmacy, Al-Dawaa, and Whites without typing.
2. **As a pharmacy shopper**, I want the app to automatically fall back to a sanitized text search on pharmacies that fail to return a barcode match, using the cleaned product title from a store that succeeded, so that I still get a complete cross-store comparison.
3. **As a pharmacy shopper**, I want to type a free-text search and see top cards per pharmacy side-by-side, so that I can visually verify variations and pack sizes myself.
4. **As a pharmacy shopper**, I want each card to present the **Single-Unit Price** (Tier 1) and **Active Multi-Buy Promotions** (Tier 2, showing promo type, required quantity, total checkout cash cost, and effective unit price), so that I can decide whether to buy one unit cheaply or commit to a bulk deal.
5. **As a pharmacy shopper**, I want to see a normalized **Base Unit Price** (e.g., SAR per 100ml or SAR per 10 tablets) alongside the sticker price, so that I can accurately compare different volume sizes across stores.
6. **As a pharmacy shopper**, I want all prices normalized to include mandatory 15% VAT (or marked as 0% SFDA-exempt), so that displayed figures match the exact cash required at the register.
7. **As a pharmacy shopper**, I want loyalty-point cashback offers (such as Nuhdeek or Arbahi points) completely excluded from discount rankings, so that results only show real, instant checkout discounts.
8. **As a pharmacy shopper**, I want pharmacy results to stream onto the screen asynchronously as each store responds, so that fast stores render in under 500ms without waiting on slower stores.
9. **As a pharmacy shopper**, I want previously scanned items saved to an on-device Watchlist / History tab, so that I can re-check prices on recurring products when I no longer have the physical box with me.
10. **As a pharmacy shopper**, I want a one-tap button to open the winning product page directly in that pharmacy's app or mobile browser, so that I can immediately purchase the deal.
11. **As a pharmacy shopper**, I want a one-tap in-app bottom sheet to appear when a pharmacy demands an interactive Cloudflare Turnstile challenge, so that I can tap once to refresh the clearance cookie and resume silent background querying.

## 4. Implementation Decisions

### 4.1 Tech Stack & Platform Seams
- **Framework:** Flutter (Dart), Android APK deployment (Min SDK 24 / Android 7.0+; Target SDK 34/35). Also runnable on Windows/Linux Desktop for local testing.
- **Camera / Scanning:** `mobile_scanner` (backed by Google ML Kit) for hardware-accelerated GTIN/EAN recognition.
- **Network & TLS Stack:** `dio` configured with `cronet_http` (Android Chromium networking stack) to ensure native TLS JA3/JA4 fingerprint alignment with mobile browsers, preventing Cloudflare handshake drops.
- **Anti-Bot & Session Bridge:** `flutter_inappwebview` used headlessly (for silent background cookie/fetch execution) and interactively (inside a modal bottom sheet when a 403 / Turnstile challenge is triggered).
- **Local Persistence:** `hive_flutter` for fast on-device storage of `ScanHistory` and `Watchlist` items.
- **External Navigation:** `url_launcher` configured with `LaunchMode.externalApplication` to trigger Android App Links into native pharmacy apps or browser tabs.

### 4.2 Modular Pharmacy Adapter Interface
Every pharmacy chain (`AlNahdiAdapter`, `UnitedPharmacyAdapter`, `AlDawaaAdapter`, `WhitesAdapter`) implements an isolated adapter adhering to the following contract:

```dart
abstract class PharmacyAdapter {
  String get storeId;
  String get storeName;
  String get baseUrl;

  /// Pin headers to English catalog (en-SA) for standardized brand/volume parsing
  Map<String, String> get defaultHeaders;

  Future<List<PharmacyOffer>> searchByBarcode(String gtin);
  Future<List<PharmacyOffer>> searchByKeyword(String query, {int limit = 5});
}
```

### 4.3 Unified Domain Data Model
```dart
class PharmacyOffer {
  final String storeId;
  final String pharmacyName;
  final String skuOrId;
  final String productTitle;
  final String? imageUrl;
  final String? productUrl;
  
  // Pricing & VAT
  final double singleUnitPrice;       // VAT-inclusive instant checkout price for qty = 1
  final bool isVatInclusive;          // Standardized true (15% applied or SFDA 0% exempt)
  final bool isSfdaRegulated;         // True if government price-fixed medication
  
  // Base Unit Normalization
  final double? unitQuantity;         // e.g., 400.0
  final String? unitMetric;           // "ml", "g", "tabs"
  final double? pricePerBaseUnit;     // e.g., SAR per 100ml or SAR per 10 tabs

  final bool isOnlineInStock;
  final bool isFallbackMatch;         // True if matched via Stage 2 title fallback
  final List<PromoDeal> multiBuyPromos;
}

class PromoDeal {
  final String label;                 // e.g., "1+1 Free", "2nd at 50% Off"
  final int requiredQuantity;         // e.g., 2
  final double totalCheckoutCost;     // Total SAR paid at register
  final double effectiveUnitPrice;    // totalCheckoutCost / requiredQuantity
}
```

### 4.4 Two-Stage Barcode Cascade & Title Sanitizer
1. **Stage 1 (Parallel Barcode Lookup):** The orchestrator dispatches `searchByBarcode(gtin)` across all adapters simultaneously using `en-SA` locale headers.
2. **Stage 2 (Title Extraction & Sanitization):** When one adapter succeeds and others return empty, `TitleSanitizer.clean(productTitle)` extracts:
   - **Brand & Core Name:** Preserved (e.g., `"Cetaphil Daily Facial Cleanser"`).
   - **Size & Metric:** Preserved (e.g., `"473ml"`).
   - **Promotional Noise:** Stripped via regex (e.g., `(1+1)`, `Special Offer`, `خصم`, `Promo Pack`, `Save 20%`).
3. **Stage 3 (Fallback Execution):** The orchestrator invokes `searchByKeyword(sanitizedQuery, limit: 3)` on the missing adapters and sets `isFallbackMatch = true`.

### 4.5 WAF Anti-Bot Clearance Bridge
1. Requests use `cronet_http` with a persistent cookie store.
2. If an adapter receives HTTP 403 or a Cloudflare Turnstile HTML challenge, that store lane enters state `ChallengeRequired`.
3. Tapping **"Verify Store"** displays a bottom sheet holding an `InAppWebView` pointed at the pharmacy's root search URL.
4. Where strict TLS binding blocks standalone HTTP clients, requests can be evaluated directly inside the WebView engine via `evaluateJavascript("fetch(...)")`.
5. Once Turnstile passes, cookies are synced back to the persistent store, the bottom sheet auto-dismisses, and the failed query retries.

### 4.6 Scan History & Watchlist Storage
- Every successful barcode search persists a record (`gtin`, `canonicalTitle`, `brand`, `thumbnailUrl`, `lastScannedTimestamp`) to a local Hive box.
- The home screen displays a **"Recent Scans & Watchlist"** section allowing one-tap re-queries without the physical box.

## 5. Testing Decisions
- **Primary Test Seam:** Boundary between `PharmacyAggregatorOrchestrator` / `PharmacyAdapter` implementations and mockable `HttpClientAdapter` fixtures in `Dio`.
- **API Fixture Contract Tests:** Validate JSON parsing across recorded responses from Al-Nahdi, United Pharmacy, Al-Dawaa, and Whites; verify VAT normalization, `pricePerBaseUnit` calculation, and exclusion of loyalty strings (`Nuhdeek`, `Arbahi`).
- **Title Sanitizer Unit Tests:** Verify noisy promotional strings are stripped cleanly while keeping dosage/volume metrics intact.
- **Cascade & Stream Integration Tests:** Verify Store A emits immediately on barcode match while Store B cascades to keyword search using Store A's sanitized title.

## 6. Out of Scope
- External backend servers, VPS, or cloud proxies.
- Third-party delivery aggregators (HungerStation, Jahez, Ninja, Nana).
- Customer login accounts, insurance copays, and loyalty cashback valuation.
- Branch-level GPS stock checks.
- Automated checkout or cart manipulation.

## 7. Execution Plan (Ticket Breakdown)
Execute strictly in sequential tickets:
- **Ticket 1: Terminal API Reconnaissance & Fixtures** — Inspect live search endpoints for Al-Nahdi, United Pharmacy, Al-Dawaa, and Whites using terminal/browser tools. Save real JSON responses in `test/fixtures/` and document endpoints, headers, VAT fields, and promo structures in `API_RECON.md`.
- **Ticket 2: Domain Layer, Sanitizer & Adapters** — Scaffold Dart models, `TitleSanitizer`, `PharmacyAggregatorOrchestrator`, and the four pharmacy adapters with passing unit tests against the recorded fixtures from Ticket 1.
- **Ticket 3: Cronet/WebView Anti-Bot Bridge & Local Storage** — Implement Chromium TLS networking, the one-tap `InAppWebView` Turnstile challenge modal, and Hive scan history/watchlist persistence.
- **Ticket 4: UI, Barcode Scanner & Streaming Comparison Deck** — Build the Flutter UI (runnable on Desktop for testing and Android for production), `mobile_scanner` integration, two-tier comparison cards, and deep-linking via `url_launcher`.
