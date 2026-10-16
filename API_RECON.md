# Saudi Pharmacy Search API Reconnaissance & Fixtures Specification

## 1. Executive Summary

This document records the reverse-engineering reconnaissance and API contract analysis for the four target Saudi pharmacy chains:
1. **Al-Nahdi** (`nahdionline.com`)
2. **United Pharmacy** (`unitedpharmacy.sa`)
3. **Whites Pharmacy** (`whites.net` / `whites.sa`)
4. **Al-Dawaa** (`al-dawaa.com`)

Live network inspection and automated terminal probing have determined the search architecture, endpoint URLs, query protocols, authentication headers, VAT classifications, multi-buy discount fields, and Cloudflare/WAF anti-bot behaviors for each chain. Real sample JSON responses have been captured and saved to `test/fixtures/`.

---

## 2. Store-by-Store API Architecture & Specifications

### 2.1 Al-Nahdi (`nahdionline.com`)

- **Store ID:** `al_nahdi`
- **Store Name:** Al-Nahdi Pharmacy
- **Base Web URL:** `https://www.nahdionline.com`
- **Catalog Locale:** `en-sa`
- **Backend Architecture:** Headless Next.js storefront backed by Algolia Search Engine.

#### Search Endpoint
- **URL:** `https://H9X4IH7M99-dsn.algolia.net/1/indexes/prod_en_products/query`
- **Alternative Multi-Query URL:** `https://H9X4IH7M99-dsn.algolia.net/1/indexes/*/queries`
- **HTTP Method:** `POST`

#### Headers
```http
Content-Type: application/json
X-Algolia-Application-Id: H9X4IH7M99
X-Algolia-API-Key: 2bbce1340a1cab2ccebe0307b1310881
Accept: application/json
```

#### Request Payload
```json
{
  "query": "Panadol",
  "hitsPerPage": 5
}
```

#### Barcode (GTIN) vs Keyword Behavior
- **Keyword Search:** High accuracy, returns faceted hits for English & Arabic brand names.
- **Barcode Search:** Primary Algolia index (`prod_en_products`) is keyed on internal Nahdi SKUs (e.g., `100015980`) and product titles rather than standard 13-digit EAN/GTIN barcodes. GTIN lookups return 0 hits, validating the Stage 2 title sanitization fallback mechanism.

#### Pricing, VAT & SFDA Medication Fields
- **Single-Unit Cash Price:** `hit.price.SAR.default` (e.g., `8.0` for Panadol Extra 24 pcs, `6.95` for Panadol Advance).
- **Original / Strikethrough Price:** `hit.price.SAR.default_original_formated` (e.g., `"161.00 SAR"` when on sale).
- **Formatted Display Price:** `hit.price.SAR.default_formated` (e.g., `"8.00 SAR"`).
- **VAT Inclusivity:** All consumer prices in KSA include 15% VAT by ZATCA mandate.
- **SFDA Regulation Flag:**
  - `hit.imf_class`: String classification (e.g., `"ADULT SIMPLE ANALGESICS"`, `"COLD MEDICATIONS AND ANALGESIC"`). When categorized under registered human medicine, SFDA zero-rates VAT (0%).
  - `hit.rx_items`: `"No"` or `"Yes"` (Prescription medication indicator).

#### Multi-Buy Promotions & Exclusions
- **Bundle Promotions:**
  - `hit.bundle_skus`: Identifier for promotional bundle packages (e.g., `102005195`).
  - `hit.bundle_discount_price_start_date` / `bundle_discount_price_end_date`: Promotion validity period.
  - `hit.redbox_pl_custom`: Promotional badges.
- **Loyalty Point Exclusion (Crucial):**
  - `hit.boosted_points`: Represents Nahdi **Nuhdeek** loyalty cashback points.
  - *Rule:* Completely exclude `boosted_points` from discount calculations.

---

### 2.2 United Pharmacy (`unitedpharmacy.sa`)

- **Store ID:** `united_pharmacy`
- **Store Name:** United Pharmacy
- **Base Web URL:** `https://unitedpharmacy.sa`
- **Catalog Locale:** `en` (`/en/`)
- **Backend Architecture:** Adobe Commerce (Magento 2) integrated with Algolia Search Engine.

