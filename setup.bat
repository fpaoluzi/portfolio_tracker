@echo off
echo ============================================
echo Portfolio Tracker - Setup Automatico
echo ============================================
echo.

REM Verifica Node.js
where node >nul 2>nul
if %errorlevel% neq 0 (
    echo [ERRORE] Node.js non trovato!
    echo Scarica da: https://nodejs.org/
    pause
    exit /b 1
)

echo [OK] Node.js trovato: 
node --version
echo.

REM Verifica PostgreSQL
where psql >nul 2>nul
if %errorlevel% neq 0 (
    echo [ERRORE] PostgreSQL non trovato!
    echo Assicurati che PostgreSQL sia installato e nel PATH
    pause
    exit /b 1
)

echo [OK] PostgreSQL trovato
echo.

echo ============================================
echo Step 1: Setup Database
echo ============================================
echo.

REM Crea database
echo Creazione database 'finance'...
psql -U postgres -h localhost -c "CREATE DATABASE finance;" 2>nul
if %errorlevel% equ 0 (
    echo [OK] Database creato
) else (
    echo [INFO] Database già esistente
)
echo.

REM Esegui schema
echo Esecuzione schema SQL...
cd backend
psql -U postgres -h localhost -d finance -f schema.sql
if %errorlevel% neq 0 (
    echo [ERRORE] Errore nell'esecuzione dello schema
    pause
    exit /b 1
)
echo [OK] Schema eseguito con successo
echo.

echo ============================================
echo Step 2: Installazione Dipendenze
echo ============================================
echo.

echo Installazione npm packages...
call npm install
if %errorlevel% neq 0 (
    echo [ERRORE] Errore installazione dipendenze
    pause
    exit /b 1
)
echo [OK] Dipendenze installate
echo.

echo ============================================
echo Step 3: Import Dati Excel
echo ============================================
echo.

if exist Investment.xlsm (
    echo [OK] File Excel trovato: Investment.xlsm
    echo Importazione dati in corso...
    node import.js Investment.xlsm
    if %errorlevel% neq 0 (
        echo [ERRORE] Errore durante l'import
        pause
        exit /b 1
    )
    echo [OK] Import completato
) else (
    echo [WARNING] File Investment.xlsm non trovato
    echo Copia il file nella cartella backend e riesegui:
    echo    npm run import
)
echo.

echo ============================================
echo Setup Completato!
echo ============================================
echo.
echo Per avviare il server:
echo    cd backend
echo    npm start
echo.
echo Server API: http://localhost:3001
echo Health check: http://localhost:3001/api/health
echo.
pause
