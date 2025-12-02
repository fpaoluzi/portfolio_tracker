// ============================================
// IMPORT CONTROLLER
// Handles Excel import operations
// ============================================

const pool = require('../config/database');
const xlsx = require('xlsx');
const fs = require('fs');
const path = require('path');

/**
 * POST /api/import/excel
 * Importa transazioni da file Excel
 */
async function importExcel(req, res) {
    const logFile = path.join(__dirname, '../../debug_import.log');
    const log = (msg) => {
        try {
            fs.appendFileSync(logFile, msg + '\n');
        } catch (e) {
            console.error('Failed to write to log file:', e);
        }
    };

    log('\n\n--- START IMPORT --- ' + new Date().toISOString());

    let client;

    try {
        if (!req.body.portfolioId) {
            log('ERROR: Missing portfolioId in body');
            return res.status(400).json({ success: false, error: 'Portfolio ID mancante' });
        }

        log(`Portfolio ID: ${req.body.portfolioId}`);
        // Parse Excel file
        log('Reading Excel file buffer...');
        const workbook = xlsx.read(req.file.buffer, { type: 'buffer' });
        const sheetName = workbook.SheetNames[0];
        log(`Sheet name: ${sheetName}`);
        const worksheet = workbook.Sheets[sheetName];

        // Convert to array of arrays to find header row
        const rawData = xlsx.utils.sheet_to_json(worksheet, { header: 1 });
        log(`Total raw rows: ${rawData.length}`);

        let headerRowIndex = -1;
        let headers = [];

        // Find header row dynamically
        // We look for a row containing 'ISIN' and ('Titolo' or 'Descrizione' or 'Strumento')
        for (let i = 0; i < Math.min(20, rawData.length); i++) {
            const row = rawData[i];
            if (!row || !Array.isArray(row)) continue;

            const rowStr = JSON.stringify(row).toLowerCase();
            if (rowStr.includes('isin') && (rowStr.includes('titolo') || rowStr.includes('descrizione') || rowStr.includes('strumento'))) {
                headerRowIndex = i;
                headers = row;
                break;
            }
        }

        if (headerRowIndex === -1) {
            log('ERROR: Could not find header row');
            return res.status(400).json({
                success: false,
                error: 'Impossibile trovare la riga di intestazione (cercati: ISIN, Titolo/Descrizione)'
            });
        }

        log(`Header row found at index ${headerRowIndex} (Row ${headerRowIndex + 1}): ${headers.join(', ')}`);

        // Parse data using found header
        const data = xlsx.utils.sheet_to_json(worksheet, { range: headerRowIndex });
        log(`Data rows found: ${data.length}`);

        log('Connecting to database...');
        client = await pool.connect();
        log('Database connected.');

        await client.query('BEGIN');

        let imported = 0;
        let skipped = 0;
        const errors = [];
        const createdAssets = new Set();

        // Helper function to get value from row with case-insensitive column matching
        const normalizeKey = (k) => String(k || '')
            .toLowerCase()
            .replace(/\u00a0/g, ' ')
            .replace(/\s+/g, ' ')
            .trim();

        const getRowValue = (row, ...columnNames) => {
            const normalizedRow = {};
            for (const key in row) {
                normalizedRow[normalizeKey(key)] = row[key];
            }

            for (const colName of columnNames) {
                const value = normalizedRow[normalizeKey(colName)];
                if (value !== undefined && value !== null && value !== '') {
                    return value;
                }
            }
            return undefined;
        };

        const parseNumber = (val, def = 0) => {
            if (val === undefined || val === null || val === '') return def;
            if (typeof val === 'number') return val;
            let s = String(val).trim();
            // Normalize spaces and NBSP
            s = s.replace(/\u00a0/g, '').replace(/\s+/g, '');

            const hasComma = s.includes(',');
            const hasDot = s.includes('.');

            if (hasComma && hasDot) {
                // Decide decimal separator by last occurrence
                const lastComma = s.lastIndexOf(',');
                const lastDot = s.lastIndexOf('.');
                if (lastComma > lastDot) {
                    // comma is decimal, dot is thousands
                    s = s.replace(/\./g, '').replace(',', '.');
                } else {
                    // dot is decimal, comma is thousands
                    s = s.replace(/,/g, '');
                }
            } else if (hasComma) {
                // Only comma present: treat as decimal
                s = s.replace(',', '.');
            } else if (hasDot) {
                // Only dots: ensure single decimal dot (remove thousand separators)
                const parts = s.split('.');
                if (parts.length > 2) {
                    const last = parts.pop();
                    s = parts.join('') + '.' + last;
                }
            }

            const n = parseFloat(s);
            return isNaN(n) ? def : n;
        };

        // Process each row
        for (let i = 0; i < data.length; i++) {
            const row = data[i];
            const rowNum = i + 2;

            try {
                // Extract data from row - case-insensitive matching
                const titolo = getRowValue(row, 'Titolo', 'Descrizione', 'Strumento');
                const isin = getRowValue(row, 'ISIN', 'Isin');
                const quantita = parseNumber(getRowValue(row, 'Quantità', 'Quantita'), 0);
                const prezzo = parseNumber(getRowValue(row, 'Prezzo'), 0);
                const data_str = getRowValue(row, 'Data Valuta', 'Data valuta', 'Data');
                const commissioni = parseNumber(getRowValue(row, 'Commissioni amministrato', 'Commissioni'), 0);
                const divisa = getRowValue(row, 'Divisa') || 'EUR';
                const segnoRaw = getRowValue(row, 'Segno');
                const segnoVal = (segnoRaw === undefined || segnoRaw === null) ? '' : String(segnoRaw).trim().toUpperCase();

                log(`Row ${rowNum}: Titolo="${titolo}", ISIN=${isin}, Qty=${quantita}, Price=${prezzo}, DateRaw="${data_str}", Currency=${divisa}, Segno=${segnoVal}, Commission=${commissioni}`);
                log(`Row ${rowNum}: Available columns: ${Object.keys(row).join(', ')}`);

                // Validate required fields
                if (!isin || isNaN(quantita) || isNaN(prezzo) || !data_str) {
                    log(`Row ${rowNum} SKIPPED: Missing or invalid fields - ISIN=${isin}, Qty=${quantita}, Price=${prezzo}, Date=${data_str}`);
                    skipped++;
                    errors.push({
                        row: `Riga ${rowNum}`,
                        error: `Campi obbligatori mancanti o non validi - ISIN: ${isin || 'mancante'}, Quantità: ${quantita || 'mancante'}, Prezzo: ${prezzo || 'mancante'}, Data: ${data_str || 'mancante'}`
                    });
                    continue;
                }

                // Parse date (support multiple formats)
                let transactionDate;
                if (typeof data_str === 'number') {
                    // Excel serial date
                    const excelEpoch = new Date(1899, 11, 30);
                    transactionDate = new Date(excelEpoch.getTime() + data_str * 86400000);
                } else if (typeof data_str === 'string') {
                    // Try Italian format first: dd/mm/yyyy or dd-mm-yyyy
                    const italianDateMatch = data_str.match(/^(\d{1,2})[\/\-](\d{1,2})[\/\-](\d{4})$/);
                    if (italianDateMatch) {
                        const day = parseInt(italianDateMatch[1], 10);
                        const month = parseInt(italianDateMatch[2], 10) - 1; // Month is 0-indexed
                        const year = parseInt(italianDateMatch[3], 10);
                        transactionDate = new Date(year, month, day);
                        log(`Row ${rowNum}: Parsed Italian date format: ${day}/${month + 1}/${year}`);
                    } else {
                        // Fallback to standard parsing
                        transactionDate = new Date(data_str);
                    }
                } else {
                    transactionDate = new Date(data_str);
                }

                if (isNaN(transactionDate.getTime())) {
                    log(`Row ${rowNum} SKIPPED: Invalid date ${data_str}`);
                    skipped++;
                    errors.push({
                        row: `Riga ${rowNum}`,
                        error: `Data non valida: ${data_str}`
                    });
                    continue;
                }

                const formattedDate = transactionDate.toISOString().split('T')[0];
                log(`Row ${rowNum}: Parsed Date=${formattedDate} from original="${data_str}"`);

                // Check if asset exists, create if not
                let assetResult = await client.query(
                    'SELECT asset_id FROM assets WHERE isin = $1',
                    [isin]
                );

                let assetId;
                if (assetResult.rows.length === 0) {
                    log(`Row ${rowNum}: Asset with ISIN ${isin} not found, creating...`);

                    // Create new asset with fallback name
                    const assetName = titolo || `Asset ${isin}`;
                    const newAssetResult = await client.query(
                        `INSERT INTO assets (isin, name, asset_type, currency)
                         VALUES ($1, $2, $3, $4)
                         RETURNING asset_id`,
                        [isin, assetName, 'EQUITY', divisa]
                    );

                    assetId = newAssetResult.rows[0].asset_id;
                    createdAssets.add(isin);
                    log(`Row ${rowNum}: Created new asset with ID ${assetId}, Name="${assetName}", Currency=${divisa}`);
                } else {
                    assetId = assetResult.rows[0].asset_id;
                    log(`Row ${rowNum}: Found existing asset with ID ${assetId}`);
                }

                if (segnoVal !== 'A' && segnoVal !== 'V') {
                    log(`Row ${rowNum} SKIPPED: Invalid Segno "${segnoRaw}" (allowed: A/V)`);
                    skipped++;
                    errors.push({
                        row: `Riga ${rowNum}`,
                        error: `Segno non valido: ${segnoRaw}. Consentiti solo A o V`
                    });
                    continue;
                }
                const transactionType = segnoVal === 'A' ? 'BUY' : 'SELL';
                const absQuantity = Math.abs(quantita);
                log(`Row ${rowNum}: Transaction Type=${transactionType}, Quantity=${absQuantity}`);

                // Calculate totals
                const totalAmount = absQuantity * prezzo;
                const amountInBaseCurrency = totalAmount;

                // Check for duplicate transaction
                const duplicateCheck = await client.query(
                    `SELECT transaction_id FROM transactions 
           WHERE portfolio_id = $1 
           AND asset_id = $2 
           AND transaction_type = $3
           AND transaction_date = $4
           AND quantity = $5
           AND ABS(total_amount - $6) < 0.01`,
                    [req.body.portfolioId, assetId, transactionType, formattedDate, absQuantity, totalAmount]
                );

                log(`Row ${rowNum}: Duplicates found=${duplicateCheck.rows.length}`);

                if (duplicateCheck.rows.length > 0) {
                    skipped++;
                    errors.push({
                        row: `Riga ${rowNum}`,
                        error: `Transazione duplicata: ${titolo} già registrata per questa data e importo`
                    });
                    continue;
                }

                // Insert transaction
                const transactionNotes = titolo ? `Importato da Excel: ${titolo}` : `Importato da Excel - ISIN: ${isin}`;
                await client.query(
                    `INSERT INTO transactions (
            portfolio_id, asset_id, transaction_type, transaction_date,
            quantity, price_per_share, total_amount, commission, fees, taxes,
            currency, exchange_rate, amount_in_base_currency, notes
          ) VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, $13, $14)`,
                    [
                        req.body.portfolioId,
                        assetId,
                        transactionType,
                        formattedDate,
                        absQuantity,
                        prezzo,
                        totalAmount,
                        commissioni,
                        0, // fees
                        0, // taxes
                        divisa,
                        1.0,
                        amountInBaseCurrency,
                        transactionNotes
                    ]
                );

                log(`Row ${rowNum}: Transaction inserted successfully`);
                imported++;
            } catch (rowError) {
                log(`Row ${rowNum} ERROR: ${rowError.message}`);
                console.error(`Error processing row ${rowNum}:`, rowError);
                errors.push({
                    row: `Riga ${rowNum}`,
                    error: rowError.message
                });
                skipped++;
            }
        }

        await client.query('COMMIT');
        log(`Import finished: Imported=${imported}, Skipped=${skipped}, Created Assets=${createdAssets.size}`);

        let message = `Import completato: ${imported} transazioni importate`;
        if (createdAssets.size > 0) {
            message += `, ${createdAssets.size} nuovi asset creati`;
        }
        if (skipped > 0) {
            message += `, ${skipped} saltate`;
        }

        res.json({
            success: true,
            message,
            results: {
                imported,
                skipped,
                createdAssets: createdAssets.size,
                errors
            }
        });

    } catch (error) {
        if (client) await client.query('ROLLBACK');
        log(`FATAL ERROR: ${error.message}`);
        console.error('Excel import error:', error);
        res.status(500).json({
            success: false,
            error: 'Errore durante l\'import del file Excel',
            details: error.message
        });
    } finally {
        if (client) client.release();
    }
}

module.exports = {
    importExcel
};
