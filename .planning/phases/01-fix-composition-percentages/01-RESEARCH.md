# Phase 1: Fix Composition Percentages - Research

**Researched:** 2026-02-05
**Domain:** React/TypeScript frontend state management, Express.js backend query parameter handling, PostgreSQL weighted aggregation
**Confidence:** HIGH

## Summary

This phase fixes a data flow bug where portfolio composition analysis shows incorrect allocation percentages when multiple assets are selected. The root cause is that `PortfolioAnalysis.tsx` calls `getMultipleAssetsComposition(assetIds)` without passing the `portfolioId`, causing all 6 backend composition controllers to use simple arithmetic average (`AVG`) instead of portfolio-value-weighted averages (`SUM(asset_weight * weight_percent)`).

The fix is straightforward: ensure `portfolioId` flows through the entire call chain (component → API layer → backend controllers). The correct weighted SQL already exists in each controller's `if (portfolioId)` branch. This is primarily a parameter-passing fix, not a logic rewrite.

The codebase uses React 19.2.0 with TypeScript 5.9.3, Next.js 16.0.1 for the frontend, and Express.js 4.18.2 with PostgreSQL for the backend. The architecture follows a modular MVC pattern with clear separation between routes, controllers, services, and database layers.

**Primary recommendation:** Pass `selectedPortfolioId` from `PortfolioAnalysis.tsx` to `getMultipleAssetsComposition()` API call, verify it propagates to all 6 backend endpoints, and add portfolio selection validation at the component level.

## Standard Stack

The existing stack for this phase (no new libraries needed):

### Core
| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| React | 19.2.0 | Frontend UI framework | Latest stable, component-based architecture |
| TypeScript | 5.9.3 | Type-safe JavaScript | Catch parameter-passing errors at compile time |
| Next.js | 16.0.1 | React meta-framework | Server-side rendering, routing, and optimization |
| Express.js | 4.18.2 | Backend REST API | Industry standard Node.js web framework |
| pg | 8.11.3 | PostgreSQL client | Official PostgreSQL driver with connection pooling |

### Supporting
| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| lucide-react | 0.552.0 | Icon library | UI feedback (loading spinners, error icons) |
| recharts | 3.3.0 | Charting library | Visualizing composition percentages |
| Decimal.js | 10.6.0 | High-precision math | Financial calculations (already used in backend) |

### Alternatives Considered
| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| Manual validation | express-validator | Unnecessary dependency for simple parameter checks |
| Custom normalization | Built-in Math.round() | Decimal.js already available for precision |
| Context API | Redux/Zustand | Overkill for single parameter passing |

**Installation:**
No new packages required - all dependencies already present in package.json files.

## Architecture Patterns

### Recommended Project Structure
The existing codebase follows this pattern (already in place):

```
frontend/src/
├── components/
│   └── features/
│       └── analysis/
│           ├── PortfolioAnalysis.tsx    # Main component (line 76 needs fix)
│           ├── equity/                  # Equity-specific analysis views
│           └── bond/                    # Bond-specific analysis views
├── lib/
│   └── api/
│       ├── etfComposition.ts           # API client (lines 207-234 - already correct)
│       └── client.ts                    # Base fetch wrapper

backend/src/
├── routes/
│   └── compositionAnalysisRoutes.js    # Route definitions
├── controllers/
│   └── composition/                     # 6 controllers to verify
│       ├── allocationAnalysis.js       # Lines 206-311 (weighted vs AVG)
│       ├── sectorAnalysis.js
│       ├── geographicAnalysis.js
│       ├── holdingsAnalysis.js
│       ├── bondRatingAnalysis.js
│       └── bondMaturityAnalysis.js
└── services/
    └── compositionCalculator.js        # Look-through formula documentation (lines 1-29)
```

### Pattern 1: Context Parameter Threading
**What:** Pass contextual identifiers (portfolioId) through the entire call chain to ensure backend logic branches correctly.

**When to use:** When API endpoints have conditional logic that depends on context (portfolio-weighted vs simple average).

