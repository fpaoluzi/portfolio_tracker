// ============================================
// ETF COMPOSITION CONTROLLER (ORCHESTRATOR)
// Gestisce scraping, salvataggio e orchestrazione dei moduli di analisi
// ============================================

const pool = require('../config/database');
const { scrapeJustETF } = require('../services/justETFScraper');
const { extractETFDataFromHTML, checkOllamaAvailability } = require('../services/ollamaService');

// Import moduli di analisi specializzati
const holdingsAnalysis = require('./composition/holdingsAnalysis');
const sectorAnalysis = require('./composition/sectorAnalysis');
const geographicAnalysis = require('./composition/geographicAnalysis');
const allocationAnalysis = require('./composition/allocationAnalysis');
const bondRatingAnalysis = require('./composition/bondRatingAnalysis');
const bondMaturityAnalysis = require('./composition/bondMaturityAnalysis');
const riskStatsAnalysis = require('./composition/riskStatsAnalysis');

/**
 * GET /api/etf-composition/:assetId
 * Recupera i dati di composizione completi per un asset
 * Questa funzione aggrega i risultati di tutti i moduli specializzati
 */
async function getCompositionByAsset(req, res) {
  try {
    const { assetId } = req.params;

    // Recupera tutti i dati di composizione usando i moduli specializzati
    const [holdings, sectors, regions, allocation, bondRatings, bondMaturity] = await Promise.all([
      pool.query('SELECT * FROM etf_holdings WHERE asset_id = $1 ORDER BY rank_position', [assetId]),
      pool.query('SELECT * FROM etf_sector_weights WHERE asset_id = $1 ORDER BY weight_percent DESC', [assetId]),
      pool.query('SELECT * FROM etf_geographic_weights WHERE asset_id = $1 ORDER BY weight_percent DESC', [assetId]),
      pool.query('SELECT * FROM etf_asset_allocation WHERE asset_id = $1 ORDER BY weight_percent DESC', [assetId]),
      pool.query('SELECT * FROM etf_bond_ratings WHERE asset_id = $1 ORDER BY weight_percent DESC', [assetId]),
      pool.query('SELECT * FROM etf_bond_maturity WHERE asset_id = $1 ORDER BY weight_percent DESC', [assetId]),
    ]);

    res.json({
      holdings: holdings.rows,
      sectors: sectors.rows,
      regions: regions.rows,
      allocation: allocation.rows,
      bondRatings: bondRatings.rows,
      bondMaturity: bondMaturity.rows,
      hasData: holdings.rows.length > 0 || sectors.rows.length > 0 || regions.rows.length > 0,
    });
  } catch (err) {
    console.error('Error in getCompositionByAsset:', err);
    res.status(500).json({ error: 'Errore nel recupero composizione ETF' });
  }
}

/**
 * POST /api/etf-composition/asset/:assetId/fetch
 * Recupera dati composizione da JustETF (via Playwright + Ollama) e li salva nel database
 */
