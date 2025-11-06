-- ============================================
-- PORTFOLIO TRACKER - DATABASE SCHEMA
-- PostgreSQL 12+
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
    
    -- Rating ESG
    esg_rating INTEGER CHECK (esg_rating BETWEEN 1 AND 10),
    
    -- Metadati
    is_accumulation BOOLEAN DEFAULT TRUE,
    is_active BOOLEAN DEFAULT TRUE,
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

CREATE OR REPLACE VIEW v_current_positions AS
SELECT
    pos.position_id,
    pf.name AS portfolio_name,
    a.isin,
    a.name AS asset_name,
    a.asset_type,
    a.sector,
    a.country,
    pos.quantity,
    pos.average_buy_price,
    pos.total_invested,
    COALESCE(ph.close_price, pos.average_buy_price) AS current_price,
    (pos.quantity * COALESCE(ph.close_price, pos.average_buy_price)) AS current_value,
    ((pos.quantity * COALESCE(ph.close_price, pos.average_buy_price)) - pos.total_invested) AS gain_loss,
    (((pos.quantity * COALESCE(ph.close_price, pos.average_buy_price)) - pos.total_invested) / NULLIF(pos.total_invested, 0) * 100) AS gain_loss_pct,
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
WHERE pos.quantity > 0;

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
