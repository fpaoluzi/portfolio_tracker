// ============================================
// YAHOO FINANCE UTILITY
// Helper functions for fetching prices from Yahoo Finance
// ============================================

const axios = require('axios');

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

module.exports = {
  getYahooFinancePrice,
  getYahooFinanceHistory,
};
