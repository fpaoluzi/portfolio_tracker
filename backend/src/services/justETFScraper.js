// ============================================
// JUSTETF SCRAPER SERVICE
// Scraping automatico di dati ETF da JustETF usando Playwright
// ============================================

const { chromium } = require('playwright');

/**
 * Costruisce l'URL di JustETF dato un ISIN
 * @param {string} isin - ISIN dell'ETF
 * @returns {string} - URL completo della pagina JustETF
 */
function buildJustETFUrl(isin) {
  return `https://www.justetf.com/it/etf-profile.html?isin=${isin}#informazioni-basilari`;
}

/**
 * Scraping completo della pagina JustETF per un dato ISIN
 * Include navigazione, espansione elementi dinamici e raccolta HTML
 * @param {string} isin - ISIN dell'ETF da scrapare
 * @param {Object} options - Opzioni di configurazione
 * @returns {Promise<Object>} - HTML completo e metadata
 */
async function scrapeJustETF(isin, options = {}) {
  const {
    headless = true,
    timeout = 30000,
    waitForNetworkIdle = true,
  } = options;

  let browser = null;
  let context = null;
  let page = null;

  try {
    console.log(`[JustETF Scraper] Avvio scraping per ISIN: ${isin}`);

    // Avvia browser
    browser = await chromium.launch({
      headless: headless,
      args: ['--disable-blink-features=AutomationControlled'], // Evita detection come bot
    });

    // Crea contesto con user agent realistico
    context = await browser.newContext({
      userAgent: 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
      viewport: { width: 1920, height: 1080 },
      locale: 'it-IT',
    });

    page = await context.newPage();

    // Costruisci URL
    const url = buildJustETFUrl(isin);
    console.log(`[JustETF Scraper] Navigazione a: ${url}`);

    // Naviga alla pagina
    await page.goto(url, {
      timeout: timeout,
      waitUntil: waitForNetworkIdle ? 'networkidle' : 'domcontentloaded',
    });

    console.log(`[JustETF Scraper] Pagina caricata`);

    // Attendi che la pagina sia completamente renderizzata
    await page.waitForTimeout(2000);

    // === GESTIONE COOKIE BANNER ===
    try {
      const cookieButtonSelectors = [
        'button:has-text("Accetta")',
        'button:has-text("Accetto")',
        'button:has-text("Accept")',
        '[id*="accept"]',
        '[class*="accept"]',
        '.cookie-accept',
        '#cookie-accept',
      ];

      for (const selector of cookieButtonSelectors) {
        try {
          const button = await page.$(selector);
          if (button) {
            await button.click();
            console.log(`[JustETF Scraper] Cookie banner accettato`);
            await page.waitForTimeout(1000);
            break;
          }
        } catch (e) {
          // Continua con il prossimo selettore
        }
      }
    } catch (error) {
      console.log(`[JustETF Scraper] Nessun cookie banner trovato o già accettato`);
    }

    // === ESPANSIONE ELEMENTI "MOSTRA DI PIÙ" (solo sezioni rilevanti) ===
    await expandAllShowMoreButtons(page);

    // Attendi rendering finale
    await page.waitForTimeout(1500);

    // Estrai SOLO le sezioni rilevanti come TESTO (no HTML)
    console.log(`[JustETF Scraper] Estrazione sezioni rilevanti (solo testo)...`);
    const relevantText = await extractRelevantSections(page);

    // Estrai metadata utili
    const title = await page.title();
    const etfName = await extractETFName(page);

    const estimatedTokens = Math.ceil(relevantText.length / 4);
    console.log(`[JustETF Scraper] Scraping completato per: ${etfName || isin}`);
    console.log(`[JustETF Scraper] Testo estratto: ${relevantText.length} chars (~${estimatedTokens} tokens)`);

    return {
      isin: isin,
      url: url,
      html: relevantText, // Testo pulito (no HTML tags)
      title: title,
      etfName: etfName,
      scrapedAt: new Date().toISOString(),
    };
  } catch (error) {
    console.error(`[JustETF Scraper] Errore durante scraping:`, error.message);
    throw new Error(`JustETF scraping error: ${error.message}`);
  } finally {
    // Cleanup
    if (page) await page.close();
    if (context) await context.close();
    if (browser) await browser.close();
    console.log(`[JustETF Scraper] Browser chiuso`);
  }
}

/**
 * Estrae solo le sezioni rilevanti della pagina per ridurre i token
 * @param {Page} page - Pagina Playwright
 * @returns {Promise<string>} - HTML concatenato delle sezioni rilevanti
 */
