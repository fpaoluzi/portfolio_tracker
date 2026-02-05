# Codebase Structure

**Analysis Date:** 2026-02-05

## Directory Layout

```
portfolio-tracker/
├── backend/
│   ├── src/
│   │   ├── config/                 # Server and database configuration
│   │   │   ├── database.js         # PostgreSQL pool setup
│   │   │   ├── server.js           # Server constants (PORT, etc.)
│   │   │   └── upload.js           # Multer middleware for Excel uploads
│   │   ├── controllers/            # Request handlers (MVC controllers)
│   │   │   ├── portfolioController.js
│   │   │   ├── assetController.js
│   │   │   ├── transactionController.js
│   │   │   ├── positionController.js
│   │   │   ├── importController.js  # Excel import logic
│   │   │   ├── performanceController.js
│   │   │   ├── priceUpdateController.js
│   │   │   ├── rebalancingController.js
│   │   │   ├── etfCompositionController.js
│   │   │   └── composition/         # Specialized composition analysis
│   │   │       ├── allocationAnalysis.js
│   │   │       ├── sectorAnalysis.js
│   │   │       ├── geographicAnalysis.js
│   │   │       ├── holdingsAnalysis.js
│   │   │       ├── bondMaturityAnalysis.js
│   │   │       ├── bondRatingAnalysis.js
│   │   │       ├── riskStatsAnalysis.js
│   │   │       └── geographicAnalysis_temp.js  # Experimental
│   │   ├── routes/                 # Express route definitions
│   │   │   ├── index.js            # Central route aggregator
│   │   │   ├── portfolioRoutes.js
│   │   │   ├── assetRoutes.js
│   │   │   ├── transactionRoutes.js
│   │   │   ├── positionRoutes.js   # (if exists)
│   │   │   ├── importRoutes.js
│   │   │   ├── performanceRoutes.js
│   │   │   ├── priceUpdateRoutes.js
│   │   │   ├── rebalancingRoutes.js
│   │   │   ├── etfCompositionRoutes.js
│   │   │   └── compositionAnalysisRoutes.js
│   │   ├── services/               # Business logic modules
│   │   │   ├── compositionCalculator.js
│   │   │   ├── rebalancingService.js
│   │   │   ├── justETFScraper.js
│   │   │   └── ollamaService.js
│   │   ├── utils/                  # Utility functions
│   │   │   ├── yahooFinance.js
│   │   │   ├── calculations.js
│   │   │   └── decimalCalculations.js
│   │   └── middleware/             # Custom middleware (empty, future use)
│   ├── scripts/                    # Standalone scripts
│   │   ├── create_view.js
│   │   ├── create_normalized_view.js
│   │   ├── create_aggregated_holdings_view.js
│   │   ├── create_all_normalized_views.js
│   │   ├── create_portfolio_wide_views.js
│   │   ├── check_transactions.js
│   │   ├── verify_positions.js
│   │   ├── get_portfolio_id.js
│   │   └── test_geographic_query.js
│   ├── migrations/                 # Database migrations
│   │   └── 001_positions_to_materialized_view.sql
│   ├── node_modules/               # Dependencies (generated)
│   ├── server.js                   # Main entry point
│   ├── finance_schema.sql          # Database schema definition
│   ├── import.js                   # Standalone import script
│   ├── package.json                # Backend dependencies
│   └── package-lock.json
│
├── frontend/
│   ├── src/
│   │   ├── app/                    # Next.js app directory
│   │   │   ├── page.tsx            # Root page (entry point)
│   │   │   └── layout.tsx          # Root layout wrapper
│   │   ├── components/
│   │   │   ├── ui/                 # Reusable UI primitives
│   │   │   │   ├── Button.tsx
│   │   │   │   ├── Input.tsx
│   │   │   │   ├── Select.tsx
│   │   │   │   ├── Textarea.tsx
│   │   │   │   ├── Modal.tsx
│   │   │   │   ├── Toast.tsx
│   │   │   │   └── index.ts        # Barrel export
│   │   │   └── features/           # Feature-specific components
│   │   │       ├── portfolio/
│   │   │       │   └── PortfolioFormModal.tsx
│   │   │       ├── asset/
│   │   │       │   ├── AssetFormModal.tsx
│   │   │       │   ├── AssetsList.tsx
│   │   │       │   └── ManualCompositionForm.tsx
│   │   │       ├── transaction/
│   │   │       │   ├── TransactionFormModal.tsx
│   │   │       │   └── ImportExcelModal.tsx
│   │   │       ├── performance/
│   │   │       │   └── MonthlyPerformanceChart.tsx
│   │   │       ├── allocation/
│   │   │       │   └── AllocationManager.tsx
│   │   │       ├── analysis/       # Portfolio composition analysis
│   │   │       │   ├── PortfolioAnalysis.tsx  # Main entry point
│   │   │       │   ├── equity/
│   │   │       │   │   ├── EquityAnalysis.tsx
│   │   │       │   │   ├── AllocationSection.tsx
│   │   │       │   │   ├── SectorsSection.tsx
│   │   │       │   │   ├── GeographySection.tsx
│   │   │       │   │   ├── HoldingsSection.tsx
│   │   │       │   │   └── RiskStatsSection.tsx
│   │   │       │   ├── bond/
│   │   │       │   │   ├── BondAnalysis.tsx
│   │   │       │   │   ├── BondAllocationSection.tsx
│   │   │       │   │   ├── BondSectorsSection.tsx
│   │   │       │   │   ├── BondGeographySection.tsx
│   │   │       │   │   ├── BondMaturitySection.tsx
│   │   │       │   │   ├── BondRatingsSection.tsx
│   │   │       │   │   └── BondRiskStatsSection.tsx
│   │   │       │   ├── shared/     # Reusable analysis components
│   │   │       │   │   ├── ChartContainer.tsx
│   │   │       │   │   ├── TableContainer.tsx
│   │   │       │   │   ├── LegendBox.tsx
│   │   │       │   │   └── PortfolioSummary.tsx
│   │   │       │   └── utils/
│   │   │       │       └── chartHelpers.tsx
│   │   │       └── rebalancing/
│   │   │           ├── RebalancingDashboard.tsx
│   │   │           ├── AllocationManager.tsx
│   │   │           ├── DriftAnalysis.tsx
│   │   │           ├── ManualSimulation.tsx
│   │   │           ├── SmartDeposit.tsx
│   │   │           └── INTEGRATION_EXAMPLES.tsx
│   │   ├── lib/                    # Shared utilities and APIs
│   │   │   ├── api/                # API client modules
│   │   │   │   ├── client.ts       # Base fetch wrapper
│   │   │   │   ├── portfolios.ts
│   │   │   │   ├── assets.ts
│   │   │   │   ├── transactions.ts
│   │   │   │   ├── analytics.ts
│   │   │   │   ├── etfComposition.ts
│   │   │   │   └── index.ts        # Public API export
│   │   │   ├── context/            # React context for state
│   │   │   │   └── ToastContext.tsx
│   │   │   ├── hooks/              # Custom React hooks
│   │   │   │   ├── usePortfolio.ts
│   │   │   │   └── useToast.ts
│   │   │   └── utils/              # Utility functions
│   │   │       ├── format.ts       # Currency, percent, date formatting
│   │   │       ├── colors.ts       # Chart color palette
│   │   │       └── assetHelpers.ts
│   │   ├── types/                  # TypeScript type definitions
│   │   │   └── index.ts            # Shared types (Portfolio, Asset, etc.)
│   │   ├── App.js                  # Legacy React monolith (still used)
│   │   ├── App.css
│   │   ├── App.test.js
│   │   ├── index.js                # Legacy entry point
│   │   ├── index.css
│   │   ├── setupTests.js
│   │   ├── reportWebVitals.js
│   │   └── logo.svg
│   ├── public/                     # Static assets
│   ├── .next/                      # Next.js build output (generated)
│   ├── node_modules/               # Dependencies (generated)
│   ├── .env.local                  # Local environment variables
│   ├── .gitignore
│   ├── next.config.js
│   ├── next-env.d.ts
│   ├── tsconfig.json               # TypeScript configuration
│   ├── tailwind.config.js          # Tailwind CSS configuration
│   ├── postcss.config.js           # PostCSS configuration
│   ├── KillFrontendProcess.bat     # Windows cleanup script
│   ├── package.json
│   ├── package-lock.json
│   └── README.md
│
├── .planning/                      # Planning and documentation
│   └── codebase/                   # Codebase analysis documents
│       └── (ARCHITECTURE.md, STRUCTURE.md, etc.)
├── .git/                           # Git repository
├── .claude/                        # Claude context
├── setup.bat / setup.sh            # Automated setup scripts
├── QUICK_START.md                  # Quick start guide
├── README.md                       # Main documentation
├── ISTRUZIONI_CALCOLO_ANALISI.md   # Analysis calculation instructions (Italian)
└── MOTORE_PROIEZIONE_PORTAFOGLIO.md # Portfolio projection engine doc (Italian)
```