#### Search Endpoint
- **URL:** `https://Y1GOQ9DTV8-dsn.algolia.net/1/indexes/unitedpharmacy_liveen_products/query`
- **HTTP Method:** `POST`

#### Headers
```http
Content-Type: application/json
X-Algolia-Application-Id: Y1GOQ9DTV8
X-Algolia-API-Key: NGFkYzM5MDgzYjA0YmI2YzdlYjk4YjIwNDFjZjQzZTg2ZDQ4M2Q0ZGM5ZTVjYTgxYTNjZWRlMjllZDg0YTg3Y3RhZ0ZpbHRlcnM9
Accept: application/json
```

#### Request Payload
```json
{
  "query": "Panadol",
  "hitsPerPage": 5
}
```

#### Barcode (GTIN) vs Keyword Behavior
- **Keyword Search:** Returns detailed product catalog hits with category hierarchies and stock status.
- **Barcode Search:** Algolia index is keyed on internal Magento SKUs (`102546`) and titles. GTIN barcode queries return 0 hits and trigger title fallback cascade.

#### Pricing, VAT & SFDA Medication Fields
- **Single-Unit Cash Price:** `hit.price.SAR.default` (e.g., `6.95` for Panadol Advance 24 Tablets).
- **Original Price (Sale Strikethrough):** `hit.price.SAR.default_original_formated` (e.g., `"115.00"` for 50% off deals).
- **Stock Status:** `hit.in_stock` (Integer `1` for in-stock, `0` for out-of-stock) and `hit.custom_in_stock` (boolean).
- **SFDA Regulation Flag:**
  - `hit.categories.level0`: `["Medications"]` indicates 0% SFDA-exempt medicine.
  - Non-medications (e.g., Skin Care, Hair Care) are subject to standard 15% VAT.

#### Multi-Buy Promotions & Exclusions
- **Active Promotions:**
  - `hit.offer_label`: String promotion label (e.g., `"50% Off"`, `"40% Off"`, `"1+1 Free"`).
  - `hit.offerApplicableLabel`: Applied promo description.
  - `hit.isOfferApplicable`: Boolean flag indicating active promo rule.
- **Loyalty Point Exclusion (Crucial):**
  - `hit.maksab_points_label`: Represents **Maksab** loyalty rewards.
  - *Rule:* Completely exclude `maksab_points_label` from checkout price and discount rankings.

---

### 2.3 Whites Pharmacy (`whites.net` / `whites.sa`)

- **Store ID:** `whites`
- **Store Name:** Whites Pharmacy
- **Base Web URL:** `https://www.whites.sa` (redirects from `https://www.whites.net`)
- **Catalog Locale:** `en-sa` (`/en-sa/`)
- **Backend Architecture:** Akinon Cloud Commerce platform integrated with Algolia Search Engine.

#### Search Endpoint
- **URL:** `https://AHYKO0TELX-dsn.algolia.net/1/indexes/whites_extensions_prod/query`
- **HTTP Method:** `POST`

#### Headers
```http
Content-Type: application/json
X-Algolia-Application-Id: AHYKO0TELX
X-Algolia-API-Key: b0bbe4982fcf187041bf7bfb53afbfb1
Accept: application/json
```

#### Request Payload
```json
{
  "query": "Panadol",
  "hitsPerPage": 5
}
```

#### Barcode (GTIN) vs Keyword Behavior
- **Direct GTIN Barcode Indexing (Hero Feature):**
  - Whites explicitly stores real commercial EAN/GTIN barcodes in the dedicated `gtin` field!
  - Example hit:
    ```json
    "gtin": "6285096003799,6285096000842,8815408,6286740000409",
    "title": "Panadol Extra 500Mg 24Tablets"
    ```
  - Querying `6285096003799` directly returns `1` hit (`Panadol Extra 500Mg 24Tablets`).
  - Querying `3499320017046` directly returns `1` hit (`Cetaphil Gentle Skin Cleanser 473 Ml`).
  - **Architectural Seam:** Whites acts as the primary barcode anchor for Stage 1 lookup in the two-stage cascade. When a user scans a physical barcode, Whites resolves the canonical product title and volume, which is sanitized and forwarded to Al-Nahdi, United Pharmacy, and Al-Dawaa.

