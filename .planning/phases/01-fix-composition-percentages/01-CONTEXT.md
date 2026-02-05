# Phase 1: Fix Composition Percentages - Context

**Gathered:** 2026-02-05
**Status:** Ready for planning

<domain>
## Phase Boundary

Fix the bug where portfolio composition analysis shows incorrect allocation percentages when multiple assets are selected. The frontend does not pass `portfolioId` to the backend, causing all 6 composition controllers to use simple arithmetic average (`AVG`) instead of portfolio-value-weighted averages (`SUM(asset_weight * weight_percent)`).

This phase fixes the data flow chain: frontend component → API layer → backend controllers. Includes UX improvements for asset selection behavior and visual feedback.

</domain>

<decisions>
## Implementation Decisions

### Portfolio Context (Always Required)
- Analysis composition always runs within a portfolio context — `portfolioId` is always present
- User has multiple portfolios with a selector — the selected portfolio drives the analysis
- If no portfolio is selected, prompt user to select one before showing multi-asset composition
- Keep the `else` branch (no portfolioId) in backend controllers as a safety fallback, but it should never be reached from the UI

### Frontend Fix (PortfolioAnalysis.tsx)
- Pass the active `portfolioId` when calling `getMultipleAssetsComposition()`
- `portfolioId` comes from the current portfolio selection state (portfolio selector)

### Frontend API Layer (etfComposition.ts)
- `getMultipleAssetsComposition()` already accepts optional `portfolioId` parameter
- Ensure it's included in the query string of all 6 endpoint calls when present
- Verify the `portfolioParam` construction includes `&portfolioId=...`

### Backend Controllers (6 files, same pattern)
- All controllers already have the correct weighted query in the `if (portfolioId)` branch
- Verify the weighted branch works correctly for all edge cases
- Affected controllers and functions:
  1. `holdingsAnalysis.js` → `getHoldingsByMultipleAssets()`
  2. `sectorAnalysis.js` → `getSectorsByMultipleAssets()`
  3. `geographicAnalysis.js` → `getGeographicByMultipleAssets()`
  4. `allocationAnalysis.js` → `getAllocationByMultipleAssets()`
  5. `bondRatingAnalysis.js` → `getBondRatingsByMultipleAssets()`
  6. `bondMaturityAnalysis.js` → `getBondMaturityByMultipleAssets()`

### Asset Selection Behavior
- Ricalcolo immediato (live) — ogni click su un asset ricalcola subito i grafici
- Nessun asset selezionato → mostra composizione totale del portafoglio intero
- Bottoni "Seleziona tutto" / "Deseleziona tutto" presenti
- Cambio portafoglio dal selettore → reset a nessuna selezione (mostra composizione totale del nuovo portfolio)

### Visual Feedback
- Mostrare il peso percentuale di ogni asset selezionato nella lista asset (es. "VOO — 65%")
- Grafici mostrano solo totale aggregato (es. "Technology 45%"), NO breakdown per asset
- Percentuali normalizzate a 100% (riscalare proporzionalmente se la somma non è esatta)
- Nessun decimale nelle percentuali (45%, non 45.23%)

### Edge Cases
- Asset con valore corrente zero → esclusi automaticamente dalla lista di selezione e dal calcolo
- Asset senza dati di composizione nel DB → inclusi nel calcolo ma categorizzati come "Non classificato"
- Asset non-ETF (azioni singole, bond) → trattati come 100% di sé stessi (es. Apple = 100% Technology, 100% USA). Il peso nel portafoglio è il valore della posizione
- Voci piccole → mostrare tutto in elenco scrollabile, nessun raggruppamento automatico

### Validation
- Percentages must sum to 100% (normalize after weighted calculation)
- Weighted result must differ from simple average when assets have different portfolio values
- Selecting a single asset should return unchanged percentages

### Claude's Discretion
- Error handling approach for unexpected edge cases
- Whether to add comments documenting the weighted formula
- Loading state/spinner design during ricalcolo

</decisions>

<specifics>
## Specific Ideas

- The correct weighted SQL already exists in each controller's `if (portfolioId)` branch — the fix is primarily ensuring this branch is always reached from the UI
- The formula uses `v_current_positions` materialized view for portfolio weights
- "Look-through" approach documented in `compositionCalculator.js` lines 1-29
- Per azioni singole: mappare settore/paese dall'asset master data se disponibile, altrimenti "Non classificato"

</specifics>

<deferred>
## Deferred Ideas

None — discussion stayed within phase scope

</deferred>

---

*Phase: 01-fix-composition-percentages*
*Context gathered: 2026-02-05*
