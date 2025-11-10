// ============================================
// COMPOSITION CALCULATOR SERVICE
// Implements correct "look-through" analysis for portfolio composition
// ============================================

/**
 * CALCOLO LOOK-THROUGH (CORRETTO)
 *
 * IMPORTANTE: Nel database, weight_percent è DECIMALE (0-1), NON percentuale (0-100)
 *             Es: 0.10 = 10%, 0.255 = 25.5%, 1.00 = 100%
 *
 * Per ogni categoria di analisi (geografica, settoriale, ecc.):
 * 1. Per ciascun asset, calcola il controvalore assoluto di quella categoria:
 *    Controvalore_Categoria_Asset = Valore_Asset * Peso_Decimale
 *    Es: €200,000 * 0.10 = €20,000
 *
 * 2. Somma i controvalori assoluti di quella categoria da tutti gli asset:
 *    Totale_Categoria_Euro = SUM(Controvalore_Categoria_Asset)
 *    Es: €20,000 + €500 = €20,500
 *
 * 3. Calcola il controvalore totale del portafoglio:
 *    Controvalore_Totale_Portafoglio = SUM(Valore_Asset)
 *    Es: €200,000 + €500 = €200,500
 *
 * 4. La percentuale ponderata finale (in decimale):
 *    Percentuale_Finale_Decimale = Totale_Categoria_Euro / Controvalore_Totale_Portafoglio
 *    Es: €20,500 / €200,500 = 0.1022
 *    Per display: 0.1022 * 100 = 10.22%
 */

const pool = require('../config/database');

/**
 * Costruisce una query SQL per calcolo look-through generico
 * @param {string} table - Nome della tabella (etf_sector_weights, etf_geographic_weights, etc.)
 * @param {string} categoryColumn - Nome della colonna categoria (sector_name, region_name, etc.)
 * @param {string} weightColumn - Nome della colonna peso (weight_percent)
 * @param {Array<string>} excludeValues - Valori da escludere (es. ['Altri', 'Other', 'N/A'])
 * @param {Object} options - Opzioni aggiuntive
 * @returns {string} Query SQL
 */
function buildLookThroughQuery(table, categoryColumn, weightColumn = 'weight_percent', excludeValues = [], options = {}) {
  const {
    limit = null,
    orderBy = 'weighted_percent DESC',
    categoryTransform = null, // Funzione CASE WHEN per normalizzare nomi
    additionalColumns = [], // Colonne aggiuntive da includere (es. AVG(duration))
    joinCondition = 'ON t.asset_id = p.asset_id',
    whereCondition = '',
  } = options;

  // Costruisci la selezione della categoria
  const categorySelect = categoryTransform || `t.${categoryColumn}`;

  // Costruisci GROUP BY (se c'è transform, usa quello, altrimenti la colonna)
  const groupByCategory = categoryTransform || `t.${categoryColumn}`;

  // Costruisci SELECT per colonne aggiuntive
  const additionalSelect = additionalColumns.length > 0
    ? ', ' + additionalColumns.join(', ')
    : '';

  // Costruisci WHERE per esclusioni
  let excludeWhere = '';
  if (excludeValues.length > 0) {
    const escapedValues = excludeValues.map(v => `'${v.replace(/'/g, "''")}'`).join(', ');
    excludeWhere = `AND t.${categoryColumn} NOT IN (${escapedValues})`;
  }

  // Costruisci WHERE aggiuntivo
  const additionalWhere = whereCondition ? `AND ${whereCondition}` : '';

  // FORMULA LOOK-THROUGH CORRETTA:
  // Nel DB: weight_percent è DECIMALE (0-1), es. 0.255 = 25.5%, 0.10 = 10%
  // Passo 1: Controvalore assoluto = weight_percent * current_value
  //          Es: Asset A (€200k, 10% USA) → 0.10 * €200,000 = €20,000
  //          Es: Asset B (€500, 100% USA) → 1.00 * €500 = €500
  // Passo 2: Somma controvalori = SUM(weight_percent * current_value)
  //          €20,000 + €500 = €20,500
  // Passo 3: Totale portafoglio = SUM(current_value)
  //          €200,000 + €500 = €200,500
  // Passo 4: Percentuale finale = Somma / Totale (in decimale)
  //          €20,500 / €200,500 = 0.1022 (moltiplicare *100 per display → 10.22%)

  const query = `
    SELECT
      ${categorySelect} as ${categoryColumn},
      SUM(t.${weightColumn} * p.current_value) / NULLIF(SUM(p.current_value), 0) AS weighted_percent
      ${additionalSelect}
    FROM ${table} t
    JOIN v_current_positions p ${joinCondition}
    WHERE 1=1
      ${excludeWhere}
      ${additionalWhere}
    GROUP BY ${groupByCategory}
    ORDER BY ${orderBy}
    ${limit ? `LIMIT ${limit}` : ''}
  `.trim();

  return query;
}

/**
 * Esegue una query look-through per un singolo portafoglio
 * @param {number} portfolioId - ID del portafoglio
 * @param {string} table - Nome della tabella
 * @param {string} categoryColumn - Nome della colonna categoria
 * @param {Object} options - Opzioni query
 * @returns {Promise<Array>} Risultati
 */
