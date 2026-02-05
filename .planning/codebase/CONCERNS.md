# Codebase Concerns

**Analysis Date:** 2026-02-05

## Security Issues

**SQL Injection Risk in Query Parameters:**
- Issue: LIMIT clauses are concatenated directly into SQL queries instead of parameterized
- Files:
  - `./backend/src/controllers/composition/allocationAnalysis.js` (lines 22, 84, 159, 237, 265)
  - `./backend/src/controllers/composition/bondMaturityAnalysis.js` (lines 24, 96, 181, 269, 298)
  - `./backend/src/controllers/composition/bondRatingAnalysis.js` (lines 23, 85, 160, 238, 266)
  - `./backend/src/controllers/composition/geographicAnalysis.js` (lines 43, 105, 180, 258, 286)
  - Similar patterns across all composition analysis controllers
- Pattern: `${queryLimit ? `LIMIT ${queryLimit}` : ''}` where queryLimit is parsed from req.query but still concatenated
- Impact: Although parseInt provides some protection, this violates SQL safety best practices
- Fix approach: Use parameterized queries or safe builder patterns. Never concatenate user input into SQL strings even after parsing

**Hardcoded API URLs in Frontend Components:**
- Issue: Hardcoded localhost URLs scattered throughout frontend instead of using centralized config
- Files:
  - `./frontend/src/components/features/transaction/ImportExcelModal.tsx:55` - hardcoded 'http://localhost:3001/api/import/excel'
  - `./frontend/src/app/page.tsx:860` - hardcoded 'http://localhost:3001/api/portfolios/'
  - `./frontend/src/components/features/performance/MonthlyPerformanceChart.tsx:8` - API_URL hardcoded to localhost
- Impact: Production deploys will fail, environment switching is error-prone
- Fix approach: Centralize all API URLs in environment-based configuration. Use the pattern from `./frontend/src/lib/api/client.ts` (which correctly uses NEXT_PUBLIC_API_URL) for all API calls

**Database Credentials in Environment Variables Only:**
- Issue: No validation that required DB env vars are set at startup
- Files: `./backend/src/config/database.js`
- Current: Uses defaults 'localhost', 'postgres' if env vars missing
- Impact: Silent failures if database config is not properly set
- Fix approach: Add validation on server startup to ensure required env vars are present

## Architectural Concerns

**Monolithic Frontend Page Component:**
- Issue: Main page is 1220 lines in a single component
- File: `./frontend/src/app/page.tsx`
- Contains: Portfolio management, assets, transactions, performance charts, analysis tabs, rebalancing
- Problem: Difficult to test, maintain, and reason about. High cognitive complexity. Hard to reuse logic
- Fix approach: Extract functionality into custom hooks. Break into smaller sub-components (PortfolioManager, TransactionManager, AnalysisPanel, etc.)

**State Management Scattered Across Multiple useState Calls:**
- Issue: The main page has 10+ useState declarations managing different aspects of the same domain
- File: `./frontend/src/app/page.tsx` (lines 50-68)
- States: portfolios, selectedPortfolio, assets, editingAsset, editingTransaction, activeTab, showModal, filters (multiple), riskStats, showAllocationDetail
- Problem: No single source of truth. Risk of state inconsistencies. Difficult to synchronize related state
- Fix approach: Consider using useReducer or moving to a proper state management solution (Context with useReducer, or Redux)

**Temporary/Backup Files Left in Source:**
- Issue: Incomplete refactoring artifacts left in codebase
- Files:
  - `./backend/src/controllers/composition/geographicAnalysis_temp.js` - appears to be a partial refactor
  - `./backend/src/controllers/composition/geographicAnalysis_temp.js:4` mentions "region ANALYSIS" (should be geographic)
- Impact: Code duplication, confusion about which file is authoritative, unused code path
- Fix approach: Delete geographicAnalysis_temp.js. Verify all references are to geographicAnalysis.js

## Code Quality Concerns

