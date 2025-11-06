-- ============================================
-- PORTFOLIO TRACKER - DATABASE SCHEMA COMPLETO
-- PostgreSQL 12+
-- Schema unificato con tutte le migrazioni
-- ============================================

-- Abilita estensioni utili
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS "btree_gist";

-- ============================================
-- TABELLE PRINCIPALI
-- ============================================

-- Tabella Portafogli (es: Fineco, ING, ecc.)
CREATE TABLE portfolios (
    portfolio_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    name VARCHAR(100) NOT NULL UNIQUE,
    broker VARCHAR(100),
    account_number VARCHAR(50),
    currency VARCHAR(3) DEFAULT 'EUR',
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    is_active BOOLEAN DEFAULT TRUE,
    notes TEXT
);

-- Tabella Anagrafica Asset/Titoli
CREATE TABLE assets (
    asset_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    isin VARCHAR(12) UNIQUE NOT NULL,
    ticker VARCHAR(20),
    name VARCHAR(255) NOT NULL,
    asset_type VARCHAR(50) NOT NULL CHECK (asset_type IN ('Azionario', 'Obbligazionario', 'Monetario', 'Oro', 'Crypto', 'ETF', 'Fondo')),
    asset_category VARCHAR(100),
    currency VARCHAR(3) DEFAULT 'EUR',

    -- Classificazione geografica
    country VARCHAR(100),
    region VARCHAR(100),

    -- Classificazione settoriale
    sector VARCHAR(100),
    industry VARCHAR(100),

    -- Indice di riferimento
    benchmark_index VARCHAR(100),

    -- Commissioni e costi
    ter DECIMAL(5,4),
    transaction_cost DECIMAL(5,4),
    annual_fees DECIMAL(8,4),

    -- Rating e Metriche
    esg_rating INTEGER CHECK (esg_rating BETWEEN 1 AND 10),
    isr INTEGER CHECK (isr BETWEEN 1 AND 7),
    sharpe_ratio DECIMAL(8,4),
    standard_deviation DECIMAL(8,4),

    -- Metadati
    is_accumulation BOOLEAN DEFAULT TRUE,
    is_active BOOLEAN DEFAULT TRUE,
    factsheet_url TEXT,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    description TEXT,

    CONSTRAINT isin_format CHECK (isin ~ '^[A-Z]{2}[A-Z0-9]{9}[0-9]$')
);

