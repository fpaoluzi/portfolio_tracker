# Phase 1: Fix Composition Percentages - Context

**Gathered:** 2026-02-05
**Status:** Ready for planning

<domain>
## Phase Boundary

Fix the bug where portfolio composition analysis shows incorrect allocation percentages when multiple assets are selected. The frontend does not pass `portfolioId` to the backend, causing all 6 composition controllers to use simple arithmetic average (`AVG`) instead of portfolio-value-weighted averages (`SUM(asset_weight * weight_percent)`).

This phase fixes the data flow chain: frontend component → API layer → backend controllers. No new features — pure bug fix.

</domain>

<decisions>
## Implementation Decisions

### Frontend Fix (PortfolioAnalysis.tsx)
- Pass the active `portfolioId` when calling `getMultipleAssetsComposition()`
- The portfolio context is needed for the backend to calculate weighted averages
- `portfolioId` should come from the current portfolio selection state

### Frontend API Layer (etfComposition.ts)
- `getMultipleAssetsComposition()` already accepts optional `portfolioId` parameter
- Ensure it's included in the query string of all 6 endpoint calls when present
- Verify the `portfolioParam` construction includes `&portfolioId=...`

### Backend Controllers (6 files, same pattern)
- All controllers already have the correct weighted query in the `if (portfolioId)` branch
- Verify the weighted branch works correctly for all edge cases:
  - Single asset selected (should return that asset's composition as-is)
  - All portfolio assets selected (should match total portfolio composition)
  - Assets with zero current value (handle division by zero)
- Affected controllers and functions:
  1. `holdingsAnalysis.js` → `getHoldingsByMultipleAssets()`
  2. `sectorAnalysis.js` → `getSectorsByMultipleAssets()`
  3. `geographicAnalysis.js` → `getGeographicByMultipleAssets()`
  4. `allocationAnalysis.js` → `getAllocationByMultipleAssets()`
  5. `bondRatingAnalysis.js` → `getBondRatingsByMultipleAssets()`
  6. `bondMaturityAnalysis.js` → `getBondMaturityByMultipleAssets()`

### Validation
- Percentages must sum to ~100% (within rounding tolerance)
- Weighted result must differ from simple average when assets have different portfolio values
- Selecting a single asset should return unchanged percentages

### Claude's Discretion
- Whether to also fix the `else` branch (no portfolioId) to use equal-weight explicitly or leave as-is
- Error handling approach for edge cases (zero values, missing data)
- Whether to add comments documenting the weighted formula

</decisions>

<specifics>
## Specific Ideas

- The correct weighted SQL already exists in each controller's `if (portfolioId)` branch — the fix is primarily ensuring this branch is always reached from the UI
- The formula uses `v_current_positions` materialized view for portfolio weights
- "Look-through" approach documented in `compositionCalculator.js` lines 1-29

</specifics>

<deferred>
## Deferred Ideas

None — discussion stayed within phase scope

</deferred>

---

*Phase: 01-fix-composition-percentages*
*Context gathered: 2026-02-05*