**Missing Test Coverage:**
- Issue: Only one test file exists (./frontend/src/App.test.js) which doesn't test actual application code
- Problem: No tests for critical paths (portfolio operations, transaction imports, calculations)
- High-risk areas without tests:
  - Excel import logic in `./backend/src/controllers/importController.js` (complex file parsing)
  - Composition analysis calculations in `./backend/src/controllers/composition/*.js`
  - Performance and position calculations in `./frontend/src/lib/hooks/usePortfolio.ts`
  - Currency conversion and amount calculations
- Impact: Bugs in calculations go undetected. Regressions are not caught
- Fix approach:
  - Add Jest/Vitest configuration
  - Create test suites for: import logic, calculations, API client, hooks
  - Target minimum 70% coverage for critical business logic

**Generic Type Usage (any):**
- Issue: 36 uses of 'any' type in TypeScript files
- Files: Scattered throughout frontend
- Problem: Defeats TypeScript's type safety. Hides bugs at compile time
- Example: `setEditingTransaction(transaction: any | null)` in `./frontend/src/app/page.tsx:54`
- Fix approach: Define proper types for all entities. Create strict tsconfig settings to warn on 'any'

**Console Logging Left in Production Code:**
- Issue: 30+ console.error/log statements throughout the codebase
- Files: Scattered in API client, controllers, components
- Problem: Logs sensitive information in production. Slows down application. Poor error tracking
- Fix approach: Implement proper logging service with levels. Replace console calls with logger.error(). Send errors to monitoring service (Sentry, LogRocket)

**Error Handling via alert() and console.error():**
- Issue: Frontend uses browser alert() for error messages and only console.error for logging
- Files: Multiple locations in `./frontend/src/app/page.tsx` (lines 142, 166, 867, etc.)
- Pattern: `catch(error) { console.error(...); alert('Error...'); }`
- Problem: Poor UX (alerts block execution), no error tracking, no detailed error context
- Fix approach: Use proper toast/notification system (already available in ToastContext). Implement error boundary. Log to monitoring service

## Data & Performance Concerns

**Silent Fallback to Empty Arrays in API Calls:**
- Issue: Parallel API calls catch all errors and return empty arrays
- File: `./frontend/src/lib/api/etfComposition.ts` (lines 154-190, 218-223)
- Pattern: `.catch(() => ({ holdings: [] ]))` used extensively
- Problem: API failures go unnoticed. User sees incomplete data without knowing errors occurred
- Impact: User makes decisions on partial/stale data unknowingly
- Fix approach: Implement proper error boundaries. Show error indicators when data is unavailable. Log API failures

**Unvalidated Excel Import with Complex Parsing:**
- Issue: Excel import logic is complex (80+ lines) with dynamic header detection
- File: `./backend/src/controllers/importController.js:44-76`
- Parsing: Uses heuristic row search, normalizes headers, converts data types
- Problem: Fragile parsing. No schema validation. Silent failures on malformed input
- Current: Logs to file instead of database for audit trail
- Fix approach: Add comprehensive input validation. Use strict schema. Add transaction rollback on partial failures

**Currency and Amount Type Inconsistencies:**
- Issue: Amount fields use inconsistent types (number | string) in Position interface
- File: `./frontend/src/types/index.ts:77-80`
- Problem: Forces runtime type coercion. Risk of calculation errors
- Fix approach: Standardize all monetary values as numbers at storage. Type-check all calculations

**Missing Price Update Validation:**
- Issue: No validation that price updates succeed or handle partial failures
- File: Prices updated via `./backend/src/controllers/priceUpdateController.js` and `usePortfolio.ts` hook
- Problem: Stale prices can be used for calculations without user awareness
- Fix approach: Track price update timestamps. Show warnings if data is stale

## Fragile Components

**Manual Composition Form:**
- Files: `./frontend/src/components/features/asset/ManualCompositionForm.tsx` (723 lines)
- Problem: Extremely large component managing 6 different data types (holdings, sectors, regions, allocation, bond ratings, bond maturity)
- Risk: Single change can break multiple composition types. Difficult to add new composition types
- Safe modification: Extract each composition type into separate sub-component. Use compound component pattern
- Test coverage: Currently untested

