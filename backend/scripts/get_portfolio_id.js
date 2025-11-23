const pool = require('../src/config/database');

async function run() {
    try {
        const res = await pool.query('SELECT portfolio_id FROM portfolios LIMIT 1');
        if (res.rows.length > 0) {
            console.log('PORTFOLIO_ID=' + res.rows[0].portfolio_id);
        } else {
            console.log('No portfolios found');
        }
    } catch (err) {
        console.error(err);
    } finally {
        pool.end();
    }
}

run();
