# 🔄 Guida alla Migrazione - Backend Rifattorizzato

Questa guida ti aiuterà a migrare dal vecchio backend monolitico (`server.js`) al nuovo backend modulare e ben strutturato.

## 📌 Cosa è Cambiato

### Prima (Monolitico)
```
backend/
├── server.js                (1500+ righe, tutto in un file)
├── schema.sql
├── add-asset-metrics.sql
├── add-factsheet-url.sql
├── apply-columns.sql
├── create-monthly-performance.sql
└── update-positions-view.sql
```

### Dopo (Modulare)
```
backend/
├── src/
│   ├── config/              # Configurazioni centralizzate
│   │   ├── database.js
│   │   ├── upload.js
│   │   └── server.js
│   ├── controllers/         # Logica business separata per entità
│   │   ├── portfolioController.js
│   │   ├── assetController.js
│   │   ├── transactionController.js
│   │   ├── positionController.js
│   │   ├── targetAllocationController.js
│   │   └── priceUpdateController.js
│   ├── routes/              # Routes organizzate
│   │   ├── index.js
│   │   ├── portfolioRoutes.js
│   │   ├── assetRoutes.js
│   │   └── ...
│   └── utils/               # Funzioni utility riutilizzabili
│       ├── yahooFinance.js
│       └── calculations.js
├── server-new.js            # Entry point pulito (~60 righe)
└── finance_schema.sql       # Schema unificato

## ✅ Vantaggi del Refactoring

1. **Manutenibilità**: Codice organizzato per funzionalità
2. **Testabilità**: Ogni controller può essere testato indipendentemente
3. **Scalabilità**: Facile aggiungere nuove funzionalità
4. **Leggibilità**: File piccoli e focalizzati (~100-200 righe)
5. **Riusabilità**: Utility functions condivise
6. **DRY (Don't Repeat Yourself)**: Configurazioni centralizzate

## 🚀 Procedura di Migrazione

### Step 1: Backup Completo

```bash
# Backup database
pg_dump -U postgres finance > backup_pre_refactor_$(date +%Y%m%d).sql

# Backup codice
cd /path/to/portfolio-tracker
tar -czf backup_code_$(date +%Y%m%d).tar.gz backend/

# Oppure con Git
git add .
git commit -m "Pre-refactor backup"
git tag pre-refactor-backup
```

### Step 2: Verifica Database

```bash
# Controlla che il database sia aggiornato
psql -U postgres -d finance

-- Verifica tabelle esistenti
\dt

-- Verifica viste
\dv

-- Esci
\q
```

Se manca qualche tabella (es. `monthly_position_performance`), applica lo schema unificato:

```bash
psql -U postgres -d finance -f backend/finance_schema.sql
```

### Step 3: Test Nuovo Server

#### A. Installa dipendenze (se necessario)

```bash
cd backend
npm install
```

#### B. Avvia nuovo server

```bash
# Termina il vecchio server se è in esecuzione (Ctrl+C)

# Avvia il nuovo
node server-new.js
```

Dovresti vedere:
```
╔═══════════════════════════════════════════╗
║   Portfolio Tracker API Server           ║
║   http://localhost:3001                  ║
║                                           ║
║   Database: PostgreSQL                    ║
║   Host: localhost:5432                    ║
║   Database: finance                       ║
║   Status: Refactored & Modular ✅         ║
╚═══════════════════════════════════════════╝
```

#### C. Test Endpoints Critici

```bash
# Health check
curl http://localhost:3001/api/health

# Lista portfolios
curl http://localhost:3001/api/portfolios

# Lista assets
curl http://localhost:3001/api/assets

# Posizioni (sostituisci YOUR_PORTFOLIO_ID)
curl http://localhost:3001/api/portfolios/YOUR_PORTFOLIO_ID/positions

# Performance
curl http://localhost:3001/api/portfolios/YOUR_PORTFOLIO_ID/performance
```

Se tutti gli endpoint rispondono correttamente, la migrazione è riuscita! ✅

### Step 4: Aggiorna Script di Avvio

#### A. Modifica package.json

```json
{
  "scripts": {
    "start": "node server-new.js",
    "dev": "nodemon server-new.js",
    "old-server": "node server.js"
  }
}
```

#### B. Testa con npm

```bash
npm start
```

### Step 5: Rimuovi File Obsoleti

⚠️ **ATTENZIONE**: Esegui solo dopo aver verificato che tutto funziona!

```bash
cd backend

# Rinomina vecchio server (non eliminarlo subito)
mv server.js server.old.js

# Rinomina nuovo server come principale
mv server-new.js server.js

# Rimuovi file SQL obsoleti (ora unificati in finance_schema.sql)
rm add-asset-metrics.sql
rm add-factsheet-url.sql
rm apply-columns.sql
rm create-monthly-performance.sql
rm update-positions-view.sql
# Mantieni solo: finance_schema.sql, schema.sql (per reference)
```

```bash
cd ..  # torna alla root

# Rimuovi documentazione obsoleta
rm GUIDA_RAPIDA.md
rm INSTALLAZIONE.md
rm INSTALL.md
rm MIGRATION_GUIDE.md
rm CRUD_FEATURES.md
rm IMPORT_EXCEL_GUIDE.md
rm APPLY_UPDATES.md
rm MONTHLY_PERFORMANCE.md
rm COMPLETED_FEATURES.md