**Example:**
```typescript
// Source: Existing codebase pattern at frontend/src/lib/api/etfComposition.ts:207-234
export async function getMultipleAssetsComposition(
  assetIds: string[],
  portfolioId?: string,  // ← Optional parameter already exists
  expand: boolean = false
): Promise<PortfolioComposition> {
  const assetIdsParam = assetIds.join(',');
  const portfolioParam = portfolioId ? `&portfolioId=${portfolioId}` : '';  // ← Conditional inclusion
  const expandParam = expand ? `&expand=true` : '';

  // All 6 endpoints receive portfolioParam
  const [holdingsRes, sectorsRes, regionsRes, allocationRes, bondRatingsRes, bondMaturityRes] = await Promise.all([
    apiClient.get<{ holdings?: AggregatedHolding[] }>(`/composition/holdings/assets/multiple?assetIds=${assetIdsParam}${portfolioParam}${expandParam}`),
    // ... 5 more endpoints
  ]);

  return { holdings, sectors, regions, allocation, bondRatings, bondMaturity };
}
```

**Fix location:**
```typescript
// Current (line 76 in PortfolioAnalysis.tsx):
const comp = await getMultipleAssetsComposition(assetIds);

// Fixed:
const comp = await getMultipleAssetsComposition(assetIds, selectedPortfolioId);
```

### Pattern 2: Backend Conditional Query Logic
**What:** Use `if (portfolioId)` branches to select weighted vs simple average queries.

**When to use:** When the same endpoint serves different contexts (portfolio analysis vs asset comparison).

**Example:**
```javascript
// Source: Existing backend pattern at backend/src/controllers/composition/allocationAnalysis.js:206-311
async function getAllocationByMultipleAssets(req, res) {
  const { assetIds, portfolioId, expand = 'false', limit = 15 } = req.query;

  if (!assetIds) {
    return res.status(400).json({ error: 'assetIds query parameter richiesto' });
  }

  const ids = Array.isArray(assetIds) ? assetIds : assetIds.split(',');

  if (portfolioId) {
    // ✅ CORRECT: Portfolio-weighted calculation
    query = `
      WITH asset_weights AS (
        SELECT
          asset_id,
          current_value / SUM(current_value) OVER() as asset_weight
        FROM v_current_positions
        WHERE portfolio_id = $2 AND asset_id = ANY($1)
      )
      SELECT
        a.allocation_type,
        SUM(aw.asset_weight * a.weight_percent) as real_weight  -- Weighted sum
      FROM etf_asset_allocation a
      JOIN asset_weights aw ON a.asset_id = aw.asset_id
      WHERE a.allocation_type NOT IN ('Altri', 'Other', 'Others', 'Altro', 'N/A')
      GROUP BY a.allocation_type
      ORDER BY real_weight DESC
    `;
    params = [ids, portfolioId];
  } else {
    // ⚠️ FALLBACK: Simple arithmetic average (should never be reached from UI)
    query = `
      SELECT
        a.allocation_type,
        AVG(a.weight_percent) as real_weight  -- Simple average
      FROM etf_asset_allocation a
      WHERE a.asset_id = ANY($1)
      GROUP BY a.allocation_type
      ORDER BY real_weight DESC
    `;
    params = [ids];
  }

  const result = await pool.query(query, params);
  // ... response formatting
}
```

### Pattern 3: useEffect Dependency Management
**What:** Include all reactive values used in useEffect as dependencies to trigger re-fetches when context changes.

**When to use:** When data fetching depends on prop or state values that can change over time.

**Example:**
```typescript
// Source: Existing pattern at PortfolioAnalysis.tsx:61-104
useEffect(() => {
  const fetchComposition = async () => {
    if (selectedAssets.length === 0) {
      setComposition(null);
      return;
    }

    setLoading(true);
    try {
      const assetIds = selectedAssets.map(a => a.asset_id);
      const comp = await getMultipleAssetsComposition(assetIds, selectedPortfolioId);  // ← Add selectedPortfolioId
      setComposition(comp);
    } catch (err: any) {
      setError(err.message);
    } finally {
      setLoading(false);
    }
  };

  fetchComposition();
}, [selectedAssets]);  // ← Should include selectedPortfolioId to re-fetch when portfolio changes
```

