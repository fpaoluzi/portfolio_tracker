// ============================================
// REBALANCING CONTROLLER
// Handles allocation category management and rebalancing simulations
// All endpoints are READ-ONLY simulations (do not modify portfolio data)
// ============================================

const pool = require('../config/database');
const {
    getAllocationCategories,
    validateAllocationSum,
    analyzeDrift,
    calculateSmartDeposit,
    simulateTransaction,
} = require('../services/rebalancingService');

/**
 * GET /api/rebalancing/:portfolioId/categories
 * Get all allocation categories for a portfolio
 */
async function getCategories(req, res) {
    try {
        const { portfolioId } = req.params;
        const categories = await getAllocationCategories(portfolioId);

        // Validate sum
        const validation = validateAllocationSum(categories);

        res.json({
            categories,
            validation,
        });
    } catch (err) {
        console.error('Error getting categories:', err);
        res.status(500).json({
            error: 'Errore nel recupero delle categorie',
            details: err.message,
            stack: err.stack
        });
    }
}

/**
 * POST /api/rebalancing/:portfolioId/categories
 * Create a new allocation category
 */
async function createCategory(req, res) {
    try {
        const { portfolioId } = req.params;
        const { category_name, target_percent, display_order, color_hex } = req.body;

        // Validate required fields
        if (!category_name || target_percent === undefined) {
            return res.status(400).json({
                error: 'category_name e target_percent sono obbligatori'
            });
        }

        // Validate numeric value
        const percent = parseFloat(target_percent);
        if (isNaN(percent) || percent < 0 || percent > 100) {
            return res.status(400).json({
                error: 'target_percent deve essere un numero compreso tra 0 e 100'
            });
        }

        // Check if category name already exists (active or inactive)
        const existing = await pool.query(
            `SELECT category_id, is_active FROM allocation_categories
       WHERE portfolio_id = $1 AND category_name = $2`,
            [portfolioId, category_name]
        );

        if (existing.rows.length > 0) {
            const category = existing.rows[0];
            if (category.is_active) {
                return res.status(400).json({
                    error: `Categoria "${category_name}" già esistente`
                });
            }

            // If inactive, reactivate and update
            // Validate sum including the reactivated category
            const currentCategories = await getAllocationCategories(portfolioId);
            const totalCurrent = currentCategories.reduce(
                (sum, cat) => sum + parseFloat(cat.target_percent),
                0
            );
            const newTotal = totalCurrent + percent;

            if (newTotal > 100.01) {
                return res.status(400).json({
                    error: `La somma delle percentuali sarebbe ${newTotal.toFixed(2)}%, non può superare il 100%`
                });
            }

            const result = await pool.query(
                `UPDATE allocation_categories SET
            is_active = true,
            target_percent = $1,
            display_order = $2,
            color_hex = $3,
            updated_at = CURRENT_TIMESTAMP
           WHERE category_id = $4
           RETURNING *`,
                [percent, display_order || 0, color_hex || '#3B82F6', category.category_id]
            );

            return res.status(201).json(result.rows[0]);
        }

        // Get all current categories to validate sum
        const currentCategories = await getAllocationCategories(portfolioId);
        const totalCurrent = currentCategories.reduce(
            (sum, cat) => sum + parseFloat(cat.target_percent),
            0
        );
        const newTotal = totalCurrent + percent;

        if (newTotal > 100.01) {
            return res.status(400).json({
                error: `La somma delle percentuali sarebbe ${newTotal.toFixed(2)}%, non può superare il 100%`
            });
        }

        const result = await pool.query(
            `INSERT INTO allocation_categories (
        portfolio_id, category_name, target_percent, display_order, color_hex
      ) VALUES ($1, $2, $3, $4, $5)
      RETURNING *`,
            [
                portfolioId,
                category_name,
                percent,
                display_order || 0,
                color_hex || '#3B82F6',
            ]
        );

        res.status(201).json(result.rows[0]);
    } catch (err) {
        console.error('Error creating category:', err);
        res.status(500).json({ error: 'Errore nella creazione della categoria' });
    }
}

/**
 * PUT /api/rebalancing/:portfolioId/categories/:categoryId
 * Update an allocation category
 */