# Rinomina README aggiornato
mv README_NEW.md README.md
```

## 🔍 Mappatura File Vecchi → Nuovi

| File Vecchio | File Nuovo | Note |
|--------------|------------|------|
| `server.js` (righe 1-40) | `src/config/database.js`, `src/config/upload.js` | Configurazioni |
| `server.js` (righe 59-145) | `src/controllers/portfolioController.js` | Portfolio CRUD |
| `server.js` (righe 148-264) | `src/controllers/assetController.js` | Asset CRUD |
| `server.js` (righe 270-284) | `src/controllers/positionController.js` | Posizioni |
| `server.js` (righe 290-418) | `src/controllers/transactionController.js` | Transaction CRUD |
| `server.js` (righe 424-596) | `src/controllers/importController.js` | Import Excel (TODO) |
| `server.js` (righe 602-650) | `src/controllers/portfolioController.js` | Analytics |
| `server.js` (righe 656-738) | `src/controllers/targetAllocationController.js` | Target Allocation |
| `server.js` (righe 741-770) | `src/utils/yahooFinance.js` | Yahoo Finance helper |
| `server.js` (righe 773-916) | `src/controllers/priceUpdateController.js` | Price updates |
| `server.js` (righe 922-1250) | `src/controllers/performanceController.js` | Performance mensili (TODO) |
| `server.js` (righe 1253-1413) | `src/controllers/performanceController.js` | Performance snapshot (TODO) |
| Tutti SQL | `finance_schema.sql` | Schema unificato |
| Tutti MD | `README_NEW.md` → `README.md` | Documentazione unificata |

## 📝 Modifiche da Fare nel Tuo Codice Frontend

Se hai un frontend che chiama le API, **NESSUNA modifica necessaria!**

Gli endpoint sono rimasti identici:

```javascript
// Prima
fetch('http://localhost:3001/api/portfolios')

// Dopo (stesso identico URL!)
fetch('http://localhost:3001/api/portfolios')
```

## 🐛 Problemi Comuni

### Problema 1: "Cannot find module './src/config/database'"

**Soluzione**: Assicurati di essere nella cartella `backend` quando avvii il server:

```bash
cd backend
node server-new.js
```

### Problema 2: Alcuni endpoint restituiscono 501

**Causa**: `importController.js` e `performanceController.js` sono ancora placeholder.

**Soluzione Temporanea**: Usa il vecchio server per queste funzionalità:

```bash
# Per import/performance, usa temporaneamente il vecchio server
node server.old.js
```

**Soluzione Definitiva**: Completa l'implementazione di questi controller (vedi TODO sotto).

### Problema 3: Database connection error

**Causa**: Le credenziali potrebbero essere hard-coded.

**Soluzione**: Usa variabili d'ambiente:

```bash
# Crea file .env nella cartella backend
cat > .env << EOF
DB_HOST=localhost
DB_PORT=5432
DB_NAME=finance
DB_USER=postgres
DB_PASSWORD=your_password_here
PORT=3001
EOF

# Installa dotenv
npm install dotenv

# Modifica src/config/database.js per usare dotenv
```

## ✅ Checklist Migrazione Completa

- [ ] Backup database completato
- [ ] Backup codice completato
- [ ] Schema database aggiornato con `finance_schema.sql`
- [ ] Nuovo server avviato con successo
- [ ] Endpoint `/api/health` funzionante
- [ ] Endpoint `/api/portfolios` funzionante
- [ ] Endpoint `/api/assets` funzionante
- [ ] Endpoint posizioni funzionante
- [ ] Endpoint performance funzionante
- [ ] Test su tutti i portfolio esistenti
- [ ] `package.json` aggiornato
- [ ] File vecchi rinominati/rimossi
- [ ] Documentazione aggiornata
- [ ] Frontend testato (se presente)

## 🚧 TODO: Completare il Refactoring

Alcuni controller sono ancora in sviluppo:

1. **importController.js**: Implementare logica import Excel
   - Estrarre codice da `server.js` righe 424-596
   - Usare `XLSX` library già installata

2. **performanceController.js**: Implementare performance mensili
   - Estrarre codice da `server.js` righe 922-1463
   - Usare utility `calculations.js` per logiche complesse

3. **Error handling middleware**: Creare middleware globale per errori

4. **Logging**: Implementare sistema di logging professionale (Winston/Morgan)

5. **Validation**: Aggiungere validazione input (express-validator)

6. **Authentication**: Implementare JWT per sicurezza API

## 📚 Risorse Aggiuntive

- [Express Best Practices](https://expressjs.com/en/advanced/best-practice-performance.html)
- [Node.js Project Structure](https://github.com/goldbergyoni/nodebestpractices)
- [PostgreSQL Performance Tuning](https://wiki.postgresql.org/wiki/Performance_Optimization)

## 💬 Domande Frequenti

**Q: Posso continuare a usare il vecchio server?**
A: Sì, `server.old.js` rimarrà funzionante, ma si consiglia di migrare al nuovo per beneficiare della struttura modulare.

**Q: Quanto tempo richiede la migrazione?**
A: Con questa guida, 15-30 minuti per una migrazione completa e testata.

**Q: Devo rifare il database?**
A: No! Il database rimane identico. Devi solo assicurarti che lo schema sia aggiornato con `finance_schema.sql`.

**Q: E se qualcosa va storto?**
A: Hai i backup! Ripristina database e codice:
```bash
psql -U postgres -d finance < backup_pre_refactor_YYYYMMDD.sql
tar -xzf backup_code_YYYYMMDD.tar.gz
```

---

**Buona migrazione! 🚀**

*In caso di problemi, consulta README_NEW.md o contatta il supporto.*