## Directory Purposes

**backend/src/config/:**
- Purpose: Centralized configuration for database, server, and file upload
- Contains: Connection pools, middleware setup, environment variables
- Key files: `database.js` (PostgreSQL pool), `server.js` (PORT constant), `upload.js` (Multer)

**backend/src/controllers/:**
- Purpose: HTTP request handlers that execute business logic
- Contains: CRUD operations, analytics computation, data transformation
- Naming: One file per resource (`*Controller.js`)
- Pattern: Each export is an async function matching a route handler

**backend/src/controllers/composition/:**
- Purpose: Specialized analysis for portfolio composition breakdown
- Contains: Sector analysis, geographic allocation, holdings, bond metrics
- Used by: Composition analysis routes for detailed portfolio insights

**backend/src/routes/:**
- Purpose: HTTP route definitions mapping paths to controllers
- Contains: Express router definitions
- Key pattern: `router.get(path, controllerFunction)`
- Central hub: `index.js` registers all domain routes

**backend/src/services/:**
- Purpose: Business logic modules used by multiple controllers
- Contains: Complex calculations, external API integration, data processing
- Examples: Rebalancing algorithms, ETF composition scraping

**backend/src/utils/:**
- Purpose: Low-level helper functions and external service clients
- Contains: Financial calculations, API clients (Yahoo Finance)
- Stateless: No shared state, pure functions preferred