async function fetchAndSaveComposition(req, res) {
  const client = await pool.connect();

  try {
    const { assetId } = req.params;

    // Recupera info asset per ottenere l'ISIN
    const assetResult = await client.query('SELECT isin, ticker, name FROM assets WHERE asset_id = $1', [assetId]);

    if (assetResult.rows.length === 0) {
      return res.status(404).json({ error: 'Asset non trovato' });
    }

    const asset = assetResult.rows[0];
    if (!asset.isin) {
      return res.status(400).json({ error: 'Asset non ha un ISIN valido' });
    }

    const timestamp = () => new Date().toISOString();
    console.log(`\n${'='.repeat(80)}`);
    console.log(`📊 [${timestamp()}] START - Fetching ETF composition`);
    console.log(`   Asset: ${asset.name}`);
    console.log(`   ISIN: ${asset.isin}`);
    console.log(`   Asset ID: ${assetId}`);
    console.log(`${'='.repeat(80)}\n`);

    // Verifica disponibilità Ollama
    console.log(`[${timestamp()}] STEP 0/3 - Verifica disponibilità Ollama...`);
    const ollamaModel = process.env.OLLAMA_MODEL || 'deepseek-v3.1:671b-cloud';
    console.log(`   Modello richiesto: ${ollamaModel}`);

    const isOllamaAvailable = await checkOllamaAvailability(ollamaModel);
    if (!isOllamaAvailable) {
      console.error(`   ❌ Ollama non disponibile!`);
      return res.status(503).json({
        error: `Ollama non disponibile o modello ${ollamaModel} non installato`,
        hint: `Esegui: ollama pull ${ollamaModel}`,
      });
    }
    console.log(`   ✅ Ollama disponibile\n`);

    // Step 1: Scraping JustETF con Playwright
    console.log(`[${timestamp()}] STEP 1/3 - Scraping JustETF...`);
    console.log(`   URL: https://www.justetf.com/it/etf-profile.html?isin=${asset.isin}`);
    console.log(`   Timeout: 30s`);
    console.log(`   Headless: true`);

    const startScraping = Date.now();
    const scrapedData = await scrapeJustETF(asset.isin, {
      headless: true,
      timeout: 30000,
    });
    const scrapingDuration = ((Date.now() - startScraping) / 1000).toFixed(2);

    console.log(`   ✅ Scraping completato in ${scrapingDuration}s`);
    console.log(`   HTML length: ${scrapedData.html.length} chars`);
    console.log(`   ETF Name: ${scrapedData.etfName}\n`);

    // Step 2: Estrazione dati con Ollama
    console.log(`[${timestamp()}] STEP 2/3 - Estrazione dati con Ollama...`);
    console.log(`   Modello: ${ollamaModel}`);
    console.log(`   Questo può richiedere 30-60 secondi...`);

    const startExtraction = Date.now();
    const extractedData = await extractETFDataFromHTML(scrapedData.html, asset.isin, ollamaModel);
    const extractionDuration = ((Date.now() - startExtraction) / 1000).toFixed(2);

    console.log(`   ✅ Estrazione completata in ${extractionDuration}s\n`);

    // Valida e normalizza i dati estratti
    console.log(`[${timestamp()}] Validazione dati estratti...`);
    const holdings = extractedData.holdings || [];
    const sectors = extractedData.sectors || [];
    const regions = extractedData.regions || [];
    const allocation = extractedData.allocation || [];
    const bondRatings = extractedData.bondRatings || [];
    const bondMaturity = extractedData.bondMaturity || [];

    console.log(`   - Holdings: ${holdings.length}`);
    console.log(`   - Sectors: ${sectors.length}`);
    console.log(`   - Regions: ${regions.length}`);
    console.log(`   - Allocation: ${allocation.length}`);
    console.log(`   - Bond Ratings: ${bondRatings.length}`);
    console.log(`   - Bond Maturity: ${bondMaturity.length}\n`);

    // Step 3: Inserimento dati nel database
    console.log(`[${timestamp()}] STEP 3/3 - Salvataggio nel database...`);

    const startDbSave = Date.now();

    // Inizia transazione
    console.log(`   BEGIN transaction...`);
    await client.query('BEGIN');

    // Cancella dati precedenti per questo asset
    console.log(`   Pulizia dati esistenti...`);
    await client.query('DELETE FROM etf_holdings WHERE asset_id = $1', [assetId]);
    await client.query('DELETE FROM etf_sector_weights WHERE asset_id = $1', [assetId]);
    await client.query('DELETE FROM etf_geographic_weights WHERE asset_id = $1', [assetId]);
    await client.query('DELETE FROM etf_asset_allocation WHERE asset_id = $1', [assetId]);
    await client.query('DELETE FROM etf_bond_ratings WHERE asset_id = $1', [assetId]);
    await client.query('DELETE FROM etf_bond_maturity WHERE asset_id = $1', [assetId]);

    // Inserisci nuovi holdings
    console.log(`   Inserimento holdings (${holdings.length})...`);
    for (const holding of holdings) {
      await client.query(
        `INSERT INTO etf_holdings (asset_id, holding_symbol, holding_name, holding_percent, rank_position)
         VALUES ($1, $2, $3, $4, $5)`,
        [assetId, holding.holding_symbol || null, holding.holding_name, holding.holding_percent / 100, holding.rank_position]
      );
    }

    // Inserisci nuovi sectors
    console.log(`   Inserimento sectors (${sectors.length})...`);
    for (const sector of sectors) {
      await client.query(
        `INSERT INTO etf_sector_weights (asset_id, sector_name, weight_percent)
         VALUES ($1, $2, $3)`,
        [assetId, sector.sector_name, sector.weight_percent / 100]
      );
    }

    // Inserisci nuove regions
    console.log(`   Inserimento regions (${regions.length})...`);
    for (const region of regions) {
      await client.query(
        `INSERT INTO etf_geographic_weights (asset_id, region_name, weight_percent)
         VALUES ($1, $2, $3)`,
        [assetId, region.region_name, region.weight_percent / 100]
      );
    }

    // Inserisci nuova asset allocation
    console.log(`   Inserimento allocation (${allocation.length})...`);
    for (const alloc of allocation) {
      await client.query(
        `INSERT INTO etf_asset_allocation (asset_id, allocation_type, weight_percent)
         VALUES ($1, $2, $3)`,
        [assetId, alloc.allocation_type, alloc.weight_percent / 100]
      );
    }

    // Inserisci bond ratings (se presenti)
    if (bondRatings.length > 0) {
      console.log(`   Inserimento bond ratings (${bondRatings.length})...`);
      for (const rating of bondRatings) {
        await client.query(
          `INSERT INTO etf_bond_ratings (asset_id, rating_category, weight_percent)
           VALUES ($1, $2, $3)`,
          [assetId, rating.rating_category, rating.weight_percent / 100]
        );
      }
    }

    // Inserisci bond maturity (se presenti)
    if (bondMaturity.length > 0) {
      console.log(`   Inserimento bond maturity (${bondMaturity.length})...`);
      for (const maturity of bondMaturity) {
        await client.query(
          `INSERT INTO etf_bond_maturity (asset_id, maturity_range, weight_percent, avg_duration_years)
           VALUES ($1, $2, $3, $4)`,
          [assetId, maturity.maturity_range, maturity.weight_percent / 100, maturity.avg_duration_years || null]
        );
      }
    }

    // Aggiorna timestamp ultimo aggiornamento
    console.log(`   Aggiornamento timestamp ultimo aggiornamento...`);
    await client.query(
      'UPDATE assets SET composition_last_updated = CURRENT_TIMESTAMP WHERE asset_id = $1',
      [assetId]
    );

    // Commit transazione
    console.log(`   COMMIT transaction...`);
    await client.query('COMMIT');

    const dbSaveDuration = ((Date.now() - startDbSave) / 1000).toFixed(2);

    console.log(`   ✅ Database save completato in ${dbSaveDuration}s\n`);
    console.log(`${'='.repeat(80)}`);
    console.log(`✅ [${timestamp()}] SUCCESS - ETF composition saved`);
    console.log(`   Asset: ${asset.name}`);
    console.log(`   Holdings: ${holdings.length}`);
    console.log(`   Sectors: ${sectors.length}`);
    console.log(`   Regions: ${regions.length}`);
    console.log(`   Allocation: ${allocation.length}`);
    console.log(`${'='.repeat(80)}\n`);

    res.json({
      success: true,
      message: 'Composizione ETF aggiornata con successo',
      stats: {
        holdings: holdings.length,
        sectors: sectors.length,
        regions: regions.length,
        allocation: allocation.length,
        bondRatings: bondRatings.length,
        bondMaturity: bondMaturity.length,
      },
    });
  } catch (err) {
    const timestamp = () => new Date().toISOString();
    await client.query('ROLLBACK');

    console.error(`\n${'='.repeat(80)}`);
    console.error(`❌ [${timestamp()}] ERROR - ETF Composition Fetch Failed`);
    console.error(`${'='.repeat(80)}`);
    console.error(`Error Message: ${err.message}`);
    console.error(`Error Stack:\n${err.stack}`);
    console.error(`${'='.repeat(80)}\n`);

    res.status(500).json({
      error: err.message,
      details: 'Controllare i log del server per maggiori dettagli',
    });
  } finally {
    client.release();
  }
}