async function updateCategory(req, res) {
    try {
        const { portfolioId, categoryId } = req.params;
        const { category_name, target_percent, display_order, color_hex } = req.body;

        // Get current category
        const current = await pool.query(
            `SELECT * FROM allocation_categories WHERE category_id = $1 AND portfolio_id = $2`,
            [categoryId, portfolioId]
        );

        if (current.rows.length === 0) {
            return res.status(404).json({ error: 'Categoria non trovata' });
        }

        // If changing target_percent, validate sum
        if (target_percent !== undefined) {
            const percent = parseFloat(target_percent);
            if (isNaN(percent) || percent < 0 || percent > 100) {
                return res.status(400).json({
                    error: 'target_percent deve essere un numero compreso tra 0 e 100'
                });
            }

            const allCategories = await getAllocationCategories(portfolioId);
            const totalOthers = allCategories
                .filter((cat) => cat.category_id !== categoryId)
                .reduce((sum, cat) => sum + parseFloat(cat.target_percent), 0);
            const newTotal = totalOthers + percent;

            if (newTotal > 100.01) {
                return res.status(400).json({
                    error: `La somma delle percentuali sarebbe ${newTotal.toFixed(2)}%, non può superare il 100%`
                });
            }
        }

        const result = await pool.query(
            `UPDATE allocation_categories SET
        category_name = COALESCE($1, category_name),
        target_percent = COALESCE($2, target_percent),
        display_order = COALESCE($3, display_order),
        color_hex = COALESCE($4, color_hex),
        updated_at = CURRENT_TIMESTAMP
       WHERE category_id = $5 AND portfolio_id = $6
       RETURNING *`,
            [category_name, target_percent, display_order, color_hex, categoryId, portfolioId]
        );

        res.json(result.rows[0]);
    } catch (err) {
        console.error('Error updating category:', err);
        res.status(500).json({ error: "Errore nell'aggiornamento della categoria" });
    }
}

/**
 * DELETE /api/rebalancing/:portfolioId/categories/:categoryId
 * Delete (soft delete) an allocation category
 */
async function deleteCategory(req, res) {
    try {
        const { portfolioId, categoryId } = req.params;

        const result = await pool.query(
            `UPDATE allocation_categories SET
        is_active = false,
        updated_at = CURRENT_TIMESTAMP
       WHERE category_id = $1 AND portfolio_id = $2
       RETURNING *`,
            [categoryId, portfolioId]
        );

        if (result.rows.length === 0) {
            return res.status(404).json({ error: 'Categoria non trovata' });
        }

        res.json({ message: 'Categoria eliminata con successo', category: result.rows[0] });
    } catch (err) {
        console.error('Error deleting category:', err);
        res.status(500).json({ error: 'Errore nella cancellazione della categoria' });
    }
}

/**
 * GET /api/rebalancing/:portfolioId/drift-analysis
 * Analyze portfolio drift vs target allocation (Health Check)
 * READ-ONLY: Does not modify portfolio data
 */
async function getDriftAnalysis(req, res) {
    try {
        const { portfolioId } = req.params;
        const analysis = await analyzeDrift(portfolioId);

        if (analysis.error) {
            return res.status(400).json({ error: analysis.error });
        }

        res.json(analysis);
    } catch (err) {
        console.error('Error analyzing drift:', err);
        res.status(500).json({ error: "Errore nell'analisi dello scostamento" });
    }
}

/**
 * POST /api/rebalancing/:portfolioId/smart-deposit
 * Calculate optimal allocation for new deposit (Smart Deposit)
 * READ-ONLY: Returns suggestions, does not execute trades
 */
async function getSmartDeposit(req, res) {
    try {
        const { portfolioId } = req.params;
        const { amount } = req.body;

        if (!amount || amount <= 0) {
            return res.status(400).json({ error: 'Importo deve essere maggiore di 0' });
        }

        const result = await calculateSmartDeposit(portfolioId, amount);

        if (result.error) {
            return res.status(400).json({ error: result.error });
        }

        res.json(result);
    } catch (err) {
        console.error('Error calculating smart deposit:', err);
        res.status(500).json({ error: 'Errore nel calcolo allocazione intelligente' });
    }
}

/**
 * POST /api/rebalancing/:portfolioId/simulate-transaction
 * Simulate a manual transaction (Manual Simulation)
 * READ-ONLY: Shows projected results, does not modify portfolio
 */
async function getSimulateTransaction(req, res) {
    try {
        const { portfolioId } = req.params;
        const { category_name, amount } = req.body;

        if (!category_name) {
            return res.status(400).json({ error: 'category_name è obbligatorio' });
        }

        if (amount === undefined || amount === 0) {
            return res.status(400).json({ error: 'amount deve essere diverso da 0' });
        }

        const result = await simulateTransaction(portfolioId, category_name, amount);

        if (result.error) {
            return res.status(400).json({ error: result.error });
        }

        res.json(result);
    } catch (err) {
        console.error('Error simulating transaction:', err);
        res.status(500).json({ error: 'Errore nella simulazione transazione' });
    }
}

module.exports = {
    getCategories,
    createCategory,
    updateCategory,
    deleteCategory,
    getDriftAnalysis,
    getSmartDeposit,
    getSimulateTransaction,
};