### Pattern 4: Portfolio Selection Reset on Change
**What:** Reset asset selection when portfolio changes to show total portfolio composition by default.

**When to use:** When changing context (portfolio) should reset drill-down state (selected assets).

**Example:**
```typescript
// New useEffect to add to PortfolioAnalysis.tsx
useEffect(() => {
  // Reset asset selection when portfolio changes
  setSelectedAssets([]);
  setComposition(null);
  setRiskStats(null);
}, [selectedPortfolioId]);
```

### Anti-Patterns to Avoid

- **Passing undefined context parameters:** Don't call `getMultipleAssetsComposition(assetIds)` without `portfolioId` from UI - this triggers the fallback AVG branch which produces incorrect results.

- **Missing dependency array entries:** Don't omit `selectedPortfolioId` from useEffect dependencies when it's used in the effect - this causes stale data when portfolio changes.

- **Client-side percentage recalculation:** Don't try to normalize percentages in the frontend - the backend already handles normalization (lines 40-48, 110-118, 185-193, 292-300 in allocationAnalysis.js).

- **Hardcoding query parameter order:** Don't assume parameter order in URL strings - use proper query string construction with conditional inclusion (`portfolioParam` pattern).

## Don't Hand-Roll

Problems that look simple but have existing solutions:

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Percentage normalization | Custom rounding logic | Backend normalization | Already implemented in all 6 controllers (lines 292-300 pattern), handles edge cases like "Altri" category aggregation |
| Weighted average calculation | Frontend aggregation | PostgreSQL window functions | Correct formula already exists using `v_current_positions` materialized view with `SUM(asset_weight * weight_percent)` |
| Asset filtering by portfolio | Client-side filter | Database join on v_current_positions | Backend has correct join logic, includes zero-value exclusion and handles non-ETF assets |
| Loading state during refetch | Custom spinner component | Existing loading state | Component already has `loading` state and `Loader2` from lucide-react (lines 33, 203-206) |
| Error handling | Custom error UI | Existing error state | Component already has error state and error display UI (lines 34, 209-215) |

**Key insight:** The weighted calculation logic is database-driven, not application-driven. The correct formula is in SQL using window functions (`current_value / SUM(current_value) OVER()`), which cannot be replicated client-side without fetching all position data. Always defer to backend calculations.

## Common Pitfalls

### Pitfall 1: Forgetting Portfolio Context in Related Functions
**What goes wrong:** After fixing `getMultipleAssetsComposition()`, forgot to pass `portfolioId` to `getMultipleAssetsRiskStats()` on the same line.

**Why it happens:** The component calls two related API functions back-to-back (lines 76 and 80), but developers focus on fixing only the first one.

**How to avoid:** Search for all API calls in the same useEffect block and verify each receives required context parameters.

**Warning signs:** Risk stats show different asset weights than composition charts; inconsistent percentage totals between different analysis sections.

**Code location:**
```typescript
// Lines 76-81 in PortfolioAnalysis.tsx
const comp = await getMultipleAssetsComposition(assetIds, selectedPortfolioId);  // ← Fixed
setComposition(comp);

const stats = await getMultipleAssetsRiskStats(assetIds, selectedPortfolioId);  // ← Also needs fix
setRiskStats(stats);
```

### Pitfall 2: Stale Data After Portfolio Change
**What goes wrong:** User switches portfolio selector, but composition charts show old portfolio's data until user manually clicks asset selection.

**Why it happens:** `useEffect` dependency array doesn't include `selectedPortfolioId`, so effect doesn't re-run when portfolio changes.

**How to avoid:** Include all reactive values (props, state) used inside useEffect in the dependency array. React DevTools will warn about missing dependencies.

**Warning signs:** Charts don't update immediately after portfolio selection; need to deselect/reselect assets to see new portfolio data.

**Code fix:**
```typescript
// Current (line 104):
}, [selectedAssets]);

// Fixed:
}, [selectedAssets, selectedPortfolioId]);
```