#### Pricing, VAT & SFDA Medication Fields
- **Single-Unit Cash Price:** `hit.sale_price` (e.g., `"8.00 SAR"`, `"120.75 SAR"`). If no sale active, equals `hit.price` (e.g., `"161.00 SAR"`).
- **Stock Status:** `hit.stock` (String numeric, e.g., `"44"`).
- **Product Title:** `hit.title` (English) and `hit.title_ar` (Arabic).

---

### 2.4 Al-Dawaa (`al-dawaa.com`)

- **Store ID:** `al_dawaa`
- **Store Name:** Al-Dawaa Pharmacy
- **Base Web URL:** `https://www.al-dawaa.com`
- **Catalog Locale:** `en` (`/en/`)
- **Backend Architecture:** SAP Commerce Cloud (SAP Hybris) with SAP Spartacus Angular Single Page App, fronted by Cloudflare WAF.

#### Live Search Endpoints
Al-Dawaa operates two distinct communication seams:

1. **Direct OCC REST API (Headless Client Seam):**
   - **URL:** `https://stgprevapi.al-dawaa.com/occ/v2/aldawaa/products/search`
   - **Query String:** `?query={searchTerm}&lang=en&curr=SAR&pageSize=5`
   - **HTTP Method:** `GET`
   - **Headers:**
     ```http
     Accept: application/json
     Accept-Language: en-SA,en;q=0.9
     User-Agent: Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36
     ```

2. **Web / Challenge Seam (`www.al-dawaa.com`):**
   - **URL:** `https://www.al-dawaa.com/occ/v2/aldawaa/products/search?query={searchTerm}`
   - **Protection:** Cloudflare Managed Challenge (Turnstile WAF).
   - **Behavior:** Standalone non-browser TLS clients receive `HTTP 403 Forbidden` with header `Cf-Mitigated: challenge` and HTML containing `https://challenges.cloudflare.com`.

#### Barcode (GTIN) vs Keyword Behavior
- **Keyword Search:** Queries free-text search across SAP Hybris Solr catalog (returns 19 hits for "panadol", 36 hits for "Cetaphil").
- **Barcode Search:** Only internal product codes (e.g., `101690`) are indexed; physical GTIN barcodes return 0 results and cascade to sanitized keyword search.

#### Pricing, VAT & SFDA Medication Fields
- **Single-Unit Cash Price:** `product.price.value` (Double, e.g., `8.0` for Panadol Extra, `141.45` for Cetaphil).
- **Discount Price:** `product.simulatedDiscountPrice.value` (Double, e.g., `106.09`).
- **SFDA Regulation Flag:**
  - `product.prescription`: Boolean (`true` / `false`). Identifies price-fixed medicines exempt from 15% VAT.
- **Stock Status:** `product.stock.stockLevelStatus` (`"inStock"` vs `"outOfStock"`).

#### Multi-Buy Promotions & Exclusions
- **Promotional Badges:**
  - `product.productLabels`: List of promotional badges containing code, format, shape, and banner images (e.g., `"WOMAN10"`, `"q-commerce"`).
- **Loyalty Point Exclusion (Crucial):**
  - `product.numberOfArbahiPointsToHave`
  - `product.numberOfArbahiPointsToPay`
  - *Rule:* Represents Al-Dawaa **Arbahi** points. Must be completely excluded from discount calculations.

---

## 3. Cloudflare & WAF Analysis

| Store | Fronting CDN / WAF | Challenge Behavior | Recommended Transport Bridge |
|---|---|---|---|
| **Al-Nahdi** | CloudFront / Algolia DSN | Direct Algolia DSN API access bypasses web bot traps; zero challenge drops. | Direct `cronet_http` HTTPS request. |
| **United Pharmacy** | Cloudflare / Algolia DSN | Web domain is Cloudflare DYNAMIC; search API is hosted on Algolia DSN without challenge. | Direct `cronet_http` HTTPS request. |
| **Whites Pharmacy** | Nginx / Akinon CDN / Algolia DSN | Direct Algolia DSN API access bypasses web bot traps; zero challenge drops. | Direct `cronet_http` HTTPS request. |
| **Al-Dawaa** | Cloudflare Managed Turnstile | `www.al-dawaa.com` triggers `HTTP 403 Forbidden` with Turnstile challenge; `stgprevapi.al-dawaa.com` provides direct OCC JSON payloads. | Primary: `stgprevapi` OCC API. Fallback: Ticket 3 `InAppWebView` Turnstile clearance modal when accessing `www.al-dawaa.com`. |

