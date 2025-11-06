// ============================================
// TRANSACTION CONTROLLER
// Handles all transaction-related operations
// ============================================

const pool = require('../config/database');

/**
 * GET /api/portfolios/:id/transactions
 * Recupera transazioni di un portafoglio con paginazione
 */
async function getPortfolioTransactions(req, res) {
  try {
    const { id } = req.params;
    const { limit = 50, offset = 0 } = req.query;

    const result = await pool.query(
      `SELECT t.*, a.name as asset_name, a.isin
       FROM transactions t
       JOIN assets a ON t.asset_id = a.asset_id
       WHERE t.portfolio_id = $1
       ORDER BY t.transaction_date DESC, t.created_at DESC
       LIMIT $2 OFFSET $3`,
      [id, limit, offset]
    );

    res.json(result.rows);
  } catch (err) {
    console.error(err);
    res.status(500).json({ error: 'Errore nel recupero transazioni' });
  }
}

/**
 * POST /api/transactions
 * Crea una nuova transazione
 */
async function createTransaction(req, res) {
  const client = await pool.connect();
  try {
    await client.query('BEGIN');

    const {
      portfolio_id,
      asset_id,
      transaction_type,
      transaction_date,
      quantity,
      price_per_share,
      commission,
      fees,
      taxes,
      currency,
      exchange_rate,
      notes,
    } = req.body;

    const total_amount = quantity * price_per_share;
    const amount_in_base_currency = total_amount * (exchange_rate || 1.0);

    const result = await client.query(
      `INSERT INTO transactions (
        portfolio_id, asset_id, transaction_type, transaction_date,
        quantity, price_per_share, total_amount, commission, fees, taxes,
        currency, exchange_rate, amount_in_base_currency, notes
      ) VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, $13, $14)
      RETURNING *`,
      [
        portfolio_id,
        asset_id,
        transaction_type,
        transaction_date,
        quantity,
        price_per_share,
        total_amount,
        commission || 0,
        fees || 0,
        taxes || 0,
        currency || 'EUR',
        exchange_rate || 1.0,
        amount_in_base_currency,
        notes,
      ]
    );

    await client.query('COMMIT');
    res.status(201).json(result.rows[0]);
  } catch (err) {
    await client.query('ROLLBACK');
    console.error(err);
    res.status(500).json({ error: 'Errore nella creazione transazione' });
  } finally {
    client.release();
  }
}

/**
 * PUT /api/transactions/:id
 * Aggiorna una transazione esistente
 */
async function updateTransaction(req, res) {
  const client = await pool.connect();
  try {
    await client.query('BEGIN');

    const { id } = req.params;
    const {
      asset_id,
      transaction_type,
      transaction_date,
      quantity,
      price_per_share,
      commission,
      fees,
      taxes,
      currency,
      exchange_rate,
      notes,
    } = req.body;

    const total_amount = quantity * price_per_share;
    const amount_in_base_currency = total_amount * (exchange_rate || 1.0);

    const result = await client.query(
      `UPDATE transactions SET
        asset_id = $1, transaction_type = $2, transaction_date = $3,
        quantity = $4, price_per_share = $5, total_amount = $6,
        commission = $7, fees = $8, taxes = $9, currency = $10,
        exchange_rate = $11, amount_in_base_currency = $12, notes = $13,
        updated_at = CURRENT_TIMESTAMP
       WHERE transaction_id = $14
       RETURNING *`,
      [
        asset_id,
        transaction_type,
        transaction_date,
        quantity,
        price_per_share,
        total_amount,
        commission || 0,
        fees || 0,
        taxes || 0,
        currency || 'EUR',
        exchange_rate || 1.0,
        amount_in_base_currency,
        notes,
        id,
      ]
    );

    if (result.rows.length === 0) {
      await client.query('ROLLBACK');
      return res.status(404).json({ error: 'Transazione non trovata' });
    }

    await client.query('COMMIT');
    res.json(result.rows[0]);
  } catch (err) {
    await client.query('ROLLBACK');
    console.error(err);
    res.status(500).json({ error: "Errore nell'aggiornamento transazione" });
  } finally {
    client.release();
  }
}

/**
 * DELETE /api/transactions/:id
 * Elimina una transazione
 */
async function deleteTransaction(req, res) {
  const client = await pool.connect();
  try {
    await client.query('BEGIN');

    const { id } = req.params;
    const result = await client.query('DELETE FROM transactions WHERE transaction_id = $1 RETURNING *', [
      id,
    ]);

    if (result.rows.length === 0) {
      await client.query('ROLLBACK');
      return res.status(404).json({ error: 'Transazione non trovata' });
    }

    await client.query('COMMIT');
    res.json({ message: 'Transazione eliminata con successo', transaction: result.rows[0] });
  } catch (err) {
    await client.query('ROLLBACK');
    console.error(err);
    res.status(500).json({ error: "Errore nell'eliminazione transazione" });
  } finally {
    client.release();
  }
}

module.exports = {
  getPortfolioTransactions,
  createTransaction,
  updateTransaction,
  deleteTransaction,
};
