# Architecture

**Analysis Date:** 2026-02-05

## Pattern Overview

**Overall:** Modular MVC with Controller-Service pattern on backend; Component-based React/Next.js frontend with feature-driven organization.

**Key Characteristics:**
- Strict separation of concerns: routes → controllers → services/utils → database
- Database-driven approach using PostgreSQL with materialized views for computed data
- RESTful API design with modular route registration
- Frontend organized by feature areas (portfolio, analysis, rebalancing, etc.)
- Hybrid: Legacy React (App.js) coexists with modern Next.js (app/page.tsx)

## Layers

**Backend Routing Layer:**
- Purpose: HTTP endpoint definition and request routing
- Location: `C:\workspaceai\portfolio-tracker\backend\src\routes\`
- Contains: Route handlers that delegate to controllers
- Depends on: Controllers
- Used by: Express server (`C:\workspaceai\portfolio-tracker\backend\server.js`)
- Key files:
  - `index.js` - Central route aggregator registering all domain routes
  - `portfolioRoutes.js`, `transactionRoutes.js`, `assetRoutes.js` - Domain-specific routes
  - `compositionAnalysisRoutes.js` - Portfolio analysis routes

**Backend Controller Layer:**
- Purpose: Business logic orchestration, request validation, response formatting
- Location: `C:\workspaceai\portfolio-tracker\backend\src\controllers\`
- Contains: Export handlers for each resource type (CRUD operations)
- Depends on: Database pool, services, utils
- Used by: Routes
- Key files:
  - `portfolioController.js` - Portfolio CRUD and summary endpoints
  - `transactionController.js` - Transaction CRUD
  - `positionController.js` - Position queries
  - `importController.js` - Excel file parsing and bulk import logic
  - `rebalancingController.js` - Rebalancing simulation
  - `performanceController.js` - Performance calculations
  - `composition/` subdirectory - Specialized analytics (allocation, sector, geography, bond metrics)

**Backend Service Layer:**
- Purpose: Complex business logic, external API integration, data transformation
- Location: `C:\workspaceai\portfolio-tracker\backend\src\services\`
- Contains: Reusable business logic modules
- Depends on: Utils, database, external APIs
- Used by: Controllers
- Key files:
  - `compositionCalculator.js` - Computes portfolio composition metrics
  - `rebalancingService.js` - Rebalancing algorithms and simulations
  - `justETFScraper.js` - Web scraping for ETF data
  - `ollamaService.js` - LLM integration for data extraction

**Backend Utility Layer:**
- Purpose: Low-level helpers, calculations, external service clients
- Location: `C:\workspaceai\portfolio-tracker\backend\src\utils\`
- Contains: Stateless utility functions
- Depends on: External libraries (Decimal.js, axios, yahoo-finance2)
- Used by: Services, controllers
- Key files:
  - `yahooFinance.js` - Price fetching and stock data queries
  - `calculations.js` - Basic financial calculations
  - `decimalCalculations.js` - Precise decimal math using Decimal.js

**Backend Configuration:**
- Purpose: Environment and connection setup
- Location: `C:\workspaceai\portfolio-tracker\backend\src\config\`
- Contains: Database pool, upload middleware, server settings
- Key files:
  - `database.js` - PostgreSQL connection pool (pg library)
  - `upload.js` - Multer configuration for Excel uploads
  - `server.js` - Server configuration (port, timeouts)

**Database Layer:**
- Purpose: Data persistence with PostgreSQL
- Entry point: `C:\workspaceai\portfolio-tracker\backend\finance_schema.sql`
- Architecture: Tables + materialized views (e.g., `v_current_positions`, `v_portfolio_performance`)
- Key tables: portfolios, assets, transactions, positions (computed), etf_asset_allocation
- Computed views provide pre-calculated metrics to avoid expensive queries

**Frontend App Shell:**
- Purpose: Next.js application container and layout
- Location: `C:\workspaceai\portfolio-tracker\frontend\src\app\`
- Contains: Layout wrapper (`layout.tsx`), root page (`page.tsx`)
- Entry point: `page.tsx` renders `HomeContent` (main UI)

**Frontend Legacy Application:**
- Purpose: Original monolithic React app (pre-Next.js refactor)
- Location: `C:\workspaceai\portfolio-tracker\frontend\src\App.js`
- Contains: 1000+ line component with all main features
- Status: Still actively used alongside Next.js components

**Frontend Feature Components:**
- Purpose: Self-contained UI modules for specific business domains
- Location: `C:\workspaceai\portfolio-tracker\frontend\src\components\features\`
- Organized by domain:
  - `portfolio/` - Portfolio CRUD UI (PortfolioFormModal)
  - `asset/` - Asset management (AssetsList, AssetFormModal)
  - `transaction/` - Transaction entry and imports
  - `performance/` - Performance charts (MonthlyPerformanceChart)
  - `allocation/` - Allocation visualization
  - `analysis/` - Comprehensive analysis (equity/, bond/, shared/)
  - `rebalancing/` - Rebalancing dashboard and simulators

**Frontend UI Components:**
- Purpose: Reusable design system primitives
- Location: `C:\workspaceai\portfolio-tracker\frontend\src\components\ui\`
- Contains: Generic button, input, modal, select, textarea, toast
- Used by: Feature components throughout app

**Frontend API Client Layer:**
- Purpose: HTTP communication with backend
- Location: `C:\workspaceai\portfolio-tracker\frontend\src\lib\api\`
- Contains: Typed API functions using `apiClient` base
- Key files:
  - `client.ts` - Base fetch wrapper with error handling
  - `portfolios.ts`, `assets.ts`, `transactions.ts` - Domain API modules
  - `analytics.ts` - Analysis endpoint wrappers
  - `index.ts` - Public API export

**Frontend Context & Hooks:**
- Purpose: State management and reusable logic
- Location: `C:\workspaceai\portfolio-tracker\frontend\src\lib\context\` and `hooks/`
- Key files:
  - `ToastContext.tsx` - Global notification system
  - `usePortfolio.ts` - Portfolio data fetching hook
  - `useToast.ts` - Toast provider hook

**Frontend Utilities:**
- Purpose: Data formatting, color mapping, asset helpers
- Location: `C:\workspaceai\portfolio-tracker\frontend\src\lib\utils\`
- Key files:
  - `format.ts` - Currency, percent, date formatting
  - `colors.ts` - Color palette for charts
  - `assetHelpers.ts` - Asset-related utilities

## Data Flow

**Portfolio Data Retrieval:**
1. Frontend calls `portfoliosApi.getPortfolios()` → `GET /api/portfolios`
2. Backend route handler calls `getAllPortfolios()` controller
3. Controller queries `portfolios` table directly
4. PostgreSQL returns rows, controller returns JSON
5. Frontend updates state and re-renders

**Transaction Import (Excel):**
1. User uploads file via `ImportExcelModal` component
2. Form multipart POST to `POST /api/import/excel` with portfolioId
3. `importController.importExcel()` receives file buffer
4. Parses Excel with xlsx library:
   - Finds header row dynamically
   - Normalizes column names
   - Reads value rows
5. For each transaction:
   - Checks if asset exists, creates if needed
   - Inserts transaction record
   - Updates position (aggregate from transactions)
6. Returns import summary (created/skipped/errors)
7. Frontend displays toast and refreshes data

**Price Update Flow:**
1. Controller calls `yahooFinance.ts` utility
2. Utility fetches current prices from Yahoo Finance API
3. Updates `assets.current_price` and `assets.last_price_date`
4. Triggers PostgreSQL view refresh to recalculate positions
5. Frontend queries updated `v_current_positions` view

**Portfolio Analysis (Composition):**
1. User selects portfolio and opens Analysis tab
2. Frontend calls `/api/composition/` endpoints:
   - `/allocation` → `allocationAnalysis.js` controller
   - `/sector` → `sectorAnalysis.js` controller
   - `/geography` → `geographicAnalysis.js` controller
   - `/holdings` → `holdingsAnalysis.js` controller
3. Each controller:
   - Computes weighted allocation using current positions
   - Applies look-through for ETF holdings
   - Returns categorized data
4. Frontend renders with Recharts in feature components
   - `EquityAnalysis.tsx`, `BondAnalysis.tsx` for detailed breakdowns
   - `PortfolioAnalysis.tsx` coordinates all analyses

**Rebalancing Simulation:**
1. User enters target allocation in `RebalancingDashboard`
2. Frontend POST to `/api/rebalancing/simulate`
3. `rebalancingService.js` calculates:
   - Current vs target weights
   - Required trades
   - Cost impact and drift analysis
4. Returns simulation results
5. Frontend displays in `DriftAnalysis`, `SmartDeposit`, `ManualSimulation` components

**State Management Pattern:**
- Legacy App.js: Local state with useState hooks + direct fetch calls
- Modern components: usePortfolio hook for shared portfolio context
- Asynchronous operations: React hooks with useEffect
- No Redux/MobX; preference for lifting state and prop drilling

## Key Abstractions

**Portfolio Entity:**
- Purpose: Container for positions, transactions, performance
- Implementation: `portfolioController.js` manages CRUD
- Database: `portfolios` table + views (`v_portfolio_performance`, `v_asset_allocation`)
- Frontend: Selected via dropdown, triggers data reload

**Position (Current Holdings):**
- Purpose: Computed aggregate of transactions per asset
- Implementation: Materialized view `v_current_positions`
- Calculation: SUM(quantity), AVG(price), CURRENT_VALUE = quantity × current_price
- Refresh: Triggered by price updates or transaction changes

**Transaction Record:**
- Purpose: Audit trail of buy/sell/dividend actions
- Fields: portfolio_id, asset_id, type (BUY/SELL/DIVIDEND), quantity, price, commission, date
- Implementation: `transactionController.js`, Excel import in `importController.js`

**Asset:**
- Purpose: Security master data (ISIN, name, type, sector, country)
- Types: Azionario (stock), Obbligazione (bond), Liquidità (cash)
- Pricing: yahoo-finance2 integration for automated updates
- Enrichment: ETF composition from justETF scraping

**ETF Composition (Look-Through):**
- Purpose: Decompose ETF into underlying holdings
- Implementation: `etf_asset_allocation` table + `etfCompositionController.js`
- Data source: Ollama LLM for extraction from justETF pages
- Used for: Asset allocation and sector analysis drill-down

**Rebalancing Scenario:**
- Purpose: Simulate portfolio rebalancing
- Inputs: Current positions, target allocation, available cash
- Outputs: Required trades, cost impact, drift metrics
- Implementation: `rebalancingService.js`, stored separately from actual transactions

**Performance Snapshot:**
- Purpose: Historical portfolio value tracking
- Implementation: `portfolio_snapshots` table, query via `getPortfolioSnapshots()`
- Refresh: Manual trigger or scheduled (implementation details in SQL)

## Entry Points

**Backend Entry Point:**
- Location: `C:\workspaceai\portfolio-tracker\backend\server.js`
- Triggers: `npm start` or `npm run dev`
- Responsibilities:
  - Initializes Express app with CORS and JSON middleware
  - Registers all route modules via `src/routes/index.js`
  - Starts HTTP server on PORT (default 3001)
  - Handles graceful shutdown with SIGTERM
  - Establishes database pool connection
- Health check: `GET /api/health` verifies database connectivity

**Frontend Entry Point (Next.js):**
- Location: `C:\workspaceai\portfolio-tracker\frontend\src\app\page.tsx`
- Triggers: `npm run dev` (Next.js dev server)
- Responsibilities:
  - Renders root layout from `layout.tsx`
  - Wraps HomeContent in `ToastProvider`
  - Initializes portfolio and asset state
  - Sets up event listeners and effect hooks
  - Routes to feature components based on activeTab state

**Frontend Entry Point (Legacy):**
- Location: `C:\workspaceai\portfolio-tracker\frontend\src\App.js`
- Triggers: Old `npm run legacy:start` (react-scripts)
- Responsibilities: Main monolithic component with all features

**Database Entry Point:**
- Location: `C:\workspaceai\portfolio-tracker\backend\finance_schema.sql`
- Triggers: Setup phase, `psql -d finance -f finance_schema.sql`
- Responsibilities: Creates tables, views, triggers, initial schema

## Error Handling

**Strategy:** Try-catch blocks in controllers with 500/400/404 status codes; basic error messages returned to frontend; no centralized error boundary (legacy React only)

**Patterns:**
- Backend: Controller catches database errors, logs to console, returns `{ error: "message" }` JSON
- Frontend (legacy App.js): catch blocks in async functions, console.error logging, silent failures or user-facing toasts
- Frontend (new components): Try-catch in API calls with `useToast()` error notifications
- Database: ROLLBACK on transaction errors in import flow

**Example (importController):**
```javascript
try {
  await client.query('BEGIN');
  // ... transaction logic
  await client.query('COMMIT');
} catch (err) {
  await client.query('ROLLBACK');
  log(`ERROR: ${err.message}`);
  res.status(500).json({ success: false, error: err.message });
}
```

## Cross-Cutting Concerns

**Logging:**
- Backend: Console.log/console.error in each controller
- Special: `importController.js` writes debug logs to file (`debug_import.log`)
- Frontend: No centralized logging; console.log for debugging

**Validation:**
- Backend: Parameter presence checks in controllers (e.g., `portfolioId` required)
- Excel import: Dynamic header detection, type coercion for numbers
- Frontend: React state initialized with defaults; no form-level validation library

**Authentication:**
- Not implemented; no auth middleware
- All endpoints publicly accessible
- Assumes single-user or trusted environment

**Data Precision:**
- Decimal.js library used for financial calculations (`decimalCalculations.js`)
- PostgreSQL numeric type for money fields
- Frontend: formatCurrency() displays 2 decimals

**Database Transactions:**
- Used in Excel import to ensure atomicity
- BEGIN/COMMIT/ROLLBACK pattern in importController
- No transaction management in other flows (ACID per-query assumption)

---

*Architecture analysis: 2026-02-05*
