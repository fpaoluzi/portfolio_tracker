
const pool = require('../src/config/database');

async function checkTransactions() {
    try {
        const portfolioId = 'a5938c95-ba8e-46f6-98f2-4e670ba3b2a4';
        const res = await pool.query('SELECT count(*) FROM transactions WHERE portfolio_id = $1', [portfolioId]);
        console.log('Transaction count:', res.rows[0].count);

        if (parseInt(res.rows[0].count) > 0) {
            const sample = await pool.query('SELECT * FROM transactions WHERE portfolio_id = $1 LIMIT 5', [portfolioId]);
            console.log('Sample transactions:', sample.rows);
        }
    } catch (err) {
        console.error('Error querying database:', err);
    } finally {
        await pool.end();
    }
}

checkTransactions();