/**
 * POST /api/etf-composition/bulk-update
 * Aggiorna la composizione per tutti gli asset (o un subset filtrato) in background
 */
async function bulkUpdateCompositions(req, res) {
  try {
    const { assetIds } = req.body;

    // Query per ottenere gli asset da aggiornare
    let query, params;
    if (assetIds && assetIds.length > 0) {
      query = 'SELECT asset_id, isin, ticker, name FROM assets WHERE asset_id = ANY($1) AND is_active = true';
      params = [assetIds];
    } else {
      query = 'SELECT asset_id, isin, ticker, name FROM assets WHERE ticker IS NOT NULL AND is_active = true';
      params = [];
    }

    const result = await pool.query(query, params);
    const assets = result.rows;

    if (assets.length === 0) {
      return res.status(404).json({ error: 'Nessun asset trovato da aggiornare' });
    }

    // Rispondi immediatamente al client
    res.json({
      success: true,
      message: `Aggiornamento in background avviato per ${assets.length} asset`,
      assetsCount: assets.length,
    });

    // Processo in background
    console.log(`\n${'='.repeat(80)}`);
    console.log(`🚀 BULK UPDATE STARTED - ${assets.length} assets`);
    console.log(`${'='.repeat(80)}\n`);

    const results = {
      successful: [],
      failed: [],
      skipped: [],
    };

    // Verifica disponibilità Ollama una sola volta
    const ollamaModel = process.env.OLLAMA_MODEL || 'deepseek-v3.1:671b-cloud';
    const isOllamaAvailable = await checkOllamaAvailability(ollamaModel);

    if (!isOllamaAvailable) {
      console.error(`❌ Ollama non disponibile. Interrompo il bulk update.`);
      return;
    }

    for (let i = 0; i < assets.length; i++) {
      const asset = assets[i];
      console.log(`\n[${i + 1}/${assets.length}] Processing: ${asset.name} (${asset.isin})`);

      try {
        if (!asset.isin) {
          console.log(`⚠️  SKIPPED - No ISIN for ${asset.name}`);
          results.skipped.push({ isin: asset.isin, name: asset.name, reason: 'No ISIN' });
          continue;
        }

        const client = await pool.connect();

        try {
          // Scraping
          const scrapedData = await scrapeJustETF(asset.isin, {
            headless: true,
            timeout: 30000,
          });

          // Estrazione con Ollama
          const extractedData = await extractETFDataFromHTML(scrapedData.html, asset.isin, ollamaModel);

          const holdings = extractedData.holdings || [];
          const sectors = extractedData.sectors || [];
          const regions = extractedData.regions || [];
          const allocation = extractedData.allocation || [];
          const bondRatings = extractedData.bondRatings || [];
          const bondMaturity = extractedData.bondMaturity || [];

          // Nessun dato estratto
          if (holdings.length === 0 && sectors.length === 0 && regions.length === 0) {
            console.log(`⚠️  SKIPPED - No data available for ${asset.name}`);
            results.skipped.push({ isin: asset.isin, name: asset.name, reason: 'No data available' });
            client.release();
            continue;
          }

          // Salva nel database
          await client.query('BEGIN');

          await client.query('DELETE FROM etf_holdings WHERE asset_id = $1', [asset.asset_id]);
          await client.query('DELETE FROM etf_sector_weights WHERE asset_id = $1', [asset.asset_id]);
          await client.query('DELETE FROM etf_geographic_weights WHERE asset_id = $1', [asset.asset_id]);
          await client.query('DELETE FROM etf_asset_allocation WHERE asset_id = $1', [asset.asset_id]);
          await client.query('DELETE FROM etf_bond_ratings WHERE asset_id = $1', [asset.asset_id]);
          await client.query('DELETE FROM etf_bond_maturity WHERE asset_id = $1', [asset.asset_id]);

          for (const holding of holdings) {
            await client.query(
              `INSERT INTO etf_holdings (asset_id, holding_symbol, holding_name, holding_percent, rank_position)
               VALUES ($1, $2, $3, $4, $5)`,
              [asset.asset_id, holding.holding_symbol || null, holding.holding_name, holding.holding_percent / 100, holding.rank_position]
            );
          }

          for (const sector of sectors) {
            await client.query(
              `INSERT INTO etf_sector_weights (asset_id, sector_name, weight_percent) VALUES ($1, $2, $3)`,
              [asset.asset_id, sector.sector_name, sector.weight_percent / 100]
            );
          }

          for (const region of regions) {
            await client.query(
              `INSERT INTO etf_geographic_weights (asset_id, region_name, weight_percent) VALUES ($1, $2, $3)`,
              [asset.asset_id, region.region_name, region.weight_percent / 100]
            );
          }

          for (const alloc of allocation) {
            await client.query(
              `INSERT INTO etf_asset_allocation (asset_id, allocation_type, weight_percent) VALUES ($1, $2, $3)`,
              [asset.asset_id, alloc.allocation_type, alloc.weight_percent / 100]
            );
          }

          if (bondRatings.length > 0) {
            for (const rating of bondRatings) {
              await client.query(
                `INSERT INTO etf_bond_ratings (asset_id, rating_category, weight_percent) VALUES ($1, $2, $3)`,
                [asset.asset_id, rating.rating_category, rating.weight_percent / 100]
              );
            }
          }

          if (bondMaturity.length > 0) {
            for (const maturity of bondMaturity) {
              await client.query(
                `INSERT INTO etf_bond_maturity (asset_id, maturity_range, weight_percent, avg_duration_years) VALUES ($1, $2, $3, $4)`,
                [asset.asset_id, maturity.maturity_range, maturity.weight_percent / 100, maturity.avg_duration_years || null]
              );
            }
          }

          // Aggiorna timestamp
          await client.query(
            'UPDATE assets SET composition_last_updated = CURRENT_TIMESTAMP WHERE asset_id = $1',
            [asset.asset_id]
          );

          await client.query('COMMIT');

          console.log(`✅ SUCCESS - ${asset.name} (H:${holdings.length} S:${sectors.length} R:${regions.length})`);
          results.successful.push({ isin: asset.isin, name: asset.name });

        } catch (err) {
          await client.query('ROLLBACK');

          // Verifica se è un errore bloccante
          if (err.code === 'ECONNREFUSED' || err.code === 'ETIMEDOUT' || err.message.includes('database')) {
            console.error(`❌ CRITICAL ERROR - Stopping bulk update: ${err.message}`);
            client.release();
            break;
          }

          console.log(`⚠️  FAILED - ${asset.name}: ${err.message}`);
          results.failed.push({ isin: asset.isin, name: asset.name, error: err.message });

        } finally {
          client.release();
        }

      } catch (err) {
        if (err.code === 'ECONNREFUSED' || err.code === 'ETIMEDOUT' || err.message.includes('database')) {
          console.error(`❌ CRITICAL ERROR - Stopping bulk update: ${err.message}`);
          break;
        }

        console.log(`⚠️  FAILED - ${asset.name}: ${err.message}`);
        results.failed.push({ isin: asset.isin, name: asset.name, error: err.message });
      }
    }

    console.log(`\n${'='.repeat(80)}`);
    console.log(`✅ BULK UPDATE COMPLETED`);
    console.log(`   Successful: ${results.successful.length}`);
    console.log(`   Failed: ${results.failed.length}`);
    console.log(`   Skipped: ${results.skipped.length}`);
    console.log(`${'='.repeat(80)}\n`);

  } catch (err) {
    console.error('Error in bulkUpdateCompositions:', err);
  }
}