**Asset List Component:**
- Files: `./frontend/src/components/features/asset/AssetsList.tsx` (584 lines)
- Problem: Large component with mixed concerns (filtering, sorting, table display, composition management, deletion)
- Risk: Changes to sorting logic could affect filtering. Hard to test table rendering independently
- Safe modification: Extract table display, filtering logic, and composition dialog into separate components

**Composition Analysis Controllers Duplication:**
- Files: Multiple nearly-identical analysis controllers in `./backend/src/controllers/composition/`
  - `allocationAnalysis.js`
  - `bondMaturityAnalysis.js`
  - `bondRatingAnalysis.js`
  - `geographicAnalysis.js`
  - `holdingsAnalysis.js`
  - `sectorAnalysis.js`
- Problem: ~250+ lines of duplicated query patterns, error handling, normalization logic
- Risk: Bug fix in one must be manually propagated to others. Inconsistent behavior
- Safe modification: Extract common query builder pattern. Create generic analysis endpoint factory

## Scalability Limits

**Portfolio-Wide View Generation Performance:**
- Issue: Portfolio analysis requires running 6 separate composition queries in parallel
- Files: `./frontend/src/lib/api/etfComposition.ts:154-190`
- Current: Promise.all() waits for all to complete
- Problem: Large portfolios (100+ positions) with slow ETF composition data will timeout
- Improvement path:
  - Add query timeout configuration
  - Implement pagination for composition endpoints
  - Cache composition data with TTL
  - Consider pre-calculating aggregates on backend

**Excel Import Memory Usage:**
- Issue: Entire Excel file loaded into memory before processing
- File: `./backend/src/controllers/importController.js:38`
- Pattern: `xlsx.read(req.file.buffer, { type: 'buffer' })`
- Problem: Large files (>10K rows) will consume significant memory
- Improvement path: Stream processing of Excel rows. Process in batches. Implement max file size validation

**Database Connection Pool Configuration:**
- Issue: Connection pool max set to 20 (small)
- File: `./backend/src/config/database.js:15`
- Problem: Under load, connection pool exhaustion could cause cascading failures
- Improvement path: Monitor pool usage. Increase max connections or add connection queue management

## Missing Critical Features

**No Audit Trail:**
- Problem: No logging of who/when for portfolio changes (add/delete assets, import transactions)
- Impact: Cannot investigate errors, no compliance trail
- Fix approach: Add audit log table. Log all portfolio modifications with user/timestamp/before-after

**No Data Validation on Insert:**
- Problem: No schema validation on transaction/asset creation before database insert
- Files: Controllers accept user input directly and insert into DB
- Impact: Corrupted data in database, calculation errors
- Fix approach: Add Joi/Yup schema validation in controllers before database operations

**No Backup/Recovery Mechanism:**
- Problem: No backup strategy documented or implemented
- Impact: Data loss risk unmitigated
- Fix approach: Implement automated PostgreSQL backups. Document recovery procedure

## Dependencies at Risk

**Node Dependencies Not Pinned:**
- Issue: package.json likely uses ^ and ~ version specifications
- Impact: Minor version updates could introduce breaking changes
- Fix approach: Use npm ci instead of npm install. Consider using lockfile-strictness

**Excel Parser (xlsx) Without Security Updates:**
- Issue: Dependency on xlsx library for file processing
- Problem: File-based vulnerabilities could exist (malformed files, XXE attacks)
- Fix approach: Implement file size limits. Validate file structure before parsing. Keep xlsx updated

**PostgreSQL Driver Version:**
- Issue: pg driver used without pinned version in package.json
- Risk: Version mismatches between environments
- Fix approach: Pin database driver version strictly

## Type Safety Gaps

**Position Interface Allows number | string:**
- File: `./frontend/src/types/index.ts:77-80`
- Problem: quantity, average_buy_price, current_price, current_value can be either type
- Risk: Runtime errors if code expects number but gets string
- Fix approach: Enforce strict parsing. Store all monetary values as numbers. Parse at API boundary

**Missing Error Type Definitions:**
- Issue: Error handling uses generic Error type
- Problem: Can't distinguish between different error types (network, validation, auth, etc.)
- Fix approach: Create ApiError hierarchy. Use type guards to handle errors appropriately

---

*Concerns audit: 2026-02-05*
