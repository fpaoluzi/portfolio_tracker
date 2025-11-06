// ============================================
// PERFORMANCE CONTROLLER
// Handles monthly performance calculations and analytics
// ============================================

const pool = require('../config/database');
const { getYahooFinanceHistory } = require('../utils/yahooFinance');
const { calculateAverageCostBasis, mapStateToMonths, generateMonthKeys } = require('../utils/calculations');

/**
 * GET /api/portfolios/:id/monthly-performance-live
 * Calcola performance mensili on-demand da Yahoo Finance
 * Usa Average Cost Basis per calcolo corretto quantità/investito per mese
 */
async function getMonthlyPerformanceLive(req, res) {
  try {
    const { id } = req.params;
    const { months = 12 } = req.query;

    console.log(`\n========================================`);
    console.log(`Recupero performance mensili per portafoglio: ${id}`);
    console.log(`Periodo richiesto: ${months} mesi`);
    console.log(`========================================\n`);

    // Recupera tutte le transazioni del portafoglio
    const transactionsResult = await pool.query(
      `SELECT t.asset_id, t.transaction_type, t.transaction_date, t.quantity,
              t.price_per_share, t.total_amount,
              a.ticker, a.isin, a.name, a.asset_type
       FROM transactions t
       JOIN assets a ON t.asset_id = a.asset_id
       WHERE t.portfolio_id = $1
       ORDER BY t.asset_id, t.transaction_date`,
      [id]
    );

    console.log(`Trovate ${transactionsResult.rows.length} transazioni totali\n`);

    if (transactionsResult.rows.length === 0) {
      return res.json({ positions: [], aggregated: [] });
    }

    // Raggruppa transazioni per asset
    const assetTransactions = {};
    transactionsResult.rows.forEach((t) => {
      if (!assetTransactions[t.asset_id]) {
        assetTransactions[t.asset_id] = {
          asset_id: t.asset_id,
          name: t.name,
          ticker: t.ticker,
          isin: t.isin,
          asset_type: t.asset_type,
          transactions: [],
        };
      }
      assetTransactions[t.asset_id].transactions.push(t);
    });

    const assetsWithPositions = Object.keys(assetTransactions);
    console.log(`Asset unici con transazioni: ${assetsWithPositions.length}\n`);

    // Calcola periodo
    const endDate = new Date();
    const startDate = new Date();
    startDate.setMonth(startDate.getMonth() - parseInt(months));

    const allMonths = generateMonthKeys(startDate, endDate);

    const monthlyData = [];
    let successCount = 0;
    let failCount = 0;

    // Processa ogni asset
    for (const assetId of assetsWithPositions) {
      const asset = assetTransactions[assetId];

      try {
        const symbol = asset.ticker || `${asset.isin}.MI`;

        console.log(`[${successCount + failCount + 1}/${assetsWithPositions.length}] ${asset.name}`);
        console.log(`  Ticker: ${symbol}`);
        console.log(`  Transazioni: ${asset.transactions.length}`);

        // Calcola Average Cost Basis
        const historicalState = calculateAverageCostBasis(asset.transactions);

        // Mappa stato ai mesi richiesti
        const { quantityByMonth, investedByMonth } = mapStateToMonths(historicalState, allMonths);

        const activeMonths = allMonths.filter((k) => quantityByMonth[k] > 0);
        console.log(`  Mesi con posizioni attive: ${activeMonths.length}`);

        const lastMonth = allMonths[allMonths.length - 1];
        console.log(
          `  Ultimo mese (${lastMonth}): qty=${quantityByMonth[lastMonth].toFixed(2)}, invested=€${investedByMonth[lastMonth].toFixed(2)}`
        );

        // Recupera dati storici da Yahoo Finance
        const result = await getYahooFinanceHistory(symbol, startDate, endDate, '1mo');

        if (result && result.timestamp && result.indicators?.quote?.[0]) {
          const timestamps = result.timestamp;
          const closes = result.indicators.quote[0].close;

          const validDataPoints = closes.filter((c) => c !== null).length;
          console.log(`  Dati Yahoo Finance: ${validDataPoints}/${timestamps.length} mesi validi`);

          if (validDataPoints === 0) {
            console.log(`  ⚠️  Nessun dato valido da Yahoo Finance`);
            failCount++;
          } else {
            let monthlyReturns = [];

            // De-duplicazione dati mensili (Map previene duplicati da Yahoo)
            const assetMonthlyData = new Map();

            for (let i = 0; i < timestamps.length; i++) {
              if (closes[i] !== null) {
                const date = new Date(timestamps[i] * 1000);
                const monthYear = `${date.getFullYear()}-${String(date.getMonth() + 1).padStart(2, '0')}-01`;

                const quantity = quantityByMonth[monthYear] || 0;
                const totalInvested = investedByMonth[monthYear] || 0;

                if (quantity <= 0) continue; // Salta mesi senza posizioni

                const price = closes[i];
                const value = quantity * price;
                const gainLoss = value - totalInvested;
                const gainLossPct = totalInvested > 0 ? (gainLoss / totalInvested) * 100 : 0;

                let monthReturn = 0;
                if (i > 0 && closes[i - 1] !== null) {
                  monthReturn = ((closes[i] - closes[i - 1]) / closes[i - 1]) * 100;
                }
                monthlyReturns.push(monthReturn);

                assetMonthlyData.set(monthYear, {
                  asset_id: asset.asset_id,
                  asset_name: asset.name,
                  asset_type: asset.asset_type,
                  ticker: asset.ticker,
                  month_year: monthYear,
                  price: price,
                  quantity: quantity,
                  value: value,
                  total_invested: totalInvested,
                  gain_loss: gainLoss,
                  gain_loss_pct: gainLossPct,
                  month_return_pct: monthReturn,
                });
              }
            }

            // Aggiungi dati unici
            for (const dataPoint of assetMonthlyData.values()) {
              monthlyData.push(dataPoint);
            }

            const avgReturn =
              monthlyReturns.length > 0 ? monthlyReturns.reduce((a, b) => a + b, 0) / monthlyReturns.length : 0;
            const lastReturn = monthlyReturns[monthlyReturns.length - 1] || 0;

            console.log(`  Rendimenti: ultimo mese ${lastReturn.toFixed(2)}%, media ${avgReturn.toFixed(2)}%`);
            console.log(`  ✓ Dati aggiunti con successo (${assetMonthlyData.size} mesi con posizioni)`);
            successCount++;
          }
        } else {
          console.log(`  ✗ Yahoo Finance non ha restituito dati per ${symbol}`);
          failCount++;
        }

        await new Promise((resolve) => setTimeout(resolve, 500));
      } catch (error) {
        console.error(`  ✗ Errore: ${error.message}`);
        failCount++;
      }
      console.log('');
    }

    console.log(`\n========================================`);
    console.log(`Riepilogo:`);
    console.log(`  ✓ Successi: ${successCount}/${assetsWithPositions.length}`);
    console.log(`  ✗ Falliti: ${failCount}/${assetsWithPositions.length}`);
    console.log(`  Totale dati mensili: ${monthlyData.length}`);
    console.log(`========================================\n`);

    // Filtra mesi futuri
    const now = new Date();
    const currentMonthKey = `${now.getFullYear()}-${String(now.getMonth() + 1).padStart(2, '0')}-01`;

    console.log(`\n📅 Mese corrente: ${currentMonthKey}`);
    const futureMonths = monthlyData.filter((item) => item.month_year > currentMonthKey);
    if (futureMonths.length > 0) {
      console.log(`⚠️  Rimuovo ${futureMonths.length} dati di mesi FUTURI (Yahoo Finance bug)`);
    }

    const validMonthlyData = monthlyData.filter((item) => item.month_year <= currentMonthKey);
    console.log(`✓ Dati validi (non futuri): ${validMonthlyData.length}/${monthlyData.length}\n`);

    // Aggrega per mese (totale portafoglio)
    const aggregatedByMonth = {};
    validMonthlyData.forEach((item) => {
      if (!aggregatedByMonth[item.month_year]) {
        aggregatedByMonth[item.month_year] = {
          month_year: item.month_year,
          total_value: 0,
          total_invested: 0,
          total_gain_loss: 0,
          positions: [],
        };
      }
      aggregatedByMonth[item.month_year].total_value += item.value;
      aggregatedByMonth[item.month_year].total_invested += item.total_invested;
      aggregatedByMonth[item.month_year].total_gain_loss += item.gain_loss;
      aggregatedByMonth[item.month_year].positions.push(item);
    });

    const aggregated = Object.values(aggregatedByMonth)
      .map((month) => ({
        ...month,
        total_return_pct: month.total_invested > 0 ? (month.total_gain_loss / month.total_invested) * 100 : 0,
        num_positions: month.positions.length,
      }))
      .sort((a, b) => a.month_year.localeCompare(b.month_year));

    console.log(`\n📊 Mesi aggregati (dopo filtro): ${aggregated.length}`);
    if (aggregated.length > 0) {
      const latest = aggregated[aggregated.length - 1];

      console.log(`Ultimo mese disponibile (${latest.month_year}):`);
      console.log(`  Valore: €${latest.total_value.toFixed(2)}`);
      console.log(`  Investito: €${latest.total_invested.toFixed(2)}`);
      console.log(`  Posizioni: ${latest.num_positions}`);
    }
    console.log('');

    res.json({
      positions: validMonthlyData.sort((a, b) => a.month_year.localeCompare(b.month_year)),
      aggregated: aggregated,
    });
  } catch (err) {
    console.error('Errore recupero performance mensili live:', err);
    res.status(500).json({ error: 'Errore nel recupero performance', details: err.message });
  }
}