async function calculateLookThrough(portfolioId, table, categoryColumn, options = {}) {
  const query = buildLookThroughQuery(table, categoryColumn, 'weight_percent', options.exclude || [], {
    ...options,
    whereCondition: `p.portfolio_id = $1${options.whereCondition ? ' AND ' + options.whereCondition : ''}`,
  });

  const result = await pool.query(query, [portfolioId]);

  // Converti da decimale (0.255) a percentuale (25.5) se richiesto
  if (options.asPercentage !== false) {
    result.rows = result.rows.map(row => ({
      ...row,
      weighted_percent: parseFloat((row.weighted_percent * 100).toFixed(2))
    }));
  }

  return result.rows;
}

/**
 * Esegue una query look-through per più portafogli
 * @param {Array<number>} portfolioIds - Array di IDs portafogli
 * @param {string} table - Nome della tabella
 * @param {string} categoryColumn - Nome della colonna categoria
 * @param {Object} options - Opzioni query
 * @returns {Promise<Array>} Risultati
 */
async function calculateMultiPortfolioLookThrough(portfolioIds, table, categoryColumn, options = {}) {
  const query = buildLookThroughQuery(table, categoryColumn, 'weight_percent', options.exclude || [], {
    ...options,
    whereCondition: `p.portfolio_id = ANY($1)${options.whereCondition ? ' AND ' + options.whereCondition : ''}`,
  });

  const result = await pool.query(query, [portfolioIds]);

  // Converti da decimale a percentuale se richiesto
  if (options.asPercentage !== false) {
    result.rows = result.rows.map(row => ({
      ...row,
      weighted_percent: parseFloat((row.weighted_percent * 100).toFixed(2))
    }));
  }

  return result.rows;
}

/**
 * Esegue una query look-through per specifici asset
 * @param {Array<number>} assetIds - Array di asset IDs
 * @param {number|null} portfolioId - ID portafoglio (opzionale, per ponderazione)
 * @param {string} table - Nome della tabella
 * @param {string} categoryColumn - Nome della colonna categoria
 * @param {Object} options - Opzioni query
 * @returns {Promise<Array>} Risultati
 */
async function calculateMultiAssetLookThrough(assetIds, portfolioId, table, categoryColumn, options = {}) {
  let query, params;

  if (portfolioId) {
    // Pesa in base al valore delle posizioni nel portafoglio
    query = buildLookThroughQuery(table, categoryColumn, 'weight_percent', options.exclude || [], {
      ...options,
      whereCondition: `t.asset_id = ANY($1) AND p.portfolio_id = $2${options.whereCondition ? ' AND ' + options.whereCondition : ''}`,
    });
    params = [assetIds, portfolioId];
  } else {
    // Peso uguale per tutti gli asset (media semplice)
    const categorySelect = options.categoryTransform || `t.${categoryColumn}`;
    const groupByCategory = options.categoryTransform || `t.${categoryColumn}`;
    const additionalSelect = options.additionalColumns ? ', ' + options.additionalColumns.join(', ') : '';

    let excludeWhere = '';
    if (options.exclude && options.exclude.length > 0) {
      const escapedValues = options.exclude.map(v => `'${v.replace(/'/g, "''")}'`).join(', ');
      excludeWhere = `AND t.${categoryColumn} NOT IN (${escapedValues})`;
    }

    query = `
      SELECT
        ${categorySelect} as ${categoryColumn},
        AVG(t.weight_percent) AS weighted_percent
        ${additionalSelect}
      FROM ${table} t
      WHERE t.asset_id = ANY($1)
        ${excludeWhere}
        ${options.whereCondition ? `AND ${options.whereCondition}` : ''}
      GROUP BY ${groupByCategory}
      ORDER BY ${options.orderBy || 'weighted_percent DESC'}
      ${options.limit ? `LIMIT ${options.limit}` : ''}
    `.trim();

    params = [assetIds];
  }

  const result = await pool.query(query, params);

  // Converti da decimale a percentuale se richiesto
  if (options.asPercentage !== false && !portfolioId) {
    // Se non c'è portfolio, AVG restituisce già percentuale
    result.rows = result.rows.map(row => ({
      ...row,
      weighted_percent: parseFloat(row.weighted_percent.toFixed(2))
    }));
  } else if (options.asPercentage !== false) {
    result.rows = result.rows.map(row => ({
      ...row,
      weighted_percent: parseFloat((row.weighted_percent * 100).toFixed(2))
    }));
  }

  return result.rows;
}

/**
 * Calcola statistiche aggregate per validare i calcoli
 * @param {Array<Object>} results - Risultati query
 * @returns {Object} Statistiche
 */
function calculateStats(results) {
  const total = results.reduce((sum, row) => sum + parseFloat(row.weighted_percent || 0), 0);
  const count = results.length;

  return {
    total: parseFloat(total.toFixed(2)),
    count,
    average: count > 0 ? parseFloat((total / count).toFixed(2)) : 0,
    isValid: Math.abs(total - 100) < 0.01, // Tolleranza 0.01% per arrotondamenti
  };
}

module.exports = {
  buildLookThroughQuery,
  calculateLookThrough,
  calculateMultiPortfolioLookThrough,
  calculateMultiAssetLookThrough,
  calculateStats,
};
