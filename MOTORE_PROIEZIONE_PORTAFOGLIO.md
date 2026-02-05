Ecco un documento di requisiti tecnici strutturato in **Markdown**, pronto per essere utilizzato come specifica (Prompt o Documento di Design) per lo sviluppo di un'applicazione tramite AI o da un team di programmatori.

# Documento di Requisiti: Motore di Proiezione Portafoglio Dinamico (DPPE)

## 1. Obiettivo del Sistema

Sviluppare un algoritmo di calcolo finanziario capace di proiettare il valore di un portafoglio d'investimento su un orizzonte temporale definito ( anni), integrando variabili che mutano annualmente: versamenti, rendimenti, inflazione e tassazione sulle plusvalenze.

---

## 2. Definizione delle Variabili di Input

Il sistema deve accettare una serie temporale di dati per ogni anno  del periodo di proiezione:

| Variabile | Simbolo | Descrizione |
| --- | --- | --- |
| **Capitale Iniziale** |  | Valore del portafoglio al tempo zero. |
| **Contribuzione Annua** |  | Flusso di cassa immesso nell'anno . |
| **Rendimento Nominale** |  | Tasso di crescita lordo stimato per l'anno . |
| **Tasso di Inflazione** |  | Tasso di svalutazione monetaria per l'anno . |
| **Aliquota Capital Gain** |  | Percentuale di tassazione sulle plusvalenze per l'anno . |
---

## 3. Logica di Calcolo e Modello Matematico
Il calcolo deve essere eseguito in modo **iterativo**. Per ogni anno , l'applicazione deve seguire rigorosamente questi step:

### Step 1: Calcolo del Valore Lordo Nominale
Il valore all'inizio dell'anno viene incrementato dal contributo annuale e successivamente rivalutato del tasso di rendimento.


### Step 2: Calcolo della Plusvalenza e Tassazione Netta
Il sistema deve distinguere tra capitale versato e rendimento per calcolare la base imponibile.

* **Plusvalenza Maturata ():** 
* **Imposta da pagare ():** 
* **Valore Finale Netto Nominale ():** 

> **Nota Tecnica:** Il calcolo assume il metodo della tassazione alla maturazione (accrual basis). Se il requisito fosse la tassazione solo al termine (realization basis), il calcolo delle tasse andrebbe spostato solo all'ultimo anno della serie.
### Step 3: Attualizzazione (Potere d'Acquisto Reale)

Per riflettere l'impatto dell'inflazione variabile, il valore netto deve essere diviso per il prodotto dei tassi di inflazione cumulati.

---

## 4. Requisiti Funzionali dell'Applicazione

### RF1: Gestione Input Dinamici

* L'utente deve poter inserire i dati in una griglia editabile o caricare un file JSON/CSV.
* Supporto per "valori costanti" (es. applica lo stesso rendimento per tutti gli anni) o "valori puntuali" (es. anno 1: 5%, anno 2: -2%).

### RF2: Elaborazione (Engine)

* L'IA deve generare una funzione che esegua il loop ricorsivo sopra descritto.
* Gestione degli scenari con rendimento negativo (le tasse non vengono applicate o generano minusvalenze, a seconda della complessità fiscale richiesta).

### RF3: Visualizzazione Output

L'applicazione deve restituire:

1. **Tabella Analitica:** Con colonne per Capitale Investito Cumulativo, Valore Nominale, Tasse Pagate, Valore Reale.
2. **Grafico Comparativo:** Un grafico a linee che mostri:
* Curva del Capitale Versato (Lineare/Scalare).
* Curva del Valore Nominale Netto (Esponenziale).
* Curva del Valore Reale (Attualizzato).



---

## 5. Casi d'Uso (Esempio per Test)

* **Scenario A:** Capitale 10k, Versamento 1k/anno, Rendimento 5% fisso, Inflazione 2% fissa, Tasse 26% fisse.
* **Scenario B (Cigno Nero):** Come sopra, ma con Anno 5 che presenta un Rendimento del -15% e Inflazione al 10%.

---

## 6. Prossimi Passi per l'AI

> "Basandoti su questi requisiti, scrivi una classe in Python chiamata `PortfolioSimulator` che includa un metodo `run_projection()` e restituisca un DataFrame di Pandas con i risultati."

---

Ti sembra che questa struttura copra tutte le tue necessità o vuoi aggiungere una sezione specifica sulla **gestione delle minusvalenze** (ovvero quando il rendimento è negativo e "accumuli un credito" fiscale)?