/**
 * GET /api/portfolios/:id/monthly-performance
 * Recupera performance mensili salvate nel database
 */
async function getMonthlyPerformance(req, res) {
  try {
    const { id } = req.params;
    const { months = 12 } = req.query;

    const result = await pool.query(
      `SELECT
        mpp.*,
        a.name AS asset_name,
        a.ticker,
        a.asset_type
       FROM monthly_position_performance mpp
       JOIN assets a ON mpp.asset_id = a.asset_id
       WHERE mpp.portfolio_id = $1
       ORDER BY mpp.month_year DESC, a.name ASC
       LIMIT $2`,
      [id, months * 20]
    );

    res.json(result.rows);
  } catch (err) {
    console.error(err);
    res.status(500).json({ error: 'Errore nel recupero performance mensili' });
  }
}

/**
 * GET /api/portfolios/:id/monthly-performance-aggregate
 * Recupera performance mensili aggregate per portafoglio
 */
async function getMonthlyPerformanceAggregate(req, res) {
  try {
    const { id } = req.params;
    const { months = 12 } = req.query;

    const result = await pool.query(
      `SELECT *
       FROM v_monthly_portfolio_performance
       WHERE portfolio_id = $1
       ORDER BY month_year DESC
       LIMIT $2`,
      [id, months]
    );

    res.json(result.rows);
  } catch (err) {
    console.error(err);
    res.status(500).json({ error: 'Errore nel recupero performance aggregate' });
  }
}

