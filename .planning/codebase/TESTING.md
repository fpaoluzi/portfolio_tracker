# Testing Patterns

**Analysis Date:** 2026-02-05

## Test Framework

**Status:** No automated tests detected in codebase

**Dependencies Installed:**
- Frontend: `@testing-library/react`, `@testing-library/dom`, `@testing-library/jest-dom`, `@testing-library/user-event` (in `package.json`)
- Backend: No testing libraries installed

**Runner:** Not configured; Jest likely available via Create React App but no configuration file

**Run Commands:** Not applicable (no tests found)

## Test File Organization

**Location:** No test files found

**Naming Pattern:** Not applicable (no test files)

**Structure:** Not applicable (no test files)

## Test Structure

**Current State:**
- No tests exist in the repository
- `frontend/package.json` includes testing libraries (`@testing-library/react`, `@testing-library/dom`, etc.)
- ESLint config extends `react-app/jest` but no test files to validate
- Backend has no testing libraries

## Mocking

**Framework:** Not configured; would use Jest mocks or `@testing-library` utilities if tests were written

**Patterns:** Not observable from codebase

**What to Mock (if tests were written):**
- API calls: Mock `fetch` or use MSW (Mock Service Worker)
- Database queries: Would require mock pool in backend tests
- Context providers: Wrap test components with context

**What NOT to Mock:**
- React components (use real components or shallow render)
- Utility functions (test real implementations)
- Redux/Context state (test with real providers unless testing provider behavior)

## Fixtures and Factories

**Test Data:**
- Not implemented in codebase
- Frontend types define shape of data (`Portfolio`, `Asset`, `Transaction`, etc.)

**Location:** Would be in `__tests__/fixtures` or `tests/data` if implemented

## Coverage

**Requirements:** Not enforced

**View Coverage:** No command or tool configured

## Test Types

**Unit Tests:** Not implemented

**Integration Tests:** Not implemented

**E2E Tests:** Not implemented (Playwright installed in backend, but not for testing)

## Writing Tests (Recommended Pattern)

Based on codebase structure, if tests were to be added, follow these patterns:

### Frontend Component Tests (React Testing Library)

Location: Co-locate tests with components or in `src/__tests__` directory

Naming: `ComponentName.test.tsx` or `ComponentName.spec.tsx`

Pattern:
```typescript
import { render, screen, fireEvent } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { Button } from '@/components/ui/Button';

describe('Button', () => {
  it('renders with correct text', () => {
    render(<Button>Click me</Button>);
    expect(screen.getByRole('button')).toHaveTextContent('Click me');
  });

  it('calls onClick handler when clicked', async () => {
    const handleClick = jest.fn();
    render(<Button onClick={handleClick}>Click me</Button>);

    const button = screen.getByRole('button');
    await userEvent.click(button);

    expect(handleClick).toHaveBeenCalledTimes(1);
  });

  it('applies variant styles', () => {
    const { container } = render(<Button variant="success">Success</Button>);
    expect(container.querySelector('button')).toHaveClass('bg-green-500');
  });
});
```

### Hook Tests

Location: `src/lib/hooks/__tests__/` or `src/__tests__/hooks/`

Pattern:
```typescript
import { renderHook, waitFor } from '@testing-library/react';
import { usePortfolio } from '@/lib/hooks/usePortfolio';

describe('usePortfolio', () => {
  it('loads portfolio data on mount', async () => {
    const { result } = renderHook(() => usePortfolio('portfolio-123'));

    await waitFor(() => {
      expect(result.current.loading).toBe(false);
    });

    expect(result.current.positions).toBeDefined();
  });
});
```

### API Client Tests

Location: `src/lib/api/__tests__/`

Pattern:
```typescript
import { apiClient } from '@/lib/api/client';

describe('apiClient', () => {
  beforeEach(() => {
    global.fetch = jest.fn();
  });

  afterEach(() => {
    jest.resetAllMocks();
  });

  it('calls fetch with correct endpoint', async () => {
    global.fetch = jest.fn().mockResolvedValue({
      ok: true,
      json: () => Promise.resolve({ data: 'test' }),
    });

    const result = await apiClient.get('/portfolios');

    expect(global.fetch).toHaveBeenCalledWith(
      'http://localhost:3001/api/portfolios',
      expect.any(Object)
    );
    expect(result).toEqual({ data: 'test' });
  });

  it('throws ApiError on non-ok response', async () => {
    global.fetch = jest.fn().mockResolvedValue({
      ok: false,
      statusText: 'Not Found',
      status: 404,
    });

    await expect(apiClient.get('/invalid')).rejects.toThrow();
  });
});
```

