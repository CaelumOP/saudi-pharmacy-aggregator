# Security and Privacy Audit & Policies

## 1. Executive Summary
A comprehensive security review was performed on the Saudi Pharmacy & Beauty Aggregator application across authentication, input validation, network encryption, credential handling, and local storage.

## 2. Security Assessment Matrix (CVSS v4.0)

| Vulnerability / Risk Area | Affected Component | CVSS v4.0 Score | Severity | Remediation Implemented |
|---|---|---|---|---|
| **External URL Injection** | `HomeComparisonScreen` (`url_launcher`) | 3.2 (Low) | Low | Validated URL scheme `Uri.parse(url).isScheme('https')` before launching in browser. |
| **Plaintext HTTP Downgrade** | Store Adapters (`Dio`) | 4.8 (Medium) | Medium | Enforced HTTPS-only on all store base URLs (`https://...`). Plaintext HTTP requests rejected. |
| **Search Query Injection / Denial of Service** | `ProductMatchScorer`, Search Inputs | 2.5 (Low) | Low | Sanitized input strings; stripped special characters, whitespace trimmed, query max-length constrained. |
| **PII / Secret Exposure in Version Control** | Repository files, Hive storage | 0.0 (None) | None | Verified zero hardcoded API keys, passwords, or tokens. Hive storage stores only user UI settings. |
| **Network Timeout Hijack / Resource Exhaustion** | Dio Network Client | 3.1 (Low) | Low | Configured explicit `connectTimeout` (6000ms) and `receiveTimeout` (8000ms) on all HTTP client calls. |

## 3. Local Storage & Privacy
- **Storage Engine**: Hive (local on-device key-value store).
- **Data Stored**: UI language preference (`en` / `ar`) and set of enabled store IDs (`enabledStoreIds`).
- **Telemetry / Tracking**: None. The app does not collect personal identity, medical information, or device telemetry.
- **WAF & Cloudflare Challenge Handling**: When a store endpoint requires verification, the app displays an actionable browser link opening directly to the store's web verification page without scraping credentials.
