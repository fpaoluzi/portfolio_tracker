// ============================================
// REBALANCING SERVICE
// Core algorithms for portfolio allocation and rebalancing simulation
// All functions are READ-ONLY and do not modify portfolio data
// ============================================

const pool = require('../config/database');
const {
    toDecimal,
    toNumber,
    toFixed,
    add,
    subtract,
    multiply,
    divide,
    percentage,
    fromPercentage,
    compare,
    abs,
    isZero,
} = require('../utils/decimalCalculations');

/**
 * Get current portfolio allocation by asset type
 * Maps asset types to category names
 * @param {string} portfolioId - Portfolio UUID
 * @returns {Promise<Object>} Current allocation by category
 */
async function getCurrentAllocation(portfolioId) {
    const result = await pool.query(
        `SELECT 
      a.asset_type as category_name,
      SUM(pos.quantity * COALESCE(ph.close_price, pos.average_buy_price)) as current_value
    FROM positions pos
    JOIN assets a ON pos.asset_id = a.asset_id
    LEFT JOIN LATERAL (
      SELECT close_price
      FROM price_history
      WHERE asset_id = pos.asset_id
      ORDER BY price_date DESC
      LIMIT 1
    ) ph ON true
    WHERE pos.portfolio_id = $1 AND pos.quantity > 0
    GROUP BY a.asset_type`,
        [portfolioId]
    );

    const allocation = {};
    let totalValue = toDecimal(0);

    result.rows.forEach((row) => {
        const value = toDecimal(row.current_value || 0);
        allocation[row.category_name] = value;
        totalValue = add(totalValue, value);
    });

    return {
        allocation,
        totalValue,
    };
}

/**
 * Get allocation categories for a portfolio
 * @param {string} portfolioId - Portfolio UUID
 * @returns {Promise<Array>} Array of allocation categories
 */
async function getAllocationCategories(portfolioId) {
    const result = await pool.query(
        `SELECT * FROM allocation_categories
     WHERE portfolio_id = $1 AND is_active = true
     ORDER BY display_order, category_name`,
        [portfolioId]
    );

    return result.rows;
}

/**
 * Validate that allocation percentages sum to 100%
 * @param {Array} categories - Array of categories with target_percent
 * @returns {Object} Validation result
 */
function validateAllocationSum(categories) {
    const total = categories.reduce(
        (sum, cat) => add(sum, toDecimal(cat.target_percent)),
        toDecimal(0)
    );

    const isValid = abs(subtract(total, 100)).lessThan(0.01);

    return {
        isValid,
        total: toNumber(total),
        error: isValid ? null : `Total allocation is ${toFixed(total, 2)}%, must equal 100%`,
    };
}

/**
 * Analyze portfolio drift vs target allocation
 * Functionality A: Health Check
 * @param {string} portfolioId - Portfolio UUID
 * @returns {Promise<Object>} Drift analysis with overweight/underweight status
 */
async function analyzeDrift(portfolioId) {
    try {
        // Get target allocation categories
        const categories = await getAllocationCategories(portfolioId);

        if (categories.length === 0) {
            return {
                error: 'No allocation categories defined for this portfolio',
                categories: [],
                totalValue: 0,
            };
        }

        // Validate target percentages sum to 100%
        const validation = validateAllocationSum(categories);
        const warning = !validation.isValid ? validation.error : null;

        // Get current portfolio allocation
        const { allocation: currentAllocation, totalValue } = await getCurrentAllocation(portfolioId);

        // Calculate drift for each category
        const driftAnalysis = categories.map((category) => {
            const targetPercent = toDecimal(category.target_percent);
            const currentValue = currentAllocation[category.category_name] || toDecimal(0);
            const currentPercent = isZero(totalValue) ? toDecimal(0) : percentage(currentValue, totalValue);

            // Drift in percentage points
            const driftPercent = subtract(currentPercent, targetPercent);

            // Drift in currency (how much value is over/under target)
            const targetValue = fromPercentage(targetPercent, totalValue);
            const driftValue = subtract(currentValue, targetValue);

            // Determine status
            let status = 'balanced';
            const absDrift = abs(driftPercent);
            if (absDrift.greaterThan(0.5)) {
                status = compare(driftPercent, 0) > 0 ? 'overweight' : 'underweight';
            }

            return {
                category_id: category.category_id,
                category_name: category.category_name,
                target_percent: toNumber(targetPercent),
                current_value: toNumber(currentValue),
                current_percent: toNumber(currentPercent),
                drift_percent: toNumber(driftPercent),
                drift_value: toNumber(driftValue),
                status,
                color_hex: category.color_hex,
            };
        });

        return {
            categories: driftAnalysis,
            totalValue: toNumber(totalValue),
            portfolioId,
            warning,
        };
    } catch (error) {
        console.error('Error analyzing drift:', error);
        throw error;
    }
}

