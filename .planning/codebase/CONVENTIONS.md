# Coding Conventions

**Analysis Date:** 2026-02-05

## Naming Patterns

**Files:**
- Components: PascalCase (e.g., `Button.tsx`, `EquityAnalysis.tsx`, `AssetFormModal.tsx`)
- Utilities/Hooks: camelCase (e.g., `usePortfolio.ts`, `format.ts`, `colors.ts`)
- Controllers/Services: camelCase with descriptive names (e.g., `portfolioController.js`, `transactionController.js`)
- UI Components: PascalCase (e.g., `Button.tsx`, `Modal.tsx`, `Input.tsx`)

**Functions:**
- Frontend (React): camelCase for event handlers (`handleSubmit`, `handleEditAsset`, `loadPortfolios`)
- Backend (Node.js): camelCase for function names (`getAllPortfolios`, `createTransaction`, `getPortfolioPerformance`)
- Async functions: Explicitly named with async semantics (`loadPortfolioData`, `updatePrices`, `fetchApi`)
- Event handlers: `handle{Action}` pattern (e.g., `handleDeleteAsset`, `handleEditTransaction`, `handleCloseAssetModal`)

**Variables:**
- Local state: camelCase (e.g., `portfolios`, `selectedPortfolio`, `activeTab`, `positionFilter`)
- React hooks: descriptive names with type annotations (e.g., `const [loading, setLoading] = useState(false)`)
- Database fields: snake_case (e.g., `portfolio_id`, `asset_type`, `transaction_date`)
- Constants: camelCase or UPPER_SNAKE_CASE (e.g., `API_URL`, `variantClasses`)

**Types:**
- Interfaces: PascalCase (e.g., `ButtonProps`, `AssetFormModalProps`, `EquityAnalysisProps`)
- Type unions: Lowercase literal unions (e.g., `type EquityTab = 'holdings' | 'sectors' | 'regions'`)
- Enums/constants: camelCase for database enums (e.g., `transaction_type: 'BUY' | 'SELL'`)

## Code Style

**Formatting:**
- No explicit formatter detected (Prettier not configured in repo)
- Consistent indentation: 2 spaces
- Line length: Variable, no enforced limit detected
- Quotes: Single quotes in JavaScript/TypeScript strings
- Semicolons: Present throughout codebase

**Linting:**
- React app ESLint config from `react-app` and `react-app/jest` (in `frontend/package.json`)
- No custom ESLint rules file detected
- Backend has no linting configuration

**Observed Patterns:**
- Comments use `//` for single-line comments
- Block comments use `/* */` for multi-line (seen in controllers with section headers)
- Section headers: `// ============================================` decorative borders with title
- No trailing whitespace observed

## Import Organization

**Order (Frontend - React/Next.js):**
1. React imports (`import { useState, useEffect } from 'react'`)
2. Third-party UI libraries (`import { Button } from 'lucide-react'`)
3. Chart libraries (`import { LineChart, Line, ... } from 'recharts'`)
4. Internal UI components (`import { Button, Modal } from '@/components/ui'`)
5. Feature components (`import { PortfolioAnalysis } from '@/components/features/...`)
6. API clients (`import { portfoliosApi, assetsApi } from '@/lib/api'`)
7. Hooks (`import { usePortfolio } from '@/lib/hooks/...'`)
8. Utilities (`import { formatCurrency, formatPercent } from '@/lib/utils/format'`)
9. Types (`import type { Portfolio, Asset } from '@/types'`)
10. Context (`import { ToastProvider, useToastContext } from '@/lib/context/...'`)

**Path Aliases:**
- `@/*` maps to `./src/*` (configured in `frontend/tsconfig.json`)
- Used consistently: `@/components`, `@/lib`, `@/types`

**Order (Backend - Node.js):**
1. Built-in modules (none observed)
2. Third-party packages (`require('express')`, `require('pg')`)
3. Configuration (`require('../config/database')`)
4. Controllers/Utilities (as needed)
5. Module exports at end

## Error Handling

**Patterns:**
- **Frontend:** Try-catch with `console.error()` logging, alert() for user feedback
  ```typescript
  try {
    const data = await portfoliosApi.getAll();
    setPortfolios(data);
  } catch (error) {
    console.error('Error loading portfolios:', error);
    // Silently fail or show alert
  }
  ```

