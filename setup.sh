#!/bin/bash

echo "============================================"
echo "Portfolio Tracker - Setup Automatico"
echo "============================================"
echo ""

# Verifica Node.js
if ! command -v node &> /dev/null; then
    echo "[ERRORE] Node.js non trovato!"
    echo "Scarica da: https://nodejs.org/"
    exit 1
fi

echo "[OK] Node.js trovato: $(node --version)"
echo ""

# Verifica PostgreSQL
if ! command -v psql &> /dev/null; then
    echo "[ERRORE] PostgreSQL non trovato!"
    echo "Installa PostgreSQL o aggiungi psql al PATH"
    exit 1
fi

echo "[OK] PostgreSQL trovato"
echo ""

echo "============================================"
echo "Step 1: Setup Database"
echo "============================================"
echo ""

# Crea database
echo "Creazione database 'finance'..."
psql -U postgres -h localhost -c "CREATE DATABASE finance;" 2>/dev/null
if [ $? -eq 0 ]; then
    echo "[OK] Database creato"
else
    echo "[INFO] Database già esistente"
fi
echo ""

# Esegui schema
echo "Esecuzione schema SQL..."
cd backend
psql -U postgres -h localhost -d finance -f schema.sql
if [ $? -ne 0 ]; then
    echo "[ERRORE] Errore nell'esecuzione dello schema"
    exit 1
fi
echo "[OK] Schema eseguito con successo"
echo ""

echo "============================================"
echo "Step 2: Installazione Dipendenze"
echo "============================================"
echo ""

echo "Installazione npm packages..."
npm install
if [ $? -ne 0 ]; then
    echo "[ERRORE] Errore installazione dipendenze"
    exit 1
fi
echo "[OK] Dipendenze installate"
echo ""

echo "============================================"
echo "Step 3: Import Dati Excel"
echo "============================================"
echo ""

if [ -f "Investment.xlsm" ]; then
    echo "[OK] File Excel trovato: Investment.xlsm"
    echo "Importazione dati in corso..."
    node import.js Investment.xlsm
    if [ $? -ne 0 ]; then
        echo "[ERRORE] Errore durante l'import"
        exit 1
    fi
    echo "[OK] Import completato"
else
    echo "[WARNING] File Investment.xlsm non trovato"
    echo "Copia il file nella cartella backend e riesegui:"
    echo "   npm run import"
fi
echo ""

echo "============================================"
echo "Setup Completato!"
echo "============================================"
echo ""
echo "Per avviare il server:"
echo "   cd backend"
echo "   npm start"
echo ""
echo "Server API: http://localhost:3001"
echo "Health check: http://localhost:3001/api/health"
echo ""