### Pitfall 3: Portfolio Not Selected State
**What goes wrong:** Component tries to fetch composition when `selectedPortfolioId` is `null`, causing backend to use AVG fallback or fail.

**Why it happens:** User hasn't selected a portfolio yet, or portfolio selector cleared the selection.

**How to avoid:** Add early return guard in useEffect when `selectedPortfolioId` is null/undefined. Show prompt UI instead of fetching data.

**Warning signs:** API calls return empty data or unexpected averages; no visual indication that portfolio selection is required.

**Code fix:**
```typescript
useEffect(() => {
  const fetchComposition = async () => {
    // Guard clause for missing portfolio context
    if (!selectedPortfolioId) {
      setComposition(null);
      setError('Seleziona un portafoglio per visualizzare l\'analisi');
      return;
    }

    if (selectedAssets.length === 0) {
      setComposition(null);
      return;
    }

    // ... rest of fetch logic
  };

  fetchComposition();
}, [selectedAssets, selectedPortfolioId]);
```

### Pitfall 4: Backend Query Parameter Type Coercion
**What goes wrong:** Backend receives `portfolioId` as string from query parameter but database expects UUID or specific type, causing query to fail silently or return empty results.

**Why it happens:** Express query parameters are always strings; pg driver may not auto-coerce to expected type.

**How to avoid:** Backend already handles this correctly (uses `$2` parameterized query), but verify the parameter isn't malformed. TypeScript types on frontend ensure string format.

**Warning signs:** Backend logs "Error in getAllocationByMultipleAssets" but no SQL error; empty result set despite valid data.

**Verification:**
```javascript
// Already correct in controllers (line 239):
params = [ids, portfolioId];  // portfolioId passed directly to parameterized query

// PostgreSQL handles string-to-UUID coercion automatically when column type is UUID
```

### Pitfall 5: Percentage Normalization Edge Cases
**What goes wrong:** After weighted calculation, percentages don't sum to exactly 100% due to rounding or missing data.

**Why it happens:** Some assets lack composition data, or small percentages get truncated, or "Altri" category miscalculated.

**How to avoid:** Backend already handles this (lines 292-300 pattern in all controllers) - calculates "Altri" as difference between total and shown. Don't add client-side normalization.

**Warning signs:** Total percentage shown as 97.8% or 102.1%; "Altri" category shows negative or very large percentage.

**Code verification:**
```javascript
// Existing normalization logic (lines 292-300 in allocationAnalysis.js):
const shownTotal = allocation.reduce((sum, a) => sum + (a.weighted_percent / 100), 0);
const othersPercent = Math.max(0, (allAllocationTotal - shownTotal) * 100);

if (othersPercent > 0.01) {
  allocation.push({
    allocation_type: 'Altri',
    weighted_percent: parseFloat(othersPercent.toFixed(2))
  });
}
```

## Code Examples

Verified patterns from existing codebase:

### Portfolio-Weighted Aggregation (SQL)
```sql
-- Source: backend/src/controllers/composition/allocationAnalysis.js:220-238
-- Formula: SUM(asset_weight_in_portfolio × asset_composition_weight)
WITH asset_weights AS (
  SELECT
    asset_id,
    current_value / SUM(current_value) OVER() as asset_weight
  FROM v_current_positions
  WHERE portfolio_id = $2 AND asset_id = ANY($1)
)
SELECT
  a.allocation_type,
  SUM(aw.asset_weight * a.weight_percent) as real_weight
FROM etf_asset_allocation a
JOIN asset_weights aw ON a.asset_id = aw.asset_id
WHERE a.allocation_type NOT IN ('Altri', 'Other', 'Others', 'Altro', 'N/A')
GROUP BY a.allocation_type
ORDER BY real_weight DESC
```

**Key insight:** Window function `SUM(current_value) OVER()` calculates total portfolio value within the partition, enabling weight calculation in a single query without subqueries.

