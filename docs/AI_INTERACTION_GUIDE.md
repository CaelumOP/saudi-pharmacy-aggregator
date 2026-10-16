# AI Interaction Guide & Automation Rules

## 1. Operating Principles
- **No Silent Failures**: Every error must be explicitly typed, logged, or surfaced through structured UI state (`StoreLaneStatus.error` or `StoreLaneStatus.challengeRequired`).
- **Pre-Approved Safe Operations**: Read-only network recon, test execution, local formatting, and documentation synchronization are pre-approved.
- **Scope Boundary**: Strictly maintain files within project repository. Never leak API keys or sensitive user data.

## 2. Coding & Verification Standards
- Maintain 100% test pass rate across `test/`.
- Enforce `flutter analyze` with 0 issues.
- All public Dart declarations must include doc comments (`///`) explaining rationale.
- Follow the "Seen-to-Fail" testing rule: Before trusting a test assertion, verify that mutating production code turns it RED.

## 3. Localization & Formatting
- All user-facing strings must reside in `AppStrings` (`lib/l10n/app_strings.dart`) with dual Arabic and English definitions.
- Prices must be clearly labelled in Saudi Riyals (`SAR` / `ر.س`).