- **Backend:** Try-catch with `console.error()`, HTTP status codes in responses
  ```javascript
  try {
    const result = await pool.query('SELECT * FROM portfolios');
    res.json(result.rows);
  } catch (err) {
    console.error(err);
    res.status(500).json({ error: 'Errore nel recupero portafogli' });
  }
  ```

- **Async Transactions:** Explicit COMMIT/ROLLBACK pattern in backend
  ```javascript
  const client = await pool.connect();
  try {
    await client.query('BEGIN');
    // Operations
    await client.query('COMMIT');
  } catch (err) {
    await client.query('ROLLBACK');
  } finally {
    client.release();
  }
  ```

- **Custom Error Classes:** `ApiError` extends Error with status field (in `frontend/src/lib/api/client.ts`)

## Logging

**Framework:** Native `console` object (no logging library)

**Patterns:**
- **Frontend:** `console.error()` for errors only; `console.log()` for debug (occasionally)
- **Backend:** `console.error()` for errors; `console.log()` for startup messages with emoji indicators
- **Startup messages:** Formatted boxes with emoji status (✅ for success, ❌ for errors)

**When to Log:**
- Error conditions (always with stack trace)
- Database connection events (at startup)
- Graceful shutdown events
- API request failures

**Example (Backend):**
```javascript
console.log(`
╔═══════════════════════════════════════════╗
║   Portfolio Tracker API Server           ║
║   http://localhost:${PORT}                  ║
╚═══════════════════════════════════════════╝
`);
```

## Comments

**When to Comment:**
- Block section headers (with decorative borders)
- JSDoc-style comments on controller functions explaining endpoint
- Inline comments explaining complex logic (rarely used)

**JSDoc/TSDoc:**
- Backend controllers: JSDoc comments on exported functions
- Example from `portfolioController.js`:
  ```javascript
  /**
   * GET /api/portfolios
   * Recupera lista di tutti i portafogli attivi
   */
  async function getAllPortfolios(req, res) { ... }
  ```

- Frontend: Props interfaces documented via TypeScript interfaces, no JSDoc

## Function Design

**Size:** Functions are generally 20-100 lines; some page components exceed 1000 lines (not ideal but current state)

**Parameters:**
- Frontend: Props passed via interfaces with explicit types
- Backend: Destructuring from `req.body` and `req.params`
- Functions avoid excessive parameters (max 5-6)

**Return Values:**
- Frontend: React components or typed data (via hooks)
- Backend: JSON responses via `res.json()` or `res.status().json()`
- Error responses: Always include `error` field with descriptive message

**Naming Pattern:** Action-based names (`getAllPortfolios`, `createTransaction`, `loadPortfolioData`)

## Module Design

**Exports:**
- Frontend components: Named exports with `export const Component: React.FC<Props> = ...`
- Backend: `module.exports = { functionName1, functionName2, ... }`
- Utilities: Named exports for utility functions

**Barrel Files:**
- Used in `frontend/src/lib/api/index.ts` to re-export all API clients
- Used in `frontend/src/components/ui/index.ts` to re-export UI components
- Pattern: `export { PortfoliosApi as portfoliosApi } from './portfolios'`

**Example (API barrel file):**
```typescript
export { portfoliosApi } from './portfolios';
export { assetsApi } from './assets';
export { transactionsApi } from './transactions';
export { analyticsApi } from './analytics';
```

## Italian Language Usage

**Important:** The codebase uses Italian language for:
- User-facing strings (modal titles, button labels, error messages)
- Database column aliases (e.g., `portfolio_name`, field descriptions)
- Comments in controllers

**Pattern:** Database operations use English SQL, but error messages and UI text are Italian (locale: `it-IT` for formatting)

## Type Safety

**Frontend:**
- TypeScript strict mode enabled (`"strict": true` in `tsconfig.json`)
- Type imports: `import type { Portfolio, Asset } from '@/types'`
- Props interfaces for all components
- Generic types used in API client (`<T>`)

**Backend:**
- No TypeScript; uses JSDoc comments for documentation
- No type checking

---

*Convention analysis: 2026-02-05*
