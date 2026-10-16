# Improvement Areas & Technical Debt

## 1. Technical Debt & Gaps
- **Store Lane Auto-Retry**: Currently, when a store returns an HTTP timeout or transient error, user must pull-to-refresh the entire search. Implementing individual per-lane retry buttons would improve UX.
- **Dynamic Store Logos**: Currently, store icons rely on local material icons and typography. Adding vector assets (`svg`) for each pharmacy brand will provide a more polished appearance.
- **Algolia / Hybris Session Warmup**: Pre-warming session cookies for Hybris-backed stores (`al_dawaa`, `boots`) can reduce first-search latency by 200-400ms.

## 2. Priority Scoring
- **Per-Lane Retry**: Technical Debt: 4 | Business Impact: 6 | Effort: 3 | **Score: 8.7** (High Priority)
- **Vector Brand Logos**: Technical Debt: 2 | Business Impact: 5 | Effort: 2 | **Score: 9.5** (Quick Win)
- **Cookie Warmup Service**: Technical Debt: 5 | Business Impact: 6 | Effort: 5 | **Score: 5.6** (Medium Priority)
