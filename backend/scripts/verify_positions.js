const pool = require('../src/config/database');

async function verifyPositionTotals() {
    try {
        console.log('=== VERIFYING POSITION TOTALS ===\n');

        const portfolioId = 'a5938c95-ba8e-46f6-98f2-4e670ba3b2a4';

        // 1. Total from BUY transactions
        const buyTransactions = await pool.query(`
            SELECT 
                SUM(total_amount + commission + fees) as total_from_buy_transactions,
                COUNT(*) as buy_count
            FROM transactions 
            WHERE portfolio_id = $1 AND transaction_type = 'BUY'
        `, [portfolioId]);

        // 2. Total from SELL transactions
        const sellTransactions = await pool.query(`
            SELECT 
                SUM(total_amount) as total_from_sell_transactions,
                COUNT(*) as sell_count
            FROM transactions 
            WHERE portfolio_id = $1 AND transaction_type = 'SELL'
        `, [portfolioId]);

        // 3. Total invested in positions
        const positions = await pool.query(`
            SELECT 
                SUM(total_invested) as total_in_positions,
                SUM(total_commissions) as total_commissions,
                SUM(total_fees) as total_fees,
                COUNT(*) as position_count
            FROM positions 
            WHERE portfolio_id = $1
        `, [portfolioId]);

        // 4. Get detailed position breakdown
        const positionDetails = await pool.query(`
            SELECT 
                a.name,
                a.isin,
                p.quantity,
                p.average_buy_price,
                p.total_invested,
                p.total_commissions,
                p.total_fees
            FROM positions p
            JOIN assets a ON p.asset_id = a.asset_id
            WHERE p.portfolio_id = $1
            ORDER BY p.total_invested DESC
        `, [portfolioId]);

        // 5. Check for duplicate transactions
        const duplicates = await pool.query(`
            SELECT 
                a.name,
                t.transaction_type,
                t.transaction_date,
                t.quantity,
                t.price_per_share,
                t.total_amount,
                COUNT(*) as duplicate_count
            FROM transactions t
            JOIN assets a ON t.asset_id = a.asset_id
            WHERE t.portfolio_id = $1
            GROUP BY a.name, t.transaction_type, t.transaction_date, t.quantity, t.price_per_share, t.total_amount
            HAVING COUNT(*) > 1
            ORDER BY duplicate_count DESC
        `, [portfolioId]);

        console.log('📊 TRANSACTION TOTALS:');
        console.log(`  BUY Transactions: ${buyTransactions.rows[0].buy_count}`);
        console.log(`  Total from BUYs: €${parseFloat(buyTransactions.rows[0].total_from_buy_transactions || 0).toFixed(2)}`);
        console.log(`  SELL Transactions: ${sellTransactions.rows[0].sell_count}`);
        console.log(`  Total from SELLs: €${parseFloat(sellTransactions.rows[0].total_from_sell_transactions || 0).toFixed(2)}`);

        console.log('\n📈 POSITION TOTALS:');
        console.log(`  Active Positions: ${positions.rows[0].position_count}`);
        console.log(`  Total Invested: €${parseFloat(positions.rows[0].total_in_positions || 0).toFixed(2)}`);
        console.log(`  Total Commissions: €${parseFloat(positions.rows[0].total_commissions || 0).toFixed(2)}`);
        console.log(`  Total Fees: €${parseFloat(positions.rows[0].total_fees || 0).toFixed(2)}`);

        const expectedTotal = parseFloat(buyTransactions.rows[0].total_from_buy_transactions || 0);
        const actualTotal = parseFloat(positions.rows[0].total_in_positions || 0);
        const difference = actualTotal - expectedTotal;

        console.log('\n⚖️  COMPARISON:');
        console.log(`  Expected (from transactions): €${expectedTotal.toFixed(2)}`);
        console.log(`  Actual (in positions): €${actualTotal.toFixed(2)}`);
        console.log(`  Difference: €${difference.toFixed(2)} (${difference > 0 ? 'OVER' : 'UNDER'})`);

        if (Math.abs(difference) > 0.01) {
            console.log('\n⚠️  WARNING: Discrepancy detected!');
        } else {
            console.log('\n✅ Totals match!');
        }

        if (duplicates.rows.length > 0) {
            console.log('\n🔴 DUPLICATE TRANSACTIONS FOUND:');
            duplicates.rows.forEach(dup => {
                console.log(`  - ${dup.name}: ${dup.duplicate_count}x ${dup.transaction_type} on ${dup.transaction_date}`);
                console.log(`    Qty: ${dup.quantity}, Price: €${dup.price_per_share}, Total: €${dup.total_amount}`);
            });
        } else {
            console.log('\n✅ No duplicate transactions found');
        }

        console.log('\n📋 TOP 10 POSITIONS BY INVESTED:');
        positionDetails.rows.slice(0, 10).forEach(pos => {
            console.log(`  ${pos.name} (${pos.isin})`);
            console.log(`    Qty: ${pos.quantity}, Avg Price: €${parseFloat(pos.average_buy_price).toFixed(2)}`);
            console.log(`    Total Invested: €${parseFloat(pos.total_invested).toFixed(2)}`);
        });

    } catch (err) {
        console.error('❌ Error:', err);
    } finally {
        await pool.end();
    }
}

verifyPositionTotals();
