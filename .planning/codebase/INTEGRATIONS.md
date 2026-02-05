# External Integrations

**Analysis Date:** 2025-02-05

## APIs & External Services

**Financial Data:**
- **Yahoo Finance** - Real-time and historical price data for securities and ETFs
  - SDK/Client: `yahoo-finance2` 3.10.1 (official Node SDK)
  - Endpoint: https://query1.finance.yahoo.com/v8/finance/chart/{symbol}
  - Usage: `C:\workspaceai\portfolio-tracker\backend\src\utils\yahooFinance.js`
  - Data retrieved: Current prices, OHLCV data, ETF composition (holdings, sectors, geographic distribution, asset allocation, bond ratings, maturity data)
  - No authentication required (public API)

**Web Scraping:**
- **JustETF** - ETF profile pages for detailed composition data
  - Scraper: Playwright headless browser automation
  - Client: `playwright` 1.56.1
  - URL pattern: https://www.justetf.com/it/etf-profile.html?isin={ISIN}
  - Usage: `C:\workspaceai\portfolio-tracker\backend\src\services\justETFScraper.js`
  - Data retrieved: Holdings, sectors, geographic allocation (through HTML parsing)
  - No authentication required

**LLM/AI Services:**
- **Ollama** - Local LLM service for structured ETF data extraction
  - SDK/Client: `ollama` 0.6.2
  - Service endpoint: http://localhost:11434 (configurable via `OLLAMA_HOST` env var)
  - Model: deepseek-v3.1:671b-cloud (configured in `C:\workspaceai\portfolio-tracker\backend\src\services\ollamaService.js`)
  - Usage: Extracting structured JSON from JustETF HTML via LLM
  - Input: HTML content from JustETF pages
  - Output: JSON with holdings, sectors, regions, asset allocation, TER, distribution policy
  - Authentication: Local service (no external auth)
  - Location: `C:\workspaceai\portfolio-tracker\backend\src\services\ollamaService.js`

## Data Storage

**Databases:**
- **PostgreSQL 12+**
  - Provider: On-premises/self-hosted
  - Connection: `C:\workspaceai\portfolio-tracker\backend\src\config\database.js`
  - Client: `pg` 8.11.3 (node-postgres)
  - Pool config:
    - Host: `process.env.DB_HOST || 'localhost'`
    - Port: `process.env.DB_PORT || 5432`
    - Database: `process.env.DB_NAME || 'finance'`
    - User: `process.env.DB_USER || 'postgres'`
    - Max connections: 20
    - Idle timeout: 30000ms
    - Connection timeout: 2000ms
  - Schema: `C:\workspaceai\portfolio-tracker\backend\finance_schema.sql`
  - Extensions: uuid-ossp, btree_gist
  - Features: Materialized views, stored procedures (PLPGSQL), triggers

**File Storage:**
- Local filesystem only
  - Excel import files: Processed in-memory via `multer` before database storage
  - No cloud storage integration

**Caching:**
- None detected - All queries hit PostgreSQL directly

## Authentication & Identity

**Auth Provider:**
- Custom/None - The application does not implement authentication/authorization
- No login system detected
- No API key validation
- All endpoints are publicly accessible (if exposed)

## Monitoring & Observability

**Error Tracking:**
- None detected - No integration with Sentry, DataDog, etc.

**Logs:**
- Console logging approach
- Log locations in code:
  - `C:\workspaceai\portfolio-tracker\backend\src\utils\yahooFinance.js` - Price fetch errors
  - `C:\workspaceai\portfolio-tracker\backend\src\services\ollamaService.js` - Ollama extraction logs
  - `C:\workspaceai\portfolio-tracker\backend\src\services\justETFScraper.js` - Scraping progress logs
  - `C:\workspaceai\portfolio-tracker\backend\src\config\database.js` - Connection status logs

## CI/CD & Deployment

**Hosting:**
- Not configured - Application is designed for local/manual deployment
- Supports Windows (batch scripts), Linux/macOS (shell scripts)

**CI Pipeline:**
- Not detected - No GitHub Actions, GitLab CI, or similar

**Deployment Scripts:**
- `C:\workspaceai\portfolio-tracker\setup.bat` - Windows setup script
- `C:\workspaceai\portfolio-tracker\setup.sh` - Unix setup script
- `C:\workspaceai\portfolio-tracker\StartProfileTracker.bat` - Windows start script

## Environment Configuration

**Required env vars (Backend):**
- `DB_HOST` - PostgreSQL hostname
- `DB_PORT` - PostgreSQL port
- `DB_NAME` - Database name
- `DB_USER` - Database user
- `DB_PASSWORD` - Database password
- `PORT` - Express server port (default: 3001)
- `NODE_ENV` - Environment (default: development)
- `CORS_ORIGIN` - CORS allowed origin (default: http://localhost:3000)
- `OLLAMA_HOST` - Ollama endpoint (default: http://localhost:11434)

**Required env vars (Frontend):**
- `NEXT_PUBLIC_API_URL` - Backend API URL (default: http://localhost:3001/api)

**Secrets location:**
- Environment variables file (`.env` or `.env.local`)
- Database credentials in process environment
- No external secrets management (Vault, AWS Secrets Manager, etc.)

## Webhooks & Callbacks

**Incoming:**
- None detected

**Outgoing:**
- None detected

## File Processing

**Excel Import:**
- Framework: `xlsx` 0.18.5 (SheetJS)
- Upload handling: `multer` 2.0.2
- Configuration: `C:\workspaceai\portfolio-tracker\backend\src\config\upload.js`
- Max file size: 10MB
- Accepted formats: .xlsx, .xls
- Processing location: `C:\workspaceai\portfolio-tracker\backend\src\controllers\importController.js`
- Features:
  - In-memory file processing (no disk storage)
  - Row parsing with column normalization
  - Transaction import with commission/fee handling
  - Automatic average cost basis calculation

## Cross-Origin Communication

**CORS:**
- Enabled via `cors` 2.8.5 middleware
- Allowed origin: Configurable via `CORS_ORIGIN` env var (default: http://localhost:3000)
- Used for frontend-to-backend API calls

---

*Integration audit: 2025-02-05*