---

## 4. Cross-Store Barcode Cascade Validation

During live terminal reconnaissance, cross-store cascade was verified with real product data:

1. **Input Barcode:** `3499320017046` (Cetaphil Gentle Skin Cleanser)
2. **Stage 1 (Parallel Barcode Lookup):**
   - Al-Nahdi: 0 hits
   - United Pharmacy: 0 hits
   - Al-Dawaa: 0 hits
   - **Whites Pharmacy:** **1 hit** -> `"Cetaphil Gentle Skin Cleanser 473 Ml"`, Sale Price: `120.75 SAR`, Original: `161.00 SAR`
3. **Stage 2 (Title Sanitization):**
   - Input: `"Cetaphil Gentle Skin Cleanser 473 Ml"`
   - Output: `"Cetaphil Gentle Skin Cleanser 473"`
4. **Stage 3 (Fallback Execution):**
   - **Al-Nahdi:** Matched `"Cetaphil Gentle Skin Cleanser - 473 ml"`, Checkout Price: `104.65 SAR`, Original: `161.00 SAR`
   - **United Pharmacy:** Matched `"Cetaphil Gentle Skin Cleanser 118Ml"`, Checkout Price: `59.80 SAR`
   - **Al-Dawaa:** Matched `"Cetaphil, Gentle Skin Cleanser"`, Checkout Price: `89.00 SAR`

This confirms the end-to-end viability of the architectural design defined in `SPEC.md`.

---

## 5. Fixtures Inventory (`test/fixtures/`)

The following 14 real sample response fixtures have been recorded directly from the live public endpoints and saved into `test/fixtures/`:

| Fixture File | Source Store | Query Type | Description |
|---|---|---|---|
| `al_nahdi_panadol.json` | Al-Nahdi | Keyword | 5 hits for "Panadol" (includes Extra 24 pcs, Advance 24 tablets, prices, IMF classes). |
| `al_nahdi_cetaphil.json` | Al-Nahdi | Keyword | 5 hits for "Cetaphil" (includes moisturizing cream twin pack, original vs discount prices). |
| `al_nahdi_barcode.json` | Al-Nahdi | GTIN | Query with standard barcode `6291038000305` returning empty hits for Stage 1. |
| `united_pharmacy_panadol.json` | United Pharmacy | Keyword | Hits for "Panadol Advance 24 Tablets" (SKU `102546`, SAR `6.95`, category "Medications"). |
| `united_pharmacy_cetaphil.json` | United Pharmacy | Keyword | Hits for "Cetaphil" products with active discounts (e.g., 50% Off, 40% Off). |
| `united_pharmacy_barcode.json` | United Pharmacy | GTIN | Query with standard barcode `6291038000305` returning empty hits for Stage 1. |
| `whites_panadol.json` | Whites | Keyword | 5 hits for Panadol with prices (`"8.00 SAR"`), stock levels, and `gtin` lists. |
| `whites_cetaphil.json` | Whites | Keyword | 5 hits for Cetaphil with `price` vs `sale_price` and stock quantities. |
| `whites_barcode.json` | Whites | GTIN | Query with real GTIN `6285096003799` returning 1 hit for `Panadol Extra 500Mg 24Tablets`. |
| `al_dawaa_panadol.json` | Al-Dawaa | Keyword | SAP OCC response for "panadol" (includes Panadol Extra 24 Tablets, Arbahi flags). |
| `al_dawaa_cetaphil.json` | Al-Dawaa | Keyword | SAP OCC response for "Cetaphil" (includes `price`, `simulatedDiscountPrice`, `productLabels`). |
| `al_dawaa_barcode.json` | Al-Dawaa | GTIN | SAP OCC response for GTIN barcode `6285096003799` returning 0 results. |
| `al_dawaa_cloudflare_403.html` | Al-Dawaa | WAF / CF | Full HTML response of Cloudflare Turnstile challenge returned by `al-dawaa.com`. |
| `al_dawaa_cloudflare_403_meta.json` | Al-Dawaa | WAF Meta | HTTP 403 status, CF-RAY, `Cf-Mitigated: challenge`, and headers for anti-bot testing. |

---

## 6. Wave 1 Store Expansion Reconnaissance (Ticket 5)

