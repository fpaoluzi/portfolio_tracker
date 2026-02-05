---
phase: 01-fix-composition-percentages
plan: 02
subsystem: ui
tags: [react, typescript, portfolio-analysis, composition, api-client]

# Dependency graph
requires:
  - phase: 01-fix-composition-percentages
    provides: Backend weighted composition calculation endpoints (plan 01)
provides:
  - Frontend now passes selectedPortfolioId to composition API calls
  - Asset selection UX with Select All/Deselect All buttons
  - Portfolio weight percentages displayed in asset selection modal
  - Zero-value assets automatically filtered from selection
  - Portfolio-change reset behavior
affects: [portfolio-analysis, composition-ui, multi-asset-analysis]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Portfolio context threading - selectedPortfolioId passed to all composition API calls"
    - "Portfolio-change reset pattern - clearing dependent state on portfolio switch"
    - "Zero-value asset filtering - excluding assets with no current position value"

key-files:
  created: []
  modified:
    - frontend/src/components/features/analysis/PortfolioAnalysis.tsx

key-decisions:
  - "Pass selectedPortfolioId to both getMultipleAssetsComposition() and getMultipleAssetsRiskStats() to enable backend weighted calculations"
  - "Add selectedPortfolioId to useEffect dependency array to trigger re-fetch when portfolio changes"
  - "Filter zero-value assets from available selection using positions data"
  - "Display portfolio weight percentages in modal using Math.round() for integer percentages"

patterns-established:
  - "Portfolio context pattern: Always pass portfolioId to composition endpoints to get weighted calculations instead of simple averages"
  - "Asset weight calculation: Use analyticsApi.getPositions() to calculate portfolio-weighted percentages"
  - "No-portfolio-selected guard: Early return with informative UI when no portfolio context available"

# Metrics
duration: 3min
completed: 2026-02-05
---

# Phase 01 Plan 02: Frontend Composition Fix Summary

**PortfolioAnalysis component now passes selectedPortfolioId to composition API calls, enabling weighted calculations instead of simple averages, with improved asset selection UX**

## Performance

- **Duration:** 3 min
- **Started:** 2026-02-05T16:07:32Z
- **Completed:** 2026-02-05T16:10:10Z
- **Tasks:** 2
- **Files modified:** 1

## Accomplishments
- Fixed THE bug: selectedPortfolioId now passed to getMultipleAssetsComposition() and getMultipleAssetsRiskStats()
- Portfolio context threading ensures backend uses weighted calculation branch
- Portfolio-change reset clears asset selection and composition data
- Select All/Deselect All buttons improve asset selection workflow
- Portfolio weight percentages displayed next to each asset in modal (e.g., "VOO 65%")
- Zero-value assets automatically excluded from available selection

## Task Commits

Each task was committed atomically:

1. **Task 1: Fix portfolioId parameter passing and add portfolio-change reset** - `4f75e38` (fix)
   - Pass selectedPortfolioId to API calls (THE BUG FIX)
   - Add selectedPortfolioId to useEffect dependency array
   - Add portfolio validation guard clause
   - Add portfolio-change reset effect
   - Remove debug logging
   - Add no-portfolio-selected UI prompt

2. **Task 2: Add Select All/Deselect All buttons and asset weight display** - `e937f5a` (feat)
   - Add Select All/Deselect All buttons in modal
   - Show portfolio weight percentage next to asset names
   - Fetch positions to calculate asset weights
   - Filter zero-value assets from available list
   - Reset assetWeights when portfolio changes

## Files Created/Modified
- `frontend/src/components/features/analysis/PortfolioAnalysis.tsx` - Fixed portfolio context threading, added UX improvements

## Decisions Made

**1. Pass portfolioId with non-null assertion**
- Used `selectedPortfolioId!` in API calls since guard clause ensures it exists at that point
- Safe approach: guard clause returns early if no portfolio selected

**2. Calculate integer percentages using Math.round()**
- Context specified "Nessun decimale nelle percentuali"
- Used Math.round() on weight calculation: `Math.round((value / totalValue) * 100)`
- Produces clean percentages like "65%" instead of "65.23%"

**3. Filter zero-value assets at fetch time**
- Exclude assets with no position or current_value = 0 from available selection
- Prevents users from selecting assets that aren't actually in their portfolio
- Cleaner UX than showing zero-weight assets in modal

**4. Handle current_value as number | string**
- Position type defines current_value as `number | string`
- Used type guard: `typeof p.current_value === 'number' ? p.current_value : parseFloat(p.current_value || '0')`
- Handles both API response formats safely

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered

**TypeScript error on current_value parsing**
- **Issue:** Position.current_value is typed as `number | string`, initial code only handled string case
- **Resolution:** Added type guard to handle both number and string values
- **Verification:** TypeScript compilation passes (only unrelated errors in INTEGRATION_EXAMPLES.tsx remain)

## Next Phase Readiness

Frontend fix complete. With backend fix from plan 01 (if completed), composition analysis will show correct weighted percentages instead of simple averages.

**Verification steps after backend deployment:**
1. Select portfolio in PortfolioAnalysis view
2. Open asset selection modal - should see weight percentages next to asset names
3. Select multiple assets - composition should reflect portfolio-weighted percentages
4. Change portfolio - asset selection should reset, new portfolio composition should load
5. Percentages should sum to 100% (after Altri normalization)

**Known limitation:** Backend plan 01 must also be deployed for weighted calculations to work. Frontend now sends portfolioId, but backend needs to use it.

---
*Phase: 01-fix-composition-percentages*
*Completed: 2026-02-05*
