// ============================================
// YAHOO FINANCE UTILITY
// Helper functions for fetching prices from Yahoo Finance
// ============================================

const axios = require('axios');
const yahooFinance = require('yahoo-finance2');

/**
 * Recupera il prezzo corrente da Yahoo Finance
 * @param {string} symbol - Simbolo del ticker (es: "AAPL" o "IE00B4L5Y983.MI")
 * @returns {Promise<Object>} - Oggetto con prezzo e dati correlati
 */
async function getYahooFinancePrice(symbol) {
  try {
    const url = `https://query1.finance.yahoo.com/v8/finance/chart/${symbol}`;
    const response = await axios.get(url, {
      params: {
        interval: '1d',
        range: '1d',
      },
      headers: {
        'User-Agent': 'Mozilla/5.0',
      },
    });

    const result = response.data?.chart?.result?.[0];
    if (!result) return null;

    const quote = result.meta;
    const indicators = result.indicators?.quote?.[0];

    return {
      price: quote.regularMarketPrice,
      open: indicators?.open?.[0],
      high: indicators?.high?.[0],
      low: indicators?.low?.[0],
      volume: indicators?.volume?.[0],
      currency: quote.currency,
    };
  } catch (error) {
    throw new Error(`Yahoo Finance error: ${error.message}`);
  }
}

/**
 * Recupera storico prezzi da Yahoo Finance
 * @param {string} symbol - Simbolo del ticker
 * @param {Date} startDate - Data inizio
 * @param {Date} endDate - Data fine
 * @param {string} interval - Intervallo ('1d', '1mo', ecc.)
 * @returns {Promise<Object>} - Oggetto con array di timestamp e prezzi
 */
async function getYahooFinanceHistory(symbol, startDate, endDate, interval = '1mo') {
  try {
    const period1 = Math.floor(startDate.getTime() / 1000);
    const period2 = Math.floor(endDate.getTime() / 1000);

    const url = `https://query1.finance.yahoo.com/v8/finance/chart/${symbol}`;
    const response = await axios.get(url, {
      params: { period1, period2, interval },
      headers: { 'User-Agent': 'Mozilla/5.0' },
      timeout: 15000,
    });

    return response.data?.chart?.result?.[0] || null;
  } catch (error) {
    throw new Error(`Yahoo Finance history error: ${error.message}`);
  }
}

/**
 * Recupera la composizione completa dell'ETF da Yahoo Finance
 * Include: holdings, sector weights, geographic breakdown, asset allocation, bond data
 * @param {string} symbol - Simbolo del ticker ETF
 * @returns {Promise<Object>} - Oggetto con tutti i dati di composizione disponibili
 */
async function getETFComposition(symbol) {
  try {
    // Usa yahoo-finance2 che gestisce automaticamente l'autenticazione
    const result = await yahooFinance.quoteSummary(symbol, {
      modules: [
        'topHoldings',
        'fundProfile',
        'assetProfile',
        'fundPerformance',
        'defaultKeyStatistics',
        'summaryDetail',
      ],
    });

    if (!result) return null;

    return {
      topHoldings: result.topHoldings || null,
      fundProfile: result.fundProfile || null,
      assetProfile: result.assetProfile || null,
      fundPerformance: result.fundPerformance || null,
      defaultKeyStatistics: result.defaultKeyStatistics || null,
      summaryDetail: result.summaryDetail || null,
    };
  } catch (error) {
    console.error(`Yahoo Finance ETF composition error for ${symbol}:`, error.message);
    throw new Error(`Yahoo Finance ETF composition error: ${error.message}`);
  }
}

/**
 * Estrae e normalizza i top holdings dall'ETF
 * @param {Object} composition - Dati composizione da getETFComposition
 * @returns {Array} - Array di holdings { symbol, name, percent, rank }
 */
function extractTopHoldings(composition) {
  if (!composition?.topHoldings?.holdings) return [];

  return composition.topHoldings.holdings
    .map((holding, index) => ({
      symbol: holding.symbol || null,
      name: holding.holdingName || 'N/A',
      percent: holding.holdingPercent || 0,
      rank: index + 1,
    }))
    .filter((h) => h.percent > 0);
}

/**
 * Estrae e normalizza i sector weights dall'ETF
 * @param {Object} composition - Dati composizione da getETFComposition
 * @returns {Array} - Array di settori { sector, percent }
 */
function extractSectorWeights(composition) {
  if (!composition?.topHoldings?.sectorWeightings) return [];

  const sectorWeightings = composition.topHoldings.sectorWeightings;
  const sectors = [];

  for (const sectorObj of sectorWeightings) {
    for (const [sectorName, weight] of Object.entries(sectorObj)) {
      if (weight && typeof weight === 'object' && 'raw' in weight) {
        sectors.push({
          sector: sectorName,
          percent: weight.raw,
        });
      } else if (typeof weight === 'number') {
        sectors.push({
          sector: sectorName,
          percent: weight,
        });
      }
    }
  }

  return sectors.filter((s) => s.percent > 0);
}

/**
 * Estrae e normalizza la distribuzione geografica dall'ETF
 * @param {Object} composition - Dati composizione da getETFComposition
 * @returns {Array} - Array di regioni { region, percent }
 */
