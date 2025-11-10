@echo off
setlocal ENABLEDELAYEDEXPANSION

:: Imposta la porta da cercare
set PORTA=3000

:: Imposta il percorso del file di blocco da cancellare
set LOCK_FILE_PATH=C:\workspaceai\portfolio-tracker\frontend\.next\dev

echo.
echo === Preparazione (Cancellazione file lock) ===
echo.

:: 1. CANCELLAZIONE DEL FILE DI BLOCCO DI NEXT.JS (se esiste)
if exist "%LOCK_FILE_PATH%\lock" (
    del "%LOCK_FILE_PATH%\lock"
    echo Successo: File lock cancellato in "%LOCK_FILE_PATH%"
) else (
    echo Avviso: Nessun file lock trovato da cancellare.
)

echo.
echo === Ricerca e terminazione processi sulla porta %PORTA% ===
echo.

:: 2. RICERCA E CANCELLAZIONE DEI PROCESSI SULLA PORTA
:: netstat -ano: mostra tutte le connessioni (-a), in formato numerico (-n) e il PID (-o).
for /f "tokens=5" %%a in ('netstat -ano ^| findstr :%PORTA% ^| findstr LISTENING') do (
    set PID=%%a

    :: Controlla se il PID e' stato assegnato e non e' vuoto
    if not "!PID!"=="" (
        
        echo Trovato processo in ascolto sulla porta %PORTA%. PID: !PID!
        
        :: Visualizza il nome del processo (opzionale, per informazione)
        tasklist /svc /FI "PID eq !PID!" | findstr /v "Immagine" 2>nul

        :: Termina il processo forzatamente (/F)
        taskkill /PID !PID! /F 2>nul
        
        :: Verifica se taskkill ha avuto successo (ERRORLEVEL 0 significa successo)
        if errorlevel 1 (
            echo ERRORE: Impossibile terminare il processo !PID!. Controlla i permessi.
        ) else (
            echo SUCCESS: Processo !PID! terminato.
        )
        
    )
)

echo.
echo === Operazione completata. ===
echo.

endlocal
pause