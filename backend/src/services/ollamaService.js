// ============================================
// OLLAMA SERVICE
// Integrazione con Ollama locale per l'estrazione dati tramite LLM
// ============================================

const { Ollama } = require('ollama');

// Inizializza il client Ollama (assume che Ollama sia in esecuzione su localhost:11434)
const ollama = new Ollama({
  host: process.env.OLLAMA_HOST || 'http://localhost:11434',
});

/**
 * Estrae dati strutturati da HTML usando Ollama
 * @param {string} html - HTML della pagina da analizzare
 * @param {string} isin - ISIN dell'ETF per contesto
 * @param {string} model - Modello Ollama da usare (default: llama3)
 * @returns {Promise<Object>} - Dati estratti in formato JSON
 */
async function extractETFDataFromHTML(html, isin, model = 'deepseek-v3.1:671b-cloud') {
  try {
    // Log dimensione HTML
    const htmlChars = html.length;
    const estimatedTokens = Math.ceil(htmlChars / 4); // Stima: ~4 chars per token
    console.log(`[Ollama] HTML size: ${htmlChars} chars (~${estimatedTokens} tokens)`);

    const prompt = `Estrai dati strutturati da JustETF per ISIN: ${isin}

Ricevi 3 sezioni di testo:
- HOLDINGS: lista partecipazioni principali
- SECTORS: suddivisione settori
- COUNTRIES: distribuzione geografica

OUTPUT RICHIESTO - JSON puro (no markdown, no testo extra):
{
  "holdings": [
    {
      "holding_symbol": "AAPL",
      "holding_name": "Apple Inc.",
      "holding_percent": 0.0456,
      "rank_position": 1
    }
  ],
  "sectors": [
    {
      "sector_name": "Informatica",
      "weight_percent": 0.245
    }
  ],
  "regions": [
    {
      "region_name": "Stati Uniti",
      "weight_percent": 0.65
    }
  ],
  "allocation": [
    {
      "allocation_type": "Equity",
      "weight_percent": 1.0
    }
  ],
  "ter": 0.0020,
  "distribution_policy": "Accumulating"
}

REGOLE:
- holding_percent e weight_percent: formato decimale (4.56% = 0.0456)
- allocation_type: solo "Equity", "Bond", "Cash", "Other", "Commodity", "Real Estate"
- distribution_policy: solo "Accumulating" o "Distributing"
- Se dato assente: array vuoto [] o null
- Estrai tutte le holdings visibili (max 15)
- IMPORTANTE: usa SEMPRE nomi settori in ITALIANO:
  Informatica, Finanza, Salute, Beni voluttuari, Beni di prima necessità, Telecomunicazioni, Industria, Materie prime, Energia, Servizi di pubblica utilità, Immobiliare
- IMPORTANTE: usa SEMPRE nomi regioni in ITALIANO:
  Stati Uniti, Regno Unito, Giappone, Cina, Germania, Francia, Svizzera, Paesi Bassi, Canada, Australia, Italia, Spagna, Svezia, Danimarca, India, Hong Kong, Singapore

TESTO DA ANALIZZARE:
${html}`;

    console.log(`[Ollama] Chiamata al modello ${model} per estrazione dati...`);

    const response = await ollama.chat({
      model: model,
      messages: [
        {
          role: 'user',
          content: prompt,
        },
      ],
      stream: false,
      options: {
        temperature: 0.1, // Bassa temperatura per output più deterministico
        num_predict: 4096, // Limite di token per la risposta
      },
    });

    console.log('[Ollama] Risposta ricevuta, parsing JSON...');

    // Estrai il contenuto della risposta
    let content = response.message.content.trim();

    // Rimuovi eventuali markdown code blocks
    content = content.replace(/```json\n?/g, '').replace(/```\n?/g, '').trim();

    // Parse JSON
    const extractedData = JSON.parse(content);

    console.log('[Ollama] Dati estratti con successo');
    console.log(`  - Holdings: ${extractedData.holdings?.length || 0}`);
    console.log(`  - Sectors: ${extractedData.sectors?.length || 0}`);
    console.log(`  - Regions: ${extractedData.regions?.length || 0}`);
    console.log(`  - Allocation: ${extractedData.allocation?.length || 0}`);

    return extractedData;
  } catch (error) {
    console.error('[Ollama] Errore durante estrazione dati:', error.message);
    throw new Error(`Ollama extraction error: ${error.message}`);
  }
}

/**
 * Verifica se Ollama è disponibile e il modello specificato è installato
 * @param {string} model - Nome del modello da verificare
 * @returns {Promise<boolean>} - true se disponibile
 */
async function checkOllamaAvailability(model = 'deepseek-v3.1:671b-cloud') {
  try {
    const models = await ollama.list();
    const modelExists = models.models.some(m => m.name.includes(model));

    if (!modelExists) {
      console.warn(`[Ollama] Modello ${model} non trovato. Modelli disponibili:`,
        models.models.map(m => m.name).join(', '));
      return false;
    }

    console.log(`[Ollama] Modello ${model} disponibile`);
    return true;
  } catch (error) {
    console.error('[Ollama] Errore connessione:', error.message);
    return false;
  }
}

module.exports = {
  extractETFDataFromHTML,
  checkOllamaAvailability,
};
