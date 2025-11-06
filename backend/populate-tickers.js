// ============================================
// SCRIPT PER POPOLARE I TICKER DAGLI ISIN
// Cerca su: Milano (.MI) -> Francoforte (.DE) -> Londra (.L)
// ============================================

const { Pool } = require('pg');
const axios = require('axios');

const pool = new Pool({
  host: 'localhost',
  port: 5432,
  database: 'finance',
  user: 'postgres',
  password: 'postgres',
});

// Helper function per cercare ticker tramite nome o ISIN
async function searchTicker(query) {
  try {
    const url = `https://query2.finance.yahoo.com/v1/finance/search`;
    const response = await axios.get(url, {
      params: {
        q: query,
        quotesCount: 10,
        newsCount: 0,
        enableFuzzyQuery: false,
        quotesQueryId: 'tss_match_phrase_query'
      },
      headers: {
        'User-Agent': 'Mozilla/5.0'
      },
      timeout: 10000
    });

    const quotes = response.data?.quotes || [];
    return quotes.filter(q =>
      q.quoteType === 'ETF' ||
      q.quoteType === 'EQUITY' ||
      q.quoteType === 'MUTUALFUND'
    );
  } catch (error) {
    console.error(`    Errore ricerca: ${error.message}`);
    return [];
  }
}

// Helper function per verificare se un ticker esiste su Yahoo Finance
async function checkTickerExists(ticker) {
  try {
    const url = `https://query1.finance.yahoo.com/v8/finance/chart/${ticker}`;
    const response = await axios.get(url, {
      params: {
        interval: '1d',
        range: '1d'
      },
      headers: {
        'User-Agent': 'Mozilla/5.0'
      },
      timeout: 5000
    });

    const result = response.data?.chart?.result?.[0];
    if (result && result.meta && result.meta.regularMarketPrice) {
      return {
        exists: true,
        price: result.meta.regularMarketPrice,
        currency: result.meta.currency,
        name: result.meta.longName || result.meta.shortName,
        exchange: result.meta.exchangeName
      };
    }
    return { exists: false };
  } catch (error) {
    return { exists: false };
  }
}

// Cerca ticker per ISIN su diversi mercati
async function findTickerForISIN(isin, assetName) {
  console.log(`\nCerco ticker per ${assetName} (${isin})...`);

  // Priorità mercati
  const marketPriority = ['.MI', '.DE', '.L', '.PA', '.AS'];

  // 1. Prima strategia: Cerca per ISIN
  console.log(`  Strategia 1: Ricerca per ISIN "${isin}"...`);
  let results = await searchTicker(isin);

  if (results.length > 0) {
    console.log(`  Trovati ${results.length} risultati per ISIN`);

    // Filtra per priorità mercato
    for (const marketSuffix of marketPriority) {
      const match = results.find(r => r.symbol && r.symbol.endsWith(marketSuffix));
      if (match) {
        const info = await checkTickerExists(match.symbol);
        if (info.exists) {
          console.log(`  ✓ TROVATO: ${match.symbol} - ${info.price} ${info.currency}`);
          console.log(`    Exchange: ${info.exchange}`);
          console.log(`    Nome: ${info.name}`);
          return {
            ticker: match.symbol,
            market: info.exchange,
            price: info.price,
            currency: info.currency
          };
        }
      }
    }

    // Se nessun match su mercati prioritari, prendi il primo valido
    for (const result of results) {
      const info = await checkTickerExists(result.symbol);
      if (info.exists) {
        console.log(`  ✓ TROVATO: ${result.symbol} - ${info.price} ${info.currency}`);
        console.log(`    Exchange: ${info.exchange}`);
        return {
          ticker: result.symbol,
          market: info.exchange,
          price: info.price,
          currency: info.currency
        };
      }
      await new Promise(resolve => setTimeout(resolve, 300));
    }
  }

  // 2. Seconda strategia: Cerca per nome asset
  console.log(`  Strategia 2: Ricerca per nome "${assetName}"...`);
  results = await searchTicker(assetName);

  if (results.length > 0) {
    console.log(`  Trovati ${results.length} risultati per nome`);

    // Filtra per priorità mercato
    for (const marketSuffix of marketPriority) {
      const match = results.find(r => r.symbol && r.symbol.endsWith(marketSuffix));
      if (match) {
        const info = await checkTickerExists(match.symbol);
        if (info.exists) {
          console.log(`  ✓ TROVATO: ${match.symbol} - ${info.price} ${info.currency}`);
          console.log(`    Exchange: ${info.exchange}`);
          console.log(`    Nome: ${info.name}`);
          return {
            ticker: match.symbol,
            market: info.exchange,
            price: info.price,
            currency: info.currency
          };
        }
      }
    }

    // Prendi il primo risultato valido
    const firstResult = results[0];
    const info = await checkTickerExists(firstResult.symbol);
    if (info.exists) {
      console.log(`  ✓ TROVATO: ${firstResult.symbol} - ${info.price} ${info.currency}`);
      console.log(`    Exchange: ${info.exchange}`);
      return {
        ticker: firstResult.symbol,
        market: info.exchange,
        price: info.price,
        currency: info.currency
      };
    }
  }

  console.log(`  ✗ Ticker non trovato`);
  return null;
}

