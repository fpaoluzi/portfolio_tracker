# Portfolio Tracker - Roadmap

**Project:** Portfolio Tracker
**Created:** 2026-02-05
**Status:** Active

---

## Milestone 1: Bug Fix — Composition Analysis Percentages

**Goal:** Fix incorrect allocation percentages in portfolio composition analysis when multiple assets are selected.

### Phase 1: Fix Composition Percentages (Bug Fix)
**Status:** Planned
**Goal:** Correct the weighted percentage calculation across all 6 composition analysis controllers and ensure the frontend passes portfolio context for accurate weighted averages.
**Plans:** 2 plans

**Scope:**
- Frontend: pass `portfolioId` to composition API calls
- Backend: ensure all 6 multi-asset composition endpoints use portfolio-weighted calculations
- Affected controllers: holdings, sectors, geographic, allocation, bond-ratings, bond-maturity
- Verify percentages sum correctly and reflect actual portfolio weights

**Root cause:** `PortfolioAnalysis.tsx` calls `getMultipleAssetsComposition(assetIds)` without `portfolioId`, triggering the `AVG()` (simple mean) branch in all backend controllers instead of the weighted `SUM(asset_weight * weight_percent)` branch.

Plans:
- [ ] 01-01-PLAN.md — Verify and harden backend composition controllers' weighted calculation branches
- [ ] 01-02-PLAN.md — Fix frontend portfolioId parameter passing and add UX improvements

---