/**
 * DELETE /api/etf-composition/:assetId
 * Cancella i dati di composizione di un asset
 */
async function deleteCompositionByAsset(req, res) {
  const client = await pool.connect();

  try {
    const { assetId } = req.params;

    console.log(`\n🗑️  Cancellazione composizione per asset ID: ${assetId}`);

    const assetCheck = await pool.query('SELECT name, asset_type FROM assets WHERE asset_id = $1', [assetId]);

    if (assetCheck.rows.length === 0) {
      return res.status(404).json({ error: 'Asset non trovato' });
    }

    const assetName = assetCheck.rows[0].name;
    const assetType = assetCheck.rows[0].asset_type;

    console.log(`   Asset: ${assetName} (${assetType})`);

    await client.query('BEGIN');

    console.log(`   Cancellazione holdings...`);
    const holdingsResult = await client.query('DELETE FROM etf_holdings WHERE asset_id = $1', [assetId]);

    console.log(`   Cancellazione sector weights...`);
    const sectorsResult = await client.query('DELETE FROM etf_sector_weights WHERE asset_id = $1', [assetId]);

    console.log(`   Cancellazione geographic weights...`);
    const regionsResult = await client.query('DELETE FROM etf_geographic_weights WHERE asset_id = $1', [assetId]);

    console.log(`   Cancellazione asset allocation...`);
    const allocationResult = await client.query('DELETE FROM etf_asset_allocation WHERE asset_id = $1', [assetId]);

    console.log(`   Cancellazione bond ratings...`);
    const ratingsResult = await client.query('DELETE FROM etf_bond_ratings WHERE asset_id = $1', [assetId]);

    console.log(`   Cancellazione bond maturity...`);
    const maturityResult = await client.query('DELETE FROM etf_bond_maturity WHERE asset_id = $1', [assetId]);

    console.log(`   Reset timestamp ultimo aggiornamento...`);
    await client.query('UPDATE assets SET composition_last_updated = NULL WHERE asset_id = $1', [assetId]);

    await client.query('COMMIT');

    const deletedCount =
      holdingsResult.rowCount +
      sectorsResult.rowCount +
      regionsResult.rowCount +
      allocationResult.rowCount +
      ratingsResult.rowCount +
      maturityResult.rowCount;

    console.log(`   ✅ Cancellazione completata: ${deletedCount} record rimossi\n`);

    res.json({
      success: true,
      message: `Composizione cancellata con successo per ${assetName}`,
      deletedRecords: {
        holdings: holdingsResult.rowCount,
        sectors: sectorsResult.rowCount,
        regions: regionsResult.rowCount,
        allocation: allocationResult.rowCount,
        bondRatings: ratingsResult.rowCount,
        bondMaturity: maturityResult.rowCount,
        total: deletedCount
      }
    });

  } catch (err) {
    await client.query('ROLLBACK');
    console.error('❌ Error deleting composition:', err);
    res.status(500).json({
      error: 'Errore durante la cancellazione della composizione',
      details: err.message
    });
  } finally {
    client.release();
  }
}