### Backend Controller Tests

Location: `backend/src/controllers/__tests__/` or `backend/tests/controllers/`

Pattern (using Jest with pg mock):
```javascript
jest.mock('../config/database');
const pool = require('../config/database');
const { getAllPortfolios } = require('../controllers/portfolioController');

describe('portfolioController', () => {
  it('getAllPortfolios returns active portfolios', async () => {
    const mockPortfolios = [
      { portfolio_id: '1', name: 'Portfolio 1', is_active: true },
    ];

    pool.query.mockResolvedValue({ rows: mockPortfolios });

    const req = {};
    const res = {
      json: jest.fn(),
      status: jest.fn().mockReturnThis(),
    };

    await getAllPortfolios(req, res);

    expect(pool.query).toHaveBeenCalledWith(
      'SELECT * FROM portfolios WHERE is_active = true ORDER BY name'
    );
    expect(res.json).toHaveBeenCalledWith(mockPortfolios);
  });

  it('returns 500 on database error', async () => {
    pool.query.mockRejectedValue(new Error('DB Error'));

    const req = {};
    const res = {
      json: jest.fn(),
      status: jest.fn().mockReturnThis(),
    };

    await getAllPortfolios(req, res);

    expect(res.status).toHaveBeenCalledWith(500);
  });
});
```

### Form Component Tests

Pattern (based on `AssetFormModal.tsx`):
```typescript
import { render, screen, waitFor } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { AssetFormModal } from '@/components/features/asset/AssetFormModal';

describe('AssetFormModal', () => {
  it('renders form with empty fields for new asset', () => {
    const onClose = jest.fn();
    const onSuccess = jest.fn();

    render(
      <AssetFormModal onClose={onClose} onSuccess={onSuccess} />
    );

    expect(screen.getByLabelText(/ISIN/i)).toHaveValue('');
    expect(screen.getByLabelText(/Ticker/i)).toHaveValue('');
  });

  it('submits form with valid data', async () => {
    const user = userEvent.setup();
    const onClose = jest.fn();
    const onSuccess = jest.fn();

    render(
      <AssetFormModal onClose={onClose} onSuccess={onSuccess} />
    );

    await user.type(screen.getByLabelText(/ISIN/i), 'IE00B5BMR087');
    await user.type(screen.getByLabelText(/Name/i), 'Test Fund');
    await user.click(screen.getByRole('button', { name: /Save/i }));

    await waitFor(() => {
      expect(onSuccess).toHaveBeenCalled();
      expect(onClose).toHaveBeenCalled();
    });
  });
});
```

## Configuration Needed

To set up testing, add to `frontend/package.json`:

```json
{
  "scripts": {
    "test": "jest",
    "test:watch": "jest --watch",
    "test:coverage": "jest --coverage"
  },
  "jest": {
    "testEnvironment": "jsdom",
    "setupFilesAfterEnv": ["<rootDir>/jest.setup.js"],
    "moduleNameMapper": {
      "^@/(.*)$": "<rootDir>/src/$1"
    }
  }
}
```

Create `frontend/jest.setup.js`:
```javascript
import '@testing-library/jest-dom';
```

Add to `backend/package.json`:
```json
{
  "devDependencies": {
    "jest": "^29.0.0"
  },
  "scripts": {
    "test": "jest",
    "test:watch": "jest --watch"
  }
}
```

## Testing Best Practices (Current Gaps)

**What's Missing:**
1. No unit tests for utility functions (format.ts, colors.ts, assetHelpers.ts)
2. No integration tests for API client with mock server
3. No component tests for complex components (page.tsx, PortfolioAnalysis.tsx)
4. No backend controller tests
5. No E2E tests for user workflows

**High Priority:**
- API client error handling (edge cases in `client.ts`)
- Form submission in modals (AssetFormModal, PortfolioFormModal)
- Portfolio data loading in usePortfolio hook
- Filtering and sorting logic in page.tsx

---

*Testing analysis: 2026-02-05*