async function populateTickers() {
  try {
    console.log('╔═══════════════════════════════════════════╗');
    console.log('║  POPOLAZIONE TICKER AUTOMATICA            ║');
    console.log('║  Milano -> Francoforte -> Londra          ║');
    console.log('╚═══════════════════════════════════════════╝\n');

    // Recupera tutti gli asset senza ticker
    const result = await pool.query(
      `SELECT asset_id, isin, name, ticker
       FROM assets
       WHERE is_active = true
       ORDER BY name`
    );

    console.log(`Trovati ${result.rows.length} asset da processare\n`);

    const stats = {
      total: result.rows.length,
      found: 0,
      notFound: 0,
      alreadyHasTicker: 0,
      updated: []
    };

    for (const asset of result.rows) {
      // Salta se ha già un ticker valido
      if (asset.ticker && !asset.ticker.includes('undefined')) {
        console.log(`${asset.name}: Ha già ticker (${asset.ticker})`);
        stats.alreadyHasTicker++;
        continue;
      }

      if (!asset.isin) {
        console.log(`${asset.name}: Nessun ISIN disponibile`);
        stats.notFound++;
        continue;
      }

      // Cerca ticker
      const tickerInfo = await findTickerForISIN(asset.isin, asset.name);

      if (tickerInfo) {
        // Aggiorna database
        await pool.query(
          'UPDATE assets SET ticker = $1, updated_at = CURRENT_TIMESTAMP WHERE asset_id = $2',
          [tickerInfo.ticker, asset.asset_id]
        );

        stats.found++;
        stats.updated.push({
          name: asset.name,
          isin: asset.isin,
          ticker: tickerInfo.ticker,
          market: tickerInfo.market,
          price: tickerInfo.price,
          currency: tickerInfo.currency
        });
      } else {
        stats.notFound++;
      }

      // Pausa tra asset
      await new Promise(resolve => setTimeout(resolve, 1000));
    }

    // Stampa riepilogo
    console.log('\n╔═══════════════════════════════════════════╗');
    console.log('║  RIEPILOGO                                ║');
    console.log('╚═══════════════════════════════════════════╝\n');
    console.log(`Totale asset:              ${stats.total}`);
    console.log(`Asset già con ticker:      ${stats.alreadyHasTicker}`);
    console.log(`Ticker trovati e salvati:  ${stats.found}`);
    console.log(`Ticker non trovati:        ${stats.notFound}`);

    if (stats.updated.length > 0) {
      console.log('\n📝 Ticker aggiornati:\n');
      stats.updated.forEach(item => {
        console.log(`  ${item.name}`);
        console.log(`    ISIN:   ${item.isin}`);
        console.log(`    Ticker: ${item.ticker} (${item.market})`);
        console.log(`    Prezzo: ${item.price} ${item.currency}`);
        console.log('');
      });
    }

    // Chiudi connessione
    await pool.end();
    console.log('✅ Script completato\n');

  } catch (error) {
    console.error('❌ Errore:', error);
    await pool.end();
    process.exit(1);
  }
}

// Esegui script
populateTickers();