/**
 * POST /api/etf-composition/asset/:assetId/manual
 * Salva manualmente i dati di composizione inseriti dall'utente
 */
async function saveManualComposition(req, res) {
  const client = await pool.connect();

  try {
    const { assetId } = req.params;
    const { holdings, sectors, regions, allocation, bondRatings, bondMaturity } = req.body;

    console.log(`\n📝 Salvataggio manuale composizione per asset ID: ${assetId}`);

    const assetCheck = await pool.query('SELECT name, asset_type FROM assets WHERE asset_id = $1', [assetId]);

    if (assetCheck.rows.length === 0) {
      return res.status(404).json({ error: 'Asset non trovato' });
    }

    const assetName = assetCheck.rows[0].name;
    const assetType = assetCheck.rows[0].asset_type;

    console.log(`   Asset: ${assetName} (${assetType})`);

    await client.query('BEGIN');

    // Cancella dati esistenti
    console.log(`   Cancellazione dati esistenti...`);
    await client.query('DELETE FROM etf_holdings WHERE asset_id = $1', [assetId]);
    await client.query('DELETE FROM etf_sector_weights WHERE asset_id = $1', [assetId]);
    await client.query('DELETE FROM etf_geographic_weights WHERE asset_id = $1', [assetId]);
    await client.query('DELETE FROM etf_asset_allocation WHERE asset_id = $1', [assetId]);
    await client.query('DELETE FROM etf_bond_ratings WHERE asset_id = $1', [assetId]);
    await client.query('DELETE FROM etf_bond_maturity WHERE asset_id = $1', [assetId]);

    let stats = {
      holdings: 0,
      sectors: 0,
      regions: 0,
      allocation: 0,
      bondRatings: 0,
      bondMaturity: 0
    };

    // Inserisci Holdings
    if (holdings && holdings.length > 0) {
      console.log(`   Inserimento ${holdings.length} holdings...`);
      for (const holding of holdings) {
        await client.query(
          `INSERT INTO etf_holdings (asset_id, holding_symbol, holding_name, holding_percent, rank_position)
           VALUES ($1, $2, $3, $4, $5)`,
          [assetId, holding.symbol || null, holding.name, holding.percent / 100, holding.rank || 0]
        );
        stats.holdings++;
      }
    }

    // Inserisci Sectors
    if (sectors && sectors.length > 0) {
      console.log(`   Inserimento ${sectors.length} settori...`);
      for (const sector of sectors) {
        await client.query(
          `INSERT INTO etf_sector_weights (asset_id, sector_name, weight_percent)
           VALUES ($1, $2, $3)`,
          [assetId, sector.name, sector.percent / 100]
        );
        stats.sectors++;
      }
    }

    // Inserisci Regions
    if (regions && regions.length > 0) {
      console.log(`   Inserimento ${regions.length} regioni...`);
      for (const region of regions) {
        await client.query(
          `INSERT INTO etf_geographic_weights (asset_id, region_name, weight_percent)
           VALUES ($1, $2, $3)`,
          [assetId, region.name, region.percent / 100]
        );
        stats.regions++;
      }
    }

    // Inserisci Asset Allocation
    if (allocation && allocation.length > 0) {
      console.log(`   Inserimento ${allocation.length} asset allocation...`);
      for (const alloc of allocation) {
        await client.query(
          `INSERT INTO etf_asset_allocation (asset_id, allocation_type, weight_percent)
           VALUES ($1, $2, $3)`,
          [assetId, alloc.type, alloc.percent / 100]
        );
        stats.allocation++;
      }
    }

    // Inserisci Bond Ratings
    if (bondRatings && bondRatings.length > 0) {
      console.log(`   Inserimento ${bondRatings.length} bond ratings...`);
      for (const rating of bondRatings) {
        await client.query(
          `INSERT INTO etf_bond_ratings (asset_id, rating_category, weight_percent)
           VALUES ($1, $2, $3)`,
          [assetId, rating.category, rating.percent / 100]
        );
        stats.bondRatings++;
      }
    }

    // Inserisci Bond Maturity
    if (bondMaturity && bondMaturity.length > 0) {
      console.log(`   Inserimento ${bondMaturity.length} bond maturity...`);
      for (const maturity of bondMaturity) {
        await client.query(
          `INSERT INTO etf_bond_maturity (asset_id, maturity_range, weight_percent, avg_duration_years)
           VALUES ($1, $2, $3, $4)`,
          [assetId, maturity.range, maturity.percent / 100, maturity.duration || null]
        );
        stats.bondMaturity++;
      }
    }

    // Aggiorna timestamp
    console.log(`   Aggiornamento timestamp...`);
    await client.query(
      'UPDATE assets SET composition_last_updated = CURRENT_TIMESTAMP WHERE asset_id = $1',
      [assetId]
    );

    await client.query('COMMIT');

    console.log(`   ✅ Composizione salvata manualmente\n`);

    res.json({
      success: true,
      message: `Composizione salvata manualmente per ${assetName}`,
      stats
    });

  } catch (err) {
    await client.query('ROLLBACK');
    console.error('❌ Error saving manual composition:', err);
    res.status(500).json({
      error: 'Errore durante il salvataggio della composizione manuale',
      details: err.message
    });
  } finally {
    client.release();
  }
}

// Esporta le funzioni del controller principale
module.exports = {
  getCompositionByAsset,
  fetchAndSaveComposition,
  bulkUpdateCompositions,
  deleteCompositionByAsset,
  saveManualComposition,

  // Esporta anche i moduli di analisi per uso nelle routes
  holdingsAnalysis,
  sectorAnalysis,
  geographicAnalysis,
  allocationAnalysis,
  bondRatingAnalysis,
  bondMaturityAnalysis,
  riskStatsAnalysis,
};