### API Client Optional Parameter Pattern
```typescript
// Source: frontend/src/lib/api/etfComposition.ts:207-234
export async function getMultipleAssetsComposition(
  assetIds: string[],
  portfolioId?: string,  // Optional parameter
  expand: boolean = false
): Promise<PortfolioComposition> {
  const assetIdsParam = assetIds.join(',');
  const portfolioParam = portfolioId ? `&portfolioId=${portfolioId}` : '';  // Conditional inclusion
  const expandParam = expand ? `&expand=true` : '';

  // Parallel fetch of all 6 composition endpoints
  const [holdingsRes, sectorsRes, regionsRes, allocationRes, bondRatingsRes, bondMaturityRes] = await Promise.all([
    apiClient.get<{ holdings?: AggregatedHolding[] }>(
      `/composition/holdings/assets/multiple?assetIds=${assetIdsParam}${portfolioParam}${expandParam}`
    ).catch(() => ({ holdings: [] })),
    // ... 5 more endpoints with same parameter pattern
  ]);

  return {
    holdings: holdingsRes.holdings || [],
    sectors: sectorsRes.sectors || [],
    regions: regionsRes.regions || [],
    allocation: allocationRes.allocation || [],
    bondRatings: bondRatingsRes.bondRatings || [],
    bondMaturity: bondMaturityRes.bondMaturity || [],
  };
}
```

**Key insight:** The API layer is already correct - it accepts `portfolioId` and conditionally includes it in query strings. The bug is that the component doesn't pass this parameter.

### Component Asset Selection Reset on Portfolio Change
```typescript
// New pattern to add to PortfolioAnalysis.tsx
// Place after existing useEffect blocks (after line 58)
useEffect(() => {
  // Reset selection when portfolio changes
  setSelectedAssets([]);
  setComposition(null);
  setRiskStats(null);
  setError(null);
}, [selectedPortfolioId]);
```

**Rationale:** When portfolio context changes, previous asset selection is invalid - assets may not exist in new portfolio or have different weights. Reset to show total portfolio composition by default.

### Loading State with User Feedback
```typescript
// Existing pattern at PortfolioAnalysis.tsx:202-207 (reference, already correct)
{loading && (
  <div className="flex items-center justify-center py-12">
    <Loader2 className="w-8 h-8 text-blue-400 animate-spin" />
    <span className="ml-3 text-gray-300">Caricamento analisi...</span>
  </div>
)}
```

**Immediate recalculation:** Component already re-fetches on every `selectedAssets` change (line 104), providing "ricalcolo immediato" behavior. No additional loading state needed.

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| Simple AVG of asset allocations | Portfolio-value-weighted SUM | Implemented in backend refactor (commit 2ba700e) | Accurate representation of actual portfolio exposure |
| Client-side composition calculation | Database-driven with materialized views | Implemented with v_current_positions view | Eliminates race conditions and stale data |
| Single monolithic composition endpoint | 6 modular composition endpoints | Recent refactor (architecture shows new structure) | Parallel fetching, better error isolation |
| Manual percentage normalization | Backend "Altri" calculation | Implemented in all controllers | Consistent 100% totals with proper rounding |

**Deprecated/outdated:**
- **Old composition endpoint (`/etf-composition/portfolio/:id`)**: Replaced by modular `/composition/{type}/...` endpoints. Still exists but not used by new components.
- **Client-side weight calculation**: Legacy App.js may have done this; new components rely entirely on backend calculations.

## Open Questions

Things that couldn't be fully resolved:

1. **Visual Feedback - Asset Weight Display**
   - What we know: Context specifies "Mostrare il peso percentuale di ogni asset selezionato nella lista asset (es. 'VOO — 65%')"
   - What's unclear: Current component doesn't show individual asset weights in the selection modal (lines 230-270). Needs data source.
   - Recommendation: Fetch asset weights from `v_current_positions` view when portfolio selected. Add to `availableAssets` state with weight field. Display in modal at line 256 after asset name.

2. **Select All / Deselect All Buttons**
   - What we know: Context specifies "Bottoni 'Seleziona tutto' / 'Deseleziona tutto' presenti"
   - What's unclear: Current modal (lines 230-270) doesn't have these buttons
   - Recommendation: Add button group above asset list in modal, before line 240. Use `setSelectedAssets(availableAssets)` for select all, `setSelectedAssets([])` for deselect all.

