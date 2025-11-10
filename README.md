# 📈 Portfolio Tracker Pro

Sistema professionale di gestione portafoglio investimenti con backend Node.js + PostgreSQL.

## 🎯 Panoramica

Portfolio Tracker Pro è un'applicazione completa per la gestione e il monitoraggio di portafogli di investimento. Supporta multipli portafogli, importazione da Excel, aggiornamento prezzi automatico e analisi performance dettagliate.

### ✨ Caratteristiche Principali

- **Gestione Multi-Portfolio**: Gestisci più portafogli (Fineco, ING, ecc.)
- **Import da Excel**: Importazione automatica transazioni da file Excel
- **Aggiornamento Prezzi**: Integrazione Yahoo Finance per prezzi real-time
- **Analytics Avanzate**: Performance mensili, allocazione asset, metriche di rischio
- **API REST Complete**: Backend modulare e ben strutturato
- **Database PostgreSQL**: Schema ottimizzato con viste e trigger automatici

## 📋 Prerequisiti

- **Node.js** 16+ ([Download](https://nodejs.org/))
- **PostgreSQL** 12+ ([Download](https://www.postgresql.org/download/))
- **Ollama** ([Download](https://ollama.ai/)) - Per estrazione dati ETF
- **npm** o **yarn**

## 🚀 Installazione

### 1. Setup Database

```bash
# Connetti a PostgreSQL
psql -U postgres -h localhost

# Crea database
CREATE DATABASE finance;
\q

# Esegui schema unificato
cd backend
psql -U postgres -d finance -f finance_schema.sql
```

### 2. Setup Backend

```bash
cd backend
npm install

# Avvia server (produzione)
npm start

# Oppure con auto-reload (sviluppo)
npm run dev
```

Il server sarà disponibile su [http://localhost:3001](http://localhost:3001)

### 3. Test Installazione

Verifica che tutto funzioni:

```bash
curl http://localhost:3001/api/health
```

Dovresti vedere:
```json
{
  "status": "ok",
  "database": "connected",
  "timestamp": "2025-11-06T..."
}
```

## 📁 Struttura Progetto

```
portfolio-tracker/
├── backend/
│   ├── src/
│   │   ├── config/           # Configurazioni (database, upload, server)
│   │   ├── controllers/      # Logica business per ogni entità
│   │   ├── routes/           # Definizione routes API
│   │   ├── utils/            # Utility functions (Yahoo Finance, calcoli)
│   │   └── middleware/       # Middleware personalizzati (future)
│   ├── server-new.js         # Server modulare rifattorizzato
│   ├── server.js             # Server legacy (deprecato)
│   ├── finance_schema.sql    # Schema database unificato
│   ├── import.js             # Script import Excel standalone
│   └── package.json
├── frontend/                  # React frontend (opzionale)
├── README_NEW.md             # Questa documentazione
└── setup.bat / setup.sh      # Script setup automatico

## 🗂️ Architettura Backend (Rifattorizzato)

Il backend è stato completamente rifattorizzato per essere modulare e manutenibile:

### Config (`src/config/`)
- `database.js` - Configurazione pool PostgreSQL
- `upload.js` - Configurazione Multer per upload Excel
- `server.js` - Costanti server (PORT, CORS, ecc.)

### Controllers (`src/controllers/`)
- `portfolioController.js` - CRUD portafogli + analytics
- `assetController.js` - CRUD asset/titoli
- `transactionController.js` - CRUD transazioni
- `positionController.js` - Visualizzazione posizioni
- `targetAllocationController.js` - Gestione target allocation
- `priceUpdateController.js` - Aggiornamento prezzi da Yahoo Finance
- `importController.js` - Import Excel (in sviluppo)
- `performanceController.js` - Performance mensili (in sviluppo)

### Routes (`src/routes/`)
Routes organizzate per entità con registrazione centralizzata in `index.js`

### Utils (`src/utils/`)
- `yahooFinance.js` - Wrapper API Yahoo Finance
- `calculations.js` - Funzioni calcolo (Average Cost Basis, ecc.)

## 📡 API Endpoints

### Portfolios

| Method | Endpoint | Descrizione |
|--------|----------|-------------|
| GET | `/api/portfolios` | Lista tutti i portafogli |
| GET | `/api/portfolios/:id` | Dettaglio portafoglio |
| POST | `/api/portfolios` | Crea portafoglio |
| PUT | `/api/portfolios/:id` | Aggiorna portafoglio |
| DELETE | `/api/portfolios/:id` | Elimina portafoglio (soft delete) |
| GET | `/api/portfolios/:id/performance` | Performance totale |
| GET | `/api/portfolios/:id/allocation` | Allocazione asset |
| GET | `/api/portfolios/:id/positions` | Posizioni correnti |
| GET | `/api/portfolios/:id/transactions` | Lista transazioni |
| GET | `/api/portfolios/:id/snapshots` | Snapshot storici |
| POST | `/api/portfolios/:id/update-prices` | Aggiorna prezzi da Yahoo Finance |

### Assets

| Method | Endpoint | Descrizione |
|--------|----------|-------------|
| GET | `/api/assets` | Lista tutti gli asset |
| GET | `/api/assets/isin/:isin` | Cerca asset per ISIN |
| POST | `/api/assets` | Crea asset |
| PUT | `/api/assets/:id` | Aggiorna asset |
| DELETE | `/api/assets/:id` | Elimina asset |

### Transactions

| Method | Endpoint | Descrizione |
|--------|----------|-------------|
| POST | `/api/transactions` | Crea transazione |
| PUT | `/api/transactions/:id` | Aggiorna transazione |
| DELETE | `/api/transactions/:id` | Elimina transazione |

### Target Allocations

| Method | Endpoint | Descrizione |
|--------|----------|-------------|
| GET | `/api/target-allocations/:portfolioId` | Recupera target |
| POST | `/api/target-allocations` | Crea target |
| PUT | `/api/target-allocations/:id` | Aggiorna target |

### Import & Performance

| Method | Endpoint | Descrizione |
|--------|----------|-------------|
| POST | `/api/import/excel` | Importa transazioni da Excel |
| GET | `/api/portfolios/:id/monthly-performance-live` | Performance mensili on-demand |
| POST | `/api/portfolios/:id/calculate-monthly-performance` | Calcola e salva snapshot mensili |
| GET | `/api/portfolios/:id/monthly-performance` | Lista performance mensili salvate |
| GET | `/api/portfolios/:id/monthly-performance-aggregate` | Performance aggregate per mese |

### ETF Composition (Nuovo!)

| Method | Endpoint | Descrizione |
|--------|----------|-------------|
| GET | `/api/etf-composition/asset/:assetId` | Recupera composizione salvata per un asset |
| POST | `/api/etf-composition/asset/:assetId/fetch` | Fetch e salva composizione da JustETF (via Playwright + Ollama) |
| GET | `/api/etf-composition/portfolio/:portfolioId` | Composizione aggregata portafoglio (pesata) |
| GET | `/api/etf-composition/portfolios/multiple?portfolioIds=id1,id2` | Composizione aggregata multi-portafoglio |

**Sistema di Scraping Automatico:**
Il sistema utilizza **Playwright** per navigare automaticamente su JustETF.com e raccogliere i dati completi degli ETF. I dati vengono poi estratti usando **Ollama** (LLM locale) per parsing intelligente dell'HTML.

**Dati estratti da JustETF:**
- **Top Holdings**: Prime 10-15 aziende nell'ETF con percentuali
- **Sector Weights**: Distribuzione settoriale (Technology, Healthcare, ecc.)
- **Geographic Breakdown**: Distribuzione geografica (US, Europe, Asia, ecc.)
- **Asset Allocation**: Allocazione per classe (Equity, Bond, Cash, ecc.)
- **Bond Ratings**: Qualità obbligazioni (AAA, AA, A, BBB, ecc.) - per ETF obbligazionari
- **Bond Maturity**: Scadenze obbligazioni (0-1Y, 1-3Y, 5-10Y, ecc.) - per ETF obbligazionari
- **TER**: Total Expense Ratio (costi di gestione)
- **Distribution Policy**: Politica di distribuzione (Accumulating/Distributing)

**Setup Ollama:**
```bash
# Installa Ollama (https://ollama.ai/)
# Scarica il modello richiesto
ollama pull llama3

# Avvia Ollama (se non già in esecuzione)
ollama serve
```

**Test del Sistema:**
```bash
cd backend
node test-scraping.js
```

Questo script testa l'intero flusso: scraping JustETF → estrazione Ollama → JSON strutturato

### Health

| Method | Endpoint | Descrizione |
|--------|----------|-------------|
| GET | `/api/health` | Health check server e database |

## 💾 Schema Database

### Tabelle Principali

- **portfolios** - Portafogli utente
- **assets** - Anagrafica titoli (ETF, fondi, azioni) con metriche finanziarie
- **transactions** - Storico operazioni (BUY, SELL, DIVIDEND)
- **positions** - Posizioni correnti con PMC automatico
- **price_history** - Storico prezzi giornalieri
- **portfolio_snapshots** - Snapshot valori portafoglio
- **dividends** - Registro dividendi ricevuti
- **target_allocations** - Obiettivi allocazione
- **monthly_position_performance** - Performance mensili per asset

### Tabelle Composizione ETF (Nuovo!)

- **etf_holdings** - Top holdings (10-15 aziende) per ogni ETF
- **etf_sector_weights** - Distribuzione settoriale per ETF
- **etf_geographic_weights** - Distribuzione geografica per ETF
- **etf_asset_allocation** - Allocazione per asset class (Equity/Bond/Cash)
- **etf_bond_ratings** - Qualità obbligazioni per ETF obbligazionari
- **etf_bond_maturity** - Scadenze obbligazioni per ETF obbligazionari

### Viste

- **v_current_positions** - Posizioni con gain/loss e percentuali
- **v_asset_allocation** - Allocazione per tipo asset
- **v_portfolio_performance** - Performance totale portfolio
- **v_monthly_portfolio_performance** - Performance mensili aggregate
- **v_etf_composition_summary** - Riepilogo dati composizione disponibili per asset

### Trigger Automatici

- Aggiornamento posizioni al salvataggio transazioni
- Calcolo automatico Prezzo Medio di Carico (PMC)
- Timestamp automatici su update

## 🔧 Comandi Utili

### Backend

```bash
cd backend

# Installa dipendenze
npm install

# Avvia server produzione
npm start

# Avvia server sviluppo (auto-reload)
npm run dev

# Import dati da Excel
npm run import
```

### Database

```bash
# Connetti al database
psql -U postgres -d finance

# Query utili
SELECT * FROM portfolios;
SELECT * FROM v_current_positions;
SELECT * FROM v_portfolio_performance;
SELECT * FROM assets ORDER BY name;

# Backup
pg_dump -U postgres finance > backup_$(date +%Y%m%d).sql

# Restore
psql -U postgres finance < backup_20251106.sql
```

## 📊 Import Dati da Excel

1. Copia il tuo file Excel nella cartella `backend/`
2. Il file deve avere un foglio "Storico Ordini" con le colonne:
   - Titolo, ISIN, Descrizione, Segno (A/V)
   - Quantità, Prezzo, Operazione (data)
   - Divisa, Commissioni, Spese, ecc.

3. Esegui import:

```bash
cd backend
npm run import
# Oppure: node import.js NomeFileExcel.xlsx
```

## 🎯 Analisi Composizione ETF (Nuovo!)

La nuova funzionalità di analisi composizione ETF permette di ottenere informazioni dettagliate sulla composizione degli ETF presenti nei tuoi portafogli.

### Come Funziona

1. **Recupera dati da Yahoo Finance** per un singolo asset:

```bash
# Via API
POST /api/etf-composition/asset/{assetId}/fetch

# Esempio con curl
curl -X POST http://localhost:3001/api/etf-composition/asset/YOUR_ASSET_ID/fetch
```

2. **Visualizza dati salvati** per un asset:

```bash
GET /api/etf-composition/asset/{assetId}
```

3. **Analisi aggregata portafoglio** (ponderata per valore posizioni):

```bash
# Singolo portafoglio
GET /api/etf-composition/portfolio/{portfolioId}

# Multi-portafoglio
GET /api/etf-composition/portfolios/multiple?portfolioIds=id1,id2,id3
```

### Dati Disponibili

Per ogni ETF vengono recuperati:

- **Top Holdings**: Le 10-15 principali aziende con percentuali di peso
- **Sector Weights**: Distribuzione per settore (Technology 25%, Healthcare 15%, ecc.)
- **Geographic Breakdown**: Distribuzione geografica (US 60%, Europe 25%, Asia 15%)
- **Asset Allocation**: Allocazione per classe (Equity 85%, Bond 10%, Cash 5%)
- **Bond Ratings** (per ETF obbligazionari): AAA, AA, A, BBB, ecc.
- **Bond Maturity** (per ETF obbligazionari): 0-1Y, 1-3Y, 3-5Y, 5-10Y, 10-20Y, 20+Y

### Frontend - Componente PortfolioAnalysis

Il componente React `PortfolioAnalysis` fornisce:

- **Selezione Multi-Portfolio**: Seleziona uno o più portafogli per l'analisi
- **Visualizzazione con Tabs**: Holdings, Settori, Geografia, Asset Allocation
- **Grafici Interattivi**: Pie charts e bar charts per ogni categoria
- **Tabelle Dettagliate**: Percentuali precise per ogni voce
- **Aggiornamento Manuale**: Pulsante per refreshare i dati da Yahoo Finance

### Esempio di Utilizzo

```javascript
import { PortfolioAnalysis } from './components/features/analysis/PortfolioAnalysis';

// Nel tuo componente React
<PortfolioAnalysis
  availablePortfolios={[
    { portfolio_id: 'uuid-1', name: 'Fineco' },
    { portfolio_id: 'uuid-2', name: 'ING' }
  ]}
/>
```

### Note Importanti

- I dati vengono salvati nel database e possono essere riutilizzati
- L'aggiornamento è manuale tramite pulsante (evita rate limiting Yahoo Finance)
- I dati sono disponibili solo per ETF con ticker valido
- L'analisi multi-portfolio è ponderata per il valore delle posizioni
- Alcuni ETF potrebbero non avere tutti i dati disponibili (es. bond data solo per ETF obbligazionari)

## 🐛 Troubleshooting

### Errore: "database finance does not exist"

```bash
psql -U postgres -c "CREATE DATABASE finance;"
cd backend
psql -U postgres -d finance -f finance_schema.sql
```

### Errore: "cannot connect to database"

```bash
# Verifica PostgreSQL attivo
# Windows:
sc query postgresql-x64-16

# Linux/Mac:
sudo systemctl status postgresql
```

### Errore: "module not found"

```bash
cd backend
rm -rf node_modules
npm install
```

### Porta 3001 già in uso

```bash
# Windows
netstat -ano | findstr :3001
taskkill /PID <PID> /F

# Linux/Mac
lsof -i :3001
kill -9 <PID>
```

## 🔄 Migrazione da Vecchio Codice

Se stai migrando dal vecchio `server.js` monolitico:

1. **Backup del database**:
   ```bash
   pg_dump -U postgres finance > backup_pre_migration.sql
   ```

2. **Applica schema unificato** (se necessario):
   ```bash
   psql -U postgres -d finance -f backend/finance_schema.sql
   ```

3. **Usa nuovo server**:
   ```bash
   cd backend
   node server-new.js
   ```

4. **Test**:
   - Verifica `/api/health`
   - Testa endpoint principali
   - Controlla che i dati siano corretti

5. **Elimina file vecchi** (opzionale):
   ```bash
   # Solo dopo aver verificato che tutto funziona!
   rm backend/server.js
   rm backend/*.sql (tranne finance_schema.sql)
   rm *.md (tranne README_NEW.md)
   ```

## 🌟 Funzionalità Avanzate

### Aggiornamento Prezzi Automatico

```bash
curl -X POST http://localhost:3001/api/portfolios/YOUR_ID/update-prices
```

Recupera prezzi aggiornati da Yahoo Finance per tutti gli asset nel portafoglio.

### Performance Mensili Live

```bash
curl "http://localhost:3001/api/portfolios/YOUR_ID/monthly-performance-live?months=12"
```

Calcola performance mensili on-demand senza salvare dati.

### Target Allocation

Imposta e monitora obiettivi di allocazione:

```json
{
  "portfolio_id": "uuid",
  "allocation_name": "Moderato",
  "target_azionario": 65.00,
  "target_obbligazionario": 30.00,
  "target_monetario": 5.00,
  "target_oro": 0.00,
  "target_crypto": 0.00
}
```

## 🔐 Sicurezza

- Usa variabili d'ambiente per credenziali sensibili
- Non committare file `.env` con password reali
- Abilita SSL per PostgreSQL in produzione
- Implementa autenticazione JWT (TODO)

## 📚 Risorse

- [Node.js Documentation](https://nodejs.org/docs/)
- [PostgreSQL Documentation](https://www.postgresql.org/docs/)
- [Express.js Guide](https://expressjs.com/)
- [Yahoo Finance API](https://www.yahoofinanceapi.com/)

## 🤝 Contributi

Per contribuire al progetto:

1. Fork del repository
2. Crea un branch per la tua feature (`git checkout -b feature/AmazingFeature`)
3. Commit delle modifiche (`git commit -m 'Add AmazingFeature'`)
4. Push al branch (`git push origin feature/AmazingFeature`)
5. Apri una Pull Request

## 📝 Licenza

Questo progetto è distribuito sotto licenza MIT.

## 📧 Supporto

Per problemi, domande o richieste:

- Apri un Issue su GitHub
- Consulta questa documentazione
- Verifica i log del server (`console.log`)

---

**Made with ❤️ using Node.js, PostgreSQL, and TypeScript-like Architecture**

*Versione: 2.0 - Rifattorizzato Novembre 2025*
