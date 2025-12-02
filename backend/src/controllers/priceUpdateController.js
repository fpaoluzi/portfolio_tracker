// ============================================
// PRICE UPDATE CONTROLLER
// Handles price updates from Yahoo Finance
// ============================================

const pool = require('../config/database');
const { getYahooFinancePrice } = require('../utils/yahooFinance');

/**
 * POST /api/portfolios/:id/update-prices
 * Aggiorna prezzi degli asset nel portafoglio da Yahoo Finance
 */
async function updatePortfolioPrices(req, res) {
  try {
    const { id } = req.params;

    // Recupera asset con posizioni attive nel portafoglio
    const result = await pool.query(
      `SELECT DISTINCT a.asset_id, a.ticker, a.isin, a.name
       FROM v_current_positions p
       JOIN assets a ON p.asset_id = a.asset_id
       WHERE p.portfolio_id = $1 AND p.quantity > 0`,
      [id]
    );

    const updates = [];
    const errors = [];
    const today = new Date().toISOString().split('T')[0];

    for (const asset of result.rows) {
      let symbol = asset.ticker;

      // Se non c'è ticker, prova con ISIN
      if (!symbol && asset.isin) {
        symbol = `${asset.isin}.MI`; // Prova mercato Milano
      }

      try {
        if (!symbol) {
          errors.push({
            asset_id: asset.asset_id,
            name: asset.name,
            error: 'Nessun ticker o ISIN disponibile',
          });
          continue;
        }

        console.log(`Recupero prezzo per ${asset.name} (${symbol})...`);

        const priceData = await getYahooFinancePrice(symbol);

        if (priceData && priceData.price) {
          await pool.query(
            `INSERT INTO price_history (asset_id, price_date, close_price, open_price, high_price, low_price, volume, data_source)
             VALUES ($1, $2, $3, $4, $5, $6, $7, 'YAHOO_FINANCE')
             ON CONFLICT (asset_id, price_date)
             DO UPDATE SET
               close_price = EXCLUDED.close_price,
               open_price = EXCLUDED.open_price,
               high_price = EXCLUDED.high_price,
               low_price = EXCLUDED.low_price,
               volume = EXCLUDED.volume`,
            [
              asset.asset_id,
              today,
              priceData.price,
              priceData.open || priceData.price,
              priceData.high || priceData.price,
              priceData.low || priceData.price,
              priceData.volume || null,
            ]
          );

          updates.push({
            asset_id: asset.asset_id,
            name: asset.name,
            symbol: symbol,
            price: priceData.price,
            currency: priceData.currency,
          });

          console.log(`✓ ${asset.name}: ${priceData.price} ${priceData.currency}`);
        } else {
          errors.push({
            asset_id: asset.asset_id,
            name: asset.name,
            symbol: symbol,
            error: 'Prezzo non disponibile',
          });
        }

        await new Promise((resolve) => setTimeout(resolve, 500));
      } catch (assetError) {
        console.error(`Errore recupero prezzo ${asset.name}:`, assetError.message);

        // Prova con mercato tedesco
        if (asset.isin && !asset.ticker) {
          try {
            const symbolDE = `${asset.isin}.DE`;
            console.log(`Riprovo con ${symbolDE}...`);

            const priceData = await getYahooFinancePrice(symbolDE);

            if (priceData && priceData.price) {
              await pool.query(
                `INSERT INTO price_history (asset_id, price_date, close_price, data_source)
                 VALUES ($1, $2, $3, 'YAHOO_FINANCE')
                 ON CONFLICT (asset_id, price_date)
                 DO UPDATE SET close_price = EXCLUDED.close_price`,
                [asset.asset_id, today, priceData.price]
              );

              updates.push({
                asset_id: asset.asset_id,
                name: asset.name,
                symbol: symbolDE,
                price: priceData.price,
              });

              console.log(`✓ ${asset.name}: ${priceData.price} (via .DE)`);
              await new Promise((resolve) => setTimeout(resolve, 500));
              continue;
            }
          } catch (secondError) {
            // Ignora
          }
        }

        errors.push({
          asset_id: asset.asset_id,
          name: asset.name,
          symbol: symbol || asset.isin,
          error: assetError.message,
        });
      }
    }

    res.json({
      success: true,
      updated: updates.length,
      failed: errors.length,
      total: result.rows.length,
      prices: updates,
      errors: errors,
    });
  } catch (err) {
    console.error('Errore aggiornamento prezzi:', err);
    res.status(500).json({ error: "Errore nell'aggiornamento prezzi", details: err.message });
  }
}

module.exports = {
  updatePortfolioPrices,
};