**backend/scripts/:**
- Purpose: Administrative and debugging scripts
- Contains: Database view creation, data verification, troubleshooting
- Run-when-needed: Not part of normal application flow

**backend/migrations/:**
- Purpose: Database schema changes over time
- Contains: SQL files for version control of schema
- Example: `001_positions_to_materialized_view.sql` documents refactor

**frontend/src/app/:**
- Purpose: Next.js App Router (React Server Components)
- Contains: Root layout and page; entry point for modern Next.js features
- Usage: `page.tsx` wraps legacy App.js or renders new components

**frontend/src/components/ui/:**
- Purpose: Reusable design system components (buttons, inputs, modals)
- Contains: Tailwind-styled components with minimal logic
- Exported via `index.ts` barrel file for convenient imports

**frontend/src/components/features/:**
- Purpose: Feature-specific UI modules organized by business domain
- Organization:
  - `portfolio/` - Portfolio CRUD operations
  - `asset/` - Asset management and composition forms
  - `transaction/` - Transaction entry and bulk import
  - `performance/` - Historical performance visualization
  - `allocation/` - Asset allocation management
  - `analysis/` - Complex portfolio analysis (equity, bond, shared utils)
  - `rebalancing/` - Rebalancing scenarios and drift analysis

**frontend/src/lib/api/:**
- Purpose: Type-safe HTTP client for backend API
- Contains: Endpoint wrappers using fetch API
- Pattern: Each module exports domain-specific functions (portfoliosApi, assetsApi, etc.)
- Base: `client.ts` provides typed `apiClient` with get/post/put/delete

**frontend/src/lib/context/:**
- Purpose: React Context for global state
- Current: ToastContext for user notifications
- Pattern: Provider wraps app, hook exposes useToastContext()

