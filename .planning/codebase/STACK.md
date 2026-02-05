# Technology Stack

**Analysis Date:** 2025-02-05

## Languages

**Primary:**
- JavaScript (Node.js) - Backend API, server-side logic, database operations
- TypeScript - Frontend, React components, type-safe UI development
- SQL (PostgreSQL) - Database schema, stored procedures, triggers

**Secondary:**
- HTML/CSS - UI markup and styling via Next.js/React
- PLPGSQL - PostgreSQL stored procedures (triggers, snapshots, analytics)

## Runtime

**Environment:**
- Node.js 16+ (referenced in README)
- Next.js 16.0.1 - React meta-framework for frontend
- React 19.2.0 - Frontend UI library

**Package Manager:**
- npm (Node Package Manager)
- Lockfile: Present (package-lock.json in both backend and frontend)

## Frameworks

**Core:**
- **Express.js** 4.18.2 - Backend REST API framework
- **Next.js** 16.0.1 - Frontend meta-framework with server-side rendering
- **React** 19.2.0 - Frontend component library
- **PostgreSQL** 12+ - Relational database (via `pg` driver)

**UI/Visualization:**
- **recharts** 3.3.0 - Chart and visualization library
- **lucide-react** 0.552.0 - Icon library
- **Tailwind CSS** 3.3.0 - Utility-first CSS framework
- **react-simple-maps** 3.0.0 - SVG maps for geographic visualization

**Testing:**
- **@testing-library/react** 16.3.0 - React component testing
- **@testing-library/jest-dom** 6.9.1 - DOM matchers for Jest
- **@testing-library/user-event** 13.5.0 - User interaction simulation
- **react-scripts** 5.0.1 - Test runner and build tooling

**Build/Dev:**
- **TypeScript** 5.9.3 - Type checking for frontend
- **Tailwind CSS** 3.3.0 - CSS framework
- **PostCSS** 8.4.32 - CSS processing
- **Autoprefixer** 10.4.16 - CSS vendor prefixing
- **nodemon** 3.0.1 - Auto-reload for Node development

## Key Dependencies

**Critical:**
- **pg** 8.11.3 - PostgreSQL client and connection pooling
- **axios** 1.13.2 - HTTP client for Yahoo Finance and external API calls
- **yahoo-finance2** 3.10.1 - Yahoo Finance API client (price data, ETF composition)
- **decimal.js** 10.6.0 - High-precision decimal arithmetic (critical for financial calculations)
- **express** 4.18.2 - HTTP server framework

**Data Processing:**
- **xlsx** 0.18.5 - Excel file parsing for portfolio import functionality
- **multer** 2.0.2 - Multipart file upload middleware (Excel imports)

**Scraping & Automation:**
- **playwright** 1.56.1 - Headless browser automation (JustETF scraping)

**AI/LLM Integration:**
- **ollama** 0.6.2 - Local LLM client (Deepseek V3.1 for ETF data extraction)

**Infrastructure:**
- **cors** 2.8.5 - Cross-origin resource sharing middleware
- **web-vitals** 2.1.4 - Web performance metrics

## Configuration

**Environment:**
- `.env.local` (frontend) - Contains `NEXT_PUBLIC_API_URL` for backend API endpoint
- Process environment variables (backend):
  - `PORT` - Express server port (default: 3001)
  - `NODE_ENV` - Environment mode (default: development)
  - `CORS_ORIGIN` - CORS allowed origin (default: http://localhost:3000)
  - `DB_HOST` - PostgreSQL hostname (default: localhost)
  - `DB_PORT` - PostgreSQL port (default: 5432)
  - `DB_NAME` - Database name (default: finance)
  - `DB_USER` - PostgreSQL user (default: postgres)
  - `DB_PASSWORD` - PostgreSQL password (default: postgres)
  - `OLLAMA_HOST` - Ollama LLM service endpoint (default: http://localhost:11434)

**Build:**
- `frontend/tsconfig.json` - TypeScript configuration with Next.js plugin
- `frontend/next.config.js` - Next.js configuration with environment variables
- `frontend/tailwind.config.js` - Tailwind CSS configuration
- `frontend/postcss.config.js` - PostCSS configuration
- `backend/package.json` - Backend dependencies and scripts

## Platform Requirements

**Development:**
- Node.js 16+
- PostgreSQL 12+
- npm or yarn
- Ollama (for ETF data extraction via LLM)
- Windows/Linux/macOS with bash or equivalent

**Production:**
- Node.js 16+
- PostgreSQL 12+
- Ollama service (optional, for advanced ETF analysis)
- HTTP server capable of serving static assets (Next.js build artifacts)

## Port Configuration

- **Frontend**: 3000 (Next.js dev server)
- **Backend**: 3001 (Express API server)
- **PostgreSQL**: 5432 (default)
- **Ollama**: 11434 (default)

## Database

**PostgreSQL 12+:**
- Schema location: `C:\workspaceai\portfolio-tracker\backend\finance_schema.sql`
- Database name: `finance`
- Tables: portfolios, assets, transactions, positions, price_history, portfolio_snapshots, etf_composition_data, etc.
- Features: UUID extensions, materialized views, triggers, stored procedures (PLPGSQL)

---

*Stack analysis: 2025-02-05*
