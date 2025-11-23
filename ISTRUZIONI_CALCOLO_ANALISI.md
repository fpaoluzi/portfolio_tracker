## Obiettivo
Raffinare al meglio la parte di analisi della composizione del portafoglio

##Esempio 1: logica da apllicare con selezione di un singolo asset azionario
Seleziono solo l'asset azionario con asset_id c117885f-43f8-4be0-8df2-f6d30a200cca  (eTF MCSI World). Questo asset  risulterebbe avere una composizione percentuale data dalle aziende facendo questa query SELECT holding_name, ROUND((holding_percent*100),2) as percentage FROM public.etf_holdings WHERE ASSET_ID='c117885f-43f8-4be0-8df2-f6d30a200cca' order by holding_symbol ASC.  riporto i valori 
- "Apple"	4.42
- "Amazon.com, Inc."	2.79
- "Broadcom"	1.70
- "Alphabet, Inc. C"	1.34
- "Alphabet, Inc. A"	1.58
- "JPMorgan Chase & Co."	1.07
- "Meta Platforms"	2.05
- "Microsoft"	4.56
- "NVIDIA Corp."	5.42
- "Tesla"	1.23.
Questi valori se sommati tutti insieme dovrebbero avere un peso complessivo di circa il 27% rispetto al totale  di questo etf. Quindi come categoria altri dovrebbe essere presente la restante parte del 100%. Ovvero 100% - 27%. Questo è un esempio concreta di logica che devi applicare per le analisi di holding, geografia, settori e asset allocation
Questo esempio è facile da applicare perchè il valore del portafoglio da analizzare comprende un solo asset selezionato. 


##Esempio 1: logica da apllicare con selezione di due o più asset azionario
Seleziono l'asset azionario con asset_id c117885f-43f8-4be0-8df2-f6d30a200cca  (eTF MCSI World) e seleziono l'asset con assed_id b46bba4b-525d-483d-bf4e-f195bde3d6bc (Nasdaq 100) 
Per il primo asset la composizione percentuale è data dalle aziende facendo questa query SELECT holding_name, ROUND((holding_percent*100),2) as percentage FROM public.etf_holdings WHERE ASSET_ID='c117885f-43f8-4be0-8df2-f6d30a200cca' order by holding_symbol ASC.  Per cui riporto i valori 

- "Apple"	4.42
- "Amazon.com, Inc."	2.79
- "Broadcom"	1.70
- "Alphabet, Inc. C"	1.34
- "Alphabet, Inc. A"	1.58
- "JPMorgan Chase & Co."	1.07
- "Meta Platforms"	2.05
- "Microsoft"	4.56
- "NVIDIA Corp."	5.42
- "Tesla"	1.23.

Per il secondo asset la composizione percentuale è data dalle aziende facendo questa query SELECT holding_name, ROUND((holding_percent*100),2) as percentage FROM public.etf_holdings WHERE ASSET_ID='b46bba4b-525d-483d-bf4e-f195bde3d6bc' order by holding_symbol ASC.  Per cui riporto i valori 

- "Apple"	6.32
- "Amazon.com, Inc."	3.94
- "Broadcom"	2.55
- "Berkshire Hathaway, Inc."	1.68
- "Alphabet, Inc. C"	1.83
- "Alphabet, Inc. A"	2.26
- "Meta Platforms"	2.92
- "Microsoft"	6.86
- "NVIDIA Corp."	7.74
- "Tesla"	1.70

Questi valori se sommati tutti insieme dovrebbero avere un peso complessivo di circa il 38% rispetto al totale di questo etf. Quindi come categoria altri dovrebbe essere presente la restante parte del 100%. Ovvero 100% - 38%. 
Questo è un esempio concreta di logica che devi applicare per le analisi di holding, geografia, settori e asset allocation in base agli asset selezionati

#Logica più complicata perchè ora il valore del portafoglio da considerare dovrebbe essere dato dalla somma del valore del valore dei due asset selezionati. Quindi ricavato da questa query
SELECT SUM(current_value) as selected_portafolio_total  FROM public.v_current_positions where asset_id IN('c117885f-43f8-4be0-8df2-f6d30a200cca','b46bba4b-525d-483d-bf4e-f195bde3d6bc')

quindi dovrebbe essere ricavata da una query simile

SELECT 
    asset_id,
    current_value,
    
    -- 1. Questo calcola la somma totale DEI SOLI ELEMENTI FILTRATI nella WHERE
    SUM(current_value) OVER() as totale_portafoglio,

    -- 2. Calcolo del peso decimale (es. 0.3521)
    -- Casting a NUMERIC per sicurezza sui decimali
    (current_value / SUM(current_value) OVER()) as peso_decimale,

    -- 3. Calcolo percentuale formattata (es. 35.21)
    ROUND(
        (current_value / SUM(current_value) OVER()) * 100, 
    2) as weight_percentage

FROM public.v_current_positions 
WHERE asset_id IN (
    'c117885f-43f8-4be0-8df2-f6d30a200cca', 
    'b46bba4b-525d-483d-bf4e-f195bde3d6bc'
);

e verrebbe fuori delle info di questo tipo 

"c117885f-43f8-4be0-8df2-f6d30a200cca"	43099.930000000000	100952.440000000000	0.42693301915238502408	42.69
"b46bba4b-525d-483d-bf4e-f195bde3d6bc"	57852.510000000000	100952.440000000000	0.57306698084761497592	57.31

Ora devi moltiplicare il peso che l'ETF ha nel tuo portafoglio per il peso che la singola azione ha dentro l'ETF.
Formula logica:$$Peso_{Reale} = (Peso_{ETF\_su\_Totale} \times Peso_{Azione\_in\_ETF})
 
per farlo un modo leggibile sarebbe usare

WITH selected_portfolio_weight AS (
    -- 1. CALCOLO IL PESO DEGLI ASSET (ETF) SUL TOTALE
    -- Questa è la query che abbiamo costruito nel passaggio precedente
    SELECT 
        asset_id,
        current_value,
        -- Calcolo il peso decimale dell'ETF nel portafoglio (es. 0.30 per 30%)
        (current_value / SUM(current_value) OVER()) as peso_etf_nel_portafoglio
    FROM public.v_current_positions 
    WHERE asset_id IN (
        'c117885f-43f8-4be0-8df2-f6d30a200cca', 
        'b46bba4b-525d-483d-bf4e-f195bde3d6bc'
    )
)
SELECT
    h.holding_symbol,
	h.holding_name,
    ROUND(
        (p.peso_etf_nel_portafoglio * h.holding_percent) * 100, 
    4) as real_weight_in_selected_portfolio

FROM public.etf_holdings h
JOIN selected_portfolio_weight p ON h.asset_id = p.asset_id
group by holding_symbol,h.holding_name,real_weight_in_selected_portfolio
ORDER BY real_weight_in_selected_portfolio DESC; 

Ricorda che tuta la parte restante deve essere trattata come Altro e normalizzata rispetto al 100%
Questa logica deve essere applicata per le analisi di holding, geografia, settori e asset allocation settori e asset allocation in base agli asset selezionati

##NOTA se seleziono tutti gli asset azionari logicamente il totale sarà su tutta la parte azionaria.

##Riepilogo su front end 
Graficamente oltre ai grafici esistenti che danno il dettaglio delle composizioni.  Vanno create in alto sezioni che riportino il valore totale del portafoglio selezionato e quanto ogni asset pesa in percentuale rispetto al totale selezionato.