**frontend/src/lib/hooks/:**
- Purpose: Reusable React logic hooks
- Examples: usePortfolio (fetch and cache), useToast (notification)

**frontend/src/lib/utils/:**
- Purpose: Data formatting and helper utilities
- Examples: formatCurrency, getColorByIndex, assetTypeLabel

**frontend/src/types/:**
- Purpose: TypeScript type definitions shared across app
- Contains: Portfolio, Asset, Transaction, RiskStats, etc.
- Consumed by: All components, API modules

## Key File Locations

**Entry Points:**

| File | Purpose | Start Command |
|------|---------|---------------|
| `C:\workspaceai\portfolio-tracker\backend\server.js` | Backend API server | `npm start` or `npm run dev` |
| `C:\workspaceai\portfolio-tracker\frontend\src\app\page.tsx` | Frontend root (Next.js) | `npm run dev` |
| `C:\workspaceai\portfolio-tracker\frontend\src\App.js` | Legacy React app | `npm run legacy:start` |

**Configuration:**

| File | Purpose |
|------|---------|
| `C:\workspaceai\portfolio-tracker\backend\finance_schema.sql` | Database schema definition |
| `C:\workspaceai\portfolio-tracker\frontend\tsconfig.json` | TypeScript configuration |
| `C:\workspaceai\portfolio-tracker\frontend\tailwind.config.js` | Tailwind CSS configuration |
| `C:\workspaceai\portfolio-tracker\backend\src\config\database.js` | PostgreSQL pool setup |

**Core Logic:**

| File | Purpose |
|------|---------|
| `C:\workspaceai\portfolio-tracker\backend\src\controllers\portfolioController.js` | Portfolio CRUD |
| `C:\workspaceai\portfolio-tracker\backend\src\controllers\importController.js` | Excel import parsing |
| `C:\workspaceai\portfolio-tracker\backend\src\services\rebalancingService.js` | Rebalancing calculations |
| `C:\workspaceai\portfolio-tracker\backend\src\utils\yahooFinance.js` | Price fetching |
| `C:\workspaceai\portfolio-tracker\backend\src\controllers\composition\allocationAnalysis.js` | Asset allocation analysis |

**API Client:**

| File | Purpose |
|------|---------|
| `C:\workspaceai\portfolio-tracker\frontend\src\lib\api\client.ts` | Base HTTP client |
| `C:\workspaceai\portfolio-tracker\frontend\src\lib\api\portfolios.ts` | Portfolio API module |
| `C:\workspaceai\portfolio-tracker\frontend\src\lib\api\analytics.ts` | Analysis endpoint wrapper |

**Feature Components:**

| File | Purpose |
|------|---------|
| `C:\workspaceai\portfolio-tracker\frontend\src\components\features\portfolio\PortfolioFormModal.tsx` | Create/edit portfolio UI |
| `C:\workspaceai\portfolio-tracker\frontend\src\components\features\asset\AssetsList.tsx` | Asset management UI |
| `C:\workspaceai\portfolio-tracker\frontend\src\components\features\analysis\PortfolioAnalysis.tsx` | Composition analysis coordinator |
| `C:\workspaceai\portfolio-tracker\frontend\src\components\features\rebalancing\RebalancingDashboard.tsx` | Rebalancing UI |

## Naming Conventions

**Files:**

| Pattern | Example | Used For |
|---------|---------|----------|
| `*Controller.js` | `portfolioController.js` | Backend request handlers |
| `*Routes.js` | `portfolioRoutes.js` | Express route definitions |
| `*Service.js` | `rebalancingService.js` | Backend business logic |
| `*Modal.tsx` | `PortfolioFormModal.tsx` | Frontend dialogs |
| `*Section.tsx` | `AllocationSection.tsx` | Analysis sub-components |
| `*Analyzer.js` | N/A (not used) | (Potential pattern unused) |
| `use*.ts` | `usePortfolio.ts`, `useToast.ts` | React custom hooks |
| `v_*` (DB) | `v_current_positions` | PostgreSQL materialized views |

**Directories:**