/**
 * Calculate smart deposit allocation using greedy algorithm
 * Functionality B: Smart Deposit
 * Prioritizes most underweight categories
 * @param {string} portfolioId - Portfolio UUID
 * @param {number} depositAmount - Amount to allocate
 * @returns {Promise<Object>} Allocation suggestions
 */
async function calculateSmartDeposit(portfolioId, depositAmount) {
    try {
        const deposit = toDecimal(depositAmount);

        if (deposit.lessThanOrEqualTo(0)) {
            return {
                error: 'Deposit amount must be greater than 0',
                allocations: [],
            };
        }

        // Get current drift analysis
        const driftData = await analyzeDrift(portfolioId);

        if (driftData.error) {
            return {
                error: driftData.error,
                allocations: [],
            };
        }

        const { categories, totalValue } = driftData;
        const newTotalValue = add(totalValue, deposit);

        // Sort categories by drift (most underweight first)
        const sortedCategories = [...categories].sort((a, b) =>
            compare(a.drift_percent, b.drift_percent)
        );

        // Greedy allocation algorithm
        const allocations = [];
        let remainingDeposit = deposit;

        for (const category of sortedCategories) {
            if (isZero(remainingDeposit)) break;

            const targetPercent = toDecimal(category.target_percent);
            const currentValue = toDecimal(category.current_value);

            // Calculate target value in new portfolio
            const newTargetValue = fromPercentage(targetPercent, newTotalValue);

            // Calculate how much this category needs to reach target
            const needed = subtract(newTargetValue, currentValue);

            if (needed.greaterThan(0)) {
                // Allocate the minimum of what's needed and what's remaining
                const toAllocate = needed.lessThan(remainingDeposit) ? needed : remainingDeposit;

                allocations.push({
                    category_id: category.category_id,
                    category_name: category.category_name,
                    amount: toNumber(toAllocate),
                    reason: `Sottopesata di ${toFixed(abs(category.drift_percent), 2)}%`,
                    current_value: category.current_value,
                    new_value: toNumber(add(currentValue, toAllocate)),
                });

                remainingDeposit = subtract(remainingDeposit, toAllocate);
            }
        }

        // If there's still money left (all categories at or above target),
        // distribute proportionally to target percentages
        if (remainingDeposit.greaterThan(0.01)) {
            const proportionalAllocations = categories.map((category) => {
                const targetPercent = toDecimal(category.target_percent);
                const proportionalAmount = fromPercentage(targetPercent, remainingDeposit);

                return {
                    category_id: category.category_id,
                    category_name: category.category_name,
                    amount: toNumber(proportionalAmount),
                    reason: 'Allocazione proporzionale al target',
                    current_value: category.current_value,
                    new_value: toNumber(add(category.current_value, proportionalAmount)),
                };
            });

            // Merge with existing allocations
            proportionalAllocations.forEach((propAlloc) => {
                const existing = allocations.find((a) => a.category_id === propAlloc.category_id);
                if (existing) {
                    existing.amount = toNumber(add(existing.amount, propAlloc.amount));
                    existing.new_value = toNumber(add(existing.current_value, existing.amount));
                    existing.reason += ' + allocazione proporzionale';
                } else {
                    allocations.push(propAlloc);
                }
            });
        }

        // Calculate projected drift after allocation
        const projectedCategories = categories.map((category) => {
            const allocation = allocations.find((a) => a.category_id === category.category_id);
            const allocatedAmount = allocation ? toDecimal(allocation.amount) : toDecimal(0);
            const newValue = add(category.current_value, allocatedAmount);
            const newPercent = percentage(newValue, newTotalValue);
            const newDrift = subtract(newPercent, category.target_percent);

            return {
                ...category,
                new_value: toNumber(newValue),
                new_percent: toNumber(newPercent),
                new_drift_percent: toNumber(newDrift),
            };
        });

        return {
            deposit_amount: toNumber(deposit),
            allocations,
            projected_drift: projectedCategories,
            new_total_value: toNumber(newTotalValue),
        };
    } catch (error) {
        console.error('Error calculating smart deposit:', error);
        throw error;
    }
}

