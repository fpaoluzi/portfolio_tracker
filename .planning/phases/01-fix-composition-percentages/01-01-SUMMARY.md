---
phase: 01-fix-composition-percentages
plan: 01
subsystem: api
tags: [backend, composition-analysis, weighted-calculations, postgresql, express]

# Dependency graph
requires:
  - phase: initial-codebase-mapping
    provides: Full understanding of composition controller architecture and SQL patterns
provides:
  - Verified weighted calculation implementation in all 6 composition controllers
  - Verified riskStats controller supports portfolioId parameter
  - Documented route wiring for all 7 composition endpoints
  - Foundation for frontend fix (plan 02) that will pass portfolioId correctly
affects: [01-02-frontend-fix, composition-analysis, portfolio-weighting]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Weighted calculation pattern: CTE with v_current_positions for asset_weight, then SUM(asset_weight * weight_percent)"
    - "Fallback pattern: else branch with AVG() for safety when portfolioId not provided"

key-files:
  created: []
  modified:
    - backend/src/controllers/composition/allocationAnalysis.js
    - backend/src/controllers/composition/sectorAnalysis.js
    - backend/src/controllers/composition/geographicAnalysis.js
    - backend/src/controllers/composition/holdingsAnalysis.js
    - backend/src/controllers/composition/bondRatingAnalysis.js
    - backend/src/controllers/composition/bondMaturityAnalysis.js
    - backend/src/controllers/composition/riskStatsAnalysis.js

key-decisions:
  - "Verification-only approach: All controllers already had correct weighted implementation, no code changes needed"
  - "Route verification confirmed GET method with query params (portfolioId flows through req.query automatically)"

patterns-established:
  - "Documentation pattern: verification comments at function level to mark audited functions"
  - "Weighted CTE pattern: asset_weights AS (SELECT asset_id, current_value / SUM(current_value) OVER() as asset_weight FROM v_current_positions WHERE portfolio_id = $N AND asset_id = ANY($M))"

# Metrics
duration: 2min
completed: 2026-02-05
---

# Phase 01 Plan 01: Backend Composition Controllers Audit Summary

**Verified weighted calculation implementation across 7 composition controllers using v_current_positions for portfolio-value-weighted percentages**

## Performance

- **Duration:** 2 min
- **Started:** 2026-02-05T10:53:29Z
- **Completed:** 2026-02-05T10:55:07Z
- **Tasks:** 2
- **Files modified:** 7

## Accomplishments
- All 6 composition controllers verified to have correct weighted SQL in if(portfolioId) branches
- riskStatsAnalysis.js confirmed to support portfolioId parameter for weighted risk stats
- All 7 routes verified correctly registered and mapping to proper controller functions
- Added verification comments documenting audit completion date

## Task Commits

Each task was committed atomically:

1. **Task 1: Audit all 6 composition controllers for consistent weighted query pattern** - `885e409` (docs)

**Plan metadata:** (No metadata commit needed - verification-only phase)

## Files Created/Modified
- `backend/src/controllers/composition/allocationAnalysis.js` - Added verification comment; confirmed weighted CTE uses v_current_positions
- `backend/src/controllers/composition/sectorAnalysis.js` - Added verification comment; confirmed weighted CTE uses v_current_positions
- `backend/src/controllers/composition/geographicAnalysis.js` - Added verification comment; confirmed weighted CTE uses v_current_positions
- `backend/src/controllers/composition/holdingsAnalysis.js` - Added verification comment; confirmed weighted CTE uses v_current_positions
- `backend/src/controllers/composition/bondRatingAnalysis.js` - Added verification comment; confirmed weighted CTE uses v_current_positions
- `backend/src/controllers/composition/bondMaturityAnalysis.js` - Added verification comment; confirmed weighted CTE uses v_current_positions
- `backend/src/controllers/composition/riskStatsAnalysis.js` - Added verification comment; confirmed portfolioId parameter support

## Decisions Made

**Verification-only execution:**
- All controllers already implemented the correct weighted calculation pattern
- No code changes required beyond documentation comments
- Route wiring already correct with GET method and query parameter extraction

**Pattern confirmed across all controllers:**
```sql
WITH asset_weights AS (
  SELECT
    asset_id,
    current_value / SUM(current_value) OVER() as asset_weight
  FROM v_current_positions
  WHERE portfolio_id = $2 AND asset_id = ANY($1)
)
SELECT
  [category_field],
  SUM(aw.asset_weight * [table].weight_percent) as real_weight
FROM [composition_table]
JOIN asset_weights aw ON [table].asset_id = aw.asset_id
GROUP BY [category_field]
ORDER BY real_weight DESC
```

**Fallback pattern present in all controllers:**
- else branch uses AVG() when portfolioId not provided (safety fallback)
- This is correct behavior: without portfolio context, treat all assets equally

## Deviations from Plan

None - plan executed exactly as written. All controllers already had the correct implementation pattern documented in codebase research.

## Issues Encountered

None. All verification checks passed:
- portfolioId parameter extracted from req.query in all 7 controllers
- v_current_positions used in all weighted calculation branches
- asset_weight * weight_percent pattern present in all SQL queries
- All route registrations correct in compositionAnalysisRoutes.js
- All syntax checks passed
- No import/require errors

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness

**Ready for plan 02 (frontend fix):**
- Backend weighted calculation foundation verified and solid
- All 7 endpoints support portfolioId query parameter
- Pattern is consistent: pass portfolioId in URL query params, backend uses v_current_positions for weighting
- Frontend fix can proceed with confidence that backend will calculate correct percentages

**Key insight for frontend:**
The bug is NOT in the backend. The backend already has correct weighted calculations. The issue is that the frontend PortfolioAnalysis.tsx passes `assetIds` without `portfolioId` when in portfolio context, causing backend to fall back to AVG() instead of using weighted calculations.

**What plan 02 needs to do:**
- Pass `portfolioId` alongside `assetIds` in all composition API calls from PortfolioAnalysis.tsx
- Verify that all 6 composition tabs (allocation, sectors, geographic, holdings, bond ratings, bond maturity) receive the portfolioId parameter

**No blockers or concerns.**

---
*Phase: 01-fix-composition-percentages*
*Completed: 2026-02-05*