3. **No Portfolio Selected Prompt**
   - What we know: Context specifies "If no portfolio is selected, prompt user to select one before showing multi-asset composition"
   - What's unclear: Component receives `selectedPortfolioId` as prop but doesn't validate it
   - Recommendation: Add guard clause at top of component render (line 137) to show prompt UI when `!selectedPortfolioId`. Prevent asset selection modal from opening.

4. **Zero-Value Asset Exclusion**
   - What we know: Context specifies "Asset con valore corrente zero → esclusi automaticamente dalla lista di selezione e dal calcolo"
   - What's unclear: Current `availableAssets` fetch (line 49-50) filters by `canHaveComposition` but doesn't check position value
   - Recommendation: Join with `v_current_positions` when fetching available assets, filter `WHERE current_value > 0 AND portfolio_id = selectedPortfolioId`. This also solves the portfolio-asset association issue.

5. **Non-ETF Asset Handling**
   - What we know: Context specifies "Asset non-ETF (azioni singole, bond) → trattati come 100% di sé stessi (es. Apple = 100% Technology, 100% USA)"
   - What's unclear: Backend controllers only query `etf_asset_allocation` table. Single stocks may not have composition data.
   - Recommendation: Backend query should LEFT JOIN with asset master data to include stocks. For assets without composition data, backend should synthesize 100% allocation based on asset sector/country fields. This may require controller modification or new service function.

## Sources

### Primary (HIGH confidence)
- Codebase files (verified by direct inspection):
  - `frontend/src/components/features/analysis/PortfolioAnalysis.tsx` - Component to modify
  - `frontend/src/lib/api/etfComposition.ts` - API layer (already correct)
  - `backend/src/controllers/composition/allocationAnalysis.js` - Pattern reference for all 6 controllers
  - `backend/src/services/compositionCalculator.js` - Look-through formula documentation
  - `backend/package.json` - Express.js 4.18.2, pg 8.11.3
  - `frontend/package.json` - React 19.2.0, Next.js 16.0.1, TypeScript 5.9.3
- Project documentation:
  - `.planning/codebase/STACK.md` - Technology stack analysis
  - `.planning/codebase/ARCHITECTURE.md` - Architecture patterns and data flow
  - `.planning/phases/01-fix-composition-percentages/01-CONTEXT.md` - User decisions and requirements

### Secondary (MEDIUM confidence)
- [React useEffect – Official React docs](https://react.dev/reference/react/useEffect) - Dependency array best practices
- [Removing Effect Dependencies – React](https://react.dev/learn/removing-effect-dependencies) - When to include values in dependency arrays
- [Best Practices for useEffect Dependency Arrays](https://egebilge.medium.com/best-practices-for-useeffect-dependency-arrays-in-react-fcb53ef55495) - Common pitfalls and solutions
- [Validate request body and parameter in Node.js Express](https://blog.tericcabrel.com/validate-request-parameter-nodejs-yup/) - Query parameter validation patterns
- [How to handle query parameters in Node.js Express](https://apidog.com/blog/nodejs-express-get-query-params/) - Missing parameter handling

### Tertiary (LOW confidence)
- [React with TypeScript Best Practices](https://prakashinfotech.com/react-with-typescript-best-practices) - General TypeScript patterns (not specific to this use case)
- [Express.js query parameter gotchas](https://evanhahn.com/gotchas-with-express-query-parsing-and-how-to-avoid-them/) - Edge cases (not directly applicable, backend already handles correctly)

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH - Verified by reading package.json files and existing code structure
- Architecture: HIGH - Direct inspection of all files mentioned in context, existing patterns are clear and consistent
- Pitfalls: HIGH - Based on actual code review and common React/Express patterns documented in official sources
- Open questions: MEDIUM - Identified gaps between context requirements and current implementation, recommendations based on standard patterns but need validation

**Research date:** 2026-02-05
**Valid until:** 2026-03-07 (30 days - stack is stable, React 19 and Express 4 are mature)