In Ticket 5, seven additional retail candidates and two global open barcode registries were reconnoitered for Saudi Arabia (SAR):

### 6.1 Boots KSA (`sa.boots.com`)
- **Store ID:** `boots`
- **Presence & Specialty:** `StorePresenceType.physicalAndOnline`, `StoreSpecialty.pharmacyAndCare`
- **Engine:** Direct Algolia Search Engine
- **Endpoint:** `https://LQE0C6VCY3-dsn.algolia.net/1/indexes/bp_prod_sa_en/query`
- **Headers:**
  - `X-Algolia-Application-Id: LQE0C6VCY3`
  - `X-Algolia-API-Key: f12de14eaa992a4ae3a13f40b61c3978`
- **Features:** GTIN barcodes indexed directly in `attr_aims_barcode`. Full pricing, strikethrough, and promotion labels.
- **Sample Pricing:** Cetaphil Gentle Skin Cleanser (161.00 SAR), COSRX Aloe Soothing Sun Cream (66.75 SAR).

### 6.2 K-Style Seoul (`kstyleseoul.com`) & K-Beauty Kingdom (`kbeautykingdom.com`)
- **Store ID:** `kstyleseoul` / `kbeautykingdom`
- **Presence & Specialty:** `StorePresenceType.onlineOnly`, `StoreSpecialty.kBeautyAndSkincare`
- **Engine:** Shopify Storefront Predictive Search
- **Endpoint:** `https://kstyleseoul.com/search/suggest.json?q={query}&resources[type]=product`
- **Features:** High-speed predictive search returning product titles, SAR prices, compare-at prices, stock availability, and image URLs.
- **Sample Pricing:** COSRX Hyaluronic Hydra Power Essence (165.00 SAR), COSRX Peptide Booster Serum (170.00 SAR).

### 6.3 Nice One (`niceonesa.com`)
- **Store ID:** `nice_one`
- **Presence & Specialty:** `StorePresenceType.onlineOnly`, `StoreSpecialty.kBeautyAndSkincare`
- **Engine:** Nuxt 3 Server-Side Rendered (SSR) HTML with embedded Schema.org JSON-LD
- **Endpoint:** `https://niceonesa.com/search?q={query}`
- **Features:** Embeds 30 products in `<script type="application/ld+json">` with `@type: ItemList`, `offers.price` in SAR, `inStock` availability, SKU, and CloudFront images.
- **Sample Pricing:** COSRX Snail 96 Mucin Power Essence (54.00 SAR), COSRX All-in-One Cream (49.00 SAR).

### 6.4 iHerb KSA (`sa.iherb.com`)
- **Store ID:** `iherb`
- **Presence & Specialty:** `StorePresenceType.onlineOnly`, `StoreSpecialty.supplements`
- **Engine:** Cloudflare Turnstile Protected Storefront
- **Endpoint:** `https://sa.iherb.com/search?kw={query}`
- **Behavior:** Automated headless HTTP requests trigger HTTP 403 Forbidden with `cf-mitigated: challenge`. The adapter raises `CloudflareChallengeException` so the lane prompts for clearance via `CookieBridgeService` while other stores continue streaming. When clearance cookies are supplied, it parses catalog suggestions.

### 6.5 Seoul Eun (`seouleun-sa.com`)
- **Store ID:** `seouleun`
- **Presence & Specialty:** `StorePresenceType.onlineOnly`, `StoreSpecialty.kBeautyAndSkincare`
- **Engine:** Salla Twilight Storefront
- **Endpoint:** `https://seouleun-sa.com/search?q={query}`
- **Features:** Extracts JSON-LD Schema.org graphs and Twilight hydration payloads for K-Beauty cosmetics.

### 6.6 Global Barcode Fallback (Stage 1.5)
- **OpenBeautyFacts v2:** `https://world.openbeautyfacts.org/api/v2/product/{gtin}.json`
- **OpenFoodFacts v2:** `https://world.openfoodfacts.org/api/v2/product/{gtin}.json`
- **Behavior:** Resolves cosmetic and supplement barcodes when no Saudi pharmacy matches the GTIN directly in Stage 1, extracting canonical title and quantity for Stage 3 keyword cascade across all stores. Requires `User-Agent: PharmacyAggregatorApp/2.0` to avoid 503 HTTP throttling.