/**
 * POST /api/portfolios/:id/calculate-monthly-performance
 * Calcola e salva snapshot mensili (per storicizzazione)
 */
async function calculateMonthlyPerformance(req, res) {
  try {
    const { id } = req.params;
    const { months = 12 } = req.body;

    const positionsResult = await pool.query(
      `SELECT p.position_id, p.portfolio_id, p.asset_id, p.quantity,
              p.average_buy_price, p.total_invested, a.ticker, a.isin, a.name
       FROM positions p
       JOIN assets a ON p.asset_id = a.asset_id
       WHERE p.portfolio_id = $1 AND p.quantity > 0`,
      [id]
    );

    if (positionsResult.rows.length === 0) {
      return res.json({ message: 'Nessuna posizione trovata nel portafoglio', snapshots: 0 });
    }

    const snapshots = [];
    const errors = [];
    const today = new Date();

    // Per ogni mese degli ultimi N mesi
    for (let i = 0; i < months; i++) {
      const targetDate = new Date(today.getFullYear(), today.getMonth() - i, 1);
      const monthYear = targetDate.toISOString().split('T')[0];
      const monthStart = new Date(targetDate.getFullYear(), targetDate.getMonth(), 1);
      const monthEnd = new Date(targetDate.getFullYear(), targetDate.getMonth() + 1, 0);

      console.log(`\nCalcolo performance per ${monthYear}...`);

      // Per ogni posizione
      for (const position of positionsResult.rows) {
        try {
          const symbol = position.ticker || `${position.isin}.MI`;

          // Cerca prezzi nel database price_history
          const pricesResult = await pool.query(
            `SELECT price_date, close_price
             FROM price_history
             WHERE asset_id = $1
               AND price_date >= $2
               AND price_date <= $3
             ORDER BY price_date ASC`,
            [position.asset_id, monthStart.toISOString().split('T')[0], monthEnd.toISOString().split('T')[0]]
          );

          let monthStartPrice = null;
          let monthEndPrice = null;

          if (pricesResult.rows.length > 0) {
            monthStartPrice = pricesResult.rows[0].close_price;
            monthEndPrice = pricesResult.rows[pricesResult.rows.length - 1].close_price;
          }

          // Se non ci sono dati storici, usa prezzo medio
          if (!monthEndPrice) {
            monthEndPrice = parseFloat(position.average_buy_price);
            monthStartPrice = monthStartPrice || monthEndPrice;
          }

          // Calcola metriche
          const monthReturnPct = monthStartPrice ? ((monthEndPrice - monthStartPrice) / monthStartPrice) * 100 : 0;
          const monthStartValue = monthStartPrice ? position.quantity * monthStartPrice : null;
          const monthEndValue = position.quantity * monthEndPrice;
          const unrealizedGainLoss = monthEndValue - parseFloat(position.total_invested);

          // Salva snapshot
          await pool.query(
            `INSERT INTO monthly_position_performance (
              portfolio_id, asset_id, month_year, quantity, average_buy_price,
              month_start_price, month_end_price, month_return_pct,
              total_invested, month_start_value, month_end_value, unrealized_gain_loss
            ) VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12)
            ON CONFLICT (portfolio_id, asset_id, month_year)
            DO UPDATE SET
              quantity = EXCLUDED.quantity,
              month_end_price = EXCLUDED.month_end_price,
              month_return_pct = EXCLUDED.month_return_pct,
              month_end_value = EXCLUDED.month_end_value,
              unrealized_gain_loss = EXCLUDED.unrealized_gain_loss`,
            [
              position.portfolio_id,
              position.asset_id,
              monthYear,
              position.quantity,
              position.average_buy_price,
              monthStartPrice,
              monthEndPrice,
              monthReturnPct,
              position.total_invested,
              monthStartValue,
              monthEndValue,
              unrealizedGainLoss,
            ]
          );

          snapshots.push({
            asset: position.name,
            month: monthYear,
            return_pct: monthReturnPct.toFixed(2),
          });

          console.log(`  ✓ ${position.name}: ${monthReturnPct.toFixed(2)}%`);
        } catch (posError) {
          console.error(`Errore posizione ${position.name}:`, posError.message);
          errors.push({
            asset: position.name,
            month: monthYear,
            error: posError.message,
          });
        }

        await new Promise((resolve) => setTimeout(resolve, 300));
      }
    }

    res.json({
      success: true,
      months_calculated: months,
      snapshots_created: snapshots.length,
      errors: errors.length,
      details: { snapshots, errors },
    });
  } catch (err) {
    console.error('Errore calcolo performance mensili:', err);
    res.status(500).json({ error: 'Errore nel calcolo performance mensili', details: err.message });
  }
}

module.exports = {
  getMonthlyPerformanceLive,
  getMonthlyPerformance,
  getMonthlyPerformanceAggregate,
  calculateMonthlyPerformance,
};
