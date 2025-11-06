// ============================================
// CALCULATION UTILITIES
// Helper functions for financial calculations
// ============================================

/**
 * Calcola il costo medio di carico (Average Cost Basis)
 * @param {Array} transactions - Array di transazioni ordinate per data
 * @returns {Array} - Array di stati storici con quantity e invested
 */
function calculateAverageCostBasis(transactions) {
  const historicalState = [];
  let currentQuantity = 0;
  let currentInvested = 0;

  for (const t of transactions) {
    const quantity = parseFloat(t.quantity);
    const totalAmount = parseFloat(t.total_amount);

    if (t.transaction_type === 'BUY') {
      currentQuantity += quantity;
      currentInvested += totalAmount;
    } else if (t.transaction_type === 'SELL') {
      if (currentQuantity === 0) {
        console.log(`⚠️  Vendita (SELL) su quantità zero - Transazione ignorata`);
        continue;
      }

      const averageCostPerShare = currentInvested / currentQuantity;
      const costOfSale = quantity * averageCostPerShare;

      currentQuantity -= quantity;
      currentInvested -= costOfSale;

      // Prevenzione errori su virgola mobile
      if (currentQuantity <= 0.00001) {
        currentQuantity = 0;
        currentInvested = 0;
      }
    }

    historicalState.push({
      date: new Date(t.transaction_date),
      quantity: currentQuantity,
      invested: currentInvested,
    });
  }

  return historicalState;
}

/**
 * Mappa lo stato storico alle quantità per mese
 * @param {Array} historicalState - Stati storici da calculateAverageCostBasis
 * @param {Array} monthKeys - Array di chiavi mese formato 'YYYY-MM-01'
 * @returns {Object} - { quantityByMonth, investedByMonth }
 */
function mapStateToMonths(historicalState, monthKeys) {
  const quantityByMonth = {};
  const investedByMonth = {};

  for (const monthKey of monthKeys) {
    const monthEnd = new Date(monthKey);
    monthEnd.setMonth(monthEnd.getMonth() + 1);
    monthEnd.setDate(0);
    monthEnd.setHours(23, 59, 59, 999);

    let lastState = null;
    for (let i = historicalState.length - 1; i >= 0; i--) {
      if (historicalState[i].date <= monthEnd) {
        lastState = historicalState[i];
        break;
      }
    }

    if (lastState) {
      quantityByMonth[monthKey] = lastState.quantity;
      investedByMonth[monthKey] = lastState.invested;
    } else {
      quantityByMonth[monthKey] = 0;
      investedByMonth[monthKey] = 0;
    }
  }

  return { quantityByMonth, investedByMonth };
}

/**
 * Genera array di mesi nel range specificato
 * @param {Date} startDate - Data inizio
 * @param {Date} endDate - Data fine
 * @returns {Array<string>} - Array di chiavi mese formato 'YYYY-MM-01'
 */
function generateMonthKeys(startDate, endDate) {
  const months = [];
  for (
    let d = new Date(startDate);
    d <= endDate;
    d = new Date(d.getFullYear(), d.getMonth() + 1, 1)
  ) {
    const monthKey = `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}-01`;
    months.push(monthKey);
  }
  return months;
}

module.exports = {
  calculateAverageCostBasis,
  mapStateToMonths,
  generateMonthKeys,
};
