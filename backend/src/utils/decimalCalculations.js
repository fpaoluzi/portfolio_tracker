// ============================================
// DECIMAL CALCULATIONS UTILITY
// High-precision decimal operations for currency calculations
// Prevents floating-point rounding errors
// ============================================

const Decimal = require('decimal.js');

// Configure Decimal for currency operations
// Precision: 20 digits, Rounding: Half-up (standard for currency)
Decimal.set({
    precision: 20,
    rounding: Decimal.ROUND_HALF_UP
});

/**
 * Convert a value to Decimal
 * @param {number|string|Decimal} value - Value to convert
 * @returns {Decimal} Decimal instance
 */
function toDecimal(value) {
    return new Decimal(value || 0);
}

/**
 * Convert Decimal to number
 * @param {Decimal} decimal - Decimal instance
 * @returns {number} Number value
 */
function toNumber(decimal) {
    return decimal.toNumber();
}

/**
 * Convert Decimal to fixed decimal string
 * @param {Decimal} decimal - Decimal instance
 * @param {number} places - Number of decimal places (default: 2)
 * @returns {string} Fixed decimal string
 */
function toFixed(decimal, places = 2) {
    return decimal.toFixed(places);
}

/**
 * Add multiple Decimal values
 * @param {...(number|string|Decimal)} values - Values to add
 * @returns {Decimal} Sum
 */
function add(...values) {
    return values.reduce((sum, val) => sum.plus(toDecimal(val)), toDecimal(0));
}

/**
 * Subtract Decimal values
 * @param {number|string|Decimal} a - Minuend
 * @param {number|string|Decimal} b - Subtrahend
 * @returns {Decimal} Difference
 */
function subtract(a, b) {
    return toDecimal(a).minus(toDecimal(b));
}

/**
 * Multiply Decimal values
 * @param {number|string|Decimal} a - Multiplicand
 * @param {number|string|Decimal} b - Multiplier
 * @returns {Decimal} Product
 */
function multiply(a, b) {
    return toDecimal(a).times(toDecimal(b));
}

/**
 * Divide Decimal values
 * @param {number|string|Decimal} a - Dividend
 * @param {number|string|Decimal} b - Divisor
 * @returns {Decimal} Quotient (returns 0 if divisor is 0)
 */
function divide(a, b) {
    const divisor = toDecimal(b);
    if (divisor.isZero()) {
        return toDecimal(0);
    }
    return toDecimal(a).dividedBy(divisor);
}

/**
 * Calculate percentage
 * @param {number|string|Decimal} part - Part value
 * @param {number|string|Decimal} total - Total value
 * @returns {Decimal} Percentage (0-100)
 */
function percentage(part, total) {
    const totalDecimal = toDecimal(total);
    if (totalDecimal.isZero()) {
        return toDecimal(0);
    }
    return toDecimal(part).dividedBy(totalDecimal).times(100);
}

/**
 * Calculate value from percentage
 * @param {number|string|Decimal} percent - Percentage (0-100)
 * @param {number|string|Decimal} total - Total value
 * @returns {Decimal} Value
 */
function fromPercentage(percent, total) {
    return toDecimal(percent).dividedBy(100).times(toDecimal(total));
}

/**
 * Compare two Decimal values
 * @param {number|string|Decimal} a - First value
 * @param {number|string|Decimal} b - Second value
 * @returns {number} -1 if a < b, 0 if a == b, 1 if a > b
 */
function compare(a, b) {
    return toDecimal(a).comparedTo(toDecimal(b));
}

/**
 * Get absolute value
 * @param {number|string|Decimal} value - Value
 * @returns {Decimal} Absolute value
 */
function abs(value) {
    return toDecimal(value).abs();
}

/**
 * Check if value is zero
 * @param {number|string|Decimal} value - Value to check
 * @returns {boolean} True if zero
 */
function isZero(value) {
    return toDecimal(value).isZero();
}

/**
 * Get minimum of multiple values
 * @param {...(number|string|Decimal)} values - Values to compare
 * @returns {Decimal} Minimum value
 */
function min(...values) {
    return Decimal.min(...values.map(toDecimal));
}

/**
 * Get maximum of multiple values
 * @param {...(number|string|Decimal)} values - Values to compare
 * @returns {Decimal} Maximum value
 */
function max(...values) {
    return Decimal.max(...values.map(toDecimal));
}

module.exports = {
    Decimal,
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
    min,
    max,
};