function extractGeographicWeights(composition) {
  if (!composition?.fundProfile?.categoryName) {
    // Fallback: prova a estrarre da altri campi disponibili
    return [];
  }

  // Yahoo Finance non sempre espone dati geografici strutturati
  // Questa funzione può essere estesa quando disponibili
  const regions = [];

  // Cerca in assetProfile per informazioni geografiche
  if (composition.assetProfile?.region) {
    regions.push({
      region: composition.assetProfile.region,
      percent: 1.0, // Default al 100% se non ci sono altri dati
    });
  }

  // Cerca in fundProfile
  if (composition.fundProfile?.categoryName) {
    const categoryName = composition.fundProfile.categoryName;
    // Estrai informazioni geografiche dal nome della categoria
    // Es: "Europe Stock", "US Large-Cap Growth"
    if (categoryName.includes('Europe')) {
      regions.push({ region: 'Europe', percent: 1.0 });
    } else if (categoryName.includes('US') || categoryName.includes('United States')) {
      regions.push({ region: 'United States', percent: 1.0 });
    } else if (categoryName.includes('Asia') || categoryName.includes('Pacific')) {
      regions.push({ region: 'Asia Pacific', percent: 1.0 });
    } else if (categoryName.includes('World') || categoryName.includes('Global')) {
      // Per ETF globali, non abbiamo distribuzione dettagliata
      regions.push({ region: 'Global', percent: 1.0 });
    }
  }

  return regions;
}

/**
 * Estrae e normalizza l'asset allocation dall'ETF
 * @param {Object} composition - Dati composizione da getETFComposition
 * @returns {Array} - Array di asset class { type, percent }
 */
function extractAssetAllocation(composition) {
  const allocation = [];

  // Cerca nei dati topHoldings per equity holdings
  if (composition?.topHoldings?.equityHoldings) {
    const equityData = composition.topHoldings.equityHoldings;

    // Se c'è percentuale di stock
    if (equityData.stockPosition?.raw) {
      allocation.push({
        type: 'Equity',
        percent: equityData.stockPosition.raw,
      });
    }
  }

  // Cerca nei dati topHoldings per bond holdings
  if (composition?.topHoldings?.bondHoldings) {
    const bondData = composition.topHoldings.bondHoldings;

    // Se c'è percentuale di bond
    if (bondData.bondPosition?.raw) {
      allocation.push({
        type: 'Bond',
        percent: bondData.bondPosition.raw,
      });
    }
  }

  // Cerca cash position
  if (composition?.topHoldings?.cashPosition?.raw) {
    allocation.push({
      type: 'Cash',
      percent: composition.topHoldings.cashPosition.raw,
    });
  }

  // Cerca other positions
  if (composition?.topHoldings?.otherPosition?.raw) {
    allocation.push({
      type: 'Other',
      percent: composition.topHoldings.otherPosition.raw,
    });
  }

  return allocation.filter((a) => a.percent > 0);
}

/**
 * Estrae e normalizza i dati sui bond ratings
 * @param {Object} composition - Dati composizione da getETFComposition
 * @returns {Array} - Array di ratings { category, percent }
 */
function extractBondRatings(composition) {
  if (!composition?.topHoldings?.bondRatings) return [];

  const bondRatings = composition.topHoldings.bondRatings;
  const ratings = [];

  // Yahoo Finance può fornire: aa, aaa, a, bbb, bb, b, belowB, us, other
  const ratingMap = {
    aaa: 'AAA',
    aa: 'AA',
    a: 'A',
    bbb: 'BBB',
    bb: 'BB',
    b: 'B',
    belowB: 'Below B',
    us: 'US Government',
    other: 'Not Rated',
  };

  for (const [key, ratingName] of Object.entries(ratingMap)) {
    if (bondRatings[key]?.raw) {
      ratings.push({
        category: ratingName,
        percent: bondRatings[key].raw,
      });
    }
  }

  return ratings.filter((r) => r.percent > 0);
}

/**
 * Estrae e normalizza i dati sulla maturity dei bond
 * @param {Object} composition - Dati composizione da getETFComposition
 * @returns {Array} - Array di maturity ranges { range, percent, avgDuration }
 */
function extractBondMaturity(composition) {
  const maturity = [];

  if (!composition?.defaultKeyStatistics) return maturity;

  const stats = composition.defaultKeyStatistics;

  // Average duration (anni)
  if (stats.threeYearAverageReturn?.raw) {
    // Yahoo Finance non sempre fornisce maturity breakdown dettagliato
    // Usiamo la duration media come indicatore
    const avgDuration = stats.fundInceptionDate?.raw
      ? Math.abs(stats.fundInceptionDate.raw)
      : null;

    if (avgDuration) {
      maturity.push({
        range: 'Average',
        percent: 1.0,
        avgDuration: avgDuration,
      });
    }
  }

  // Se disponibili dati più dettagliati, aggiungerli qui
  return maturity;
}

module.exports = {
  getYahooFinancePrice,
  getYahooFinanceHistory,
  getETFComposition,
  extractTopHoldings,
  extractSectorWeights,
  extractGeographicWeights,
  extractAssetAllocation,
  extractBondRatings,
  extractBondMaturity,
};