/**
 * Simulate a manual transaction
 * Functionality C: Manual Simulation
 * @param {string} portfolioId - Portfolio UUID
 * @param {string} categoryName - Category name
 * @param {number} amount - Transaction amount (positive = buy, negative = sell)
 * @returns {Promise<Object>} Simulation results
 */
async function simulateTransaction(portfolioId, categoryName, amount) {
    try {
        const transactionAmount = toDecimal(amount);

        // Get current drift analysis
        const driftData = await analyzeDrift(portfolioId);

        if (driftData.error) {
            return {
                error: driftData.error,
                projected_allocations: [],
            };
        }

        const { categories, totalValue } = driftData;

        // Find the target category
        const targetCategory = categories.find((c) => c.category_name === categoryName);

        if (!targetCategory) {
            return {
                error: `Category "${categoryName}" not found`,
                projected_allocations: [],
            };
        }

        // Calculate new total portfolio value
        const newTotalValue = add(totalValue, transactionAmount);

        if (newTotalValue.lessThanOrEqualTo(0)) {
            return {
                error: 'Transaction would result in zero or negative portfolio value',
                projected_allocations: [],
            };
        }

        // Calculate new allocations
        const projectedAllocations = categories.map((category) => {
            const currentValue = toDecimal(category.current_value);
            const isTargetCategory = category.category_name === categoryName;

            // Add transaction amount to target category
            const newValue = isTargetCategory ? add(currentValue, transactionAmount) : currentValue;

            if (newValue.lessThan(0)) {
                return {
                    ...category,
                    error: `Transaction would result in negative value for ${categoryName}`,
                };
            }

            const newPercent = percentage(newValue, newTotalValue);
            const changePercent = subtract(newPercent, category.current_percent);
            const newDrift = subtract(newPercent, category.target_percent);

            return {
                category_id: category.category_id,
                category_name: category.category_name,
                target_percent: category.target_percent,
                current_value: category.current_value,
                current_percent: category.current_percent,
                new_value: toNumber(newValue),
                new_percent: toNumber(newPercent),
                change_percent: toNumber(changePercent),
                new_drift_percent: toNumber(newDrift),
                color_hex: category.color_hex,
            };
        });

        // Check for errors
        const hasError = projectedAllocations.some((p) => p.error);
        if (hasError) {
            const errorCategory = projectedAllocations.find((p) => p.error);
            return {
                error: errorCategory.error,
                projected_allocations: [],
            };
        }

        return {
            category_name: categoryName,
            transaction_amount: toNumber(transactionAmount),
            current_total_value: toNumber(totalValue),
            new_total_value: toNumber(newTotalValue),
            projected_allocations: projectedAllocations,
        };
    } catch (error) {
        console.error('Error simulating transaction:', error);
        throw error;
    }
}

module.exports = {
    getCurrentAllocation,
    getAllocationCategories,
    validateAllocationSum,
    analyzeDrift,
    calculateSmartDeposit,
    simulateTransaction,
};