-- Tabella Transazioni/Ordini
CREATE TABLE transactions (
    transaction_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    portfolio_id UUID NOT NULL REFERENCES portfolios(portfolio_id) ON DELETE CASCADE,
    asset_id UUID NOT NULL REFERENCES assets(asset_id),

    transaction_type VARCHAR(20) NOT NULL CHECK (transaction_type IN ('BUY', 'SELL', 'DIVIDEND', 'FEE', 'TRANSFER_IN', 'TRANSFER_OUT')),
    transaction_date DATE NOT NULL,
    settlement_date DATE,

    quantity DECIMAL(18,6) NOT NULL,
    price_per_share DECIMAL(18,6) NOT NULL,
    total_amount DECIMAL(18,2) NOT NULL,

    commission DECIMAL(18,2) DEFAULT 0,
    fees DECIMAL(18,2) DEFAULT 0,
    taxes DECIMAL(18,2) DEFAULT 0,

    currency VARCHAR(3) DEFAULT 'EUR',
    exchange_rate DECIMAL(12,6) DEFAULT 1.0,
    amount_in_base_currency DECIMAL(18,2),

    order_id VARCHAR(100),
    notes TEXT,

    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- Tabella Posizioni Correnti
CREATE TABLE positions (
    position_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    portfolio_id UUID NOT NULL REFERENCES portfolios(portfolio_id) ON DELETE CASCADE,
    asset_id UUID NOT NULL REFERENCES assets(asset_id),

    quantity DECIMAL(18,6) NOT NULL CHECK (quantity >= 0),
    average_buy_price DECIMAL(18,6) NOT NULL,
    total_invested DECIMAL(18,2) NOT NULL,

    total_commissions DECIMAL(18,2) DEFAULT 0,
    total_fees DECIMAL(18,2) DEFAULT 0,

    first_purchase_date DATE,
    last_transaction_date DATE,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,

    UNIQUE(portfolio_id, asset_id)
);

-- Tabella Storico Prezzi
CREATE TABLE price_history (
    price_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    asset_id UUID NOT NULL REFERENCES assets(asset_id) ON DELETE CASCADE,

    price_date DATE NOT NULL,

    open_price DECIMAL(18,6),
    high_price DECIMAL(18,6),
    low_price DECIMAL(18,6),
    close_price DECIMAL(18,6) NOT NULL,

    volume BIGINT,

    data_source VARCHAR(50),

    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,

    UNIQUE(asset_id, price_date)
);

-- Tabella Snapshot Portafoglio
CREATE TABLE portfolio_snapshots (
    snapshot_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    portfolio_id UUID NOT NULL REFERENCES portfolios(portfolio_id) ON DELETE CASCADE,
    snapshot_date DATE NOT NULL,

    total_value DECIMAL(18,2) NOT NULL,
    total_invested DECIMAL(18,2) NOT NULL,
    total_gain_loss DECIMAL(18,2) NOT NULL,
    total_gain_loss_pct DECIMAL(8,4) NOT NULL,

    asset_allocation JSONB,
    geographic_allocation JSONB,
    sector_allocation JSONB,

    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,

    UNIQUE(portfolio_id, snapshot_date)
);

-- Tabella Dividendi Ricevuti
CREATE TABLE dividends (
    dividend_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    portfolio_id UUID NOT NULL REFERENCES portfolios(portfolio_id) ON DELETE CASCADE,
    asset_id UUID NOT NULL REFERENCES assets(asset_id),

    payment_date DATE NOT NULL,
    ex_dividend_date DATE,

    dividend_per_share DECIMAL(18,6) NOT NULL,
    quantity DECIMAL(18,6) NOT NULL,
    total_dividend DECIMAL(18,2) NOT NULL,

    withholding_tax DECIMAL(18,2) DEFAULT 0,
    net_dividend DECIMAL(18,2) NOT NULL,

    currency VARCHAR(3) DEFAULT 'EUR',

    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- Tabella Obiettivi Target Allocation
CREATE TABLE target_allocations (
    target_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    portfolio_id UUID NOT NULL REFERENCES portfolios(portfolio_id) ON DELETE CASCADE,

    allocation_name VARCHAR(100) NOT NULL,

    target_azionario DECIMAL(5,2) CHECK (target_azionario BETWEEN 0 AND 100),
    target_obbligazionario DECIMAL(5,2) CHECK (target_obbligazionario BETWEEN 0 AND 100),
    target_monetario DECIMAL(5,2) CHECK (target_monetario BETWEEN 0 AND 100),
    target_oro DECIMAL(5,2) CHECK (target_oro BETWEEN 0 AND 100),
    target_crypto DECIMAL(5,2) CHECK (target_crypto BETWEEN 0 AND 100),

    is_active BOOLEAN DEFAULT TRUE,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT sum_100_percent CHECK (
        target_azionario + target_obbligazionario + target_monetario +
        COALESCE(target_oro, 0) + COALESCE(target_crypto, 0) = 100
    )
);

-- Tabella Performance Mensili per Posizione
CREATE TABLE IF NOT EXISTS monthly_position_performance (
  performance_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  portfolio_id UUID NOT NULL REFERENCES portfolios(portfolio_id) ON DELETE CASCADE,
  asset_id UUID NOT NULL REFERENCES assets(asset_id) ON DELETE CASCADE,
  month_year DATE NOT NULL,
  quantity DECIMAL(18,8) NOT NULL,
  average_buy_price DECIMAL(18,8) NOT NULL,
  month_start_price DECIMAL(18,8),
  month_end_price DECIMAL(18,8) NOT NULL,
  month_return_pct DECIMAL(8,4),
  total_invested DECIMAL(18,2) NOT NULL,
  month_start_value DECIMAL(18,2),
  month_end_value DECIMAL(18,2) NOT NULL,
  unrealized_gain_loss DECIMAL(18,2),
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  UNIQUE(portfolio_id, asset_id, month_year)
);

-- ============================================
-- INDICI PER PERFORMANCE
-- ============================================

CREATE INDEX idx_transactions_portfolio ON transactions(portfolio_id);
CREATE INDEX idx_transactions_asset ON transactions(asset_id);
CREATE INDEX idx_transactions_date ON transactions(transaction_date);
CREATE INDEX idx_transactions_type ON transactions(transaction_type);

CREATE INDEX idx_positions_portfolio ON positions(portfolio_id);
CREATE INDEX idx_positions_asset ON positions(asset_id);

CREATE INDEX idx_price_history_asset ON price_history(asset_id);
CREATE INDEX idx_price_history_date ON price_history(price_date DESC);
CREATE INDEX idx_price_history_asset_date ON price_history(asset_id, price_date DESC);

CREATE INDEX idx_snapshots_portfolio ON portfolio_snapshots(portfolio_id);
CREATE INDEX idx_snapshots_date ON portfolio_snapshots(snapshot_date DESC);
CREATE INDEX idx_snapshots_portfolio_date ON portfolio_snapshots(portfolio_id, snapshot_date DESC);

CREATE INDEX idx_dividends_portfolio ON dividends(portfolio_id);
CREATE INDEX idx_dividends_asset ON dividends(asset_id);
CREATE INDEX idx_dividends_date ON dividends(payment_date DESC);

CREATE INDEX idx_assets_isin ON assets(isin);
CREATE INDEX idx_assets_type ON assets(asset_type);
CREATE INDEX idx_assets_active ON assets(is_active);

CREATE INDEX idx_assets_name_search ON assets USING gin(to_tsvector('italian', name));

CREATE INDEX idx_monthly_perf_portfolio ON monthly_position_performance(portfolio_id, month_year DESC);
CREATE INDEX idx_monthly_perf_asset ON monthly_position_performance(asset_id, month_year DESC);
CREATE INDEX idx_monthly_perf_date ON monthly_position_performance(month_year DESC);

-- ============================================
-- TRIGGER PER AGGIORNAMENTO AUTOMATICO
-- ============================================

CREATE OR REPLACE FUNCTION update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = CURRENT_TIMESTAMP;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER update_portfolios_updated_at BEFORE UPDATE ON portfolios
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_assets_updated_at BEFORE UPDATE ON assets
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_transactions_updated_at BEFORE UPDATE ON transactions
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_positions_updated_at BEFORE UPDATE ON positions
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_target_allocations_updated_at BEFORE UPDATE ON target_allocations
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

-- ============================================
-- VISTE UTILI
-- ============================================

-- Vista Posizioni Correnti (con percentuali possesso e investita)
DROP VIEW IF EXISTS v_current_positions;
CREATE VIEW v_current_positions AS
WITH position_values AS (
    SELECT
        pos.position_id,
        pos.portfolio_id,
        pos.asset_id,
        pf.name AS portfolio_name,
        a.isin,
        a.ticker,
        a.name AS asset_name,
        a.asset_type,
        a.sector,
        a.country,
        pos.quantity,
        pos.average_buy_price,
        pos.total_invested,
        COALESCE(ph.close_price, pos.average_buy_price) AS current_price,
        (pos.quantity * COALESCE(ph.close_price, pos.average_buy_price)) AS current_value,
        ph.price_date AS last_price_date
    FROM positions pos
    JOIN portfolios pf ON pos.portfolio_id = pf.portfolio_id
    JOIN assets a ON pos.asset_id = a.asset_id
    LEFT JOIN LATERAL (
        SELECT close_price, price_date
        FROM price_history
        WHERE asset_id = pos.asset_id
        ORDER BY price_date DESC
        LIMIT 1
    ) ph ON TRUE
    WHERE pos.quantity > 0
)
SELECT
    position_id,
    portfolio_id,
    asset_id,
    portfolio_name,
    isin,
    ticker,
    asset_name,
    asset_type,
    sector,
    country,
    quantity,
    average_buy_price,
    total_invested,
    current_price,
    current_value,
    (current_value - total_invested) AS gain_loss,
    ((current_value - total_invested) / NULLIF(total_invested, 0) * 100) AS gain_loss_pct,
    last_price_date,
    (current_value / NULLIF(SUM(current_value) OVER (PARTITION BY portfolio_id), 0) * 100) AS ownership_pct,
    (total_invested / NULLIF(SUM(total_invested) OVER (PARTITION BY portfolio_id), 0) * 100) AS invested_pct
FROM position_values;

-- Vista Asset Allocation
CREATE OR REPLACE VIEW v_asset_allocation AS
SELECT
    pf.portfolio_id,
    pf.name AS portfolio_name,
    a.asset_type,
    SUM(pos.quantity * COALESCE(ph.close_price, pos.average_buy_price)) AS total_value,
    (SUM(pos.quantity * COALESCE(ph.close_price, pos.average_buy_price)) / SUM(SUM(pos.quantity * COALESCE(ph.close_price, pos.average_buy_price))) OVER (PARTITION BY pf.portfolio_id) * 100) AS percentage
FROM positions pos
JOIN portfolios pf ON pos.portfolio_id = pf.portfolio_id
JOIN assets a ON pos.asset_id = a.asset_id
LEFT JOIN LATERAL (
    SELECT close_price
    FROM price_history
    WHERE asset_id = pos.asset_id
    ORDER BY price_date DESC
    LIMIT 1
) ph ON TRUE
WHERE pos.quantity > 0
GROUP BY pf.portfolio_id, pf.name, a.asset_type;

-- Vista Portfolio Performance
CREATE OR REPLACE VIEW v_portfolio_performance AS
SELECT
    pf.portfolio_id,
    pf.name AS portfolio_name,
    COALESCE(SUM(pos.total_invested), 0) AS total_invested,
    COALESCE(SUM(pos.quantity * COALESCE(ph.close_price, pos.average_buy_price)), 0) AS current_value,
    COALESCE(SUM((pos.quantity * COALESCE(ph.close_price, pos.average_buy_price)) - pos.total_invested), 0) AS total_gain_loss,
    CASE
        WHEN SUM(pos.total_invested) > 0 THEN
            (SUM((pos.quantity * COALESCE(ph.close_price, pos.average_buy_price)) - pos.total_invested) / SUM(pos.total_invested) * 100)
        ELSE 0
    END AS total_gain_loss_pct,
    COUNT(CASE WHEN pos.quantity > 0 THEN 1 END) AS number_of_positions
FROM portfolios pf
LEFT JOIN positions pos ON pf.portfolio_id = pos.portfolio_id AND pos.quantity > 0
LEFT JOIN LATERAL (
    SELECT close_price
    FROM price_history
    WHERE asset_id = pos.asset_id
    ORDER BY price_date DESC
    LIMIT 1
) ph ON TRUE
WHERE pf.is_active = TRUE
GROUP BY pf.portfolio_id, pf.name;

-- Vista Monthly Portfolio Performance
CREATE OR REPLACE VIEW v_monthly_portfolio_performance AS
SELECT
  portfolio_id,
  pf.name AS portfolio_name,
  month_year,
  COUNT(DISTINCT asset_id) AS num_positions,
  SUM(total_invested) AS total_invested,
  SUM(month_end_value) AS month_end_value,
  SUM(unrealized_gain_loss) AS total_unrealized_gain_loss,
  (SUM(unrealized_gain_loss) / NULLIF(SUM(total_invested), 0) * 100) AS total_return_pct,
  SUM(month_return_pct * month_end_value) / NULLIF(SUM(month_end_value), 0) AS weighted_monthly_return_pct
FROM monthly_position_performance mpp
JOIN portfolios pf ON mpp.portfolio_id = pf.portfolio_id
GROUP BY portfolio_id, pf.name, month_year
ORDER BY portfolio_id, month_year DESC;

-- ============================================
-- STORED PROCEDURES
-- ============================================

CREATE OR REPLACE FUNCTION update_position_after_transaction()
RETURNS TRIGGER AS $$
BEGIN
    IF NEW.transaction_type = 'BUY' THEN
        INSERT INTO positions (portfolio_id, asset_id, quantity, average_buy_price, total_invested, first_purchase_date, last_transaction_date)
        VALUES (
            NEW.portfolio_id,
            NEW.asset_id,
            NEW.quantity,
            NEW.price_per_share,
            NEW.total_amount + NEW.commission + NEW.fees,
            NEW.transaction_date,
            NEW.transaction_date
        )
        ON CONFLICT (portfolio_id, asset_id)
        DO UPDATE SET
            quantity = positions.quantity + NEW.quantity,
            average_buy_price = (
                (positions.total_invested + NEW.total_amount + NEW.commission + NEW.fees) /
                (positions.quantity + NEW.quantity)
            ),
            total_invested = positions.total_invested + NEW.total_amount + NEW.commission + NEW.fees,
            total_commissions = positions.total_commissions + NEW.commission,
            total_fees = positions.total_fees + NEW.fees,
            last_transaction_date = NEW.transaction_date;

    ELSIF NEW.transaction_type = 'SELL' THEN
        UPDATE positions
        SET
            quantity = quantity - NEW.quantity,
            last_transaction_date = NEW.transaction_date
        WHERE portfolio_id = NEW.portfolio_id AND asset_id = NEW.asset_id;

        DELETE FROM positions
        WHERE portfolio_id = NEW.portfolio_id
        AND asset_id = NEW.asset_id
        AND quantity <= 0;
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER update_position_on_transaction
    AFTER INSERT ON transactions
    FOR EACH ROW
    EXECUTE FUNCTION update_position_after_transaction();

CREATE OR REPLACE FUNCTION create_daily_snapshot(p_portfolio_id UUID, p_date DATE)
RETURNS VOID AS $$
DECLARE
    v_total_value DECIMAL(18,2);
    v_total_invested DECIMAL(18,2);
    v_asset_allocation JSONB;
BEGIN
    SELECT
        COALESCE(SUM(pos.quantity * ph.close_price), 0),
        COALESCE(SUM(pos.total_invested), 0)
    INTO v_total_value, v_total_invested
    FROM positions pos
    LEFT JOIN LATERAL (
        SELECT close_price
        FROM price_history
        WHERE asset_id = pos.asset_id AND price_date <= p_date
        ORDER BY price_date DESC
        LIMIT 1
    ) ph ON TRUE
    WHERE pos.portfolio_id = p_portfolio_id;

    SELECT jsonb_object_agg(asset_type, total_value)
    INTO v_asset_allocation
    FROM (
        SELECT
            a.asset_type,
            SUM(pos.quantity * ph.close_price) AS total_value
        FROM positions pos
        JOIN assets a ON pos.asset_id = a.asset_id
        LEFT JOIN LATERAL (
            SELECT close_price
            FROM price_history
            WHERE asset_id = pos.asset_id AND price_date <= p_date
            ORDER BY price_date DESC
            LIMIT 1
        ) ph ON TRUE
        WHERE pos.portfolio_id = p_portfolio_id
        GROUP BY a.asset_type
    ) sub;

    INSERT INTO portfolio_snapshots (
        portfolio_id, snapshot_date, total_value, total_invested,
        total_gain_loss, total_gain_loss_pct, asset_allocation
    ) VALUES (
        p_portfolio_id, p_date, v_total_value, v_total_invested,
        v_total_value - v_total_invested,
        CASE WHEN v_total_invested > 0 THEN ((v_total_value - v_total_invested) / v_total_invested * 100) ELSE 0 END,
        v_asset_allocation
    )
    ON CONFLICT (portfolio_id, snapshot_date)
    DO UPDATE SET
        total_value = EXCLUDED.total_value,
        total_invested = EXCLUDED.total_invested,
        total_gain_loss = EXCLUDED.total_gain_loss,
        total_gain_loss_pct = EXCLUDED.total_gain_loss_pct,
        asset_allocation = EXCLUDED.asset_allocation;
END;
$$ LANGUAGE plpgsql;

-- ============================================
-- COMMENTI PER DOCUMENTAZIONE
-- ============================================

COMMENT ON TABLE assets IS 'Anagrafica completa asset/titoli con metriche finanziarie';
COMMENT ON COLUMN assets.sharpe_ratio IS 'Sharpe Ratio - Rapporto tra rendimento e rischio (higher is better)';
COMMENT ON COLUMN assets.annual_fees IS 'Commissioni annue totali in percentuale (%)';
COMMENT ON COLUMN assets.standard_deviation IS 'Deviazione standard dei rendimenti - misura della volatilità (%)';
COMMENT ON COLUMN assets.isr IS 'Indice Sintetico di Rischio (ISR) - scala da 1 (basso rischio) a 7 (alto rischio)';
COMMENT ON COLUMN assets.factsheet_url IS 'URL del factsheet PDF dell''asset (es. link a documento informativo ETF)';

COMMENT ON TABLE monthly_position_performance IS 'Storico mensile delle performance per ogni posizione in portafoglio';
COMMENT ON COLUMN monthly_position_performance.month_year IS 'Primo giorno del mese di riferimento (es: 2024-01-01)';
COMMENT ON COLUMN monthly_position_performance.month_return_pct IS 'Rendimento percentuale del mese: (end_price - start_price) / start_price * 100';

COMMENT ON VIEW v_current_positions IS 'Vista posizioni correnti con percentuali di possesso e investita';
COMMENT ON VIEW v_monthly_portfolio_performance IS 'Vista aggregata delle performance mensili per portafoglio';