| Pattern | Example | Purpose |
|---------|---------|---------|
| Plural nouns | `controllers/`, `routes/`, `utils/` | Collections of modules |
| Feature names | `portfolio/`, `asset/`, `analysis/` | Feature-specific components |
| Adjective+noun | `composition/`, `shared/` | Thematic grouping |

**Functions (Backend):**

| Pattern | Example |
|---------|---------|
| `get*` | `getAllPortfolios()`, `getPortfolioById()` |
| `create*` | `createPortfolio()` |
| `update*` | `updatePortfolio()` |
| `delete*` | `deletePortfolio()` |
| `calculate*` | (None yet, but `compositionCalculator.js` exists) |

**React Components:**

| Pattern | Example |
|---------|---------|
| PascalCase | `PortfolioFormModal`, `AssetsList` |
| Descriptive | `MonthlyPerformanceChart`, `RebalancingDashboard` |
| No suffix for pages | `page.tsx` (Next.js convention) |

## Where to Add New Code

**New Backend Feature:**
1. Create controller: `C:\workspaceai\portfolio-tracker\backend\src\controllers\<domain>Controller.js`
2. Create routes: `C:\workspaceai\portfolio-tracker\backend\src\routes\<domain>Routes.js`
3. Register in: `C:\workspaceai\portfolio-tracker\backend\src\routes\index.js` → `router.use('/<domain>', <domain>Routes)`
4. If complex logic, extract to service: `C:\workspaceai\portfolio-tracker\backend\src\services\<domain>Service.js`
5. Database updates: Add tables/views to `C:\workspaceai\portfolio-tracker\backend\finance_schema.sql`
6. Create migration if schema change: `C:\workspaceai\portfolio-tracker\backend\migrations/<number>_description.sql`

**New Frontend Feature:**
1. Create feature folder: `C:\workspaceai\portfolio-tracker\frontend\src\components\features\<feature>/`
2. Create main component: `<Feature>Dashboard.tsx` or `<Feature>Modal.tsx`
3. Create sub-components: `<Feature><Section>.tsx` for each logical piece
4. Add API module if needed: `C:\workspaceai\portfolio-tracker\frontend\src\lib\api\<feature>.ts`
5. Add types to: `C:\workspaceai\portfolio-tracker\frontend\src\types\index.ts`
6. Wire into: `C:\workspaceai\portfolio-tracker\frontend\src\app\page.tsx` or import in `App.js`

**New Utility Function:**
- Calculations: `C:\workspaceai\portfolio-tracker\backend\src\utils\decimalCalculations.js` (use Decimal.js)
- External API: `C:\workspaceai\portfolio-tracker\backend\src\utils\yahooFinance.js` (async, returns data)
- Frontend formatting: `C:\workspaceai\portfolio-tracker\frontend\src\lib\utils\format.ts`

**New UI Component:**
- Generic reusable: `C:\workspaceai\portfolio-tracker\frontend\src\components\ui\<Component>.tsx`
- Export in: `C:\workspaceai\portfolio-tracker\frontend\src\components\ui\index.ts`
- Feature-specific: Create in feature folder, don't add to ui/

## Special Directories

**backend/.next/ and frontend/.next/:**
- Purpose: Next.js build artifacts
- Generated: Yes (by build process)
- Committed: No (.gitignore excludes)
- Wipe if: Stale cache causes issues (`rm -rf .next`)

**backend/node_modules/ and frontend/node_modules/:**
- Purpose: npm dependencies
- Generated: Yes (`npm install`)
- Committed: No (.gitignore excludes)
- Rebuild if: package-lock.json changes

**backend/migrations/:**
- Purpose: Version-controlled database schema changes
- Generated: No (manually created)
- Committed: Yes (tracking schema evolution)
- Pattern: SQL files numbered sequentially (`001_*`, `002_*`, etc.)

**frontend/.env.local:**
- Purpose: Local environment variables (not committed)
- Example contents: `NEXT_PUBLIC_API_URL=http://localhost:3001/api`
- Gitignore: Yes (.gitignore excludes)

---

*Structure analysis: 2026-02-05*