async function extractRelevantSections(page) {
  console.log(`[JustETF Scraper]    Estrazione dati da tabelle specifiche JustETF...`);

  // Estrai SOLO le tabelle specifiche usando data-testid
  const extractedData = await page.evaluate(() => {
    const data = {
      holdings: '',
      sectors: '',
      countries: '',
    };

    // === HOLDINGS - Top Holdings Table ===
    const holdingsTable = document.querySelector('[data-testid="etf-holdings_top-holdings_table"]');
    if (holdingsTable) {
      data.holdings = holdingsTable.innerText;
    }

    // === SECTORS - Sectors Table ===
    const sectorsTable = document.querySelector('[data-testid="etf-holdings_sectors_table"]');
    if (sectorsTable) {
      data.sectors = sectorsTable.innerText;
    }

    // === COUNTRIES - Countries Table ===
    const countriesTable = document.querySelector('[data-testid="etf-holdings_countries_table"]');
    if (countriesTable) {
      data.countries = countriesTable.innerText;
    }

    return data;
  });

  // Costruisci testo strutturato MINIMALISTA
  let relevantText = '';

  if (extractedData.holdings) {
    relevantText += `HOLDINGS:\n${extractedData.holdings}\n\n`;
    console.log(`[JustETF Scraper]       ✓ Holdings estratti (${extractedData.holdings.length} chars)`);
  }

  if (extractedData.sectors) {
    relevantText += `SECTORS:\n${extractedData.sectors}\n\n`;
    console.log(`[JustETF Scraper]       ✓ Sectors estratti (${extractedData.sectors.length} chars)`);
  }

  if (extractedData.countries) {
    relevantText += `COUNTRIES:\n${extractedData.countries}\n\n`;
    console.log(`[JustETF Scraper]       ✓ Countries estratti (${extractedData.countries.length} chars)`);
  }

  // Se non abbiamo trovato nulla, usa fallback
  if (relevantText.length < 100) {
    console.log(`[JustETF Scraper]    ⚠️  Dati non trovati con selettori specifici, uso fallback`);

    // Fallback: cerca tutto il testo ma limitato
    const allText = await page.evaluate(() => {
      const clone = document.body.cloneNode(true);
      const scripts = clone.querySelectorAll('script, style, noscript, nav, footer, header');
      scripts.forEach(s => s.remove());
      return clone.innerText;
    });

    // Limita a 8000 caratteri
    return allText.substring(0, 8000);
  }

  return relevantText;
}

/**
 * Estrae il testo da una sezione specifica cercando il titolo
 * @param {Page} page - Pagina Playwright
 * @param {Array<string>} titles - Titoli possibili della sezione
 * @returns {Promise<string>} - Testo estratto
 */
async function extractSectionText(page, titles) {
  for (const title of titles) {
    try {
      // Cerca l'elemento con questo titolo
      const heading = await page.locator(`text="${title}"`).first();

      if (await heading.isVisible()) {
        // Trova il contenitore parent della sezione
        const section = await heading.evaluateHandle((el) => {
          // Vai su fino a trovare un div/section che contiene questa heading
          let parent = el.parentElement;
          while (parent && !parent.classList.contains('section') &&
                 !parent.classList.contains('card') &&
                 parent.tagName !== 'SECTION') {
            parent = parent.parentElement;
            if (parent === document.body) break;
          }
          return parent || el.parentElement;
        });

        // Estrai solo il testo, pulito
        const text = await section.evaluate((el) => {
          // Rimuovi elementi nascosti, script, style
          const clone = el.cloneNode(true);
          const hidden = clone.querySelectorAll('script, style, [style*="display: none"], [style*="display:none"]');
          hidden.forEach(h => h.remove());
          return clone.innerText;
        });

        if (text && text.length > 20) {
          return text.trim();
        }
      }
    } catch (error) {
      // Titolo non trovato, continua
    }
  }

  return '';
}

/**
 * Espande SOLO i bottoni "Mostra di più" nelle sezioni rilevanti:
 * - Prime 10 partecipazioni
 * - Paesi
 * - Settori
 * @param {Page} page - Pagina Playwright
 */
async function expandAllShowMoreButtons(page) {
  console.log(`[JustETF Scraper] Espansione sezioni rilevanti...`);

  // Trova TUTTI i link "Mostra di più" sulla pagina
  const showMoreSelectors = [
    'a:has-text("Mostra di più")',
    'a:has-text("Show more")',
    'button:has-text("Mostra di più")',
    'button:has-text("Show more")',
  ];

  let expandedCount = 0;

  for (const selector of showMoreSelectors) {
    try {
      const buttons = await page.$$(selector);

      if (buttons.length > 0) {
        console.log(`[JustETF Scraper]    Trovati ${buttons.length} bottoni con "${selector}"`);

        for (let i = 0; i < buttons.length; i++) {
          try {
            const button = buttons[i];

            // Verifica se è visibile
            const isVisible = await button.isVisible();
            if (!isVisible) continue;

            // Scroll e click
            await button.scrollIntoViewIfNeeded();
            await button.click();

            // Attendi che il contenuto si carichi (importante!)
            await page.waitForTimeout(1500);

            expandedCount++;
            console.log(`[JustETF Scraper]    ✓ Espanso bottone ${i + 1}/${buttons.length}`);
          } catch (e) {
            // Bottone non più valido o già cliccato
          }
        }

        // Se abbiamo trovato e cliccato bottoni, non cercare altri selettori
        if (expandedCount > 0) break;
      }
    } catch (error) {
      // Selettore non trovato, continua
    }
  }

  console.log(`[JustETF Scraper] Espanse ${expandedCount} sezioni\n`);
}

/**
 * Estrae il nome dell'ETF dalla pagina
 * @param {Page} page - Pagina Playwright
 * @returns {Promise<string|null>} - Nome ETF o null
 */
async function extractETFName(page) {
  try {
    const selectors = [
      'h1.etf-name',
      'h1',
      '.etf-header h1',
      '[class*="etf-name"]',
    ];

    for (const selector of selectors) {
      try {
        const element = await page.$(selector);
        if (element) {
          const text = await element.textContent();
          if (text && text.trim().length > 0) {
            return text.trim();
          }
        }
      } catch (e) {
        // Continua con il prossimo selettore
      }
    }

    return null;
  } catch (error) {
    return null;
  }
}

module.exports = {
  scrapeJustETF,
  buildJustETFUrl,
};
