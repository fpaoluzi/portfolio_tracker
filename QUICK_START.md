# ⚡ Quick Start - Portfolio Tracker v2.0

## 🚀 Avvio Veloce (5 minuti)

### Step 1: Database Setup (1 min)

```bash
# Crea database (se non esiste)
psql -U postgres -c "CREATE DATABASE finance;"

# Applica schema
cd backend
psql -U postgres -d finance -f finance_schema.sql
```

### Step 2: Backend Setup (2 min)

```bash
# Installa dipendenze (se necessario)
npm install

# Avvia server
npm start
```

### Step 3: Test (1 min)

```bash
# In un altro terminale
curl http://localhost:3001/api/health
```

Se vedi `{"status":"ok","database":"connected",...}` → **Tutto funziona! ✅**

---

## 📂 Struttura Progetto (Rifattorizzato)

```
portfolio-tracker/
├── backend/
│   ├── src/
│   │   ├── config/              ← Configurazioni
│   │   ├── controllers/         ← Logica business
│   │   ├── routes/              ← Routes API
│   │   └── utils/               ← Utility functions
│   ├── server.js                ← Entry point (60 righe!)
│   ├── finance_schema.sql       ← Schema unificato
│   └── package.json             ← v2.0
├── README.md                    ← Documentazione completa
├── MIGRATION_GUIDE_REFACTOR.md  ← Guida migrazione
└── REFACTORING_SUMMARY.md       ← Riepilogo refactoring
```

---

## 🎯 Funzionalità Principali

| Feature | Endpoint | Status |
|---------|----------|--------|
| Portfolio CRUD | `/api/portfolios` | ✅ Attivo |
| Asset CRUD | `/api/assets` | ✅ Attivo |
| Transazioni CRUD | `/api/transactions` | ✅ Attivo |
| Posizioni Correnti | `/api/portfolios/:id/positions` | ✅ Attivo |
| Performance | `/api/portfolios/:id/performance` | ✅ Attivo |
| Allocation | `/api/portfolios/:id/allocation` | ✅ Attivo |
| Aggiorna Prezzi | `/api/portfolios/:id/update-prices` | ✅ Attivo |
| Target Allocation | `/api/target-allocations/:id` | ✅ Attivo |
| Import Excel | `/api/import/excel` | 🚧 In sviluppo |
| Performance Mensili | `/api/portfolios/:id/monthly-performance-live` | 🚧 In sviluppo |

---

## 📖 Comandi Utili

```bash
# Avvia server (produzione)
npm start

# Avvia server (sviluppo con auto-reload)
npm run dev

# Import Excel
npm run import

# Setup database
npm run setup

# Avvia vecchio server (backup)
npm run old-server
```

---

## 🆘 Aiuto Rapido

### Server non si avvia
```bash
cd backend
rm -rf node_modules
npm install
npm start
```

### Database non si connette
```bash
# Verifica PostgreSQL attivo
psql -U postgres -l
```

### Porta 3001 occupata
```bash
# Windows
netstat -ano | findstr :3001
# Killa il processo o cambia porta in src/config/server.js
```

---

## 📚 Documentazione

- [README.md](README.md) - Documentazione completa con tutti gli endpoint
- [MIGRATION_GUIDE_REFACTOR.md](MIGRATION_GUIDE_REFACTOR.md) - Guida per migrare dal vecchio codice
- [REFACTORING_SUMMARY.md](REFACTORING_SUMMARY.md) - Dettagli del refactoring

---

## ✅ Checklist Prima di Iniziare

- [ ] PostgreSQL installato e attivo
- [ ] Node.js 16+ installato
- [ ] Database `finance` creato
- [ ] Schema `finance_schema.sql` applicato
- [ ] `npm install` completato
- [ ] Server avviato con successo
- [ ] `/api/health` risponde OK

---

**Tutto pronto? Inizia a usare le API! 🎉**

```bash
# Esempi
curl http://localhost:3001/api/portfolios
curl http://localhost:3001/api/assets
curl http://localhost:3001/api/portfolios/YOUR_ID/positions
```

---

*Portfolio Tracker v2.0 - Backend Modulare e Professionale*
