--
-- PostgreSQL database dump
--

-- Dumped from database version 16.0
-- Dumped by pg_dump version 16.0

-- Started on 2025-11-28 16:12:21

SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;

--
-- TOC entry 3 (class 3079 OID 99347)
-- Name: btree_gist; Type: EXTENSION; Schema: -; Owner: -
--

CREATE EXTENSION IF NOT EXISTS btree_gist WITH SCHEMA public;


--
-- TOC entry 5435 (class 0 OID 0)
-- Dependencies: 3
-- Name: EXTENSION btree_gist; Type: COMMENT; Schema: -; Owner: 
--

COMMENT ON EXTENSION btree_gist IS 'support for indexing common datatypes in GiST';


--
-- TOC entry 2 (class 3079 OID 99336)
-- Name: uuid-ossp; Type: EXTENSION; Schema: -; Owner: -
--

CREATE EXTENSION IF NOT EXISTS "uuid-ossp" WITH SCHEMA public;


--
-- TOC entry 5436 (class 0 OID 0)
-- Dependencies: 2
-- Name: EXTENSION "uuid-ossp"; Type: COMMENT; Schema: -; Owner: 
--

COMMENT ON EXTENSION "uuid-ossp" IS 'generate universally unique identifiers (UUIDs)';


--
-- TOC entry 340 (class 1255 OID 100192)
-- Name: create_daily_snapshot(uuid, date); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.create_daily_snapshot(p_portfolio_id uuid, p_date date) RETURNS void
    LANGUAGE plpgsql
    AS $$
DECLARE
    v_total_value DECIMAL(18,2);
    v_total_invested DECIMAL(18,2);
    v_asset_allocation JSONB;
    v_geographic_allocation JSONB;
    v_sector_allocation JSONB;
BEGIN
    -- Calcola valore totale
    SELECT 
        SUM(pos.quantity * ph.close_price),
        SUM(pos.total_invested)
    INTO v_total_value, v_total_invested
    FROM positions pos
    JOIN LATERAL (
        SELECT close_price
        FROM price_history
        WHERE asset_id = pos.asset_id AND price_date <= p_date
        ORDER BY price_date DESC
        LIMIT 1
    ) ph ON TRUE
    WHERE pos.portfolio_id = p_portfolio_id;
    
    -- Calcola allocazione asset
    SELECT jsonb_object_agg(asset_type, total_value)
    INTO v_asset_allocation
    FROM (
        SELECT 
            a.asset_type,
            SUM(pos.quantity * ph.close_price) AS total_value
        FROM positions pos
        JOIN assets a ON pos.asset_id = a.asset_id
        JOIN LATERAL (
            SELECT close_price
            FROM price_history
            WHERE asset_id = pos.asset_id AND price_date <= p_date
            ORDER BY price_date DESC
            LIMIT 1
        ) ph ON TRUE
        WHERE pos.portfolio_id = p_portfolio_id
        GROUP BY a.asset_type
    ) sub;
    
    -- Inserisci snapshot
    INSERT INTO portfolio_snapshots (
        portfolio_id, snapshot_date, total_value, total_invested,
        total_gain_loss, total_gain_loss_pct, asset_allocation,
        geographic_allocation, sector_allocation
    ) VALUES (
        p_portfolio_id, p_date, v_total_value, v_total_invested,
        v_total_value - v_total_invested,
        ((v_total_value - v_total_invested) / v_total_invested * 100),
        v_asset_allocation, v_geographic_allocation, v_sector_allocation
    )
    ON CONFLICT (portfolio_id, snapshot_date) 
    DO UPDATE SET
        total_value = EXCLUDED.total_value,
        total_invested = EXCLUDED.total_invested,
        total_gain_loss = EXCLUDED.total_gain_loss,
        total_gain_loss_pct = EXCLUDED.total_gain_loss_pct,
        asset_allocation = EXCLUDED.asset_allocation;
END;
$$;


ALTER FUNCTION public.create_daily_snapshot(p_portfolio_id uuid, p_date date) OWNER TO postgres;

--
-- TOC entry 309 (class 1255 OID 100190)
-- Name: update_position_after_transaction(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.update_position_after_transaction() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
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
        
        -- Rimuovi posizione se quantità = 0
        DELETE FROM positions 
        WHERE portfolio_id = NEW.portfolio_id 
        AND asset_id = NEW.asset_id 
        AND quantity <= 0;
    END IF;
    
    RETURN NEW;
END;
$$;


ALTER FUNCTION public.update_position_after_transaction() OWNER TO postgres;

--
-- TOC entry 422 (class 1255 OID 100152)
-- Name: update_updated_at_column(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.update_updated_at_column() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
    NEW.updated_at = CURRENT_TIMESTAMP;
    RETURN NEW;
END;
$$;


ALTER FUNCTION public.update_updated_at_column() OWNER TO postgres;

SET default_tablespace = '';

SET default_table_access_method = heap;

--
-- TOC entry 246 (class 1259 OID 113797)
-- Name: allocation_categories; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.allocation_categories (
    category_id uuid DEFAULT public.uuid_generate_v4() NOT NULL,
    portfolio_id uuid NOT NULL,
    category_name character varying(100) NOT NULL,
    target_percent numeric(5,2) NOT NULL,
    display_order integer DEFAULT 0,
    color_hex character varying(7) DEFAULT '#3B82F6'::character varying,
    is_active boolean DEFAULT true,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT allocation_categories_target_percent_check CHECK (((target_percent >= (0)::numeric) AND (target_percent <= (100)::numeric)))
);


ALTER TABLE public.allocation_categories OWNER TO postgres;

--
-- TOC entry 5437 (class 0 OID 0)
-- Dependencies: 246
-- Name: TABLE allocation_categories; Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON TABLE public.allocation_categories IS 'User-defined allocation targets for portfolio rebalancing simulation (does not modify actual positions)';


--
-- TOC entry 5438 (class 0 OID 0)
-- Dependencies: 246
-- Name: COLUMN allocation_categories.category_name; Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON COLUMN public.allocation_categories.category_name IS 'Category name (e.g., Azionario, Obbligazionario, Bitcoin, Oro)';


--
-- TOC entry 5439 (class 0 OID 0)
-- Dependencies: 246
-- Name: COLUMN allocation_categories.target_percent; Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON COLUMN public.allocation_categories.target_percent IS 'Target allocation percentage (0-100). Sum across all active categories should equal 100%';


--
-- TOC entry 5440 (class 0 OID 0)
-- Dependencies: 246
-- Name: COLUMN allocation_categories.display_order; Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON COLUMN public.allocation_categories.display_order IS 'Display order in UI (lower numbers appear first)';


--
-- TOC entry 5441 (class 0 OID 0)
-- Dependencies: 246
-- Name: COLUMN allocation_categories.color_hex; Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON COLUMN public.allocation_categories.color_hex IS 'Hex color code for UI visualization (e.g., #3B82F6)';


--
-- TOC entry 218 (class 1259 OID 100009)
-- Name: assets; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.assets (
    asset_id uuid DEFAULT public.uuid_generate_v4() NOT NULL,
    isin character varying(12) NOT NULL,
    ticker character varying(20),
    name character varying(255) NOT NULL,
    asset_type character varying(50) NOT NULL,
    asset_category character varying(100),
    currency character varying(3) DEFAULT 'EUR'::character varying,
    country character varying(100),
    region character varying(100),
    sector character varying(100),
    industry character varying(100),
    benchmark_index character varying(100),
    ter numeric(5,4),
    transaction_cost numeric(5,4),
    esg_rating integer,
    is_accumulation boolean DEFAULT true,
    is_active boolean DEFAULT true,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP,
    description text,
    sharpe_ratio numeric(8,4),
    annual_fees numeric(8,4),
    standard_deviation numeric(8,4),
    isr integer,
    factsheet_url text,
    composition_last_updated timestamp with time zone,
    CONSTRAINT assets_asset_type_check CHECK (((asset_type)::text = ANY ((ARRAY['Azionario'::character varying, 'Obbligazionario'::character varying, 'Monetario'::character varying, 'Oro'::character varying, 'Crypto'::character varying, 'ETF'::character varying, 'Fondo'::character varying, 'Azione Singola'::character varying, 'Obbligazione Singola'::character varying])::text[]))),
    CONSTRAINT assets_esg_rating_check CHECK (((esg_rating >= 1) AND (esg_rating <= 10))),
    CONSTRAINT assets_isr_check CHECK (((isr >= 1) AND (isr <= 7))),
    CONSTRAINT isin_format CHECK (((isin)::text ~ '^[A-Z]{2}[A-Z0-9]{9}[0-9]$'::text))
);


ALTER TABLE public.assets OWNER TO postgres;

--
-- TOC entry 5442 (class 0 OID 0)
-- Dependencies: 218
-- Name: TABLE assets; Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON TABLE public.assets IS 'Anagrafica completa di tutti i titoli/asset';


--
-- TOC entry 5443 (class 0 OID 0)
-- Dependencies: 218
-- Name: COLUMN assets.composition_last_updated; Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON COLUMN public.assets.composition_last_updated IS 'Timestamp of last successful ETF composition update (holdings, sectors, regions)';


--
-- TOC entry 222 (class 1259 OID 100091)
-- Name: dividends; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.dividends (
    dividend_id uuid DEFAULT public.uuid_generate_v4() NOT NULL,
    portfolio_id uuid NOT NULL,
    asset_id uuid NOT NULL,
    payment_date date NOT NULL,
    ex_dividend_date date,
    dividend_per_share numeric(18,6) NOT NULL,
    quantity numeric(18,6) NOT NULL,
    total_dividend numeric(18,2) NOT NULL,
    withholding_tax numeric(18,2) DEFAULT 0,
    net_dividend numeric(18,2) NOT NULL,
    currency character varying(3) DEFAULT 'EUR'::character varying,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP
);


ALTER TABLE public.dividends OWNER TO postgres;

--
-- TOC entry 5444 (class 0 OID 0)
-- Dependencies: 222
-- Name: TABLE dividends; Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON TABLE public.dividends IS 'Registro dividendi ricevuti';


--
-- TOC entry 231 (class 1259 OID 102257)
-- Name: etf_asset_allocation; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.etf_asset_allocation (
    asset_allocation_id uuid DEFAULT public.uuid_generate_v4() NOT NULL,
    asset_id uuid NOT NULL,
    allocation_type character varying(50) NOT NULL,
    weight_percent numeric(5,4) NOT NULL,
    updated_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT etf_asset_allocation_allocation_type_check CHECK (((allocation_type)::text = ANY ((ARRAY['Equity'::character varying, 'Bond'::character varying, 'Cash'::character varying, 'Other'::character varying, 'Commodity'::character varying, 'Real Estate'::character varying])::text[]))),
    CONSTRAINT etf_asset_allocation_weight_percent_check CHECK (((weight_percent >= (0)::numeric) AND (weight_percent <= (1)::numeric)))
);


ALTER TABLE public.etf_asset_allocation OWNER TO postgres;

--
-- TOC entry 5445 (class 0 OID 0)
-- Dependencies: 231
-- Name: TABLE etf_asset_allocation; Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON TABLE public.etf_asset_allocation IS 'Asset class allocation breakdown for ETF assets (Stocks, Bonds, Cash, etc.)';


--
-- TOC entry 5446 (class 0 OID 0)
-- Dependencies: 231
-- Name: COLUMN etf_asset_allocation.allocation_type; Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON COLUMN public.etf_asset_allocation.allocation_type IS 'Type of asset class (Equity, Bond, Cash, Other, Commodity, Real Estate)';


--
-- TOC entry 5447 (class 0 OID 0)
-- Dependencies: 231
-- Name: COLUMN etf_asset_allocation.weight_percent; Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON COLUMN public.etf_asset_allocation.weight_percent IS 'Percentage weight of asset class in ETF (0-1, e.g., 0.85 = 85%)';


--
-- TOC entry 233 (class 1259 OID 102290)
-- Name: etf_bond_maturity; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.etf_bond_maturity (
    bond_maturity_id uuid DEFAULT public.uuid_generate_v4() NOT NULL,
    asset_id uuid NOT NULL,
    maturity_range character varying(50) NOT NULL,
    weight_percent numeric(5,4) NOT NULL,
    avg_duration_years numeric(6,2),
    updated_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT etf_bond_maturity_weight_percent_check CHECK (((weight_percent >= (0)::numeric) AND (weight_percent <= (1)::numeric)))
);


ALTER TABLE public.etf_bond_maturity OWNER TO postgres;

--
-- TOC entry 5448 (class 0 OID 0)
-- Dependencies: 233
-- Name: TABLE etf_bond_maturity; Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON TABLE public.etf_bond_maturity IS 'Bond maturity/duration distribution for bond ETFs';


--
-- TOC entry 5449 (class 0 OID 0)
-- Dependencies: 233
-- Name: COLUMN etf_bond_maturity.maturity_range; Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON COLUMN public.etf_bond_maturity.maturity_range IS 'Maturity range category (0-1Y, 1-3Y, 3-5Y, 5-10Y, 10-20Y, 20+Y)';


--
-- TOC entry 5450 (class 0 OID 0)
-- Dependencies: 233
-- Name: COLUMN etf_bond_maturity.weight_percent; Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON COLUMN public.etf_bond_maturity.weight_percent IS 'Percentage of bonds with this maturity (0-1)';


--
-- TOC entry 5451 (class 0 OID 0)
-- Dependencies: 233
-- Name: COLUMN etf_bond_maturity.avg_duration_years; Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON COLUMN public.etf_bond_maturity.avg_duration_years IS 'Average duration in years for bonds in this maturity range';


--
-- TOC entry 232 (class 1259 OID 102275)
-- Name: etf_bond_ratings; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.etf_bond_ratings (
    bond_rating_id uuid DEFAULT public.uuid_generate_v4() NOT NULL,
    asset_id uuid NOT NULL,
    rating_category character varying(50) NOT NULL,
    weight_percent numeric(5,4) NOT NULL,
    updated_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT etf_bond_ratings_weight_percent_check CHECK (((weight_percent >= (0)::numeric) AND (weight_percent <= (1)::numeric)))
);


ALTER TABLE public.etf_bond_ratings OWNER TO postgres;

--
-- TOC entry 5452 (class 0 OID 0)
-- Dependencies: 232
-- Name: TABLE etf_bond_ratings; Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON TABLE public.etf_bond_ratings IS 'Bond quality ratings distribution for bond ETFs (AAA, AA, A, BBB, etc.)';


--
-- TOC entry 5453 (class 0 OID 0)
-- Dependencies: 232
-- Name: COLUMN etf_bond_ratings.rating_category; Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON COLUMN public.etf_bond_ratings.rating_category IS 'Bond rating category (AAA, AA, A, BBB, BB, B, Below B, Not Rated)';


--
-- TOC entry 5454 (class 0 OID 0)
-- Dependencies: 232
-- Name: COLUMN etf_bond_ratings.weight_percent; Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON COLUMN public.etf_bond_ratings.weight_percent IS 'Percentage of bonds with this rating (0-1)';


--
-- TOC entry 230 (class 1259 OID 102240)
-- Name: etf_geographic_weights; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.etf_geographic_weights (
    geographic_weight_id uuid DEFAULT public.uuid_generate_v4() NOT NULL,
    asset_id uuid NOT NULL,
    region_name character varying(100) NOT NULL,
    weight_percent numeric(5,4) NOT NULL,
    updated_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT etf_geographic_weights_weight_percent_check CHECK (((weight_percent >= (0)::numeric) AND (weight_percent <= (1)::numeric)))
);


ALTER TABLE public.etf_geographic_weights OWNER TO postgres;

--
-- TOC entry 5455 (class 0 OID 0)
-- Dependencies: 230
-- Name: TABLE etf_geographic_weights; Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON TABLE public.etf_geographic_weights IS 'Geographic allocation breakdown for ETF assets (US, Europe, Asia, etc.)';


--
-- TOC entry 5456 (class 0 OID 0)
-- Dependencies: 230
-- Name: COLUMN etf_geographic_weights.weight_percent; Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON COLUMN public.etf_geographic_weights.weight_percent IS 'Percentage weight of region in ETF (0-1, e.g., 0.65 = 65%)';


--
-- TOC entry 228 (class 1259 OID 102208)
-- Name: etf_holdings; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.etf_holdings (
    holding_id uuid DEFAULT public.uuid_generate_v4() NOT NULL,
    asset_id uuid NOT NULL,
    holding_symbol character varying(20),
    holding_name character varying(255) NOT NULL,
    holding_percent numeric(5,4) NOT NULL,
    rank_position integer,
    updated_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT etf_holdings_holding_percent_check CHECK (((holding_percent >= (0)::numeric) AND (holding_percent <= (1)::numeric)))
);


ALTER TABLE public.etf_holdings OWNER TO postgres;

--
-- TOC entry 5457 (class 0 OID 0)
-- Dependencies: 228
-- Name: TABLE etf_holdings; Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON TABLE public.etf_holdings IS 'Top holdings (companies) within ETF assets with their weight percentages';


--
-- TOC entry 5458 (class 0 OID 0)
-- Dependencies: 228
-- Name: COLUMN etf_holdings.holding_percent; Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON COLUMN public.etf_holdings.holding_percent IS 'Percentage weight of holding in ETF (0-1, e.g., 0.045 = 4.5%)';


--
-- TOC entry 5459 (class 0 OID 0)
-- Dependencies: 228
-- Name: COLUMN etf_holdings.rank_position; Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON COLUMN public.etf_holdings.rank_position IS 'Ranking position of holding (1 = largest holding)';


--
-- TOC entry 229 (class 1259 OID 102223)
-- Name: etf_sector_weights; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.etf_sector_weights (
    sector_weight_id uuid DEFAULT public.uuid_generate_v4() NOT NULL,
    asset_id uuid NOT NULL,
    sector_name character varying(100) NOT NULL,
    weight_percent numeric(5,4) NOT NULL,
    updated_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT etf_sector_weights_weight_percent_check CHECK (((weight_percent >= (0)::numeric) AND (weight_percent <= (1)::numeric)))
);


ALTER TABLE public.etf_sector_weights OWNER TO postgres;

--
-- TOC entry 5460 (class 0 OID 0)
-- Dependencies: 229
-- Name: TABLE etf_sector_weights; Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON TABLE public.etf_sector_weights IS 'Sector allocation breakdown for ETF assets (Technology, Healthcare, etc.)';


--
-- TOC entry 5461 (class 0 OID 0)
-- Dependencies: 229
-- Name: COLUMN etf_sector_weights.weight_percent; Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON COLUMN public.etf_sector_weights.weight_percent IS 'Percentage weight of sector in ETF (0-1, e.g., 0.245 = 24.5%)';


--
-- TOC entry 221 (class 1259 OID 100075)
-- Name: portfolio_snapshots; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.portfolio_snapshots (
    snapshot_id uuid DEFAULT public.uuid_generate_v4() NOT NULL,
    portfolio_id uuid NOT NULL,
    snapshot_date date NOT NULL,
    total_value numeric(18,2) NOT NULL,
    total_invested numeric(18,2) NOT NULL,
    total_gain_loss numeric(18,2) NOT NULL,
    total_gain_loss_pct numeric(8,4) NOT NULL,
    asset_allocation jsonb,
    geographic_allocation jsonb,
    sector_allocation jsonb,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP
);


ALTER TABLE public.portfolio_snapshots OWNER TO postgres;

--
-- TOC entry 5462 (class 0 OID 0)
-- Dependencies: 221
-- Name: TABLE portfolio_snapshots; Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON TABLE public.portfolio_snapshots IS 'Snapshot giornalieri per tracking performance';


--
-- TOC entry 217 (class 1259 OID 99997)
-- Name: portfolios; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.portfolios (
    portfolio_id uuid DEFAULT public.uuid_generate_v4() NOT NULL,
    name character varying(100) NOT NULL,
    broker character varying(100),
    account_number character varying(50),
    currency character varying(3) DEFAULT 'EUR'::character varying,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP,
    is_active boolean DEFAULT true,
    notes text
);


ALTER TABLE public.portfolios OWNER TO postgres;

--
-- TOC entry 5463 (class 0 OID 0)
-- Dependencies: 217
-- Name: TABLE portfolios; Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON TABLE public.portfolios IS 'Gestione di multipli portafogli (es: Fineco, ING)';


--
-- TOC entry 220 (class 1259 OID 100053)
-- Name: positions; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.positions (
    position_id uuid DEFAULT public.uuid_generate_v4() NOT NULL,
    portfolio_id uuid NOT NULL,
    asset_id uuid NOT NULL,
    quantity numeric(18,6) NOT NULL,
    average_buy_price numeric(18,6) NOT NULL,
    total_invested numeric(18,2) NOT NULL,
    total_commissions numeric(18,2) DEFAULT 0,
    total_fees numeric(18,2) DEFAULT 0,
    first_purchase_date date,
    last_transaction_date date,
    updated_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT positions_quantity_check CHECK ((quantity >= (0)::numeric))
);


ALTER TABLE public.positions OWNER TO postgres;

--
-- TOC entry 5464 (class 0 OID 0)
-- Dependencies: 220
-- Name: TABLE positions; Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON TABLE public.positions IS 'Posizioni correnti per ogni portafoglio';


--
-- TOC entry 224 (class 1259 OID 100158)
-- Name: price_history; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.price_history (
    price_id uuid DEFAULT public.uuid_generate_v4() NOT NULL,
    asset_id uuid NOT NULL,
    price_date date NOT NULL,
    open_price numeric(18,6),
    high_price numeric(18,6),
    low_price numeric(18,6),
    close_price numeric(18,6) NOT NULL,
    volume bigint,
    data_source character varying(50),
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP
);


ALTER TABLE public.price_history OWNER TO postgres;

--
-- TOC entry 5465 (class 0 OID 0)
-- Dependencies: 224
-- Name: TABLE price_history; Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON TABLE public.price_history IS 'Storico prezzi giornalieri per analisi temporali';


--
-- TOC entry 223 (class 1259 OID 100110)
-- Name: target_allocations; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.target_allocations (
    target_id uuid DEFAULT public.uuid_generate_v4() NOT NULL,
    portfolio_id uuid NOT NULL,
    allocation_name character varying(100) NOT NULL,
    target_azionario numeric(5,2),
    target_obbligazionario numeric(5,2),
    target_monetario numeric(5,2),
    target_oro numeric(5,2),
    target_crypto numeric(5,2),
    is_active boolean DEFAULT true,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT sum_100_percent CHECK ((((((target_azionario + target_obbligazionario) + target_monetario) + COALESCE(target_oro, (0)::numeric)) + COALESCE(target_crypto, (0)::numeric)) = (100)::numeric)),
    CONSTRAINT target_allocations_target_azionario_check CHECK (((target_azionario >= (0)::numeric) AND (target_azionario <= (100)::numeric))),
    CONSTRAINT target_allocations_target_crypto_check CHECK (((target_crypto >= (0)::numeric) AND (target_crypto <= (100)::numeric))),
    CONSTRAINT target_allocations_target_monetario_check CHECK (((target_monetario >= (0)::numeric) AND (target_monetario <= (100)::numeric))),
    CONSTRAINT target_allocations_target_obbligazionario_check CHECK (((target_obbligazionario >= (0)::numeric) AND (target_obbligazionario <= (100)::numeric))),
    CONSTRAINT target_allocations_target_oro_check CHECK (((target_oro >= (0)::numeric) AND (target_oro <= (100)::numeric)))
);


ALTER TABLE public.target_allocations OWNER TO postgres;

--
-- TOC entry 5466 (class 0 OID 0)
-- Dependencies: 223
-- Name: TABLE target_allocations; Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON TABLE public.target_allocations IS 'Obiettivi di allocazione per ribilanciamento';


--
-- TOC entry 219 (class 1259 OID 100027)
-- Name: transactions; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.transactions (
    transaction_id uuid DEFAULT public.uuid_generate_v4() NOT NULL,
    portfolio_id uuid NOT NULL,
    asset_id uuid NOT NULL,
    transaction_type character varying(20) NOT NULL,
    transaction_date date NOT NULL,
    settlement_date date,
    quantity numeric(18,6) NOT NULL,
    price_per_share numeric(18,6) NOT NULL,
    total_amount numeric(18,2) NOT NULL,
    commission numeric(18,2) DEFAULT 0,
    fees numeric(18,2) DEFAULT 0,
    taxes numeric(18,2) DEFAULT 0,
    currency character varying(3) DEFAULT 'EUR'::character varying,
    exchange_rate numeric(12,6) DEFAULT 1.0,
    amount_in_base_currency numeric(18,2),
    order_id character varying(100),
    notes text,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT transactions_transaction_type_check CHECK (((transaction_type)::text = ANY ((ARRAY['BUY'::character varying, 'SELL'::character varying, 'DIVIDEND'::character varying, 'FEE'::character varying, 'TRANSFER_IN'::character varying, 'TRANSFER_OUT'::character varying])::text[])))
);


ALTER TABLE public.transactions OWNER TO postgres;

--
-- TOC entry 5467 (class 0 OID 0)
-- Dependencies: 219
-- Name: TABLE transactions; Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON TABLE public.transactions IS 'Storico completo di tutte le transazioni';


--
-- TOC entry 225 (class 1259 OID 100180)
-- Name: v_asset_allocation; Type: VIEW; Schema: public; Owner: postgres
--

CREATE VIEW public.v_asset_allocation AS
 SELECT pf.portfolio_id,
    pf.name AS portfolio_name,
    a.asset_type,
    sum((pos.quantity * ph.close_price)) AS total_value,
    ((sum((pos.quantity * ph.close_price)) / sum(sum((pos.quantity * ph.close_price))) OVER (PARTITION BY pf.portfolio_id)) * (100)::numeric) AS percentage
   FROM (((public.positions pos
     JOIN public.portfolios pf ON ((pos.portfolio_id = pf.portfolio_id)))
     JOIN public.assets a ON ((pos.asset_id = a.asset_id)))
     JOIN LATERAL ( SELECT price_history.close_price
           FROM public.price_history
          WHERE (price_history.asset_id = pos.asset_id)
          ORDER BY price_history.price_date DESC
         LIMIT 1) ph ON (true))
  WHERE (pos.quantity > (0)::numeric)
  GROUP BY pf.portfolio_id, pf.name, a.asset_type;


ALTER VIEW public.v_asset_allocation OWNER TO postgres;

--
-- TOC entry 227 (class 1259 OID 102203)
-- Name: v_current_positions; Type: VIEW; Schema: public; Owner: postgres
--

CREATE VIEW public.v_current_positions AS
 WITH position_values AS (
         SELECT pos.position_id,
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
           FROM (((public.positions pos
             JOIN public.portfolios pf ON ((pos.portfolio_id = pf.portfolio_id)))
             JOIN public.assets a ON ((pos.asset_id = a.asset_id)))
             LEFT JOIN LATERAL ( SELECT price_history.close_price,
                    price_history.price_date
                   FROM public.price_history
                  WHERE (price_history.asset_id = pos.asset_id)
                  ORDER BY price_history.price_date DESC
                 LIMIT 1) ph ON (true))
          WHERE (pos.quantity > (0)::numeric)
        )
 SELECT position_id,
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
    (((current_value - total_invested) / NULLIF(total_invested, (0)::numeric)) * (100)::numeric) AS gain_loss_pct,
    last_price_date,
    ((current_value / NULLIF(sum(current_value) OVER (PARTITION BY portfolio_id), (0)::numeric)) * (100)::numeric) AS ownership_pct,
    ((total_invested / NULLIF(sum(total_invested) OVER (PARTITION BY portfolio_id), (0)::numeric)) * (100)::numeric) AS invested_pct
   FROM position_values;


ALTER VIEW public.v_current_positions OWNER TO postgres;

--
-- TOC entry 5468 (class 0 OID 0)
-- Dependencies: 227
-- Name: VIEW v_current_positions; Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON VIEW public.v_current_positions IS 'Vista posizioni correnti con percentuali di possesso e investita';


--
-- TOC entry 239 (class 1259 OID 113688)
-- Name: v_etf_asset_allocation_normalized; Type: VIEW; Schema: public; Owner: postgres
--

CREATE VIEW public.v_etf_asset_allocation_normalized AS
 SELECT asset_allocation_id,
    asset_id,
    allocation_type,
    updated_at,
        CASE
            WHEN (weight_percent > 1.5) THEN (weight_percent / 100.0)
            ELSE weight_percent
        END AS normalized_percent
   FROM public.etf_asset_allocation a;


ALTER VIEW public.v_etf_asset_allocation_normalized OWNER TO postgres;

--
-- TOC entry 241 (class 1259 OID 113696)
-- Name: v_etf_bond_maturity_normalized; Type: VIEW; Schema: public; Owner: postgres
--

CREATE VIEW public.v_etf_bond_maturity_normalized AS
 SELECT bond_maturity_id,
    asset_id,
    maturity_range,
    avg_duration_years,
    updated_at,
        CASE
            WHEN (weight_percent > 1.5) THEN (weight_percent / 100.0)
            ELSE weight_percent
        END AS normalized_percent
   FROM public.etf_bond_maturity m;


ALTER VIEW public.v_etf_bond_maturity_normalized OWNER TO postgres;

--
-- TOC entry 240 (class 1259 OID 113692)
-- Name: v_etf_bond_ratings_normalized; Type: VIEW; Schema: public; Owner: postgres
--

CREATE VIEW public.v_etf_bond_ratings_normalized AS
 SELECT bond_rating_id,
    asset_id,
    rating_category,
    updated_at,
        CASE
            WHEN (weight_percent > 1.5) THEN (weight_percent / 100.0)
            ELSE weight_percent
        END AS normalized_percent
   FROM public.etf_bond_ratings b;


ALTER VIEW public.v_etf_bond_ratings_normalized OWNER TO postgres;

--
-- TOC entry 234 (class 1259 OID 102305)
-- Name: v_etf_composition_summary; Type: VIEW; Schema: public; Owner: postgres
--

CREATE VIEW public.v_etf_composition_summary AS
 SELECT asset_id,
    isin,
    ticker,
    name,
    asset_type,
    ( SELECT count(*) AS count
           FROM public.etf_holdings eh
          WHERE (eh.asset_id = a.asset_id)) AS holdings_count,
    ( SELECT count(*) AS count
           FROM public.etf_sector_weights esw
          WHERE (esw.asset_id = a.asset_id)) AS sectors_count,
    ( SELECT count(*) AS count
           FROM public.etf_geographic_weights egw
          WHERE (egw.asset_id = a.asset_id)) AS regions_count,
    ( SELECT count(*) AS count
           FROM public.etf_asset_allocation eaa
          WHERE (eaa.asset_id = a.asset_id)) AS asset_classes_count,
    ( SELECT max(eh.updated_at) AS max
           FROM public.etf_holdings eh
          WHERE (eh.asset_id = a.asset_id)) AS last_updated,
        CASE
            WHEN (EXISTS ( SELECT 1
               FROM public.etf_holdings eh
              WHERE (eh.asset_id = a.asset_id))) THEN true
            ELSE false
        END AS has_composition_data
   FROM public.assets a
  WHERE (is_active = true);


ALTER VIEW public.v_etf_composition_summary OWNER TO postgres;

--
-- TOC entry 5469 (class 0 OID 0)
-- Dependencies: 234
-- Name: VIEW v_etf_composition_summary; Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON VIEW public.v_etf_composition_summary IS 'Summary of available ETF composition data for each asset';


--
-- TOC entry 238 (class 1259 OID 113684)
-- Name: v_etf_geographic_weights_normalized; Type: VIEW; Schema: public; Owner: postgres
--

CREATE VIEW public.v_etf_geographic_weights_normalized AS
 SELECT geographic_weight_id,
    asset_id,
    region_name,
    updated_at,
        CASE
            WHEN (weight_percent > 1.5) THEN (weight_percent / 100.0)
            ELSE weight_percent
        END AS normalized_percent
   FROM public.etf_geographic_weights g;


ALTER VIEW public.v_etf_geographic_weights_normalized OWNER TO postgres;

--
-- TOC entry 236 (class 1259 OID 113676)
-- Name: v_etf_holdings_normalized; Type: VIEW; Schema: public; Owner: postgres
--

CREATE VIEW public.v_etf_holdings_normalized AS
 SELECT holding_id,
    asset_id,
    holding_symbol,
    holding_name,
    rank_position,
    updated_at,
        CASE
            WHEN (holding_percent > 1.5) THEN (holding_percent / 100.0)
            ELSE holding_percent
        END AS normalized_percent
   FROM public.etf_holdings h;


ALTER VIEW public.v_etf_holdings_normalized OWNER TO postgres;

--
-- TOC entry 237 (class 1259 OID 113680)
-- Name: v_etf_sector_weights_normalized; Type: VIEW; Schema: public; Owner: postgres
--

CREATE VIEW public.v_etf_sector_weights_normalized AS
 SELECT sector_weight_id,
    asset_id,
    sector_name,
    updated_at,
        CASE
            WHEN (weight_percent > 1.5) THEN (weight_percent / 100.0)
            ELSE weight_percent
        END AS normalized_percent
   FROM public.etf_sector_weights s;


ALTER VIEW public.v_etf_sector_weights_normalized OWNER TO postgres;

--
-- TOC entry 245 (class 1259 OID 113714)
-- Name: v_portfolio_allocation; Type: VIEW; Schema: public; Owner: postgres
--

CREATE VIEW public.v_portfolio_allocation AS
 WITH portfolio_totals AS (
         SELECT v_current_positions.portfolio_id,
            sum(v_current_positions.current_value) AS total_portfolio_value
           FROM public.v_current_positions
          GROUP BY v_current_positions.portfolio_id
        )
 SELECT p.portfolio_id,
    p.asset_id,
    p.ticker AS etf_ticker,
    p.asset_name AS etf_name,
    p.current_value AS etf_value,
    a.allocation_type,
    a.normalized_percent AS allocation_weight_in_etf,
    (a.normalized_percent * p.current_value) AS allocation_value_in_portfolio,
    pt.total_portfolio_value
   FROM ((public.v_current_positions p
     JOIN public.v_etf_asset_allocation_normalized a ON ((p.asset_id = a.asset_id)))
     JOIN portfolio_totals pt ON ((p.portfolio_id = pt.portfolio_id)));


ALTER VIEW public.v_portfolio_allocation OWNER TO postgres;

--
-- TOC entry 244 (class 1259 OID 113709)
-- Name: v_portfolio_geographic; Type: VIEW; Schema: public; Owner: postgres
--

CREATE VIEW public.v_portfolio_geographic AS
 WITH portfolio_totals AS (
         SELECT v_current_positions.portfolio_id,
            sum(v_current_positions.current_value) AS total_portfolio_value
           FROM public.v_current_positions
          GROUP BY v_current_positions.portfolio_id
        )
 SELECT p.portfolio_id,
    p.asset_id,
    p.ticker AS etf_ticker,
    p.asset_name AS etf_name,
    p.current_value AS etf_value,
    g.region_name,
    g.normalized_percent AS region_weight_in_etf,
    (g.normalized_percent * p.current_value) AS region_value_in_portfolio,
    pt.total_portfolio_value
   FROM ((public.v_current_positions p
     JOIN public.v_etf_geographic_weights_normalized g ON ((p.asset_id = g.asset_id)))
     JOIN portfolio_totals pt ON ((p.portfolio_id = pt.portfolio_id)));


ALTER VIEW public.v_portfolio_geographic OWNER TO postgres;

--
-- TOC entry 235 (class 1259 OID 113671)
-- Name: v_portfolio_holdings; Type: VIEW; Schema: public; Owner: postgres
--

CREATE VIEW public.v_portfolio_holdings AS
 WITH normalized_holdings AS (
         SELECT h_1.holding_id,
            h_1.asset_id,
            h_1.holding_symbol,
            h_1.holding_name,
                CASE
                    WHEN (h_1.holding_percent > 1.5) THEN (h_1.holding_percent / 100.0)
                    ELSE h_1.holding_percent
                END AS normalized_percent
           FROM public.etf_holdings h_1
        ), portfolio_totals AS (
         SELECT v_current_positions.portfolio_id,
            sum(v_current_positions.current_value) AS total_portfolio_value
           FROM public.v_current_positions
          GROUP BY v_current_positions.portfolio_id
        )
 SELECT p.portfolio_id,
    p.asset_id,
    p.ticker AS etf_ticker,
    p.asset_name AS etf_name,
    p.current_value AS etf_value,
    h.holding_symbol,
    h.holding_name,
    h.normalized_percent AS holding_weight_in_etf,
    (h.normalized_percent * p.current_value) AS holding_value_in_portfolio,
    pt.total_portfolio_value
   FROM ((public.v_current_positions p
     JOIN normalized_holdings h ON ((p.asset_id = h.asset_id)))
     JOIN portfolio_totals pt ON ((p.portfolio_id = pt.portfolio_id)))
  WHERE (((h.holding_name)::text <> ALL ((ARRAY['Altri'::character varying, 'Other'::character varying, 'Others'::character varying, 'Altro'::character varying])::text[])) AND ((h.holding_symbol IS NOT NULL) AND ((h.holding_symbol)::text <> ''::text)));


ALTER VIEW public.v_portfolio_holdings OWNER TO postgres;

--
-- TOC entry 242 (class 1259 OID 113700)
-- Name: v_portfolio_holdings_aggregated; Type: VIEW; Schema: public; Owner: postgres
--

CREATE VIEW public.v_portfolio_holdings_aggregated AS
 SELECT portfolio_id,
    holding_symbol,
    min((holding_name)::text) AS holding_name,
    sum(holding_value_in_portfolio) AS total_holding_value,
    max(total_portfolio_value) AS total_portfolio_value,
    (sum(holding_value_in_portfolio) / NULLIF(max(total_portfolio_value), (0)::numeric)) AS weighted_percent
   FROM public.v_portfolio_holdings ph
  GROUP BY portfolio_id, holding_symbol;


ALTER VIEW public.v_portfolio_holdings_aggregated OWNER TO postgres;

--
-- TOC entry 226 (class 1259 OID 100185)
-- Name: v_portfolio_performance; Type: VIEW; Schema: public; Owner: postgres
--

CREATE VIEW public.v_portfolio_performance AS
 SELECT pf.portfolio_id,
    pf.name AS portfolio_name,
    COALESCE(sum(pos.total_invested), (0)::numeric) AS total_invested,
    COALESCE(sum((pos.quantity * COALESCE(ph.close_price, pos.average_buy_price))), (0)::numeric) AS current_value,
    COALESCE(sum(((pos.quantity * COALESCE(ph.close_price, pos.average_buy_price)) - pos.total_invested)), (0)::numeric) AS total_gain_loss,
        CASE
            WHEN (sum(pos.total_invested) > (0)::numeric) THEN ((sum(((pos.quantity * COALESCE(ph.close_price, pos.average_buy_price)) - pos.total_invested)) / sum(pos.total_invested)) * (100)::numeric)
            ELSE (0)::numeric
        END AS total_gain_loss_pct,
    count(
        CASE
            WHEN (pos.quantity > (0)::numeric) THEN 1
            ELSE NULL::integer
        END) AS number_of_positions
   FROM ((public.portfolios pf
     LEFT JOIN public.positions pos ON (((pf.portfolio_id = pos.portfolio_id) AND (pos.quantity > (0)::numeric))))
     LEFT JOIN LATERAL ( SELECT price_history.close_price
           FROM public.price_history
          WHERE (price_history.asset_id = pos.asset_id)
          ORDER BY price_history.price_date DESC
         LIMIT 1) ph ON (true))
  WHERE (pf.is_active = true)
  GROUP BY pf.portfolio_id, pf.name;


ALTER VIEW public.v_portfolio_performance OWNER TO postgres;

--
-- TOC entry 243 (class 1259 OID 113704)
-- Name: v_portfolio_sectors; Type: VIEW; Schema: public; Owner: postgres
--

CREATE VIEW public.v_portfolio_sectors AS
 WITH portfolio_totals AS (
         SELECT v_current_positions.portfolio_id,
            sum(v_current_positions.current_value) AS total_portfolio_value
           FROM public.v_current_positions
          GROUP BY v_current_positions.portfolio_id
        )
 SELECT p.portfolio_id,
    p.asset_id,
    p.ticker AS etf_ticker,
    p.asset_name AS etf_name,
    p.current_value AS etf_value,
    s.sector_name,
    s.normalized_percent AS sector_weight_in_etf,
    (s.normalized_percent * p.current_value) AS sector_value_in_portfolio,
    pt.total_portfolio_value
   FROM ((public.v_current_positions p
     JOIN public.v_etf_sector_weights_normalized s ON ((p.asset_id = s.asset_id)))
     JOIN portfolio_totals pt ON ((p.portfolio_id = pt.portfolio_id)));


ALTER VIEW public.v_portfolio_sectors OWNER TO postgres;

--
-- TOC entry 5429 (class 0 OID 113797)
-- Dependencies: 246
-- Data for Name: allocation_categories; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.allocation_categories (category_id, portfolio_id, category_name, target_percent, display_order, color_hex, is_active, created_at, updated_at) FROM stdin;
7860ef75-e5c8-4bc3-954a-c984fe448a9e	a5938c95-ba8e-46f6-98f2-4e670ba3b2a4	Oro	15.00	0	#f7e73b	t	2025-11-27 20:22:43.457951+01	2025-11-28 10:33:35.447965+01
68685173-af8d-4c9e-be00-a07047c4d243	a5938c95-ba8e-46f6-98f2-4e670ba3b2a4	Obbligazionario	15.00	0	#3bf77a	t	2025-11-28 10:34:31.512472+01	2025-11-28 10:34:31.512472+01
e02401d2-a445-4b3f-a3d9-419758df952e	a5938c95-ba8e-46f6-98f2-4e670ba3b2a4	Bitcoin	5.00	0	#f73b3b	t	2025-11-28 10:34:48.921199+01	2025-11-28 10:34:48.921199+01
362ead89-c6c3-42f4-8bc7-4abafddd521a	a5938c95-ba8e-46f6-98f2-4e670ba3b2a4	Azionario	65.00	0	#3B82F6	t	2025-11-26 16:11:11.771579+01	2025-11-28 16:03:30.612592+01
\.


--
-- TOC entry 5416 (class 0 OID 100009)
-- Dependencies: 218
-- Data for Name: assets; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.assets (asset_id, isin, ticker, name, asset_type, asset_category, currency, country, region, sector, industry, benchmark_index, ter, transaction_cost, esg_rating, is_accumulation, is_active, created_at, updated_at, description, sharpe_ratio, annual_fees, standard_deviation, isr, factsheet_url, composition_last_updated) FROM stdin;
cc52fa73-bb3a-49ea-bb36-a0191f934e11	IE00B579F325	SGLD.MI	Invesco Physical Gold ETC	Oro	\N	EUR	Globale	Global	Metalli Preziosi	\N	\N	0.0000	\N	\N	\N	t	2025-11-04 12:45:09.782615+01	2025-11-09 17:51:32.350946+01	\N	1.1700	0.1200	11.3600	4	https://images.fineco.it/pvt/pdf/kid/IT/IE00B579F325_20250717_IT_KID.pdf	2025-11-08 17:37:16.049015+01
fda2e7d3-54a5-4b6b-a504-48873da1c697	GB00BVG7F061	BRSL	BRIGHTSTAR LOTTERY	Azione Singola	\N	USD	USA		Gaming	\N	\N	0.0000	\N	\N	\N	t	2025-11-05 12:35:29.892777+01	2025-11-10 14:37:39.841516+01	\N	0.0000	0.0000	0.0000	1	https://finance.yahoo.com/quote/BRSL/	2025-11-10 14:37:39.841516+01
fc48529f-7c1b-41f4-9975-fc576e2788bd	IE00BJ5JPG56	ICGA.DE	MSCI CHINA USD-AC	Azionario	\N	EUR	China		Diversificato	\N	\N	0.0000	\N	\N	\N	t	2025-11-05 12:35:29.892777+01	2025-11-09 18:17:35.824821+01	\N	0.5500	0.3300	31.5000	5	https://api.fundinfo.com/document/6e6609e16096bc5cc0931fc6066916b4_258434/MR_IT_it_IE00BJ5JPG56_YES_2025-08-31.pdf	2025-11-09 18:17:35.824821+01
e0534574-8100-43c6-a396-f954f8ac95be	LU1781541252	LCJP.MI	Amundi Japan TOPIX UCITS ETF	Azionario	\N	EUR	Giappone		Diversificato	\N	\N	0.0000	\N	\N	\N	t	2025-11-05 12:35:29.892777+01	2025-11-09 18:20:39.635127+01	\N	1.3400	0.1200	11.6800	1	https://api.fundinfo.com/document/5810274fa8d601efedbca9cb9d26fca9_406636/MR_IT_it_LU1781541252_YES_2025-10-31.pdf	2025-11-09 18:20:39.635127+01
bcdff4ec-d4bf-419e-afb1-49beea99eeaf	IE000YYE6WK5	DFEN.DE	VanEck Defense UCITS ETF	Azionario	\N	EUR	Globale		Difesa	\N	\N	0.0000	\N	\N	\N	t	2025-11-05 12:35:29.892777+01	2025-11-09 18:23:01.038402+01	\N	0.0000	0.5500	19.1400	5	https://api.fundinfo.com/document/ab48b33f9056352785f4c51024deb9c1_128216/MR_IT_it_IE000YYE6WK5_YES_2025-07-31.pdf	2025-11-09 18:23:01.038402+01
c743dda6-c6ba-43c2-a14e-75490a1b06b0	LU1650487413	EM13.MI	Amundi Euro Government Bond 1-3Y UCITS ETF Acc	Obbligazionario	\N	EUR	Europa	Europa	Titoli stato	\N	\N	0.0000	\N	\N	\N	t	2025-11-05 12:35:29.892777+01	2025-11-23 14:48:36.564523+01	\N	0.9600	0.1500	2.1200	2	https://api.fundinfo.com/document/a69372868934a274866b8203d26cfed9_439923/MR_IT_it_LU1650487413_YES_2025-10-31.pdf	2025-11-23 14:48:36.564523+01
6e5b011b-1658-420d-886d-4f0802372d0b	IE00BP3QZ825	IWFM.L	iShares Core STOXX Europe 600 UCITS ETF	Azionario	\N	EUR	Europa	Europa	Diversificato	\N	STOXX 600	\N	\N	\N	t	f	2025-11-04 12:45:09.778244+01	2025-11-06 09:04:16.466654+01	\N	\N	\N	\N	\N	\N	\N
0ede49d0-617f-451f-b90e-7fd9631cfa04	LU2090063673	LCJP.MI	Amundi Japan TOPIX UCITS ETF	Azionario	\N	EUR	Giappone	Asia	Diversificato	\N	\N	0.0000	\N	\N	\N	f	2025-11-04 12:45:09.779073+01	2025-11-06 09:10:02.856955+01	\N	1.3400	0.1200	11.6800	\N	\N	\N
92125d99-571e-42c7-8369-4ce85c866078	LU0378434582	EM13	Amundi Euro Government Bond 1-3Y	Obbligazionario	\N	EUR	Europa	Europa	Obbligazioni Gov	\N	\N	0.0000	\N	\N	\N	f	2025-11-04 12:45:09.780885+01	2025-11-06 09:16:22.727291+01	\N	0.0000	0.0000	0.0000	\N	\N	\N
bf3b3448-1ec3-4f29-87e3-7fc90bc83308	LU1829221024	UST.MI	Amundi Nasdaq-100 UCITS ETF	Azionario	\N	EUR	USA	Nord America	Tecnologia	\N	\N	0.0000	\N	\N	\N	t	2025-11-04 12:45:09.775511+01	2025-11-09 17:42:38.826816+01	\N	0.3200	0.2200	21.2100	5	https://api.fundinfo.com/document/73afc09e0b7464eee3ba6523ba999228_417223/MR_IT_it_LU1829221024_YES_2025-10-31.pdf	2025-11-09 17:42:38.826816+01
8f706b9d-54ae-4ac7-8ce5-0ed005362d68	IE00BJQRDN15	IQSA.MI	Invesco Quantitative Strategies Global Equity	Azionario	\N	EUR	Globale	Global	Diversificato	\N	\N	0.0000	\N	\N	\N	t	2025-11-04 12:45:09.77742+01	2025-11-09 17:44:33.678445+01	\N	0.3400	0.3000	18.0400	1	https://api.fundinfo.com/document/b5957e53b4c7ec4b0efd8935514c8d0a_1133962/MR_IT_it_IE00BJQRDN15_YES_2025-09-30.pdf	2025-11-08 17:31:02.260804+01
0999dc6a-e6f9-4bbf-9bd2-30a25658de89	LU1287023185	EM710.MI	Amundi Euro Government Bond 7-10Y UCITS ETF Acc	Obbligazionario	\N	EUR	Europa		Titoli stato	\N	\N	0.0000	\N	\N	\N	t	2025-11-05 12:35:29.892777+01	2025-11-09 17:30:13.286655+01	\N	0.6600	0.1500	8.5800	3	https://api.fundinfo.com/document/95d896cfed9e4656af606d476b631d8a_440679/MR_IT_it_LU1287023185_YES_2025-10-31.pdf	2025-11-09 17:30:13.286655+01
c117885f-43f8-4be0-8df2-f6d30a200cca	IE00B4L5Y983	SWDA.MI	iShares Core MSCI World UCITS ETF	Azionario	\N	EUR	Globale	Global	Diversificato	\N	\N	0.0000	\N	\N	\N	t	2025-11-04 12:45:09.776579+01	2025-11-09 17:45:07.647849+01	\N	0.1900	0.0200	15.7900	4	https://api.fundinfo.com/document/207efe477d072d985b922a239f3d0c18_381039/MR_IT_it_IE00B4L5Y983_YES_2025-09-30.pdf	2025-11-08 17:06:28.357133+01
d2c980bc-c787-4166-8e74-d074800bf867	IE00BGYWFS63	VDTA.MI	Vanguard USD Treasury Bond UCITS ETF	Obbligazionario	\N	EUR	USA	Nord America	Governativi	\N	\N	0.0000	\N	\N	\N	t	2025-11-04 12:45:09.779995+01	2025-11-09 17:48:54.739563+01	\N	0.1200	0.0700	6.5200	3	https://api.fundinfo.com/document/31d0fe28a496a396452ebe37047f12a6_413067/MR_IT_en_IE00BGYWFS63_RES_2025-09-30.pdf	2025-11-09 17:16:45.576933+01
b46bba4b-525d-483d-bf4e-f195bde3d6bc	IE00B5BMR087	CSSPX.MI	iShares Core S&P 500 UCITS ETF	Azionario	\N	EUR	USA	Nord America	Tecnologia	\N	\N	0.0000	\N	\N	\N	t	2025-11-04 12:45:09.749129+01	2025-11-09 17:45:51.89288+01	\N	0.3200	0.1200	16.1000	4	https://api.fundinfo.com/document/f4e5cf3a5e19c89e83bd32f82a3ed3a7_355121/MR_IT_it_IE00B5BMR087_YES_2025-09-30.pdf	2025-11-08 17:19:32.530707+01
f1daeb66-3038-40d7-beea-ba11dd317ae9	IE00B53L3W79	CSSX5E.MI	ISHS CR STX 50 EUR-AC	Azionario	\N	EUR	Europa		Diversificato	\N	\N	0.0000	\N	\N	\N	t	2025-11-05 12:35:29.892777+01	2025-11-09 17:46:18.165746+01	\N	0.6100	0.1000	16.5400	1	https://api.fundinfo.com/document/19b28abed3139fff0af8589c2c839afb_375690/MR_IT_it_IE00B53L3W79_YES_2025-09-30.pdf	2025-11-08 17:20:11.535478+01
3a15e4de-589b-450d-93d1-a19b0c7bdb28	LU0290358497	XEON.DE	Xtrackers EUR Overnight Rate Swap UCITS ETF	Monetario	\N	EUR	Europa	Europa	Cash	\N	\N	0.0000	\N	\N	\N	t	2025-11-04 12:45:09.783368+01	2025-11-09 17:49:33.652665+01	\N	0.7700	0.1000	0.7700	1	https://api.fundinfo.com/document/65cf93c4396efc32a67fe0fb1a358bb5_224349/MR_IT_it_LU0290358497_YES_2025-08-29.pdf	\N
719121c9-908d-49b7-a047-23464f0960ab	LU0908500753	MEUD.MI	LIF C S EU 600 UEAC	Azionario	\N	EUR	Europa		Diversificato	\N	\N	0.0000	\N	\N	\N	t	2025-11-05 12:35:29.892777+01	2025-11-09 17:46:53.653487+01	\N	1.7300	0.0700	10.9200	4	https://api.fundinfo.com/document/605d18d0e25e2d1076d472eb161151b8_2004152/MR_IT_it_LU0908500753_RES_2025-10-31.pdf	2025-11-08 17:24:51.177479+01
\.


--
-- TOC entry 5420 (class 0 OID 100091)
-- Dependencies: 222
-- Data for Name: dividends; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.dividends (dividend_id, portfolio_id, asset_id, payment_date, ex_dividend_date, dividend_per_share, quantity, total_dividend, withholding_tax, net_dividend, currency, created_at) FROM stdin;
\.


--
-- TOC entry 5426 (class 0 OID 102257)
-- Dependencies: 231
-- Data for Name: etf_asset_allocation; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.etf_asset_allocation (asset_allocation_id, asset_id, allocation_type, weight_percent, updated_at) FROM stdin;
7db7f2b0-958e-49ec-a7cc-dfe5b55b32d4	b46bba4b-525d-483d-bf4e-f195bde3d6bc	Equity	1.0000	2025-11-08 17:19:32.530707+01
a681d067-0c4a-4a7a-92cf-d1d7550ecc6a	3a15e4de-589b-450d-93d1-a19b0c7bdb28	Equity	1.0000	2025-11-08 17:38:32.297222+01
33f77fcf-b325-4e15-b434-ea758d034406	d2c980bc-c787-4166-8e74-d074800bf867	Bond	1.0000	2025-11-09 17:16:45.576933+01
1748e2a3-7b90-491e-a1b7-b24dbc2e12c8	0999dc6a-e6f9-4bbf-9bd2-30a25658de89	Bond	0.9734	2025-11-09 17:30:13.286655+01
697c6bd5-b9ff-488a-a13b-87ae703a7e89	0999dc6a-e6f9-4bbf-9bd2-30a25658de89	Cash	0.0266	2025-11-09 17:30:13.286655+01
2531fc16-fe65-481f-b556-682b63673a4a	bf3b3448-1ec3-4f29-87e3-7fc90bc83308	Equity	1.0000	2025-11-09 17:42:38.826816+01
d5ff6359-ff71-470c-b503-651106077dc2	fc48529f-7c1b-41f4-9975-fc576e2788bd	Equity	1.0000	2025-11-09 18:17:35.824821+01
70fddb1a-35e2-4b93-9d38-e04ece40d39e	e0534574-8100-43c6-a396-f954f8ac95be	Equity	1.0000	2025-11-09 18:20:39.635127+01
bc77c4ed-8c2b-48cb-9488-2424f68ca54a	bcdff4ec-d4bf-419e-afb1-49beea99eeaf	Equity	1.0000	2025-11-09 18:23:01.038402+01
f8867f5b-a44d-4c70-a4fd-1120e0d0afe0	fda2e7d3-54a5-4b6b-a504-48873da1c697	Equity	1.0000	2025-11-10 14:37:39.841516+01
2daca682-3008-4531-8dd5-117ae563cb72	c743dda6-c6ba-43c2-a14e-75490a1b06b0	Bond	0.9994	2025-11-23 14:48:36.564523+01
7cca7d59-0f5d-4b2a-ace8-1bdba00b1275	c743dda6-c6ba-43c2-a14e-75490a1b06b0	Cash	0.0006	2025-11-23 14:48:36.564523+01
\.


--
-- TOC entry 5428 (class 0 OID 102290)
-- Dependencies: 233
-- Data for Name: etf_bond_maturity; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.etf_bond_maturity (bond_maturity_id, asset_id, maturity_range, weight_percent, avg_duration_years, updated_at) FROM stdin;
59dc2cbe-4e31-4d0b-a752-324db55d511d	d2c980bc-c787-4166-8e74-d074800bf867	3-5 Years	0.2850	\N	2025-11-09 17:16:45.576933+01
e0c70899-aa61-485e-bcee-f28e425dc4a2	d2c980bc-c787-4166-8e74-d074800bf867	1-3 Years	0.2800	\N	2025-11-09 17:16:45.576933+01
22f9b714-f3af-49af-b10b-3eea318bdc80	d2c980bc-c787-4166-8e74-d074800bf867	5-7 Years	0.1170	\N	2025-11-09 17:16:45.576933+01
98fee569-d125-4c82-8c67-1acb1ce9d215	d2c980bc-c787-4166-8e74-d074800bf867	7-10 Years	0.1100	\N	2025-11-09 17:16:45.576933+01
7488aca3-ccf2-4f1c-9197-7ee6804d93ed	d2c980bc-c787-4166-8e74-d074800bf867	20+ Years	0.1060	\N	2025-11-09 17:16:45.576933+01
f17cd650-2cd8-4ee5-8fec-63ae4da18469	d2c980bc-c787-4166-8e74-d074800bf867	15-20 Years	0.0810	\N	2025-11-09 17:16:45.576933+01
2697232b-cfb0-46d3-a850-1b6204f5f9c4	d2c980bc-c787-4166-8e74-d074800bf867	10-15 Years	0.0120	\N	2025-11-09 17:16:45.576933+01
c9509528-0f23-4c62-8562-b587b6dadaf5	d2c980bc-c787-4166-8e74-d074800bf867	0-1 Years	0.0030	\N	2025-11-09 17:16:45.576933+01
1ecc9a53-4871-40a3-ad34-6c4c427d9398	0999dc6a-e6f9-4bbf-9bd2-30a25658de89	7-10 Years	1.0000	\N	2025-11-09 17:30:13.286655+01
fd15d315-33b2-4bf0-a0c8-2f8743105c12	c743dda6-c6ba-43c2-a14e-75490a1b06b0	1-3 Years	1.0000	\N	2025-11-23 14:48:36.564523+01
\.


--
-- TOC entry 5427 (class 0 OID 102275)
-- Dependencies: 232
-- Data for Name: etf_bond_ratings; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.etf_bond_ratings (bond_rating_id, asset_id, rating_category, weight_percent, updated_at) FROM stdin;
345a9c83-2502-4002-8167-c92c1a5ebccf	d2c980bc-c787-4166-8e74-d074800bf867	AA	0.9970	2025-11-09 17:16:45.576933+01
23185085-b97f-46f6-8f5b-1d257ba077f7	d2c980bc-c787-4166-8e74-d074800bf867	Not Rated	0.0030	2025-11-09 17:16:45.576933+01
8be4c8ec-ad85-485a-8f84-7fb15105e24b	0999dc6a-e6f9-4bbf-9bd2-30a25658de89	A	0.3861	2025-11-09 17:30:13.286655+01
858f8194-c6c2-41b2-83b4-a66d03caeb37	0999dc6a-e6f9-4bbf-9bd2-30a25658de89	AAA	0.2260	2025-11-09 17:30:13.286655+01
79b84a1f-e74e-4ecf-a96d-46ff54ff7a9e	0999dc6a-e6f9-4bbf-9bd2-30a25658de89	BBB	0.2209	2025-11-09 17:30:13.286655+01
4ddbfa1f-58a4-4894-814e-a4fd197898eb	0999dc6a-e6f9-4bbf-9bd2-30a25658de89	AA	0.1404	2025-11-09 17:30:13.286655+01
432cf636-dc06-4643-a9ae-90630efa8492	0999dc6a-e6f9-4bbf-9bd2-30a25658de89	Not Rated	0.0266	2025-11-09 17:30:13.286655+01
ecacdead-5e44-4a71-903c-310e2ea495bd	c743dda6-c6ba-43c2-a14e-75490a1b06b0	A	0.4070	2025-11-23 14:48:36.564523+01
a490b28a-218c-476f-aa21-ac71ef46ea8d	c743dda6-c6ba-43c2-a14e-75490a1b06b0	AAA	0.2618	2025-11-23 14:48:36.564523+01
3730c8f3-1183-4c0f-820b-ed7609dd5f34	c743dda6-c6ba-43c2-a14e-75490a1b06b0	BBB	0.2351	2025-11-23 14:48:36.564523+01
a165c684-2af7-410f-85e5-ad73fb19c02b	c743dda6-c6ba-43c2-a14e-75490a1b06b0	AA	0.0955	2025-11-23 14:48:36.564523+01
942cd7dd-ef75-459d-bf9a-f9dd024499b4	c743dda6-c6ba-43c2-a14e-75490a1b06b0	Not Rated	0.0006	2025-11-23 14:48:36.564523+01
\.


--
-- TOC entry 5425 (class 0 OID 102240)
-- Dependencies: 230
-- Data for Name: etf_geographic_weights; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.etf_geographic_weights (geographic_weight_id, asset_id, region_name, weight_percent, updated_at) FROM stdin;
f4919555-9a7a-4559-81ff-6bf031987a26	c117885f-43f8-4be0-8df2-f6d30a200cca	Stati Uniti	0.6847	2025-11-08 17:06:28.357133+01
c427201b-10d3-4e54-a89d-d83a406e40d4	c117885f-43f8-4be0-8df2-f6d30a200cca	Giappone	0.0547	2025-11-08 17:06:28.357133+01
ffaa4e8e-3bb8-407b-9061-bdf2d30ba0aa	c117885f-43f8-4be0-8df2-f6d30a200cca	Regno Unito	0.0351	2025-11-08 17:06:28.357133+01
14e380aa-6f8e-4c75-8fc3-01cfc8070239	c117885f-43f8-4be0-8df2-f6d30a200cca	Canada	0.0289	2025-11-08 17:06:28.357133+01
aa20616d-9df5-4c28-aede-94d724747d93	c117885f-43f8-4be0-8df2-f6d30a200cca	Svizzera	0.0248	2025-11-08 17:06:28.357133+01
aaadf693-539c-4ea4-9312-634a085ec646	c117885f-43f8-4be0-8df2-f6d30a200cca	Germania	0.0244	2025-11-08 17:06:28.357133+01
90454eb4-8581-42c7-b685-a4c55aaab72f	c117885f-43f8-4be0-8df2-f6d30a200cca	Francia	0.0242	2025-11-08 17:06:28.357133+01
8695c78b-f9e9-40ef-a5fc-3d6ee1b25892	c117885f-43f8-4be0-8df2-f6d30a200cca	Australia	0.0166	2025-11-08 17:06:28.357133+01
643585d8-82ad-40b1-9838-333eb1c63913	c117885f-43f8-4be0-8df2-f6d30a200cca	Paesi bassi	0.0131	2025-11-08 17:06:28.357133+01
2c1f8848-5628-4bc1-8da2-4c95733bf42f	c117885f-43f8-4be0-8df2-f6d30a200cca	Irlanda	0.0131	2025-11-08 17:06:28.357133+01
dab7893d-942a-4304-a2cf-519a85a0c04f	c117885f-43f8-4be0-8df2-f6d30a200cca	Altri	0.0804	2025-11-08 17:06:28.357133+01
7445b3b4-8c91-47fa-9651-a7de8798b33d	b46bba4b-525d-483d-bf4e-f195bde3d6bc	Stati Uniti	0.9570	2025-11-08 17:19:32.530707+01
349573ab-57cd-4484-814b-ab7a95c4604a	b46bba4b-525d-483d-bf4e-f195bde3d6bc	Irlanda	0.0134	2025-11-08 17:19:32.530707+01
86db5683-5639-4fcc-bffd-ab3686c648d4	b46bba4b-525d-483d-bf4e-f195bde3d6bc	Altri	0.0296	2025-11-08 17:19:32.530707+01
e85a6396-f943-4961-99e6-5e3f4a3d34e9	f1daeb66-3038-40d7-beea-ba11dd317ae9	Francia	0.3313	2025-11-08 17:20:11.535478+01
3204ede4-5989-461f-8349-df3c98ebe85d	f1daeb66-3038-40d7-beea-ba11dd317ae9	Germania	0.2964	2025-11-08 17:20:11.535478+01
cc857b44-c4d7-49b5-9fc7-7904e27aa584	f1daeb66-3038-40d7-beea-ba11dd317ae9	Paesi bassi	0.1586	2025-11-08 17:20:11.535478+01
5102f37f-2710-496c-ae82-892dc7043d04	f1daeb66-3038-40d7-beea-ba11dd317ae9	Spagna	0.0932	2025-11-08 17:20:11.535478+01
c0bef6bf-6f45-4631-9bf2-9d1db35e583b	f1daeb66-3038-40d7-beea-ba11dd317ae9	Italia	0.0854	2025-11-08 17:20:11.535478+01
a3653eb4-941f-4441-a9c4-a1f0fb8d7b7e	f1daeb66-3038-40d7-beea-ba11dd317ae9	Finlandia	0.0163	2025-11-08 17:20:11.535478+01
8a910c12-24d9-4c10-9f32-5ac1df14c730	f1daeb66-3038-40d7-beea-ba11dd317ae9	Belgio	0.0144	2025-11-08 17:20:11.535478+01
80350a8e-5b32-4778-9a94-cae6d46d300f	f1daeb66-3038-40d7-beea-ba11dd317ae9	Altri	0.0044	2025-11-08 17:20:11.535478+01
6277812c-767d-470c-9910-34c89cd9f597	719121c9-908d-49b7-a047-23464f0960ab	Regno Unito	0.2137	2025-11-08 17:24:51.177479+01
48a535b1-520e-416a-95f4-233f1a80e9f6	719121c9-908d-49b7-a047-23464f0960ab	Germania	0.1456	2025-11-08 17:24:51.177479+01
4ec17f19-90e7-40a7-ad2a-d3f6f24631fa	719121c9-908d-49b7-a047-23464f0960ab	Francia	0.1428	2025-11-08 17:24:51.177479+01
a6751120-56f2-4883-9410-ac940e60671f	719121c9-908d-49b7-a047-23464f0960ab	Svizzera	0.1357	2025-11-08 17:24:51.177479+01
6d15ca74-e04a-40ef-b22f-59cb17c0cb6a	719121c9-908d-49b7-a047-23464f0960ab	Paesi bassi	0.0742	2025-11-08 17:24:51.177479+01
f1bed854-7d26-4be1-9069-67e1459ac906	719121c9-908d-49b7-a047-23464f0960ab	Italia	0.0494	2025-11-08 17:24:51.177479+01
288f476a-6c2b-4b8b-96d6-c443fae1a4c6	719121c9-908d-49b7-a047-23464f0960ab	Spagna	0.0490	2025-11-08 17:24:51.177479+01
dcbfc156-185b-4547-8650-0a5cde02cd09	719121c9-908d-49b7-a047-23464f0960ab	Svezia	0.0454	2025-11-08 17:24:51.177479+01
ee0eb043-bbc3-4bff-9bfa-b5bc2a6c25a3	719121c9-908d-49b7-a047-23464f0960ab	Danimarca	0.0178	2025-11-08 17:24:51.177479+01
b4379584-742a-4f7a-8dca-2c1574f8498d	719121c9-908d-49b7-a047-23464f0960ab	Finlandia	0.0148	2025-11-08 17:24:51.177479+01
d3f976b8-74f1-492b-80e9-5d0f3df4d736	719121c9-908d-49b7-a047-23464f0960ab	Belgio	0.0137	2025-11-08 17:24:51.177479+01
2e9904b2-1ca9-456c-a10e-b33405b9d1d3	719121c9-908d-49b7-a047-23464f0960ab	Irlanda	0.0107	2025-11-08 17:24:51.177479+01
5b6950dc-4385-4bcd-819b-63caf89c92a7	719121c9-908d-49b7-a047-23464f0960ab	Altri	0.0872	2025-11-08 17:24:51.177479+01
a5a37a7f-46db-4cdc-9f1b-922a4ce2c669	8f706b9d-54ae-4ac7-8ce5-0ed005362d68	Stati Uniti	0.6421	2025-11-08 17:31:02.260804+01
cc0f303b-7419-4620-93d1-9338a5c4da1f	8f706b9d-54ae-4ac7-8ce5-0ed005362d68	Giappone	0.0846	2025-11-08 17:31:02.260804+01
c4e89ca2-f1c5-48bf-a964-a90b3423da6b	8f706b9d-54ae-4ac7-8ce5-0ed005362d68	Francia	0.0427	2025-11-08 17:31:02.260804+01
be28f251-9427-4a1e-8003-523dc1a63f30	8f706b9d-54ae-4ac7-8ce5-0ed005362d68	Canada	0.0353	2025-11-08 17:31:02.260804+01
aa160233-72e3-42ac-96c7-b10f5bdeedca	8f706b9d-54ae-4ac7-8ce5-0ed005362d68	Irlanda	0.0311	2025-11-08 17:31:02.260804+01
6e7598ba-8a0d-49c1-835a-f3ca4a8d895a	8f706b9d-54ae-4ac7-8ce5-0ed005362d68	Danimarca	0.0222	2025-11-08 17:31:02.260804+01
b0aca03b-5432-4258-8c63-4637abda52c3	8f706b9d-54ae-4ac7-8ce5-0ed005362d68	Germania	0.0185	2025-11-08 17:31:02.260804+01
796d28ab-aede-4a25-91d2-7ff91c6c2614	8f706b9d-54ae-4ac7-8ce5-0ed005362d68	Paesi bassi	0.0163	2025-11-08 17:31:02.260804+01
1725601f-b54e-4c8d-8f74-a69a206d345c	8f706b9d-54ae-4ac7-8ce5-0ed005362d68	Italia	0.0155	2025-11-08 17:31:02.260804+01
046ae2c5-ee09-4c9a-855c-84f9a93b8c58	8f706b9d-54ae-4ac7-8ce5-0ed005362d68	Svezia	0.0105	2025-11-08 17:31:02.260804+01
79e64b7c-0d10-4e4e-8e7e-2565d8878538	8f706b9d-54ae-4ac7-8ce5-0ed005362d68	Regno Unito	0.0104	2025-11-08 17:31:02.260804+01
a799cb68-bc81-40bd-8765-43cc67667680	8f706b9d-54ae-4ac7-8ce5-0ed005362d68	Altri	0.0708	2025-11-08 17:31:02.260804+01
381a7d70-3d38-4034-b10a-94b115a6f73f	e0534574-8100-43c6-a396-f954f8ac95be	Giappone	0.9992	2025-11-09 18:20:39.635127+01
121588d9-893c-42b1-a5ce-3002169578e6	e0534574-8100-43c6-a396-f954f8ac95be	Altri	0.0008	2025-11-09 18:20:39.635127+01
72bc5da9-1a32-4182-8380-38fcecd89374	bcdff4ec-d4bf-419e-afb1-49beea99eeaf	Stati Uniti	0.4883	2025-11-09 18:23:01.038402+01
6e5530f1-d96a-4602-b2b3-d35b5ea2f55a	bcdff4ec-d4bf-419e-afb1-49beea99eeaf	Altri	0.1160	2025-11-09 18:23:01.038402+01
6cf2f655-7924-483e-bc39-fe59c1eb32e4	bcdff4ec-d4bf-419e-afb1-49beea99eeaf	Corea del Sud	0.1054	2025-11-09 18:23:01.038402+01
a44fb77c-566c-448a-b5f2-49d2ec71382e	bcdff4ec-d4bf-419e-afb1-49beea99eeaf	Francia	0.0880	2025-11-09 18:23:01.038402+01
55621209-4950-4496-a7bb-d66ac374dda1	bcdff4ec-d4bf-419e-afb1-49beea99eeaf	Italia	0.0761	2025-11-09 18:23:01.038402+01
8db090d1-c7f5-4b16-b795-d5c3cd83505c	bcdff4ec-d4bf-419e-afb1-49beea99eeaf	Israel	0.0434	2025-11-09 18:23:01.038402+01
255c212b-d8a2-4a60-a2fb-9cc141cae870	bcdff4ec-d4bf-419e-afb1-49beea99eeaf	Singapore	0.0317	2025-11-09 18:23:01.038402+01
ab384843-5dbe-407f-94b4-43a7b1331c31	bcdff4ec-d4bf-419e-afb1-49beea99eeaf	Regno Unito	0.0295	2025-11-09 18:23:01.038402+01
b24fdfc3-7d92-4e3d-b5cc-b085975c321f	bcdff4ec-d4bf-419e-afb1-49beea99eeaf	Germania	0.0216	2025-11-09 18:23:01.038402+01
ad3da42a-bf4d-4b1e-a700-a4f816a4c7b3	c743dda6-c6ba-43c2-a14e-75490a1b06b0	Italia	0.2351	2025-11-23 14:48:36.564523+01
73b6abd8-91bb-48dd-b17a-60340d59b32e	c743dda6-c6ba-43c2-a14e-75490a1b06b0	Francia	0.2249	2025-11-23 14:48:36.564523+01
3613aed6-2f37-42ca-b73f-4f12db1a51ce	c743dda6-c6ba-43c2-a14e-75490a1b06b0	Germania	0.2235	2025-11-23 14:48:36.564523+01
c0a0452b-6b4b-434f-9b2e-0a467c6c419e	c743dda6-c6ba-43c2-a14e-75490a1b06b0	Spagna	0.1630	2025-11-23 14:48:36.564523+01
add289a9-54d0-460a-ae2f-ae74ee3f2e7d	c743dda6-c6ba-43c2-a14e-75490a1b06b0	Belgio	0.0392	2025-11-23 14:48:36.564523+01
e81794b4-b173-4ebe-a589-1a306516ffa1	c743dda6-c6ba-43c2-a14e-75490a1b06b0	Olanda	0.0383	2025-11-23 14:48:36.564523+01
babc9627-51b1-4eea-8eef-9c59089d63e6	c743dda6-c6ba-43c2-a14e-75490a1b06b0	Austria	0.0332	2025-11-23 14:48:36.564523+01
a7eaf634-d1ff-41c2-96a0-a88c8f9a4ad8	c743dda6-c6ba-43c2-a14e-75490a1b06b0	Portogallo	0.0190	2025-11-23 14:48:36.564523+01
1d901aa2-8c47-4285-b9a2-524613a320e9	c743dda6-c6ba-43c2-a14e-75490a1b06b0	Finlandia	0.0139	2025-11-23 14:48:36.564523+01
dfea269b-c443-45bc-934b-847fcc80310a	c743dda6-c6ba-43c2-a14e-75490a1b06b0	Altri	0.0100	2025-11-23 14:48:36.564523+01
a9159804-b0c8-419a-9872-98ed41055d36	3a15e4de-589b-450d-93d1-a19b0c7bdb28	United States	0.7040	2025-11-08 17:38:32.297222+01
dac2d5d5-c5b0-48a6-9a53-946c564a5bb9	3a15e4de-589b-450d-93d1-a19b0c7bdb28	Japan	0.0610	2025-11-08 17:38:32.297222+01
0119e774-f83b-44fb-ba79-ba28673d016d	3a15e4de-589b-450d-93d1-a19b0c7bdb28	United Kingdom	0.0400	2025-11-08 17:38:32.297222+01
335dab32-97f9-4a71-b864-9f4169efa27a	3a15e4de-589b-450d-93d1-a19b0c7bdb28	France	0.0300	2025-11-08 17:38:32.297222+01
736dc0f8-60fc-4510-9c07-e37031f6edae	3a15e4de-589b-450d-93d1-a19b0c7bdb28	Switzerland	0.0270	2025-11-08 17:38:32.297222+01
07975d8a-5cc8-4854-9ebb-482fea29913f	3a15e4de-589b-450d-93d1-a19b0c7bdb28	Canada	0.0260	2025-11-08 17:38:32.297222+01
876989b7-1bfe-4d8e-8d44-59defec31f22	3a15e4de-589b-450d-93d1-a19b0c7bdb28	Australia	0.0230	2025-11-08 17:38:32.297222+01
9ec051c2-644c-4bb6-afbe-a783fc2a0c12	3a15e4de-589b-450d-93d1-a19b0c7bdb28	Germany	0.0220	2025-11-08 17:38:32.297222+01
1b28f028-4332-4d94-9bd5-1b6806a38ec8	3a15e4de-589b-450d-93d1-a19b0c7bdb28	Netherlands	0.0110	2025-11-08 17:38:32.297222+01
f9d173f7-abbc-4823-abba-2e587440657f	3a15e4de-589b-450d-93d1-a19b0c7bdb28	Other	0.0560	2025-11-08 17:38:32.297222+01
7de78c10-13f5-493a-8e20-5fabc2aba92b	0999dc6a-e6f9-4bbf-9bd2-30a25658de89	Francia	0.2412	2025-11-09 17:30:13.286655+01
3b502fde-096d-47cc-b770-8483856adce7	0999dc6a-e6f9-4bbf-9bd2-30a25658de89	Italia	0.2209	2025-11-09 17:30:13.286655+01
414de810-5449-43c9-85dd-e7a16184a316	0999dc6a-e6f9-4bbf-9bd2-30a25658de89	Germania	0.1897	2025-11-09 17:30:13.286655+01
bab83fc0-6e86-4e1e-853d-f9d5f915f487	0999dc6a-e6f9-4bbf-9bd2-30a25658de89	Spagna	0.1231	2025-11-09 17:30:13.286655+01
5d105298-bcbb-4e1f-973b-4db015beab99	d2c980bc-c787-4166-8e74-d074800bf867	Stati Uniti	1.0000	2025-11-09 17:16:45.576933+01
3bc78a38-60d9-4b49-8024-09d5f777d231	0999dc6a-e6f9-4bbf-9bd2-30a25658de89	Belgio	0.0692	2025-11-09 17:30:13.286655+01
35379610-b697-42b9-981e-2808c18eec14	0999dc6a-e6f9-4bbf-9bd2-30a25658de89	Austria	0.0390	2025-11-09 17:30:13.286655+01
5990cdff-40e4-440a-b75d-a052b0e92051	0999dc6a-e6f9-4bbf-9bd2-30a25658de89	Olanda	0.0363	2025-11-09 17:30:13.286655+01
a053b5db-2888-4831-a4eb-8da6bc2bfb52	0999dc6a-e6f9-4bbf-9bd2-30a25658de89	Eurozona	0.0267	2025-11-09 17:30:13.286655+01
1f940307-f782-4ecd-a118-39b086f64ba8	0999dc6a-e6f9-4bbf-9bd2-30a25658de89	Portogallo	0.0216	2025-11-09 17:30:13.286655+01
69354497-a5b5-47ae-98c1-98e285070f20	0999dc6a-e6f9-4bbf-9bd2-30a25658de89	Finlandia	0.0198	2025-11-09 17:30:13.286655+01
d9cd8e59-0161-4ecd-83bd-b5392d640c36	0999dc6a-e6f9-4bbf-9bd2-30a25658de89	Irlanda	0.0124	2025-11-09 17:30:13.286655+01
fc0a676a-625e-4d4d-a088-a83e567316e0	bf3b3448-1ec3-4f29-87e3-7fc90bc83308	Stati Uniti	0.9563	2025-11-09 17:42:38.826816+01
e0b81752-c62c-4f38-bfbb-fe04dafa0e1f	bf3b3448-1ec3-4f29-87e3-7fc90bc83308	Canada	0.0145	2025-11-09 17:42:38.826816+01
0b7c02e3-6802-464c-b1a1-b9d886a95a80	bf3b3448-1ec3-4f29-87e3-7fc90bc83308	Irlanda	0.0104	2025-11-09 17:42:38.826816+01
b39a2c0a-afaf-4edb-acd2-ff9de3cc0b99	bf3b3448-1ec3-4f29-87e3-7fc90bc83308	Olanda	0.0074	2025-11-09 17:42:38.826816+01
78846f68-4ddd-460e-bb32-f8c7dbdb3a58	bf3b3448-1ec3-4f29-87e3-7fc90bc83308	Regno Unito	0.0057	2025-11-09 17:42:38.826816+01
f710a2fc-a1cd-454d-bc71-bbc1bd4ce436	bf3b3448-1ec3-4f29-87e3-7fc90bc83308	Isole Cayman	0.0057	2025-11-09 17:42:38.826816+01
6325ea77-9b43-4392-9d23-2afcfa8858aa	fc48529f-7c1b-41f4-9975-fc576e2788bd	Cina	0.9175	2025-11-09 18:17:35.824821+01
5e6ce775-3d13-4251-a25d-62c73ba1541d	fc48529f-7c1b-41f4-9975-fc576e2788bd	Hong Kong	0.0415	2025-11-09 18:17:35.824821+01
9ee025a3-e19f-4d82-98ee-08549a4754da	fc48529f-7c1b-41f4-9975-fc576e2788bd	Altri	0.0410	2025-11-09 18:17:35.824821+01
de31a304-1a1b-4f8a-abb7-70b2b4bc2584	fda2e7d3-54a5-4b6b-a504-48873da1c697	Regno Unito	1.0000	2025-11-10 14:37:39.841516+01
\.


--
-- TOC entry 5423 (class 0 OID 102208)
-- Dependencies: 228
-- Data for Name: etf_holdings; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.etf_holdings (holding_id, asset_id, holding_symbol, holding_name, holding_percent, rank_position, updated_at) FROM stdin;
67b8517d-17b4-4ea0-9b20-c23115f8c55c	e0534574-8100-43c6-a396-f954f8ac95be	TM	Toyota Motor Corp.	0.0436	0	2025-11-09 18:20:39.635127+01
e578bd59-6306-4b35-a8de-054d93c0c0ef	e0534574-8100-43c6-a396-f954f8ac95be	MUFG	Mitsubishi UFJ Financial Group, Inc.	0.0411	0	2025-11-09 18:20:39.635127+01
10be5462-06d4-470e-97c4-9f05d5f83e9c	e0534574-8100-43c6-a396-f954f8ac95be	SONY	Sony Group Corp.	0.0406	0	2025-11-09 18:20:39.635127+01
5cd79531-5db6-4241-bfb1-79f987f99aa5	e0534574-8100-43c6-a396-f954f8ac95be	HTHIY	Hitachi Ltd.	0.0295	0	2025-11-09 18:20:39.635127+01
93e22191-081a-4ccb-b440-69a0bb096fbe	e0534574-8100-43c6-a396-f954f8ac95be	SMFG	Sumitomo Mitsui Financial Group, Inc.	0.0238	0	2025-11-09 18:20:39.635127+01
01bbcfa1-b773-4121-bb15-27d5fba19c73	e0534574-8100-43c6-a396-f954f8ac95be	NTDOY	Nintendo Co., Ltd.	0.0237	0	2025-11-09 18:20:39.635127+01
e39796bd-75d6-4ad0-b841-f99c8ff156db	e0534574-8100-43c6-a396-f954f8ac95be	SFTBY	SoftBank Group Corp.	0.0222	0	2025-11-09 18:20:39.635127+01
4001ca45-a2ef-4f47-81d2-4f2764752e93	e0534574-8100-43c6-a396-f954f8ac95be	RCRUY	Recruit Holdings Co., Ltd.	0.0193	0	2025-11-09 18:20:39.635127+01
46c15790-695c-4c39-84d6-5b360e015340	e0534574-8100-43c6-a396-f954f8ac95be	MHVYF	Mitsubishi Heavy Industries, Ltd.	0.0191	0	2025-11-09 18:20:39.635127+01
c840bfea-c297-4acb-b90b-7717af14c3a3	c117885f-43f8-4be0-8df2-f6d30a200cca	NVDA	NVIDIA Corp.	0.0542	1	2025-11-08 17:06:28.357133+01
8e9a1e7b-afa2-44b3-8501-97364c5bc0b9	c117885f-43f8-4be0-8df2-f6d30a200cca	MSFT	Microsoft	0.0456	2	2025-11-08 17:06:28.357133+01
e73b922c-98c0-44d6-b702-0a19fc1aadfd	c117885f-43f8-4be0-8df2-f6d30a200cca	AAPL	Apple	0.0442	3	2025-11-08 17:06:28.357133+01
f3d5d90d-7799-4ef4-9f50-5453e66d568e	c117885f-43f8-4be0-8df2-f6d30a200cca	AMZN	Amazon.com, Inc.	0.0279	4	2025-11-08 17:06:28.357133+01
92a10f5a-6107-4b50-9e66-436c7f3f665c	c117885f-43f8-4be0-8df2-f6d30a200cca	META	Meta Platforms	0.0205	5	2025-11-08 17:06:28.357133+01
fac831d9-b542-4a86-b8fe-904d8faba6d5	c117885f-43f8-4be0-8df2-f6d30a200cca	AVGO	Broadcom	0.0170	6	2025-11-08 17:06:28.357133+01
21212735-1314-4191-af70-feb6f4c3fa3e	c117885f-43f8-4be0-8df2-f6d30a200cca	GOOGL	Alphabet, Inc. A	0.0158	7	2025-11-08 17:06:28.357133+01
8d39a879-20a6-4603-acdb-e3dd2aacab58	c117885f-43f8-4be0-8df2-f6d30a200cca	GOOG	Alphabet, Inc. C	0.0134	8	2025-11-08 17:06:28.357133+01
7eac7fae-6dc9-4cfb-b039-b24ab32a01df	c117885f-43f8-4be0-8df2-f6d30a200cca	TSLA	Tesla	0.0123	9	2025-11-08 17:06:28.357133+01
eec87d88-d1e4-4dfb-a488-ed9318cbb8a3	c117885f-43f8-4be0-8df2-f6d30a200cca	JPM	JPMorgan Chase & Co.	0.0107	10	2025-11-08 17:06:28.357133+01
dd86ba13-e53e-4f1b-babf-8f3883ad9d2d	bcdff4ec-d4bf-419e-afb1-49beea99eeaf	PLTR	Palantir Technologies, Inc.	0.0851	0	2025-11-09 18:23:01.038402+01
37ff6b52-1353-421c-a50d-756c4b8249b7	bcdff4ec-d4bf-419e-afb1-49beea99eeaf	RTX	RTX	0.0829	0	2025-11-09 18:23:01.038402+01
5d410fa5-fbdf-41d0-8035-f0c848557c54	bcdff4ec-d4bf-419e-afb1-49beea99eeaf	LDO	Leonardo SpA	0.0761	0	2025-11-09 18:23:01.038402+01
800f6565-2841-4b67-902f-476f2ddae166	bcdff4ec-d4bf-419e-afb1-49beea99eeaf	HO	Thales SA	0.0683	0	2025-11-09 18:23:01.038402+01
066e0e57-bf57-4809-9d8b-85bbe577b745	bcdff4ec-d4bf-419e-afb1-49beea99eeaf	SAAB	SAAB	0.0637	0	2025-11-09 18:23:01.038402+01
65977016-909d-4e9c-a88f-3912e0392b84	bcdff4ec-d4bf-419e-afb1-49beea99eeaf	LDOS	Leidos Holdings	0.0629	0	2025-11-09 18:23:01.038402+01
7a9a736c-29c8-4099-84d1-154135adfa70	bcdff4ec-d4bf-419e-afb1-49beea99eeaf	012450	HANWHA AEROSPACE Co., Ltd.	0.0624	0	2025-11-09 18:23:01.038402+01
eb7ca02d-aca4-4736-82b3-bbab28bf6b8d	bcdff4ec-d4bf-419e-afb1-49beea99eeaf	CW	Curtiss-Wright	0.0499	0	2025-11-09 18:23:01.038402+01
48bd05c2-159c-4154-b707-ae62d2c40720	e0534574-8100-43c6-a396-f954f8ac95be	TKOMY	Tokio Marine Holdings, Inc.	0.0189	0	2025-11-09 18:20:39.635127+01
9669103a-32ed-4ca4-b63d-b5bae767bf5b	b46bba4b-525d-483d-bf4e-f195bde3d6bc	NVDA	NVIDIA Corp.	0.0774	1	2025-11-08 17:19:32.530707+01
0d2d8bce-c829-4587-b98a-8e11c082a4f8	b46bba4b-525d-483d-bf4e-f195bde3d6bc	MSFT	Microsoft	0.0686	2	2025-11-08 17:19:32.530707+01
af1bd5ca-5184-4d2a-a944-9ecd116887a6	b46bba4b-525d-483d-bf4e-f195bde3d6bc	AAPL	Apple	0.0632	3	2025-11-08 17:19:32.530707+01
e7ec5bef-fdc0-458d-9325-d2de81f27f81	b46bba4b-525d-483d-bf4e-f195bde3d6bc	AMZN	Amazon.com, Inc.	0.0394	4	2025-11-08 17:19:32.530707+01
8578c324-4365-49b1-8ca8-7a735e0d3011	b46bba4b-525d-483d-bf4e-f195bde3d6bc	META	Meta Platforms	0.0292	5	2025-11-08 17:19:32.530707+01
713e1127-d784-432a-a641-9fe1d7d92a1a	b46bba4b-525d-483d-bf4e-f195bde3d6bc	AVGO	Broadcom	0.0255	6	2025-11-08 17:19:32.530707+01
3a25f087-b167-4dd6-8134-be68569d576b	b46bba4b-525d-483d-bf4e-f195bde3d6bc	GOOGL	Alphabet, Inc. A	0.0226	7	2025-11-08 17:19:32.530707+01
6c62bbeb-8dc0-480c-9d11-73a8be48f213	b46bba4b-525d-483d-bf4e-f195bde3d6bc	GOOG	Alphabet, Inc. C	0.0183	8	2025-11-08 17:19:32.530707+01
22c3076e-d132-489f-ac06-b58985a3e17d	b46bba4b-525d-483d-bf4e-f195bde3d6bc	TSLA	Tesla	0.0170	9	2025-11-08 17:19:32.530707+01
e73bd100-4f60-4ab7-8618-d6ba38f2e959	b46bba4b-525d-483d-bf4e-f195bde3d6bc	BRK.B	Berkshire Hathaway, Inc.	0.0168	10	2025-11-08 17:19:32.530707+01
c0418ff1-2f7a-447a-b098-cb7890b2a787	f1daeb66-3038-40d7-beea-ba11dd317ae9	ASML	ASML Holding NV	0.0659	1	2025-11-08 17:20:11.535478+01
166a4ead-0b9d-4bfc-b406-59e29df31beb	f1daeb66-3038-40d7-beea-ba11dd317ae9	SAP	SAP SE	0.0623	2	2025-11-08 17:20:11.535478+01
f4ad6aee-cc61-48a2-b368-3a768b9ebdb2	f1daeb66-3038-40d7-beea-ba11dd317ae9	SIE	Siemens AG	0.0467	3	2025-11-08 17:20:11.535478+01
3382c5eb-63c1-47c8-b159-45c951d6e672	f1daeb66-3038-40d7-beea-ba11dd317ae9	ALV	Allianz SE	0.0366	4	2025-11-08 17:20:11.535478+01
294cdfe6-bdd9-45f5-8ed9-7c359ea2e277	f1daeb66-3038-40d7-beea-ba11dd317ae9	MC	LVMH Moët Hennessy Louis Vuitton SE	0.0338	5	2025-11-08 17:20:11.535478+01
82fb5afe-8080-4fec-802c-fa14f8b06657	f1daeb66-3038-40d7-beea-ba11dd317ae9	SAN	Banco Santander SA	0.0325	6	2025-11-08 17:20:11.535478+01
1fdee48f-5577-49e5-8884-ba99a336ae61	f1daeb66-3038-40d7-beea-ba11dd317ae9	TTE	TotalEnergies SE	0.0319	7	2025-11-08 17:20:11.535478+01
0083e80f-6b5e-4759-9d9d-71bd39b6e290	f1daeb66-3038-40d7-beea-ba11dd317ae9	SU	Schneider Electric SE	0.0318	8	2025-11-08 17:20:11.535478+01
06cf4eb1-ee2f-40e2-a426-1079b29c6d0d	f1daeb66-3038-40d7-beea-ba11dd317ae9	DTE	Deutsche Telekom AG	0.0295	9	2025-11-08 17:20:11.535478+01
ac9a66f2-5866-4d56-a419-4507022edf33	f1daeb66-3038-40d7-beea-ba11dd317ae9	SAF	Safran SA	0.0280	10	2025-11-08 17:20:11.535478+01
837ac2dc-7014-46ac-804c-db3e66e8e432	719121c9-908d-49b7-a047-23464f0960ab	ASML	ASML Holding NV	0.0217	1	2025-11-08 17:24:51.177479+01
4cbffc5d-8719-4926-ae24-9502128f5d63	719121c9-908d-49b7-a047-23464f0960ab	SAP	SAP SE	0.0203	2	2025-11-08 17:24:51.177479+01
d76544ba-6a75-478b-9c75-82ba857fcff9	719121c9-908d-49b7-a047-23464f0960ab	AZN	AstraZeneca PLC	0.0183	3	2025-11-08 17:24:51.177479+01
1e4ec36e-be86-4821-a222-b04c771a6ab3	719121c9-908d-49b7-a047-23464f0960ab	NOVN	Novartis AG	0.0180	4	2025-11-08 17:24:51.177479+01
dcd91885-2b50-40a3-a414-2886efaa9020	719121c9-908d-49b7-a047-23464f0960ab	NESN	Nestlé SA	0.0176	5	2025-11-08 17:24:51.177479+01
aa1caedd-d47d-4c5a-abde-44e1b3890532	719121c9-908d-49b7-a047-23464f0960ab	HSBA	HSBC Holdings Plc	0.0167	6	2025-11-08 17:24:51.177479+01
2ff81ac8-be43-4b2a-a67f-c93287606f2c	719121c9-908d-49b7-a047-23464f0960ab	ROG	Roche Holding AG	0.0167	7	2025-11-08 17:24:51.177479+01
a65e46a8-3226-4625-a1b7-c84a7749f24e	719121c9-908d-49b7-a047-23464f0960ab	SHEL	Shell Plc	0.0158	8	2025-11-08 17:24:51.177479+01
4ff86b97-8695-43ec-b495-a6637510467b	719121c9-908d-49b7-a047-23464f0960ab	SIE	Siemens AG	0.0152	9	2025-11-08 17:24:51.177479+01
1495e0f8-f8c6-432f-9d4f-9833bf2dd881	719121c9-908d-49b7-a047-23464f0960ab	NOVO B	Novo Nordisk A/S	0.0133	10	2025-11-08 17:24:51.177479+01
282a73ba-a4b1-4341-af6c-7e2ba4efe31b	8f706b9d-54ae-4ac7-8ce5-0ed005362d68	NVDA	NVIDIA Corp.	0.0686	1	2025-11-08 17:31:02.260804+01
3654c0e1-8703-4df6-9c01-18231d37bb43	8f706b9d-54ae-4ac7-8ce5-0ed005362d68	BKNG	Booking Holdings, Inc.	0.0270	2	2025-11-08 17:31:02.260804+01
1381c175-c554-436d-98ef-fce4798bf080	8f706b9d-54ae-4ac7-8ce5-0ed005362d68	CSCO	Cisco Systems, Inc.	0.0270	3	2025-11-08 17:31:02.260804+01
a96cb522-bde8-4f88-a987-cf2ff580cda8	8f706b9d-54ae-4ac7-8ce5-0ed005362d68	HD	Home Depot	0.0230	4	2025-11-08 17:31:02.260804+01
59a77760-b9a0-4288-96d8-c7282c0f982e	8f706b9d-54ae-4ac7-8ce5-0ed005362d68	AVGO	Broadcom	0.0226	5	2025-11-08 17:31:02.260804+01
fd20fd0b-24ca-42ff-ae5a-f21aabce920f	8f706b9d-54ae-4ac7-8ce5-0ed005362d68	V	Visa	0.0209	6	2025-11-08 17:31:02.260804+01
16a82204-38b9-4d96-acc5-cb3a5058d042	8f706b9d-54ae-4ac7-8ce5-0ed005362d68	GILD	Gilead Sciences, Inc.	0.0189	7	2025-11-08 17:31:02.260804+01
5fa4e14d-33aa-4ef0-9605-dd5c184cbb0e	8f706b9d-54ae-4ac7-8ce5-0ed005362d68	AEM	Agnico Eagle Mines Ltd.	0.0183	8	2025-11-08 17:31:02.260804+01
cd7ebdff-6d54-409b-b5dd-fe9f3eddbc62	8f706b9d-54ae-4ac7-8ce5-0ed005362d68	BK	The Bank of New York Mellon Corp.	0.0172	9	2025-11-08 17:31:02.260804+01
771a53d8-64ca-46e3-a70c-b853b07d5c68	8f706b9d-54ae-4ac7-8ce5-0ed005362d68	TT	Trane Technologies	0.0158	10	2025-11-08 17:31:02.260804+01
870f9b98-bced-49cf-a4f7-5cd2771f5131	bcdff4ec-d4bf-419e-afb1-49beea99eeaf	ESLT	Elbit Systems	0.0434	0	2025-11-09 18:23:01.038402+01
1f7c4fbf-8204-4665-8431-bfa850a47361	bcdff4ec-d4bf-419e-afb1-49beea99eeaf	BAH	Booz Allen Hamilton Hldg	0.0360	0	2025-11-09 18:23:01.038402+01
dbce8618-61a7-4d09-bdc9-1c8ae8be3c78	fda2e7d3-54a5-4b6b-a504-48873da1c697	BRSL	Brightstar Lottery	1.0000	0	2025-11-10 14:37:39.841516+01
d928f4d3-0cc6-4580-b0a5-00375a5aada7	bf3b3448-1ec3-4f29-87e3-7fc90bc83308	NFLX	NETFLIX INC USD	0.0236	0	2025-11-09 17:42:38.826816+01
88d5585c-b52f-4c64-900d-000cd1e2d3dd	bf3b3448-1ec3-4f29-87e3-7fc90bc83308	NVDA	NVIDIA Corp.	0.1031	0	2025-11-09 17:42:38.826816+01
2f4a424a-6232-446f-9e0e-b84083cccfe4	bf3b3448-1ec3-4f29-87e3-7fc90bc83308	AAPL	Apple	0.0842	0	2025-11-09 17:42:38.826816+01
f67cd06a-b365-442c-bbda-6d1ccfc54d5b	bf3b3448-1ec3-4f29-87e3-7fc90bc83308	AMZN	Amazon.com, Inc.	0.0497	0	2025-11-09 17:42:38.826816+01
aaefb58d-1608-4246-9b28-5f879e2af3df	bf3b3448-1ec3-4f29-87e3-7fc90bc83308	AVGO	Broadcom	0.0612	0	2025-11-09 17:42:38.826816+01
7ab83bd4-bb91-46a5-9cd5-9567f0bb00da	bf3b3448-1ec3-4f29-87e3-7fc90bc83308	GOOG	Alphabet, Inc. C	0.0320	0	2025-11-09 17:42:38.826816+01
f58d3027-97eb-4359-ac3d-1a7b85c24aa7	bf3b3448-1ec3-4f29-87e3-7fc90bc83308	GOOGL	Alphabet, Inc. A	0.0342	0	2025-11-09 17:42:38.826816+01
ba1a2ebd-b13d-4781-b62a-fafe81bbeaa2	bf3b3448-1ec3-4f29-87e3-7fc90bc83308	MSFT	Microsoft	0.0817	0	2025-11-09 17:42:38.826816+01
a693f989-0622-495f-817d-b70271a6cf60	bf3b3448-1ec3-4f29-87e3-7fc90bc83308	TSLA	Tesla	0.0335	0	2025-11-09 17:42:38.826816+01
2ca4c75e-b24b-40cc-aa3f-39a56b5cbb3e	bf3b3448-1ec3-4f29-87e3-7fc90bc83308	META	META PLATFORMS INC-CLASS A	0.0302	0	2025-11-09 17:42:38.826816+01
84afd133-f219-4280-9800-7396e5661d2b	fc48529f-7c1b-41f4-9975-fc576e2788bd	TCEHY	Tencent Holdings Ltd.	0.1776	0	2025-11-09 18:17:35.824821+01
2814601f-5937-4aaa-b61d-792999a842de	fc48529f-7c1b-41f4-9975-fc576e2788bd	BABA	Alibaba Group Holding Ltd.	0.0922	0	2025-11-09 18:17:35.824821+01
6787789e-bc6f-414f-a12b-37edec9eec8f	fc48529f-7c1b-41f4-9975-fc576e2788bd	XIACY	Xiaomi Corp.	0.0421	0	2025-11-09 18:17:35.824821+01
77d5029b-4dda-41d3-9b30-3aff906a67aa	fc48529f-7c1b-41f4-9975-fc576e2788bd	CICHY	China Construction Bank Corp.	0.0335	0	2025-11-09 18:17:35.824821+01
8aac64fc-ac6d-44a7-9821-e9c3cc64d0e6	fc48529f-7c1b-41f4-9975-fc576e2788bd	PDD	PDD Holdings	0.0309	0	2025-11-09 18:17:35.824821+01
ecfc1563-814d-4764-9f2a-9b50ff1f73aa	fc48529f-7c1b-41f4-9975-fc576e2788bd	MPNGY	Meituan	0.0237	0	2025-11-09 18:17:35.824821+01
17bc3436-a81e-499c-a966-8dab2c81a453	fc48529f-7c1b-41f4-9975-fc576e2788bd	BYDDY	BYD Co., Ltd.	0.0196	0	2025-11-09 18:17:35.824821+01
e2dcdb13-c374-4941-9285-8df27893f032	fc48529f-7c1b-41f4-9975-fc576e2788bd	PNGAY	Ping An Insurance (Group) Co. of China Ltd.	0.0175	0	2025-11-09 18:17:35.824821+01
dc5a5fc5-868d-48af-81f1-d044fb2a92b1	fc48529f-7c1b-41f4-9975-fc576e2788bd	IDCBY	Industrial & Commercial Bank of China Ltd.	0.0174	0	2025-11-09 18:17:35.824821+01
fb9700af-ce1e-4f3d-ad81-2e8487d0426a	fc48529f-7c1b-41f4-9975-fc576e2788bd	NTES	NetEase, Inc.	0.0172	0	2025-11-09 18:17:35.824821+01
\.


--
-- TOC entry 5424 (class 0 OID 102223)
-- Dependencies: 229
-- Data for Name: etf_sector_weights; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.etf_sector_weights (sector_weight_id, asset_id, sector_name, weight_percent, updated_at) FROM stdin;
0023774c-aaf5-45b8-8e2a-9e82b7cfd124	e0534574-8100-43c6-a396-f954f8ac95be	Industria	0.2375	2025-11-09 18:20:39.635127+01
a8179a65-c687-45aa-aaf7-4782fb3aa0b8	e0534574-8100-43c6-a396-f954f8ac95be	Beni voluttuari	0.1813	2025-11-09 18:20:39.635127+01
00fa9a9c-81b7-433f-a421-129d9d51d4f9	e0534574-8100-43c6-a396-f954f8ac95be	Finanza	0.1706	2025-11-09 18:20:39.635127+01
45647b68-c586-4294-9979-9b14056ef7af	e0534574-8100-43c6-a396-f954f8ac95be	Informatica	0.1246	2025-11-09 18:20:39.635127+01
23cbc4b7-613b-4485-8d7f-28c93cfd5621	e0534574-8100-43c6-a396-f954f8ac95be	Telecomunicazioni	0.0896	2025-11-09 18:20:39.635127+01
bc53b16d-2843-440a-a9f7-62be88906c78	e0534574-8100-43c6-a396-f954f8ac95be	Salute	0.0675	2025-11-09 18:20:39.635127+01
6f184338-1566-487f-8aab-1a7492565c83	e0534574-8100-43c6-a396-f954f8ac95be	Beni di prima necessità	0.0515	2025-11-09 18:20:39.635127+01
710b762f-f4c7-4ad8-8393-a54e5a24d1c8	e0534574-8100-43c6-a396-f954f8ac95be	Materie prime	0.0335	2025-11-09 18:20:39.635127+01
0d582fc3-c372-422d-8b90-68d9cc18ccbc	e0534574-8100-43c6-a396-f954f8ac95be	Immobiliare	0.0241	2025-11-09 18:20:39.635127+01
3cf99338-94a2-4a0c-870b-0afafd5649a6	e0534574-8100-43c6-a396-f954f8ac95be	Servizi di pubblica utilità	0.0107	2025-11-09 18:20:39.635127+01
30e95c75-cdc5-410e-8a57-7c75d46fd13f	e0534574-8100-43c6-a396-f954f8ac95be	Energia	0.0084	2025-11-09 18:20:39.635127+01
044119c2-deec-43d3-bd6c-7260a346f706	e0534574-8100-43c6-a396-f954f8ac95be	Altri	0.0008	2025-11-09 18:20:39.635127+01
5366f4a7-3ca0-4782-9f6c-1118f898bc19	c117885f-43f8-4be0-8df2-f6d30a200cca	Informatica	0.2793	2025-11-08 17:06:28.357133+01
4bda6c27-1be5-4dff-a4c1-a46da0940081	c117885f-43f8-4be0-8df2-f6d30a200cca	Finanza	0.1470	2025-11-08 17:06:28.357133+01
1623d2e0-fd74-43c8-a9c5-1bff34716e8e	c117885f-43f8-4be0-8df2-f6d30a200cca	Beni voluttuari	0.1040	2025-11-08 17:06:28.357133+01
af6e1c20-0ef5-49f8-b083-c2f632f76272	c117885f-43f8-4be0-8df2-f6d30a200cca	Industria	0.1029	2025-11-08 17:06:28.357133+01
ed296e49-1b01-4284-ab5a-9f6a33f27c7a	c117885f-43f8-4be0-8df2-f6d30a200cca	Salute	0.0869	2025-11-08 17:06:28.357133+01
d991615b-b2b3-451d-92fb-ee8f6e24a3c1	bcdff4ec-d4bf-419e-afb1-49beea99eeaf	Industria	0.7910	2025-11-09 18:23:01.038402+01
8a660f2e-da1e-43bc-bee7-e2da7b5fe977	bcdff4ec-d4bf-419e-afb1-49beea99eeaf	Altri	0.1160	2025-11-09 18:23:01.038402+01
bd0faf21-147c-4eb6-adf4-c7cd275b8cde	bcdff4ec-d4bf-419e-afb1-49beea99eeaf	Informatica	0.0930	2025-11-09 18:23:01.038402+01
42677eed-21c6-4a4b-8494-452c84649696	c743dda6-c6ba-43c2-a14e-75490a1b06b0	Obbligazionario Governativo	1.0000	2025-11-23 14:48:36.564523+01
8ae83218-ad41-4700-89af-d715e19c7ccf	c117885f-43f8-4be0-8df2-f6d30a200cca	Telecomunicazioni	0.0842	2025-11-08 17:06:28.357133+01
c9bb06ba-3cca-49c4-8d6e-115da8fd0772	c117885f-43f8-4be0-8df2-f6d30a200cca	Beni di prima necessità	0.0554	2025-11-08 17:06:28.357133+01
8c04bee5-bc74-4c39-9c38-425963139d34	c117885f-43f8-4be0-8df2-f6d30a200cca	Energia	0.0353	2025-11-08 17:06:28.357133+01
30278080-0390-49ea-b6f6-ad5efa382918	c117885f-43f8-4be0-8df2-f6d30a200cca	Materie prime	0.0274	2025-11-08 17:06:28.357133+01
43a2d932-f4ea-4f93-91b4-34da201ce1aa	c117885f-43f8-4be0-8df2-f6d30a200cca	Servizi di pubblica utilità	0.0255	2025-11-08 17:06:28.357133+01
02a5b32b-b045-4e12-88f6-c2ad23f46d2a	c117885f-43f8-4be0-8df2-f6d30a200cca	Immobiliare	0.0190	2025-11-08 17:06:28.357133+01
49d5de80-ceb7-4d46-8ae9-ba81c35f7141	c117885f-43f8-4be0-8df2-f6d30a200cca	Altri	0.0332	2025-11-08 17:06:28.357133+01
a7b231f0-e265-4f2f-92af-f5147b2b9874	b46bba4b-525d-483d-bf4e-f195bde3d6bc	Informatica	0.3567	2025-11-08 17:19:32.530707+01
5a5e2319-d9de-4415-80c1-23e4ab626799	b46bba4b-525d-483d-bf4e-f195bde3d6bc	Finanza	0.1114	2025-11-08 17:19:32.530707+01
d332aec3-a77a-45c1-b28c-3376a677da30	b46bba4b-525d-483d-bf4e-f195bde3d6bc	Beni voluttuari	0.1065	2025-11-08 17:19:32.530707+01
ad406cb1-9a28-476c-8b26-bd165bdcd46c	b46bba4b-525d-483d-bf4e-f195bde3d6bc	Telecomunicazioni	0.0992	2025-11-08 17:19:32.530707+01
13f5f2c7-6526-4b06-879f-994ba69e5f9f	b46bba4b-525d-483d-bf4e-f195bde3d6bc	Salute	0.0891	2025-11-08 17:19:32.530707+01
f6ca7ede-e0cc-4508-b310-1d3b506f280a	b46bba4b-525d-483d-bf4e-f195bde3d6bc	Industria	0.0772	2025-11-08 17:19:32.530707+01
5b4611a9-616d-4750-a6e6-aa73ef97aa74	b46bba4b-525d-483d-bf4e-f195bde3d6bc	Beni di prima necessità	0.0493	2025-11-08 17:19:32.530707+01
711033cc-60a1-43db-8825-72b30835a976	b46bba4b-525d-483d-bf4e-f195bde3d6bc	Energia	0.0302	2025-11-08 17:19:32.530707+01
ed81f5b8-6f21-4345-a98f-8f6bc76068c3	b46bba4b-525d-483d-bf4e-f195bde3d6bc	Servizi di pubblica utilità	0.0235	2025-11-08 17:19:32.530707+01
0c2776a8-8ed3-43a6-93c7-b0cdfebb426f	b46bba4b-525d-483d-bf4e-f195bde3d6bc	Immobiliare	0.0192	2025-11-08 17:19:32.530707+01
33095e2b-9a2c-44b7-92e2-69723c35a068	b46bba4b-525d-483d-bf4e-f195bde3d6bc	Materie prime	0.0144	2025-11-08 17:19:32.530707+01
f2bfdf81-2d4d-491f-8b2a-5b076d2680cd	b46bba4b-525d-483d-bf4e-f195bde3d6bc	Altri	0.0233	2025-11-08 17:19:32.530707+01
aea3f8f2-5114-486a-ad02-ce8f23cde5c6	f1daeb66-3038-40d7-beea-ba11dd317ae9	Finanza	0.2407	2025-11-08 17:20:11.535478+01
3f1f958c-5e86-4654-b5d9-9fe0d347f4b2	f1daeb66-3038-40d7-beea-ba11dd317ae9	Industria	0.2006	2025-11-08 17:20:11.535478+01
aaa194fc-65f8-44a3-b2c1-fafa9c82f16d	f1daeb66-3038-40d7-beea-ba11dd317ae9	Informatica	0.1563	2025-11-08 17:20:11.535478+01
ae66a743-1198-4ea5-9f85-3192a300e63f	f1daeb66-3038-40d7-beea-ba11dd317ae9	Beni voluttuari	0.1520	2025-11-08 17:20:11.535478+01
5b271a23-23a4-4af5-b60a-2383af0b187a	f1daeb66-3038-40d7-beea-ba11dd317ae9	Beni di prima necessità	0.0649	2025-11-08 17:20:11.535478+01
9a067b57-b35c-4dc1-aed4-162d638953c9	f1daeb66-3038-40d7-beea-ba11dd317ae9	Servizi di pubblica utilità	0.0410	2025-11-08 17:20:11.535478+01
3ab3c786-4426-4be8-a75f-6c1516704411	f1daeb66-3038-40d7-beea-ba11dd317ae9	Energia	0.0405	2025-11-08 17:20:11.535478+01
af413e10-01b6-4bf6-8e3a-5d9357453fda	f1daeb66-3038-40d7-beea-ba11dd317ae9	Materie prime	0.0374	2025-11-08 17:20:11.535478+01
8615bc05-400d-48a2-8937-604c979e761a	f1daeb66-3038-40d7-beea-ba11dd317ae9	Salute	0.0325	2025-11-08 17:20:11.535478+01
12440973-54f3-4d22-a528-2532b6c19d62	f1daeb66-3038-40d7-beea-ba11dd317ae9	Telecomunicazioni	0.0295	2025-11-08 17:20:11.535478+01
aa1cb003-a869-4b43-85ea-7f5ee3df0a90	f1daeb66-3038-40d7-beea-ba11dd317ae9	Altri	0.0046	2025-11-08 17:20:11.535478+01
20281223-c148-4214-ba77-877938baecc8	719121c9-908d-49b7-a047-23464f0960ab	Finanza	0.2337	2025-11-08 17:24:51.177479+01
3e6809a5-6f3f-4723-83cc-c1289b7dd87c	719121c9-908d-49b7-a047-23464f0960ab	Industria	0.1840	2025-11-08 17:24:51.177479+01
2c991d82-3a39-478b-a739-6e3eb487dbba	719121c9-908d-49b7-a047-23464f0960ab	Salute	0.1020	2025-11-08 17:24:51.177479+01
57a8d312-9afe-401b-b68f-492a7d2dc2ab	719121c9-908d-49b7-a047-23464f0960ab	Beni di prima necessità	0.0900	2025-11-08 17:24:51.177479+01
dcd1cc4a-360c-48b8-a3b9-a2a9d7d549eb	719121c9-908d-49b7-a047-23464f0960ab	Beni voluttuari	0.0843	2025-11-08 17:24:51.177479+01
96dbe2aa-79ee-4aa0-8e79-c7c2da6e09fa	719121c9-908d-49b7-a047-23464f0960ab	Informatica	0.0731	2025-11-08 17:24:51.177479+01
df6abff1-aea2-441b-aaf2-5920da7207bd	719121c9-908d-49b7-a047-23464f0960ab	Energia	0.0449	2025-11-08 17:24:51.177479+01
af2bc59e-0c5d-4576-a26a-92b8d6463e33	719121c9-908d-49b7-a047-23464f0960ab	Servizi di pubblica utilità	0.0405	2025-11-08 17:24:51.177479+01
c1801205-7ded-4eab-a5d1-cd70c5fce74b	719121c9-908d-49b7-a047-23464f0960ab	Materie prime	0.0405	2025-11-08 17:24:51.177479+01
8e5013f8-7156-4de8-95b4-cb917f461fb7	719121c9-908d-49b7-a047-23464f0960ab	Telecomunicazioni	0.0338	2025-11-08 17:24:51.177479+01
6054a32b-397c-4653-8e93-b8bbd84cbbd5	719121c9-908d-49b7-a047-23464f0960ab	Immobiliare	0.0122	2025-11-08 17:24:51.177479+01
69f63c6d-9abe-4e87-b97a-68fff27d4b1b	719121c9-908d-49b7-a047-23464f0960ab	Altri	0.0610	2025-11-08 17:24:51.177479+01
f30ef26c-5643-48fc-89ea-a0a209e81a0f	8f706b9d-54ae-4ac7-8ce5-0ed005362d68	Informatica	0.3256	2025-11-08 17:31:02.260804+01
01da9c19-034e-43bc-a96d-476a6ba2022c	8f706b9d-54ae-4ac7-8ce5-0ed005362d68	Finanza	0.1866	2025-11-08 17:31:02.260804+01
e7499661-1250-49fd-aa85-a5df655fc3c6	8f706b9d-54ae-4ac7-8ce5-0ed005362d68	Industria	0.1305	2025-11-08 17:31:02.260804+01
a7a2c195-fc3c-4240-b80d-e80f3ee912da	8f706b9d-54ae-4ac7-8ce5-0ed005362d68	Beni voluttuari	0.1265	2025-11-08 17:31:02.260804+01
37ef52a5-0e80-4d62-8af0-ad811102ee7b	8f706b9d-54ae-4ac7-8ce5-0ed005362d68	Salute	0.0722	2025-11-08 17:31:02.260804+01
479fa0b6-b1a3-4a61-b3e8-5336462b78ec	8f706b9d-54ae-4ac7-8ce5-0ed005362d68	Telecomunicazioni	0.0630	2025-11-08 17:31:02.260804+01
c078d4de-d882-4622-bba0-b38e5ed306b4	8f706b9d-54ae-4ac7-8ce5-0ed005362d68	Materie prime	0.0408	2025-11-08 17:31:02.260804+01
53a1e337-f745-424d-b532-c791cb59fb2d	8f706b9d-54ae-4ac7-8ce5-0ed005362d68	Beni di prima necessità	0.0184	2025-11-08 17:31:02.260804+01
7573bde4-3f2a-4143-a41d-aec6e0a588f1	8f706b9d-54ae-4ac7-8ce5-0ed005362d68	Servizi di pubblica utilità	0.0017	2025-11-08 17:31:02.260804+01
e7ac1358-877a-45b2-9c5c-ba6590e20a98	8f706b9d-54ae-4ac7-8ce5-0ed005362d68	Immobiliare	0.0007	2025-11-08 17:31:02.260804+01
09fc85d5-5a68-4fde-9991-63e1ae997e2f	8f706b9d-54ae-4ac7-8ce5-0ed005362d68	Altri	0.0340	2025-11-08 17:31:02.260804+01
e775be6d-e6a8-4631-8df0-bc67190d9895	3a15e4de-589b-450d-93d1-a19b0c7bdb28	Information Technology	0.3260	2025-11-08 17:38:32.297222+01
c101124c-ef57-4bd1-9345-450bee99c6ec	3a15e4de-589b-450d-93d1-a19b0c7bdb28	Financials	0.1330	2025-11-08 17:38:32.297222+01
cfcae0db-01c1-4afe-8cca-43d59283550e	3a15e4de-589b-450d-93d1-a19b0c7bdb28	Health Care	0.1250	2025-11-08 17:38:32.297222+01
aae21862-4b3e-44ef-9515-062e54897542	3a15e4de-589b-450d-93d1-a19b0c7bdb28	Consumer Discretionary	0.1050	2025-11-08 17:38:32.297222+01
407e28b1-cb18-4714-beb2-39dc1721c518	3a15e4de-589b-450d-93d1-a19b0c7bdb28	Communication Services	0.0860	2025-11-08 17:38:32.297222+01
fa0bfa4d-22ce-475a-be3e-b266c7ea3ae5	3a15e4de-589b-450d-93d1-a19b0c7bdb28	Industrials	0.0800	2025-11-08 17:38:32.297222+01
f0ed27d9-dfbc-424b-a14f-d1b17be20103	3a15e4de-589b-450d-93d1-a19b0c7bdb28	Energy	0.0410	2025-11-08 17:38:32.297222+01
8d265835-61ae-43ad-a9fe-ba6da8fda2d3	3a15e4de-589b-450d-93d1-a19b0c7bdb28	Consumer Staples	0.0370	2025-11-08 17:38:32.297222+01
b505448b-f024-4970-a611-5b95a8bf0d7d	3a15e4de-589b-450d-93d1-a19b0c7bdb28	Materials	0.0360	2025-11-08 17:38:32.297222+01
800c8e97-5820-47d4-bb77-91c4eb0c2e6a	3a15e4de-589b-450d-93d1-a19b0c7bdb28	Utilities	0.0240	2025-11-08 17:38:32.297222+01
5782ad3a-54e3-4dd4-bfaf-895ca5acc62d	3a15e4de-589b-450d-93d1-a19b0c7bdb28	Real Estate	0.0230	2025-11-08 17:38:32.297222+01
6af83fcf-a682-4b0c-87b7-ac0f6595d2bd	fda2e7d3-54a5-4b6b-a504-48873da1c697	Gaming and Lottery	0.0000	2025-11-10 14:37:39.841516+01
28df65ac-1604-438a-9083-c288c2620f8e	d2c980bc-c787-4166-8e74-d074800bf867	Obbligazioni Governative	0.9980	2025-11-09 17:16:45.576933+01
2c56d827-c4fa-42b5-9b59-07a74eb5e016	d2c980bc-c787-4166-8e74-d074800bf867	Cash	0.0030	2025-11-09 17:16:45.576933+01
86fba4e3-c3a7-4188-9c25-bed161db5a07	0999dc6a-e6f9-4bbf-9bd2-30a25658de89	Obbligazionario Governativo	1.0000	2025-11-09 17:30:13.286655+01
452a61f7-2dce-47e5-81a9-fa1f8cfebe9a	bf3b3448-1ec3-4f29-87e3-7fc90bc83308	Nuove tecnologie	0.5643	2025-11-09 17:42:38.826816+01
fc248d93-b012-424a-a25c-0facfdf3e29b	bf3b3448-1ec3-4f29-87e3-7fc90bc83308	Telecomunicazioni	0.1481	2025-11-09 17:42:38.826816+01
560a56f4-08f3-421f-9828-11a5782e2044	bf3b3448-1ec3-4f29-87e3-7fc90bc83308	Beni ciclici	0.1269	2025-11-09 17:42:38.826816+01
a49529db-2b3e-4ea0-8d80-2e7751fcfb5e	bf3b3448-1ec3-4f29-87e3-7fc90bc83308	Farmaceutico	0.0438	2025-11-09 17:42:38.826816+01
fc647893-b7fa-4fc8-b8c4-a9b50721710e	bf3b3448-1ec3-4f29-87e3-7fc90bc83308	Industriale	0.0382	2025-11-09 17:42:38.826816+01
a41dbd88-9c34-491d-8c54-fe8873a385ca	bf3b3448-1ec3-4f29-87e3-7fc90bc83308	Servizi	0.0144	2025-11-09 17:42:38.826816+01
72290925-6c6a-4790-bab1-83eda72262bd	bf3b3448-1ec3-4f29-87e3-7fc90bc83308	Materiali	0.0108	2025-11-09 17:42:38.826816+01
c5057aca-d73f-406e-a19f-7523305ea443	bf3b3448-1ec3-4f29-87e3-7fc90bc83308	Energia	0.0046	2025-11-09 17:42:38.826816+01
70b375f4-085c-4269-a050-7f04b38241e7	bf3b3448-1ec3-4f29-87e3-7fc90bc83308	Finanziari	0.0033	2025-11-09 17:42:38.826816+01
98d7d4e2-cef7-46eb-ba10-b2aff7ac2bfc	bf3b3448-1ec3-4f29-87e3-7fc90bc83308	Immobiliare	0.0015	2025-11-09 17:42:38.826816+01
1078b288-005c-43ab-b792-d20c3e27dcd0	fc48529f-7c1b-41f4-9975-fc576e2788bd	Beni voluttuari	0.2689	2025-11-09 18:17:35.824821+01
7418863b-6f2f-4201-ab21-f3d8784ad32a	fc48529f-7c1b-41f4-9975-fc576e2788bd	Telecomunicazioni	0.2275	2025-11-09 18:17:35.824821+01
3f8c0826-076a-44e2-817a-3bb208655589	fc48529f-7c1b-41f4-9975-fc576e2788bd	Finanza	0.1743	2025-11-09 18:17:35.824821+01
800d5ce1-8012-4b33-91f4-0058179f82db	fc48529f-7c1b-41f4-9975-fc576e2788bd	Informatica	0.0866	2025-11-09 18:17:35.824821+01
56b3dae2-bbbe-4af5-99a5-4044ac18753f	fc48529f-7c1b-41f4-9975-fc576e2788bd	Salute	0.0424	2025-11-09 18:17:35.824821+01
9806921e-4eb9-49e7-a19b-b9f2de0f661f	fc48529f-7c1b-41f4-9975-fc576e2788bd	Industria	0.0388	2025-11-09 18:17:35.824821+01
5a679558-34ff-4e54-a1d9-aaea467455a8	fc48529f-7c1b-41f4-9975-fc576e2788bd	Altri	0.0384	2025-11-09 18:17:35.824821+01
5cee2065-2624-4009-bd16-b592cfcfee17	fc48529f-7c1b-41f4-9975-fc576e2788bd	Materie prime	0.0334	2025-11-09 18:17:35.824821+01
6bda590e-951c-49f2-b56f-6d0250ac8478	fc48529f-7c1b-41f4-9975-fc576e2788bd	Beni di prima necessità	0.0304	2025-11-09 18:17:35.824821+01
47c68997-00fa-42a9-bdd3-879d6fa35106	fc48529f-7c1b-41f4-9975-fc576e2788bd	Energia	0.0245	2025-11-09 18:17:35.824821+01
bf83fe98-edb8-4ac5-8ff6-c2ca65399897	fc48529f-7c1b-41f4-9975-fc576e2788bd	Servizi di pubblica utilità	0.0183	2025-11-09 18:17:35.824821+01
2c68632c-ff84-4420-b8c8-fb04ade8cd67	fc48529f-7c1b-41f4-9975-fc576e2788bd	Immobiliare	0.0165	2025-11-09 18:17:35.824821+01
\.


--
-- TOC entry 5419 (class 0 OID 100075)
-- Dependencies: 221
-- Data for Name: portfolio_snapshots; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.portfolio_snapshots (snapshot_id, portfolio_id, snapshot_date, total_value, total_invested, total_gain_loss, total_gain_loss_pct, asset_allocation, geographic_allocation, sector_allocation, created_at) FROM stdin;
\.


--
-- TOC entry 5415 (class 0 OID 99997)
-- Dependencies: 217
-- Data for Name: portfolios; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.portfolios (portfolio_id, name, broker, account_number, currency, created_at, updated_at, is_active, notes) FROM stdin;
a5938c95-ba8e-46f6-98f2-4e670ba3b2a4	Portafoglio Franco	Fineco Bank	\N	EUR	2025-11-04 19:00:50.340903+01	2025-11-04 19:00:50.340903+01	t	Portafoglio di Franco Paoluzi
\.


--
-- TOC entry 5418 (class 0 OID 100053)
-- Dependencies: 220
-- Data for Name: positions; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.positions (position_id, portfolio_id, asset_id, quantity, average_buy_price, total_invested, total_commissions, total_fees, first_purchase_date, last_transaction_date, updated_at) FROM stdin;
5c4363fc-55db-4c06-8ee7-4d8c85a1e903	a5938c95-ba8e-46f6-98f2-4e670ba3b2a4	fc48529f-7c1b-41f4-9975-fc576e2788bd	800.000000	5.443738	4354.99	5.52	0.00	2025-10-07	2025-09-03	2025-11-05 12:35:29.892777+01
2e7fdf12-f20d-436b-b2e3-bcedec49d0b9	a5938c95-ba8e-46f6-98f2-4e670ba3b2a4	fda2e7d3-54a5-4b6b-a504-48873da1c697	100.000000	16.364100	1636.41	0.00	0.00	2025-07-02	2025-07-02	2025-11-05 12:35:29.892777+01
8e0d97d4-1345-4981-9a98-dedd4864e6df	a5938c95-ba8e-46f6-98f2-4e670ba3b2a4	bcdff4ec-d4bf-419e-afb1-49beea99eeaf	150.000000	40.632070	6106.37	0.00	0.00	2025-03-04	2025-03-04	2025-11-05 12:35:29.892777+01
b5cb7f11-3db4-4ecd-9f14-8bb88250fee5	a5938c95-ba8e-46f6-98f2-4e670ba3b2a4	e0534574-8100-43c6-a396-f954f8ac95be	730.000000	17.431479	12724.98	19.00	0.00	2025-10-07	2025-02-28	2025-11-05 12:35:29.892777+01
ab03ab82-8497-45aa-8b32-81e8be312148	a5938c95-ba8e-46f6-98f2-4e670ba3b2a4	f1daeb66-3038-40d7-beea-ba11dd317ae9	69.000000	202.293913	13958.28	24.59	0.00	2025-10-07	2025-02-28	2025-11-05 12:35:29.892777+01
d664e451-b7f2-4bd9-9156-1936f2f0826d	a5938c95-ba8e-46f6-98f2-4e670ba3b2a4	c743dda6-c6ba-43c2-a14e-75490a1b06b0	26.000000	125.670000	3267.42	0.00	0.00	2025-02-28	2025-02-28	2025-11-05 12:35:29.892777+01
cc527e3a-2df1-45e1-8813-67dab1974672	a5938c95-ba8e-46f6-98f2-4e670ba3b2a4	719121c9-908d-49b7-a047-23464f0960ab	20.000000	261.160000	5223.20	7.40	0.00	2025-06-02	2025-02-28	2025-11-05 12:35:29.892777+01
80c015e8-dd94-4a3a-af88-bb2e842640e0	a5938c95-ba8e-46f6-98f2-4e670ba3b2a4	0999dc6a-e6f9-4bbf-9bd2-30a25658de89	20.000000	168.470000	3369.40	0.00	0.00	2025-02-28	2025-02-28	2025-11-05 12:35:29.892777+01
e5091434-1443-4e45-b8e4-c96edac2ea2a	a5938c95-ba8e-46f6-98f2-4e670ba3b2a4	cc52fa73-bb3a-49ea-bb36-a0191f934e11	132.000000	266.612424	35192.84	39.44	0.00	2025-11-04	2025-01-17	2025-11-05 12:35:29.892777+01
b4f8c103-d777-475f-93eb-8728589743f5	a5938c95-ba8e-46f6-98f2-4e670ba3b2a4	3a15e4de-589b-450d-93d1-a19b0c7bdb28	155.000000	144.979800	22471.87	0.00	0.00	2025-01-13	2025-01-13	2025-11-05 12:35:29.892777+01
7c5731ed-c0cb-4906-8858-ba7ac157dbfa	a5938c95-ba8e-46f6-98f2-4e670ba3b2a4	d2c980bc-c787-4166-8e74-d074800bf867	1900.000000	24.836821	47189.96	19.00	0.00	2025-01-17	2025-01-06	2025-11-05 12:35:29.892777+01
b990e477-0bae-434d-a4ee-17d2e78511dd	a5938c95-ba8e-46f6-98f2-4e670ba3b2a4	c117885f-43f8-4be0-8df2-f6d30a200cca	391.000000	102.833504	40207.90	0.00	0.00	2025-08-13	2025-01-02	2025-11-05 12:35:29.892777+01
4ce692ba-da35-42b6-859d-18be7d21e7ca	a5938c95-ba8e-46f6-98f2-4e670ba3b2a4	b46bba4b-525d-483d-bf4e-f195bde3d6bc	93.000000	607.971613	56541.36	54.42	0.00	2025-11-04	2024-12-10	2025-11-05 12:35:29.892777+01
5cd6edbe-e24f-4f59-b1d4-cf780113e012	a5938c95-ba8e-46f6-98f2-4e670ba3b2a4	8f706b9d-54ae-4ac7-8ce5-0ed005362d68	30.000000	77.031333	2310.94	0.14	0.00	2024-12-10	2024-12-10	2025-11-05 12:35:29.892777+01
b6cdef8d-bb1a-4d31-8437-2f2205e6e987	a5938c95-ba8e-46f6-98f2-4e670ba3b2a4	bf3b3448-1ec3-4f29-87e3-7fc90bc83308	605.000000	83.265207	50375.45	0.00	0.00	2025-01-17	2024-12-10	2025-11-05 12:35:29.892777+01
\.


--
-- TOC entry 5422 (class 0 OID 100158)
-- Dependencies: 224
-- Data for Name: price_history; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.price_history (price_id, asset_id, price_date, open_price, high_price, low_price, close_price, volume, data_source, created_at) FROM stdin;
13c9c5ff-29f9-4cd0-b737-d652e0bb46b2	b46bba4b-525d-483d-bf4e-f195bde3d6bc	2024-11-04	\N	\N	\N	574.510000	\N	GENERATED	2025-11-04 12:45:09.892682+01
91a5e050-64f6-4462-b6e5-13b70a847bee	b46bba4b-525d-483d-bf4e-f195bde3d6bc	2024-11-05	\N	\N	\N	574.770000	\N	GENERATED	2025-11-04 12:45:09.89348+01
89253145-3e61-4683-b214-f02abbbbed6c	b46bba4b-525d-483d-bf4e-f195bde3d6bc	2024-11-06	\N	\N	\N	584.300000	\N	GENERATED	2025-11-04 12:45:09.894198+01
2574dd6a-9b4b-4881-a6e8-d3c41f87a710	b46bba4b-525d-483d-bf4e-f195bde3d6bc	2024-11-07	\N	\N	\N	580.850000	\N	GENERATED	2025-11-04 12:45:09.894908+01
2530c94b-d786-4973-818d-5cade5cd1276	b46bba4b-525d-483d-bf4e-f195bde3d6bc	2024-11-08	\N	\N	\N	580.620000	\N	GENERATED	2025-11-04 12:45:09.895644+01
c1f8c7f8-f53b-4412-854a-449286e16fa6	b46bba4b-525d-483d-bf4e-f195bde3d6bc	2024-11-09	\N	\N	\N	585.210000	\N	GENERATED	2025-11-04 12:45:09.896339+01
8fd4f7fc-7efc-4d47-825b-d78ae76c8c4d	b46bba4b-525d-483d-bf4e-f195bde3d6bc	2024-11-10	\N	\N	\N	580.910000	\N	GENERATED	2025-11-04 12:45:09.897175+01
acf3d634-8909-4d82-a071-92e201d3d817	b46bba4b-525d-483d-bf4e-f195bde3d6bc	2024-11-11	\N	\N	\N	581.640000	\N	GENERATED	2025-11-04 12:45:09.897899+01
4d00f8fd-fb7c-4dcb-8bd2-e56985c5819b	b46bba4b-525d-483d-bf4e-f195bde3d6bc	2024-11-12	\N	\N	\N	585.470000	\N	GENERATED	2025-11-04 12:45:09.89861+01
abb0f5d7-7823-40cb-a07f-ffcc439d9364	b46bba4b-525d-483d-bf4e-f195bde3d6bc	2024-11-13	\N	\N	\N	584.990000	\N	GENERATED	2025-11-04 12:45:09.899316+01
fb6aa57e-d705-459c-80bd-e5e6c50f0a84	b46bba4b-525d-483d-bf4e-f195bde3d6bc	2024-11-14	\N	\N	\N	582.530000	\N	GENERATED	2025-11-04 12:45:09.900254+01
e5682b44-7b9c-432a-9534-1580697c6d47	b46bba4b-525d-483d-bf4e-f195bde3d6bc	2024-11-15	\N	\N	\N	580.580000	\N	GENERATED	2025-11-04 12:45:09.90099+01
b1754fab-db9d-4efe-9d7c-4a06d2fe91dc	b46bba4b-525d-483d-bf4e-f195bde3d6bc	2024-11-16	\N	\N	\N	582.160000	\N	GENERATED	2025-11-04 12:45:09.901754+01
3ec8485a-1de6-49a8-8d41-758665334c9b	b46bba4b-525d-483d-bf4e-f195bde3d6bc	2024-11-17	\N	\N	\N	586.840000	\N	GENERATED	2025-11-04 12:45:09.902497+01
993679c9-df54-403c-9a27-e0c234f6c96c	b46bba4b-525d-483d-bf4e-f195bde3d6bc	2024-11-18	\N	\N	\N	576.290000	\N	GENERATED	2025-11-04 12:45:09.903318+01
1d337f60-bd48-4498-b456-72e76dd6b4e7	b46bba4b-525d-483d-bf4e-f195bde3d6bc	2024-11-19	\N	\N	\N	581.380000	\N	GENERATED	2025-11-04 12:45:09.904395+01
6469a0c2-77b2-4180-885f-148b22627f59	b46bba4b-525d-483d-bf4e-f195bde3d6bc	2024-11-20	\N	\N	\N	584.040000	\N	GENERATED	2025-11-04 12:45:09.905205+01
44a43eee-b07c-4f43-b991-965afbec15a9	b46bba4b-525d-483d-bf4e-f195bde3d6bc	2024-11-21	\N	\N	\N	585.050000	\N	GENERATED	2025-11-04 12:45:09.905901+01
e57e7f6e-0a13-426b-84dd-27a579b2de77	b46bba4b-525d-483d-bf4e-f195bde3d6bc	2024-11-22	\N	\N	\N	578.620000	\N	GENERATED	2025-11-04 12:45:09.906607+01
cce168fd-8365-4e13-b8b4-18ae5456dc68	b46bba4b-525d-483d-bf4e-f195bde3d6bc	2024-11-23	\N	\N	\N	580.980000	\N	GENERATED	2025-11-04 12:45:09.907371+01
dd8e376e-800d-41a0-bbb0-3e366c7bde4d	b46bba4b-525d-483d-bf4e-f195bde3d6bc	2024-11-24	\N	\N	\N	580.280000	\N	GENERATED	2025-11-04 12:45:09.90807+01
1730d906-abd8-45d2-80ee-f171fc05cf10	b46bba4b-525d-483d-bf4e-f195bde3d6bc	2024-11-25	\N	\N	\N	579.120000	\N	GENERATED	2025-11-04 12:45:09.908769+01
0f857e2c-f8c7-44b9-8278-713cedbb66f8	b46bba4b-525d-483d-bf4e-f195bde3d6bc	2024-11-26	\N	\N	\N	585.740000	\N	GENERATED	2025-11-04 12:45:09.909635+01
6e7b2b3e-293f-4d29-935f-be247a63e461	b46bba4b-525d-483d-bf4e-f195bde3d6bc	2024-11-27	\N	\N	\N	585.220000	\N	GENERATED	2025-11-04 12:45:09.910322+01
46e550b6-b7c4-49d1-a8f4-76ddcc170b58	b46bba4b-525d-483d-bf4e-f195bde3d6bc	2024-11-28	\N	\N	\N	583.080000	\N	GENERATED	2025-11-04 12:45:09.911015+01
1f14f39d-467c-4079-a3b3-b38e6c3ff493	b46bba4b-525d-483d-bf4e-f195bde3d6bc	2024-11-29	\N	\N	\N	588.940000	\N	GENERATED	2025-11-04 12:45:09.911781+01
c9323d00-fb76-4382-9525-3ce4b8b951f5	b46bba4b-525d-483d-bf4e-f195bde3d6bc	2024-11-30	\N	\N	\N	588.090000	\N	GENERATED	2025-11-04 12:45:09.912461+01
ecc68b36-d6a8-4e33-8eff-f6ca9b612e7d	b46bba4b-525d-483d-bf4e-f195bde3d6bc	2024-12-01	\N	\N	\N	578.450000	\N	GENERATED	2025-11-04 12:45:09.91315+01
ad48cc89-93d2-4b66-b0f4-eb88a0ec3e89	b46bba4b-525d-483d-bf4e-f195bde3d6bc	2024-12-02	\N	\N	\N	577.980000	\N	GENERATED	2025-11-04 12:45:09.913859+01
be86810e-1870-4566-a8b8-cd98b8a95fdd	b46bba4b-525d-483d-bf4e-f195bde3d6bc	2024-12-03	\N	\N	\N	588.120000	\N	GENERATED	2025-11-04 12:45:09.91478+01
521cde80-fa47-4de7-9203-bba406eb413e	b46bba4b-525d-483d-bf4e-f195bde3d6bc	2024-12-04	\N	\N	\N	588.420000	\N	GENERATED	2025-11-04 12:45:09.916033+01
c34dec5a-83f8-4806-8bd4-95d1d5d2870e	b46bba4b-525d-483d-bf4e-f195bde3d6bc	2024-12-05	\N	\N	\N	589.510000	\N	GENERATED	2025-11-04 12:45:09.91685+01
19721c40-f1dc-4c7b-a488-081a26ff0217	b46bba4b-525d-483d-bf4e-f195bde3d6bc	2024-12-06	\N	\N	\N	580.330000	\N	GENERATED	2025-11-04 12:45:09.917659+01
435162e0-f9fb-4223-9982-63210b763ec4	b46bba4b-525d-483d-bf4e-f195bde3d6bc	2024-12-07	\N	\N	\N	584.800000	\N	GENERATED	2025-11-04 12:45:09.918343+01
02346efa-0a3e-47c9-94fb-14aa34304965	b46bba4b-525d-483d-bf4e-f195bde3d6bc	2024-12-08	\N	\N	\N	581.650000	\N	GENERATED	2025-11-04 12:45:09.919056+01
758503d7-5ec6-41ac-8d8e-444d143ff9cc	b46bba4b-525d-483d-bf4e-f195bde3d6bc	2024-12-09	\N	\N	\N	585.890000	\N	GENERATED	2025-11-04 12:45:09.919755+01
7c8c67a9-2e8f-4b28-a78d-c1cef4265c26	b46bba4b-525d-483d-bf4e-f195bde3d6bc	2024-12-10	\N	\N	\N	584.410000	\N	GENERATED	2025-11-04 12:45:09.920434+01
f695887c-fd36-4309-a525-c8071893ef77	b46bba4b-525d-483d-bf4e-f195bde3d6bc	2024-12-11	\N	\N	\N	585.940000	\N	GENERATED	2025-11-04 12:45:09.92114+01
df0fbe83-fcbe-4e97-b3f6-ac3cf8295bf2	b46bba4b-525d-483d-bf4e-f195bde3d6bc	2024-12-12	\N	\N	\N	589.020000	\N	GENERATED	2025-11-04 12:45:09.921907+01
6b439f84-ff9d-479b-8b26-a39bcd0cec28	b46bba4b-525d-483d-bf4e-f195bde3d6bc	2024-12-13	\N	\N	\N	589.020000	\N	GENERATED	2025-11-04 12:45:09.922593+01
0586a9f5-bda2-4f38-ae84-40cd41087fb8	b46bba4b-525d-483d-bf4e-f195bde3d6bc	2024-12-14	\N	\N	\N	585.180000	\N	GENERATED	2025-11-04 12:45:09.923284+01
6ba8beb6-4dc4-42e8-b639-f93d89a4f812	b46bba4b-525d-483d-bf4e-f195bde3d6bc	2024-12-15	\N	\N	\N	590.850000	\N	GENERATED	2025-11-04 12:45:09.923973+01
9a960ab6-fb29-47b0-bd37-ea6c1696165e	b46bba4b-525d-483d-bf4e-f195bde3d6bc	2024-12-16	\N	\N	\N	579.740000	\N	GENERATED	2025-11-04 12:45:09.924652+01
701b8c00-034c-4665-bdf3-29510cf21360	b46bba4b-525d-483d-bf4e-f195bde3d6bc	2024-12-17	\N	\N	\N	583.710000	\N	GENERATED	2025-11-04 12:45:09.925369+01
40900275-3f34-4e5a-852e-104eee39a18b	b46bba4b-525d-483d-bf4e-f195bde3d6bc	2024-12-18	\N	\N	\N	586.560000	\N	GENERATED	2025-11-04 12:45:09.926057+01
3b7b98d3-5145-459e-b70a-c21584364b17	b46bba4b-525d-483d-bf4e-f195bde3d6bc	2024-12-19	\N	\N	\N	580.350000	\N	GENERATED	2025-11-04 12:45:09.926745+01
cd76e97e-838c-4792-9761-35903a41f65d	b46bba4b-525d-483d-bf4e-f195bde3d6bc	2024-12-20	\N	\N	\N	581.910000	\N	GENERATED	2025-11-04 12:45:09.927424+01
8a882d62-4265-4e7e-847e-9e7474ad95c1	b46bba4b-525d-483d-bf4e-f195bde3d6bc	2024-12-21	\N	\N	\N	591.330000	\N	GENERATED	2025-11-04 12:45:09.928166+01
423594e9-0351-455a-8ad2-7f810756b741	b46bba4b-525d-483d-bf4e-f195bde3d6bc	2024-12-22	\N	\N	\N	583.040000	\N	GENERATED	2025-11-04 12:45:09.928859+01
6106c881-88ee-4162-97dd-a0d1d54667d8	b46bba4b-525d-483d-bf4e-f195bde3d6bc	2024-12-23	\N	\N	\N	590.800000	\N	GENERATED	2025-11-04 12:45:09.92954+01
89fdc065-03da-4914-8a4a-a6b05a6ccbc1	b46bba4b-525d-483d-bf4e-f195bde3d6bc	2024-12-24	\N	\N	\N	582.760000	\N	GENERATED	2025-11-04 12:45:09.93023+01
9192225d-f240-480e-97eb-943eb8a30048	b46bba4b-525d-483d-bf4e-f195bde3d6bc	2024-12-25	\N	\N	\N	587.830000	\N	GENERATED	2025-11-04 12:45:09.931282+01
0100fe7a-e3b9-4209-9e9d-fcdcb3789249	b46bba4b-525d-483d-bf4e-f195bde3d6bc	2024-12-26	\N	\N	\N	585.520000	\N	GENERATED	2025-11-04 12:45:09.932161+01
15398c00-30f9-4eff-a01b-6721b72865c0	b46bba4b-525d-483d-bf4e-f195bde3d6bc	2024-12-27	\N	\N	\N	587.270000	\N	GENERATED	2025-11-04 12:45:09.932884+01
b994d210-a604-4fd9-b0ac-aff757c70b58	b46bba4b-525d-483d-bf4e-f195bde3d6bc	2024-12-28	\N	\N	\N	590.870000	\N	GENERATED	2025-11-04 12:45:09.933571+01
da160063-9018-45b4-9015-686ee18f1717	b46bba4b-525d-483d-bf4e-f195bde3d6bc	2024-12-29	\N	\N	\N	587.160000	\N	GENERATED	2025-11-04 12:45:09.934304+01
f6697c87-d06f-4261-82c2-4005a067ee64	b46bba4b-525d-483d-bf4e-f195bde3d6bc	2024-12-30	\N	\N	\N	587.490000	\N	GENERATED	2025-11-04 12:45:09.935001+01
e1301f25-879f-4a44-a523-d12f4e7e7af1	b46bba4b-525d-483d-bf4e-f195bde3d6bc	2024-12-31	\N	\N	\N	589.110000	\N	GENERATED	2025-11-04 12:45:09.935694+01
79a67462-b74a-4c43-bbf5-038f166360db	b46bba4b-525d-483d-bf4e-f195bde3d6bc	2025-01-01	\N	\N	\N	582.750000	\N	GENERATED	2025-11-04 12:45:09.93639+01
4bfd8d4c-87ce-4c52-bcb8-bad70c7258f0	b46bba4b-525d-483d-bf4e-f195bde3d6bc	2025-01-02	\N	\N	\N	589.850000	\N	GENERATED	2025-11-04 12:45:09.937092+01
32bc0125-79af-4b85-a85c-c814abfbf4ce	b46bba4b-525d-483d-bf4e-f195bde3d6bc	2025-01-03	\N	\N	\N	593.360000	\N	GENERATED	2025-11-04 12:45:09.937806+01
01c83b55-b867-4cce-abfa-c772fdf8a980	b46bba4b-525d-483d-bf4e-f195bde3d6bc	2025-01-04	\N	\N	\N	584.570000	\N	GENERATED	2025-11-04 12:45:09.938493+01
4e62030f-cf3d-40a0-ac93-cc897903b6f4	b46bba4b-525d-483d-bf4e-f195bde3d6bc	2025-01-05	\N	\N	\N	584.150000	\N	GENERATED	2025-11-04 12:45:09.939187+01
92865ceb-0ac9-43dd-8633-0bbf3d38464c	b46bba4b-525d-483d-bf4e-f195bde3d6bc	2025-01-06	\N	\N	\N	588.670000	\N	GENERATED	2025-11-04 12:45:09.939873+01
15b68244-b08c-48ef-b8c3-1e03aa1a5cd9	b46bba4b-525d-483d-bf4e-f195bde3d6bc	2025-01-07	\N	\N	\N	584.360000	\N	GENERATED	2025-11-04 12:45:09.940558+01
cd7acf85-c2dd-43c8-9dd8-4708f3cefec9	b46bba4b-525d-483d-bf4e-f195bde3d6bc	2025-01-08	\N	\N	\N	592.630000	\N	GENERATED	2025-11-04 12:45:09.941237+01
68de7bbe-fc8f-433c-8fec-15704f2312e3	b46bba4b-525d-483d-bf4e-f195bde3d6bc	2025-01-09	\N	\N	\N	589.810000	\N	GENERATED	2025-11-04 12:45:09.941912+01
f75bb4f9-95e8-4b43-b110-16caffc90c01	b46bba4b-525d-483d-bf4e-f195bde3d6bc	2025-01-10	\N	\N	\N	591.780000	\N	GENERATED	2025-11-04 12:45:09.942636+01
6fceb36f-2c0b-4326-8a04-e32ae9912f6a	b46bba4b-525d-483d-bf4e-f195bde3d6bc	2025-01-11	\N	\N	\N	583.660000	\N	GENERATED	2025-11-04 12:45:09.943355+01
0a9c3558-b6a9-43bb-9dd2-a5e512379faf	b46bba4b-525d-483d-bf4e-f195bde3d6bc	2025-01-12	\N	\N	\N	583.000000	\N	GENERATED	2025-11-04 12:45:09.944038+01
e83ac4c3-acc3-4af4-a2db-152369ec84e4	bf3b3448-1ec3-4f29-87e3-7fc90bc83308	2025-11-04	\N	\N	\N	85.300000	\N	MANUAL	2025-11-04 12:45:09.882674+01
8bf03584-450a-47d8-aa27-9e7d72961de2	c117885f-43f8-4be0-8df2-f6d30a200cca	2025-11-04	\N	\N	\N	108.750000	\N	MANUAL	2025-11-04 12:45:09.883815+01
79ee659a-9199-45cc-adae-49d83cc122c6	8f706b9d-54ae-4ac7-8ce5-0ed005362d68	2025-11-04	\N	\N	\N	79.200000	\N	MANUAL	2025-11-04 12:45:09.884898+01
f81b1701-a10e-421b-ab43-4fb0ddb5b3b6	6e5b011b-1658-420d-886d-4f0802372d0b	2025-11-04	\N	\N	\N	101.450000	\N	MANUAL	2025-11-04 12:45:09.885906+01
71c743fb-d003-4e2b-ac22-836ed50a25d7	0ede49d0-617f-451f-b90e-7fd9631cfa04	2025-11-04	\N	\N	\N	78.900000	\N	MANUAL	2025-11-04 12:45:09.886823+01
e4a45daf-f2b3-426f-a25c-bf2c8eb2b9e0	d2c980bc-c787-4166-8e74-d074800bf867	2025-11-04	\N	\N	\N	25.100000	\N	MANUAL	2025-11-04 12:45:09.887819+01
ba1ce4c0-bbaa-4655-aba4-e6204e89924d	92125d99-571e-42c7-8369-4ce85c866078	2025-11-04	\N	\N	\N	115.200000	\N	MANUAL	2025-11-04 12:45:09.888694+01
d630c942-6d17-4184-b8f5-bdce453e4ca4	cc52fa73-bb3a-49ea-bb36-a0191f934e11	2025-11-04	\N	\N	\N	268.400000	\N	MANUAL	2025-11-04 12:45:09.890406+01
12142ab1-9c0a-4000-a603-fad736cf72e7	3a15e4de-589b-450d-93d1-a19b0c7bdb28	2025-11-04	\N	\N	\N	147.350000	\N	MANUAL	2025-11-04 12:45:09.891534+01
cf2a9d67-f62d-4fbb-a4a0-36db86ba4943	b46bba4b-525d-483d-bf4e-f195bde3d6bc	2025-01-13	\N	\N	\N	594.480000	\N	GENERATED	2025-11-04 12:45:09.944733+01
04935a81-b2e7-43a0-a18f-00afec7f2c4a	b46bba4b-525d-483d-bf4e-f195bde3d6bc	2025-01-14	\N	\N	\N	591.110000	\N	GENERATED	2025-11-04 12:45:09.946123+01
ec2a8f7e-8af8-4e69-abc1-17edf42622af	b46bba4b-525d-483d-bf4e-f195bde3d6bc	2025-01-15	\N	\N	\N	594.900000	\N	GENERATED	2025-11-04 12:45:09.946962+01
9aa8a9cc-309e-4665-a591-5e8ad91cd663	b46bba4b-525d-483d-bf4e-f195bde3d6bc	2025-01-16	\N	\N	\N	584.760000	\N	GENERATED	2025-11-04 12:45:09.9477+01
7ebd53a7-c730-49a6-b0bc-cb9b388c265f	b46bba4b-525d-483d-bf4e-f195bde3d6bc	2025-01-17	\N	\N	\N	585.180000	\N	GENERATED	2025-11-04 12:45:09.948409+01
df527293-387c-4183-9219-ba374209f271	b46bba4b-525d-483d-bf4e-f195bde3d6bc	2025-01-18	\N	\N	\N	590.880000	\N	GENERATED	2025-11-04 12:45:09.949097+01
0634c272-d388-4b8e-8ca1-b307f0ca78cf	b46bba4b-525d-483d-bf4e-f195bde3d6bc	2025-01-19	\N	\N	\N	592.010000	\N	GENERATED	2025-11-04 12:45:09.949789+01
5476e9cb-2011-4230-acb3-ced4a56294a0	b46bba4b-525d-483d-bf4e-f195bde3d6bc	2025-01-20	\N	\N	\N	593.530000	\N	GENERATED	2025-11-04 12:45:09.950484+01
d3166e3a-ef95-42c5-aa89-9ea9030be859	b46bba4b-525d-483d-bf4e-f195bde3d6bc	2025-01-21	\N	\N	\N	591.840000	\N	GENERATED	2025-11-04 12:45:09.951173+01
5cb4aeee-aeeb-4d71-b51a-94238e697ab6	b46bba4b-525d-483d-bf4e-f195bde3d6bc	2025-01-22	\N	\N	\N	591.700000	\N	GENERATED	2025-11-04 12:45:09.951917+01
a1189e65-50b4-45fa-8ea6-397c56e92350	b46bba4b-525d-483d-bf4e-f195bde3d6bc	2025-01-23	\N	\N	\N	586.600000	\N	GENERATED	2025-11-04 12:45:09.952611+01
db2d597b-4ea1-48a3-975a-3dabde05dda0	b46bba4b-525d-483d-bf4e-f195bde3d6bc	2025-01-24	\N	\N	\N	590.080000	\N	GENERATED	2025-11-04 12:45:09.95333+01
071f3835-ed1a-48fe-b17a-5a6d3d94b8d5	b46bba4b-525d-483d-bf4e-f195bde3d6bc	2025-01-25	\N	\N	\N	593.440000	\N	GENERATED	2025-11-04 12:45:09.954017+01
369ecc32-739f-4c7b-85e2-294821e956ff	b46bba4b-525d-483d-bf4e-f195bde3d6bc	2025-01-26	\N	\N	\N	592.330000	\N	GENERATED	2025-11-04 12:45:09.954701+01
ccb03b5e-fb69-42d0-a697-4a2c80d33f47	b46bba4b-525d-483d-bf4e-f195bde3d6bc	2025-01-27	\N	\N	\N	588.710000	\N	GENERATED	2025-11-04 12:45:09.955378+01
3cf6c324-b515-46e3-a7e0-74cb7db376a3	b46bba4b-525d-483d-bf4e-f195bde3d6bc	2025-01-28	\N	\N	\N	589.580000	\N	GENERATED	2025-11-04 12:45:09.956062+01
3c2f5bd5-5616-4e76-be03-3943397fa991	b46bba4b-525d-483d-bf4e-f195bde3d6bc	2025-01-29	\N	\N	\N	590.570000	\N	GENERATED	2025-11-04 12:45:09.95674+01
28d4539b-706b-4b57-a517-58fe90007fe4	b46bba4b-525d-483d-bf4e-f195bde3d6bc	2025-01-30	\N	\N	\N	596.140000	\N	GENERATED	2025-11-04 12:45:09.957415+01
64043836-b924-4276-8e86-d53cf4b61aab	b46bba4b-525d-483d-bf4e-f195bde3d6bc	2025-01-31	\N	\N	\N	590.880000	\N	GENERATED	2025-11-04 12:45:09.958139+01
8fd2e399-bd4a-44c9-a85c-99ff8e3e4f9b	b46bba4b-525d-483d-bf4e-f195bde3d6bc	2025-02-01	\N	\N	\N	588.920000	\N	GENERATED	2025-11-04 12:45:09.958823+01
a97ea0ec-53fc-422b-8a27-566edf73cf99	b46bba4b-525d-483d-bf4e-f195bde3d6bc	2025-02-02	\N	\N	\N	587.540000	\N	GENERATED	2025-11-04 12:45:09.9595+01
52fc7c5d-b971-4595-bf15-96c6fadb552a	b46bba4b-525d-483d-bf4e-f195bde3d6bc	2025-02-03	\N	\N	\N	596.670000	\N	GENERATED	2025-11-04 12:45:09.960208+01
45925209-9a70-4871-b977-649bfd8151de	b46bba4b-525d-483d-bf4e-f195bde3d6bc	2025-02-04	\N	\N	\N	592.700000	\N	GENERATED	2025-11-04 12:45:09.9609+01
ff2040f8-a55d-443e-b051-501f58686394	b46bba4b-525d-483d-bf4e-f195bde3d6bc	2025-02-05	\N	\N	\N	589.610000	\N	GENERATED	2025-11-04 12:45:09.961575+01
3a662d10-7705-403c-abb2-6012aa5872c7	b46bba4b-525d-483d-bf4e-f195bde3d6bc	2025-02-06	\N	\N	\N	588.310000	\N	GENERATED	2025-11-04 12:45:09.962458+01
f71417ee-69a9-4ecc-8a42-48ed99c6d25a	b46bba4b-525d-483d-bf4e-f195bde3d6bc	2025-02-07	\N	\N	\N	590.340000	\N	GENERATED	2025-11-04 12:45:09.963151+01
862b6565-4745-4417-af84-c4ee44fdd5bb	b46bba4b-525d-483d-bf4e-f195bde3d6bc	2025-02-08	\N	\N	\N	594.410000	\N	GENERATED	2025-11-04 12:45:09.963835+01
63c31907-87fb-400b-9ddb-19bd91b0f062	b46bba4b-525d-483d-bf4e-f195bde3d6bc	2025-02-09	\N	\N	\N	590.290000	\N	GENERATED	2025-11-04 12:45:09.964515+01
746f346b-d5c6-41a2-a824-75ee8190546d	b46bba4b-525d-483d-bf4e-f195bde3d6bc	2025-02-10	\N	\N	\N	593.260000	\N	GENERATED	2025-11-04 12:45:09.965204+01
8fc56c35-695c-4a72-abb7-e96d95cc5c4c	b46bba4b-525d-483d-bf4e-f195bde3d6bc	2025-02-11	\N	\N	\N	591.860000	\N	GENERATED	2025-11-04 12:45:09.965879+01
e3613226-5499-4dd2-a77f-bfe635047de4	b46bba4b-525d-483d-bf4e-f195bde3d6bc	2025-02-12	\N	\N	\N	590.150000	\N	GENERATED	2025-11-04 12:45:09.966567+01
45fcd50c-ed57-45df-afa0-80dd815c372f	b46bba4b-525d-483d-bf4e-f195bde3d6bc	2025-02-13	\N	\N	\N	596.420000	\N	GENERATED	2025-11-04 12:45:09.967248+01
121ae1e0-4b6c-41c8-b549-011b51b5898e	b46bba4b-525d-483d-bf4e-f195bde3d6bc	2025-02-14	\N	\N	\N	587.460000	\N	GENERATED	2025-11-04 12:45:09.967935+01
09b31251-0e8a-4254-a60e-429600399eac	b46bba4b-525d-483d-bf4e-f195bde3d6bc	2025-02-15	\N	\N	\N	593.220000	\N	GENERATED	2025-11-04 12:45:09.968624+01
bf82619b-d31c-44dd-9e71-8a310afdac50	b46bba4b-525d-483d-bf4e-f195bde3d6bc	2025-02-16	\N	\N	\N	597.770000	\N	GENERATED	2025-11-04 12:45:09.969298+01
1869c1e0-cfc7-4a69-9dc9-270f207e302c	b46bba4b-525d-483d-bf4e-f195bde3d6bc	2025-02-17	\N	\N	\N	597.680000	\N	GENERATED	2025-11-04 12:45:09.969984+01
566a593e-fc7f-444e-b481-216d178bddab	b46bba4b-525d-483d-bf4e-f195bde3d6bc	2025-02-18	\N	\N	\N	598.680000	\N	GENERATED	2025-11-04 12:45:09.970665+01
d9fec333-059c-4a14-bb3c-0ef9395f0b34	b46bba4b-525d-483d-bf4e-f195bde3d6bc	2025-02-19	\N	\N	\N	597.410000	\N	GENERATED	2025-11-04 12:45:09.971349+01
53706c79-5d83-43e2-9975-a3253928b82e	b46bba4b-525d-483d-bf4e-f195bde3d6bc	2025-02-20	\N	\N	\N	594.300000	\N	GENERATED	2025-11-04 12:45:09.972101+01
962989eb-7999-480f-8b4c-952734cac514	b46bba4b-525d-483d-bf4e-f195bde3d6bc	2025-02-21	\N	\N	\N	592.120000	\N	GENERATED	2025-11-04 12:45:09.97292+01
ad48d923-9c1c-453f-b8a4-a5167f590621	b46bba4b-525d-483d-bf4e-f195bde3d6bc	2025-02-22	\N	\N	\N	592.600000	\N	GENERATED	2025-11-04 12:45:09.973617+01
e236953d-b096-4945-9097-d847d81746f4	b46bba4b-525d-483d-bf4e-f195bde3d6bc	2025-02-23	\N	\N	\N	594.430000	\N	GENERATED	2025-11-04 12:45:09.974295+01
49e936df-ce46-4420-8ac6-645edf9a0f8a	b46bba4b-525d-483d-bf4e-f195bde3d6bc	2025-02-24	\N	\N	\N	590.770000	\N	GENERATED	2025-11-04 12:45:09.975021+01
1f5618f8-2888-4c66-9260-6c5965e97009	b46bba4b-525d-483d-bf4e-f195bde3d6bc	2025-02-25	\N	\N	\N	599.880000	\N	GENERATED	2025-11-04 12:45:09.975711+01
74d34d86-e9e2-4d63-9c2f-04706c6656d3	b46bba4b-525d-483d-bf4e-f195bde3d6bc	2025-02-26	\N	\N	\N	596.990000	\N	GENERATED	2025-11-04 12:45:09.976402+01
04590be8-8dcd-4cd7-89cd-47f230820b44	b46bba4b-525d-483d-bf4e-f195bde3d6bc	2025-02-27	\N	\N	\N	599.700000	\N	GENERATED	2025-11-04 12:45:09.977109+01
39981f45-d7f2-4037-bfb6-00e5a3ea6f9c	b46bba4b-525d-483d-bf4e-f195bde3d6bc	2025-02-28	\N	\N	\N	599.460000	\N	GENERATED	2025-11-04 12:45:09.977996+01
8b4595d8-446e-4e64-b01f-9f28a02be4bb	b46bba4b-525d-483d-bf4e-f195bde3d6bc	2025-03-01	\N	\N	\N	594.550000	\N	GENERATED	2025-11-04 12:45:09.978831+01
093256f2-35ba-4d07-be85-8d628234aca4	b46bba4b-525d-483d-bf4e-f195bde3d6bc	2025-03-02	\N	\N	\N	599.840000	\N	GENERATED	2025-11-04 12:45:09.979591+01
a8774c75-3453-4515-b3c2-8e79a1b9d719	b46bba4b-525d-483d-bf4e-f195bde3d6bc	2025-03-03	\N	\N	\N	591.590000	\N	GENERATED	2025-11-04 12:45:09.980311+01
19733bf1-7f74-4b15-915f-93ff29a054cc	b46bba4b-525d-483d-bf4e-f195bde3d6bc	2025-03-04	\N	\N	\N	598.710000	\N	GENERATED	2025-11-04 12:45:09.981006+01
9e3a82df-b0e0-4094-83af-d7fa7a1dec56	b46bba4b-525d-483d-bf4e-f195bde3d6bc	2025-03-05	\N	\N	\N	592.130000	\N	GENERATED	2025-11-04 12:45:09.9817+01
c19f256e-7b92-4514-b02c-a179500ad9aa	b46bba4b-525d-483d-bf4e-f195bde3d6bc	2025-03-06	\N	\N	\N	589.820000	\N	GENERATED	2025-11-04 12:45:09.982385+01
07640279-59aa-422b-99ab-a238744875f9	b46bba4b-525d-483d-bf4e-f195bde3d6bc	2025-03-07	\N	\N	\N	597.610000	\N	GENERATED	2025-11-04 12:45:09.983086+01
5d8aae6f-aac5-4d80-857d-11d3e18f470c	b46bba4b-525d-483d-bf4e-f195bde3d6bc	2025-03-08	\N	\N	\N	590.790000	\N	GENERATED	2025-11-04 12:45:09.98377+01
f0b0d9de-bb8a-4b8a-b232-30286ef551bc	b46bba4b-525d-483d-bf4e-f195bde3d6bc	2025-03-09	\N	\N	\N	599.110000	\N	GENERATED	2025-11-04 12:45:09.984558+01
96b37737-1e1f-49a1-b2d0-d92296858731	b46bba4b-525d-483d-bf4e-f195bde3d6bc	2025-03-10	\N	\N	\N	594.150000	\N	GENERATED	2025-11-04 12:45:09.985592+01
08b299b4-aee9-465f-91d3-2c671cd89df7	b46bba4b-525d-483d-bf4e-f195bde3d6bc	2025-03-11	\N	\N	\N	595.400000	\N	GENERATED	2025-11-04 12:45:09.986277+01
e192fe0d-5eea-4c20-9d1a-425f8134ac96	b46bba4b-525d-483d-bf4e-f195bde3d6bc	2025-03-12	\N	\N	\N	595.110000	\N	GENERATED	2025-11-04 12:45:09.986971+01
0ca3f731-b314-432b-81bb-ce44b20ce775	b46bba4b-525d-483d-bf4e-f195bde3d6bc	2025-03-13	\N	\N	\N	602.080000	\N	GENERATED	2025-11-04 12:45:09.987666+01
84b2318b-f7ab-4390-b795-bda67e90f49f	b46bba4b-525d-483d-bf4e-f195bde3d6bc	2025-03-14	\N	\N	\N	591.920000	\N	GENERATED	2025-11-04 12:45:09.988335+01
7bb5560e-0890-4e57-8eb5-7dc55e1274a9	b46bba4b-525d-483d-bf4e-f195bde3d6bc	2025-03-15	\N	\N	\N	591.460000	\N	GENERATED	2025-11-04 12:45:09.989006+01
22f957df-dd76-4a66-8dcf-e56ea5629f35	b46bba4b-525d-483d-bf4e-f195bde3d6bc	2025-03-16	\N	\N	\N	597.990000	\N	GENERATED	2025-11-04 12:45:09.989781+01
3e2ab751-0306-4176-bd0d-fd7a85acb145	b46bba4b-525d-483d-bf4e-f195bde3d6bc	2025-03-17	\N	\N	\N	597.640000	\N	GENERATED	2025-11-04 12:45:09.990488+01
73573660-02dc-4185-bac4-670df83b3000	b46bba4b-525d-483d-bf4e-f195bde3d6bc	2025-03-18	\N	\N	\N	596.250000	\N	GENERATED	2025-11-04 12:45:09.991385+01
29541c62-70c3-45d4-a287-4bfa7b39c265	b46bba4b-525d-483d-bf4e-f195bde3d6bc	2025-03-19	\N	\N	\N	599.100000	\N	GENERATED	2025-11-04 12:45:09.992063+01
b4d7b9e7-43cf-4070-96f4-102412943430	b46bba4b-525d-483d-bf4e-f195bde3d6bc	2025-03-20	\N	\N	\N	600.540000	\N	GENERATED	2025-11-04 12:45:09.992756+01
a68093bc-1639-4096-9448-12e5e8a7dd11	b46bba4b-525d-483d-bf4e-f195bde3d6bc	2025-03-21	\N	\N	\N	594.820000	\N	GENERATED	2025-11-04 12:45:09.993565+01
8c9f7db1-4314-4724-8517-18de46111bb2	b46bba4b-525d-483d-bf4e-f195bde3d6bc	2025-03-22	\N	\N	\N	596.760000	\N	GENERATED	2025-11-04 12:45:09.994247+01
76b059d8-f5f9-473b-8f47-43ee636af8f2	b46bba4b-525d-483d-bf4e-f195bde3d6bc	2025-03-23	\N	\N	\N	595.370000	\N	GENERATED	2025-11-04 12:45:09.994928+01
00ff1458-45ad-43b5-98b7-f6fa7ef77fbf	b46bba4b-525d-483d-bf4e-f195bde3d6bc	2025-03-24	\N	\N	\N	596.620000	\N	GENERATED	2025-11-04 12:45:09.995605+01
90fd1b4c-1888-4dea-bb8c-bc6d463169ef	b46bba4b-525d-483d-bf4e-f195bde3d6bc	2025-03-25	\N	\N	\N	593.190000	\N	GENERATED	2025-11-04 12:45:09.996263+01
ae66017d-4d4a-40b3-90f8-1cdf382ba08f	b46bba4b-525d-483d-bf4e-f195bde3d6bc	2025-03-26	\N	\N	\N	602.990000	\N	GENERATED	2025-11-04 12:45:09.996969+01
4836705b-dc1d-4447-bc1c-c0eeceb08e88	b46bba4b-525d-483d-bf4e-f195bde3d6bc	2025-03-27	\N	\N	\N	603.720000	\N	GENERATED	2025-11-04 12:45:09.997814+01
d5ae6595-5ca8-4bca-a78d-84196f5989f4	b46bba4b-525d-483d-bf4e-f195bde3d6bc	2025-03-28	\N	\N	\N	596.140000	\N	GENERATED	2025-11-04 12:45:09.998478+01
830558a9-5d92-41cf-82fe-3e0821fccb70	b46bba4b-525d-483d-bf4e-f195bde3d6bc	2025-03-29	\N	\N	\N	595.170000	\N	GENERATED	2025-11-04 12:45:09.999136+01
478d9109-d8d4-46b1-9fa5-b6b215390254	b46bba4b-525d-483d-bf4e-f195bde3d6bc	2025-03-30	\N	\N	\N	596.500000	\N	GENERATED	2025-11-04 12:45:09.999829+01
1f3ed46e-d92e-4d64-a324-2d78bb53ded0	b46bba4b-525d-483d-bf4e-f195bde3d6bc	2025-03-31	\N	\N	\N	600.260000	\N	GENERATED	2025-11-04 12:45:10.000488+01
46bbc4a2-97ec-460c-94f3-790c35851381	b46bba4b-525d-483d-bf4e-f195bde3d6bc	2025-04-01	\N	\N	\N	596.490000	\N	GENERATED	2025-11-04 12:45:10.00115+01
f8a2f487-3d3e-47f6-a184-6ea775e9cce2	b46bba4b-525d-483d-bf4e-f195bde3d6bc	2025-04-02	\N	\N	\N	600.230000	\N	GENERATED	2025-11-04 12:45:10.001821+01
56d11ead-ba45-4c6a-aa92-fb77de82d42d	b46bba4b-525d-483d-bf4e-f195bde3d6bc	2025-04-03	\N	\N	\N	601.730000	\N	GENERATED	2025-11-04 12:45:10.002487+01
b05da288-237f-4543-abaf-c9bb90fe842d	b46bba4b-525d-483d-bf4e-f195bde3d6bc	2025-04-04	\N	\N	\N	603.500000	\N	GENERATED	2025-11-04 12:45:10.003161+01
8c9dee47-0417-4c58-a12a-e3b732897d57	b46bba4b-525d-483d-bf4e-f195bde3d6bc	2025-04-05	\N	\N	\N	594.690000	\N	GENERATED	2025-11-04 12:45:10.003864+01
6d18e099-0432-438c-8f2e-f2170f2c0244	b46bba4b-525d-483d-bf4e-f195bde3d6bc	2025-04-06	\N	\N	\N	605.030000	\N	GENERATED	2025-11-04 12:45:10.004514+01
e525de5b-410c-4351-ba0e-96ed39a6f193	b46bba4b-525d-483d-bf4e-f195bde3d6bc	2025-04-07	\N	\N	\N	597.880000	\N	GENERATED	2025-11-04 12:45:10.005175+01
fca6e3b4-e106-4a02-aecb-3fde9d733e8e	b46bba4b-525d-483d-bf4e-f195bde3d6bc	2025-04-08	\N	\N	\N	598.600000	\N	GENERATED	2025-11-04 12:45:10.005832+01
d36f6921-4c7c-472b-bd60-915e51999ebd	b46bba4b-525d-483d-bf4e-f195bde3d6bc	2025-04-09	\N	\N	\N	603.670000	\N	GENERATED	2025-11-04 12:45:10.006604+01
46e3909f-05ee-496f-9fc4-4212b1cde7d8	b46bba4b-525d-483d-bf4e-f195bde3d6bc	2025-04-10	\N	\N	\N	594.820000	\N	GENERATED	2025-11-04 12:45:10.007308+01
6523a087-5916-43f8-902e-b7bd687a907d	b46bba4b-525d-483d-bf4e-f195bde3d6bc	2025-04-11	\N	\N	\N	597.030000	\N	GENERATED	2025-11-04 12:45:10.007977+01
068fe5ea-c541-46c6-8a0d-9ac293401e67	b46bba4b-525d-483d-bf4e-f195bde3d6bc	2025-04-12	\N	\N	\N	597.680000	\N	GENERATED	2025-11-04 12:45:10.008899+01
e5cb67a4-c938-4b38-9acb-d4278bac09c3	b46bba4b-525d-483d-bf4e-f195bde3d6bc	2025-04-13	\N	\N	\N	596.790000	\N	GENERATED	2025-11-04 12:45:10.009937+01
146033f8-e060-44d5-bfef-47e379dd0e51	b46bba4b-525d-483d-bf4e-f195bde3d6bc	2025-04-14	\N	\N	\N	599.420000	\N	GENERATED	2025-11-04 12:45:10.010649+01
6e713e62-bffd-4702-a362-0c605866ff0c	b46bba4b-525d-483d-bf4e-f195bde3d6bc	2025-04-15	\N	\N	\N	601.650000	\N	GENERATED	2025-11-04 12:45:10.011357+01
18f47091-5ee8-4856-8847-26c3ad10029b	b46bba4b-525d-483d-bf4e-f195bde3d6bc	2025-04-16	\N	\N	\N	596.550000	\N	GENERATED	2025-11-04 12:45:10.012087+01
a17dc090-597c-4288-a4ac-6192c885d7df	b46bba4b-525d-483d-bf4e-f195bde3d6bc	2025-04-17	\N	\N	\N	602.330000	\N	GENERATED	2025-11-04 12:45:10.012772+01
746213a4-5146-4682-9ed9-7789bf4692e0	b46bba4b-525d-483d-bf4e-f195bde3d6bc	2025-04-18	\N	\N	\N	598.180000	\N	GENERATED	2025-11-04 12:45:10.013459+01
4aadd673-f309-40f8-94fb-270f7282d0ef	b46bba4b-525d-483d-bf4e-f195bde3d6bc	2025-04-19	\N	\N	\N	604.450000	\N	GENERATED	2025-11-04 12:45:10.014151+01
9faf9653-980a-4552-9820-a9f2d945825b	b46bba4b-525d-483d-bf4e-f195bde3d6bc	2025-04-20	\N	\N	\N	599.810000	\N	GENERATED	2025-11-04 12:45:10.014847+01
0b91f22d-1ed6-41c1-9846-aba0f9db34a2	b46bba4b-525d-483d-bf4e-f195bde3d6bc	2025-04-21	\N	\N	\N	595.760000	\N	GENERATED	2025-11-04 12:45:10.015629+01
34e69f8d-a4e0-430c-b41b-c521cba185b7	b46bba4b-525d-483d-bf4e-f195bde3d6bc	2025-04-22	\N	\N	\N	602.910000	\N	GENERATED	2025-11-04 12:45:10.016311+01
05d96e36-af7c-435f-be7b-f6362e3a8067	b46bba4b-525d-483d-bf4e-f195bde3d6bc	2025-04-23	\N	\N	\N	607.110000	\N	GENERATED	2025-11-04 12:45:10.01697+01
1c07fd4d-3a3c-48ff-8142-5e567e7e61a2	b46bba4b-525d-483d-bf4e-f195bde3d6bc	2025-04-24	\N	\N	\N	607.290000	\N	GENERATED	2025-11-04 12:45:10.017637+01
e76930a8-be4a-4bbf-a9fe-284b3300eb42	b46bba4b-525d-483d-bf4e-f195bde3d6bc	2025-04-25	\N	\N	\N	596.080000	\N	GENERATED	2025-11-04 12:45:10.018292+01
f107706f-0e72-46ab-9f2a-5088ff02cab6	b46bba4b-525d-483d-bf4e-f195bde3d6bc	2025-04-26	\N	\N	\N	601.300000	\N	GENERATED	2025-11-04 12:45:10.018966+01
0be89f6d-17a3-45d8-bb01-ea50669a5764	b46bba4b-525d-483d-bf4e-f195bde3d6bc	2025-04-27	\N	\N	\N	599.780000	\N	GENERATED	2025-11-04 12:45:10.019636+01
c6535104-9c24-485f-bacb-b22a17df094b	b46bba4b-525d-483d-bf4e-f195bde3d6bc	2025-04-28	\N	\N	\N	603.790000	\N	GENERATED	2025-11-04 12:45:10.020299+01
2ddd62e0-a551-43c9-b82e-ba023e2a312c	b46bba4b-525d-483d-bf4e-f195bde3d6bc	2025-04-29	\N	\N	\N	604.380000	\N	GENERATED	2025-11-04 12:45:10.020958+01
67d85831-cae1-431c-83b6-b442d7cbb7fb	b46bba4b-525d-483d-bf4e-f195bde3d6bc	2025-04-30	\N	\N	\N	601.410000	\N	GENERATED	2025-11-04 12:45:10.021657+01
5aa411b3-d7d2-453c-ae23-548c6952b941	b46bba4b-525d-483d-bf4e-f195bde3d6bc	2025-05-01	\N	\N	\N	600.420000	\N	GENERATED	2025-11-04 12:45:10.02235+01
9fa7d4e0-a3fd-49c1-b97d-71bafb89bf8c	b46bba4b-525d-483d-bf4e-f195bde3d6bc	2025-05-02	\N	\N	\N	603.860000	\N	GENERATED	2025-11-04 12:45:10.023011+01
68c66fb7-3b84-45f1-96af-fcf517c780ed	b46bba4b-525d-483d-bf4e-f195bde3d6bc	2025-05-03	\N	\N	\N	597.140000	\N	GENERATED	2025-11-04 12:45:10.023683+01
2bebc900-afa0-4d6a-80cd-ecbac121349e	b46bba4b-525d-483d-bf4e-f195bde3d6bc	2025-05-04	\N	\N	\N	599.560000	\N	GENERATED	2025-11-04 12:45:10.024611+01
688bcc23-dc98-4519-a4e3-50f4877ac39a	b46bba4b-525d-483d-bf4e-f195bde3d6bc	2025-05-05	\N	\N	\N	597.440000	\N	GENERATED	2025-11-04 12:45:10.025894+01
212fe7b3-befe-44f1-8b81-d6253011cb80	b46bba4b-525d-483d-bf4e-f195bde3d6bc	2025-05-06	\N	\N	\N	606.600000	\N	GENERATED	2025-11-04 12:45:10.026663+01
0cd27aa4-5329-4f5f-8820-908906c1c3eb	b46bba4b-525d-483d-bf4e-f195bde3d6bc	2025-05-07	\N	\N	\N	601.530000	\N	GENERATED	2025-11-04 12:45:10.02734+01
72cc470d-892c-4ccb-b01e-1df627031493	b46bba4b-525d-483d-bf4e-f195bde3d6bc	2025-05-08	\N	\N	\N	598.190000	\N	GENERATED	2025-11-04 12:45:10.028017+01
209c3468-d79d-4742-8acb-488e71ae7819	b46bba4b-525d-483d-bf4e-f195bde3d6bc	2025-05-09	\N	\N	\N	602.660000	\N	GENERATED	2025-11-04 12:45:10.028705+01
8e0c7701-4fcf-40ff-a08c-5d68989aca1c	b46bba4b-525d-483d-bf4e-f195bde3d6bc	2025-05-10	\N	\N	\N	598.210000	\N	GENERATED	2025-11-04 12:45:10.029372+01
145e0a02-9fa5-4ef3-9c06-813d3ca48075	b46bba4b-525d-483d-bf4e-f195bde3d6bc	2025-05-11	\N	\N	\N	607.870000	\N	GENERATED	2025-11-04 12:45:10.030044+01
738aba2b-88e9-47b4-8b1b-8ad6a8784029	b46bba4b-525d-483d-bf4e-f195bde3d6bc	2025-05-12	\N	\N	\N	608.630000	\N	GENERATED	2025-11-04 12:45:10.03071+01
86df896d-a4cb-48cb-9fe2-2d8ba6fe374d	b46bba4b-525d-483d-bf4e-f195bde3d6bc	2025-05-13	\N	\N	\N	600.110000	\N	GENERATED	2025-11-04 12:45:10.031462+01
02740b8c-3a49-407f-8e41-1f51b87bc855	b46bba4b-525d-483d-bf4e-f195bde3d6bc	2025-05-14	\N	\N	\N	601.310000	\N	GENERATED	2025-11-04 12:45:10.032223+01
b51ba2b1-4916-4753-b7d8-8ae4ea6e70f6	b46bba4b-525d-483d-bf4e-f195bde3d6bc	2025-05-15	\N	\N	\N	608.200000	\N	GENERATED	2025-11-04 12:45:10.032902+01
8f0bbea0-e4d5-4b58-909c-8b845dd64c18	b46bba4b-525d-483d-bf4e-f195bde3d6bc	2025-05-16	\N	\N	\N	602.220000	\N	GENERATED	2025-11-04 12:45:10.033597+01
e217e397-cb74-4adf-8be7-38fbbce8801c	b46bba4b-525d-483d-bf4e-f195bde3d6bc	2025-05-17	\N	\N	\N	603.180000	\N	GENERATED	2025-11-04 12:45:10.034253+01
04575838-68a9-4dd8-991c-1f6a106c8234	b46bba4b-525d-483d-bf4e-f195bde3d6bc	2025-05-18	\N	\N	\N	608.150000	\N	GENERATED	2025-11-04 12:45:10.034907+01
22e8679e-53d3-44f3-8010-b780c96d87b5	b46bba4b-525d-483d-bf4e-f195bde3d6bc	2025-05-19	\N	\N	\N	601.150000	\N	GENERATED	2025-11-04 12:45:10.035572+01
b3372110-bf2b-43db-8093-492b38df8157	b46bba4b-525d-483d-bf4e-f195bde3d6bc	2025-05-20	\N	\N	\N	602.030000	\N	GENERATED	2025-11-04 12:45:10.036231+01
b7967ec4-faaa-470c-b936-ae4ac6510e65	b46bba4b-525d-483d-bf4e-f195bde3d6bc	2025-05-21	\N	\N	\N	608.250000	\N	GENERATED	2025-11-04 12:45:10.036898+01
32533a29-d0d2-4c85-a7aa-33cfedf09a50	b46bba4b-525d-483d-bf4e-f195bde3d6bc	2025-05-22	\N	\N	\N	602.710000	\N	GENERATED	2025-11-04 12:45:10.037598+01
882f7eaf-522f-4c9d-b542-b5d95d219b85	b46bba4b-525d-483d-bf4e-f195bde3d6bc	2025-05-23	\N	\N	\N	600.130000	\N	GENERATED	2025-11-04 12:45:10.038261+01
35976055-16cb-4209-8263-dd90c8820391	b46bba4b-525d-483d-bf4e-f195bde3d6bc	2025-05-24	\N	\N	\N	600.730000	\N	GENERATED	2025-11-04 12:45:10.03893+01
e62776c9-029c-4335-a44e-18da4a92b10e	b46bba4b-525d-483d-bf4e-f195bde3d6bc	2025-05-25	\N	\N	\N	609.860000	\N	GENERATED	2025-11-04 12:45:10.039648+01
39c571d9-30a2-4c01-a085-4b26d981e52d	b46bba4b-525d-483d-bf4e-f195bde3d6bc	2025-05-26	\N	\N	\N	607.910000	\N	GENERATED	2025-11-04 12:45:10.040506+01
085733f7-b3f9-4b27-bc6e-74b1d4a1c5a2	b46bba4b-525d-483d-bf4e-f195bde3d6bc	2025-05-27	\N	\N	\N	611.620000	\N	GENERATED	2025-11-04 12:45:10.041223+01
33e42d35-65d6-4821-b24e-4fa992851dfd	b46bba4b-525d-483d-bf4e-f195bde3d6bc	2025-05-28	\N	\N	\N	609.020000	\N	GENERATED	2025-11-04 12:45:10.041941+01
bc537d14-100a-45a3-8358-f48282abcce0	b46bba4b-525d-483d-bf4e-f195bde3d6bc	2025-05-29	\N	\N	\N	605.670000	\N	GENERATED	2025-11-04 12:45:10.042802+01
7c211156-85d2-4c27-916c-dc77726975c8	b46bba4b-525d-483d-bf4e-f195bde3d6bc	2025-05-30	\N	\N	\N	608.620000	\N	GENERATED	2025-11-04 12:45:10.043599+01
9b8393ae-d636-4155-9d8a-876d757fd85e	b46bba4b-525d-483d-bf4e-f195bde3d6bc	2025-05-31	\N	\N	\N	611.900000	\N	GENERATED	2025-11-04 12:45:10.044362+01
ada47327-7fc7-4618-8dfb-802afe5d4064	b46bba4b-525d-483d-bf4e-f195bde3d6bc	2025-06-01	\N	\N	\N	611.970000	\N	GENERATED	2025-11-04 12:45:10.04507+01
d7d259a6-b916-476d-b95f-ce69de0b4eb0	b46bba4b-525d-483d-bf4e-f195bde3d6bc	2025-06-02	\N	\N	\N	607.680000	\N	GENERATED	2025-11-04 12:45:10.045755+01
34dd93ad-fd4f-41e7-9765-a2d20866d9d7	b46bba4b-525d-483d-bf4e-f195bde3d6bc	2025-06-03	\N	\N	\N	607.110000	\N	GENERATED	2025-11-04 12:45:10.046472+01
d9a21ceb-1ba9-419f-8cae-4015bf3c0230	b46bba4b-525d-483d-bf4e-f195bde3d6bc	2025-06-04	\N	\N	\N	602.000000	\N	GENERATED	2025-11-04 12:45:10.047164+01
4a831265-6f19-416f-91d3-47c8b2f690f6	b46bba4b-525d-483d-bf4e-f195bde3d6bc	2025-06-05	\N	\N	\N	607.510000	\N	GENERATED	2025-11-04 12:45:10.047839+01
619b51f8-4ced-498c-8e1f-6ddcbde34ac6	b46bba4b-525d-483d-bf4e-f195bde3d6bc	2025-06-06	\N	\N	\N	610.950000	\N	GENERATED	2025-11-04 12:45:10.048521+01
806ae9db-6c50-403e-b036-f6e7ec9b87ae	b46bba4b-525d-483d-bf4e-f195bde3d6bc	2025-06-07	\N	\N	\N	604.350000	\N	GENERATED	2025-11-04 12:45:10.049193+01
6e916ccd-d302-4465-9c4c-3e2119d98fd3	b46bba4b-525d-483d-bf4e-f195bde3d6bc	2025-06-08	\N	\N	\N	604.960000	\N	GENERATED	2025-11-04 12:45:10.050429+01
ee1ac16e-c7ea-4683-ba64-27496bfb71c2	b46bba4b-525d-483d-bf4e-f195bde3d6bc	2025-06-09	\N	\N	\N	609.190000	\N	GENERATED	2025-11-04 12:45:10.0511+01
c2765058-97b7-4024-b618-99e0b1dc9fb0	b46bba4b-525d-483d-bf4e-f195bde3d6bc	2025-06-10	\N	\N	\N	611.710000	\N	GENERATED	2025-11-04 12:45:10.051866+01
9b50a283-2309-4efc-a84f-ca2b453731c5	b46bba4b-525d-483d-bf4e-f195bde3d6bc	2025-06-11	\N	\N	\N	604.970000	\N	GENERATED	2025-11-04 12:45:10.052585+01
264f613b-af06-4f0a-9f3c-ab701ecd2b25	b46bba4b-525d-483d-bf4e-f195bde3d6bc	2025-06-12	\N	\N	\N	604.470000	\N	GENERATED	2025-11-04 12:45:10.053264+01
75de18ec-03ae-4141-ad57-6de3d096fea7	b46bba4b-525d-483d-bf4e-f195bde3d6bc	2025-06-13	\N	\N	\N	608.280000	\N	GENERATED	2025-11-04 12:45:10.054385+01
7e40247a-b49d-4ded-8c8a-207e7b9a989c	b46bba4b-525d-483d-bf4e-f195bde3d6bc	2025-06-14	\N	\N	\N	613.920000	\N	GENERATED	2025-11-04 12:45:10.055073+01
5bcb5437-0453-4e02-81a3-2220a142e3ef	b46bba4b-525d-483d-bf4e-f195bde3d6bc	2025-06-15	\N	\N	\N	610.220000	\N	GENERATED	2025-11-04 12:45:10.055919+01
71022e9c-5ab6-45e5-b969-d813a64ad8cd	b46bba4b-525d-483d-bf4e-f195bde3d6bc	2025-06-16	\N	\N	\N	607.260000	\N	GENERATED	2025-11-04 12:45:10.05661+01
9d382df9-873a-4b0c-8223-d005440dc2af	b46bba4b-525d-483d-bf4e-f195bde3d6bc	2025-06-17	\N	\N	\N	604.230000	\N	GENERATED	2025-11-04 12:45:10.057289+01
fa42c582-c96c-4585-9045-2a6071822d06	b46bba4b-525d-483d-bf4e-f195bde3d6bc	2025-06-18	\N	\N	\N	612.470000	\N	GENERATED	2025-11-04 12:45:10.057978+01
6c9301b2-cce5-4a6e-8546-b39537887e38	b46bba4b-525d-483d-bf4e-f195bde3d6bc	2025-06-19	\N	\N	\N	608.380000	\N	GENERATED	2025-11-04 12:45:10.058658+01
5d5ad311-aa9c-4b1b-bc51-c808ece1624f	b46bba4b-525d-483d-bf4e-f195bde3d6bc	2025-06-20	\N	\N	\N	612.590000	\N	GENERATED	2025-11-04 12:45:10.059358+01
0d691012-51de-4873-bb7d-f22772702b18	b46bba4b-525d-483d-bf4e-f195bde3d6bc	2025-06-21	\N	\N	\N	605.200000	\N	GENERATED	2025-11-04 12:45:10.060225+01
a47619fe-27f8-4811-8a05-17cc6ea33db8	b46bba4b-525d-483d-bf4e-f195bde3d6bc	2025-06-22	\N	\N	\N	615.030000	\N	GENERATED	2025-11-04 12:45:10.061092+01
a7bed180-c660-424b-91c5-a6adc9dc3386	b46bba4b-525d-483d-bf4e-f195bde3d6bc	2025-06-23	\N	\N	\N	612.040000	\N	GENERATED	2025-11-04 12:45:10.061783+01
382a8331-09ad-4eb5-bb6e-c9d14eb92b64	b46bba4b-525d-483d-bf4e-f195bde3d6bc	2025-06-24	\N	\N	\N	606.500000	\N	GENERATED	2025-11-04 12:45:10.062466+01
81351f58-ac54-4230-8d20-6b4cf2afe071	b46bba4b-525d-483d-bf4e-f195bde3d6bc	2025-06-25	\N	\N	\N	605.290000	\N	GENERATED	2025-11-04 12:45:10.063156+01
b34e188b-57fe-43ff-8e1f-f0521933616a	b46bba4b-525d-483d-bf4e-f195bde3d6bc	2025-06-26	\N	\N	\N	605.470000	\N	GENERATED	2025-11-04 12:45:10.063828+01
0095007c-ddd4-49cf-a0bc-4e8e3fedf067	b46bba4b-525d-483d-bf4e-f195bde3d6bc	2025-06-27	\N	\N	\N	604.250000	\N	GENERATED	2025-11-04 12:45:10.064507+01
7cf01278-67be-4b1d-b45e-ca0c2ead6142	b46bba4b-525d-483d-bf4e-f195bde3d6bc	2025-06-28	\N	\N	\N	613.780000	\N	GENERATED	2025-11-04 12:45:10.065165+01
0b03c469-8fb7-44d5-9199-08b91e99051c	b46bba4b-525d-483d-bf4e-f195bde3d6bc	2025-06-29	\N	\N	\N	609.620000	\N	GENERATED	2025-11-04 12:45:10.065832+01
a9265060-18bf-4e2a-b0f6-488b10252401	b46bba4b-525d-483d-bf4e-f195bde3d6bc	2025-06-30	\N	\N	\N	611.910000	\N	GENERATED	2025-11-04 12:45:10.066499+01
1451e765-1f6e-4b5b-b84a-fad8fe33be18	b46bba4b-525d-483d-bf4e-f195bde3d6bc	2025-07-01	\N	\N	\N	606.890000	\N	GENERATED	2025-11-04 12:45:10.067264+01
f9ced836-5e64-4c5b-9e51-9e271f336776	b46bba4b-525d-483d-bf4e-f195bde3d6bc	2025-07-02	\N	\N	\N	604.950000	\N	GENERATED	2025-11-04 12:45:10.067981+01
111ee335-d9a7-45ec-92c3-8f97fb6ee48d	b46bba4b-525d-483d-bf4e-f195bde3d6bc	2025-07-03	\N	\N	\N	607.080000	\N	GENERATED	2025-11-04 12:45:10.068654+01
12f663ad-cde3-4bb6-b3ec-976dfb4a4180	b46bba4b-525d-483d-bf4e-f195bde3d6bc	2025-07-04	\N	\N	\N	605.580000	\N	GENERATED	2025-11-04 12:45:10.069316+01
f201f80c-05a6-4cee-beee-563fac7b3ae1	b46bba4b-525d-483d-bf4e-f195bde3d6bc	2025-07-05	\N	\N	\N	609.360000	\N	GENERATED	2025-11-04 12:45:10.069988+01
f84fc8ba-61a5-4f41-8f2e-7b81c10163f9	b46bba4b-525d-483d-bf4e-f195bde3d6bc	2025-07-06	\N	\N	\N	608.190000	\N	GENERATED	2025-11-04 12:45:10.070731+01
29ddf474-a402-49ff-af19-f119fb3d3501	b46bba4b-525d-483d-bf4e-f195bde3d6bc	2025-07-07	\N	\N	\N	609.160000	\N	GENERATED	2025-11-04 12:45:10.071458+01
79b2c251-ab93-4f43-973e-bfb1cc13b356	b46bba4b-525d-483d-bf4e-f195bde3d6bc	2025-07-08	\N	\N	\N	616.430000	\N	GENERATED	2025-11-04 12:45:10.072221+01
2611dc92-97aa-4538-b8e8-6a52102dc8a7	b46bba4b-525d-483d-bf4e-f195bde3d6bc	2025-07-09	\N	\N	\N	614.040000	\N	GENERATED	2025-11-04 12:45:10.072914+01
e6ea75d0-fcd9-41e3-a8e3-1f84803e0fa0	b46bba4b-525d-483d-bf4e-f195bde3d6bc	2025-07-10	\N	\N	\N	610.670000	\N	GENERATED	2025-11-04 12:45:10.07359+01
901d3988-be58-4eb8-9977-82ee3f0c52f7	b46bba4b-525d-483d-bf4e-f195bde3d6bc	2025-07-11	\N	\N	\N	607.590000	\N	GENERATED	2025-11-04 12:45:10.074257+01
59e671f0-1e3d-4f12-857e-76f9c4bdbcf0	b46bba4b-525d-483d-bf4e-f195bde3d6bc	2025-07-12	\N	\N	\N	611.510000	\N	GENERATED	2025-11-04 12:45:10.074934+01
75f39e04-0c0b-4f28-8307-1dae86d6a41e	b46bba4b-525d-483d-bf4e-f195bde3d6bc	2025-07-13	\N	\N	\N	613.890000	\N	GENERATED	2025-11-04 12:45:10.075601+01
d773bfa6-7e35-4409-9559-b4b5fbf23cda	b46bba4b-525d-483d-bf4e-f195bde3d6bc	2025-07-14	\N	\N	\N	611.750000	\N	GENERATED	2025-11-04 12:45:10.076265+01
0c1f332e-be13-4b7b-b6b6-b3675bfed882	b46bba4b-525d-483d-bf4e-f195bde3d6bc	2025-07-15	\N	\N	\N	611.900000	\N	GENERATED	2025-11-04 12:45:10.07693+01
616ab029-b6d2-4460-93e5-9add0b0353f5	b46bba4b-525d-483d-bf4e-f195bde3d6bc	2025-07-16	\N	\N	\N	616.960000	\N	GENERATED	2025-11-04 12:45:10.077596+01
85a8f025-9522-41f6-8f20-a469e45761d5	b46bba4b-525d-483d-bf4e-f195bde3d6bc	2025-07-17	\N	\N	\N	617.170000	\N	GENERATED	2025-11-04 12:45:10.078291+01
1f6b59a2-fc01-4a02-8577-206b23fc0b32	b46bba4b-525d-483d-bf4e-f195bde3d6bc	2025-07-18	\N	\N	\N	609.970000	\N	GENERATED	2025-11-04 12:45:10.07898+01
0dd4c4d0-d3aa-4043-8d9d-e32f620fa91e	b46bba4b-525d-483d-bf4e-f195bde3d6bc	2025-07-19	\N	\N	\N	609.410000	\N	GENERATED	2025-11-04 12:45:10.079651+01
91e3d760-5fe4-43d4-a9bb-e62e139a7dc7	b46bba4b-525d-483d-bf4e-f195bde3d6bc	2025-07-20	\N	\N	\N	612.850000	\N	GENERATED	2025-11-04 12:45:10.080329+01
26d07875-66e9-4454-951f-81ab9534e93e	b46bba4b-525d-483d-bf4e-f195bde3d6bc	2025-07-21	\N	\N	\N	613.870000	\N	GENERATED	2025-11-04 12:45:10.081001+01
bfc51641-1b18-4113-ae44-649b90c61d75	b46bba4b-525d-483d-bf4e-f195bde3d6bc	2025-07-22	\N	\N	\N	607.630000	\N	GENERATED	2025-11-04 12:45:10.081669+01
f44a6f0f-c12c-4fee-bf1b-e7481a7a070e	b46bba4b-525d-483d-bf4e-f195bde3d6bc	2025-07-23	\N	\N	\N	610.410000	\N	GENERATED	2025-11-04 12:45:10.082367+01
18167031-e23d-4e47-afe7-46a3d7cddbe5	b46bba4b-525d-483d-bf4e-f195bde3d6bc	2025-07-24	\N	\N	\N	615.650000	\N	GENERATED	2025-11-04 12:45:10.083107+01
bc38e88d-395d-4622-9156-008832b80c90	b46bba4b-525d-483d-bf4e-f195bde3d6bc	2025-07-25	\N	\N	\N	619.230000	\N	GENERATED	2025-11-04 12:45:10.083821+01
248ad92f-1062-4259-80a7-e51adcc8e21b	b46bba4b-525d-483d-bf4e-f195bde3d6bc	2025-07-26	\N	\N	\N	612.080000	\N	GENERATED	2025-11-04 12:45:10.084498+01
53b57f41-fc9e-4331-ab16-cbba8e90cff1	b46bba4b-525d-483d-bf4e-f195bde3d6bc	2025-07-27	\N	\N	\N	617.360000	\N	GENERATED	2025-11-04 12:45:10.085204+01
86ad92c3-f7e6-4dda-985e-0beb2eb746a3	b46bba4b-525d-483d-bf4e-f195bde3d6bc	2025-07-28	\N	\N	\N	617.950000	\N	GENERATED	2025-11-04 12:45:10.086135+01
a8528398-6ea4-4b83-a383-e953596ccadd	b46bba4b-525d-483d-bf4e-f195bde3d6bc	2025-07-29	\N	\N	\N	608.460000	\N	GENERATED	2025-11-04 12:45:10.087149+01
f896b9d5-4e21-455d-8995-0cc60a17555b	b46bba4b-525d-483d-bf4e-f195bde3d6bc	2025-07-30	\N	\N	\N	609.060000	\N	GENERATED	2025-11-04 12:45:10.087861+01
8ece2c47-033d-4cf1-aa83-bcb802f478a0	b46bba4b-525d-483d-bf4e-f195bde3d6bc	2025-07-31	\N	\N	\N	619.490000	\N	GENERATED	2025-11-04 12:45:10.088565+01
0d9e7e15-303a-4e67-b772-cadbf45b1d91	b46bba4b-525d-483d-bf4e-f195bde3d6bc	2025-08-01	\N	\N	\N	609.070000	\N	GENERATED	2025-11-04 12:45:10.089265+01
1315eb6c-b5fd-49ba-9067-c70587daef65	b46bba4b-525d-483d-bf4e-f195bde3d6bc	2025-08-02	\N	\N	\N	612.960000	\N	GENERATED	2025-11-04 12:45:10.089937+01
bbdec828-6ca0-46c4-b65a-6e4e8b32eb74	b46bba4b-525d-483d-bf4e-f195bde3d6bc	2025-08-03	\N	\N	\N	619.300000	\N	GENERATED	2025-11-04 12:45:10.090599+01
c6fc0231-744c-4857-bf06-a5efb91441fb	b46bba4b-525d-483d-bf4e-f195bde3d6bc	2025-08-04	\N	\N	\N	613.480000	\N	GENERATED	2025-11-04 12:45:10.091463+01
5d0656cc-aa9c-40b9-bd61-9070501b1d48	b46bba4b-525d-483d-bf4e-f195bde3d6bc	2025-08-05	\N	\N	\N	619.290000	\N	GENERATED	2025-11-04 12:45:10.092194+01
fe1fe369-03d6-4c11-822b-7003e12bc7d5	b46bba4b-525d-483d-bf4e-f195bde3d6bc	2025-08-06	\N	\N	\N	618.370000	\N	GENERATED	2025-11-04 12:45:10.092854+01
e4755b40-c377-458f-8e00-80b266a46f4d	b46bba4b-525d-483d-bf4e-f195bde3d6bc	2025-08-07	\N	\N	\N	619.320000	\N	GENERATED	2025-11-04 12:45:10.093525+01
efcd0d31-cf60-414b-9bd2-d8a3776b55ab	b46bba4b-525d-483d-bf4e-f195bde3d6bc	2025-08-08	\N	\N	\N	610.970000	\N	GENERATED	2025-11-04 12:45:10.094195+01
8a493bce-94e1-4787-b6f2-7e9dce302d80	b46bba4b-525d-483d-bf4e-f195bde3d6bc	2025-08-09	\N	\N	\N	609.840000	\N	GENERATED	2025-11-04 12:45:10.094874+01
d5eacb55-3e66-43b7-8218-2e0cad1facc5	b46bba4b-525d-483d-bf4e-f195bde3d6bc	2025-08-10	\N	\N	\N	617.140000	\N	GENERATED	2025-11-04 12:45:10.095541+01
6be68311-0a45-40b1-b646-e044070dd86f	b46bba4b-525d-483d-bf4e-f195bde3d6bc	2025-08-11	\N	\N	\N	621.140000	\N	GENERATED	2025-11-04 12:45:10.096197+01
abd42ddd-b9c0-472b-bb5f-a25541e6d55b	b46bba4b-525d-483d-bf4e-f195bde3d6bc	2025-08-12	\N	\N	\N	620.620000	\N	GENERATED	2025-11-04 12:45:10.097162+01
1b448102-0342-4e01-8ce1-f67aa0c87a1e	b46bba4b-525d-483d-bf4e-f195bde3d6bc	2025-08-13	\N	\N	\N	619.340000	\N	GENERATED	2025-11-04 12:45:10.097867+01
d70a0eee-adee-41f0-959a-22d7493f0b7a	b46bba4b-525d-483d-bf4e-f195bde3d6bc	2025-08-14	\N	\N	\N	617.150000	\N	GENERATED	2025-11-04 12:45:10.098579+01
78d98117-808a-4496-8f93-31a6259b3747	b46bba4b-525d-483d-bf4e-f195bde3d6bc	2025-08-15	\N	\N	\N	621.130000	\N	GENERATED	2025-11-04 12:45:10.099245+01
3f12103d-3832-486f-8fa5-73a20b7a4829	b46bba4b-525d-483d-bf4e-f195bde3d6bc	2025-08-16	\N	\N	\N	611.180000	\N	GENERATED	2025-11-04 12:45:10.099922+01
72e44a27-083c-492a-aa65-784a6178cedc	b46bba4b-525d-483d-bf4e-f195bde3d6bc	2025-08-17	\N	\N	\N	620.440000	\N	GENERATED	2025-11-04 12:45:10.100593+01
fec9d084-9b10-460f-8b3f-3f8f21b58b0c	b46bba4b-525d-483d-bf4e-f195bde3d6bc	2025-08-18	\N	\N	\N	619.420000	\N	GENERATED	2025-11-04 12:45:10.101275+01
8da32f51-a67c-4667-9835-294a9f404930	b46bba4b-525d-483d-bf4e-f195bde3d6bc	2025-08-19	\N	\N	\N	620.150000	\N	GENERATED	2025-11-04 12:45:10.101993+01
b593682e-c3d0-4d6f-b623-15905e7c359e	b46bba4b-525d-483d-bf4e-f195bde3d6bc	2025-08-20	\N	\N	\N	613.290000	\N	GENERATED	2025-11-04 12:45:10.102673+01
9360288a-ab4d-4bd1-8576-9153e2db68cd	b46bba4b-525d-483d-bf4e-f195bde3d6bc	2025-08-21	\N	\N	\N	615.530000	\N	GENERATED	2025-11-04 12:45:10.103572+01
7591bd5d-6081-4560-8966-2f770417cdf9	b46bba4b-525d-483d-bf4e-f195bde3d6bc	2025-08-22	\N	\N	\N	615.810000	\N	GENERATED	2025-11-04 12:45:10.104239+01
375b515f-2920-4520-819b-c573efaf5e30	b46bba4b-525d-483d-bf4e-f195bde3d6bc	2025-08-23	\N	\N	\N	611.720000	\N	GENERATED	2025-11-04 12:45:10.104922+01
0b82ff38-354c-4e4d-9cfc-404dd78416b6	b46bba4b-525d-483d-bf4e-f195bde3d6bc	2025-08-24	\N	\N	\N	621.330000	\N	GENERATED	2025-11-04 12:45:10.105585+01
47b538af-3053-4947-b45d-48134ce46d81	b46bba4b-525d-483d-bf4e-f195bde3d6bc	2025-08-25	\N	\N	\N	615.000000	\N	GENERATED	2025-11-04 12:45:10.106236+01
6d392ea2-774b-4912-98d7-80e09dd51ef7	b46bba4b-525d-483d-bf4e-f195bde3d6bc	2025-08-26	\N	\N	\N	622.890000	\N	GENERATED	2025-11-04 12:45:10.106899+01
ff1ab575-6de7-45a7-ad86-c1e1f2dfeed8	b46bba4b-525d-483d-bf4e-f195bde3d6bc	2025-08-27	\N	\N	\N	622.970000	\N	GENERATED	2025-11-04 12:45:10.10756+01
ec6eb324-c49c-4aa3-9ca2-a523d7843046	b46bba4b-525d-483d-bf4e-f195bde3d6bc	2025-08-28	\N	\N	\N	614.390000	\N	GENERATED	2025-11-04 12:45:10.10822+01
b3d3e9bf-a5ca-4f6c-8a10-1e64dd574b47	b46bba4b-525d-483d-bf4e-f195bde3d6bc	2025-08-29	\N	\N	\N	616.990000	\N	GENERATED	2025-11-04 12:45:10.108878+01
092ab4d8-a386-4eab-bf7e-0780421c9551	b46bba4b-525d-483d-bf4e-f195bde3d6bc	2025-08-30	\N	\N	\N	613.620000	\N	GENERATED	2025-11-04 12:45:10.109547+01
e0c23df7-f5a3-42f4-873f-a79ef129d53f	b46bba4b-525d-483d-bf4e-f195bde3d6bc	2025-08-31	\N	\N	\N	613.160000	\N	GENERATED	2025-11-04 12:45:10.110201+01
dda20bb3-98b0-4388-89af-167a0ccfe7df	b46bba4b-525d-483d-bf4e-f195bde3d6bc	2025-09-01	\N	\N	\N	615.510000	\N	GENERATED	2025-11-04 12:45:10.110857+01
d7cc95b7-1726-420a-9514-dc92906c64c0	b46bba4b-525d-483d-bf4e-f195bde3d6bc	2025-09-02	\N	\N	\N	618.850000	\N	GENERATED	2025-11-04 12:45:10.111527+01
762293d5-7d0b-4a0f-bfa1-8eb92e155179	b46bba4b-525d-483d-bf4e-f195bde3d6bc	2025-09-03	\N	\N	\N	619.470000	\N	GENERATED	2025-11-04 12:45:10.112282+01
c8f059a1-9499-42b9-b24e-5eb3a423e3ab	b46bba4b-525d-483d-bf4e-f195bde3d6bc	2025-09-04	\N	\N	\N	622.560000	\N	GENERATED	2025-11-04 12:45:10.112943+01
5e6c49a0-ba6b-4fb7-a38e-a09aca024f24	b46bba4b-525d-483d-bf4e-f195bde3d6bc	2025-09-05	\N	\N	\N	623.580000	\N	GENERATED	2025-11-04 12:45:10.11361+01
e547ffd9-47fa-4c2f-97e5-f19a60cccff1	b46bba4b-525d-483d-bf4e-f195bde3d6bc	2025-09-06	\N	\N	\N	618.900000	\N	GENERATED	2025-11-04 12:45:10.114286+01
93d56059-6ebd-48f3-b9df-0ae33b87710d	b46bba4b-525d-483d-bf4e-f195bde3d6bc	2025-09-07	\N	\N	\N	620.900000	\N	GENERATED	2025-11-04 12:45:10.114955+01
f8c6de90-4909-4f4e-bd91-d1112df1f5ae	b46bba4b-525d-483d-bf4e-f195bde3d6bc	2025-09-08	\N	\N	\N	616.330000	\N	GENERATED	2025-11-04 12:45:10.115626+01
9ca7f00c-7fb0-4d1b-899c-803d9cbbe975	b46bba4b-525d-483d-bf4e-f195bde3d6bc	2025-09-09	\N	\N	\N	623.610000	\N	GENERATED	2025-11-04 12:45:10.116284+01
e9f1e3ce-4e3d-4872-9e3e-802a974071eb	b46bba4b-525d-483d-bf4e-f195bde3d6bc	2025-09-10	\N	\N	\N	616.070000	\N	GENERATED	2025-11-04 12:45:10.116958+01
76632403-7464-40b5-8775-5571cc94f34d	b46bba4b-525d-483d-bf4e-f195bde3d6bc	2025-09-11	\N	\N	\N	617.730000	\N	GENERATED	2025-11-04 12:45:10.117895+01
314ed1c7-1312-4e28-8fdd-f97049d43a0d	b46bba4b-525d-483d-bf4e-f195bde3d6bc	2025-09-12	\N	\N	\N	621.260000	\N	GENERATED	2025-11-04 12:45:10.118625+01
919cbb92-aa97-4682-8f55-ce89a307945f	b46bba4b-525d-483d-bf4e-f195bde3d6bc	2025-09-13	\N	\N	\N	621.850000	\N	GENERATED	2025-11-04 12:45:10.119357+01
26b39575-fd26-482e-9bc1-3bc11a9cf041	b46bba4b-525d-483d-bf4e-f195bde3d6bc	2025-09-14	\N	\N	\N	617.820000	\N	GENERATED	2025-11-04 12:45:10.120141+01
7b651a0b-c646-4472-9177-1f1f4ed2b260	b46bba4b-525d-483d-bf4e-f195bde3d6bc	2025-09-15	\N	\N	\N	623.150000	\N	GENERATED	2025-11-04 12:45:10.120856+01
b0f9cf07-b864-48d6-a236-d9226571e5d9	b46bba4b-525d-483d-bf4e-f195bde3d6bc	2025-09-16	\N	\N	\N	618.380000	\N	GENERATED	2025-11-04 12:45:10.121541+01
8403c330-b14a-4675-9737-56f4621e4328	b46bba4b-525d-483d-bf4e-f195bde3d6bc	2025-09-17	\N	\N	\N	625.170000	\N	GENERATED	2025-11-04 12:45:10.122316+01
ede3b9a7-21ab-4557-b974-612fc94793d9	b46bba4b-525d-483d-bf4e-f195bde3d6bc	2025-09-18	\N	\N	\N	618.510000	\N	GENERATED	2025-11-04 12:45:10.123001+01
585a98c6-a6e7-4ed2-94f0-7f68132a3666	b46bba4b-525d-483d-bf4e-f195bde3d6bc	2025-09-19	\N	\N	\N	625.600000	\N	GENERATED	2025-11-04 12:45:10.123678+01
4a2c1f69-a55c-4c39-8e89-c8899129c0b2	b46bba4b-525d-483d-bf4e-f195bde3d6bc	2025-09-20	\N	\N	\N	621.340000	\N	GENERATED	2025-11-04 12:45:10.124387+01
caabfbb7-79df-4ee7-af71-2df7b8110330	b46bba4b-525d-483d-bf4e-f195bde3d6bc	2025-09-21	\N	\N	\N	620.860000	\N	GENERATED	2025-11-04 12:45:10.125255+01
8a96bc8f-f262-4785-bdac-ab4af44294c5	b46bba4b-525d-483d-bf4e-f195bde3d6bc	2025-09-22	\N	\N	\N	622.710000	\N	GENERATED	2025-11-04 12:45:10.125978+01
5997c093-5b91-49cd-87ed-bed98672c929	b46bba4b-525d-483d-bf4e-f195bde3d6bc	2025-09-23	\N	\N	\N	625.070000	\N	GENERATED	2025-11-04 12:45:10.126726+01
816f2d31-5828-4fc0-bbbc-972025622591	b46bba4b-525d-483d-bf4e-f195bde3d6bc	2025-09-24	\N	\N	\N	623.310000	\N	GENERATED	2025-11-04 12:45:10.127429+01
25d9e1ae-63b1-49a8-9833-3cfdb77255c1	b46bba4b-525d-483d-bf4e-f195bde3d6bc	2025-09-25	\N	\N	\N	618.600000	\N	GENERATED	2025-11-04 12:45:10.12816+01
758b43e7-1100-42b8-b663-24b9a248de20	b46bba4b-525d-483d-bf4e-f195bde3d6bc	2025-09-26	\N	\N	\N	618.460000	\N	GENERATED	2025-11-04 12:45:10.128831+01
54770c1f-7764-4f5c-805d-fd466f1f07c6	b46bba4b-525d-483d-bf4e-f195bde3d6bc	2025-09-27	\N	\N	\N	619.400000	\N	GENERATED	2025-11-04 12:45:10.129497+01
04d38606-9ed1-440b-b77a-607d5cdb2d5c	b46bba4b-525d-483d-bf4e-f195bde3d6bc	2025-09-28	\N	\N	\N	617.860000	\N	GENERATED	2025-11-04 12:45:10.130167+01
b803a3f4-969a-4503-ac12-0a2fc6acd3ca	b46bba4b-525d-483d-bf4e-f195bde3d6bc	2025-09-29	\N	\N	\N	621.440000	\N	GENERATED	2025-11-04 12:45:10.130843+01
cd6b0820-a4a9-45c1-bc5c-8514a129715d	b46bba4b-525d-483d-bf4e-f195bde3d6bc	2025-09-30	\N	\N	\N	619.060000	\N	GENERATED	2025-11-04 12:45:10.131691+01
45d62141-d784-4e73-9464-3b0cc606e542	b46bba4b-525d-483d-bf4e-f195bde3d6bc	2025-10-01	\N	\N	\N	616.660000	\N	GENERATED	2025-11-04 12:45:10.13296+01
6e637408-3a25-4712-a03e-71b1d538f992	b46bba4b-525d-483d-bf4e-f195bde3d6bc	2025-10-02	\N	\N	\N	616.920000	\N	GENERATED	2025-11-04 12:45:10.134045+01
24a014d1-4cab-487e-a19c-b5d6aa550cbc	b46bba4b-525d-483d-bf4e-f195bde3d6bc	2025-10-03	\N	\N	\N	627.580000	\N	GENERATED	2025-11-04 12:45:10.134776+01
d66429c8-112a-4c6a-a18a-50a5bb9bccfb	b46bba4b-525d-483d-bf4e-f195bde3d6bc	2025-10-04	\N	\N	\N	621.260000	\N	GENERATED	2025-11-04 12:45:10.135463+01
f40f613d-85fb-4bd7-bdd9-b89677d99a6b	b46bba4b-525d-483d-bf4e-f195bde3d6bc	2025-10-05	\N	\N	\N	620.990000	\N	GENERATED	2025-11-04 12:45:10.13614+01
ca4cd0d4-bc35-4bba-ba77-a570ddbda24a	b46bba4b-525d-483d-bf4e-f195bde3d6bc	2025-10-06	\N	\N	\N	623.490000	\N	GENERATED	2025-11-04 12:45:10.136823+01
0b8905bd-6363-404b-a2c7-258e9d9a9291	b46bba4b-525d-483d-bf4e-f195bde3d6bc	2025-10-07	\N	\N	\N	623.040000	\N	GENERATED	2025-11-04 12:45:10.13751+01
e0b1af23-e0f8-49ab-8e75-c1238511a9e8	b46bba4b-525d-483d-bf4e-f195bde3d6bc	2025-10-08	\N	\N	\N	618.260000	\N	GENERATED	2025-11-04 12:45:10.138219+01
4c9b9ecb-8f17-4916-92d4-a358ec359e71	b46bba4b-525d-483d-bf4e-f195bde3d6bc	2025-10-09	\N	\N	\N	626.010000	\N	GENERATED	2025-11-04 12:45:10.13892+01
d6022400-5c10-4361-85cf-3a2c93c00ab9	b46bba4b-525d-483d-bf4e-f195bde3d6bc	2025-10-10	\N	\N	\N	625.650000	\N	GENERATED	2025-11-04 12:45:10.139611+01
9ff36037-0159-4777-a477-0aa86408fce8	b46bba4b-525d-483d-bf4e-f195bde3d6bc	2025-10-11	\N	\N	\N	618.150000	\N	GENERATED	2025-11-04 12:45:10.140296+01
63a60c42-7837-42bf-b738-243cd1d77165	b46bba4b-525d-483d-bf4e-f195bde3d6bc	2025-10-12	\N	\N	\N	624.350000	\N	GENERATED	2025-11-04 12:45:10.14097+01
3a5c547f-ba2a-4496-872f-703315d96ff8	b46bba4b-525d-483d-bf4e-f195bde3d6bc	2025-10-13	\N	\N	\N	626.670000	\N	GENERATED	2025-11-04 12:45:10.141642+01
208bc6c6-d2bc-4069-80d4-18f0631235ec	b46bba4b-525d-483d-bf4e-f195bde3d6bc	2025-10-14	\N	\N	\N	624.720000	\N	GENERATED	2025-11-04 12:45:10.142345+01
ad8ffc98-6e0e-42f2-b855-65c7f75b66dd	b46bba4b-525d-483d-bf4e-f195bde3d6bc	2025-10-15	\N	\N	\N	621.390000	\N	GENERATED	2025-11-04 12:45:10.143031+01
3d82a4bb-aa4e-432a-a0ae-cb909d4384f0	b46bba4b-525d-483d-bf4e-f195bde3d6bc	2025-10-16	\N	\N	\N	624.320000	\N	GENERATED	2025-11-04 12:45:10.14369+01
a68be4d7-7f27-4775-abd7-e21b5e412dbc	b46bba4b-525d-483d-bf4e-f195bde3d6bc	2025-10-17	\N	\N	\N	623.690000	\N	GENERATED	2025-11-04 12:45:10.144366+01
563c40fd-5dd7-4447-8c5c-515e3391e895	b46bba4b-525d-483d-bf4e-f195bde3d6bc	2025-10-18	\N	\N	\N	627.100000	\N	GENERATED	2025-11-04 12:45:10.145036+01
5caeb1f2-971d-4f49-896c-b6056a01fc81	b46bba4b-525d-483d-bf4e-f195bde3d6bc	2025-10-19	\N	\N	\N	628.710000	\N	GENERATED	2025-11-04 12:45:10.145702+01
cc567014-78dd-460c-bc73-f52361365f12	b46bba4b-525d-483d-bf4e-f195bde3d6bc	2025-10-20	\N	\N	\N	622.350000	\N	GENERATED	2025-11-04 12:45:10.146369+01
448bff93-dc15-4639-a61c-4047477f7608	b46bba4b-525d-483d-bf4e-f195bde3d6bc	2025-10-21	\N	\N	\N	626.800000	\N	GENERATED	2025-11-04 12:45:10.147025+01
6646a210-487d-40d8-b014-2e2e7d53cd27	b46bba4b-525d-483d-bf4e-f195bde3d6bc	2025-10-22	\N	\N	\N	621.790000	\N	GENERATED	2025-11-04 12:45:10.147779+01
20e16dfc-85ef-440c-bee8-183b1babdcdc	b46bba4b-525d-483d-bf4e-f195bde3d6bc	2025-10-23	\N	\N	\N	629.940000	\N	GENERATED	2025-11-04 12:45:10.148741+01
a47b140f-92a3-4ce2-98cc-9330c5134877	b46bba4b-525d-483d-bf4e-f195bde3d6bc	2025-10-24	\N	\N	\N	621.180000	\N	GENERATED	2025-11-04 12:45:10.14959+01
be7a98e0-4857-42cd-9850-2fdb4b6f5743	b46bba4b-525d-483d-bf4e-f195bde3d6bc	2025-10-25	\N	\N	\N	622.370000	\N	GENERATED	2025-11-04 12:45:10.150348+01
93696a84-0980-4feb-8f49-b8c41bdad336	b46bba4b-525d-483d-bf4e-f195bde3d6bc	2025-10-26	\N	\N	\N	620.480000	\N	GENERATED	2025-11-04 12:45:10.151027+01
ce8085b6-378c-4da4-a716-4909f7eaada3	b46bba4b-525d-483d-bf4e-f195bde3d6bc	2025-10-27	\N	\N	\N	625.130000	\N	GENERATED	2025-11-04 12:45:10.151734+01
550618a6-8c21-4253-a8c6-77ac6818cbd5	b46bba4b-525d-483d-bf4e-f195bde3d6bc	2025-10-28	\N	\N	\N	623.170000	\N	GENERATED	2025-11-04 12:45:10.152459+01
15e44266-307a-4bf5-aa5d-3f07173161e6	b46bba4b-525d-483d-bf4e-f195bde3d6bc	2025-10-29	\N	\N	\N	623.550000	\N	GENERATED	2025-11-04 12:45:10.153155+01
2f789c67-eed1-4c70-a644-e763bcc0e94b	b46bba4b-525d-483d-bf4e-f195bde3d6bc	2025-10-30	\N	\N	\N	620.750000	\N	GENERATED	2025-11-04 12:45:10.153827+01
ab83c977-9532-4ca4-9b02-008eeb186203	b46bba4b-525d-483d-bf4e-f195bde3d6bc	2025-10-31	\N	\N	\N	623.180000	\N	GENERATED	2025-11-04 12:45:10.154505+01
5e0c40f1-5f65-40f4-a3ac-7fc5738e28f7	b46bba4b-525d-483d-bf4e-f195bde3d6bc	2025-11-01	\N	\N	\N	631.710000	\N	GENERATED	2025-11-04 12:45:10.15517+01
5a562fe1-3038-424c-8f97-52741d00ce52	b46bba4b-525d-483d-bf4e-f195bde3d6bc	2025-11-02	\N	\N	\N	622.020000	\N	GENERATED	2025-11-04 12:45:10.155841+01
2aeeedef-495f-4738-a5e9-f7421a4e8bc0	b46bba4b-525d-483d-bf4e-f195bde3d6bc	2025-11-03	\N	\N	\N	623.940000	\N	GENERATED	2025-11-04 12:45:10.156505+01
04433006-b37b-4d97-b9db-8a3a32887bda	bf3b3448-1ec3-4f29-87e3-7fc90bc83308	2024-11-04	\N	\N	\N	75.210000	\N	GENERATED	2025-11-04 12:45:10.157783+01
d599ebd7-8404-469a-acec-4b37a288f1d2	bf3b3448-1ec3-4f29-87e3-7fc90bc83308	2024-11-05	\N	\N	\N	74.310000	\N	GENERATED	2025-11-04 12:45:10.158459+01
5baeedde-a1cf-4656-a839-ab8a0d87badb	bf3b3448-1ec3-4f29-87e3-7fc90bc83308	2024-11-06	\N	\N	\N	75.780000	\N	GENERATED	2025-11-04 12:45:10.159114+01
6f70719a-b29f-434e-acda-cf76fc15574d	bf3b3448-1ec3-4f29-87e3-7fc90bc83308	2024-11-07	\N	\N	\N	75.500000	\N	GENERATED	2025-11-04 12:45:10.159779+01
1979e38f-9728-475d-b465-20786b7c55c6	bf3b3448-1ec3-4f29-87e3-7fc90bc83308	2024-11-08	\N	\N	\N	75.610000	\N	GENERATED	2025-11-04 12:45:10.16045+01
903a51ec-5dcd-4540-9c38-0b6f4f43e731	bf3b3448-1ec3-4f29-87e3-7fc90bc83308	2024-11-09	\N	\N	\N	75.640000	\N	GENERATED	2025-11-04 12:45:10.1611+01
cc643066-ad48-4054-a1ca-349312a6a476	bf3b3448-1ec3-4f29-87e3-7fc90bc83308	2024-11-10	\N	\N	\N	75.160000	\N	GENERATED	2025-11-04 12:45:10.161806+01
065ad80f-e101-4960-a5f3-ab6ded23d3af	bf3b3448-1ec3-4f29-87e3-7fc90bc83308	2024-11-11	\N	\N	\N	74.370000	\N	GENERATED	2025-11-04 12:45:10.162477+01
4a3aa280-df4e-478b-8637-3a9b177c79e3	bf3b3448-1ec3-4f29-87e3-7fc90bc83308	2024-11-12	\N	\N	\N	75.330000	\N	GENERATED	2025-11-04 12:45:10.163141+01
1846001b-9989-4656-afb0-caa53b0d3d0c	bf3b3448-1ec3-4f29-87e3-7fc90bc83308	2024-11-13	\N	\N	\N	75.880000	\N	GENERATED	2025-11-04 12:45:10.163969+01
dc184b6e-9337-4324-9ea0-f1e280a28270	bf3b3448-1ec3-4f29-87e3-7fc90bc83308	2024-11-14	\N	\N	\N	74.910000	\N	GENERATED	2025-11-04 12:45:10.164668+01
e66db187-a08f-4c95-b80f-db828f62abd5	bf3b3448-1ec3-4f29-87e3-7fc90bc83308	2024-11-15	\N	\N	\N	75.810000	\N	GENERATED	2025-11-04 12:45:10.165331+01
7c15a416-0b4b-4860-bbc5-498eb471687b	bf3b3448-1ec3-4f29-87e3-7fc90bc83308	2024-11-16	\N	\N	\N	75.670000	\N	GENERATED	2025-11-04 12:45:10.165994+01
baac716f-2bc4-4543-b1ce-545df15917ba	bf3b3448-1ec3-4f29-87e3-7fc90bc83308	2024-11-17	\N	\N	\N	75.890000	\N	GENERATED	2025-11-04 12:45:10.166693+01
1b31b03b-404f-403c-adc5-005971e03aa4	bf3b3448-1ec3-4f29-87e3-7fc90bc83308	2024-11-18	\N	\N	\N	75.540000	\N	GENERATED	2025-11-04 12:45:10.167699+01
6d4ea85f-9476-47f4-a91a-38e2aa62da10	bf3b3448-1ec3-4f29-87e3-7fc90bc83308	2024-11-19	\N	\N	\N	74.860000	\N	GENERATED	2025-11-04 12:45:10.168371+01
a5b3926f-d4d1-4b39-9310-778336983362	bf3b3448-1ec3-4f29-87e3-7fc90bc83308	2024-11-20	\N	\N	\N	75.810000	\N	GENERATED	2025-11-04 12:45:10.169036+01
2eab90c7-7140-4b59-aaa8-3463a267af76	bf3b3448-1ec3-4f29-87e3-7fc90bc83308	2024-11-21	\N	\N	\N	74.700000	\N	GENERATED	2025-11-04 12:45:10.16971+01
c0d573d5-480c-4347-a93c-fc346aab0a87	bf3b3448-1ec3-4f29-87e3-7fc90bc83308	2024-11-22	\N	\N	\N	75.060000	\N	GENERATED	2025-11-04 12:45:10.170366+01
3efdf2df-0717-4773-b356-266c47b1259a	bf3b3448-1ec3-4f29-87e3-7fc90bc83308	2024-11-23	\N	\N	\N	75.990000	\N	GENERATED	2025-11-04 12:45:10.17103+01
39e91bcd-a06e-4c41-b38d-b5b54ce5a4aa	bf3b3448-1ec3-4f29-87e3-7fc90bc83308	2024-11-24	\N	\N	\N	74.900000	\N	GENERATED	2025-11-04 12:45:10.171745+01
1f3b8ff9-38b9-4835-8e5d-e9f8a6fb869d	bf3b3448-1ec3-4f29-87e3-7fc90bc83308	2024-11-25	\N	\N	\N	74.630000	\N	GENERATED	2025-11-04 12:45:10.172721+01
0152541b-db89-4c26-aac1-c0aaa51aa038	bf3b3448-1ec3-4f29-87e3-7fc90bc83308	2024-11-26	\N	\N	\N	75.370000	\N	GENERATED	2025-11-04 12:45:10.173386+01
9feb50c8-5348-4f30-909f-84c0df3354e8	bf3b3448-1ec3-4f29-87e3-7fc90bc83308	2024-11-27	\N	\N	\N	75.020000	\N	GENERATED	2025-11-04 12:45:10.174044+01
e20e21c4-0c5e-48b3-bdc2-c474417911eb	bf3b3448-1ec3-4f29-87e3-7fc90bc83308	2024-11-28	\N	\N	\N	75.020000	\N	GENERATED	2025-11-04 12:45:10.174746+01
2cf19d7d-2186-4308-af5f-784de42be19f	bf3b3448-1ec3-4f29-87e3-7fc90bc83308	2024-11-29	\N	\N	\N	75.480000	\N	GENERATED	2025-11-04 12:45:10.175401+01
edf75af7-2123-4d20-b2d6-157deae23b6a	bf3b3448-1ec3-4f29-87e3-7fc90bc83308	2024-11-30	\N	\N	\N	75.360000	\N	GENERATED	2025-11-04 12:45:10.176094+01
9779d8ee-fb39-43e6-a281-c237604b6098	bf3b3448-1ec3-4f29-87e3-7fc90bc83308	2024-12-01	\N	\N	\N	76.110000	\N	GENERATED	2025-11-04 12:45:10.176873+01
4ca397f6-841f-4151-a8f2-c28259e651b0	bf3b3448-1ec3-4f29-87e3-7fc90bc83308	2024-12-02	\N	\N	\N	75.910000	\N	GENERATED	2025-11-04 12:45:10.17786+01
593f95cf-75dc-4642-b291-470e8becc6a8	bf3b3448-1ec3-4f29-87e3-7fc90bc83308	2024-12-03	\N	\N	\N	75.710000	\N	GENERATED	2025-11-04 12:45:10.178619+01
f3b6a610-f8dc-4341-8659-b8c3b5aae0d5	bf3b3448-1ec3-4f29-87e3-7fc90bc83308	2024-12-04	\N	\N	\N	75.040000	\N	GENERATED	2025-11-04 12:45:10.179685+01
cb572c6a-6971-4c89-8e78-3487b2708e80	bf3b3448-1ec3-4f29-87e3-7fc90bc83308	2024-12-05	\N	\N	\N	74.780000	\N	GENERATED	2025-11-04 12:45:10.180366+01
a3a1f530-e08f-464b-a4ee-9a3c0612bf8e	bf3b3448-1ec3-4f29-87e3-7fc90bc83308	2024-12-06	\N	\N	\N	75.590000	\N	GENERATED	2025-11-04 12:45:10.181068+01
c2fef4b9-b3a2-4686-9296-cde8fd290cae	bf3b3448-1ec3-4f29-87e3-7fc90bc83308	2024-12-07	\N	\N	\N	76.290000	\N	GENERATED	2025-11-04 12:45:10.181773+01
e8f6c6a4-c69d-44c6-9b47-a5584c1152ef	bf3b3448-1ec3-4f29-87e3-7fc90bc83308	2024-12-08	\N	\N	\N	76.220000	\N	GENERATED	2025-11-04 12:45:10.182457+01
f2a9186c-94d8-4c64-a85c-82198bf3bc21	bf3b3448-1ec3-4f29-87e3-7fc90bc83308	2024-12-09	\N	\N	\N	76.120000	\N	GENERATED	2025-11-04 12:45:10.183122+01
556c0f32-14bb-4c6c-9b7d-c9a59fdce5c1	bf3b3448-1ec3-4f29-87e3-7fc90bc83308	2024-12-10	\N	\N	\N	76.120000	\N	GENERATED	2025-11-04 12:45:10.183824+01
47e712d8-a428-4f4a-a14c-85afaea0ed3b	bf3b3448-1ec3-4f29-87e3-7fc90bc83308	2024-12-11	\N	\N	\N	76.290000	\N	GENERATED	2025-11-04 12:45:10.184497+01
2dd040a8-fdad-49ee-a122-a2bc2e87fa45	bf3b3448-1ec3-4f29-87e3-7fc90bc83308	2024-12-12	\N	\N	\N	74.880000	\N	GENERATED	2025-11-04 12:45:10.185171+01
1c2e0e46-99ca-4b89-bfb3-3d4e7ee919c0	bf3b3448-1ec3-4f29-87e3-7fc90bc83308	2024-12-13	\N	\N	\N	75.560000	\N	GENERATED	2025-11-04 12:45:10.185861+01
fc314829-1c5d-4382-ab21-f2d9b4e92126	bf3b3448-1ec3-4f29-87e3-7fc90bc83308	2024-12-14	\N	\N	\N	76.270000	\N	GENERATED	2025-11-04 12:45:10.186517+01
d972c84e-cacc-4fa8-b5d8-018f73b51063	bf3b3448-1ec3-4f29-87e3-7fc90bc83308	2024-12-15	\N	\N	\N	75.240000	\N	GENERATED	2025-11-04 12:45:10.187221+01
955d2dc1-4735-4ae8-a1b8-14c8087873bf	bf3b3448-1ec3-4f29-87e3-7fc90bc83308	2024-12-16	\N	\N	\N	75.180000	\N	GENERATED	2025-11-04 12:45:10.1879+01
9fef22ec-3c6e-4c9e-871e-a9d811ccc86a	bf3b3448-1ec3-4f29-87e3-7fc90bc83308	2024-12-17	\N	\N	\N	75.660000	\N	GENERATED	2025-11-04 12:45:10.188593+01
9a33dd1d-d93a-4b3a-9ba5-6772228e6547	bf3b3448-1ec3-4f29-87e3-7fc90bc83308	2024-12-18	\N	\N	\N	75.400000	\N	GENERATED	2025-11-04 12:45:10.189669+01
ea7727ba-34cd-4ed4-b453-29f0eac2c8d5	bf3b3448-1ec3-4f29-87e3-7fc90bc83308	2024-12-19	\N	\N	\N	76.170000	\N	GENERATED	2025-11-04 12:45:10.190327+01
7dab42e0-e4f1-4054-acc7-4628afdf85cf	bf3b3448-1ec3-4f29-87e3-7fc90bc83308	2024-12-20	\N	\N	\N	75.480000	\N	GENERATED	2025-11-04 12:45:10.190987+01
825fef5f-d560-4134-b4c6-fc245438ddf5	bf3b3448-1ec3-4f29-87e3-7fc90bc83308	2024-12-21	\N	\N	\N	75.910000	\N	GENERATED	2025-11-04 12:45:10.19177+01
8d165f83-5cc2-4e36-861a-17cf8737a8f0	bf3b3448-1ec3-4f29-87e3-7fc90bc83308	2024-12-22	\N	\N	\N	75.240000	\N	GENERATED	2025-11-04 12:45:10.192625+01
5555ccb3-cdbb-4a70-b5e4-7d491f8a7e5d	bf3b3448-1ec3-4f29-87e3-7fc90bc83308	2024-12-23	\N	\N	\N	75.670000	\N	GENERATED	2025-11-04 12:45:10.193449+01
6af81738-ec50-4280-8822-1cdf8169faa1	bf3b3448-1ec3-4f29-87e3-7fc90bc83308	2024-12-24	\N	\N	\N	75.280000	\N	GENERATED	2025-11-04 12:45:10.19412+01
b68160a5-cfe1-4396-bca7-315b8d59b4d1	bf3b3448-1ec3-4f29-87e3-7fc90bc83308	2024-12-25	\N	\N	\N	76.440000	\N	GENERATED	2025-11-04 12:45:10.194822+01
fe4cac43-e9b4-4a31-a14e-dcd98c568f58	bf3b3448-1ec3-4f29-87e3-7fc90bc83308	2024-12-26	\N	\N	\N	75.270000	\N	GENERATED	2025-11-04 12:45:10.195574+01
e412207e-3f4e-4fca-a1de-b41682aee76c	bf3b3448-1ec3-4f29-87e3-7fc90bc83308	2024-12-27	\N	\N	\N	75.460000	\N	GENERATED	2025-11-04 12:45:10.196259+01
898b57bd-b438-4380-b52d-acde73a0502f	bf3b3448-1ec3-4f29-87e3-7fc90bc83308	2024-12-28	\N	\N	\N	75.530000	\N	GENERATED	2025-11-04 12:45:10.197057+01
dbec3805-acef-42f7-931f-0dbd2bf7beed	bf3b3448-1ec3-4f29-87e3-7fc90bc83308	2024-12-29	\N	\N	\N	76.270000	\N	GENERATED	2025-11-04 12:45:10.197731+01
99a74ced-8f9d-40ec-9612-dea4443a6ec3	bf3b3448-1ec3-4f29-87e3-7fc90bc83308	2024-12-30	\N	\N	\N	76.430000	\N	GENERATED	2025-11-04 12:45:10.19841+01
e4ec5538-1f76-42f3-ad58-e404fd0a296e	bf3b3448-1ec3-4f29-87e3-7fc90bc83308	2024-12-31	\N	\N	\N	75.300000	\N	GENERATED	2025-11-04 12:45:10.199233+01
e222a3cd-8974-4d86-a204-d5886573f147	bf3b3448-1ec3-4f29-87e3-7fc90bc83308	2025-01-01	\N	\N	\N	75.410000	\N	GENERATED	2025-11-04 12:45:10.199899+01
4f196fde-5883-4b81-92d3-9cafa8162c8f	bf3b3448-1ec3-4f29-87e3-7fc90bc83308	2025-01-02	\N	\N	\N	75.850000	\N	GENERATED	2025-11-04 12:45:10.200558+01
f974e005-9971-496e-afaa-680147fa3025	bf3b3448-1ec3-4f29-87e3-7fc90bc83308	2025-01-03	\N	\N	\N	75.840000	\N	GENERATED	2025-11-04 12:45:10.201219+01
d58ec6c1-3a55-4a77-af9c-4a06992baae1	bf3b3448-1ec3-4f29-87e3-7fc90bc83308	2025-01-04	\N	\N	\N	75.480000	\N	GENERATED	2025-11-04 12:45:10.201956+01
76ac5625-a04a-4517-9fb2-225114e6611c	bf3b3448-1ec3-4f29-87e3-7fc90bc83308	2025-01-05	\N	\N	\N	75.940000	\N	GENERATED	2025-11-04 12:45:10.202632+01
10796ec8-2802-4c91-b031-161ab629e27f	bf3b3448-1ec3-4f29-87e3-7fc90bc83308	2025-01-06	\N	\N	\N	75.480000	\N	GENERATED	2025-11-04 12:45:10.203317+01
dff44228-b48b-491b-8512-045cb0a4959a	bf3b3448-1ec3-4f29-87e3-7fc90bc83308	2025-01-07	\N	\N	\N	75.630000	\N	GENERATED	2025-11-04 12:45:10.203982+01
e9f4ce08-882f-4f25-b304-69897a4dac1f	bf3b3448-1ec3-4f29-87e3-7fc90bc83308	2025-01-08	\N	\N	\N	76.430000	\N	GENERATED	2025-11-04 12:45:10.204634+01
a9b352a3-2975-4146-bee4-749463e5ec22	bf3b3448-1ec3-4f29-87e3-7fc90bc83308	2025-01-09	\N	\N	\N	76.760000	\N	GENERATED	2025-11-04 12:45:10.205289+01
a6f6784a-eb1b-4435-8180-25e6ffde5a20	bf3b3448-1ec3-4f29-87e3-7fc90bc83308	2025-01-10	\N	\N	\N	76.310000	\N	GENERATED	2025-11-04 12:45:10.205943+01
18a6cf0f-d852-4515-b182-7c9410dae1c6	bf3b3448-1ec3-4f29-87e3-7fc90bc83308	2025-01-11	\N	\N	\N	76.630000	\N	GENERATED	2025-11-04 12:45:10.206606+01
2605716d-38f7-4655-877c-62859ad828f3	bf3b3448-1ec3-4f29-87e3-7fc90bc83308	2025-01-12	\N	\N	\N	76.730000	\N	GENERATED	2025-11-04 12:45:10.207306+01
8da3544a-78bb-4e94-88c0-a07ec7671f95	bf3b3448-1ec3-4f29-87e3-7fc90bc83308	2025-01-13	\N	\N	\N	76.510000	\N	GENERATED	2025-11-04 12:45:10.208112+01
9153496d-b590-4da3-85e4-85f7c8f050e6	bf3b3448-1ec3-4f29-87e3-7fc90bc83308	2025-01-14	\N	\N	\N	76.390000	\N	GENERATED	2025-11-04 12:45:10.209059+01
016708ff-8447-43f0-a9ae-8555feb1e205	bf3b3448-1ec3-4f29-87e3-7fc90bc83308	2025-01-15	\N	\N	\N	75.600000	\N	GENERATED	2025-11-04 12:45:10.210024+01
9ff6f7f7-eb20-498b-9c72-3b588eba5240	bf3b3448-1ec3-4f29-87e3-7fc90bc83308	2025-01-16	\N	\N	\N	75.510000	\N	GENERATED	2025-11-04 12:45:10.210954+01
0c2cf80f-39a5-48d1-940a-5fd8ebb9e568	bf3b3448-1ec3-4f29-87e3-7fc90bc83308	2025-01-17	\N	\N	\N	76.690000	\N	GENERATED	2025-11-04 12:45:10.211634+01
34f6890c-6463-43fa-8150-33550631b37b	bf3b3448-1ec3-4f29-87e3-7fc90bc83308	2025-01-18	\N	\N	\N	76.060000	\N	GENERATED	2025-11-04 12:45:10.212374+01
847f8ef7-55e8-4645-b838-08971eb8ff69	bf3b3448-1ec3-4f29-87e3-7fc90bc83308	2025-01-19	\N	\N	\N	76.390000	\N	GENERATED	2025-11-04 12:45:10.213057+01
bbde4e47-113c-4bfa-98f0-7c4dbbc1eec0	bf3b3448-1ec3-4f29-87e3-7fc90bc83308	2025-01-20	\N	\N	\N	76.560000	\N	GENERATED	2025-11-04 12:45:10.213723+01
7f350b32-80d4-41fc-aac6-54ba3f021e8e	bf3b3448-1ec3-4f29-87e3-7fc90bc83308	2025-01-21	\N	\N	\N	76.040000	\N	GENERATED	2025-11-04 12:45:10.214385+01
c77ebbf5-7894-4f5e-b436-ed4c90c00fc7	bf3b3448-1ec3-4f29-87e3-7fc90bc83308	2025-01-22	\N	\N	\N	75.910000	\N	GENERATED	2025-11-04 12:45:10.215035+01
cc8a4825-d674-433a-a6e3-d83193b6371c	bf3b3448-1ec3-4f29-87e3-7fc90bc83308	2025-01-23	\N	\N	\N	75.890000	\N	GENERATED	2025-11-04 12:45:10.215699+01
5dcb18b0-cf2a-4d0e-bfb4-a473baf6bbb4	bf3b3448-1ec3-4f29-87e3-7fc90bc83308	2025-01-24	\N	\N	\N	76.980000	\N	GENERATED	2025-11-04 12:45:10.216377+01
bf5a329d-447e-473c-8390-64c57a7a52dd	bf3b3448-1ec3-4f29-87e3-7fc90bc83308	2025-01-25	\N	\N	\N	76.230000	\N	GENERATED	2025-11-04 12:45:10.217481+01
d5e7a208-463a-4473-9a2d-4b82133e992a	bf3b3448-1ec3-4f29-87e3-7fc90bc83308	2025-01-26	\N	\N	\N	76.440000	\N	GENERATED	2025-11-04 12:45:10.21817+01
d219ce4f-6cb2-4dd6-84a2-9b107f043ffe	bf3b3448-1ec3-4f29-87e3-7fc90bc83308	2025-01-27	\N	\N	\N	76.210000	\N	GENERATED	2025-11-04 12:45:10.218852+01
38bb7eff-38ad-4953-bd1f-35bff0f77768	bf3b3448-1ec3-4f29-87e3-7fc90bc83308	2025-01-28	\N	\N	\N	76.500000	\N	GENERATED	2025-11-04 12:45:10.219514+01
ca8dd4f6-c2d7-448e-8e07-3a835fb2353d	bf3b3448-1ec3-4f29-87e3-7fc90bc83308	2025-01-29	\N	\N	\N	77.060000	\N	GENERATED	2025-11-04 12:45:10.220193+01
8119658d-ba13-4e6f-b6da-304bd3fd3092	bf3b3448-1ec3-4f29-87e3-7fc90bc83308	2025-01-30	\N	\N	\N	76.680000	\N	GENERATED	2025-11-04 12:45:10.220847+01
8b12f83b-b93d-47b6-b101-9d22532c989f	bf3b3448-1ec3-4f29-87e3-7fc90bc83308	2025-01-31	\N	\N	\N	76.910000	\N	GENERATED	2025-11-04 12:45:10.221514+01
980fade0-5e52-4842-8705-76b1a3354e63	bf3b3448-1ec3-4f29-87e3-7fc90bc83308	2025-02-01	\N	\N	\N	77.120000	\N	GENERATED	2025-11-04 12:45:10.222165+01
64a8132c-5598-4020-967f-70f94f5cd2de	bf3b3448-1ec3-4f29-87e3-7fc90bc83308	2025-02-02	\N	\N	\N	76.340000	\N	GENERATED	2025-11-04 12:45:10.222833+01
87cb9d31-0f6d-4a21-b52d-ab9ed276b485	bf3b3448-1ec3-4f29-87e3-7fc90bc83308	2025-02-03	\N	\N	\N	76.060000	\N	GENERATED	2025-11-04 12:45:10.223619+01
e01c3502-252d-4bf4-ab32-988dc81a398e	bf3b3448-1ec3-4f29-87e3-7fc90bc83308	2025-02-04	\N	\N	\N	77.050000	\N	GENERATED	2025-11-04 12:45:10.224318+01
fd5645ea-e629-4182-9ad1-2a95f94e97ae	bf3b3448-1ec3-4f29-87e3-7fc90bc83308	2025-02-05	\N	\N	\N	76.570000	\N	GENERATED	2025-11-04 12:45:10.224989+01
1a7e2a00-0fd0-4c2a-a9cd-4cad472d9ee7	bf3b3448-1ec3-4f29-87e3-7fc90bc83308	2025-02-06	\N	\N	\N	75.910000	\N	GENERATED	2025-11-04 12:45:10.225966+01
30951f1f-cc97-43c8-8509-87cf9794957d	bf3b3448-1ec3-4f29-87e3-7fc90bc83308	2025-02-07	\N	\N	\N	75.960000	\N	GENERATED	2025-11-04 12:45:10.226963+01
e8e2ef06-5c94-4f91-93c1-fa7b4740a34b	bf3b3448-1ec3-4f29-87e3-7fc90bc83308	2025-02-08	\N	\N	\N	76.530000	\N	GENERATED	2025-11-04 12:45:10.227714+01
d7ab87ad-3baf-46ea-92e6-865ef040d6e6	bf3b3448-1ec3-4f29-87e3-7fc90bc83308	2025-02-09	\N	\N	\N	77.050000	\N	GENERATED	2025-11-04 12:45:10.228426+01
533aa7b6-5b7f-4877-99ed-61e136a30c5a	bf3b3448-1ec3-4f29-87e3-7fc90bc83308	2025-02-10	\N	\N	\N	76.720000	\N	GENERATED	2025-11-04 12:45:10.2291+01
42a88add-10d0-4996-81da-04a1dae58c5e	bf3b3448-1ec3-4f29-87e3-7fc90bc83308	2025-02-11	\N	\N	\N	75.890000	\N	GENERATED	2025-11-04 12:45:10.229783+01
c6221cca-8acd-468e-85d3-2d9dd6bd6d7d	bf3b3448-1ec3-4f29-87e3-7fc90bc83308	2025-02-12	\N	\N	\N	76.050000	\N	GENERATED	2025-11-04 12:45:10.230463+01
1bfb5aa5-deb0-46cd-a236-6c1d91116e3c	bf3b3448-1ec3-4f29-87e3-7fc90bc83308	2025-02-13	\N	\N	\N	75.950000	\N	GENERATED	2025-11-04 12:45:10.231248+01
552f25c0-2ad9-4cee-9a85-f928ace7da0d	bf3b3448-1ec3-4f29-87e3-7fc90bc83308	2025-02-14	\N	\N	\N	77.400000	\N	GENERATED	2025-11-04 12:45:10.232036+01
bd1a2aca-def3-4afa-92e2-2273f72d3c76	bf3b3448-1ec3-4f29-87e3-7fc90bc83308	2025-02-15	\N	\N	\N	76.230000	\N	GENERATED	2025-11-04 12:45:10.232968+01
e5825442-32bb-41b3-943a-4cf21923e1e1	bf3b3448-1ec3-4f29-87e3-7fc90bc83308	2025-02-16	\N	\N	\N	76.720000	\N	GENERATED	2025-11-04 12:45:10.233648+01
9f937798-fd69-457d-9b73-7878306b9790	bf3b3448-1ec3-4f29-87e3-7fc90bc83308	2025-02-17	\N	\N	\N	77.330000	\N	GENERATED	2025-11-04 12:45:10.234322+01
5131309e-485d-4416-8cd3-092292c7cf8e	bf3b3448-1ec3-4f29-87e3-7fc90bc83308	2025-02-18	\N	\N	\N	77.410000	\N	GENERATED	2025-11-04 12:45:10.234988+01
2c26d672-db38-4aa9-876d-578bdfcf572b	bf3b3448-1ec3-4f29-87e3-7fc90bc83308	2025-02-19	\N	\N	\N	77.270000	\N	GENERATED	2025-11-04 12:45:10.2357+01
d0741e56-8e87-4f5c-bb1c-4763932aee9d	bf3b3448-1ec3-4f29-87e3-7fc90bc83308	2025-02-20	\N	\N	\N	76.810000	\N	GENERATED	2025-11-04 12:45:10.236393+01
05bc3905-8d22-4762-b6fa-2fd8caa2b129	bf3b3448-1ec3-4f29-87e3-7fc90bc83308	2025-02-21	\N	\N	\N	76.760000	\N	GENERATED	2025-11-04 12:45:10.237053+01
e97a14aa-c133-43e1-9c8a-5ac8243bb2a2	bf3b3448-1ec3-4f29-87e3-7fc90bc83308	2025-02-22	\N	\N	\N	76.250000	\N	GENERATED	2025-11-04 12:45:10.237739+01
6a1f1a46-e6f3-465b-b180-ef4b8bfc7026	bf3b3448-1ec3-4f29-87e3-7fc90bc83308	2025-02-23	\N	\N	\N	77.360000	\N	GENERATED	2025-11-04 12:45:10.238417+01
93ec17b3-7376-4104-8c0c-c14e08f63791	bf3b3448-1ec3-4f29-87e3-7fc90bc83308	2025-02-24	\N	\N	\N	77.450000	\N	GENERATED	2025-11-04 12:45:10.239178+01
e1d1b247-0289-436a-b7e4-f784b1bf3a4a	bf3b3448-1ec3-4f29-87e3-7fc90bc83308	2025-02-25	\N	\N	\N	77.410000	\N	GENERATED	2025-11-04 12:45:10.239905+01
e9979f4d-0f69-41f3-8aa5-b10256f2ed98	bf3b3448-1ec3-4f29-87e3-7fc90bc83308	2025-02-26	\N	\N	\N	76.600000	\N	GENERATED	2025-11-04 12:45:10.240578+01
856e5e4d-1590-4484-8edc-e41cdadd7982	bf3b3448-1ec3-4f29-87e3-7fc90bc83308	2025-02-27	\N	\N	\N	76.140000	\N	GENERATED	2025-11-04 12:45:10.241488+01
f7653166-8501-44d6-99a3-6a869a48528d	bf3b3448-1ec3-4f29-87e3-7fc90bc83308	2025-02-28	\N	\N	\N	76.600000	\N	GENERATED	2025-11-04 12:45:10.242356+01
c606460b-1661-41b3-aa14-8fd57aae5d47	bf3b3448-1ec3-4f29-87e3-7fc90bc83308	2025-03-01	\N	\N	\N	76.670000	\N	GENERATED	2025-11-04 12:45:10.243113+01
79b9454b-8efc-4658-813c-5afe4c3eacb5	bf3b3448-1ec3-4f29-87e3-7fc90bc83308	2025-03-02	\N	\N	\N	76.730000	\N	GENERATED	2025-11-04 12:45:10.243842+01
4ce140cd-dd26-4cc7-9142-dd21c5eaf0ad	bf3b3448-1ec3-4f29-87e3-7fc90bc83308	2025-03-03	\N	\N	\N	77.550000	\N	GENERATED	2025-11-04 12:45:10.244543+01
67398e69-5105-4d45-8ae7-d1536f92656a	bf3b3448-1ec3-4f29-87e3-7fc90bc83308	2025-03-04	\N	\N	\N	76.660000	\N	GENERATED	2025-11-04 12:45:10.245218+01
30be2111-7a33-415d-811e-f7a0aa959cb3	bf3b3448-1ec3-4f29-87e3-7fc90bc83308	2025-03-05	\N	\N	\N	76.530000	\N	GENERATED	2025-11-04 12:45:10.24589+01
85f04c9c-7bec-4160-97e0-0d9f3c4edda1	bf3b3448-1ec3-4f29-87e3-7fc90bc83308	2025-03-06	\N	\N	\N	77.530000	\N	GENERATED	2025-11-04 12:45:10.246584+01
a0d54338-f5c7-4f8e-ad09-1b1754a6f31d	bf3b3448-1ec3-4f29-87e3-7fc90bc83308	2025-03-07	\N	\N	\N	76.400000	\N	GENERATED	2025-11-04 12:45:10.247251+01
c1039fb6-b6b1-417f-a90a-97fb85154764	bf3b3448-1ec3-4f29-87e3-7fc90bc83308	2025-03-08	\N	\N	\N	76.630000	\N	GENERATED	2025-11-04 12:45:10.247955+01
8570d3ac-7f91-4eb7-a913-8e9171542595	bf3b3448-1ec3-4f29-87e3-7fc90bc83308	2025-03-09	\N	\N	\N	77.590000	\N	GENERATED	2025-11-04 12:45:10.248621+01
af5ceaf2-adfd-4ffc-90a2-7590bb420a85	bf3b3448-1ec3-4f29-87e3-7fc90bc83308	2025-03-10	\N	\N	\N	76.500000	\N	GENERATED	2025-11-04 12:45:10.249308+01
33d616ab-3284-4454-8f1e-4ce1ba164d4a	bf3b3448-1ec3-4f29-87e3-7fc90bc83308	2025-03-11	\N	\N	\N	77.260000	\N	GENERATED	2025-11-04 12:45:10.249979+01
f86d9eff-4f57-445f-9fa7-988cd596ec7d	bf3b3448-1ec3-4f29-87e3-7fc90bc83308	2025-03-12	\N	\N	\N	76.800000	\N	GENERATED	2025-11-04 12:45:10.25064+01
d883c1f0-e5e9-4763-b3ac-baf36bc30982	bf3b3448-1ec3-4f29-87e3-7fc90bc83308	2025-03-13	\N	\N	\N	76.450000	\N	GENERATED	2025-11-04 12:45:10.251345+01
4bf81d8e-0226-4b8d-95a3-241e1734e93d	bf3b3448-1ec3-4f29-87e3-7fc90bc83308	2025-03-14	\N	\N	\N	77.590000	\N	GENERATED	2025-11-04 12:45:10.252072+01
22b4390e-2524-45bf-a43a-a30ead893773	bf3b3448-1ec3-4f29-87e3-7fc90bc83308	2025-03-15	\N	\N	\N	77.800000	\N	GENERATED	2025-11-04 12:45:10.252736+01
9cf63cc0-75cb-421f-8f51-f5fb55b6366f	bf3b3448-1ec3-4f29-87e3-7fc90bc83308	2025-03-16	\N	\N	\N	76.920000	\N	GENERATED	2025-11-04 12:45:10.253434+01
52cc96da-093f-4be2-a02d-d444360c1d8b	bf3b3448-1ec3-4f29-87e3-7fc90bc83308	2025-03-17	\N	\N	\N	77.490000	\N	GENERATED	2025-11-04 12:45:10.254121+01
937ad2a0-9e3c-464d-92d2-eb6f41e9e597	bf3b3448-1ec3-4f29-87e3-7fc90bc83308	2025-03-18	\N	\N	\N	76.960000	\N	GENERATED	2025-11-04 12:45:10.254795+01
cf862d28-a9d2-4a04-84cd-71c0230d8c3e	bf3b3448-1ec3-4f29-87e3-7fc90bc83308	2025-03-19	\N	\N	\N	77.620000	\N	GENERATED	2025-11-04 12:45:10.255449+01
b5070d92-be44-41e5-9c6e-802f301ef108	bf3b3448-1ec3-4f29-87e3-7fc90bc83308	2025-03-20	\N	\N	\N	77.350000	\N	GENERATED	2025-11-04 12:45:10.256118+01
b805e68d-0563-4f0e-8c8e-aaca27b2f9da	bf3b3448-1ec3-4f29-87e3-7fc90bc83308	2025-03-21	\N	\N	\N	77.360000	\N	GENERATED	2025-11-04 12:45:10.256778+01
0043efa7-ae75-41f4-9171-9bdf4829b6c0	bf3b3448-1ec3-4f29-87e3-7fc90bc83308	2025-03-22	\N	\N	\N	76.690000	\N	GENERATED	2025-11-04 12:45:10.257758+01
bf7cd2b4-391c-49be-924b-889e2018859d	bf3b3448-1ec3-4f29-87e3-7fc90bc83308	2025-03-23	\N	\N	\N	77.000000	\N	GENERATED	2025-11-04 12:45:10.258513+01
12e020af-cda8-4f4e-839b-01d1d5479c26	bf3b3448-1ec3-4f29-87e3-7fc90bc83308	2025-03-24	\N	\N	\N	77.620000	\N	GENERATED	2025-11-04 12:45:10.259209+01
a7b07483-3a0e-49a6-af3b-2bfe09bb5879	bf3b3448-1ec3-4f29-87e3-7fc90bc83308	2025-03-25	\N	\N	\N	77.200000	\N	GENERATED	2025-11-04 12:45:10.25988+01
4e55d93e-9d65-43b6-a0a4-e5e70b227f56	bf3b3448-1ec3-4f29-87e3-7fc90bc83308	2025-03-26	\N	\N	\N	76.940000	\N	GENERATED	2025-11-04 12:45:10.260549+01
72f20c84-a4c0-463f-b759-a8381c22f8c1	bf3b3448-1ec3-4f29-87e3-7fc90bc83308	2025-03-27	\N	\N	\N	78.070000	\N	GENERATED	2025-11-04 12:45:10.26122+01
e3e8f17f-6398-4e30-abd9-df34f3fdd596	bf3b3448-1ec3-4f29-87e3-7fc90bc83308	2025-03-28	\N	\N	\N	77.390000	\N	GENERATED	2025-11-04 12:45:10.261887+01
83811c79-7916-4642-be54-41d4d522c8d5	bf3b3448-1ec3-4f29-87e3-7fc90bc83308	2025-03-29	\N	\N	\N	76.970000	\N	GENERATED	2025-11-04 12:45:10.262588+01
d7e42e70-fb22-4c86-bf36-45868fb59445	bf3b3448-1ec3-4f29-87e3-7fc90bc83308	2025-03-30	\N	\N	\N	78.050000	\N	GENERATED	2025-11-04 12:45:10.263263+01
fae4aab6-1263-41a2-be6c-f5e299b1d2cb	bf3b3448-1ec3-4f29-87e3-7fc90bc83308	2025-03-31	\N	\N	\N	77.850000	\N	GENERATED	2025-11-04 12:45:10.263928+01
4b075d52-a6d8-483b-97de-f290e2423c7c	bf3b3448-1ec3-4f29-87e3-7fc90bc83308	2025-04-01	\N	\N	\N	77.530000	\N	GENERATED	2025-11-04 12:45:10.26478+01
5532ad84-bb20-4e59-aa88-bae475ccfa92	bf3b3448-1ec3-4f29-87e3-7fc90bc83308	2025-04-02	\N	\N	\N	76.820000	\N	GENERATED	2025-11-04 12:45:10.265462+01
0a3b294c-0872-4d99-bed4-c88718a740f3	bf3b3448-1ec3-4f29-87e3-7fc90bc83308	2025-04-03	\N	\N	\N	77.240000	\N	GENERATED	2025-11-04 12:45:10.266121+01
773f2b3d-7df2-4c2f-b227-0b8f45e49794	bf3b3448-1ec3-4f29-87e3-7fc90bc83308	2025-04-04	\N	\N	\N	77.210000	\N	GENERATED	2025-11-04 12:45:10.266786+01
595639ea-5235-4687-a006-892ae4481866	bf3b3448-1ec3-4f29-87e3-7fc90bc83308	2025-04-05	\N	\N	\N	77.790000	\N	GENERATED	2025-11-04 12:45:10.26747+01
55891397-35de-47d8-8688-8f1eb802aea0	bf3b3448-1ec3-4f29-87e3-7fc90bc83308	2025-04-06	\N	\N	\N	76.970000	\N	GENERATED	2025-11-04 12:45:10.268138+01
3bd8be36-71e6-4c0a-bedc-9e58fe57aa0a	bf3b3448-1ec3-4f29-87e3-7fc90bc83308	2025-04-07	\N	\N	\N	76.930000	\N	GENERATED	2025-11-04 12:45:10.268789+01
3b141d5a-b4f6-4435-a1dc-8f4e1c9f4c99	bf3b3448-1ec3-4f29-87e3-7fc90bc83308	2025-04-08	\N	\N	\N	77.520000	\N	GENERATED	2025-11-04 12:45:10.269457+01
64a8d2fa-28c1-4bfb-9f71-aa9caf501cd2	bf3b3448-1ec3-4f29-87e3-7fc90bc83308	2025-04-09	\N	\N	\N	77.700000	\N	GENERATED	2025-11-04 12:45:10.270109+01
f5158cb2-5cc6-4f65-ad0a-903be7d83b55	bf3b3448-1ec3-4f29-87e3-7fc90bc83308	2025-04-10	\N	\N	\N	77.510000	\N	GENERATED	2025-11-04 12:45:10.270764+01
7047d7cb-1291-4bb4-97df-10d382eef65d	bf3b3448-1ec3-4f29-87e3-7fc90bc83308	2025-04-11	\N	\N	\N	76.910000	\N	GENERATED	2025-11-04 12:45:10.271596+01
009b0400-efc7-4c8d-9ac9-27dca925df56	bf3b3448-1ec3-4f29-87e3-7fc90bc83308	2025-04-12	\N	\N	\N	77.020000	\N	GENERATED	2025-11-04 12:45:10.272748+01
7d759ec9-b27b-412d-a44c-c8e39ddfbd99	bf3b3448-1ec3-4f29-87e3-7fc90bc83308	2025-04-13	\N	\N	\N	77.330000	\N	GENERATED	2025-11-04 12:45:10.273461+01
4e1982ed-1f96-461e-9d7b-5966d991155c	bf3b3448-1ec3-4f29-87e3-7fc90bc83308	2025-04-14	\N	\N	\N	77.710000	\N	GENERATED	2025-11-04 12:45:10.274132+01
8900bb2c-fae9-4ea1-b142-2f69d6550c9d	bf3b3448-1ec3-4f29-87e3-7fc90bc83308	2025-04-15	\N	\N	\N	77.080000	\N	GENERATED	2025-11-04 12:45:10.27481+01
c880fdcd-0483-4b64-83df-64d91ec616c3	bf3b3448-1ec3-4f29-87e3-7fc90bc83308	2025-04-16	\N	\N	\N	78.410000	\N	GENERATED	2025-11-04 12:45:10.275469+01
6d80614a-3d9d-4aa5-b1dc-ce50ca4ca9d2	bf3b3448-1ec3-4f29-87e3-7fc90bc83308	2025-04-17	\N	\N	\N	78.130000	\N	GENERATED	2025-11-04 12:45:10.276143+01
e3c31086-c8ac-4b27-b7d3-bf42cad77e8e	bf3b3448-1ec3-4f29-87e3-7fc90bc83308	2025-04-18	\N	\N	\N	77.660000	\N	GENERATED	2025-11-04 12:45:10.276848+01
48290991-9462-4c87-af91-6fda83f8a85d	bf3b3448-1ec3-4f29-87e3-7fc90bc83308	2025-04-19	\N	\N	\N	77.310000	\N	GENERATED	2025-11-04 12:45:10.277502+01
fd8bb034-2134-45f6-af92-a95934b9b356	bf3b3448-1ec3-4f29-87e3-7fc90bc83308	2025-04-20	\N	\N	\N	78.470000	\N	GENERATED	2025-11-04 12:45:10.278169+01
54385f06-f96f-40b0-b2c2-23d1018783b6	bf3b3448-1ec3-4f29-87e3-7fc90bc83308	2025-04-21	\N	\N	\N	77.520000	\N	GENERATED	2025-11-04 12:45:10.278897+01
6cea4e98-d5a3-4e35-b91d-0775bd1bde35	bf3b3448-1ec3-4f29-87e3-7fc90bc83308	2025-04-22	\N	\N	\N	77.510000	\N	GENERATED	2025-11-04 12:45:10.279555+01
767fd085-b2c3-4866-a619-20d9cff091a3	bf3b3448-1ec3-4f29-87e3-7fc90bc83308	2025-04-23	\N	\N	\N	77.310000	\N	GENERATED	2025-11-04 12:45:10.280228+01
dc97363b-cd08-45c0-9c71-2aff6f49a23e	bf3b3448-1ec3-4f29-87e3-7fc90bc83308	2025-04-24	\N	\N	\N	77.300000	\N	GENERATED	2025-11-04 12:45:10.280892+01
f6612587-701c-4ab9-9a8c-3d018384918f	bf3b3448-1ec3-4f29-87e3-7fc90bc83308	2025-04-25	\N	\N	\N	78.320000	\N	GENERATED	2025-11-04 12:45:10.281549+01
5f69f54d-718a-44ee-8812-d06bbd64a60c	bf3b3448-1ec3-4f29-87e3-7fc90bc83308	2025-04-26	\N	\N	\N	77.500000	\N	GENERATED	2025-11-04 12:45:10.282241+01
519f2708-ae5e-47f3-bdc5-75b5752684af	bf3b3448-1ec3-4f29-87e3-7fc90bc83308	2025-04-27	\N	\N	\N	78.130000	\N	GENERATED	2025-11-04 12:45:10.282929+01
d011e515-5f81-4cc5-85df-3c3c9e4bd709	bf3b3448-1ec3-4f29-87e3-7fc90bc83308	2025-04-28	\N	\N	\N	77.500000	\N	GENERATED	2025-11-04 12:45:10.283595+01
3f93ae73-73d0-4af0-8adf-ad61bf230734	bf3b3448-1ec3-4f29-87e3-7fc90bc83308	2025-04-29	\N	\N	\N	77.650000	\N	GENERATED	2025-11-04 12:45:10.284293+01
d8ec6aed-4449-47d2-842c-06c42f25d82d	bf3b3448-1ec3-4f29-87e3-7fc90bc83308	2025-04-30	\N	\N	\N	77.890000	\N	GENERATED	2025-11-04 12:45:10.285264+01
e4e04f5a-a528-4fd0-96d6-a6467be8ca2a	bf3b3448-1ec3-4f29-87e3-7fc90bc83308	2025-05-01	\N	\N	\N	78.170000	\N	GENERATED	2025-11-04 12:45:10.285959+01
dab614f7-ec60-490b-8e06-747c98f3bdaa	bf3b3448-1ec3-4f29-87e3-7fc90bc83308	2025-05-02	\N	\N	\N	78.590000	\N	GENERATED	2025-11-04 12:45:10.28664+01
ef973857-164d-4d33-806e-48155178c455	bf3b3448-1ec3-4f29-87e3-7fc90bc83308	2025-05-03	\N	\N	\N	77.460000	\N	GENERATED	2025-11-04 12:45:10.287428+01
c3b226d2-d3c9-4341-b780-5a20b928c216	bf3b3448-1ec3-4f29-87e3-7fc90bc83308	2025-05-04	\N	\N	\N	78.630000	\N	GENERATED	2025-11-04 12:45:10.288398+01
0da774a6-aa50-4276-ad28-c2374e4503f9	bf3b3448-1ec3-4f29-87e3-7fc90bc83308	2025-05-05	\N	\N	\N	77.980000	\N	GENERATED	2025-11-04 12:45:10.289269+01
1f1262c9-4ad5-4e03-a7db-55a168ddce2a	bf3b3448-1ec3-4f29-87e3-7fc90bc83308	2025-05-06	\N	\N	\N	77.550000	\N	GENERATED	2025-11-04 12:45:10.290018+01
65559d73-7823-4f70-b541-7b55d4cb83fd	bf3b3448-1ec3-4f29-87e3-7fc90bc83308	2025-05-07	\N	\N	\N	78.120000	\N	GENERATED	2025-11-04 12:45:10.29079+01
f6cff707-4b08-41ea-acfc-b79467846f80	bf3b3448-1ec3-4f29-87e3-7fc90bc83308	2025-05-08	\N	\N	\N	78.770000	\N	GENERATED	2025-11-04 12:45:10.291493+01
7fd3ebdb-72c0-47c0-beee-b46ed0ce96b6	bf3b3448-1ec3-4f29-87e3-7fc90bc83308	2025-05-09	\N	\N	\N	78.450000	\N	GENERATED	2025-11-04 12:45:10.292302+01
157c0086-d489-4838-a76b-93fd65be4bc5	bf3b3448-1ec3-4f29-87e3-7fc90bc83308	2025-05-10	\N	\N	\N	78.760000	\N	GENERATED	2025-11-04 12:45:10.293+01
795150bd-0977-4720-9b96-0406076e5db4	bf3b3448-1ec3-4f29-87e3-7fc90bc83308	2025-05-11	\N	\N	\N	78.290000	\N	GENERATED	2025-11-04 12:45:10.293696+01
c82b8d23-7a5e-4c0d-9f1a-f694def4b003	bf3b3448-1ec3-4f29-87e3-7fc90bc83308	2025-05-12	\N	\N	\N	77.870000	\N	GENERATED	2025-11-04 12:45:10.294398+01
c80c7d39-c2e4-4d86-affb-4ecc10264702	bf3b3448-1ec3-4f29-87e3-7fc90bc83308	2025-05-13	\N	\N	\N	78.490000	\N	GENERATED	2025-11-04 12:45:10.295507+01
dcb3de62-0394-4563-89f4-2516ae89e264	bf3b3448-1ec3-4f29-87e3-7fc90bc83308	2025-05-14	\N	\N	\N	78.770000	\N	GENERATED	2025-11-04 12:45:10.296216+01
e0dab45c-4553-47d2-af18-b871f980a21b	bf3b3448-1ec3-4f29-87e3-7fc90bc83308	2025-05-15	\N	\N	\N	78.070000	\N	GENERATED	2025-11-04 12:45:10.296931+01
75d94bfc-581b-4a3f-8a2e-b6dc8f379708	bf3b3448-1ec3-4f29-87e3-7fc90bc83308	2025-05-16	\N	\N	\N	77.550000	\N	GENERATED	2025-11-04 12:45:10.2976+01
1915b181-654b-41fd-a470-18b4708bdb58	bf3b3448-1ec3-4f29-87e3-7fc90bc83308	2025-05-17	\N	\N	\N	78.700000	\N	GENERATED	2025-11-04 12:45:10.29832+01
0288593f-789f-4805-9d45-a66739573f7e	bf3b3448-1ec3-4f29-87e3-7fc90bc83308	2025-05-18	\N	\N	\N	78.540000	\N	GENERATED	2025-11-04 12:45:10.298993+01
9f0efe9e-97c6-4141-bee1-dbde904dc027	bf3b3448-1ec3-4f29-87e3-7fc90bc83308	2025-05-19	\N	\N	\N	77.620000	\N	GENERATED	2025-11-04 12:45:10.299706+01
ea3dcb22-520b-46bf-8264-0866188868b6	bf3b3448-1ec3-4f29-87e3-7fc90bc83308	2025-05-20	\N	\N	\N	78.490000	\N	GENERATED	2025-11-04 12:45:10.30096+01
1161d004-f7ae-48b8-9a1d-8bac8d3520e6	bf3b3448-1ec3-4f29-87e3-7fc90bc83308	2025-05-21	\N	\N	\N	78.030000	\N	GENERATED	2025-11-04 12:45:10.302089+01
3095e2c7-56d3-416e-9ad1-237f2303bf9e	bf3b3448-1ec3-4f29-87e3-7fc90bc83308	2025-05-22	\N	\N	\N	78.310000	\N	GENERATED	2025-11-04 12:45:10.303425+01
758ea61a-857b-4046-8b14-81e23ef39e7d	bf3b3448-1ec3-4f29-87e3-7fc90bc83308	2025-05-23	\N	\N	\N	78.000000	\N	GENERATED	2025-11-04 12:45:10.304534+01
5b381cbf-2906-4a04-ac07-b5335644f119	bf3b3448-1ec3-4f29-87e3-7fc90bc83308	2025-05-24	\N	\N	\N	78.740000	\N	GENERATED	2025-11-04 12:45:10.305452+01
0ec2d29b-a285-4983-95ca-30fd7ab8b4a2	bf3b3448-1ec3-4f29-87e3-7fc90bc83308	2025-05-25	\N	\N	\N	78.740000	\N	GENERATED	2025-11-04 12:45:10.306444+01
1d9185f8-ff95-4dda-baa7-615eac45db7f	bf3b3448-1ec3-4f29-87e3-7fc90bc83308	2025-05-26	\N	\N	\N	77.890000	\N	GENERATED	2025-11-04 12:45:10.307512+01
20deb7c9-6086-437e-8586-5e621f854f58	bf3b3448-1ec3-4f29-87e3-7fc90bc83308	2025-05-27	\N	\N	\N	79.050000	\N	GENERATED	2025-11-04 12:45:10.308412+01
551db3ce-5040-4e39-a232-15bf98ce859c	bf3b3448-1ec3-4f29-87e3-7fc90bc83308	2025-05-28	\N	\N	\N	78.200000	\N	GENERATED	2025-11-04 12:45:10.309306+01
5179d413-d134-4c6e-a31a-3f5827fd9eb8	bf3b3448-1ec3-4f29-87e3-7fc90bc83308	2025-05-29	\N	\N	\N	79.040000	\N	GENERATED	2025-11-04 12:45:10.310189+01
312e2f27-2c7a-49d3-8537-a46b9c87b6c7	bf3b3448-1ec3-4f29-87e3-7fc90bc83308	2025-05-30	\N	\N	\N	77.760000	\N	GENERATED	2025-11-04 12:45:10.311063+01
844ddcd6-cbe6-493f-9222-be786944b444	bf3b3448-1ec3-4f29-87e3-7fc90bc83308	2025-05-31	\N	\N	\N	78.240000	\N	GENERATED	2025-11-04 12:45:10.311941+01
4ece6d68-9a38-4950-aea0-7b809fa4a863	bf3b3448-1ec3-4f29-87e3-7fc90bc83308	2025-06-01	\N	\N	\N	77.940000	\N	GENERATED	2025-11-04 12:45:10.312819+01
bf760a91-b14a-4a93-836d-cee7fe41ccf3	bf3b3448-1ec3-4f29-87e3-7fc90bc83308	2025-06-02	\N	\N	\N	77.920000	\N	GENERATED	2025-11-04 12:45:10.313705+01
500f2bdc-3f35-4a53-8989-84cf1956cbd1	bf3b3448-1ec3-4f29-87e3-7fc90bc83308	2025-06-03	\N	\N	\N	78.200000	\N	GENERATED	2025-11-04 12:45:10.314607+01
87d473b1-0cfd-42f8-ac4e-a3c17041f628	bf3b3448-1ec3-4f29-87e3-7fc90bc83308	2025-06-04	\N	\N	\N	78.330000	\N	GENERATED	2025-11-04 12:45:10.315405+01
e6b929d4-4589-40d4-b0fb-4b1d6a9f8fc9	bf3b3448-1ec3-4f29-87e3-7fc90bc83308	2025-06-05	\N	\N	\N	79.160000	\N	GENERATED	2025-11-04 12:45:10.31619+01
238acac1-48bf-4d5f-a230-01cecc5f22dd	bf3b3448-1ec3-4f29-87e3-7fc90bc83308	2025-06-06	\N	\N	\N	78.460000	\N	GENERATED	2025-11-04 12:45:10.316895+01
4b9ff296-14c6-4300-bb37-09c1bc52290f	bf3b3448-1ec3-4f29-87e3-7fc90bc83308	2025-06-07	\N	\N	\N	78.580000	\N	GENERATED	2025-11-04 12:45:10.317813+01
b3aa6a70-ed0b-4f33-9090-dc4785851248	bf3b3448-1ec3-4f29-87e3-7fc90bc83308	2025-06-08	\N	\N	\N	78.510000	\N	GENERATED	2025-11-04 12:45:10.318922+01
77754be2-bb21-433f-a7a8-57005e82d047	bf3b3448-1ec3-4f29-87e3-7fc90bc83308	2025-06-09	\N	\N	\N	78.410000	\N	GENERATED	2025-11-04 12:45:10.320072+01
f2afbad3-e7b6-4451-8417-3e8cb15b9059	bf3b3448-1ec3-4f29-87e3-7fc90bc83308	2025-06-10	\N	\N	\N	78.620000	\N	GENERATED	2025-11-04 12:45:10.320955+01
3a7b62de-f384-4d8b-9a38-1cd33f23e99a	bf3b3448-1ec3-4f29-87e3-7fc90bc83308	2025-06-11	\N	\N	\N	78.840000	\N	GENERATED	2025-11-04 12:45:10.322059+01
432276a9-08a9-49e2-a97e-0aff56ac8c82	bf3b3448-1ec3-4f29-87e3-7fc90bc83308	2025-06-12	\N	\N	\N	78.690000	\N	GENERATED	2025-11-04 12:45:10.322979+01
4aecda65-0376-4bea-9792-f94fe2435ccc	bf3b3448-1ec3-4f29-87e3-7fc90bc83308	2025-06-13	\N	\N	\N	78.190000	\N	GENERATED	2025-11-04 12:45:10.323889+01
f246a7a4-bc52-4112-990f-e8b790b2a2a1	bf3b3448-1ec3-4f29-87e3-7fc90bc83308	2025-06-14	\N	\N	\N	78.130000	\N	GENERATED	2025-11-04 12:45:10.324817+01
f4588fcf-705e-4566-bedd-b802e7763b9b	bf3b3448-1ec3-4f29-87e3-7fc90bc83308	2025-06-15	\N	\N	\N	78.360000	\N	GENERATED	2025-11-04 12:45:10.325752+01
8559b819-aab3-4758-a50d-870518659bfd	bf3b3448-1ec3-4f29-87e3-7fc90bc83308	2025-06-16	\N	\N	\N	78.170000	\N	GENERATED	2025-11-04 12:45:10.326667+01
f84772d6-2431-4e38-92c4-713e9d56a2c9	bf3b3448-1ec3-4f29-87e3-7fc90bc83308	2025-06-17	\N	\N	\N	78.880000	\N	GENERATED	2025-11-04 12:45:10.327584+01
4010a820-a672-46ec-9be9-1880d4d965f8	bf3b3448-1ec3-4f29-87e3-7fc90bc83308	2025-06-18	\N	\N	\N	78.290000	\N	GENERATED	2025-11-04 12:45:10.328665+01
9c1c8556-6050-4d16-a189-7968c255fd3a	bf3b3448-1ec3-4f29-87e3-7fc90bc83308	2025-06-19	\N	\N	\N	79.350000	\N	GENERATED	2025-11-04 12:45:10.329619+01
7f267ecc-3f76-465d-8dd7-efbd9619c5a6	bf3b3448-1ec3-4f29-87e3-7fc90bc83308	2025-06-20	\N	\N	\N	78.660000	\N	GENERATED	2025-11-04 12:45:10.330715+01
dd1e0e9e-cb3a-4c26-aeb7-3d4b1cfd8f90	bf3b3448-1ec3-4f29-87e3-7fc90bc83308	2025-06-21	\N	\N	\N	78.420000	\N	GENERATED	2025-11-04 12:45:10.331734+01
b3e67f6d-98b5-4677-b90b-b6f623d56c9e	bf3b3448-1ec3-4f29-87e3-7fc90bc83308	2025-06-22	\N	\N	\N	79.020000	\N	GENERATED	2025-11-04 12:45:10.332532+01
32e1aebf-f914-4cec-802b-3809f989e1d1	bf3b3448-1ec3-4f29-87e3-7fc90bc83308	2025-06-23	\N	\N	\N	78.850000	\N	GENERATED	2025-11-04 12:45:10.333326+01
ccb9fa82-054d-46fa-8d70-afeb39a4a24d	bf3b3448-1ec3-4f29-87e3-7fc90bc83308	2025-06-24	\N	\N	\N	78.690000	\N	GENERATED	2025-11-04 12:45:10.334111+01
605ba68c-0323-497e-bcb5-d10b02d69bdd	bf3b3448-1ec3-4f29-87e3-7fc90bc83308	2025-06-25	\N	\N	\N	78.150000	\N	GENERATED	2025-11-04 12:45:10.335029+01
e521c837-274b-43d5-95f8-d62fc1006acb	bf3b3448-1ec3-4f29-87e3-7fc90bc83308	2025-06-26	\N	\N	\N	78.550000	\N	GENERATED	2025-11-04 12:45:10.335779+01
e2e28256-9c04-4d85-88e1-185ad546bd3b	bf3b3448-1ec3-4f29-87e3-7fc90bc83308	2025-06-27	\N	\N	\N	78.190000	\N	GENERATED	2025-11-04 12:45:10.33649+01
c35e543d-0aa4-4d5a-92d1-e2d982afc378	bf3b3448-1ec3-4f29-87e3-7fc90bc83308	2025-06-28	\N	\N	\N	78.670000	\N	GENERATED	2025-11-04 12:45:10.337206+01
8369e828-a40a-4eba-afe3-86eedef8fc2b	bf3b3448-1ec3-4f29-87e3-7fc90bc83308	2025-06-29	\N	\N	\N	78.900000	\N	GENERATED	2025-11-04 12:45:10.337904+01
765a9ded-86f7-440b-b6d7-d8e1ae4fea6f	bf3b3448-1ec3-4f29-87e3-7fc90bc83308	2025-06-30	\N	\N	\N	78.180000	\N	GENERATED	2025-11-04 12:45:10.338591+01
5e4f6863-d3da-44f5-a772-5d4102ec7ec5	bf3b3448-1ec3-4f29-87e3-7fc90bc83308	2025-07-01	\N	\N	\N	79.300000	\N	GENERATED	2025-11-04 12:45:10.339272+01
61b569f0-485c-48b4-be5e-7567c098fe52	bf3b3448-1ec3-4f29-87e3-7fc90bc83308	2025-07-02	\N	\N	\N	79.120000	\N	GENERATED	2025-11-04 12:45:10.339942+01
325eb3ee-b741-4c76-9b57-3599734c5427	bf3b3448-1ec3-4f29-87e3-7fc90bc83308	2025-07-03	\N	\N	\N	78.760000	\N	GENERATED	2025-11-04 12:45:10.340612+01
3ba27441-fae1-448f-b1f4-6fcb29ed84b7	bf3b3448-1ec3-4f29-87e3-7fc90bc83308	2025-07-04	\N	\N	\N	78.670000	\N	GENERATED	2025-11-04 12:45:10.341279+01
cdbff027-2436-4842-b072-5d025b9b0f90	bf3b3448-1ec3-4f29-87e3-7fc90bc83308	2025-07-05	\N	\N	\N	78.940000	\N	GENERATED	2025-11-04 12:45:10.341937+01
f51f4bbf-0482-479b-b145-a9a9ba6c831e	bf3b3448-1ec3-4f29-87e3-7fc90bc83308	2025-07-06	\N	\N	\N	78.900000	\N	GENERATED	2025-11-04 12:45:10.342611+01
abc236b8-40da-4cac-85a3-2ce7bfbba31b	bf3b3448-1ec3-4f29-87e3-7fc90bc83308	2025-07-07	\N	\N	\N	79.040000	\N	GENERATED	2025-11-04 12:45:10.343272+01
64e6f0e4-ae5a-4965-b491-13d790f1cfa4	bf3b3448-1ec3-4f29-87e3-7fc90bc83308	2025-07-08	\N	\N	\N	79.760000	\N	GENERATED	2025-11-04 12:45:10.343935+01
3f94944b-d136-49cd-9975-d9b3341b039f	bf3b3448-1ec3-4f29-87e3-7fc90bc83308	2025-07-09	\N	\N	\N	79.220000	\N	GENERATED	2025-11-04 12:45:10.344609+01
8d4237a1-b108-447f-aa74-1cbc27a91f43	bf3b3448-1ec3-4f29-87e3-7fc90bc83308	2025-07-10	\N	\N	\N	79.060000	\N	GENERATED	2025-11-04 12:45:10.345266+01
58ea3e33-69ec-4f1f-ba64-cbc3e87c9a70	bf3b3448-1ec3-4f29-87e3-7fc90bc83308	2025-07-11	\N	\N	\N	78.780000	\N	GENERATED	2025-11-04 12:45:10.345923+01
c82a5a64-ed6c-4fff-8844-22e3c79dd1fc	bf3b3448-1ec3-4f29-87e3-7fc90bc83308	2025-07-12	\N	\N	\N	79.170000	\N	GENERATED	2025-11-04 12:45:10.346611+01
63e9ab26-d106-4eac-9887-11b90a953668	bf3b3448-1ec3-4f29-87e3-7fc90bc83308	2025-07-13	\N	\N	\N	78.950000	\N	GENERATED	2025-11-04 12:45:10.347268+01
6f9320c3-0a3e-4449-8a7a-46e01b7663aa	bf3b3448-1ec3-4f29-87e3-7fc90bc83308	2025-07-14	\N	\N	\N	79.350000	\N	GENERATED	2025-11-04 12:45:10.347922+01
61a279b7-9b1e-4da0-a0a9-e51789b89aee	bf3b3448-1ec3-4f29-87e3-7fc90bc83308	2025-07-15	\N	\N	\N	78.790000	\N	GENERATED	2025-11-04 12:45:10.348605+01
c1e37e6a-a0f1-4ee0-9f15-343b605d5ed7	bf3b3448-1ec3-4f29-87e3-7fc90bc83308	2025-07-16	\N	\N	\N	79.750000	\N	GENERATED	2025-11-04 12:45:10.349262+01
3f2bc6d7-f149-4315-8b59-da43b0edd603	bf3b3448-1ec3-4f29-87e3-7fc90bc83308	2025-07-17	\N	\N	\N	78.730000	\N	GENERATED	2025-11-04 12:45:10.349917+01
e245dbc0-1fe4-4924-bfd9-a8cdebde1bcb	bf3b3448-1ec3-4f29-87e3-7fc90bc83308	2025-07-18	\N	\N	\N	79.120000	\N	GENERATED	2025-11-04 12:45:10.350715+01
10e6593d-747b-4e94-91c0-af5078f94848	bf3b3448-1ec3-4f29-87e3-7fc90bc83308	2025-07-19	\N	\N	\N	79.020000	\N	GENERATED	2025-11-04 12:45:10.351508+01
a0c690f8-0199-46fa-ac7e-3cd1a7193b0c	bf3b3448-1ec3-4f29-87e3-7fc90bc83308	2025-07-20	\N	\N	\N	78.600000	\N	GENERATED	2025-11-04 12:45:10.352242+01
97a8fa21-0527-41dc-acb4-ea911fafe8f8	bf3b3448-1ec3-4f29-87e3-7fc90bc83308	2025-07-21	\N	\N	\N	78.780000	\N	GENERATED	2025-11-04 12:45:10.352938+01
81f606ec-1f26-4099-b3d0-1de1492449e3	bf3b3448-1ec3-4f29-87e3-7fc90bc83308	2025-07-22	\N	\N	\N	79.120000	\N	GENERATED	2025-11-04 12:45:10.353595+01
4c8cc6ac-d942-4ff8-87c9-dd30a5644dfc	bf3b3448-1ec3-4f29-87e3-7fc90bc83308	2025-07-23	\N	\N	\N	79.340000	\N	GENERATED	2025-11-04 12:45:10.354276+01
c6df2934-72c5-42da-bad4-cad38940d3a1	bf3b3448-1ec3-4f29-87e3-7fc90bc83308	2025-07-24	\N	\N	\N	78.690000	\N	GENERATED	2025-11-04 12:45:10.355393+01
ac383a29-3b1a-44d9-8d16-75220f1064ef	bf3b3448-1ec3-4f29-87e3-7fc90bc83308	2025-07-25	\N	\N	\N	78.800000	\N	GENERATED	2025-11-04 12:45:10.356062+01
8016425c-a199-410e-a0cd-9587db47babc	bf3b3448-1ec3-4f29-87e3-7fc90bc83308	2025-07-26	\N	\N	\N	80.030000	\N	GENERATED	2025-11-04 12:45:10.356732+01
4eb35b40-3002-4e54-9715-0f10a5fb28fc	bf3b3448-1ec3-4f29-87e3-7fc90bc83308	2025-07-27	\N	\N	\N	79.280000	\N	GENERATED	2025-11-04 12:45:10.357382+01
6596d3b0-1f27-44db-a0a9-8debf35a87be	bf3b3448-1ec3-4f29-87e3-7fc90bc83308	2025-07-28	\N	\N	\N	79.660000	\N	GENERATED	2025-11-04 12:45:10.358051+01
f570cd53-f7dd-4131-8705-99b3de7b39d2	bf3b3448-1ec3-4f29-87e3-7fc90bc83308	2025-07-29	\N	\N	\N	79.940000	\N	GENERATED	2025-11-04 12:45:10.358706+01
62743c04-c9d3-4d8d-80b7-9ab492591f39	bf3b3448-1ec3-4f29-87e3-7fc90bc83308	2025-07-30	\N	\N	\N	78.740000	\N	GENERATED	2025-11-04 12:45:10.359356+01
9a11b879-5cab-4dc6-9cac-a79f94e122b5	bf3b3448-1ec3-4f29-87e3-7fc90bc83308	2025-07-31	\N	\N	\N	79.450000	\N	GENERATED	2025-11-04 12:45:10.360015+01
e9956a40-d125-45ea-8def-2397a4913580	bf3b3448-1ec3-4f29-87e3-7fc90bc83308	2025-08-01	\N	\N	\N	79.550000	\N	GENERATED	2025-11-04 12:45:10.360764+01
19580434-e2af-4143-ad37-7798531bb228	bf3b3448-1ec3-4f29-87e3-7fc90bc83308	2025-08-02	\N	\N	\N	79.020000	\N	GENERATED	2025-11-04 12:45:10.361433+01
0acc7a26-38fe-4e98-bf6a-f46d14abb10d	bf3b3448-1ec3-4f29-87e3-7fc90bc83308	2025-08-03	\N	\N	\N	78.910000	\N	GENERATED	2025-11-04 12:45:10.362092+01
a3c778b2-5355-42d7-a473-153dbc2a29f4	bf3b3448-1ec3-4f29-87e3-7fc90bc83308	2025-08-04	\N	\N	\N	80.100000	\N	GENERATED	2025-11-04 12:45:10.362768+01
74db477e-4446-4691-a0c8-c3677061e941	bf3b3448-1ec3-4f29-87e3-7fc90bc83308	2025-08-05	\N	\N	\N	78.790000	\N	GENERATED	2025-11-04 12:45:10.363436+01
fd6ce2aa-0681-4c1d-97d3-0da1cdc12ddb	bf3b3448-1ec3-4f29-87e3-7fc90bc83308	2025-08-06	\N	\N	\N	79.410000	\N	GENERATED	2025-11-04 12:45:10.364093+01
d4ab2ccc-10b8-40c6-bfe1-84f2ba8c6a8d	bf3b3448-1ec3-4f29-87e3-7fc90bc83308	2025-08-07	\N	\N	\N	78.990000	\N	GENERATED	2025-11-04 12:45:10.364746+01
20df5a66-d994-4868-ab28-8b488fe904a8	bf3b3448-1ec3-4f29-87e3-7fc90bc83308	2025-08-08	\N	\N	\N	79.060000	\N	GENERATED	2025-11-04 12:45:10.365406+01
d4bd40fe-6dbd-4901-9016-3423d2301d0c	bf3b3448-1ec3-4f29-87e3-7fc90bc83308	2025-08-09	\N	\N	\N	79.800000	\N	GENERATED	2025-11-04 12:45:10.366221+01
33f1608f-2236-4018-8ca9-6751bb891ce6	bf3b3448-1ec3-4f29-87e3-7fc90bc83308	2025-08-10	\N	\N	\N	79.420000	\N	GENERATED	2025-11-04 12:45:10.36715+01
c5e8f76d-e16c-4cc6-a0ad-d38cc124eaab	bf3b3448-1ec3-4f29-87e3-7fc90bc83308	2025-08-11	\N	\N	\N	79.050000	\N	GENERATED	2025-11-04 12:45:10.368007+01
f283153f-8515-4f30-937c-c423c800901a	bf3b3448-1ec3-4f29-87e3-7fc90bc83308	2025-08-12	\N	\N	\N	79.430000	\N	GENERATED	2025-11-04 12:45:10.368684+01
f95c228e-d6c0-4dbc-b2bf-402214154066	bf3b3448-1ec3-4f29-87e3-7fc90bc83308	2025-08-13	\N	\N	\N	79.450000	\N	GENERATED	2025-11-04 12:45:10.369367+01
bcb5d115-351a-4124-a8dc-a7872a731dd3	bf3b3448-1ec3-4f29-87e3-7fc90bc83308	2025-08-14	\N	\N	\N	79.720000	\N	GENERATED	2025-11-04 12:45:10.370028+01
f8dba5a5-74cc-418d-aba3-83574f9b9086	bf3b3448-1ec3-4f29-87e3-7fc90bc83308	2025-08-15	\N	\N	\N	79.600000	\N	GENERATED	2025-11-04 12:45:10.370687+01
fd353ebe-a0eb-4e32-b2db-9ca1d53721b6	bf3b3448-1ec3-4f29-87e3-7fc90bc83308	2025-08-16	\N	\N	\N	79.030000	\N	GENERATED	2025-11-04 12:45:10.371343+01
b94b1071-eb03-4c79-b709-5b87b732467d	bf3b3448-1ec3-4f29-87e3-7fc90bc83308	2025-08-17	\N	\N	\N	80.110000	\N	GENERATED	2025-11-04 12:45:10.372002+01
9c867c41-8701-4e31-ac93-77b962a6382e	bf3b3448-1ec3-4f29-87e3-7fc90bc83308	2025-08-18	\N	\N	\N	79.160000	\N	GENERATED	2025-11-04 12:45:10.372951+01
a601c041-4509-4f49-8544-b554c659006a	bf3b3448-1ec3-4f29-87e3-7fc90bc83308	2025-08-19	\N	\N	\N	79.580000	\N	GENERATED	2025-11-04 12:45:10.373623+01
73d5557a-b5a7-4635-bb48-b6a96323ef9f	bf3b3448-1ec3-4f29-87e3-7fc90bc83308	2025-08-20	\N	\N	\N	79.650000	\N	GENERATED	2025-11-04 12:45:10.374286+01
63d14f9c-5763-44b5-89f9-7aa9a2e827a1	bf3b3448-1ec3-4f29-87e3-7fc90bc83308	2025-08-21	\N	\N	\N	79.030000	\N	GENERATED	2025-11-04 12:45:10.374944+01
d15c916f-59fe-40b5-adda-0d048b66f2d0	bf3b3448-1ec3-4f29-87e3-7fc90bc83308	2025-08-22	\N	\N	\N	79.870000	\N	GENERATED	2025-11-04 12:45:10.375588+01
cf704db1-0703-449f-a9f9-3ef320415f5e	bf3b3448-1ec3-4f29-87e3-7fc90bc83308	2025-08-23	\N	\N	\N	79.890000	\N	GENERATED	2025-11-04 12:45:10.376236+01
fadbd181-44e5-4470-9256-f260d9f2e2a8	bf3b3448-1ec3-4f29-87e3-7fc90bc83308	2025-08-24	\N	\N	\N	79.660000	\N	GENERATED	2025-11-04 12:45:10.376889+01
f7bc20d4-e321-47d2-82ca-f72035b3207e	bf3b3448-1ec3-4f29-87e3-7fc90bc83308	2025-08-25	\N	\N	\N	79.330000	\N	GENERATED	2025-11-04 12:45:10.377552+01
667f4163-40b1-4a0a-a186-dc88bdaef03c	bf3b3448-1ec3-4f29-87e3-7fc90bc83308	2025-08-26	\N	\N	\N	79.210000	\N	GENERATED	2025-11-04 12:45:10.378348+01
fca70c13-0cc1-4136-8411-624b3b027209	bf3b3448-1ec3-4f29-87e3-7fc90bc83308	2025-08-27	\N	\N	\N	79.150000	\N	GENERATED	2025-11-04 12:45:10.379043+01
4aa77e82-038f-41df-82b7-5e76b6ab1593	bf3b3448-1ec3-4f29-87e3-7fc90bc83308	2025-08-28	\N	\N	\N	79.920000	\N	GENERATED	2025-11-04 12:45:10.379723+01
c6793065-f26a-42c1-acd5-6c0afe73a069	bf3b3448-1ec3-4f29-87e3-7fc90bc83308	2025-08-29	\N	\N	\N	80.520000	\N	GENERATED	2025-11-04 12:45:10.380374+01
8446e4a7-1dbf-41ea-b7e3-ee4efa94f8b1	bf3b3448-1ec3-4f29-87e3-7fc90bc83308	2025-08-30	\N	\N	\N	79.640000	\N	GENERATED	2025-11-04 12:45:10.381024+01
24fb248e-e663-420e-9f6e-5ae76433df42	bf3b3448-1ec3-4f29-87e3-7fc90bc83308	2025-08-31	\N	\N	\N	80.240000	\N	GENERATED	2025-11-04 12:45:10.381852+01
d7be8b1a-e633-4e4e-ae54-58941ad0510d	bf3b3448-1ec3-4f29-87e3-7fc90bc83308	2025-09-01	\N	\N	\N	80.000000	\N	GENERATED	2025-11-04 12:45:10.38292+01
6b4fe860-9821-4973-9760-183d48392555	bf3b3448-1ec3-4f29-87e3-7fc90bc83308	2025-09-02	\N	\N	\N	79.860000	\N	GENERATED	2025-11-04 12:45:10.383608+01
ca20c84a-4209-4b90-87f6-9cb8c0723abe	bf3b3448-1ec3-4f29-87e3-7fc90bc83308	2025-09-03	\N	\N	\N	79.240000	\N	GENERATED	2025-11-04 12:45:10.384371+01
75d0c35d-6d25-4aad-b332-3042280167ab	bf3b3448-1ec3-4f29-87e3-7fc90bc83308	2025-09-04	\N	\N	\N	79.490000	\N	GENERATED	2025-11-04 12:45:10.385137+01
e58abfbf-3f4b-467d-8fab-1d591f3a51e4	bf3b3448-1ec3-4f29-87e3-7fc90bc83308	2025-09-05	\N	\N	\N	79.580000	\N	GENERATED	2025-11-04 12:45:10.385814+01
823797e0-0d26-40ca-94a7-74dd983b9dc5	bf3b3448-1ec3-4f29-87e3-7fc90bc83308	2025-09-06	\N	\N	\N	79.720000	\N	GENERATED	2025-11-04 12:45:10.386484+01
1bc978d9-76f8-495f-b1a5-2c4b63934324	bf3b3448-1ec3-4f29-87e3-7fc90bc83308	2025-09-07	\N	\N	\N	79.460000	\N	GENERATED	2025-11-04 12:45:10.387138+01
17b86b40-a589-4e28-89a3-d24447681413	bf3b3448-1ec3-4f29-87e3-7fc90bc83308	2025-09-08	\N	\N	\N	79.610000	\N	GENERATED	2025-11-04 12:45:10.387819+01
26062d29-86f0-4bdd-bad6-6ed6562aa520	bf3b3448-1ec3-4f29-87e3-7fc90bc83308	2025-09-09	\N	\N	\N	79.960000	\N	GENERATED	2025-11-04 12:45:10.388464+01
525ca7be-a440-4abf-b003-10421fdc6f7b	bf3b3448-1ec3-4f29-87e3-7fc90bc83308	2025-09-10	\N	\N	\N	80.220000	\N	GENERATED	2025-11-04 12:45:10.389126+01
5c5cbcbe-2ae8-4d9a-9baa-504f0c253b6b	bf3b3448-1ec3-4f29-87e3-7fc90bc83308	2025-09-11	\N	\N	\N	79.430000	\N	GENERATED	2025-11-04 12:45:10.389806+01
4a622c30-ed34-4104-bfc4-c2b63d807308	bf3b3448-1ec3-4f29-87e3-7fc90bc83308	2025-09-12	\N	\N	\N	80.010000	\N	GENERATED	2025-11-04 12:45:10.390636+01
50f012e7-0abd-472d-8240-e01430494cc8	bf3b3448-1ec3-4f29-87e3-7fc90bc83308	2025-09-13	\N	\N	\N	80.450000	\N	GENERATED	2025-11-04 12:45:10.391442+01
6c6d6b75-bcbd-41b6-b676-a6efb1d56b22	bf3b3448-1ec3-4f29-87e3-7fc90bc83308	2025-09-14	\N	\N	\N	80.890000	\N	GENERATED	2025-11-04 12:45:10.392201+01
a4d47980-0218-4821-b51f-99aa9c1c291f	bf3b3448-1ec3-4f29-87e3-7fc90bc83308	2025-09-15	\N	\N	\N	79.700000	\N	GENERATED	2025-11-04 12:45:10.392934+01
a48ef343-14e6-4bd1-8082-6b38eacc9a4d	bf3b3448-1ec3-4f29-87e3-7fc90bc83308	2025-09-16	\N	\N	\N	79.520000	\N	GENERATED	2025-11-04 12:45:10.393675+01
2f1112df-85f4-4fee-9835-daf58b279ff8	bf3b3448-1ec3-4f29-87e3-7fc90bc83308	2025-09-17	\N	\N	\N	80.650000	\N	GENERATED	2025-11-04 12:45:10.394342+01
900f279f-ca16-4410-97dd-d96a724a51ac	bf3b3448-1ec3-4f29-87e3-7fc90bc83308	2025-09-18	\N	\N	\N	79.790000	\N	GENERATED	2025-11-04 12:45:10.395035+01
1de0e416-a244-4208-84fe-1ee396bcd6dd	bf3b3448-1ec3-4f29-87e3-7fc90bc83308	2025-09-19	\N	\N	\N	80.540000	\N	GENERATED	2025-11-04 12:45:10.395697+01
bc11d319-cf89-4545-ade5-8f48f7d55c79	bf3b3448-1ec3-4f29-87e3-7fc90bc83308	2025-09-20	\N	\N	\N	80.510000	\N	GENERATED	2025-11-04 12:45:10.39636+01
89e5231c-40d6-4e38-b269-e647580fff46	bf3b3448-1ec3-4f29-87e3-7fc90bc83308	2025-09-21	\N	\N	\N	80.680000	\N	GENERATED	2025-11-04 12:45:10.397146+01
8537f3c3-d1d8-4a4b-8815-f9bec7054734	bf3b3448-1ec3-4f29-87e3-7fc90bc83308	2025-09-22	\N	\N	\N	80.150000	\N	GENERATED	2025-11-04 12:45:10.398096+01
76481300-8a3b-4e55-91c7-d3a44bd26f45	bf3b3448-1ec3-4f29-87e3-7fc90bc83308	2025-09-23	\N	\N	\N	80.990000	\N	GENERATED	2025-11-04 12:45:10.398776+01
52707ab2-b7c6-457d-bf0b-9d48308a9054	bf3b3448-1ec3-4f29-87e3-7fc90bc83308	2025-09-24	\N	\N	\N	79.580000	\N	GENERATED	2025-11-04 12:45:10.399472+01
0e3a7178-cba3-439f-9069-49569e1faaaf	bf3b3448-1ec3-4f29-87e3-7fc90bc83308	2025-09-25	\N	\N	\N	80.690000	\N	GENERATED	2025-11-04 12:45:10.400137+01
4d04f06c-4fd5-4d14-88d3-a3e074a991ba	bf3b3448-1ec3-4f29-87e3-7fc90bc83308	2025-09-26	\N	\N	\N	79.930000	\N	GENERATED	2025-11-04 12:45:10.400801+01
b5a5267d-3fa7-432b-b7aa-1971911a2a16	bf3b3448-1ec3-4f29-87e3-7fc90bc83308	2025-09-27	\N	\N	\N	79.910000	\N	GENERATED	2025-11-04 12:45:10.401479+01
d28e850f-189f-468b-b44d-bde9375d5c28	bf3b3448-1ec3-4f29-87e3-7fc90bc83308	2025-09-28	\N	\N	\N	80.510000	\N	GENERATED	2025-11-04 12:45:10.402135+01
e8de7fea-4bb0-451f-9d78-e92d426cd95e	bf3b3448-1ec3-4f29-87e3-7fc90bc83308	2025-09-29	\N	\N	\N	80.590000	\N	GENERATED	2025-11-04 12:45:10.402795+01
a981f40e-2580-48e5-b86f-767ae4e5ac89	bf3b3448-1ec3-4f29-87e3-7fc90bc83308	2025-09-30	\N	\N	\N	81.160000	\N	GENERATED	2025-11-04 12:45:10.403467+01
38ca20bb-0835-49ee-973f-aed1171a32af	bf3b3448-1ec3-4f29-87e3-7fc90bc83308	2025-10-01	\N	\N	\N	79.730000	\N	GENERATED	2025-11-04 12:45:10.404119+01
26bdba8d-5ec1-40ff-9f8c-f8bf5f059a9f	bf3b3448-1ec3-4f29-87e3-7fc90bc83308	2025-10-02	\N	\N	\N	80.260000	\N	GENERATED	2025-11-04 12:45:10.404783+01
302321fb-2fd5-494f-911d-4404bb65e1ed	bf3b3448-1ec3-4f29-87e3-7fc90bc83308	2025-10-03	\N	\N	\N	80.040000	\N	GENERATED	2025-11-04 12:45:10.405446+01
1a86e4f1-627b-4901-8b0f-3f8bff493f07	bf3b3448-1ec3-4f29-87e3-7fc90bc83308	2025-10-04	\N	\N	\N	80.570000	\N	GENERATED	2025-11-04 12:45:10.406124+01
784dfc06-df45-4125-a1f6-a233bb3fd07a	bf3b3448-1ec3-4f29-87e3-7fc90bc83308	2025-10-05	\N	\N	\N	80.850000	\N	GENERATED	2025-11-04 12:45:10.406795+01
7692adde-f876-404b-aad1-81a150b24ad1	bf3b3448-1ec3-4f29-87e3-7fc90bc83308	2025-10-06	\N	\N	\N	79.960000	\N	GENERATED	2025-11-04 12:45:10.407456+01
02470f54-7fcc-47ba-962c-456e88bd9f97	bf3b3448-1ec3-4f29-87e3-7fc90bc83308	2025-10-07	\N	\N	\N	79.810000	\N	GENERATED	2025-11-04 12:45:10.408108+01
24a571a7-37d3-4958-bb90-5ff1f080b8a5	bf3b3448-1ec3-4f29-87e3-7fc90bc83308	2025-10-08	\N	\N	\N	81.280000	\N	GENERATED	2025-11-04 12:45:10.409056+01
4cf2c035-ad77-4fca-b6cf-24aab3b0082b	bf3b3448-1ec3-4f29-87e3-7fc90bc83308	2025-10-09	\N	\N	\N	80.510000	\N	GENERATED	2025-11-04 12:45:10.410137+01
6ac3d6fb-10a9-477e-b373-d33aeb2da710	bf3b3448-1ec3-4f29-87e3-7fc90bc83308	2025-10-10	\N	\N	\N	80.420000	\N	GENERATED	2025-11-04 12:45:10.410818+01
910a4d52-0edb-4b4c-a2fd-a7fde71719e5	bf3b3448-1ec3-4f29-87e3-7fc90bc83308	2025-10-11	\N	\N	\N	80.540000	\N	GENERATED	2025-11-04 12:45:10.411531+01
27243c18-e938-433e-b4a1-ca72930df5c3	bf3b3448-1ec3-4f29-87e3-7fc90bc83308	2025-10-12	\N	\N	\N	80.500000	\N	GENERATED	2025-11-04 12:45:10.412256+01
1af7c1d5-726e-437d-a40b-895013570474	bf3b3448-1ec3-4f29-87e3-7fc90bc83308	2025-10-13	\N	\N	\N	79.970000	\N	GENERATED	2025-11-04 12:45:10.412986+01
a13a984a-9362-4c36-aec9-7b098dc3cea8	bf3b3448-1ec3-4f29-87e3-7fc90bc83308	2025-10-14	\N	\N	\N	80.660000	\N	GENERATED	2025-11-04 12:45:10.413663+01
198dd8f9-fb7a-41bf-a46c-6aac9676cd6f	bf3b3448-1ec3-4f29-87e3-7fc90bc83308	2025-10-15	\N	\N	\N	81.080000	\N	GENERATED	2025-11-04 12:45:10.414327+01
783c9f51-9cdb-43f5-95a9-9e36093ae254	bf3b3448-1ec3-4f29-87e3-7fc90bc83308	2025-10-16	\N	\N	\N	80.270000	\N	GENERATED	2025-11-04 12:45:10.415039+01
5ed7d526-e462-4867-8dcb-c38177440d4e	bf3b3448-1ec3-4f29-87e3-7fc90bc83308	2025-10-17	\N	\N	\N	80.700000	\N	GENERATED	2025-11-04 12:45:10.415915+01
6f7e3719-b620-4c00-b864-fb1020462670	bf3b3448-1ec3-4f29-87e3-7fc90bc83308	2025-10-18	\N	\N	\N	80.280000	\N	GENERATED	2025-11-04 12:45:10.416697+01
6a2e8e53-1d2f-4da5-b5eb-bb9177884aa2	bf3b3448-1ec3-4f29-87e3-7fc90bc83308	2025-10-19	\N	\N	\N	81.170000	\N	GENERATED	2025-11-04 12:45:10.41745+01
1618c95b-0ca0-493b-8668-8451cdecc69c	bf3b3448-1ec3-4f29-87e3-7fc90bc83308	2025-10-20	\N	\N	\N	81.220000	\N	GENERATED	2025-11-04 12:45:10.418152+01
ed79a94d-029b-4ea8-b1db-16ab08dca324	bf3b3448-1ec3-4f29-87e3-7fc90bc83308	2025-10-21	\N	\N	\N	81.060000	\N	GENERATED	2025-11-04 12:45:10.41885+01
a305c95e-9c50-4af7-a52d-7d6bd6704ea1	bf3b3448-1ec3-4f29-87e3-7fc90bc83308	2025-10-22	\N	\N	\N	80.330000	\N	GENERATED	2025-11-04 12:45:10.419552+01
4143f894-c516-4152-889f-2e16f782ed7d	bf3b3448-1ec3-4f29-87e3-7fc90bc83308	2025-10-23	\N	\N	\N	81.370000	\N	GENERATED	2025-11-04 12:45:10.420207+01
2d24bba4-b66a-4d6f-a739-cd43fa06da6f	bf3b3448-1ec3-4f29-87e3-7fc90bc83308	2025-10-24	\N	\N	\N	80.930000	\N	GENERATED	2025-11-04 12:45:10.420887+01
e0fed160-75d9-444a-9f26-3dba4dd64233	bf3b3448-1ec3-4f29-87e3-7fc90bc83308	2025-10-25	\N	\N	\N	80.130000	\N	GENERATED	2025-11-04 12:45:10.421559+01
2bb18e5f-7c98-4b68-a492-79be230f013a	bf3b3448-1ec3-4f29-87e3-7fc90bc83308	2025-10-26	\N	\N	\N	81.540000	\N	GENERATED	2025-11-04 12:45:10.422233+01
bd979a45-d625-4e12-8624-ea98fa0b6861	bf3b3448-1ec3-4f29-87e3-7fc90bc83308	2025-10-27	\N	\N	\N	80.560000	\N	GENERATED	2025-11-04 12:45:10.423085+01
3bef450a-3e42-46f4-a248-1c44bdbd4fad	bf3b3448-1ec3-4f29-87e3-7fc90bc83308	2025-10-28	\N	\N	\N	81.160000	\N	GENERATED	2025-11-04 12:45:10.423815+01
9d50266d-2975-4a0f-b3e9-5238587bb884	bf3b3448-1ec3-4f29-87e3-7fc90bc83308	2025-10-29	\N	\N	\N	80.880000	\N	GENERATED	2025-11-04 12:45:10.42447+01
7862b4ce-0ba6-4f13-8b23-d1d3cdf2b75e	bf3b3448-1ec3-4f29-87e3-7fc90bc83308	2025-10-30	\N	\N	\N	80.210000	\N	GENERATED	2025-11-04 12:45:10.425186+01
8cd51207-c7e1-46aa-a0de-3d2233daa91a	bf3b3448-1ec3-4f29-87e3-7fc90bc83308	2025-10-31	\N	\N	\N	80.310000	\N	GENERATED	2025-11-04 12:45:10.425906+01
ac075e49-3fc7-4a1b-9ab7-187c422d9214	bf3b3448-1ec3-4f29-87e3-7fc90bc83308	2025-11-01	\N	\N	\N	80.750000	\N	GENERATED	2025-11-04 12:45:10.426775+01
45fcb603-ef2a-4327-91ce-b5f1eb0223b7	bf3b3448-1ec3-4f29-87e3-7fc90bc83308	2025-11-02	\N	\N	\N	80.530000	\N	GENERATED	2025-11-04 12:45:10.427953+01
b86a293a-b8c9-4501-8514-1375c0ae7e94	bf3b3448-1ec3-4f29-87e3-7fc90bc83308	2025-11-03	\N	\N	\N	80.820000	\N	GENERATED	2025-11-04 12:45:10.42878+01
9a6c2b65-778a-4647-8ef1-cca78a82cba3	c117885f-43f8-4be0-8df2-f6d30a200cca	2024-11-04	\N	\N	\N	94.270000	\N	GENERATED	2025-11-04 12:45:10.430123+01
7ed82e01-76ed-4f44-b184-33b0a8cf8505	c117885f-43f8-4be0-8df2-f6d30a200cca	2024-11-05	\N	\N	\N	95.700000	\N	GENERATED	2025-11-04 12:45:10.430798+01
cf33ee1f-04ba-4c99-b82d-d498d052c443	c117885f-43f8-4be0-8df2-f6d30a200cca	2024-11-06	\N	\N	\N	95.310000	\N	GENERATED	2025-11-04 12:45:10.431464+01
40bf933f-9071-4f67-86ff-2b7a15c4d353	c117885f-43f8-4be0-8df2-f6d30a200cca	2024-11-07	\N	\N	\N	95.890000	\N	GENERATED	2025-11-04 12:45:10.432128+01
bfb91dfd-612b-48fd-b93e-9e18d6b9eb33	c117885f-43f8-4be0-8df2-f6d30a200cca	2024-11-08	\N	\N	\N	94.820000	\N	GENERATED	2025-11-04 12:45:10.432907+01
9e457005-9c2d-41c4-a626-fcff2db7084f	c117885f-43f8-4be0-8df2-f6d30a200cca	2024-11-09	\N	\N	\N	95.240000	\N	GENERATED	2025-11-04 12:45:10.433576+01
2fd56bfa-094d-42af-bb82-b3f37cdae951	c117885f-43f8-4be0-8df2-f6d30a200cca	2024-11-10	\N	\N	\N	94.730000	\N	GENERATED	2025-11-04 12:45:10.434233+01
a049bcc8-f0b5-4a6a-8d6e-7d13b6a2b017	c117885f-43f8-4be0-8df2-f6d30a200cca	2024-11-11	\N	\N	\N	95.820000	\N	GENERATED	2025-11-04 12:45:10.434927+01
793b409c-6a60-4a10-8c47-dcda1eed2427	c117885f-43f8-4be0-8df2-f6d30a200cca	2024-11-12	\N	\N	\N	95.400000	\N	GENERATED	2025-11-04 12:45:10.435583+01
23595ab1-8a8e-4fcc-bbd6-9b35f792b4fb	c117885f-43f8-4be0-8df2-f6d30a200cca	2024-11-13	\N	\N	\N	95.880000	\N	GENERATED	2025-11-04 12:45:10.436233+01
60770c93-e3db-4ed5-9c52-0e324e3b0f04	c117885f-43f8-4be0-8df2-f6d30a200cca	2024-11-14	\N	\N	\N	94.510000	\N	GENERATED	2025-11-04 12:45:10.43693+01
a6947dab-5929-4f2a-8928-c00bc844df24	c117885f-43f8-4be0-8df2-f6d30a200cca	2024-11-15	\N	\N	\N	95.260000	\N	GENERATED	2025-11-04 12:45:10.437646+01
f45decf5-52a8-4bba-ab0d-76dde9a99f79	c117885f-43f8-4be0-8df2-f6d30a200cca	2024-11-16	\N	\N	\N	94.890000	\N	GENERATED	2025-11-04 12:45:10.438328+01
b1025536-6a6d-432c-a9f0-9535987a2ef6	c117885f-43f8-4be0-8df2-f6d30a200cca	2024-11-17	\N	\N	\N	96.080000	\N	GENERATED	2025-11-04 12:45:10.439026+01
2f5e68c8-62ed-44d5-810b-56c9093d29df	c117885f-43f8-4be0-8df2-f6d30a200cca	2024-11-18	\N	\N	\N	94.530000	\N	GENERATED	2025-11-04 12:45:10.43973+01
c410e40f-f752-47a7-887f-502943c5d920	c117885f-43f8-4be0-8df2-f6d30a200cca	2024-11-19	\N	\N	\N	96.170000	\N	GENERATED	2025-11-04 12:45:10.44042+01
70be8d04-0bdf-4733-b7bc-1c2377ff13f1	c117885f-43f8-4be0-8df2-f6d30a200cca	2024-11-20	\N	\N	\N	95.850000	\N	GENERATED	2025-11-04 12:45:10.441076+01
814c0a71-163a-494a-8869-86471874a9a3	c117885f-43f8-4be0-8df2-f6d30a200cca	2024-11-21	\N	\N	\N	95.780000	\N	GENERATED	2025-11-04 12:45:10.441762+01
c11f012f-521a-4ce8-a799-5eb538805d0e	c117885f-43f8-4be0-8df2-f6d30a200cca	2024-11-22	\N	\N	\N	94.530000	\N	GENERATED	2025-11-04 12:45:10.442533+01
48f78f8c-7e4a-434e-99aa-dc3be1e3432e	c117885f-43f8-4be0-8df2-f6d30a200cca	2024-11-23	\N	\N	\N	95.880000	\N	GENERATED	2025-11-04 12:45:10.443643+01
7830f630-ed01-427c-87ae-eef315c38ad7	c117885f-43f8-4be0-8df2-f6d30a200cca	2024-11-24	\N	\N	\N	96.340000	\N	GENERATED	2025-11-04 12:45:10.44443+01
18c05b64-e061-4f33-aeaf-e3e9ce7966ec	c117885f-43f8-4be0-8df2-f6d30a200cca	2024-11-25	\N	\N	\N	95.580000	\N	GENERATED	2025-11-04 12:45:10.445142+01
e945c96c-3af8-4972-9ced-496a85696cbe	c117885f-43f8-4be0-8df2-f6d30a200cca	2024-11-26	\N	\N	\N	94.820000	\N	GENERATED	2025-11-04 12:45:10.445823+01
63ed71d6-8ab5-46aa-b0d9-b9223e8add21	c117885f-43f8-4be0-8df2-f6d30a200cca	2024-11-27	\N	\N	\N	96.080000	\N	GENERATED	2025-11-04 12:45:10.446525+01
ad44e372-399d-4c14-bf91-11542045abb2	c117885f-43f8-4be0-8df2-f6d30a200cca	2024-11-28	\N	\N	\N	94.910000	\N	GENERATED	2025-11-04 12:45:10.44718+01
f909d894-0b13-408f-97f1-93fea4d6e5b3	c117885f-43f8-4be0-8df2-f6d30a200cca	2024-11-29	\N	\N	\N	95.420000	\N	GENERATED	2025-11-04 12:45:10.447852+01
07e916db-18e7-4970-8ccf-36ac2ba83538	c117885f-43f8-4be0-8df2-f6d30a200cca	2024-11-30	\N	\N	\N	94.790000	\N	GENERATED	2025-11-04 12:45:10.448508+01
c5e5b1e0-47fd-4c02-8add-1bece0a14f38	c117885f-43f8-4be0-8df2-f6d30a200cca	2024-12-01	\N	\N	\N	95.390000	\N	GENERATED	2025-11-04 12:45:10.44916+01
c7a9d317-e17b-46c7-814e-282ef2f5c578	c117885f-43f8-4be0-8df2-f6d30a200cca	2024-12-02	\N	\N	\N	96.320000	\N	GENERATED	2025-11-04 12:45:10.44984+01
a7c8df31-b1bf-4a57-b88f-5e7dadb9d08f	c117885f-43f8-4be0-8df2-f6d30a200cca	2024-12-03	\N	\N	\N	96.500000	\N	GENERATED	2025-11-04 12:45:10.450494+01
8dffa475-38e6-4ab8-827e-9ea33b430ac4	c117885f-43f8-4be0-8df2-f6d30a200cca	2024-12-04	\N	\N	\N	96.040000	\N	GENERATED	2025-11-04 12:45:10.451149+01
a87ec2ed-0b22-4010-960c-f024ae326317	c117885f-43f8-4be0-8df2-f6d30a200cca	2024-12-05	\N	\N	\N	96.100000	\N	GENERATED	2025-11-04 12:45:10.451802+01
28d7b96c-1bc8-4cb2-b60d-2d89dd0ecbbd	c117885f-43f8-4be0-8df2-f6d30a200cca	2024-12-06	\N	\N	\N	95.710000	\N	GENERATED	2025-11-04 12:45:10.452772+01
77264831-dff3-4840-92b6-81f59789e54f	c117885f-43f8-4be0-8df2-f6d30a200cca	2024-12-07	\N	\N	\N	96.240000	\N	GENERATED	2025-11-04 12:45:10.453675+01
9d49f46d-5dfd-429e-a59b-2819abe82d8f	c117885f-43f8-4be0-8df2-f6d30a200cca	2024-12-08	\N	\N	\N	94.850000	\N	GENERATED	2025-11-04 12:45:10.454373+01
21b0fbc0-d3c6-44f4-822b-9e9e97d1abea	c117885f-43f8-4be0-8df2-f6d30a200cca	2024-12-09	\N	\N	\N	95.700000	\N	GENERATED	2025-11-04 12:45:10.455049+01
c20c20bb-cd29-4b8a-b083-49447c144570	c117885f-43f8-4be0-8df2-f6d30a200cca	2024-12-10	\N	\N	\N	95.790000	\N	GENERATED	2025-11-04 12:45:10.455702+01
a8d862b0-13d6-4406-9b77-18d1ec0d7ce8	c117885f-43f8-4be0-8df2-f6d30a200cca	2024-12-11	\N	\N	\N	96.110000	\N	GENERATED	2025-11-04 12:45:10.45636+01
9056f52b-418e-4770-89c3-989953bc4745	c117885f-43f8-4be0-8df2-f6d30a200cca	2024-12-12	\N	\N	\N	95.690000	\N	GENERATED	2025-11-04 12:45:10.457035+01
58f6ed88-1416-4a12-9a57-224285a226d0	c117885f-43f8-4be0-8df2-f6d30a200cca	2024-12-13	\N	\N	\N	95.170000	\N	GENERATED	2025-11-04 12:45:10.457698+01
a9299a4c-5999-453c-b9bc-6562a684ce4d	c117885f-43f8-4be0-8df2-f6d30a200cca	2024-12-14	\N	\N	\N	95.300000	\N	GENERATED	2025-11-04 12:45:10.458443+01
409aad0b-ae8d-4bec-b8ab-ba151d1cbcdb	c117885f-43f8-4be0-8df2-f6d30a200cca	2024-12-15	\N	\N	\N	95.190000	\N	GENERATED	2025-11-04 12:45:10.45918+01
6244b88d-eb9d-4684-8734-6ef44120295f	c117885f-43f8-4be0-8df2-f6d30a200cca	2024-12-16	\N	\N	\N	95.650000	\N	GENERATED	2025-11-04 12:45:10.459902+01
ee0c7cc3-f47c-4d86-859d-5ff570a65a7c	c117885f-43f8-4be0-8df2-f6d30a200cca	2024-12-17	\N	\N	\N	95.170000	\N	GENERATED	2025-11-04 12:45:10.460568+01
f781b21b-a7a2-41b6-a871-52515ffb9382	c117885f-43f8-4be0-8df2-f6d30a200cca	2024-12-18	\N	\N	\N	95.830000	\N	GENERATED	2025-11-04 12:45:10.461235+01
658d2055-ce3e-4271-9911-e8aab1e9fe74	c117885f-43f8-4be0-8df2-f6d30a200cca	2024-12-19	\N	\N	\N	96.850000	\N	GENERATED	2025-11-04 12:45:10.461888+01
627aafd0-7620-43a0-9318-e6f5d4fd550a	c117885f-43f8-4be0-8df2-f6d30a200cca	2024-12-20	\N	\N	\N	96.750000	\N	GENERATED	2025-11-04 12:45:10.46254+01
1cf63279-e8b1-41b0-931d-e13a3481526e	c117885f-43f8-4be0-8df2-f6d30a200cca	2024-12-21	\N	\N	\N	96.460000	\N	GENERATED	2025-11-04 12:45:10.463196+01
1fb702d9-e997-495b-bbb1-dc903a69648e	c117885f-43f8-4be0-8df2-f6d30a200cca	2024-12-22	\N	\N	\N	96.710000	\N	GENERATED	2025-11-04 12:45:10.463841+01
90864347-7e42-4002-a30e-1f2c3b355d2d	c117885f-43f8-4be0-8df2-f6d30a200cca	2024-12-23	\N	\N	\N	95.140000	\N	GENERATED	2025-11-04 12:45:10.4645+01
0273639f-3d3f-49da-aa38-b968b55cd0e6	c117885f-43f8-4be0-8df2-f6d30a200cca	2024-12-24	\N	\N	\N	95.220000	\N	GENERATED	2025-11-04 12:45:10.465152+01
bfd1f382-d503-4117-a607-9ad7110f593d	c117885f-43f8-4be0-8df2-f6d30a200cca	2024-12-25	\N	\N	\N	96.490000	\N	GENERATED	2025-11-04 12:45:10.465799+01
7407e773-2c5d-45c0-8d5f-15b6a410cbe2	c117885f-43f8-4be0-8df2-f6d30a200cca	2024-12-26	\N	\N	\N	95.620000	\N	GENERATED	2025-11-04 12:45:10.466459+01
10c4f488-f0ab-47ce-9514-0e029f418ce1	c117885f-43f8-4be0-8df2-f6d30a200cca	2024-12-27	\N	\N	\N	96.320000	\N	GENERATED	2025-11-04 12:45:10.467117+01
f7ddf391-e5a4-4901-9458-52f189a844c3	c117885f-43f8-4be0-8df2-f6d30a200cca	2024-12-28	\N	\N	\N	95.280000	\N	GENERATED	2025-11-04 12:45:10.467766+01
0d30d240-6812-4938-a5c3-8239e27b6630	c117885f-43f8-4be0-8df2-f6d30a200cca	2024-12-29	\N	\N	\N	96.460000	\N	GENERATED	2025-11-04 12:45:10.468418+01
a40b789e-0ab2-425e-86db-a057eb9808d2	c117885f-43f8-4be0-8df2-f6d30a200cca	2024-12-30	\N	\N	\N	96.890000	\N	GENERATED	2025-11-04 12:45:10.469058+01
db2fe0ad-5200-4bd1-b0ff-dc0be7ab6029	c117885f-43f8-4be0-8df2-f6d30a200cca	2024-12-31	\N	\N	\N	95.580000	\N	GENERATED	2025-11-04 12:45:10.469708+01
5725ba2b-329a-4738-b94f-baa4363d3500	c117885f-43f8-4be0-8df2-f6d30a200cca	2025-01-01	\N	\N	\N	96.790000	\N	GENERATED	2025-11-04 12:45:10.470361+01
f6d96fa4-6f79-4bcd-9eeb-f2007975f3a3	c117885f-43f8-4be0-8df2-f6d30a200cca	2025-01-02	\N	\N	\N	96.400000	\N	GENERATED	2025-11-04 12:45:10.471012+01
496207cb-b607-4483-941b-73b026591c4e	c117885f-43f8-4be0-8df2-f6d30a200cca	2025-01-03	\N	\N	\N	95.460000	\N	GENERATED	2025-11-04 12:45:10.471663+01
bcf72af1-243f-4197-9b21-b4c495baa543	c117885f-43f8-4be0-8df2-f6d30a200cca	2025-01-04	\N	\N	\N	95.980000	\N	GENERATED	2025-11-04 12:45:10.472474+01
4df96448-b409-4d8d-9576-3c132faad092	c117885f-43f8-4be0-8df2-f6d30a200cca	2025-01-05	\N	\N	\N	97.160000	\N	GENERATED	2025-11-04 12:45:10.473156+01
cc17015c-27ca-423d-821d-da9deb74bc71	c117885f-43f8-4be0-8df2-f6d30a200cca	2025-01-06	\N	\N	\N	96.660000	\N	GENERATED	2025-11-04 12:45:10.473802+01
4c6edd04-5cbd-4c42-9e93-737f3e0df922	c117885f-43f8-4be0-8df2-f6d30a200cca	2025-01-07	\N	\N	\N	96.560000	\N	GENERATED	2025-11-04 12:45:10.474458+01
7ba8c4c6-f7a9-4b85-86ea-df92bb325cf9	c117885f-43f8-4be0-8df2-f6d30a200cca	2025-01-08	\N	\N	\N	95.920000	\N	GENERATED	2025-11-04 12:45:10.475192+01
462caee9-1333-4a5e-9d09-68361f2bb176	c117885f-43f8-4be0-8df2-f6d30a200cca	2025-01-09	\N	\N	\N	96.860000	\N	GENERATED	2025-11-04 12:45:10.476195+01
5691057d-92d4-4353-8852-31b7924d8816	c117885f-43f8-4be0-8df2-f6d30a200cca	2025-01-10	\N	\N	\N	95.750000	\N	GENERATED	2025-11-04 12:45:10.476862+01
071f364e-e009-4cce-91a1-069f353a1654	c117885f-43f8-4be0-8df2-f6d30a200cca	2025-01-11	\N	\N	\N	96.410000	\N	GENERATED	2025-11-04 12:45:10.477529+01
09bae8ef-1d22-4784-9b77-773fbbc8a258	c117885f-43f8-4be0-8df2-f6d30a200cca	2025-01-12	\N	\N	\N	95.870000	\N	GENERATED	2025-11-04 12:45:10.478186+01
56198200-5cd0-4618-b4e9-3f7dbf730271	c117885f-43f8-4be0-8df2-f6d30a200cca	2025-01-13	\N	\N	\N	96.100000	\N	GENERATED	2025-11-04 12:45:10.478873+01
57b76f80-a37b-4ca1-80f6-ad3c840e6d6a	c117885f-43f8-4be0-8df2-f6d30a200cca	2025-01-14	\N	\N	\N	95.810000	\N	GENERATED	2025-11-04 12:45:10.479565+01
631ed531-e4eb-4ee9-ae3d-edee40186a6a	c117885f-43f8-4be0-8df2-f6d30a200cca	2025-01-15	\N	\N	\N	97.390000	\N	GENERATED	2025-11-04 12:45:10.480215+01
ff24141f-98bc-41e4-8bec-8489471b4288	c117885f-43f8-4be0-8df2-f6d30a200cca	2025-01-16	\N	\N	\N	96.880000	\N	GENERATED	2025-11-04 12:45:10.480872+01
dbde6457-fc85-45cd-a879-8d8b4351473b	c117885f-43f8-4be0-8df2-f6d30a200cca	2025-01-17	\N	\N	\N	96.060000	\N	GENERATED	2025-11-04 12:45:10.481572+01
84a8270d-9426-492b-a614-a664a5747181	c117885f-43f8-4be0-8df2-f6d30a200cca	2025-01-18	\N	\N	\N	97.170000	\N	GENERATED	2025-11-04 12:45:10.48223+01
1bc27c3f-0c4d-4046-a021-714dddb7a40b	c117885f-43f8-4be0-8df2-f6d30a200cca	2025-01-19	\N	\N	\N	96.140000	\N	GENERATED	2025-11-04 12:45:10.482882+01
78f58a0e-d932-47f0-8aa8-4b2de95d4358	c117885f-43f8-4be0-8df2-f6d30a200cca	2025-01-20	\N	\N	\N	96.000000	\N	GENERATED	2025-11-04 12:45:10.483556+01
b7318eac-6f00-4707-bb1d-2c8168bc62c7	c117885f-43f8-4be0-8df2-f6d30a200cca	2025-01-21	\N	\N	\N	96.750000	\N	GENERATED	2025-11-04 12:45:10.484233+01
94dfc7ef-ffad-4f32-9a0d-a7a8c7181109	c117885f-43f8-4be0-8df2-f6d30a200cca	2025-01-22	\N	\N	\N	96.390000	\N	GENERATED	2025-11-04 12:45:10.485391+01
bbae83ea-2494-4823-a4af-126e180f4bb9	c117885f-43f8-4be0-8df2-f6d30a200cca	2025-01-23	\N	\N	\N	97.410000	\N	GENERATED	2025-11-04 12:45:10.486035+01
e1cc29cd-b61c-4a4f-b631-3e90658eeeae	c117885f-43f8-4be0-8df2-f6d30a200cca	2025-01-24	\N	\N	\N	95.970000	\N	GENERATED	2025-11-04 12:45:10.486701+01
3d259ba6-9216-4575-b9d0-9d7bba4d783f	c117885f-43f8-4be0-8df2-f6d30a200cca	2025-01-25	\N	\N	\N	97.260000	\N	GENERATED	2025-11-04 12:45:10.487379+01
7cc9cc53-e7c7-45bd-8cf1-b4b7b623912c	c117885f-43f8-4be0-8df2-f6d30a200cca	2025-01-26	\N	\N	\N	96.040000	\N	GENERATED	2025-11-04 12:45:10.488028+01
1f1b7c98-5db6-455e-9025-01ad50fb8fd6	c117885f-43f8-4be0-8df2-f6d30a200cca	2025-01-27	\N	\N	\N	96.870000	\N	GENERATED	2025-11-04 12:45:10.488716+01
d3643b18-59e2-4d22-9604-8569c5f77089	c117885f-43f8-4be0-8df2-f6d30a200cca	2025-01-28	\N	\N	\N	96.900000	\N	GENERATED	2025-11-04 12:45:10.489428+01
9505a5a0-d0b7-4252-b075-6d1fbae27c26	c117885f-43f8-4be0-8df2-f6d30a200cca	2025-01-29	\N	\N	\N	96.910000	\N	GENERATED	2025-11-04 12:45:10.490085+01
2ade14c2-f465-48c8-b4d7-662af4480fc7	c117885f-43f8-4be0-8df2-f6d30a200cca	2025-01-30	\N	\N	\N	97.630000	\N	GENERATED	2025-11-04 12:45:10.490867+01
7b563149-067e-4428-b251-2375b2748416	c117885f-43f8-4be0-8df2-f6d30a200cca	2025-01-31	\N	\N	\N	97.500000	\N	GENERATED	2025-11-04 12:45:10.49185+01
d2b275ad-33cd-4243-999e-e2c72d944e6c	c117885f-43f8-4be0-8df2-f6d30a200cca	2025-02-01	\N	\N	\N	96.060000	\N	GENERATED	2025-11-04 12:45:10.492755+01
b0557d3e-12a1-4eac-b6b0-ce745c768816	c117885f-43f8-4be0-8df2-f6d30a200cca	2025-02-02	\N	\N	\N	96.860000	\N	GENERATED	2025-11-04 12:45:10.493463+01
9c11d84d-8f41-4bf4-807f-11a155ecf17d	c117885f-43f8-4be0-8df2-f6d30a200cca	2025-02-03	\N	\N	\N	96.040000	\N	GENERATED	2025-11-04 12:45:10.494123+01
15211f52-1f84-426c-879f-467f38dc4aac	c117885f-43f8-4be0-8df2-f6d30a200cca	2025-02-04	\N	\N	\N	96.980000	\N	GENERATED	2025-11-04 12:45:10.494806+01
1dd7205d-5f33-4068-b7b9-0a0d72b0fff1	c117885f-43f8-4be0-8df2-f6d30a200cca	2025-02-05	\N	\N	\N	97.070000	\N	GENERATED	2025-11-04 12:45:10.4955+01
1cc8672e-871c-4665-8ec5-8b9863887845	c117885f-43f8-4be0-8df2-f6d30a200cca	2025-02-06	\N	\N	\N	96.690000	\N	GENERATED	2025-11-04 12:45:10.496171+01
72cef8e0-43e5-4627-afa5-da416419269d	c117885f-43f8-4be0-8df2-f6d30a200cca	2025-02-07	\N	\N	\N	96.630000	\N	GENERATED	2025-11-04 12:45:10.49691+01
f25cb8f7-8398-4ab6-93c0-59acc20793ad	c117885f-43f8-4be0-8df2-f6d30a200cca	2025-02-08	\N	\N	\N	97.330000	\N	GENERATED	2025-11-04 12:45:10.497568+01
ba8e757d-d6b2-4423-846d-3872b9270a12	c117885f-43f8-4be0-8df2-f6d30a200cca	2025-02-09	\N	\N	\N	97.030000	\N	GENERATED	2025-11-04 12:45:10.498229+01
257762c9-48b1-4f3c-870e-67eb9b9bdf9d	c117885f-43f8-4be0-8df2-f6d30a200cca	2025-02-10	\N	\N	\N	96.750000	\N	GENERATED	2025-11-04 12:45:10.498888+01
b26a1795-2205-4415-9ab9-c35d9d9966d1	c117885f-43f8-4be0-8df2-f6d30a200cca	2025-02-11	\N	\N	\N	96.650000	\N	GENERATED	2025-11-04 12:45:10.499555+01
689004d8-c4cd-4623-b7aa-c33e894199c3	c117885f-43f8-4be0-8df2-f6d30a200cca	2025-02-12	\N	\N	\N	97.200000	\N	GENERATED	2025-11-04 12:45:10.500196+01
0abf36a7-b5d1-467c-b7fd-b02ebe346fb3	c117885f-43f8-4be0-8df2-f6d30a200cca	2025-02-13	\N	\N	\N	97.260000	\N	GENERATED	2025-11-04 12:45:10.500842+01
f04a00ef-3008-4851-a782-d199a76babc9	c117885f-43f8-4be0-8df2-f6d30a200cca	2025-02-14	\N	\N	\N	97.760000	\N	GENERATED	2025-11-04 12:45:10.501501+01
9246538d-f336-4f06-b59c-dc865bee1d01	c117885f-43f8-4be0-8df2-f6d30a200cca	2025-02-15	\N	\N	\N	97.300000	\N	GENERATED	2025-11-04 12:45:10.502149+01
6b903d90-7723-4621-be73-064851e78e2d	c117885f-43f8-4be0-8df2-f6d30a200cca	2025-02-16	\N	\N	\N	97.760000	\N	GENERATED	2025-11-04 12:45:10.502835+01
c8f385b5-afda-4285-abba-ad4692818224	c117885f-43f8-4be0-8df2-f6d30a200cca	2025-02-17	\N	\N	\N	97.300000	\N	GENERATED	2025-11-04 12:45:10.503481+01
8829bc6f-5341-4bd0-96ba-2fee6e6dfe33	c117885f-43f8-4be0-8df2-f6d30a200cca	2025-02-18	\N	\N	\N	96.800000	\N	GENERATED	2025-11-04 12:45:10.504133+01
639e7fa8-df34-42e6-a403-5c98de9071a3	c117885f-43f8-4be0-8df2-f6d30a200cca	2025-02-19	\N	\N	\N	96.310000	\N	GENERATED	2025-11-04 12:45:10.504873+01
325879c7-ab91-4877-93e0-fa16feca2e68	c117885f-43f8-4be0-8df2-f6d30a200cca	2025-02-20	\N	\N	\N	96.840000	\N	GENERATED	2025-11-04 12:45:10.505753+01
4d69313e-5732-4263-93f2-5a134c35c2a6	c117885f-43f8-4be0-8df2-f6d30a200cca	2025-02-21	\N	\N	\N	96.480000	\N	GENERATED	2025-11-04 12:45:10.506832+01
d9e3fdca-dd9a-49c6-ab89-bf6e38991b26	c117885f-43f8-4be0-8df2-f6d30a200cca	2025-02-22	\N	\N	\N	96.990000	\N	GENERATED	2025-11-04 12:45:10.507595+01
d4baa235-b99e-484f-8bd1-efdb204346d5	c117885f-43f8-4be0-8df2-f6d30a200cca	2025-02-23	\N	\N	\N	98.050000	\N	GENERATED	2025-11-04 12:45:10.50824+01
9c0385f5-3d3d-4fe7-9b31-2bb37c4223a6	c117885f-43f8-4be0-8df2-f6d30a200cca	2025-02-24	\N	\N	\N	96.780000	\N	GENERATED	2025-11-04 12:45:10.508896+01
b1c7ae33-4023-4f49-82e3-c5a6f72ddc33	c117885f-43f8-4be0-8df2-f6d30a200cca	2025-02-25	\N	\N	\N	97.250000	\N	GENERATED	2025-11-04 12:45:10.509541+01
d28b3d11-7404-4f58-986c-4d42e0e09cc6	c117885f-43f8-4be0-8df2-f6d30a200cca	2025-02-26	\N	\N	\N	97.970000	\N	GENERATED	2025-11-04 12:45:10.510182+01
8371e3bb-7213-4570-a0b1-2782103f4be0	c117885f-43f8-4be0-8df2-f6d30a200cca	2025-02-27	\N	\N	\N	96.630000	\N	GENERATED	2025-11-04 12:45:10.51083+01
9403a228-1d09-4022-8592-89435d678178	c117885f-43f8-4be0-8df2-f6d30a200cca	2025-02-28	\N	\N	\N	96.720000	\N	GENERATED	2025-11-04 12:45:10.511525+01
62ce0f4e-8d60-4de9-9329-b1b524559cd0	c117885f-43f8-4be0-8df2-f6d30a200cca	2025-03-01	\N	\N	\N	97.370000	\N	GENERATED	2025-11-04 12:45:10.512181+01
b3cad285-2fe0-4cd5-b685-7ed7023a99b6	c117885f-43f8-4be0-8df2-f6d30a200cca	2025-03-02	\N	\N	\N	97.480000	\N	GENERATED	2025-11-04 12:45:10.5129+01
db109629-2b7c-4005-abb7-fa825447bae6	c117885f-43f8-4be0-8df2-f6d30a200cca	2025-03-03	\N	\N	\N	97.390000	\N	GENERATED	2025-11-04 12:45:10.513562+01
e2fdc6df-5eb5-4185-b906-301906eded15	c117885f-43f8-4be0-8df2-f6d30a200cca	2025-03-04	\N	\N	\N	98.020000	\N	GENERATED	2025-11-04 12:45:10.51422+01
0f07e391-2e27-48f5-9a9d-7937341b57b9	c117885f-43f8-4be0-8df2-f6d30a200cca	2025-03-05	\N	\N	\N	97.980000	\N	GENERATED	2025-11-04 12:45:10.514867+01
a188aebd-5519-4b16-90f6-10b9fccbbaef	c117885f-43f8-4be0-8df2-f6d30a200cca	2025-03-06	\N	\N	\N	98.140000	\N	GENERATED	2025-11-04 12:45:10.515517+01
4ace19af-c545-47ed-bdc3-4c3dd0ed3afa	c117885f-43f8-4be0-8df2-f6d30a200cca	2025-03-07	\N	\N	\N	96.760000	\N	GENERATED	2025-11-04 12:45:10.516175+01
404d473a-9f7b-4c99-b314-837c7b48a2c0	c117885f-43f8-4be0-8df2-f6d30a200cca	2025-03-08	\N	\N	\N	98.350000	\N	GENERATED	2025-11-04 12:45:10.516822+01
93c94b1e-1183-4684-a2e5-e6c2b26f80ba	c117885f-43f8-4be0-8df2-f6d30a200cca	2025-03-09	\N	\N	\N	98.080000	\N	GENERATED	2025-11-04 12:45:10.517504+01
e365b179-42ac-418b-add8-7a5adec5400a	c117885f-43f8-4be0-8df2-f6d30a200cca	2025-03-10	\N	\N	\N	98.230000	\N	GENERATED	2025-11-04 12:45:10.518149+01
c8acadac-3724-423b-b56b-249ec55df908	c117885f-43f8-4be0-8df2-f6d30a200cca	2025-03-11	\N	\N	\N	97.740000	\N	GENERATED	2025-11-04 12:45:10.518802+01
4c63b029-a0e2-46f4-b6ee-d8c4877d8222	c117885f-43f8-4be0-8df2-f6d30a200cca	2025-03-12	\N	\N	\N	97.360000	\N	GENERATED	2025-11-04 12:45:10.519469+01
4fb76d4c-1dd6-40ea-9550-2d12dde7eb39	c117885f-43f8-4be0-8df2-f6d30a200cca	2025-03-13	\N	\N	\N	96.790000	\N	GENERATED	2025-11-04 12:45:10.52012+01
9b4cc3ee-7425-4929-a59d-1e9e50da5613	c117885f-43f8-4be0-8df2-f6d30a200cca	2025-03-14	\N	\N	\N	98.270000	\N	GENERATED	2025-11-04 12:45:10.520762+01
f1e7b72e-b1cb-4ee3-b736-7b305000af3f	c117885f-43f8-4be0-8df2-f6d30a200cca	2025-03-15	\N	\N	\N	98.020000	\N	GENERATED	2025-11-04 12:45:10.521668+01
d3eab32f-ae82-4596-b62b-a09f750fe664	c117885f-43f8-4be0-8df2-f6d30a200cca	2025-03-16	\N	\N	\N	97.990000	\N	GENERATED	2025-11-04 12:45:10.522745+01
8cdf1457-c258-489d-bbe2-274c84a513ff	c117885f-43f8-4be0-8df2-f6d30a200cca	2025-03-17	\N	\N	\N	97.590000	\N	GENERATED	2025-11-04 12:45:10.523487+01
4809978f-4218-4c43-ae4c-3e6e6b2fe268	c117885f-43f8-4be0-8df2-f6d30a200cca	2025-03-18	\N	\N	\N	97.310000	\N	GENERATED	2025-11-04 12:45:10.524152+01
6b0a2222-1ae0-4ccf-bda4-6e78ea0d9859	c117885f-43f8-4be0-8df2-f6d30a200cca	2025-03-19	\N	\N	\N	97.730000	\N	GENERATED	2025-11-04 12:45:10.524806+01
14a5ddb5-726c-46e6-a50b-733d28d67325	c117885f-43f8-4be0-8df2-f6d30a200cca	2025-03-20	\N	\N	\N	97.940000	\N	GENERATED	2025-11-04 12:45:10.52545+01
dd732717-d775-443a-b5e4-bb26d683293c	c117885f-43f8-4be0-8df2-f6d30a200cca	2025-03-21	\N	\N	\N	97.320000	\N	GENERATED	2025-11-04 12:45:10.526098+01
d2658560-8f25-441d-b0de-c8319e4dbabd	c117885f-43f8-4be0-8df2-f6d30a200cca	2025-03-22	\N	\N	\N	98.340000	\N	GENERATED	2025-11-04 12:45:10.526745+01
bc730ebb-7cda-476d-a680-44368ba17cb9	c117885f-43f8-4be0-8df2-f6d30a200cca	2025-03-23	\N	\N	\N	97.280000	\N	GENERATED	2025-11-04 12:45:10.52741+01
2c868efb-d67f-4044-81cc-3ecd44b12e94	c117885f-43f8-4be0-8df2-f6d30a200cca	2025-03-24	\N	\N	\N	97.960000	\N	GENERATED	2025-11-04 12:45:10.528091+01
4ca9f2d0-4792-4b99-ac20-4cdde1a42bf6	c117885f-43f8-4be0-8df2-f6d30a200cca	2025-03-25	\N	\N	\N	97.340000	\N	GENERATED	2025-11-04 12:45:10.528843+01
c95e346f-a055-4b5d-83cb-ef4e3f2c0468	c117885f-43f8-4be0-8df2-f6d30a200cca	2025-03-26	\N	\N	\N	98.630000	\N	GENERATED	2025-11-04 12:45:10.529484+01
7e693ad1-21be-4642-aabe-22c747710d1a	c117885f-43f8-4be0-8df2-f6d30a200cca	2025-03-27	\N	\N	\N	97.520000	\N	GENERATED	2025-11-04 12:45:10.530132+01
19e506b3-f097-498a-aecc-3e1e786f8b63	c117885f-43f8-4be0-8df2-f6d30a200cca	2025-03-28	\N	\N	\N	98.490000	\N	GENERATED	2025-11-04 12:45:10.5308+01
88a2843d-4bec-4252-b4cf-0fe8a9d8df4d	c117885f-43f8-4be0-8df2-f6d30a200cca	2025-03-29	\N	\N	\N	97.640000	\N	GENERATED	2025-11-04 12:45:10.531448+01
3efc9e73-ffe5-4cc6-9030-47dd31ec0481	c117885f-43f8-4be0-8df2-f6d30a200cca	2025-03-30	\N	\N	\N	97.460000	\N	GENERATED	2025-11-04 12:45:10.532127+01
073960be-24af-4cc5-b52b-71b25e1a74f4	c117885f-43f8-4be0-8df2-f6d30a200cca	2025-03-31	\N	\N	\N	98.560000	\N	GENERATED	2025-11-04 12:45:10.532851+01
ad1086c3-24cc-4df5-a8e8-c78e3cf8f1ad	c117885f-43f8-4be0-8df2-f6d30a200cca	2025-04-01	\N	\N	\N	98.520000	\N	GENERATED	2025-11-04 12:45:10.533501+01
87620a3b-d6bc-4294-aa39-c6fecc87b80d	c117885f-43f8-4be0-8df2-f6d30a200cca	2025-04-02	\N	\N	\N	97.640000	\N	GENERATED	2025-11-04 12:45:10.534161+01
4d53059e-67da-4262-9681-d8ecc83c27b3	c117885f-43f8-4be0-8df2-f6d30a200cca	2025-04-03	\N	\N	\N	98.080000	\N	GENERATED	2025-11-04 12:45:10.534918+01
bcafb1eb-bdeb-4192-88d0-171c49c13d45	c117885f-43f8-4be0-8df2-f6d30a200cca	2025-04-04	\N	\N	\N	99.000000	\N	GENERATED	2025-11-04 12:45:10.535581+01
5e55bc7e-a8c0-44e7-8ec9-4dc8fc0953ea	c117885f-43f8-4be0-8df2-f6d30a200cca	2025-04-05	\N	\N	\N	97.560000	\N	GENERATED	2025-11-04 12:45:10.536231+01
50a8527d-3e82-4a9b-b140-613d0820c1fd	c117885f-43f8-4be0-8df2-f6d30a200cca	2025-04-06	\N	\N	\N	98.570000	\N	GENERATED	2025-11-04 12:45:10.537077+01
738818bb-8408-4df2-a651-43cf48f77582	c117885f-43f8-4be0-8df2-f6d30a200cca	2025-04-07	\N	\N	\N	97.930000	\N	GENERATED	2025-11-04 12:45:10.538005+01
69a57d39-ea3a-4b29-bdc6-c9c00efe69a5	c117885f-43f8-4be0-8df2-f6d30a200cca	2025-04-08	\N	\N	\N	97.790000	\N	GENERATED	2025-11-04 12:45:10.538701+01
5409f365-88fd-4096-b69b-7f06140d0b47	c117885f-43f8-4be0-8df2-f6d30a200cca	2025-04-09	\N	\N	\N	98.560000	\N	GENERATED	2025-11-04 12:45:10.539412+01
baf1d0ce-2c43-44d8-84e4-080acc6098d2	c117885f-43f8-4be0-8df2-f6d30a200cca	2025-04-10	\N	\N	\N	98.500000	\N	GENERATED	2025-11-04 12:45:10.540085+01
da1b8aee-823f-4425-80cc-f2893d32a731	c117885f-43f8-4be0-8df2-f6d30a200cca	2025-04-11	\N	\N	\N	98.350000	\N	GENERATED	2025-11-04 12:45:10.540837+01
113cd1d9-ea0a-4634-b470-b536a7abac1e	c117885f-43f8-4be0-8df2-f6d30a200cca	2025-04-12	\N	\N	\N	98.460000	\N	GENERATED	2025-11-04 12:45:10.541528+01
226af1da-edca-4311-b71b-0564dfafe558	c117885f-43f8-4be0-8df2-f6d30a200cca	2025-04-13	\N	\N	\N	98.160000	\N	GENERATED	2025-11-04 12:45:10.542196+01
566c80fe-eaca-4702-a2cc-57f800244495	c117885f-43f8-4be0-8df2-f6d30a200cca	2025-04-14	\N	\N	\N	98.460000	\N	GENERATED	2025-11-04 12:45:10.542872+01
456a6467-00b4-4a6b-8856-558dfa657b88	c117885f-43f8-4be0-8df2-f6d30a200cca	2025-04-15	\N	\N	\N	99.290000	\N	GENERATED	2025-11-04 12:45:10.543542+01
49a882f2-71df-4af6-a9ed-b0819d23e8f3	c117885f-43f8-4be0-8df2-f6d30a200cca	2025-04-16	\N	\N	\N	98.370000	\N	GENERATED	2025-11-04 12:45:10.544182+01
b7953c6a-37c3-44f0-8f69-fa064ed9d266	c117885f-43f8-4be0-8df2-f6d30a200cca	2025-04-17	\N	\N	\N	97.660000	\N	GENERATED	2025-11-04 12:45:10.544838+01
ff2469ac-b5f3-4ab7-9e5e-f1b91f0a9dd4	c117885f-43f8-4be0-8df2-f6d30a200cca	2025-04-18	\N	\N	\N	99.070000	\N	GENERATED	2025-11-04 12:45:10.545481+01
dc064d7e-798f-4e42-b7e5-2ecc0bbf60cc	c117885f-43f8-4be0-8df2-f6d30a200cca	2025-04-19	\N	\N	\N	98.110000	\N	GENERATED	2025-11-04 12:45:10.546138+01
e766b5b3-e6cd-47ca-a1f8-c7913168e650	c117885f-43f8-4be0-8df2-f6d30a200cca	2025-04-20	\N	\N	\N	98.280000	\N	GENERATED	2025-11-04 12:45:10.546827+01
e7e2d9c7-e1e5-48ff-8213-0aa46f78f977	c117885f-43f8-4be0-8df2-f6d30a200cca	2025-04-21	\N	\N	\N	98.090000	\N	GENERATED	2025-11-04 12:45:10.547466+01
4f226a2f-5406-4322-9c8c-d3efdf7ccef1	c117885f-43f8-4be0-8df2-f6d30a200cca	2025-04-22	\N	\N	\N	99.240000	\N	GENERATED	2025-11-04 12:45:10.548115+01
e5b8365a-55fa-456b-8a25-c2ea87cc53c9	c117885f-43f8-4be0-8df2-f6d30a200cca	2025-04-23	\N	\N	\N	98.610000	\N	GENERATED	2025-11-04 12:45:10.548764+01
58508b9e-8f98-4fde-973d-034e34b0d657	c117885f-43f8-4be0-8df2-f6d30a200cca	2025-04-24	\N	\N	\N	99.040000	\N	GENERATED	2025-11-04 12:45:10.54943+01
ce5c1f08-5f9c-47c0-a237-41627b6f4e39	c117885f-43f8-4be0-8df2-f6d30a200cca	2025-04-25	\N	\N	\N	99.440000	\N	GENERATED	2025-11-04 12:45:10.550086+01
17e239a2-e3cb-45a2-a029-148dcc9bdf63	c117885f-43f8-4be0-8df2-f6d30a200cca	2025-04-26	\N	\N	\N	99.340000	\N	GENERATED	2025-11-04 12:45:10.550723+01
ded633ed-0973-4f1f-ac65-95b852254ae5	c117885f-43f8-4be0-8df2-f6d30a200cca	2025-04-27	\N	\N	\N	98.240000	\N	GENERATED	2025-11-04 12:45:10.551371+01
7c00eb09-ce5f-4998-a4b0-29e6915ab4c0	c117885f-43f8-4be0-8df2-f6d30a200cca	2025-04-28	\N	\N	\N	99.260000	\N	GENERATED	2025-11-04 12:45:10.552262+01
8131f140-e558-415c-8168-f463dd6c7e94	c117885f-43f8-4be0-8df2-f6d30a200cca	2025-04-29	\N	\N	\N	98.050000	\N	GENERATED	2025-11-04 12:45:10.553307+01
a3652074-2107-4b3e-8abd-6d88e9aff460	c117885f-43f8-4be0-8df2-f6d30a200cca	2025-04-30	\N	\N	\N	99.120000	\N	GENERATED	2025-11-04 12:45:10.554054+01
2f3f9c3a-02b9-4aec-a83d-facce0b6aaec	c117885f-43f8-4be0-8df2-f6d30a200cca	2025-05-01	\N	\N	\N	99.630000	\N	GENERATED	2025-11-04 12:45:10.554782+01
dc06664b-f287-4afa-a474-ae723cb40acf	c117885f-43f8-4be0-8df2-f6d30a200cca	2025-05-02	\N	\N	\N	98.250000	\N	GENERATED	2025-11-04 12:45:10.55547+01
3e55820a-4a3a-4d91-bcf9-9a440ac511cb	c117885f-43f8-4be0-8df2-f6d30a200cca	2025-05-03	\N	\N	\N	99.680000	\N	GENERATED	2025-11-04 12:45:10.556155+01
44299672-be41-4a6c-80f5-b253f57ebaa2	c117885f-43f8-4be0-8df2-f6d30a200cca	2025-05-04	\N	\N	\N	97.950000	\N	GENERATED	2025-11-04 12:45:10.556823+01
93c23d1e-7a6e-4a59-8fdd-a38fb979880d	c117885f-43f8-4be0-8df2-f6d30a200cca	2025-05-05	\N	\N	\N	98.850000	\N	GENERATED	2025-11-04 12:45:10.557469+01
52e04b56-1de1-439e-bd5f-e37c7cabfd74	c117885f-43f8-4be0-8df2-f6d30a200cca	2025-05-06	\N	\N	\N	98.320000	\N	GENERATED	2025-11-04 12:45:10.558123+01
5e611ec1-dbc3-4712-87f8-c8e822ae3d6c	c117885f-43f8-4be0-8df2-f6d30a200cca	2025-05-07	\N	\N	\N	98.070000	\N	GENERATED	2025-11-04 12:45:10.558781+01
e78dd476-8df5-46d4-a6e9-fbfb6264d31a	c117885f-43f8-4be0-8df2-f6d30a200cca	2025-05-08	\N	\N	\N	98.590000	\N	GENERATED	2025-11-04 12:45:10.559429+01
b8754e15-74d8-4ecb-beab-5a8f85ace423	c117885f-43f8-4be0-8df2-f6d30a200cca	2025-05-09	\N	\N	\N	98.560000	\N	GENERATED	2025-11-04 12:45:10.560083+01
195f11e7-f9ef-483d-a47f-9b4eeabcdba0	c117885f-43f8-4be0-8df2-f6d30a200cca	2025-05-10	\N	\N	\N	98.690000	\N	GENERATED	2025-11-04 12:45:10.560731+01
3241fa85-307d-4605-93d5-103a694cff30	c117885f-43f8-4be0-8df2-f6d30a200cca	2025-05-11	\N	\N	\N	99.160000	\N	GENERATED	2025-11-04 12:45:10.561374+01
bb3fbfc5-462e-4608-836a-cead02fcdcca	c117885f-43f8-4be0-8df2-f6d30a200cca	2025-05-12	\N	\N	\N	99.040000	\N	GENERATED	2025-11-04 12:45:10.562066+01
26b680a9-a1f0-4357-b3a5-15d7636aecb2	c117885f-43f8-4be0-8df2-f6d30a200cca	2025-05-13	\N	\N	\N	98.040000	\N	GENERATED	2025-11-04 12:45:10.56274+01
a6ec2383-e818-41e2-8dd9-d029b9a1de00	c117885f-43f8-4be0-8df2-f6d30a200cca	2025-05-14	\N	\N	\N	99.140000	\N	GENERATED	2025-11-04 12:45:10.563393+01
70b6b346-ed54-4db6-bacd-77876b05a09b	c117885f-43f8-4be0-8df2-f6d30a200cca	2025-05-15	\N	\N	\N	98.680000	\N	GENERATED	2025-11-04 12:45:10.564062+01
5d883617-ae61-4e90-8f00-304a90c8a175	c117885f-43f8-4be0-8df2-f6d30a200cca	2025-05-16	\N	\N	\N	99.240000	\N	GENERATED	2025-11-04 12:45:10.564899+01
d28686c4-7535-46ca-9237-05c5cee58749	c117885f-43f8-4be0-8df2-f6d30a200cca	2025-05-17	\N	\N	\N	99.950000	\N	GENERATED	2025-11-04 12:45:10.565706+01
2bf7b59e-834e-4ab0-a3e1-63677d504d85	c117885f-43f8-4be0-8df2-f6d30a200cca	2025-05-18	\N	\N	\N	98.360000	\N	GENERATED	2025-11-04 12:45:10.566392+01
2939df06-9a62-4e15-8f53-1222c8fedd96	c117885f-43f8-4be0-8df2-f6d30a200cca	2025-05-19	\N	\N	\N	99.780000	\N	GENERATED	2025-11-04 12:45:10.567066+01
9090c377-987c-4a5b-8b7e-46942755526b	c117885f-43f8-4be0-8df2-f6d30a200cca	2025-05-20	\N	\N	\N	99.570000	\N	GENERATED	2025-11-04 12:45:10.567781+01
c69b34ae-eb4b-4af7-9046-a3e6c7c5f2eb	c117885f-43f8-4be0-8df2-f6d30a200cca	2025-05-21	\N	\N	\N	99.530000	\N	GENERATED	2025-11-04 12:45:10.568501+01
4e165d5a-3211-4895-a77e-15336b265dc4	c117885f-43f8-4be0-8df2-f6d30a200cca	2025-05-22	\N	\N	\N	99.560000	\N	GENERATED	2025-11-04 12:45:10.569166+01
36612fac-d784-406a-ba43-1ff6dd1a6ea1	c117885f-43f8-4be0-8df2-f6d30a200cca	2025-05-23	\N	\N	\N	99.730000	\N	GENERATED	2025-11-04 12:45:10.56983+01
ef01f6b1-dc89-42a6-a1f5-fae5ad5df7b6	c117885f-43f8-4be0-8df2-f6d30a200cca	2025-05-24	\N	\N	\N	99.200000	\N	GENERATED	2025-11-04 12:45:10.570472+01
8f089b96-a9a7-4310-948c-8d1acaf40e25	c117885f-43f8-4be0-8df2-f6d30a200cca	2025-05-25	\N	\N	\N	99.500000	\N	GENERATED	2025-11-04 12:45:10.571121+01
95aac358-0c7a-485e-a630-cb49dcf9db46	c117885f-43f8-4be0-8df2-f6d30a200cca	2025-05-26	\N	\N	\N	98.900000	\N	GENERATED	2025-11-04 12:45:10.571864+01
15da8fe7-9a83-4a80-b1e2-2431feeb0d2e	c117885f-43f8-4be0-8df2-f6d30a200cca	2025-05-27	\N	\N	\N	99.910000	\N	GENERATED	2025-11-04 12:45:10.572633+01
e2dc8cb3-78dc-44f8-8823-37c6a8913413	c117885f-43f8-4be0-8df2-f6d30a200cca	2025-05-28	\N	\N	\N	98.890000	\N	GENERATED	2025-11-04 12:45:10.573295+01
65f00127-9ba8-4581-931f-fb11ec0f658d	c117885f-43f8-4be0-8df2-f6d30a200cca	2025-05-29	\N	\N	\N	98.610000	\N	GENERATED	2025-11-04 12:45:10.573957+01
94f8f16c-a332-42f2-b76d-dd5347d0f81a	c117885f-43f8-4be0-8df2-f6d30a200cca	2025-05-30	\N	\N	\N	99.630000	\N	GENERATED	2025-11-04 12:45:10.574601+01
8d1611e8-a6ae-423d-b46b-330c5be7d3ed	c117885f-43f8-4be0-8df2-f6d30a200cca	2025-05-31	\N	\N	\N	98.850000	\N	GENERATED	2025-11-04 12:45:10.575247+01
ce37e19d-2b9b-4f9e-8ed8-7efc81ee4ff8	c117885f-43f8-4be0-8df2-f6d30a200cca	2025-06-01	\N	\N	\N	99.100000	\N	GENERATED	2025-11-04 12:45:10.575907+01
bd56fe75-ef83-4685-b136-2f7347286344	c117885f-43f8-4be0-8df2-f6d30a200cca	2025-06-02	\N	\N	\N	99.930000	\N	GENERATED	2025-11-04 12:45:10.576556+01
a72a8aab-b3f9-487c-b08a-a924d101d082	c117885f-43f8-4be0-8df2-f6d30a200cca	2025-06-03	\N	\N	\N	99.160000	\N	GENERATED	2025-11-04 12:45:10.577223+01
74a6a5c9-f9f3-4423-a7da-041393ac76cb	c117885f-43f8-4be0-8df2-f6d30a200cca	2025-06-04	\N	\N	\N	99.560000	\N	GENERATED	2025-11-04 12:45:10.577874+01
ad9a445c-a7fd-4128-9a75-3ace483249e4	c117885f-43f8-4be0-8df2-f6d30a200cca	2025-06-05	\N	\N	\N	99.020000	\N	GENERATED	2025-11-04 12:45:10.578522+01
a18be341-5290-499f-859c-d25ac50e9c66	c117885f-43f8-4be0-8df2-f6d30a200cca	2025-06-06	\N	\N	\N	99.360000	\N	GENERATED	2025-11-04 12:45:10.579177+01
cfa93827-e897-4f78-8b4b-db99cfa0cf0d	c117885f-43f8-4be0-8df2-f6d30a200cca	2025-06-07	\N	\N	\N	100.090000	\N	GENERATED	2025-11-04 12:45:10.579839+01
a58ea8a1-d985-4000-a407-d817c31784eb	c117885f-43f8-4be0-8df2-f6d30a200cca	2025-06-08	\N	\N	\N	99.060000	\N	GENERATED	2025-11-04 12:45:10.580501+01
a7a336e0-c7d3-4815-b617-1e92b08fbb7d	c117885f-43f8-4be0-8df2-f6d30a200cca	2025-06-09	\N	\N	\N	99.640000	\N	GENERATED	2025-11-04 12:45:10.581152+01
13909fda-1d08-4cff-8d55-507d1ef12bfe	c117885f-43f8-4be0-8df2-f6d30a200cca	2025-06-10	\N	\N	\N	99.650000	\N	GENERATED	2025-11-04 12:45:10.581794+01
c480c0c2-320a-4519-8234-c5b966ce5697	c117885f-43f8-4be0-8df2-f6d30a200cca	2025-06-11	\N	\N	\N	99.130000	\N	GENERATED	2025-11-04 12:45:10.582445+01
a45c339f-4712-473e-8875-ff2779b348e7	c117885f-43f8-4be0-8df2-f6d30a200cca	2025-06-12	\N	\N	\N	99.610000	\N	GENERATED	2025-11-04 12:45:10.58333+01
4394c5e6-c245-4028-9424-a277ffb0106d	c117885f-43f8-4be0-8df2-f6d30a200cca	2025-06-13	\N	\N	\N	99.680000	\N	GENERATED	2025-11-04 12:45:10.584221+01
d05c15b8-6823-4679-9a07-17694400edd7	c117885f-43f8-4be0-8df2-f6d30a200cca	2025-06-14	\N	\N	\N	99.500000	\N	GENERATED	2025-11-04 12:45:10.584961+01
5e2cdc94-d0f2-45b0-9d59-643c87411e7e	c117885f-43f8-4be0-8df2-f6d30a200cca	2025-06-15	\N	\N	\N	100.530000	\N	GENERATED	2025-11-04 12:45:10.585628+01
d029aabf-ac2a-44fb-8aef-c8d6956f66ce	c117885f-43f8-4be0-8df2-f6d30a200cca	2025-06-16	\N	\N	\N	99.380000	\N	GENERATED	2025-11-04 12:45:10.58629+01
5f6109ad-5c38-4bfb-898a-fcb942029d9a	c117885f-43f8-4be0-8df2-f6d30a200cca	2025-06-17	\N	\N	\N	100.100000	\N	GENERATED	2025-11-04 12:45:10.586951+01
57d43fea-d95d-4f42-8da4-e220f4d8e3be	c117885f-43f8-4be0-8df2-f6d30a200cca	2025-06-18	\N	\N	\N	100.620000	\N	GENERATED	2025-11-04 12:45:10.587964+01
c525b0df-699d-4d44-8a75-71f5a0c6f0fd	c117885f-43f8-4be0-8df2-f6d30a200cca	2025-06-19	\N	\N	\N	100.210000	\N	GENERATED	2025-11-04 12:45:10.588692+01
aa2c8650-1cc3-4298-8487-29cfda002afa	c117885f-43f8-4be0-8df2-f6d30a200cca	2025-06-20	\N	\N	\N	99.080000	\N	GENERATED	2025-11-04 12:45:10.589406+01
f416798b-46f5-427f-9f1e-dc6d4adb0805	c117885f-43f8-4be0-8df2-f6d30a200cca	2025-06-21	\N	\N	\N	100.290000	\N	GENERATED	2025-11-04 12:45:10.590166+01
ba93ab04-b216-4777-a534-a2773daa26f9	c117885f-43f8-4be0-8df2-f6d30a200cca	2025-06-22	\N	\N	\N	99.470000	\N	GENERATED	2025-11-04 12:45:10.590837+01
dad94c41-9dec-4d9c-ab74-f2b11dba0077	c117885f-43f8-4be0-8df2-f6d30a200cca	2025-06-23	\N	\N	\N	100.550000	\N	GENERATED	2025-11-04 12:45:10.591503+01
2ed01b15-fb86-44e2-9b51-6f00a21da9da	c117885f-43f8-4be0-8df2-f6d30a200cca	2025-06-24	\N	\N	\N	98.960000	\N	GENERATED	2025-11-04 12:45:10.592227+01
0bf3bc3f-abe5-4905-bf01-7d6b91af8179	c117885f-43f8-4be0-8df2-f6d30a200cca	2025-06-25	\N	\N	\N	100.000000	\N	GENERATED	2025-11-04 12:45:10.593042+01
75c47953-23a3-4567-ac39-f23918228db3	c117885f-43f8-4be0-8df2-f6d30a200cca	2025-06-26	\N	\N	\N	100.250000	\N	GENERATED	2025-11-04 12:45:10.593794+01
3e9494e0-0b40-4161-821d-e277b705803f	c117885f-43f8-4be0-8df2-f6d30a200cca	2025-06-27	\N	\N	\N	99.150000	\N	GENERATED	2025-11-04 12:45:10.59459+01
aaef18de-26d6-4c76-bcc6-a379809e74d9	c117885f-43f8-4be0-8df2-f6d30a200cca	2025-06-28	\N	\N	\N	100.510000	\N	GENERATED	2025-11-04 12:45:10.595305+01
c29c153d-edde-4069-9c2e-6de47025180c	c117885f-43f8-4be0-8df2-f6d30a200cca	2025-06-29	\N	\N	\N	100.680000	\N	GENERATED	2025-11-04 12:45:10.596002+01
acf58183-5db0-43d7-b985-4997f05f6e68	c117885f-43f8-4be0-8df2-f6d30a200cca	2025-06-30	\N	\N	\N	100.030000	\N	GENERATED	2025-11-04 12:45:10.59667+01
114f6c6a-b1ff-423d-8d95-ec8c5d1cd731	c117885f-43f8-4be0-8df2-f6d30a200cca	2025-07-01	\N	\N	\N	100.270000	\N	GENERATED	2025-11-04 12:45:10.597315+01
e3ebc9fe-50ce-4ae3-8792-9dafe264705d	c117885f-43f8-4be0-8df2-f6d30a200cca	2025-07-02	\N	\N	\N	99.970000	\N	GENERATED	2025-11-04 12:45:10.597969+01
3a1edb28-3f2a-4e91-be15-940121f8a4c0	c117885f-43f8-4be0-8df2-f6d30a200cca	2025-07-03	\N	\N	\N	99.150000	\N	GENERATED	2025-11-04 12:45:10.598744+01
effe9908-765a-4bd8-a311-98c3004d2875	c117885f-43f8-4be0-8df2-f6d30a200cca	2025-07-04	\N	\N	\N	100.080000	\N	GENERATED	2025-11-04 12:45:10.599495+01
8f0b017e-4d16-423e-8a18-af83ccb6cd92	c117885f-43f8-4be0-8df2-f6d30a200cca	2025-07-05	\N	\N	\N	99.990000	\N	GENERATED	2025-11-04 12:45:10.600195+01
7bc1f755-7a26-4b85-8843-a10fe497cc9b	c117885f-43f8-4be0-8df2-f6d30a200cca	2025-07-06	\N	\N	\N	100.620000	\N	GENERATED	2025-11-04 12:45:10.600882+01
518296dc-6d08-4660-9064-a20af7b52653	c117885f-43f8-4be0-8df2-f6d30a200cca	2025-07-07	\N	\N	\N	99.550000	\N	GENERATED	2025-11-04 12:45:10.601564+01
0404ce5a-0282-4255-8b79-232eeaad87dc	c117885f-43f8-4be0-8df2-f6d30a200cca	2025-07-08	\N	\N	\N	99.280000	\N	GENERATED	2025-11-04 12:45:10.602246+01
995f37cf-8631-4bb6-a54d-767e887c5257	c117885f-43f8-4be0-8df2-f6d30a200cca	2025-07-09	\N	\N	\N	100.930000	\N	GENERATED	2025-11-04 12:45:10.60292+01
3c10af07-b0e3-40d1-8e0a-a24bef0a6a66	c117885f-43f8-4be0-8df2-f6d30a200cca	2025-07-10	\N	\N	\N	101.110000	\N	GENERATED	2025-11-04 12:45:10.603699+01
bd81b414-16e2-46e2-81f5-10728a38791c	c117885f-43f8-4be0-8df2-f6d30a200cca	2025-07-11	\N	\N	\N	99.770000	\N	GENERATED	2025-11-04 12:45:10.604349+01
ae001039-fafe-42a7-ac5f-9437c36c7e8f	c117885f-43f8-4be0-8df2-f6d30a200cca	2025-07-12	\N	\N	\N	99.590000	\N	GENERATED	2025-11-04 12:45:10.604994+01
8935ead9-0ffe-454b-97c3-fa867c1cb659	c117885f-43f8-4be0-8df2-f6d30a200cca	2025-07-13	\N	\N	\N	99.450000	\N	GENERATED	2025-11-04 12:45:10.605646+01
2d825f74-7b3d-419a-b8b1-6af749588efe	c117885f-43f8-4be0-8df2-f6d30a200cca	2025-07-14	\N	\N	\N	100.470000	\N	GENERATED	2025-11-04 12:45:10.606291+01
6c1c34b3-a55e-4aae-be10-8ce40ee7bc36	c117885f-43f8-4be0-8df2-f6d30a200cca	2025-07-15	\N	\N	\N	100.710000	\N	GENERATED	2025-11-04 12:45:10.606952+01
1f54e5ca-4de0-4104-99c3-4cc7179bdaca	c117885f-43f8-4be0-8df2-f6d30a200cca	2025-07-16	\N	\N	\N	100.730000	\N	GENERATED	2025-11-04 12:45:10.607611+01
29c861a9-6b8c-4720-84e6-ebb45f1d4b3e	c117885f-43f8-4be0-8df2-f6d30a200cca	2025-07-17	\N	\N	\N	99.900000	\N	GENERATED	2025-11-04 12:45:10.60826+01
e3f4e181-4db3-4672-9d03-b4b43586a2bd	c117885f-43f8-4be0-8df2-f6d30a200cca	2025-07-18	\N	\N	\N	100.370000	\N	GENERATED	2025-11-04 12:45:10.608905+01
ad61089c-897a-4648-86b9-6c28f384b2f6	c117885f-43f8-4be0-8df2-f6d30a200cca	2025-07-19	\N	\N	\N	100.940000	\N	GENERATED	2025-11-04 12:45:10.60966+01
095df744-a65d-46c0-88c6-2c3a8015ab81	c117885f-43f8-4be0-8df2-f6d30a200cca	2025-07-20	\N	\N	\N	99.490000	\N	GENERATED	2025-11-04 12:45:10.610311+01
5eb1e787-4a86-4a46-afd7-cbffaa00bcf4	c117885f-43f8-4be0-8df2-f6d30a200cca	2025-07-21	\N	\N	\N	100.820000	\N	GENERATED	2025-11-04 12:45:10.61096+01
4fd0c6bf-c6ac-4689-9bb5-ad509b5928ae	c117885f-43f8-4be0-8df2-f6d30a200cca	2025-07-22	\N	\N	\N	101.280000	\N	GENERATED	2025-11-04 12:45:10.611608+01
49eca9df-c58a-4414-9390-cf16060486c5	c117885f-43f8-4be0-8df2-f6d30a200cca	2025-07-23	\N	\N	\N	99.850000	\N	GENERATED	2025-11-04 12:45:10.612251+01
207093ae-e8bd-46c3-b1cc-6a7bb57ac4c0	c117885f-43f8-4be0-8df2-f6d30a200cca	2025-07-24	\N	\N	\N	99.870000	\N	GENERATED	2025-11-04 12:45:10.612973+01
11c62890-c200-4afd-a98c-c43953c11082	c117885f-43f8-4be0-8df2-f6d30a200cca	2025-07-25	\N	\N	\N	99.610000	\N	GENERATED	2025-11-04 12:45:10.613732+01
237f1ac7-f1ff-4c24-b8ef-b037950a42c7	c117885f-43f8-4be0-8df2-f6d30a200cca	2025-07-26	\N	\N	\N	100.280000	\N	GENERATED	2025-11-04 12:45:10.614514+01
87d521b6-6559-4e95-bcc2-538eb2397e46	c117885f-43f8-4be0-8df2-f6d30a200cca	2025-07-27	\N	\N	\N	100.460000	\N	GENERATED	2025-11-04 12:45:10.615182+01
da2e1bcd-3c5f-4628-89ae-766432fe8576	c117885f-43f8-4be0-8df2-f6d30a200cca	2025-07-28	\N	\N	\N	101.270000	\N	GENERATED	2025-11-04 12:45:10.616036+01
b1a4b5f9-d9ca-4e30-9fd1-60f23b58b08d	c117885f-43f8-4be0-8df2-f6d30a200cca	2025-07-29	\N	\N	\N	100.940000	\N	GENERATED	2025-11-04 12:45:10.616715+01
1181c840-5b34-427d-b2d9-ff246e7244eb	c117885f-43f8-4be0-8df2-f6d30a200cca	2025-07-30	\N	\N	\N	100.820000	\N	GENERATED	2025-11-04 12:45:10.617373+01
6d8ba56a-1dda-4072-bbd4-7bc5d69be807	c117885f-43f8-4be0-8df2-f6d30a200cca	2025-07-31	\N	\N	\N	101.080000	\N	GENERATED	2025-11-04 12:45:10.61802+01
be7abaaa-3cd8-434e-9342-c12cc2df6296	c117885f-43f8-4be0-8df2-f6d30a200cca	2025-08-01	\N	\N	\N	100.700000	\N	GENERATED	2025-11-04 12:45:10.618688+01
a1f78671-ed81-444d-9ed3-956b932752b9	c117885f-43f8-4be0-8df2-f6d30a200cca	2025-08-02	\N	\N	\N	100.220000	\N	GENERATED	2025-11-04 12:45:10.619386+01
d0fb6f80-1d7b-4827-8d58-a85870a0c13d	c117885f-43f8-4be0-8df2-f6d30a200cca	2025-08-03	\N	\N	\N	100.110000	\N	GENERATED	2025-11-04 12:45:10.620036+01
bd275183-3db2-4b49-83e0-ef47f4695f3f	c117885f-43f8-4be0-8df2-f6d30a200cca	2025-08-04	\N	\N	\N	100.670000	\N	GENERATED	2025-11-04 12:45:10.620702+01
4b357f27-b16c-4265-8de1-85fdb1418faf	c117885f-43f8-4be0-8df2-f6d30a200cca	2025-08-05	\N	\N	\N	100.790000	\N	GENERATED	2025-11-04 12:45:10.621363+01
735509f7-1327-45b3-8ea2-e33f315016f3	c117885f-43f8-4be0-8df2-f6d30a200cca	2025-08-06	\N	\N	\N	100.160000	\N	GENERATED	2025-11-04 12:45:10.622119+01
e9afda0e-58ea-4559-8e59-e11dc51ae92c	c117885f-43f8-4be0-8df2-f6d30a200cca	2025-08-07	\N	\N	\N	101.160000	\N	GENERATED	2025-11-04 12:45:10.6228+01
63591519-1b5d-444c-be25-829d21e11714	c117885f-43f8-4be0-8df2-f6d30a200cca	2025-08-08	\N	\N	\N	100.190000	\N	GENERATED	2025-11-04 12:45:10.623477+01
110f21d7-5cb8-41c3-a7da-19caeb08cdc7	c117885f-43f8-4be0-8df2-f6d30a200cca	2025-08-09	\N	\N	\N	100.580000	\N	GENERATED	2025-11-04 12:45:10.62412+01
2780e410-289a-4b79-99c4-8c377673d132	c117885f-43f8-4be0-8df2-f6d30a200cca	2025-08-10	\N	\N	\N	100.890000	\N	GENERATED	2025-11-04 12:45:10.62477+01
e1872770-e3b5-4117-b852-06b09b21be03	c117885f-43f8-4be0-8df2-f6d30a200cca	2025-08-11	\N	\N	\N	101.270000	\N	GENERATED	2025-11-04 12:45:10.625406+01
24bd3317-e602-4f98-929f-88621390655a	c117885f-43f8-4be0-8df2-f6d30a200cca	2025-08-12	\N	\N	\N	100.070000	\N	GENERATED	2025-11-04 12:45:10.626047+01
9efd013c-2c77-4209-bffb-875a7d41c3a5	c117885f-43f8-4be0-8df2-f6d30a200cca	2025-08-13	\N	\N	\N	100.040000	\N	GENERATED	2025-11-04 12:45:10.626709+01
6236716a-763f-42b3-9c47-8f1727901b4a	c117885f-43f8-4be0-8df2-f6d30a200cca	2025-08-14	\N	\N	\N	100.760000	\N	GENERATED	2025-11-04 12:45:10.627718+01
c4b013fd-993a-4917-b136-205cd77c5e6b	c117885f-43f8-4be0-8df2-f6d30a200cca	2025-08-15	\N	\N	\N	101.850000	\N	GENERATED	2025-11-04 12:45:10.628365+01
4ecebb6c-460c-42ed-8e17-fe182c5f2fcc	c117885f-43f8-4be0-8df2-f6d30a200cca	2025-08-16	\N	\N	\N	100.130000	\N	GENERATED	2025-11-04 12:45:10.629214+01
8d1964c5-8d83-4b3f-bd22-df663103db90	c117885f-43f8-4be0-8df2-f6d30a200cca	2025-08-17	\N	\N	\N	100.040000	\N	GENERATED	2025-11-04 12:45:10.630145+01
9a844f43-3d67-4d4f-8811-2c46b062ea4a	c117885f-43f8-4be0-8df2-f6d30a200cca	2025-08-18	\N	\N	\N	101.370000	\N	GENERATED	2025-11-04 12:45:10.630828+01
76df9bdb-9d9c-463d-a2a6-cd2952aa70c1	c117885f-43f8-4be0-8df2-f6d30a200cca	2025-08-19	\N	\N	\N	101.280000	\N	GENERATED	2025-11-04 12:45:10.63148+01
68e95c92-2982-47e4-90c1-1f6e8058ebe7	c117885f-43f8-4be0-8df2-f6d30a200cca	2025-08-20	\N	\N	\N	100.110000	\N	GENERATED	2025-11-04 12:45:10.632156+01
74a476d9-c20d-476b-8736-0010efa41169	c117885f-43f8-4be0-8df2-f6d30a200cca	2025-08-21	\N	\N	\N	100.830000	\N	GENERATED	2025-11-04 12:45:10.632923+01
450d1d17-7917-448f-ba74-753d1671de8b	c117885f-43f8-4be0-8df2-f6d30a200cca	2025-08-22	\N	\N	\N	101.960000	\N	GENERATED	2025-11-04 12:45:10.633596+01
b803dd79-202d-4a37-ac91-6c34f9cba6f3	c117885f-43f8-4be0-8df2-f6d30a200cca	2025-08-23	\N	\N	\N	102.010000	\N	GENERATED	2025-11-04 12:45:10.634258+01
d92c3418-a1cd-41c4-811a-e91d038975ea	c117885f-43f8-4be0-8df2-f6d30a200cca	2025-08-24	\N	\N	\N	100.560000	\N	GENERATED	2025-11-04 12:45:10.634913+01
6850f4d1-9495-40a1-9e72-fedb6ba912a7	c117885f-43f8-4be0-8df2-f6d30a200cca	2025-08-25	\N	\N	\N	101.850000	\N	GENERATED	2025-11-04 12:45:10.635574+01
d3ca63d6-b65b-401d-9109-d483124b51d4	c117885f-43f8-4be0-8df2-f6d30a200cca	2025-08-26	\N	\N	\N	101.130000	\N	GENERATED	2025-11-04 12:45:10.636224+01
2462a986-f8e9-49c2-a8d1-66522372aa6c	c117885f-43f8-4be0-8df2-f6d30a200cca	2025-08-27	\N	\N	\N	100.610000	\N	GENERATED	2025-11-04 12:45:10.636927+01
70870e6f-4cf6-43d4-9c4d-6fc3f74c1524	c117885f-43f8-4be0-8df2-f6d30a200cca	2025-08-28	\N	\N	\N	101.230000	\N	GENERATED	2025-11-04 12:45:10.637749+01
43570621-cbb8-4735-abca-ceeee650af03	c117885f-43f8-4be0-8df2-f6d30a200cca	2025-08-29	\N	\N	\N	100.550000	\N	GENERATED	2025-11-04 12:45:10.638657+01
4cc74c47-ef53-4585-82f9-99063ee75454	c117885f-43f8-4be0-8df2-f6d30a200cca	2025-08-30	\N	\N	\N	100.610000	\N	GENERATED	2025-11-04 12:45:10.639358+01
9c94ce1b-3af1-4143-a0dd-0f90729ecd08	c117885f-43f8-4be0-8df2-f6d30a200cca	2025-08-31	\N	\N	\N	100.980000	\N	GENERATED	2025-11-04 12:45:10.640037+01
821f07d7-652b-4332-86ef-9fc4beedfebc	c117885f-43f8-4be0-8df2-f6d30a200cca	2025-09-01	\N	\N	\N	101.680000	\N	GENERATED	2025-11-04 12:45:10.640717+01
b321da15-2c93-49e1-8c11-4ee3c6cd13ff	c117885f-43f8-4be0-8df2-f6d30a200cca	2025-09-02	\N	\N	\N	100.750000	\N	GENERATED	2025-11-04 12:45:10.641387+01
44202ad7-33e0-49c1-83ae-15f61a63ae09	c117885f-43f8-4be0-8df2-f6d30a200cca	2025-09-03	\N	\N	\N	101.790000	\N	GENERATED	2025-11-04 12:45:10.642032+01
026dff9c-6e45-4baa-9160-1ac1424b6ee8	c117885f-43f8-4be0-8df2-f6d30a200cca	2025-09-04	\N	\N	\N	100.510000	\N	GENERATED	2025-11-04 12:45:10.642714+01
72e25a24-ec43-4a4e-83c5-b2b7f5de9384	c117885f-43f8-4be0-8df2-f6d30a200cca	2025-09-05	\N	\N	\N	101.030000	\N	GENERATED	2025-11-04 12:45:10.643374+01
a8e58416-b6bb-4cec-94aa-a5892835dbca	c117885f-43f8-4be0-8df2-f6d30a200cca	2025-09-06	\N	\N	\N	100.910000	\N	GENERATED	2025-11-04 12:45:10.644023+01
a3e82130-2232-4e13-ae64-b06376a9af8b	c117885f-43f8-4be0-8df2-f6d30a200cca	2025-09-07	\N	\N	\N	101.560000	\N	GENERATED	2025-11-04 12:45:10.644983+01
96c969ae-f8fa-403d-b628-07836496aafc	c117885f-43f8-4be0-8df2-f6d30a200cca	2025-09-08	\N	\N	\N	102.050000	\N	GENERATED	2025-11-04 12:45:10.646058+01
df62551b-20b4-4564-98b5-b8621df4788c	c117885f-43f8-4be0-8df2-f6d30a200cca	2025-09-09	\N	\N	\N	101.880000	\N	GENERATED	2025-11-04 12:45:10.646798+01
28c95597-59de-4294-9c67-1fcae6f86bc3	c117885f-43f8-4be0-8df2-f6d30a200cca	2025-09-10	\N	\N	\N	101.430000	\N	GENERATED	2025-11-04 12:45:10.647519+01
66f5a34c-e2b1-4de6-ab89-91dd309c4154	c117885f-43f8-4be0-8df2-f6d30a200cca	2025-09-11	\N	\N	\N	101.760000	\N	GENERATED	2025-11-04 12:45:10.648201+01
ff899fca-7ba4-4e9b-b2aa-3999390b18f6	c117885f-43f8-4be0-8df2-f6d30a200cca	2025-09-12	\N	\N	\N	101.740000	\N	GENERATED	2025-11-04 12:45:10.648952+01
a12b02ef-e588-47b9-806a-a3765aff840d	c117885f-43f8-4be0-8df2-f6d30a200cca	2025-09-13	\N	\N	\N	101.330000	\N	GENERATED	2025-11-04 12:45:10.649636+01
a115d1fe-63fe-4dcd-bea3-7bc18b814f2c	c117885f-43f8-4be0-8df2-f6d30a200cca	2025-09-14	\N	\N	\N	102.150000	\N	GENERATED	2025-11-04 12:45:10.650297+01
6f35d45b-ddc2-4ba5-8b5c-947ebd0d1bd0	c117885f-43f8-4be0-8df2-f6d30a200cca	2025-09-15	\N	\N	\N	101.750000	\N	GENERATED	2025-11-04 12:45:10.65097+01
5c2b2877-e08b-4003-9d95-7cedf968ef3c	c117885f-43f8-4be0-8df2-f6d30a200cca	2025-09-16	\N	\N	\N	101.890000	\N	GENERATED	2025-11-04 12:45:10.651635+01
c4b7e8d3-463b-419a-aa52-0364fac53ccd	c117885f-43f8-4be0-8df2-f6d30a200cca	2025-09-17	\N	\N	\N	101.760000	\N	GENERATED	2025-11-04 12:45:10.652644+01
cf4c23bf-508e-48c5-af07-8ea16a7c74bd	c117885f-43f8-4be0-8df2-f6d30a200cca	2025-09-18	\N	\N	\N	100.820000	\N	GENERATED	2025-11-04 12:45:10.653312+01
33d7a9b5-6b1d-45f1-8b44-8375f7b72cd1	c117885f-43f8-4be0-8df2-f6d30a200cca	2025-09-19	\N	\N	\N	101.340000	\N	GENERATED	2025-11-04 12:45:10.653968+01
1d3826cf-d063-49fc-9abf-95102f98a54c	c117885f-43f8-4be0-8df2-f6d30a200cca	2025-09-20	\N	\N	\N	102.210000	\N	GENERATED	2025-11-04 12:45:10.654707+01
df2f1904-442b-4e8c-8e7f-a31d9c8b2b92	c117885f-43f8-4be0-8df2-f6d30a200cca	2025-09-21	\N	\N	\N	101.480000	\N	GENERATED	2025-11-04 12:45:10.655369+01
a18a3860-9a71-4a35-8788-e04b579de866	c117885f-43f8-4be0-8df2-f6d30a200cca	2025-09-22	\N	\N	\N	101.670000	\N	GENERATED	2025-11-04 12:45:10.656024+01
aed0b3d3-414c-4d9b-bab9-d0c937f0a59d	c117885f-43f8-4be0-8df2-f6d30a200cca	2025-09-23	\N	\N	\N	101.220000	\N	GENERATED	2025-11-04 12:45:10.656701+01
7468bfca-5b7c-4202-aaea-be4b15763086	c117885f-43f8-4be0-8df2-f6d30a200cca	2025-09-24	\N	\N	\N	102.690000	\N	GENERATED	2025-11-04 12:45:10.65734+01
e8e3cc79-b473-4a16-a1ff-b2d7d821e60e	c117885f-43f8-4be0-8df2-f6d30a200cca	2025-09-25	\N	\N	\N	101.380000	\N	GENERATED	2025-11-04 12:45:10.658+01
8a2af00b-b209-429e-8f7e-f10f9c6fdec1	c117885f-43f8-4be0-8df2-f6d30a200cca	2025-09-26	\N	\N	\N	101.950000	\N	GENERATED	2025-11-04 12:45:10.658648+01
4117415f-bb19-45bb-a49c-aa16c9a6969b	c117885f-43f8-4be0-8df2-f6d30a200cca	2025-09-27	\N	\N	\N	101.900000	\N	GENERATED	2025-11-04 12:45:10.659297+01
63efc073-8802-4ad5-afcb-3cfe56ef785d	c117885f-43f8-4be0-8df2-f6d30a200cca	2025-09-28	\N	\N	\N	102.140000	\N	GENERATED	2025-11-04 12:45:10.660177+01
33f27dd7-6d91-46fe-8de2-b76d29c490d7	c117885f-43f8-4be0-8df2-f6d30a200cca	2025-09-29	\N	\N	\N	102.110000	\N	GENERATED	2025-11-04 12:45:10.660972+01
05d72560-d0bf-49eb-81f5-1fa6f74c385e	c117885f-43f8-4be0-8df2-f6d30a200cca	2025-09-30	\N	\N	\N	101.040000	\N	GENERATED	2025-11-04 12:45:10.661691+01
cb1400b1-36a1-457d-953f-adca9f149650	c117885f-43f8-4be0-8df2-f6d30a200cca	2025-10-01	\N	\N	\N	101.760000	\N	GENERATED	2025-11-04 12:45:10.662726+01
3c723f06-c430-4a85-8810-0c57e0ad8cd8	c117885f-43f8-4be0-8df2-f6d30a200cca	2025-10-02	\N	\N	\N	102.650000	\N	GENERATED	2025-11-04 12:45:10.663475+01
ccd95ae7-6c21-459f-8d45-4b1f335c0904	c117885f-43f8-4be0-8df2-f6d30a200cca	2025-10-03	\N	\N	\N	102.060000	\N	GENERATED	2025-11-04 12:45:10.664207+01
02387122-9bf6-4c83-a379-db21df72597b	c117885f-43f8-4be0-8df2-f6d30a200cca	2025-10-04	\N	\N	\N	101.570000	\N	GENERATED	2025-11-04 12:45:10.664885+01
6d971d89-9104-4a37-be5c-c3ab5668ee55	c117885f-43f8-4be0-8df2-f6d30a200cca	2025-10-05	\N	\N	\N	102.400000	\N	GENERATED	2025-11-04 12:45:10.665559+01
f6477f0e-c7fd-4a87-8a14-450fc700e034	c117885f-43f8-4be0-8df2-f6d30a200cca	2025-10-06	\N	\N	\N	101.250000	\N	GENERATED	2025-11-04 12:45:10.666208+01
b2589bee-73aa-4f99-bbc7-6d28538f2fbf	c117885f-43f8-4be0-8df2-f6d30a200cca	2025-10-07	\N	\N	\N	101.980000	\N	GENERATED	2025-11-04 12:45:10.666867+01
174d93cd-9b37-424f-b53b-eaac1967d372	c117885f-43f8-4be0-8df2-f6d30a200cca	2025-10-08	\N	\N	\N	102.830000	\N	GENERATED	2025-11-04 12:45:10.667796+01
42d2edba-ed35-449a-9a6e-7b5894a257ff	c117885f-43f8-4be0-8df2-f6d30a200cca	2025-10-09	\N	\N	\N	102.510000	\N	GENERATED	2025-11-04 12:45:10.668561+01
95e738a8-9379-40bb-ad6c-c7ff73c7aaaa	c117885f-43f8-4be0-8df2-f6d30a200cca	2025-10-10	\N	\N	\N	102.300000	\N	GENERATED	2025-11-04 12:45:10.669224+01
736bb218-d779-4115-9992-9f4fef5e773b	c117885f-43f8-4be0-8df2-f6d30a200cca	2025-10-11	\N	\N	\N	101.180000	\N	GENERATED	2025-11-04 12:45:10.669869+01
b85eb3b2-8c4c-4808-a2bc-09ac133adf3f	c117885f-43f8-4be0-8df2-f6d30a200cca	2025-10-12	\N	\N	\N	102.870000	\N	GENERATED	2025-11-04 12:45:10.670514+01
1ff4d6eb-5f7e-4673-855c-8e6394d2d08b	c117885f-43f8-4be0-8df2-f6d30a200cca	2025-10-13	\N	\N	\N	102.800000	\N	GENERATED	2025-11-04 12:45:10.67115+01
4ed711b7-4940-45ae-8833-254007616475	c117885f-43f8-4be0-8df2-f6d30a200cca	2025-10-14	\N	\N	\N	102.720000	\N	GENERATED	2025-11-04 12:45:10.671797+01
d08b811f-9205-4631-be06-a6f40d472e59	c117885f-43f8-4be0-8df2-f6d30a200cca	2025-10-15	\N	\N	\N	101.720000	\N	GENERATED	2025-11-04 12:45:10.672443+01
1c26204d-8902-4d5f-a6e9-571ab41adc16	c117885f-43f8-4be0-8df2-f6d30a200cca	2025-10-16	\N	\N	\N	102.350000	\N	GENERATED	2025-11-04 12:45:10.673164+01
491b510b-cbc9-446c-afb9-282f5b447a90	c117885f-43f8-4be0-8df2-f6d30a200cca	2025-10-17	\N	\N	\N	102.710000	\N	GENERATED	2025-11-04 12:45:10.67382+01
3d918c54-1b42-457b-8bf6-e9a9853b3348	c117885f-43f8-4be0-8df2-f6d30a200cca	2025-10-18	\N	\N	\N	101.970000	\N	GENERATED	2025-11-04 12:45:10.674479+01
b472f2e8-b175-436d-b15a-0ca8191d7af9	c117885f-43f8-4be0-8df2-f6d30a200cca	2025-10-19	\N	\N	\N	102.910000	\N	GENERATED	2025-11-04 12:45:10.675122+01
6586b5a9-4992-451d-b539-6cddac667cee	c117885f-43f8-4be0-8df2-f6d30a200cca	2025-10-20	\N	\N	\N	102.560000	\N	GENERATED	2025-11-04 12:45:10.67591+01
1f4df4fb-6168-4a1f-9acd-a81806313047	c117885f-43f8-4be0-8df2-f6d30a200cca	2025-10-21	\N	\N	\N	101.730000	\N	GENERATED	2025-11-04 12:45:10.676585+01
0c20b4d4-fd00-4e9e-afe6-56caec862417	c117885f-43f8-4be0-8df2-f6d30a200cca	2025-10-22	\N	\N	\N	102.940000	\N	GENERATED	2025-11-04 12:45:10.677235+01
f4943f9f-e57d-46e7-8469-a96c6931a004	c117885f-43f8-4be0-8df2-f6d30a200cca	2025-10-23	\N	\N	\N	103.290000	\N	GENERATED	2025-11-04 12:45:10.677913+01
bafef9d4-94fa-415a-becb-dcf186e86af0	c117885f-43f8-4be0-8df2-f6d30a200cca	2025-10-24	\N	\N	\N	102.450000	\N	GENERATED	2025-11-04 12:45:10.678568+01
86ab1d21-6947-4ed0-8c00-abdfde406318	c117885f-43f8-4be0-8df2-f6d30a200cca	2025-10-25	\N	\N	\N	102.530000	\N	GENERATED	2025-11-04 12:45:10.679211+01
70451711-84b1-4710-a42a-23918d20ed7e	c117885f-43f8-4be0-8df2-f6d30a200cca	2025-10-26	\N	\N	\N	101.730000	\N	GENERATED	2025-11-04 12:45:10.68026+01
836c551b-8bca-4a4c-8dd2-29c1379cb39d	c117885f-43f8-4be0-8df2-f6d30a200cca	2025-10-27	\N	\N	\N	102.110000	\N	GENERATED	2025-11-04 12:45:10.681112+01
bc001c79-c4e9-4f25-b745-e85b7ac92238	c117885f-43f8-4be0-8df2-f6d30a200cca	2025-10-28	\N	\N	\N	102.310000	\N	GENERATED	2025-11-04 12:45:10.681768+01
fb493463-2578-4e1f-8c0d-28c899016382	c117885f-43f8-4be0-8df2-f6d30a200cca	2025-10-29	\N	\N	\N	102.960000	\N	GENERATED	2025-11-04 12:45:10.682465+01
b20b2ca4-b36b-4abd-8353-6ac3699d5775	c117885f-43f8-4be0-8df2-f6d30a200cca	2025-10-30	\N	\N	\N	101.650000	\N	GENERATED	2025-11-04 12:45:10.683105+01
2f92d086-25dd-46fe-b50f-b09ad199bdf7	c117885f-43f8-4be0-8df2-f6d30a200cca	2025-10-31	\N	\N	\N	102.860000	\N	GENERATED	2025-11-04 12:45:10.68375+01
f346d613-260d-4b39-96e9-74e96b44f126	c117885f-43f8-4be0-8df2-f6d30a200cca	2025-11-01	\N	\N	\N	103.090000	\N	GENERATED	2025-11-04 12:45:10.684401+01
3e93509d-1b33-48eb-bfd4-6c3f9cb012eb	c117885f-43f8-4be0-8df2-f6d30a200cca	2025-11-02	\N	\N	\N	103.370000	\N	GENERATED	2025-11-04 12:45:10.685042+01
81f9016a-bba1-4c37-8c25-29b8fba35d72	c117885f-43f8-4be0-8df2-f6d30a200cca	2025-11-03	\N	\N	\N	101.850000	\N	GENERATED	2025-11-04 12:45:10.685696+01
23b2a095-3932-4a52-978e-218b521e34db	8f706b9d-54ae-4ac7-8ce5-0ed005362d68	2024-11-04	\N	\N	\N	69.780000	\N	GENERATED	2025-11-04 12:45:10.686896+01
84fb7f43-d262-4c6c-ae20-95cf07bae254	8f706b9d-54ae-4ac7-8ce5-0ed005362d68	2024-11-05	\N	\N	\N	70.590000	\N	GENERATED	2025-11-04 12:45:10.687555+01
f6183e3d-4143-4bae-9dad-cbb9d07013da	8f706b9d-54ae-4ac7-8ce5-0ed005362d68	2024-11-06	\N	\N	\N	70.430000	\N	GENERATED	2025-11-04 12:45:10.68821+01
b5004194-24c1-484e-aa0c-71951f9867ec	8f706b9d-54ae-4ac7-8ce5-0ed005362d68	2024-11-07	\N	\N	\N	70.160000	\N	GENERATED	2025-11-04 12:45:10.688981+01
097b35ef-af00-4dcb-b015-fbd58a731367	8f706b9d-54ae-4ac7-8ce5-0ed005362d68	2024-11-08	\N	\N	\N	70.610000	\N	GENERATED	2025-11-04 12:45:10.689655+01
133bf306-a448-4b8e-a231-5805d2052e97	8f706b9d-54ae-4ac7-8ce5-0ed005362d68	2024-11-09	\N	\N	\N	70.130000	\N	GENERATED	2025-11-04 12:45:10.6904+01
d139fe32-9156-4707-a86d-479af68097cc	8f706b9d-54ae-4ac7-8ce5-0ed005362d68	2024-11-10	\N	\N	\N	69.480000	\N	GENERATED	2025-11-04 12:45:10.691594+01
3a45056e-601c-4610-9e28-8e7fea4c5ea0	8f706b9d-54ae-4ac7-8ce5-0ed005362d68	2024-11-11	\N	\N	\N	70.430000	\N	GENERATED	2025-11-04 12:45:10.692332+01
5bae30ae-6684-4844-9e07-89540355a17d	8f706b9d-54ae-4ac7-8ce5-0ed005362d68	2024-11-12	\N	\N	\N	69.900000	\N	GENERATED	2025-11-04 12:45:10.693114+01
468df160-a36a-46f0-a4a9-82dbff7145fb	8f706b9d-54ae-4ac7-8ce5-0ed005362d68	2024-11-13	\N	\N	\N	70.060000	\N	GENERATED	2025-11-04 12:45:10.693768+01
0f83f5d7-9029-4574-8c1f-f7a90c59f368	8f706b9d-54ae-4ac7-8ce5-0ed005362d68	2024-11-14	\N	\N	\N	69.870000	\N	GENERATED	2025-11-04 12:45:10.694423+01
d5496728-e357-4bc0-96df-a5ecb860a1ac	8f706b9d-54ae-4ac7-8ce5-0ed005362d68	2024-11-15	\N	\N	\N	70.330000	\N	GENERATED	2025-11-04 12:45:10.695068+01
03b69a0d-598c-4be4-9a3a-f61bd589260d	8f706b9d-54ae-4ac7-8ce5-0ed005362d68	2024-11-16	\N	\N	\N	70.730000	\N	GENERATED	2025-11-04 12:45:10.69571+01
89ffb35f-f21e-4639-9a40-237e1ac97ac1	8f706b9d-54ae-4ac7-8ce5-0ed005362d68	2024-11-17	\N	\N	\N	69.510000	\N	GENERATED	2025-11-04 12:45:10.696349+01
158105fe-f3f9-4406-bc4f-b8f26718c534	8f706b9d-54ae-4ac7-8ce5-0ed005362d68	2024-11-18	\N	\N	\N	69.970000	\N	GENERATED	2025-11-04 12:45:10.697002+01
59320828-2ddd-49ab-b2ee-82ce4ed90f14	8f706b9d-54ae-4ac7-8ce5-0ed005362d68	2024-11-19	\N	\N	\N	69.890000	\N	GENERATED	2025-11-04 12:45:10.697648+01
1981f652-fda9-42ce-a2cc-3dc48c466230	8f706b9d-54ae-4ac7-8ce5-0ed005362d68	2024-11-20	\N	\N	\N	69.710000	\N	GENERATED	2025-11-04 12:45:10.698287+01
6629845e-08eb-404d-94b2-2593667377ed	8f706b9d-54ae-4ac7-8ce5-0ed005362d68	2024-11-21	\N	\N	\N	70.710000	\N	GENERATED	2025-11-04 12:45:10.698924+01
b794a807-0c3f-4cda-a977-1fdc53fb6ea3	8f706b9d-54ae-4ac7-8ce5-0ed005362d68	2024-11-22	\N	\N	\N	69.760000	\N	GENERATED	2025-11-04 12:45:10.699828+01
513cfa8b-f80e-4f21-afc8-b68736dd015e	8f706b9d-54ae-4ac7-8ce5-0ed005362d68	2024-11-23	\N	\N	\N	69.810000	\N	GENERATED	2025-11-04 12:45:10.700512+01
120133f7-777b-4748-bcdf-afe0474b7233	8f706b9d-54ae-4ac7-8ce5-0ed005362d68	2024-11-24	\N	\N	\N	70.390000	\N	GENERATED	2025-11-04 12:45:10.701166+01
dd98f9ac-cec0-40ea-b395-9456d7b3766b	8f706b9d-54ae-4ac7-8ce5-0ed005362d68	2024-11-25	\N	\N	\N	70.900000	\N	GENERATED	2025-11-04 12:45:10.701816+01
f0b898c1-4120-4e8e-82e6-9b52707e7c61	8f706b9d-54ae-4ac7-8ce5-0ed005362d68	2024-11-26	\N	\N	\N	70.070000	\N	GENERATED	2025-11-04 12:45:10.702462+01
9c18df01-a521-4786-a03c-23e24907e212	8f706b9d-54ae-4ac7-8ce5-0ed005362d68	2024-11-27	\N	\N	\N	70.600000	\N	GENERATED	2025-11-04 12:45:10.703231+01
8658d5b4-7146-4c49-a2e5-bcc616b43101	8f706b9d-54ae-4ac7-8ce5-0ed005362d68	2024-11-28	\N	\N	\N	70.560000	\N	GENERATED	2025-11-04 12:45:10.703888+01
5ab6f068-740e-4180-be1d-3c912efffe9e	8f706b9d-54ae-4ac7-8ce5-0ed005362d68	2024-11-29	\N	\N	\N	71.020000	\N	GENERATED	2025-11-04 12:45:10.704553+01
b3aa717f-6e9d-46ab-bc83-fc17ca56c354	8f706b9d-54ae-4ac7-8ce5-0ed005362d68	2024-11-30	\N	\N	\N	70.400000	\N	GENERATED	2025-11-04 12:45:10.705216+01
774af995-4e48-4313-83f7-ea75c432e718	8f706b9d-54ae-4ac7-8ce5-0ed005362d68	2024-12-01	\N	\N	\N	69.800000	\N	GENERATED	2025-11-04 12:45:10.70587+01
d0a15904-1558-447c-85b7-1b6097a215ac	8f706b9d-54ae-4ac7-8ce5-0ed005362d68	2024-12-02	\N	\N	\N	70.170000	\N	GENERATED	2025-11-04 12:45:10.706573+01
d70302b3-9d2c-4c67-a9f2-4814659bf081	8f706b9d-54ae-4ac7-8ce5-0ed005362d68	2024-12-03	\N	\N	\N	69.780000	\N	GENERATED	2025-11-04 12:45:10.70726+01
4681acd7-614e-41e2-b9b5-19221aa2d08d	8f706b9d-54ae-4ac7-8ce5-0ed005362d68	2024-12-04	\N	\N	\N	70.570000	\N	GENERATED	2025-11-04 12:45:10.707948+01
58678c85-3972-4b74-a27f-d210deac6560	8f706b9d-54ae-4ac7-8ce5-0ed005362d68	2024-12-05	\N	\N	\N	70.010000	\N	GENERATED	2025-11-04 12:45:10.708604+01
8a9ae114-60d3-48cc-8fd5-8b5e8c019343	8f706b9d-54ae-4ac7-8ce5-0ed005362d68	2024-12-06	\N	\N	\N	69.840000	\N	GENERATED	2025-11-04 12:45:10.709271+01
102283f2-da45-4b8f-aaee-f183252c2437	8f706b9d-54ae-4ac7-8ce5-0ed005362d68	2024-12-07	\N	\N	\N	69.810000	\N	GENERATED	2025-11-04 12:45:10.709922+01
fbd9a0c7-4a3b-4be0-91e7-c1f914404913	8f706b9d-54ae-4ac7-8ce5-0ed005362d68	2024-12-08	\N	\N	\N	70.560000	\N	GENERATED	2025-11-04 12:45:10.710572+01
85f422fa-cab0-4a9e-a03b-1754b9cd5b67	8f706b9d-54ae-4ac7-8ce5-0ed005362d68	2024-12-09	\N	\N	\N	70.420000	\N	GENERATED	2025-11-04 12:45:10.711222+01
73aab5e1-4026-49fe-a94a-5e766455442c	8f706b9d-54ae-4ac7-8ce5-0ed005362d68	2024-12-10	\N	\N	\N	70.230000	\N	GENERATED	2025-11-04 12:45:10.711882+01
5c83a3c4-89b2-4ede-9068-911de171942f	8f706b9d-54ae-4ac7-8ce5-0ed005362d68	2024-12-11	\N	\N	\N	70.950000	\N	GENERATED	2025-11-04 12:45:10.712569+01
7b408f34-b19e-41ae-b8d7-21c07fb4f46a	8f706b9d-54ae-4ac7-8ce5-0ed005362d68	2024-12-12	\N	\N	\N	70.430000	\N	GENERATED	2025-11-04 12:45:10.713281+01
4a4700cd-464c-4d2f-8a9c-bd44d47fc47c	8f706b9d-54ae-4ac7-8ce5-0ed005362d68	2024-12-13	\N	\N	\N	70.100000	\N	GENERATED	2025-11-04 12:45:10.713938+01
e458e7e3-30e1-4199-950b-a7badc721f37	8f706b9d-54ae-4ac7-8ce5-0ed005362d68	2024-12-14	\N	\N	\N	70.580000	\N	GENERATED	2025-11-04 12:45:10.714609+01
296d4fe3-94d3-43a5-ae0a-7ce7cb4de719	8f706b9d-54ae-4ac7-8ce5-0ed005362d68	2024-12-15	\N	\N	\N	70.570000	\N	GENERATED	2025-11-04 12:45:10.71525+01
da7bfec8-8562-45b6-a500-c5870671bf99	8f706b9d-54ae-4ac7-8ce5-0ed005362d68	2024-12-16	\N	\N	\N	70.830000	\N	GENERATED	2025-11-04 12:45:10.715897+01
d65cf0b8-c7c4-4126-a789-d6f2e72cdcfe	8f706b9d-54ae-4ac7-8ce5-0ed005362d68	2024-12-17	\N	\N	\N	70.240000	\N	GENERATED	2025-11-04 12:45:10.716543+01
c0aaf7e3-720f-4350-9d49-4be701f28d6d	8f706b9d-54ae-4ac7-8ce5-0ed005362d68	2024-12-18	\N	\N	\N	70.790000	\N	GENERATED	2025-11-04 12:45:10.717179+01
286b3693-368d-4643-8709-18eeeeaa4bd9	8f706b9d-54ae-4ac7-8ce5-0ed005362d68	2024-12-19	\N	\N	\N	70.430000	\N	GENERATED	2025-11-04 12:45:10.717829+01
dd6d78d5-b426-44dd-9eaf-3e0bd6e39eca	8f706b9d-54ae-4ac7-8ce5-0ed005362d68	2024-12-20	\N	\N	\N	70.110000	\N	GENERATED	2025-11-04 12:45:10.718503+01
cf607fa7-5f25-4877-bafe-35a2e1226e08	8f706b9d-54ae-4ac7-8ce5-0ed005362d68	2024-12-21	\N	\N	\N	70.690000	\N	GENERATED	2025-11-04 12:45:10.719139+01
f8df1d14-5432-4817-a5ff-0405fc39095f	8f706b9d-54ae-4ac7-8ce5-0ed005362d68	2024-12-22	\N	\N	\N	70.980000	\N	GENERATED	2025-11-04 12:45:10.719798+01
7403dfb8-43cc-4a9c-9623-a9cee550c6fe	8f706b9d-54ae-4ac7-8ce5-0ed005362d68	2024-12-23	\N	\N	\N	71.200000	\N	GENERATED	2025-11-04 12:45:10.720456+01
fd89ac45-06a6-498b-9740-468e3ef797a5	8f706b9d-54ae-4ac7-8ce5-0ed005362d68	2024-12-24	\N	\N	\N	70.250000	\N	GENERATED	2025-11-04 12:45:10.721091+01
e265e210-aa90-401a-9eb3-f0df1aecf8b3	8f706b9d-54ae-4ac7-8ce5-0ed005362d68	2024-12-25	\N	\N	\N	71.080000	\N	GENERATED	2025-11-04 12:45:10.721893+01
b7cc458f-d37e-442f-987f-6551ebc3e4b0	8f706b9d-54ae-4ac7-8ce5-0ed005362d68	2024-12-26	\N	\N	\N	70.110000	\N	GENERATED	2025-11-04 12:45:10.722563+01
3cfeb458-b889-40ea-900c-ff386e019a9c	8f706b9d-54ae-4ac7-8ce5-0ed005362d68	2024-12-27	\N	\N	\N	71.000000	\N	GENERATED	2025-11-04 12:45:10.723208+01
9e1b2f0b-a684-4c56-9634-6175f00fc7bb	8f706b9d-54ae-4ac7-8ce5-0ed005362d68	2024-12-28	\N	\N	\N	70.790000	\N	GENERATED	2025-11-04 12:45:10.723912+01
e445bb91-38fa-4716-b4ac-4cce93baf914	8f706b9d-54ae-4ac7-8ce5-0ed005362d68	2024-12-29	\N	\N	\N	70.840000	\N	GENERATED	2025-11-04 12:45:10.724605+01
8171e8c2-148a-451d-a8be-d1abaa8e2cc6	8f706b9d-54ae-4ac7-8ce5-0ed005362d68	2024-12-30	\N	\N	\N	70.660000	\N	GENERATED	2025-11-04 12:45:10.725264+01
04c09502-1989-4869-8446-084fef451a72	8f706b9d-54ae-4ac7-8ce5-0ed005362d68	2024-12-31	\N	\N	\N	70.310000	\N	GENERATED	2025-11-04 12:45:10.725917+01
e22b2b8d-fab1-48d7-bebf-81790ac68266	8f706b9d-54ae-4ac7-8ce5-0ed005362d68	2025-01-01	\N	\N	\N	70.420000	\N	GENERATED	2025-11-04 12:45:10.72656+01
02466373-b7c7-4c67-881f-cdcca45fd771	8f706b9d-54ae-4ac7-8ce5-0ed005362d68	2025-01-02	\N	\N	\N	70.570000	\N	GENERATED	2025-11-04 12:45:10.727208+01
6f078dd6-0c07-4612-b2df-5c1b45b52147	8f706b9d-54ae-4ac7-8ce5-0ed005362d68	2025-01-03	\N	\N	\N	71.490000	\N	GENERATED	2025-11-04 12:45:10.728333+01
4f0b5c5c-8636-4023-85c9-9885fc33709a	8f706b9d-54ae-4ac7-8ce5-0ed005362d68	2025-01-04	\N	\N	\N	71.270000	\N	GENERATED	2025-11-04 12:45:10.728982+01
5bb78bad-0deb-4e46-bfff-49a3d22ffcc4	8f706b9d-54ae-4ac7-8ce5-0ed005362d68	2025-01-05	\N	\N	\N	70.660000	\N	GENERATED	2025-11-04 12:45:10.729638+01
dcfe08ba-7b98-44ba-9907-18ef3622bac5	8f706b9d-54ae-4ac7-8ce5-0ed005362d68	2025-01-06	\N	\N	\N	71.530000	\N	GENERATED	2025-11-04 12:45:10.730273+01
d9cc177d-a410-4267-b40e-5280d47edc39	8f706b9d-54ae-4ac7-8ce5-0ed005362d68	2025-01-07	\N	\N	\N	71.320000	\N	GENERATED	2025-11-04 12:45:10.730926+01
464b6270-43b0-4f8f-bec9-8c30e52ad3bb	8f706b9d-54ae-4ac7-8ce5-0ed005362d68	2025-01-08	\N	\N	\N	70.390000	\N	GENERATED	2025-11-04 12:45:10.731572+01
1212ce51-44b7-4b04-919b-76db8badeb88	8f706b9d-54ae-4ac7-8ce5-0ed005362d68	2025-01-09	\N	\N	\N	70.480000	\N	GENERATED	2025-11-04 12:45:10.73222+01
bd2b22cc-e7c7-4d05-a02a-2cc7e0a4e064	8f706b9d-54ae-4ac7-8ce5-0ed005362d68	2025-01-10	\N	\N	\N	71.490000	\N	GENERATED	2025-11-04 12:45:10.73293+01
6c01ad63-6197-4f44-b55e-9ccde8449e9c	8f706b9d-54ae-4ac7-8ce5-0ed005362d68	2025-01-11	\N	\N	\N	71.180000	\N	GENERATED	2025-11-04 12:45:10.733572+01
3cfd2518-ad51-4d3d-b44a-a1e33f848947	8f706b9d-54ae-4ac7-8ce5-0ed005362d68	2025-01-12	\N	\N	\N	70.460000	\N	GENERATED	2025-11-04 12:45:10.734244+01
62187413-59e3-4088-837e-bce7962b3a5e	8f706b9d-54ae-4ac7-8ce5-0ed005362d68	2025-01-13	\N	\N	\N	70.540000	\N	GENERATED	2025-11-04 12:45:10.734893+01
4caa11b1-1da5-47f6-8b90-e4ede94717d9	8f706b9d-54ae-4ac7-8ce5-0ed005362d68	2025-01-14	\N	\N	\N	70.730000	\N	GENERATED	2025-11-04 12:45:10.735556+01
852e7f81-b082-45a9-be1b-405d80c83e65	8f706b9d-54ae-4ac7-8ce5-0ed005362d68	2025-01-15	\N	\N	\N	71.000000	\N	GENERATED	2025-11-04 12:45:10.736193+01
80037b87-9e19-4457-84ef-1a28391c7406	8f706b9d-54ae-4ac7-8ce5-0ed005362d68	2025-01-16	\N	\N	\N	70.800000	\N	GENERATED	2025-11-04 12:45:10.736856+01
c1a5e725-b8d6-4d9d-98f9-bb61f3bd36bd	8f706b9d-54ae-4ac7-8ce5-0ed005362d68	2025-01-17	\N	\N	\N	71.120000	\N	GENERATED	2025-11-04 12:45:10.737707+01
a424ed05-91ab-46ed-b24f-d613e1d8a9c7	8f706b9d-54ae-4ac7-8ce5-0ed005362d68	2025-01-18	\N	\N	\N	71.280000	\N	GENERATED	2025-11-04 12:45:10.738433+01
6a321534-5ba8-4699-b302-500c8eaab013	8f706b9d-54ae-4ac7-8ce5-0ed005362d68	2025-01-19	\N	\N	\N	71.330000	\N	GENERATED	2025-11-04 12:45:10.739097+01
a7b764ad-b7cc-453b-8dd6-17e499fd4edd	8f706b9d-54ae-4ac7-8ce5-0ed005362d68	2025-01-20	\N	\N	\N	70.550000	\N	GENERATED	2025-11-04 12:45:10.739785+01
a9921f04-4d93-4900-a822-58e564bca493	8f706b9d-54ae-4ac7-8ce5-0ed005362d68	2025-01-21	\N	\N	\N	70.580000	\N	GENERATED	2025-11-04 12:45:10.740434+01
3d53cb72-ccbc-4715-84b4-eea59ff9e0dc	8f706b9d-54ae-4ac7-8ce5-0ed005362d68	2025-01-22	\N	\N	\N	70.810000	\N	GENERATED	2025-11-04 12:45:10.741097+01
828b2f0d-d1d4-4617-bb66-71c4886f43f1	8f706b9d-54ae-4ac7-8ce5-0ed005362d68	2025-01-23	\N	\N	\N	70.710000	\N	GENERATED	2025-11-04 12:45:10.741775+01
12df85c2-dadb-486b-8873-2fef165ef983	8f706b9d-54ae-4ac7-8ce5-0ed005362d68	2025-01-24	\N	\N	\N	71.520000	\N	GENERATED	2025-11-04 12:45:10.742425+01
0a581d64-c10e-4c21-8989-86d93240428c	8f706b9d-54ae-4ac7-8ce5-0ed005362d68	2025-01-25	\N	\N	\N	71.750000	\N	GENERATED	2025-11-04 12:45:10.743112+01
924ba677-dd19-4fbc-b244-b7907bc53a17	8f706b9d-54ae-4ac7-8ce5-0ed005362d68	2025-01-26	\N	\N	\N	70.700000	\N	GENERATED	2025-11-04 12:45:10.743762+01
d92cad40-2085-403b-91ec-ebbf2d007ed3	8f706b9d-54ae-4ac7-8ce5-0ed005362d68	2025-01-27	\N	\N	\N	70.600000	\N	GENERATED	2025-11-04 12:45:10.744436+01
b183a603-fb35-4c70-b9b7-dfcac24e5562	8f706b9d-54ae-4ac7-8ce5-0ed005362d68	2025-01-28	\N	\N	\N	71.010000	\N	GENERATED	2025-11-04 12:45:10.745164+01
b000f6a7-b928-45d7-a680-e5e0ddc3c7ed	8f706b9d-54ae-4ac7-8ce5-0ed005362d68	2025-01-29	\N	\N	\N	71.530000	\N	GENERATED	2025-11-04 12:45:10.745805+01
1403559b-54e8-4ba7-8a81-4a38c0ee8206	8f706b9d-54ae-4ac7-8ce5-0ed005362d68	2025-01-30	\N	\N	\N	71.230000	\N	GENERATED	2025-11-04 12:45:10.746452+01
10cc1132-0365-443e-b91d-b8eae9656613	8f706b9d-54ae-4ac7-8ce5-0ed005362d68	2025-01-31	\N	\N	\N	70.860000	\N	GENERATED	2025-11-04 12:45:10.747092+01
4aef8bfb-d44d-4924-ba9b-43981f92e0c5	8f706b9d-54ae-4ac7-8ce5-0ed005362d68	2025-02-01	\N	\N	\N	71.350000	\N	GENERATED	2025-11-04 12:45:10.747749+01
973eab49-868c-40f5-8823-634ddf2fb242	8f706b9d-54ae-4ac7-8ce5-0ed005362d68	2025-02-02	\N	\N	\N	71.130000	\N	GENERATED	2025-11-04 12:45:10.748406+01
3c14a376-6534-4ec2-a31b-ee041b90f27d	8f706b9d-54ae-4ac7-8ce5-0ed005362d68	2025-02-03	\N	\N	\N	71.240000	\N	GENERATED	2025-11-04 12:45:10.749077+01
ba1f70ec-224f-4616-a878-c01f29a6d33f	8f706b9d-54ae-4ac7-8ce5-0ed005362d68	2025-02-04	\N	\N	\N	70.920000	\N	GENERATED	2025-11-04 12:45:10.749735+01
a86a7a0f-ab14-42ae-81a2-8aefdefad828	8f706b9d-54ae-4ac7-8ce5-0ed005362d68	2025-02-05	\N	\N	\N	71.550000	\N	GENERATED	2025-11-04 12:45:10.750378+01
44a0e4c6-87e5-47c3-b4a4-a3023bb6102a	8f706b9d-54ae-4ac7-8ce5-0ed005362d68	2025-02-06	\N	\N	\N	71.830000	\N	GENERATED	2025-11-04 12:45:10.751024+01
a556bb87-fb83-4a62-9d3c-54da0674d2fc	8f706b9d-54ae-4ac7-8ce5-0ed005362d68	2025-02-07	\N	\N	\N	71.550000	\N	GENERATED	2025-11-04 12:45:10.75167+01
7ee67144-f868-424b-9687-d86d728c800f	8f706b9d-54ae-4ac7-8ce5-0ed005362d68	2025-02-08	\N	\N	\N	71.640000	\N	GENERATED	2025-11-04 12:45:10.752347+01
05005d0f-aab2-4a4f-bacf-f1b54e7b6758	8f706b9d-54ae-4ac7-8ce5-0ed005362d68	2025-02-09	\N	\N	\N	71.230000	\N	GENERATED	2025-11-04 12:45:10.753135+01
64e9baf5-1d4b-49b1-8236-cc1d0e7c095a	8f706b9d-54ae-4ac7-8ce5-0ed005362d68	2025-02-10	\N	\N	\N	71.980000	\N	GENERATED	2025-11-04 12:45:10.753809+01
8b9c90cc-5fb4-4c09-afeb-d592c662968c	8f706b9d-54ae-4ac7-8ce5-0ed005362d68	2025-02-11	\N	\N	\N	71.550000	\N	GENERATED	2025-11-04 12:45:10.754511+01
aebc71a7-a245-473f-a939-49bf4bcf802a	8f706b9d-54ae-4ac7-8ce5-0ed005362d68	2025-02-12	\N	\N	\N	71.440000	\N	GENERATED	2025-11-04 12:45:10.755246+01
05c087b1-b99b-4372-815b-38d373695753	8f706b9d-54ae-4ac7-8ce5-0ed005362d68	2025-02-13	\N	\N	\N	71.560000	\N	GENERATED	2025-11-04 12:45:10.755894+01
b0795181-a672-4750-bc76-4d9d7df14d48	8f706b9d-54ae-4ac7-8ce5-0ed005362d68	2025-02-14	\N	\N	\N	71.040000	\N	GENERATED	2025-11-04 12:45:10.75655+01
c369fd53-14e8-4602-bc18-7ffe7cf04147	8f706b9d-54ae-4ac7-8ce5-0ed005362d68	2025-02-15	\N	\N	\N	71.990000	\N	GENERATED	2025-11-04 12:45:10.757208+01
84b15093-ecf6-43f2-961c-0498f8cf89e8	8f706b9d-54ae-4ac7-8ce5-0ed005362d68	2025-02-16	\N	\N	\N	71.880000	\N	GENERATED	2025-11-04 12:45:10.757874+01
36fb1cc2-04f5-49c2-87ef-6d43fdc2511c	8f706b9d-54ae-4ac7-8ce5-0ed005362d68	2025-02-17	\N	\N	\N	70.970000	\N	GENERATED	2025-11-04 12:45:10.758533+01
b3953a65-4339-4e13-bf12-d1f6c797cce9	8f706b9d-54ae-4ac7-8ce5-0ed005362d68	2025-02-18	\N	\N	\N	71.650000	\N	GENERATED	2025-11-04 12:45:10.75918+01
48801d91-67be-46c2-aec2-75e531037c17	8f706b9d-54ae-4ac7-8ce5-0ed005362d68	2025-02-19	\N	\N	\N	71.200000	\N	GENERATED	2025-11-04 12:45:10.75987+01
73bc89fa-4cc1-4bba-87ee-35bd784138e0	8f706b9d-54ae-4ac7-8ce5-0ed005362d68	2025-02-20	\N	\N	\N	72.050000	\N	GENERATED	2025-11-04 12:45:10.760525+01
18ce155c-8f95-4531-a36d-5159c43e8183	8f706b9d-54ae-4ac7-8ce5-0ed005362d68	2025-02-21	\N	\N	\N	71.600000	\N	GENERATED	2025-11-04 12:45:10.761169+01
dcb52bc0-4240-4568-b9bf-c90d30a91d2a	8f706b9d-54ae-4ac7-8ce5-0ed005362d68	2025-02-22	\N	\N	\N	72.040000	\N	GENERATED	2025-11-04 12:45:10.761829+01
f26381c2-5c11-4399-a894-4e6a5cb68681	8f706b9d-54ae-4ac7-8ce5-0ed005362d68	2025-02-23	\N	\N	\N	71.450000	\N	GENERATED	2025-11-04 12:45:10.762506+01
2b7bc364-f822-4d7d-a4b7-81d30fffba77	8f706b9d-54ae-4ac7-8ce5-0ed005362d68	2025-02-24	\N	\N	\N	71.470000	\N	GENERATED	2025-11-04 12:45:10.763146+01
651e3d8e-1db4-4777-9e39-56882c1751fe	8f706b9d-54ae-4ac7-8ce5-0ed005362d68	2025-02-25	\N	\N	\N	71.700000	\N	GENERATED	2025-11-04 12:45:10.763794+01
8e19d457-77b0-485a-bbac-29eca6163b88	8f706b9d-54ae-4ac7-8ce5-0ed005362d68	2025-02-26	\N	\N	\N	71.050000	\N	GENERATED	2025-11-04 12:45:10.764454+01
d45e02c9-4ccb-4c74-9b7b-a065643b3a77	8f706b9d-54ae-4ac7-8ce5-0ed005362d68	2025-02-27	\N	\N	\N	71.220000	\N	GENERATED	2025-11-04 12:45:10.765092+01
2510f945-cf5a-48f9-9da6-5d3795906060	8f706b9d-54ae-4ac7-8ce5-0ed005362d68	2025-02-28	\N	\N	\N	72.110000	\N	GENERATED	2025-11-04 12:45:10.765749+01
c348df38-22c7-4fff-98cd-7a672926dbfc	8f706b9d-54ae-4ac7-8ce5-0ed005362d68	2025-03-01	\N	\N	\N	71.590000	\N	GENERATED	2025-11-04 12:45:10.766396+01
e9368882-e04a-46b9-9c75-3f244f80beb1	8f706b9d-54ae-4ac7-8ce5-0ed005362d68	2025-03-02	\N	\N	\N	71.650000	\N	GENERATED	2025-11-04 12:45:10.767041+01
47a7c413-fe8a-4623-902f-4e4710f73b46	8f706b9d-54ae-4ac7-8ce5-0ed005362d68	2025-03-03	\N	\N	\N	71.170000	\N	GENERATED	2025-11-04 12:45:10.767697+01
f26270bb-bd86-4372-bf55-1b545ed38d5a	8f706b9d-54ae-4ac7-8ce5-0ed005362d68	2025-03-04	\N	\N	\N	72.370000	\N	GENERATED	2025-11-04 12:45:10.76843+01
c3090d75-586c-4b1a-bc51-7fb178e26467	8f706b9d-54ae-4ac7-8ce5-0ed005362d68	2025-03-05	\N	\N	\N	72.370000	\N	GENERATED	2025-11-04 12:45:10.769218+01
31059618-9306-435a-9844-d78d3e384f7f	8f706b9d-54ae-4ac7-8ce5-0ed005362d68	2025-03-06	\N	\N	\N	71.310000	\N	GENERATED	2025-11-04 12:45:10.76988+01
7131f6fe-b696-4b70-89aa-d38ab548bdb0	8f706b9d-54ae-4ac7-8ce5-0ed005362d68	2025-03-07	\N	\N	\N	72.550000	\N	GENERATED	2025-11-04 12:45:10.770545+01
ba217899-f710-4140-81ff-a927deb737e7	8f706b9d-54ae-4ac7-8ce5-0ed005362d68	2025-03-08	\N	\N	\N	71.880000	\N	GENERATED	2025-11-04 12:45:10.771195+01
519ad650-73d8-458d-8a76-bac6d65390cd	8f706b9d-54ae-4ac7-8ce5-0ed005362d68	2025-03-09	\N	\N	\N	71.830000	\N	GENERATED	2025-11-04 12:45:10.771877+01
b2eb575e-b20e-4054-a2d7-b1b88b815e07	8f706b9d-54ae-4ac7-8ce5-0ed005362d68	2025-03-10	\N	\N	\N	71.290000	\N	GENERATED	2025-11-04 12:45:10.772557+01
4ea2cc35-729c-4ebc-bf13-fcff695b9168	8f706b9d-54ae-4ac7-8ce5-0ed005362d68	2025-03-11	\N	\N	\N	71.410000	\N	GENERATED	2025-11-04 12:45:10.77328+01
153b99b7-1976-494a-8f22-acf8eb34abfe	8f706b9d-54ae-4ac7-8ce5-0ed005362d68	2025-03-12	\N	\N	\N	72.230000	\N	GENERATED	2025-11-04 12:45:10.773938+01
1e8c7a84-87a4-4a9b-9049-ba158d519d81	8f706b9d-54ae-4ac7-8ce5-0ed005362d68	2025-03-13	\N	\N	\N	71.840000	\N	GENERATED	2025-11-04 12:45:10.774592+01
c14675cd-cea8-4a24-9bbb-7f35a5ba4ad1	8f706b9d-54ae-4ac7-8ce5-0ed005362d68	2025-03-14	\N	\N	\N	71.520000	\N	GENERATED	2025-11-04 12:45:10.775241+01
17da2d3d-03d8-4770-a6d2-dcd3e77b6983	8f706b9d-54ae-4ac7-8ce5-0ed005362d68	2025-03-15	\N	\N	\N	71.500000	\N	GENERATED	2025-11-04 12:45:10.775885+01
d6d4f89f-815f-4eea-be94-2a02dd44f7ea	8f706b9d-54ae-4ac7-8ce5-0ed005362d68	2025-03-16	\N	\N	\N	71.910000	\N	GENERATED	2025-11-04 12:45:10.77654+01
8df40316-3a25-4c14-bcee-47368ba35afe	8f706b9d-54ae-4ac7-8ce5-0ed005362d68	2025-03-17	\N	\N	\N	72.680000	\N	GENERATED	2025-11-04 12:45:10.777178+01
7d452f97-42f2-4ba3-aa1f-8b9ef2406c34	8f706b9d-54ae-4ac7-8ce5-0ed005362d68	2025-03-18	\N	\N	\N	71.360000	\N	GENERATED	2025-11-04 12:45:10.77783+01
7969d285-40ab-4505-9249-e6cf5560bc12	8f706b9d-54ae-4ac7-8ce5-0ed005362d68	2025-03-19	\N	\N	\N	71.960000	\N	GENERATED	2025-11-04 12:45:10.778473+01
2b9c35b0-b924-47d0-ba6d-5d5bf0e41674	8f706b9d-54ae-4ac7-8ce5-0ed005362d68	2025-03-20	\N	\N	\N	71.620000	\N	GENERATED	2025-11-04 12:45:10.779231+01
746a06e4-f2ef-44f6-9169-cc259c38cf54	8f706b9d-54ae-4ac7-8ce5-0ed005362d68	2025-03-21	\N	\N	\N	72.470000	\N	GENERATED	2025-11-04 12:45:10.779893+01
ebbfd63c-bd84-412a-9a6a-5e7006745fbe	8f706b9d-54ae-4ac7-8ce5-0ed005362d68	2025-03-22	\N	\N	\N	72.480000	\N	GENERATED	2025-11-04 12:45:10.780558+01
6c30ff97-6e02-4413-8840-1f5b58fd88d7	8f706b9d-54ae-4ac7-8ce5-0ed005362d68	2025-03-23	\N	\N	\N	72.330000	\N	GENERATED	2025-11-04 12:45:10.78165+01
db545d01-99e5-47ec-abb1-baf9ba66a6d0	8f706b9d-54ae-4ac7-8ce5-0ed005362d68	2025-03-24	\N	\N	\N	72.550000	\N	GENERATED	2025-11-04 12:45:10.782304+01
ff3ef5c5-303f-46b9-93ef-35910095ada9	8f706b9d-54ae-4ac7-8ce5-0ed005362d68	2025-03-25	\N	\N	\N	71.620000	\N	GENERATED	2025-11-04 12:45:10.782958+01
e550b541-02f7-4413-a690-7c1c9557cc03	8f706b9d-54ae-4ac7-8ce5-0ed005362d68	2025-03-26	\N	\N	\N	71.540000	\N	GENERATED	2025-11-04 12:45:10.783689+01
484d0d33-5861-4ba5-82f2-5fc08c42b425	8f706b9d-54ae-4ac7-8ce5-0ed005362d68	2025-03-27	\N	\N	\N	71.570000	\N	GENERATED	2025-11-04 12:45:10.784376+01
52c143ec-9e4d-49cf-ae21-5f44db0c148b	8f706b9d-54ae-4ac7-8ce5-0ed005362d68	2025-03-28	\N	\N	\N	71.640000	\N	GENERATED	2025-11-04 12:45:10.785048+01
75e79599-3255-4a97-a00a-e74c22b17fc0	8f706b9d-54ae-4ac7-8ce5-0ed005362d68	2025-03-29	\N	\N	\N	72.740000	\N	GENERATED	2025-11-04 12:45:10.785714+01
156acaca-4548-469e-8160-3de6b4bb6d89	8f706b9d-54ae-4ac7-8ce5-0ed005362d68	2025-03-30	\N	\N	\N	72.370000	\N	GENERATED	2025-11-04 12:45:10.78636+01
9bcec688-c10a-47ca-9c88-e25a692d02a2	8f706b9d-54ae-4ac7-8ce5-0ed005362d68	2025-03-31	\N	\N	\N	71.800000	\N	GENERATED	2025-11-04 12:45:10.787041+01
8721047a-1dee-40e9-b4b0-80a116a1cea8	8f706b9d-54ae-4ac7-8ce5-0ed005362d68	2025-04-01	\N	\N	\N	72.110000	\N	GENERATED	2025-11-04 12:45:10.787705+01
601a01ff-1ab8-4a74-9bd9-e36b617c445c	8f706b9d-54ae-4ac7-8ce5-0ed005362d68	2025-04-02	\N	\N	\N	71.740000	\N	GENERATED	2025-11-04 12:45:10.78836+01
5c15abd1-90fd-4deb-b9cf-5f6842c09101	8f706b9d-54ae-4ac7-8ce5-0ed005362d68	2025-04-03	\N	\N	\N	72.880000	\N	GENERATED	2025-11-04 12:45:10.789012+01
8ac52682-6c3a-4131-8cfc-db8cadcc107e	8f706b9d-54ae-4ac7-8ce5-0ed005362d68	2025-04-04	\N	\N	\N	72.050000	\N	GENERATED	2025-11-04 12:45:10.789689+01
a60f7218-a626-4f7a-8cce-8d13d63f9d18	8f706b9d-54ae-4ac7-8ce5-0ed005362d68	2025-04-05	\N	\N	\N	72.040000	\N	GENERATED	2025-11-04 12:45:10.790328+01
b02fa332-7139-4615-9be6-76f89e8d99de	8f706b9d-54ae-4ac7-8ce5-0ed005362d68	2025-04-06	\N	\N	\N	71.930000	\N	GENERATED	2025-11-04 12:45:10.790972+01
c94e29ae-6c40-4628-a964-37fb7e6904bb	8f706b9d-54ae-4ac7-8ce5-0ed005362d68	2025-04-07	\N	\N	\N	73.040000	\N	GENERATED	2025-11-04 12:45:10.791624+01
bb740122-8375-4c60-ba0e-35681abd11a1	8f706b9d-54ae-4ac7-8ce5-0ed005362d68	2025-04-08	\N	\N	\N	72.890000	\N	GENERATED	2025-11-04 12:45:10.79226+01
9566d06e-58b8-498a-98b3-b6d3f83777e4	8f706b9d-54ae-4ac7-8ce5-0ed005362d68	2025-04-09	\N	\N	\N	71.720000	\N	GENERATED	2025-11-04 12:45:10.793044+01
8dd9ad25-b98f-4405-bfc4-ff715617c4df	8f706b9d-54ae-4ac7-8ce5-0ed005362d68	2025-04-10	\N	\N	\N	73.050000	\N	GENERATED	2025-11-04 12:45:10.793956+01
7ab40974-c8bc-4673-b7ec-370a9f5410a1	8f706b9d-54ae-4ac7-8ce5-0ed005362d68	2025-04-11	\N	\N	\N	73.000000	\N	GENERATED	2025-11-04 12:45:10.794605+01
e7182c5a-897e-480f-91b0-bf7c53c00976	8f706b9d-54ae-4ac7-8ce5-0ed005362d68	2025-04-12	\N	\N	\N	72.410000	\N	GENERATED	2025-11-04 12:45:10.795237+01
178459c0-8864-43de-92f9-6e0d979e73d0	8f706b9d-54ae-4ac7-8ce5-0ed005362d68	2025-04-13	\N	\N	\N	71.780000	\N	GENERATED	2025-11-04 12:45:10.795891+01
587249b7-b0af-4e33-ada9-5eb988224fb0	8f706b9d-54ae-4ac7-8ce5-0ed005362d68	2025-04-14	\N	\N	\N	73.010000	\N	GENERATED	2025-11-04 12:45:10.796543+01
d6afa149-2a9c-4447-af29-14d8644678db	8f706b9d-54ae-4ac7-8ce5-0ed005362d68	2025-04-15	\N	\N	\N	72.320000	\N	GENERATED	2025-11-04 12:45:10.797179+01
ca3f155b-c607-4f51-944f-fbaf965ae137	8f706b9d-54ae-4ac7-8ce5-0ed005362d68	2025-04-16	\N	\N	\N	72.460000	\N	GENERATED	2025-11-04 12:45:10.797847+01
c68c8e5f-0a88-468d-9657-8efe9052ab7e	8f706b9d-54ae-4ac7-8ce5-0ed005362d68	2025-04-17	\N	\N	\N	72.480000	\N	GENERATED	2025-11-04 12:45:10.798497+01
7a4fb683-0bf5-4e99-a2fa-77752ad39b03	8f706b9d-54ae-4ac7-8ce5-0ed005362d68	2025-04-18	\N	\N	\N	72.200000	\N	GENERATED	2025-11-04 12:45:10.799136+01
fec3a981-2670-4851-9c23-dea89ab803ee	8f706b9d-54ae-4ac7-8ce5-0ed005362d68	2025-04-19	\N	\N	\N	73.240000	\N	GENERATED	2025-11-04 12:45:10.800014+01
8d352d0d-01ea-46c7-ad7a-1c414006c316	8f706b9d-54ae-4ac7-8ce5-0ed005362d68	2025-04-20	\N	\N	\N	72.490000	\N	GENERATED	2025-11-04 12:45:10.800685+01
bd0d4bd8-27d8-4374-bd8b-63423753ceb9	8f706b9d-54ae-4ac7-8ce5-0ed005362d68	2025-04-21	\N	\N	\N	72.190000	\N	GENERATED	2025-11-04 12:45:10.801346+01
286fa672-7b7b-4a1c-87fa-03337194ce28	8f706b9d-54ae-4ac7-8ce5-0ed005362d68	2025-04-22	\N	\N	\N	72.870000	\N	GENERATED	2025-11-04 12:45:10.80199+01
eca80d0e-26d6-4e68-8636-b3c1ad27b0a4	8f706b9d-54ae-4ac7-8ce5-0ed005362d68	2025-04-23	\N	\N	\N	72.530000	\N	GENERATED	2025-11-04 12:45:10.80266+01
851343a6-94c0-4b35-a859-11118cca8fcf	8f706b9d-54ae-4ac7-8ce5-0ed005362d68	2025-04-24	\N	\N	\N	73.110000	\N	GENERATED	2025-11-04 12:45:10.803305+01
a33ea151-b4d9-43d6-933f-f24fb3e5f957	8f706b9d-54ae-4ac7-8ce5-0ed005362d68	2025-04-25	\N	\N	\N	72.950000	\N	GENERATED	2025-11-04 12:45:10.804068+01
22ff4ed1-5532-45c1-b3ef-4f57a8dd192d	8f706b9d-54ae-4ac7-8ce5-0ed005362d68	2025-04-26	\N	\N	\N	72.480000	\N	GENERATED	2025-11-04 12:45:10.804716+01
ac1d02da-89d5-4442-83e4-1a1c2ec941ba	8f706b9d-54ae-4ac7-8ce5-0ed005362d68	2025-04-27	\N	\N	\N	72.970000	\N	GENERATED	2025-11-04 12:45:10.805367+01
789a6a4e-1742-44cb-834c-751816114ac2	8f706b9d-54ae-4ac7-8ce5-0ed005362d68	2025-04-28	\N	\N	\N	72.320000	\N	GENERATED	2025-11-04 12:45:10.806014+01
af539336-ae3a-4bfe-b3a6-2ccc1f2cd71e	8f706b9d-54ae-4ac7-8ce5-0ed005362d68	2025-04-29	\N	\N	\N	73.350000	\N	GENERATED	2025-11-04 12:45:10.806657+01
380d7592-8e92-4119-8bb9-492957961566	8f706b9d-54ae-4ac7-8ce5-0ed005362d68	2025-04-30	\N	\N	\N	72.230000	\N	GENERATED	2025-11-04 12:45:10.807309+01
b7c51fb9-1529-4fd2-9d74-1dabb2d23596	8f706b9d-54ae-4ac7-8ce5-0ed005362d68	2025-05-01	\N	\N	\N	72.110000	\N	GENERATED	2025-11-04 12:45:10.807958+01
e15dac87-006e-46a4-ae59-aa8695bb1aec	8f706b9d-54ae-4ac7-8ce5-0ed005362d68	2025-05-02	\N	\N	\N	72.620000	\N	GENERATED	2025-11-04 12:45:10.808601+01
2c9e9dd4-a9ef-47d0-a740-16eee9fbce2a	8f706b9d-54ae-4ac7-8ce5-0ed005362d68	2025-05-03	\N	\N	\N	73.400000	\N	GENERATED	2025-11-04 12:45:10.809259+01
0fd291c1-1e38-4320-af2f-39aa456112ed	8f706b9d-54ae-4ac7-8ce5-0ed005362d68	2025-05-04	\N	\N	\N	73.090000	\N	GENERATED	2025-11-04 12:45:10.809898+01
45a6f515-5b77-4836-8b7a-d882bab98b04	8f706b9d-54ae-4ac7-8ce5-0ed005362d68	2025-05-05	\N	\N	\N	73.370000	\N	GENERATED	2025-11-04 12:45:10.810545+01
6e65d682-ab7f-48e6-9d82-a219a74500f2	8f706b9d-54ae-4ac7-8ce5-0ed005362d68	2025-05-06	\N	\N	\N	72.810000	\N	GENERATED	2025-11-04 12:45:10.811209+01
aa046359-4b78-4ec5-be6b-c02e56ca15b7	8f706b9d-54ae-4ac7-8ce5-0ed005362d68	2025-05-07	\N	\N	\N	72.560000	\N	GENERATED	2025-11-04 12:45:10.811863+01
a8042195-8ae7-45f9-8f48-d328509445bc	8f706b9d-54ae-4ac7-8ce5-0ed005362d68	2025-05-08	\N	\N	\N	72.340000	\N	GENERATED	2025-11-04 12:45:10.812512+01
a6b45714-2cbf-4316-a551-b8ae485515e3	8f706b9d-54ae-4ac7-8ce5-0ed005362d68	2025-05-09	\N	\N	\N	73.500000	\N	GENERATED	2025-11-04 12:45:10.813238+01
6658b168-7141-4afe-b799-b47871eedd2a	8f706b9d-54ae-4ac7-8ce5-0ed005362d68	2025-05-10	\N	\N	\N	73.440000	\N	GENERATED	2025-11-04 12:45:10.813887+01
a7c38f75-02a2-448f-b9cf-d39f94ccce73	8f706b9d-54ae-4ac7-8ce5-0ed005362d68	2025-05-11	\N	\N	\N	72.210000	\N	GENERATED	2025-11-04 12:45:10.814545+01
0fe6c1de-6ff9-43d7-af8b-70f2152774a0	8f706b9d-54ae-4ac7-8ce5-0ed005362d68	2025-05-12	\N	\N	\N	73.260000	\N	GENERATED	2025-11-04 12:45:10.815571+01
0e45e4da-ebe8-475e-a761-f921d51cbfc6	8f706b9d-54ae-4ac7-8ce5-0ed005362d68	2025-05-13	\N	\N	\N	72.370000	\N	GENERATED	2025-11-04 12:45:10.816289+01
dbfef216-bca3-4000-a9e8-2bed3dfe0f3f	8f706b9d-54ae-4ac7-8ce5-0ed005362d68	2025-05-14	\N	\N	\N	73.160000	\N	GENERATED	2025-11-04 12:45:10.816986+01
32216fdf-bea7-40c0-a27a-c71b28a020e7	8f706b9d-54ae-4ac7-8ce5-0ed005362d68	2025-05-15	\N	\N	\N	72.870000	\N	GENERATED	2025-11-04 12:45:10.817663+01
523d3e48-f2f7-4b0f-881f-742123c91657	8f706b9d-54ae-4ac7-8ce5-0ed005362d68	2025-05-16	\N	\N	\N	73.180000	\N	GENERATED	2025-11-04 12:45:10.818339+01
fa5d3013-2643-444c-bfc5-eec1457d3c4b	8f706b9d-54ae-4ac7-8ce5-0ed005362d68	2025-05-17	\N	\N	\N	73.250000	\N	GENERATED	2025-11-04 12:45:10.818994+01
3e461ccf-2d22-4231-a748-49e1127b18ef	8f706b9d-54ae-4ac7-8ce5-0ed005362d68	2025-05-18	\N	\N	\N	73.220000	\N	GENERATED	2025-11-04 12:45:10.819657+01
f92ad244-5cc3-45da-a48b-09bc9344187f	8f706b9d-54ae-4ac7-8ce5-0ed005362d68	2025-05-19	\N	\N	\N	73.440000	\N	GENERATED	2025-11-04 12:45:10.82031+01
14c1ad0d-60c4-4e53-8d2a-e9a87c10c083	8f706b9d-54ae-4ac7-8ce5-0ed005362d68	2025-05-20	\N	\N	\N	73.660000	\N	GENERATED	2025-11-04 12:45:10.820956+01
762bf8e5-513b-4ef6-9440-b249967442f9	8f706b9d-54ae-4ac7-8ce5-0ed005362d68	2025-05-21	\N	\N	\N	73.210000	\N	GENERATED	2025-11-04 12:45:10.821699+01
535a127e-e360-49dd-98cd-a50ae15a95c4	8f706b9d-54ae-4ac7-8ce5-0ed005362d68	2025-05-22	\N	\N	\N	73.180000	\N	GENERATED	2025-11-04 12:45:10.822364+01
82a7948f-e950-400e-91fa-bf394b3128fd	8f706b9d-54ae-4ac7-8ce5-0ed005362d68	2025-05-23	\N	\N	\N	72.470000	\N	GENERATED	2025-11-04 12:45:10.823009+01
7f664d65-4609-4bb1-80af-0a21b3377e95	8f706b9d-54ae-4ac7-8ce5-0ed005362d68	2025-05-24	\N	\N	\N	73.420000	\N	GENERATED	2025-11-04 12:45:10.82365+01
b3aba282-75cc-4595-af0c-fe55426f79e2	8f706b9d-54ae-4ac7-8ce5-0ed005362d68	2025-05-25	\N	\N	\N	73.790000	\N	GENERATED	2025-11-04 12:45:10.824306+01
18ddd4a6-dd85-4b69-b214-586f5a634651	8f706b9d-54ae-4ac7-8ce5-0ed005362d68	2025-05-26	\N	\N	\N	72.830000	\N	GENERATED	2025-11-04 12:45:10.824957+01
1d9046cf-6ef1-4511-93d5-e80c8348b19d	8f706b9d-54ae-4ac7-8ce5-0ed005362d68	2025-05-27	\N	\N	\N	73.600000	\N	GENERATED	2025-11-04 12:45:10.825596+01
44ba967d-ec9b-47b2-949a-90e45d0c9d50	8f706b9d-54ae-4ac7-8ce5-0ed005362d68	2025-05-28	\N	\N	\N	73.650000	\N	GENERATED	2025-11-04 12:45:10.826247+01
25268985-957d-4813-879c-a76a16e0d14e	8f706b9d-54ae-4ac7-8ce5-0ed005362d68	2025-05-29	\N	\N	\N	73.810000	\N	GENERATED	2025-11-04 12:45:10.826891+01
680bbf8e-b8c5-49ee-bb8b-ca3cd80d9c2d	8f706b9d-54ae-4ac7-8ce5-0ed005362d68	2025-05-30	\N	\N	\N	72.580000	\N	GENERATED	2025-11-04 12:45:10.827543+01
2193514f-54b9-4bd8-aed7-67ba861e77ae	8f706b9d-54ae-4ac7-8ce5-0ed005362d68	2025-05-31	\N	\N	\N	73.110000	\N	GENERATED	2025-11-04 12:45:10.828181+01
c78db619-2b3d-4f14-84b0-b6be33c01912	8f706b9d-54ae-4ac7-8ce5-0ed005362d68	2025-06-01	\N	\N	\N	73.860000	\N	GENERATED	2025-11-04 12:45:10.828846+01
db677a8e-95f1-4f03-9678-337b80cd9e34	8f706b9d-54ae-4ac7-8ce5-0ed005362d68	2025-06-02	\N	\N	\N	72.950000	\N	GENERATED	2025-11-04 12:45:10.829513+01
3d04ebdf-ed7e-4d7a-bb74-3f0a8a98c792	8f706b9d-54ae-4ac7-8ce5-0ed005362d68	2025-06-03	\N	\N	\N	72.880000	\N	GENERATED	2025-11-04 12:45:10.830152+01
f5ca4912-5a5b-4ef1-81d9-cf15e2354a64	8f706b9d-54ae-4ac7-8ce5-0ed005362d68	2025-06-04	\N	\N	\N	73.400000	\N	GENERATED	2025-11-04 12:45:10.831046+01
c3049fc6-1d77-4557-840f-81f156bc7443	8f706b9d-54ae-4ac7-8ce5-0ed005362d68	2025-06-05	\N	\N	\N	73.480000	\N	GENERATED	2025-11-04 12:45:10.831943+01
07c598e0-9678-428e-8373-a8dde7ac4198	8f706b9d-54ae-4ac7-8ce5-0ed005362d68	2025-06-06	\N	\N	\N	73.290000	\N	GENERATED	2025-11-04 12:45:10.832643+01
474e7e46-0660-41b3-99f8-087964ca200c	8f706b9d-54ae-4ac7-8ce5-0ed005362d68	2025-06-07	\N	\N	\N	73.590000	\N	GENERATED	2025-11-04 12:45:10.833476+01
0b4f158f-bd9b-41de-9553-ff31abf975ab	8f706b9d-54ae-4ac7-8ce5-0ed005362d68	2025-06-08	\N	\N	\N	73.580000	\N	GENERATED	2025-11-04 12:45:10.834294+01
be19c68c-0b72-4b04-b99f-dd0f607306d8	8f706b9d-54ae-4ac7-8ce5-0ed005362d68	2025-06-09	\N	\N	\N	73.790000	\N	GENERATED	2025-11-04 12:45:10.834958+01
b6786f0e-05d7-4536-ad5f-ae175b8bdbcf	8f706b9d-54ae-4ac7-8ce5-0ed005362d68	2025-06-10	\N	\N	\N	73.610000	\N	GENERATED	2025-11-04 12:45:10.835631+01
d8d3f4d8-f1db-41a1-8dd2-528fb867927c	8f706b9d-54ae-4ac7-8ce5-0ed005362d68	2025-06-11	\N	\N	\N	73.010000	\N	GENERATED	2025-11-04 12:45:10.836281+01
d3b2dbe5-ac66-421c-b0bc-4a6dd109fda6	8f706b9d-54ae-4ac7-8ce5-0ed005362d68	2025-06-12	\N	\N	\N	73.690000	\N	GENERATED	2025-11-04 12:45:10.837383+01
4aba5f23-473e-4fb1-a401-1adbd77c7369	8f706b9d-54ae-4ac7-8ce5-0ed005362d68	2025-06-13	\N	\N	\N	72.790000	\N	GENERATED	2025-11-04 12:45:10.83812+01
b0d5735c-d2d2-41bc-a69e-9abdcc8ae3b6	8f706b9d-54ae-4ac7-8ce5-0ed005362d68	2025-06-14	\N	\N	\N	73.410000	\N	GENERATED	2025-11-04 12:45:10.838775+01
e1954ecc-bdfe-4c66-9dcf-6bbee486cf37	8f706b9d-54ae-4ac7-8ce5-0ed005362d68	2025-06-15	\N	\N	\N	73.000000	\N	GENERATED	2025-11-04 12:45:10.839443+01
934c6040-d2cf-4b4e-a5e5-4e1f4db8e039	8f706b9d-54ae-4ac7-8ce5-0ed005362d68	2025-06-16	\N	\N	\N	73.340000	\N	GENERATED	2025-11-04 12:45:10.840101+01
dc4168b6-a34e-44eb-9ee0-039d9d27e0d1	8f706b9d-54ae-4ac7-8ce5-0ed005362d68	2025-06-17	\N	\N	\N	73.880000	\N	GENERATED	2025-11-04 12:45:10.840755+01
5a093f98-c5b1-4a97-8d04-842d8e14a2c9	8f706b9d-54ae-4ac7-8ce5-0ed005362d68	2025-06-18	\N	\N	\N	74.120000	\N	GENERATED	2025-11-04 12:45:10.841413+01
c7f188fe-4c16-4f0a-80d1-dbda7505b591	8f706b9d-54ae-4ac7-8ce5-0ed005362d68	2025-06-19	\N	\N	\N	73.720000	\N	GENERATED	2025-11-04 12:45:10.842483+01
140cf8ff-5c21-44b5-b3d5-1ccbd7a07522	8f706b9d-54ae-4ac7-8ce5-0ed005362d68	2025-06-20	\N	\N	\N	73.060000	\N	GENERATED	2025-11-04 12:45:10.84313+01
5485ebdb-3517-46e8-afc6-5a0e128486f7	8f706b9d-54ae-4ac7-8ce5-0ed005362d68	2025-06-21	\N	\N	\N	73.510000	\N	GENERATED	2025-11-04 12:45:10.843808+01
0e48f565-ebec-478b-b2b7-73082fcfe096	8f706b9d-54ae-4ac7-8ce5-0ed005362d68	2025-06-22	\N	\N	\N	73.120000	\N	GENERATED	2025-11-04 12:45:10.844466+01
3d07c018-da0f-4d6a-8842-90cc52a5a417	8f706b9d-54ae-4ac7-8ce5-0ed005362d68	2025-06-23	\N	\N	\N	72.950000	\N	GENERATED	2025-11-04 12:45:10.845118+01
0037ba0d-6d6d-4485-8906-3688a75d1770	8f706b9d-54ae-4ac7-8ce5-0ed005362d68	2025-06-24	\N	\N	\N	73.590000	\N	GENERATED	2025-11-04 12:45:10.846046+01
bd8ff8a9-40e7-4467-bd2f-62c7ddf902e9	8f706b9d-54ae-4ac7-8ce5-0ed005362d68	2025-06-25	\N	\N	\N	73.100000	\N	GENERATED	2025-11-04 12:45:10.84679+01
56a9d5ca-f93f-406a-99cd-141085eab6f3	8f706b9d-54ae-4ac7-8ce5-0ed005362d68	2025-06-26	\N	\N	\N	74.230000	\N	GENERATED	2025-11-04 12:45:10.847463+01
9bc04e7d-2104-4632-8e83-ada4e2bff547	8f706b9d-54ae-4ac7-8ce5-0ed005362d68	2025-06-27	\N	\N	\N	73.630000	\N	GENERATED	2025-11-04 12:45:10.848102+01
bc328ca2-3681-47bb-a0a8-e33e4e7eb18f	8f706b9d-54ae-4ac7-8ce5-0ed005362d68	2025-06-28	\N	\N	\N	74.000000	\N	GENERATED	2025-11-04 12:45:10.848819+01
c96954f2-0779-4ee7-9c49-820b9408ecdf	8f706b9d-54ae-4ac7-8ce5-0ed005362d68	2025-06-29	\N	\N	\N	73.970000	\N	GENERATED	2025-11-04 12:45:10.849479+01
176af245-c6b7-43bf-a176-c55417608412	8f706b9d-54ae-4ac7-8ce5-0ed005362d68	2025-06-30	\N	\N	\N	73.250000	\N	GENERATED	2025-11-04 12:45:10.850127+01
79da2f2d-814f-49fc-86f4-e8b05c619299	8f706b9d-54ae-4ac7-8ce5-0ed005362d68	2025-07-01	\N	\N	\N	73.130000	\N	GENERATED	2025-11-04 12:45:10.850776+01
718ca075-7097-4d58-8a65-e396d494a91a	8f706b9d-54ae-4ac7-8ce5-0ed005362d68	2025-07-02	\N	\N	\N	74.110000	\N	GENERATED	2025-11-04 12:45:10.851429+01
0bac9712-bc50-46a3-b3a5-990356454833	8f706b9d-54ae-4ac7-8ce5-0ed005362d68	2025-07-03	\N	\N	\N	74.170000	\N	GENERATED	2025-11-04 12:45:10.852073+01
d82c6980-a2c0-41be-8b9d-f07992108447	8f706b9d-54ae-4ac7-8ce5-0ed005362d68	2025-07-04	\N	\N	\N	74.090000	\N	GENERATED	2025-11-04 12:45:10.852715+01
15117cff-59a8-400e-b68d-839f80473fdf	8f706b9d-54ae-4ac7-8ce5-0ed005362d68	2025-07-05	\N	\N	\N	74.120000	\N	GENERATED	2025-11-04 12:45:10.853457+01
37f0bfa1-e27e-4528-bd8a-6708aafdfaf0	8f706b9d-54ae-4ac7-8ce5-0ed005362d68	2025-07-06	\N	\N	\N	73.820000	\N	GENERATED	2025-11-04 12:45:10.854094+01
62e8c6da-2a4a-415b-8cd4-fc5eb2ebec75	8f706b9d-54ae-4ac7-8ce5-0ed005362d68	2025-07-07	\N	\N	\N	74.330000	\N	GENERATED	2025-11-04 12:45:10.854737+01
f521fbde-e435-41c2-9cef-dff0fe4842dd	8f706b9d-54ae-4ac7-8ce5-0ed005362d68	2025-07-08	\N	\N	\N	73.130000	\N	GENERATED	2025-11-04 12:45:10.855378+01
5fd38114-bb42-477a-a810-3dcba343fcf5	8f706b9d-54ae-4ac7-8ce5-0ed005362d68	2025-07-09	\N	\N	\N	73.680000	\N	GENERATED	2025-11-04 12:45:10.85603+01
1cfa138c-4c44-4841-a674-2ac2dc2e3f2e	8f706b9d-54ae-4ac7-8ce5-0ed005362d68	2025-07-10	\N	\N	\N	74.040000	\N	GENERATED	2025-11-04 12:45:10.856697+01
60e968bd-fdac-4b86-85c2-9c5a372c552d	8f706b9d-54ae-4ac7-8ce5-0ed005362d68	2025-07-11	\N	\N	\N	74.300000	\N	GENERATED	2025-11-04 12:45:10.857449+01
9b6fad9d-48b0-4909-97bc-e79635607b17	8f706b9d-54ae-4ac7-8ce5-0ed005362d68	2025-07-12	\N	\N	\N	73.150000	\N	GENERATED	2025-11-04 12:45:10.858088+01
ec335392-d7ba-45d9-b3a3-bf1f97c7f107	8f706b9d-54ae-4ac7-8ce5-0ed005362d68	2025-07-13	\N	\N	\N	73.780000	\N	GENERATED	2025-11-04 12:45:10.858739+01
0d83f686-f7e5-44e1-a123-8a8b22b61555	8f706b9d-54ae-4ac7-8ce5-0ed005362d68	2025-07-14	\N	\N	\N	73.200000	\N	GENERATED	2025-11-04 12:45:10.859389+01
9ccb4287-8949-495d-8eb1-dd8fa094c05d	8f706b9d-54ae-4ac7-8ce5-0ed005362d68	2025-07-15	\N	\N	\N	74.370000	\N	GENERATED	2025-11-04 12:45:10.860029+01
d38b89f5-b967-4362-b12b-82dde48ac257	8f706b9d-54ae-4ac7-8ce5-0ed005362d68	2025-07-16	\N	\N	\N	73.510000	\N	GENERATED	2025-11-04 12:45:10.860675+01
b6234a36-9f2e-4fef-9eb4-7b30850b8130	8f706b9d-54ae-4ac7-8ce5-0ed005362d68	2025-07-17	\N	\N	\N	74.430000	\N	GENERATED	2025-11-04 12:45:10.86144+01
dd47566e-9a72-4b4a-bfd3-e3ff78777c39	8f706b9d-54ae-4ac7-8ce5-0ed005362d68	2025-07-18	\N	\N	\N	74.320000	\N	GENERATED	2025-11-04 12:45:10.862141+01
67f04eec-4345-42c6-9e88-918e8ef4165e	8f706b9d-54ae-4ac7-8ce5-0ed005362d68	2025-07-19	\N	\N	\N	74.390000	\N	GENERATED	2025-11-04 12:45:10.862828+01
9b414260-303f-4ed2-b815-88fcf6373480	8f706b9d-54ae-4ac7-8ce5-0ed005362d68	2025-07-20	\N	\N	\N	74.010000	\N	GENERATED	2025-11-04 12:45:10.863509+01
77795507-8456-48e6-bea3-c08331cd8159	8f706b9d-54ae-4ac7-8ce5-0ed005362d68	2025-07-21	\N	\N	\N	74.180000	\N	GENERATED	2025-11-04 12:45:10.86415+01
b09b9460-0789-4063-9539-b88df7c827a2	8f706b9d-54ae-4ac7-8ce5-0ed005362d68	2025-07-22	\N	\N	\N	74.250000	\N	GENERATED	2025-11-04 12:45:10.864896+01
bfe2cff3-7a3a-4485-9917-86ddf03abc31	8f706b9d-54ae-4ac7-8ce5-0ed005362d68	2025-07-23	\N	\N	\N	73.520000	\N	GENERATED	2025-11-04 12:45:10.865559+01
1eb166f4-0159-4c19-b9cb-20dd07eadfe6	8f706b9d-54ae-4ac7-8ce5-0ed005362d68	2025-07-24	\N	\N	\N	74.230000	\N	GENERATED	2025-11-04 12:45:10.866203+01
09622634-e677-490c-a8ad-4bf7ad7e4baf	8f706b9d-54ae-4ac7-8ce5-0ed005362d68	2025-07-25	\N	\N	\N	73.710000	\N	GENERATED	2025-11-04 12:45:10.866878+01
6f0fa502-7812-47c6-9b5b-22f31828c0fb	8f706b9d-54ae-4ac7-8ce5-0ed005362d68	2025-07-26	\N	\N	\N	74.150000	\N	GENERATED	2025-11-04 12:45:10.867637+01
af84cc24-405f-48ad-813d-ccbaa2cb612e	8f706b9d-54ae-4ac7-8ce5-0ed005362d68	2025-07-27	\N	\N	\N	74.670000	\N	GENERATED	2025-11-04 12:45:10.868326+01
aec7aed6-d913-4f6f-8133-6a63eee5be4f	8f706b9d-54ae-4ac7-8ce5-0ed005362d68	2025-07-28	\N	\N	\N	73.700000	\N	GENERATED	2025-11-04 12:45:10.868984+01
191f1099-b8f0-46ef-9b02-02e5f0424399	8f706b9d-54ae-4ac7-8ce5-0ed005362d68	2025-07-29	\N	\N	\N	73.750000	\N	GENERATED	2025-11-04 12:45:10.869651+01
560e2196-13c4-4480-b701-45ebf487e18c	8f706b9d-54ae-4ac7-8ce5-0ed005362d68	2025-07-30	\N	\N	\N	74.120000	\N	GENERATED	2025-11-04 12:45:10.870294+01
1c60567d-b2e2-468f-8bc4-c0f9cfbcb0ea	8f706b9d-54ae-4ac7-8ce5-0ed005362d68	2025-07-31	\N	\N	\N	73.680000	\N	GENERATED	2025-11-04 12:45:10.870942+01
55b58568-47f2-4009-adca-fb94fd5c735f	8f706b9d-54ae-4ac7-8ce5-0ed005362d68	2025-08-01	\N	\N	\N	74.370000	\N	GENERATED	2025-11-04 12:45:10.871603+01
4e4229b1-76e4-4e3c-a37b-45ee416761fa	8f706b9d-54ae-4ac7-8ce5-0ed005362d68	2025-08-02	\N	\N	\N	74.830000	\N	GENERATED	2025-11-04 12:45:10.87225+01
5ed982a6-2e1c-4272-bedc-039969da1077	8f706b9d-54ae-4ac7-8ce5-0ed005362d68	2025-08-03	\N	\N	\N	74.580000	\N	GENERATED	2025-11-04 12:45:10.872908+01
9bc2ef83-335f-4963-96dc-f2d5dc7db7b0	8f706b9d-54ae-4ac7-8ce5-0ed005362d68	2025-08-04	\N	\N	\N	73.880000	\N	GENERATED	2025-11-04 12:45:10.873632+01
ef6a0724-2e4f-4951-93fd-b94479b45b4d	8f706b9d-54ae-4ac7-8ce5-0ed005362d68	2025-08-05	\N	\N	\N	73.530000	\N	GENERATED	2025-11-04 12:45:10.874277+01
725dc839-35c4-40bc-a065-7b15b79bd7c2	8f706b9d-54ae-4ac7-8ce5-0ed005362d68	2025-08-06	\N	\N	\N	74.030000	\N	GENERATED	2025-11-04 12:45:10.874934+01
465f89df-a4f6-4487-994b-1f613db69853	8f706b9d-54ae-4ac7-8ce5-0ed005362d68	2025-08-07	\N	\N	\N	74.370000	\N	GENERATED	2025-11-04 12:45:10.875581+01
7e271e54-a7b9-4a62-be47-d43a7629e7a1	8f706b9d-54ae-4ac7-8ce5-0ed005362d68	2025-08-08	\N	\N	\N	74.240000	\N	GENERATED	2025-11-04 12:45:10.876223+01
a268e4c2-5a17-4f10-8ffe-efa7229ee991	8f706b9d-54ae-4ac7-8ce5-0ed005362d68	2025-08-09	\N	\N	\N	74.490000	\N	GENERATED	2025-11-04 12:45:10.876871+01
ff24dc00-95e6-48f7-8983-6b011ba57693	8f706b9d-54ae-4ac7-8ce5-0ed005362d68	2025-08-10	\N	\N	\N	74.350000	\N	GENERATED	2025-11-04 12:45:10.877776+01
aa960ac0-6bce-4454-9e40-73e550d70ea7	8f706b9d-54ae-4ac7-8ce5-0ed005362d68	2025-08-11	\N	\N	\N	73.770000	\N	GENERATED	2025-11-04 12:45:10.878483+01
566ab83e-e6e5-4a93-bfa6-a05c43657bb5	8f706b9d-54ae-4ac7-8ce5-0ed005362d68	2025-08-12	\N	\N	\N	73.800000	\N	GENERATED	2025-11-04 12:45:10.879138+01
21963569-b62d-4daa-835a-b6c0141ec546	8f706b9d-54ae-4ac7-8ce5-0ed005362d68	2025-08-13	\N	\N	\N	73.790000	\N	GENERATED	2025-11-04 12:45:10.879835+01
f4041d96-d024-4d48-a803-829268888913	8f706b9d-54ae-4ac7-8ce5-0ed005362d68	2025-08-14	\N	\N	\N	74.650000	\N	GENERATED	2025-11-04 12:45:10.880505+01
3fb1465e-9de7-45e4-b21a-25f9720b40c4	8f706b9d-54ae-4ac7-8ce5-0ed005362d68	2025-08-15	\N	\N	\N	74.750000	\N	GENERATED	2025-11-04 12:45:10.881165+01
2d12f111-44a6-449c-815c-f7fdfa1e3f94	8f706b9d-54ae-4ac7-8ce5-0ed005362d68	2025-08-16	\N	\N	\N	75.020000	\N	GENERATED	2025-11-04 12:45:10.881835+01
764f776e-83fe-44fa-b5b6-a798508f77f7	8f706b9d-54ae-4ac7-8ce5-0ed005362d68	2025-08-17	\N	\N	\N	73.850000	\N	GENERATED	2025-11-04 12:45:10.882478+01
dece832d-6796-472d-9d6e-cb088077113e	8f706b9d-54ae-4ac7-8ce5-0ed005362d68	2025-08-18	\N	\N	\N	74.920000	\N	GENERATED	2025-11-04 12:45:10.883115+01
2bfb3351-3467-410a-be44-13a115b75727	8f706b9d-54ae-4ac7-8ce5-0ed005362d68	2025-08-19	\N	\N	\N	73.820000	\N	GENERATED	2025-11-04 12:45:10.883782+01
ba5a6a69-9530-4277-894c-e438a742a81b	8f706b9d-54ae-4ac7-8ce5-0ed005362d68	2025-08-20	\N	\N	\N	73.940000	\N	GENERATED	2025-11-04 12:45:10.884459+01
ff36e282-2f5b-467a-af94-4aafb02b28c4	8f706b9d-54ae-4ac7-8ce5-0ed005362d68	2025-08-21	\N	\N	\N	73.780000	\N	GENERATED	2025-11-04 12:45:10.885111+01
f00783bb-abfd-47a3-b313-cf9d2b9556d3	8f706b9d-54ae-4ac7-8ce5-0ed005362d68	2025-08-22	\N	\N	\N	74.320000	\N	GENERATED	2025-11-04 12:45:10.885762+01
ab9007df-2782-4c9f-b39a-327cc9760327	8f706b9d-54ae-4ac7-8ce5-0ed005362d68	2025-08-23	\N	\N	\N	74.580000	\N	GENERATED	2025-11-04 12:45:10.886418+01
7957393e-aa01-41ec-8025-768cfd48a5fa	8f706b9d-54ae-4ac7-8ce5-0ed005362d68	2025-08-24	\N	\N	\N	75.040000	\N	GENERATED	2025-11-04 12:45:10.887059+01
ad2b1814-760d-496f-9ad2-b1a11edbc868	8f706b9d-54ae-4ac7-8ce5-0ed005362d68	2025-08-25	\N	\N	\N	74.600000	\N	GENERATED	2025-11-04 12:45:10.887715+01
f9c0dfd2-324b-4e4f-8e54-a0f9d7537c04	8f706b9d-54ae-4ac7-8ce5-0ed005362d68	2025-08-26	\N	\N	\N	74.500000	\N	GENERATED	2025-11-04 12:45:10.888401+01
d3b431b3-f9d4-46f5-bb54-691114673fd2	8f706b9d-54ae-4ac7-8ce5-0ed005362d68	2025-08-27	\N	\N	\N	74.950000	\N	GENERATED	2025-11-04 12:45:10.889058+01
ca6be687-7901-45a0-993d-623bc8466115	8f706b9d-54ae-4ac7-8ce5-0ed005362d68	2025-08-28	\N	\N	\N	74.000000	\N	GENERATED	2025-11-04 12:45:10.889714+01
4187a2d6-f82f-4aca-99d9-631dc732c40f	8f706b9d-54ae-4ac7-8ce5-0ed005362d68	2025-08-29	\N	\N	\N	74.450000	\N	GENERATED	2025-11-04 12:45:10.890368+01
e3d97e35-ac99-4bf8-94ec-649c87284986	8f706b9d-54ae-4ac7-8ce5-0ed005362d68	2025-08-30	\N	\N	\N	74.370000	\N	GENERATED	2025-11-04 12:45:10.891008+01
31bc1a7f-7189-417a-b289-9229ca89d64d	8f706b9d-54ae-4ac7-8ce5-0ed005362d68	2025-08-31	\N	\N	\N	74.910000	\N	GENERATED	2025-11-04 12:45:10.891668+01
061533cf-b8e1-402f-bd37-b3d2cf8ea3ac	8f706b9d-54ae-4ac7-8ce5-0ed005362d68	2025-09-01	\N	\N	\N	74.010000	\N	GENERATED	2025-11-04 12:45:10.892386+01
8a062f2b-2700-4a6a-bb57-3ebd41c4cb3d	8f706b9d-54ae-4ac7-8ce5-0ed005362d68	2025-09-02	\N	\N	\N	75.310000	\N	GENERATED	2025-11-04 12:45:10.893149+01
f6ccff00-fd18-4855-ab88-9719002f068b	8f706b9d-54ae-4ac7-8ce5-0ed005362d68	2025-09-03	\N	\N	\N	75.010000	\N	GENERATED	2025-11-04 12:45:10.893829+01
131dc010-ac4f-46b8-8bbd-9f4705b80999	8f706b9d-54ae-4ac7-8ce5-0ed005362d68	2025-09-04	\N	\N	\N	74.800000	\N	GENERATED	2025-11-04 12:45:10.894522+01
9c7e4c11-54a0-4a53-b703-21773d98e3e3	8f706b9d-54ae-4ac7-8ce5-0ed005362d68	2025-09-05	\N	\N	\N	74.330000	\N	GENERATED	2025-11-04 12:45:10.89517+01
84c78bdf-58e6-4910-87c7-13931a86ad55	8f706b9d-54ae-4ac7-8ce5-0ed005362d68	2025-09-06	\N	\N	\N	74.240000	\N	GENERATED	2025-11-04 12:45:10.895826+01
af41c06a-3594-416e-99aa-245251416203	8f706b9d-54ae-4ac7-8ce5-0ed005362d68	2025-09-07	\N	\N	\N	74.940000	\N	GENERATED	2025-11-04 12:45:10.896504+01
fc7a70e1-ff54-442e-87ef-77e56e14ef21	8f706b9d-54ae-4ac7-8ce5-0ed005362d68	2025-09-08	\N	\N	\N	75.000000	\N	GENERATED	2025-11-04 12:45:10.897151+01
e124730e-0bb5-48a6-8a53-65f29ab586ce	8f706b9d-54ae-4ac7-8ce5-0ed005362d68	2025-09-09	\N	\N	\N	74.890000	\N	GENERATED	2025-11-04 12:45:10.8978+01
37b7acd1-2bef-43a1-adec-9618deec7604	8f706b9d-54ae-4ac7-8ce5-0ed005362d68	2025-09-10	\N	\N	\N	74.480000	\N	GENERATED	2025-11-04 12:45:10.898461+01
d1658d63-3a8b-4deb-8c17-08ea5288a400	8f706b9d-54ae-4ac7-8ce5-0ed005362d68	2025-09-11	\N	\N	\N	74.150000	\N	GENERATED	2025-11-04 12:45:10.899097+01
d113ed3e-c604-4d55-a166-a380e8f423ad	8f706b9d-54ae-4ac7-8ce5-0ed005362d68	2025-09-12	\N	\N	\N	74.920000	\N	GENERATED	2025-11-04 12:45:10.899748+01
afed7394-5805-404e-a514-e86669ba2599	8f706b9d-54ae-4ac7-8ce5-0ed005362d68	2025-09-13	\N	\N	\N	74.690000	\N	GENERATED	2025-11-04 12:45:10.90039+01
cb3d39bb-596d-4f02-b673-71acd64fee90	8f706b9d-54ae-4ac7-8ce5-0ed005362d68	2025-09-14	\N	\N	\N	74.190000	\N	GENERATED	2025-11-04 12:45:10.901034+01
81a425af-2a18-4240-82ed-0563eb3e75c5	8f706b9d-54ae-4ac7-8ce5-0ed005362d68	2025-09-15	\N	\N	\N	74.920000	\N	GENERATED	2025-11-04 12:45:10.901687+01
d767808a-e032-415c-8f5a-b207c8c8e6bd	8f706b9d-54ae-4ac7-8ce5-0ed005362d68	2025-09-16	\N	\N	\N	75.240000	\N	GENERATED	2025-11-04 12:45:10.902327+01
fe3e73a9-47b9-4a80-854e-809af318e2e1	8f706b9d-54ae-4ac7-8ce5-0ed005362d68	2025-09-17	\N	\N	\N	74.420000	\N	GENERATED	2025-11-04 12:45:10.902974+01
ecdd2179-c32d-4a86-abbe-20595b9b20b1	8f706b9d-54ae-4ac7-8ce5-0ed005362d68	2025-09-18	\N	\N	\N	74.940000	\N	GENERATED	2025-11-04 12:45:10.903628+01
4143dd7c-92b2-4795-b17c-f59a1f85bae6	8f706b9d-54ae-4ac7-8ce5-0ed005362d68	2025-09-19	\N	\N	\N	75.310000	\N	GENERATED	2025-11-04 12:45:10.904274+01
ed194d54-2e0d-4f50-b1ff-f35cfb56fce2	8f706b9d-54ae-4ac7-8ce5-0ed005362d68	2025-09-20	\N	\N	\N	75.390000	\N	GENERATED	2025-11-04 12:45:10.904914+01
5ccb0d53-e4ee-453a-82ce-df4cdc3bf0cb	8f706b9d-54ae-4ac7-8ce5-0ed005362d68	2025-09-21	\N	\N	\N	74.670000	\N	GENERATED	2025-11-04 12:45:10.905552+01
95588275-b183-4340-bf7c-be2f70535085	8f706b9d-54ae-4ac7-8ce5-0ed005362d68	2025-09-22	\N	\N	\N	74.350000	\N	GENERATED	2025-11-04 12:45:10.906195+01
9c776c82-dd76-49e8-8692-e861ae27afc1	8f706b9d-54ae-4ac7-8ce5-0ed005362d68	2025-09-23	\N	\N	\N	74.890000	\N	GENERATED	2025-11-04 12:45:10.906834+01
1bb7b0e6-a36c-4837-a68b-e0fe3f91fb42	8f706b9d-54ae-4ac7-8ce5-0ed005362d68	2025-09-24	\N	\N	\N	75.270000	\N	GENERATED	2025-11-04 12:45:10.907504+01
54ab04ed-10b0-43e9-806f-efb1bd03a1dd	8f706b9d-54ae-4ac7-8ce5-0ed005362d68	2025-09-25	\N	\N	\N	75.000000	\N	GENERATED	2025-11-04 12:45:10.908144+01
0b9cecdb-9b43-405a-a9b5-6e9e197c545f	8f706b9d-54ae-4ac7-8ce5-0ed005362d68	2025-09-26	\N	\N	\N	74.880000	\N	GENERATED	2025-11-04 12:45:10.909093+01
d44f9c48-7c88-4924-b2d2-695422b92bec	8f706b9d-54ae-4ac7-8ce5-0ed005362d68	2025-09-27	\N	\N	\N	75.040000	\N	GENERATED	2025-11-04 12:45:10.91001+01
1c4b03cd-655e-4012-b411-b1573c3b9aa5	8f706b9d-54ae-4ac7-8ce5-0ed005362d68	2025-09-28	\N	\N	\N	75.090000	\N	GENERATED	2025-11-04 12:45:10.910724+01
66fd823f-0151-4c43-bda5-255028da5973	8f706b9d-54ae-4ac7-8ce5-0ed005362d68	2025-09-29	\N	\N	\N	74.840000	\N	GENERATED	2025-11-04 12:45:10.911407+01
c9d4a8ea-eb7f-4481-96ca-1620e306172d	8f706b9d-54ae-4ac7-8ce5-0ed005362d68	2025-09-30	\N	\N	\N	75.310000	\N	GENERATED	2025-11-04 12:45:10.912068+01
61df56da-e8f5-4dab-b2d6-a72c3027e3c7	8f706b9d-54ae-4ac7-8ce5-0ed005362d68	2025-10-01	\N	\N	\N	75.400000	\N	GENERATED	2025-11-04 12:45:10.912806+01
83ca4b47-0c59-46d1-83e4-4ca5bf99cc83	8f706b9d-54ae-4ac7-8ce5-0ed005362d68	2025-10-02	\N	\N	\N	74.890000	\N	GENERATED	2025-11-04 12:45:10.913929+01
17d7ad08-19b4-49c3-9a6a-5139f4ed0027	8f706b9d-54ae-4ac7-8ce5-0ed005362d68	2025-10-03	\N	\N	\N	75.670000	\N	GENERATED	2025-11-04 12:45:10.914771+01
d0e78d4b-1288-408b-84d4-b7114339bd72	8f706b9d-54ae-4ac7-8ce5-0ed005362d68	2025-10-04	\N	\N	\N	75.170000	\N	GENERATED	2025-11-04 12:45:10.915565+01
f6ed2d9c-62cb-41ee-9ab1-048fc3cfac50	8f706b9d-54ae-4ac7-8ce5-0ed005362d68	2025-10-05	\N	\N	\N	75.020000	\N	GENERATED	2025-11-04 12:45:10.916341+01
13e6acce-ef72-4117-89f4-d856d4f955f1	8f706b9d-54ae-4ac7-8ce5-0ed005362d68	2025-10-06	\N	\N	\N	74.740000	\N	GENERATED	2025-11-04 12:45:10.916999+01
2929b6b4-9650-4f04-9e13-4a1b85432167	8f706b9d-54ae-4ac7-8ce5-0ed005362d68	2025-10-07	\N	\N	\N	75.070000	\N	GENERATED	2025-11-04 12:45:10.917655+01
17441c1e-c829-4066-be53-e12689910945	8f706b9d-54ae-4ac7-8ce5-0ed005362d68	2025-10-08	\N	\N	\N	74.620000	\N	GENERATED	2025-11-04 12:45:10.918311+01
312f6318-6ada-4be5-bed1-b8c5818110bb	8f706b9d-54ae-4ac7-8ce5-0ed005362d68	2025-10-09	\N	\N	\N	74.870000	\N	GENERATED	2025-11-04 12:45:10.918953+01
31d52a54-43a5-4a81-835d-26a96a82adfc	8f706b9d-54ae-4ac7-8ce5-0ed005362d68	2025-10-10	\N	\N	\N	74.620000	\N	GENERATED	2025-11-04 12:45:10.919603+01
ae6cd9be-1858-4127-9579-4f180f3816c9	8f706b9d-54ae-4ac7-8ce5-0ed005362d68	2025-10-11	\N	\N	\N	74.970000	\N	GENERATED	2025-11-04 12:45:10.920252+01
bc6a89b3-fb66-412d-9f9a-b30cf5c0f85c	8f706b9d-54ae-4ac7-8ce5-0ed005362d68	2025-10-12	\N	\N	\N	74.790000	\N	GENERATED	2025-11-04 12:45:10.920902+01
dd529e14-aa53-49f6-b33c-880a8dcb1488	8f706b9d-54ae-4ac7-8ce5-0ed005362d68	2025-10-13	\N	\N	\N	75.470000	\N	GENERATED	2025-11-04 12:45:10.921547+01
d0f07276-2a09-4a6c-a4ce-a0252de49774	8f706b9d-54ae-4ac7-8ce5-0ed005362d68	2025-10-14	\N	\N	\N	74.810000	\N	GENERATED	2025-11-04 12:45:10.922355+01
1987f30b-51d9-4897-a5cf-864cf4ccced4	8f706b9d-54ae-4ac7-8ce5-0ed005362d68	2025-10-15	\N	\N	\N	74.900000	\N	GENERATED	2025-11-04 12:45:10.923002+01
dbe9d13f-9fd3-407f-b238-810f86c8c477	8f706b9d-54ae-4ac7-8ce5-0ed005362d68	2025-10-16	\N	\N	\N	75.070000	\N	GENERATED	2025-11-04 12:45:10.923974+01
895de24c-b3f3-4b69-90a3-466e96696e76	8f706b9d-54ae-4ac7-8ce5-0ed005362d68	2025-10-17	\N	\N	\N	75.240000	\N	GENERATED	2025-11-04 12:45:10.924975+01
39bb5ce4-d3b5-4c5a-a817-d2d23f25002b	8f706b9d-54ae-4ac7-8ce5-0ed005362d68	2025-10-18	\N	\N	\N	75.790000	\N	GENERATED	2025-11-04 12:45:10.925657+01
02a3e36d-ab0a-4185-aa86-df1167fc5e6b	8f706b9d-54ae-4ac7-8ce5-0ed005362d68	2025-10-19	\N	\N	\N	76.050000	\N	GENERATED	2025-11-04 12:45:10.926308+01
50dfd7c3-4661-48bf-ba09-6ec45f73cce1	8f706b9d-54ae-4ac7-8ce5-0ed005362d68	2025-10-20	\N	\N	\N	75.590000	\N	GENERATED	2025-11-04 12:45:10.926973+01
fe5f5d70-3da7-4e6a-b097-002db66e8681	8f706b9d-54ae-4ac7-8ce5-0ed005362d68	2025-10-21	\N	\N	\N	75.340000	\N	GENERATED	2025-11-04 12:45:10.92763+01
2374e967-e21b-46bb-8c02-95952590657e	8f706b9d-54ae-4ac7-8ce5-0ed005362d68	2025-10-22	\N	\N	\N	75.080000	\N	GENERATED	2025-11-04 12:45:10.928442+01
e05cdd10-3b1b-4bf3-b7ca-b1984388992c	8f706b9d-54ae-4ac7-8ce5-0ed005362d68	2025-10-23	\N	\N	\N	75.650000	\N	GENERATED	2025-11-04 12:45:10.929141+01
0302913a-6194-4e53-97ed-552d20f84b02	8f706b9d-54ae-4ac7-8ce5-0ed005362d68	2025-10-24	\N	\N	\N	75.680000	\N	GENERATED	2025-11-04 12:45:10.929891+01
fab396ea-5f4e-4047-8915-ea39d9dfecc1	8f706b9d-54ae-4ac7-8ce5-0ed005362d68	2025-10-25	\N	\N	\N	75.430000	\N	GENERATED	2025-11-04 12:45:10.930582+01
8b4153dc-d62f-444a-815c-94fb69f52513	8f706b9d-54ae-4ac7-8ce5-0ed005362d68	2025-10-26	\N	\N	\N	75.070000	\N	GENERATED	2025-11-04 12:45:10.931226+01
f12c7ace-d753-4aa4-abc6-c49bbf2b3c38	8f706b9d-54ae-4ac7-8ce5-0ed005362d68	2025-10-27	\N	\N	\N	75.340000	\N	GENERATED	2025-11-04 12:45:10.93187+01
f9078a1c-1046-4316-b13a-dfb3c4378a67	8f706b9d-54ae-4ac7-8ce5-0ed005362d68	2025-10-28	\N	\N	\N	75.150000	\N	GENERATED	2025-11-04 12:45:10.932513+01
f37c6571-d4c7-4a6c-a8d8-27af7baa8f84	8f706b9d-54ae-4ac7-8ce5-0ed005362d68	2025-10-29	\N	\N	\N	75.630000	\N	GENERATED	2025-11-04 12:45:10.933241+01
7cf12f07-593f-483b-844d-d6b9a8152f8a	8f706b9d-54ae-4ac7-8ce5-0ed005362d68	2025-10-30	\N	\N	\N	75.010000	\N	GENERATED	2025-11-04 12:45:10.9339+01
cc59a2bc-36ae-464b-b6af-c23885a2a13f	8f706b9d-54ae-4ac7-8ce5-0ed005362d68	2025-10-31	\N	\N	\N	76.000000	\N	GENERATED	2025-11-04 12:45:10.934797+01
aabef032-4e70-4b81-a59d-57b5ab0e7a19	8f706b9d-54ae-4ac7-8ce5-0ed005362d68	2025-11-01	\N	\N	\N	75.530000	\N	GENERATED	2025-11-04 12:45:10.935987+01
cefbfa8e-9c13-4486-ba63-78598c95dc26	8f706b9d-54ae-4ac7-8ce5-0ed005362d68	2025-11-02	\N	\N	\N	75.360000	\N	GENERATED	2025-11-04 12:45:10.936784+01
65e418e4-bb2e-485d-8e16-288dbf9c2684	8f706b9d-54ae-4ac7-8ce5-0ed005362d68	2025-11-03	\N	\N	\N	75.030000	\N	GENERATED	2025-11-04 12:45:10.937513+01
3ace81a4-27c3-4e73-98bc-72fed2f797f1	6e5b011b-1658-420d-886d-4f0802372d0b	2024-11-04	\N	\N	\N	90.230000	\N	GENERATED	2025-11-04 12:45:10.938786+01
4a2d1131-08a0-422a-86ac-d79d70643b7c	6e5b011b-1658-420d-886d-4f0802372d0b	2024-11-05	\N	\N	\N	90.450000	\N	GENERATED	2025-11-04 12:45:10.939592+01
9a3dcc00-baef-4419-b758-a985ccf219a5	6e5b011b-1658-420d-886d-4f0802372d0b	2024-11-06	\N	\N	\N	90.540000	\N	GENERATED	2025-11-04 12:45:10.940275+01
ea594935-31a5-45ce-a344-5d44579b6401	6e5b011b-1658-420d-886d-4f0802372d0b	2024-11-07	\N	\N	\N	90.770000	\N	GENERATED	2025-11-04 12:45:10.941013+01
a6c1b0f1-8372-449e-9329-133802d5a19f	6e5b011b-1658-420d-886d-4f0802372d0b	2024-11-08	\N	\N	\N	90.410000	\N	GENERATED	2025-11-04 12:45:10.94192+01
092b3941-ab42-44ce-ab53-a04423c5e911	6e5b011b-1658-420d-886d-4f0802372d0b	2024-11-09	\N	\N	\N	90.160000	\N	GENERATED	2025-11-04 12:45:10.942672+01
4aa330b7-6834-4197-b781-add85d7d25e2	6e5b011b-1658-420d-886d-4f0802372d0b	2024-11-10	\N	\N	\N	89.590000	\N	GENERATED	2025-11-04 12:45:10.94343+01
8576be4b-ffae-4fc6-9d99-55a55a596d58	6e5b011b-1658-420d-886d-4f0802372d0b	2024-11-11	\N	\N	\N	90.770000	\N	GENERATED	2025-11-04 12:45:10.944128+01
b2fd243b-d949-453d-ba86-2c3f41085d62	6e5b011b-1658-420d-886d-4f0802372d0b	2024-11-12	\N	\N	\N	90.300000	\N	GENERATED	2025-11-04 12:45:10.944825+01
b0654ea8-3246-4e17-9f62-f71ac71b914c	6e5b011b-1658-420d-886d-4f0802372d0b	2024-11-13	\N	\N	\N	89.640000	\N	GENERATED	2025-11-04 12:45:10.945492+01
e44aba02-35b4-4d27-9835-604bb97b8836	6e5b011b-1658-420d-886d-4f0802372d0b	2024-11-14	\N	\N	\N	90.630000	\N	GENERATED	2025-11-04 12:45:10.94614+01
0447985c-8265-4dba-82e0-b7dd324389d2	6e5b011b-1658-420d-886d-4f0802372d0b	2024-11-15	\N	\N	\N	89.850000	\N	GENERATED	2025-11-04 12:45:10.946798+01
cddbd93c-422c-4a51-b293-89e5efb98326	6e5b011b-1658-420d-886d-4f0802372d0b	2024-11-16	\N	\N	\N	89.990000	\N	GENERATED	2025-11-04 12:45:10.947453+01
9d34d3b4-9d25-4aea-aa22-b0bea89dc371	6e5b011b-1658-420d-886d-4f0802372d0b	2024-11-17	\N	\N	\N	89.590000	\N	GENERATED	2025-11-04 12:45:10.948095+01
c974b024-33f1-4399-a258-99787c65d2da	6e5b011b-1658-420d-886d-4f0802372d0b	2024-11-18	\N	\N	\N	90.050000	\N	GENERATED	2025-11-04 12:45:10.94876+01
3b3c9d1b-9a0a-41a9-903b-6a3ae6c83b4a	6e5b011b-1658-420d-886d-4f0802372d0b	2024-11-19	\N	\N	\N	90.020000	\N	GENERATED	2025-11-04 12:45:10.949423+01
df377823-95a5-40bf-87d7-efc7af2583a4	6e5b011b-1658-420d-886d-4f0802372d0b	2024-11-20	\N	\N	\N	90.570000	\N	GENERATED	2025-11-04 12:45:10.950076+01
4933abd2-52ef-4870-ac8e-dd0ecb23d59f	6e5b011b-1658-420d-886d-4f0802372d0b	2024-11-21	\N	\N	\N	91.180000	\N	GENERATED	2025-11-04 12:45:10.950717+01
863ebde5-f328-44b1-881a-02e6bcedab25	6e5b011b-1658-420d-886d-4f0802372d0b	2024-11-22	\N	\N	\N	91.110000	\N	GENERATED	2025-11-04 12:45:10.951363+01
24b66f17-d207-46d5-8a18-e1c513e4be79	6e5b011b-1658-420d-886d-4f0802372d0b	2024-11-23	\N	\N	\N	91.270000	\N	GENERATED	2025-11-04 12:45:10.952007+01
8b867673-63ca-4e93-89f4-c425e15ea904	6e5b011b-1658-420d-886d-4f0802372d0b	2024-11-24	\N	\N	\N	90.020000	\N	GENERATED	2025-11-04 12:45:10.952682+01
f9fa7db0-cf4b-4f65-9100-39958697096d	6e5b011b-1658-420d-886d-4f0802372d0b	2024-11-25	\N	\N	\N	89.990000	\N	GENERATED	2025-11-04 12:45:10.9534+01
76df1294-a0bc-4221-82dc-0e385237524a	6e5b011b-1658-420d-886d-4f0802372d0b	2024-11-26	\N	\N	\N	90.820000	\N	GENERATED	2025-11-04 12:45:10.954039+01
67dbfd79-a6fe-4db3-96e9-e22f02b4b368	6e5b011b-1658-420d-886d-4f0802372d0b	2024-11-27	\N	\N	\N	90.030000	\N	GENERATED	2025-11-04 12:45:10.954801+01
7c1515e3-9653-418f-812d-780c356b0aeb	6e5b011b-1658-420d-886d-4f0802372d0b	2024-11-28	\N	\N	\N	90.560000	\N	GENERATED	2025-11-04 12:45:10.955468+01
59fb0c8e-cf6e-403a-b964-306d8e48ab3c	6e5b011b-1658-420d-886d-4f0802372d0b	2024-11-29	\N	\N	\N	89.680000	\N	GENERATED	2025-11-04 12:45:10.956131+01
831369ab-5983-4aa4-bedb-a8624f6b70c9	6e5b011b-1658-420d-886d-4f0802372d0b	2024-11-30	\N	\N	\N	90.310000	\N	GENERATED	2025-11-04 12:45:10.956795+01
4cd71018-975c-4fc4-88f3-5e688ec7ab24	6e5b011b-1658-420d-886d-4f0802372d0b	2024-12-01	\N	\N	\N	90.130000	\N	GENERATED	2025-11-04 12:45:10.957465+01
abf9d4c6-1cc6-4223-bc15-9623e90fe9db	6e5b011b-1658-420d-886d-4f0802372d0b	2024-12-02	\N	\N	\N	90.550000	\N	GENERATED	2025-11-04 12:45:10.958102+01
29414fdc-7ecb-4ecd-89ce-81496a59e45b	6e5b011b-1658-420d-886d-4f0802372d0b	2024-12-03	\N	\N	\N	91.120000	\N	GENERATED	2025-11-04 12:45:10.958784+01
814b3a2d-4834-41b6-8d57-466a91657965	6e5b011b-1658-420d-886d-4f0802372d0b	2024-12-04	\N	\N	\N	90.390000	\N	GENERATED	2025-11-04 12:45:10.959441+01
722a410e-a3d2-4321-b6b9-66c2c1228cee	6e5b011b-1658-420d-886d-4f0802372d0b	2024-12-05	\N	\N	\N	90.910000	\N	GENERATED	2025-11-04 12:45:10.960084+01
90df87cf-0588-43ce-9e6a-9142183bbba6	6e5b011b-1658-420d-886d-4f0802372d0b	2024-12-06	\N	\N	\N	89.840000	\N	GENERATED	2025-11-04 12:45:10.960732+01
40cb10b1-d136-4ac4-9549-7c44e6faf438	6e5b011b-1658-420d-886d-4f0802372d0b	2024-12-07	\N	\N	\N	89.920000	\N	GENERATED	2025-11-04 12:45:10.961372+01
b97d45c1-e4f1-4717-938d-984e4f18452e	6e5b011b-1658-420d-886d-4f0802372d0b	2024-12-08	\N	\N	\N	90.520000	\N	GENERATED	2025-11-04 12:45:10.962017+01
08275f66-940f-4e42-8969-33f1853df836	6e5b011b-1658-420d-886d-4f0802372d0b	2024-12-09	\N	\N	\N	90.360000	\N	GENERATED	2025-11-04 12:45:10.96267+01
01fd31c6-00c4-4a47-8b9c-7ae283b12209	6e5b011b-1658-420d-886d-4f0802372d0b	2024-12-10	\N	\N	\N	91.090000	\N	GENERATED	2025-11-04 12:45:10.963305+01
829b5a2c-9786-4065-a8e9-6833406d395f	6e5b011b-1658-420d-886d-4f0802372d0b	2024-12-11	\N	\N	\N	90.490000	\N	GENERATED	2025-11-04 12:45:10.963968+01
c7a66310-d9e2-42f6-a1ca-1378103deb6e	6e5b011b-1658-420d-886d-4f0802372d0b	2024-12-12	\N	\N	\N	90.200000	\N	GENERATED	2025-11-04 12:45:10.964633+01
747ed709-2329-4e2a-9deb-da4ad343c016	6e5b011b-1658-420d-886d-4f0802372d0b	2024-12-13	\N	\N	\N	90.820000	\N	GENERATED	2025-11-04 12:45:10.965275+01
c52ad417-261c-4c94-886c-04467aa12a70	6e5b011b-1658-420d-886d-4f0802372d0b	2024-12-14	\N	\N	\N	91.400000	\N	GENERATED	2025-11-04 12:45:10.965909+01
d1a9d1ff-c1c4-48ec-a0a5-748a48309ee8	6e5b011b-1658-420d-886d-4f0802372d0b	2024-12-15	\N	\N	\N	89.910000	\N	GENERATED	2025-11-04 12:45:10.966558+01
7f8533f2-daf9-468e-91ae-467fad4fdcb9	6e5b011b-1658-420d-886d-4f0802372d0b	2024-12-16	\N	\N	\N	91.020000	\N	GENERATED	2025-11-04 12:45:10.967217+01
e31651bc-0c34-4b44-8799-aa5c39a8c61b	6e5b011b-1658-420d-886d-4f0802372d0b	2024-12-17	\N	\N	\N	91.740000	\N	GENERATED	2025-11-04 12:45:10.967853+01
70dea47c-92c7-45cc-8497-acd3e7ffaacf	6e5b011b-1658-420d-886d-4f0802372d0b	2024-12-18	\N	\N	\N	91.620000	\N	GENERATED	2025-11-04 12:45:10.968506+01
55350c27-a785-445b-9c22-96efc3eec1e2	6e5b011b-1658-420d-886d-4f0802372d0b	2024-12-19	\N	\N	\N	90.610000	\N	GENERATED	2025-11-04 12:45:10.969144+01
fd1fc0b3-73e7-471d-abc6-f7842f32cf49	6e5b011b-1658-420d-886d-4f0802372d0b	2024-12-20	\N	\N	\N	90.240000	\N	GENERATED	2025-11-04 12:45:10.969812+01
4b35be8f-71d6-4236-87ca-7868df40d7a2	6e5b011b-1658-420d-886d-4f0802372d0b	2024-12-21	\N	\N	\N	90.210000	\N	GENERATED	2025-11-04 12:45:10.970633+01
83ad30f0-1a11-44fe-8741-d28278e9d364	6e5b011b-1658-420d-886d-4f0802372d0b	2024-12-22	\N	\N	\N	90.720000	\N	GENERATED	2025-11-04 12:45:10.97171+01
30db4bd0-ae51-41c7-822e-18e299681e6d	6e5b011b-1658-420d-886d-4f0802372d0b	2024-12-23	\N	\N	\N	91.550000	\N	GENERATED	2025-11-04 12:45:10.972455+01
f44186d5-7f86-49cf-844e-9f9016a783ee	6e5b011b-1658-420d-886d-4f0802372d0b	2024-12-24	\N	\N	\N	91.670000	\N	GENERATED	2025-11-04 12:45:10.973096+01
8d5bbf96-0931-4001-8ed4-2696fe128dfe	6e5b011b-1658-420d-886d-4f0802372d0b	2024-12-25	\N	\N	\N	91.620000	\N	GENERATED	2025-11-04 12:45:10.97383+01
12108c40-a18d-420e-aa27-09b51671bfaf	6e5b011b-1658-420d-886d-4f0802372d0b	2024-12-26	\N	\N	\N	90.990000	\N	GENERATED	2025-11-04 12:45:10.974498+01
ae5f4279-4dd8-4d9e-9aed-46eedd75dbf1	6e5b011b-1658-420d-886d-4f0802372d0b	2024-12-27	\N	\N	\N	91.060000	\N	GENERATED	2025-11-04 12:45:10.975143+01
141d6585-dfa5-4605-8967-890f8ed49517	6e5b011b-1658-420d-886d-4f0802372d0b	2024-12-28	\N	\N	\N	91.670000	\N	GENERATED	2025-11-04 12:45:10.975798+01
3188a30b-48c1-4783-9cf8-253e7e9fb617	6e5b011b-1658-420d-886d-4f0802372d0b	2024-12-29	\N	\N	\N	91.290000	\N	GENERATED	2025-11-04 12:45:10.976454+01
6efc8f99-c422-4f71-9ae9-0fd237d06c3c	6e5b011b-1658-420d-886d-4f0802372d0b	2024-12-30	\N	\N	\N	91.350000	\N	GENERATED	2025-11-04 12:45:10.977105+01
d5505d08-0e9d-4848-9afc-d725f5401bb6	6e5b011b-1658-420d-886d-4f0802372d0b	2024-12-31	\N	\N	\N	91.390000	\N	GENERATED	2025-11-04 12:45:10.977756+01
a009a07d-ecf3-4df9-a26c-2a33d9e9e5d2	6e5b011b-1658-420d-886d-4f0802372d0b	2025-01-01	\N	\N	\N	91.610000	\N	GENERATED	2025-11-04 12:45:10.978389+01
a198455a-7fda-4ea2-8f01-6222049ad19a	6e5b011b-1658-420d-886d-4f0802372d0b	2025-01-02	\N	\N	\N	91.180000	\N	GENERATED	2025-11-04 12:45:10.979026+01
fed55a93-3085-4793-8de5-9216aa7bdc98	6e5b011b-1658-420d-886d-4f0802372d0b	2025-01-03	\N	\N	\N	90.290000	\N	GENERATED	2025-11-04 12:45:10.979667+01
effa0a23-2f8f-46c6-9965-6adac74cc3d9	6e5b011b-1658-420d-886d-4f0802372d0b	2025-01-04	\N	\N	\N	90.790000	\N	GENERATED	2025-11-04 12:45:10.980301+01
f2c4191c-2002-4709-bbf7-fdbe143dd3e2	6e5b011b-1658-420d-886d-4f0802372d0b	2025-01-05	\N	\N	\N	90.400000	\N	GENERATED	2025-11-04 12:45:10.980939+01
d5e00722-d31d-4c34-99d9-7e6e6f0d24d2	6e5b011b-1658-420d-886d-4f0802372d0b	2025-01-06	\N	\N	\N	90.370000	\N	GENERATED	2025-11-04 12:45:10.981588+01
076adee2-e920-4c32-9e05-a1e6218bc382	6e5b011b-1658-420d-886d-4f0802372d0b	2025-01-07	\N	\N	\N	91.660000	\N	GENERATED	2025-11-04 12:45:10.982687+01
08344a23-ca8e-4acc-96b5-a706e4c6eae2	6e5b011b-1658-420d-886d-4f0802372d0b	2025-01-08	\N	\N	\N	90.780000	\N	GENERATED	2025-11-04 12:45:10.983329+01
5556bbc5-8814-429e-896d-27e53fccce01	6e5b011b-1658-420d-886d-4f0802372d0b	2025-01-09	\N	\N	\N	91.470000	\N	GENERATED	2025-11-04 12:45:10.983969+01
329598ab-be61-40fe-80e6-e93760805523	6e5b011b-1658-420d-886d-4f0802372d0b	2025-01-10	\N	\N	\N	91.250000	\N	GENERATED	2025-11-04 12:45:10.984621+01
f046a59f-2320-4a4d-a41e-ad04638c07b5	6e5b011b-1658-420d-886d-4f0802372d0b	2025-01-11	\N	\N	\N	91.020000	\N	GENERATED	2025-11-04 12:45:10.985758+01
1b0ef2f2-c608-46be-be43-cb050d379b6e	6e5b011b-1658-420d-886d-4f0802372d0b	2025-01-12	\N	\N	\N	90.630000	\N	GENERATED	2025-11-04 12:45:10.986498+01
67e4224e-e149-4bff-899c-4accc205a279	6e5b011b-1658-420d-886d-4f0802372d0b	2025-01-13	\N	\N	\N	90.950000	\N	GENERATED	2025-11-04 12:45:10.987163+01
badd0b12-87f2-418c-b05d-08a48245941a	6e5b011b-1658-420d-886d-4f0802372d0b	2025-01-14	\N	\N	\N	91.180000	\N	GENERATED	2025-11-04 12:45:10.987836+01
b8630eb9-c60d-4b71-9538-bcde379581aa	6e5b011b-1658-420d-886d-4f0802372d0b	2025-01-15	\N	\N	\N	90.660000	\N	GENERATED	2025-11-04 12:45:10.988474+01
831e627b-71ce-486f-8fc1-fd6f251fe4e3	6e5b011b-1658-420d-886d-4f0802372d0b	2025-01-16	\N	\N	\N	90.570000	\N	GENERATED	2025-11-04 12:45:10.989127+01
35bceec4-dd45-46fc-b340-e00bc7b5dc32	6e5b011b-1658-420d-886d-4f0802372d0b	2025-01-17	\N	\N	\N	91.390000	\N	GENERATED	2025-11-04 12:45:10.989803+01
b6706b59-7867-447d-a3c7-d86fda83ee1e	6e5b011b-1658-420d-886d-4f0802372d0b	2025-01-18	\N	\N	\N	91.730000	\N	GENERATED	2025-11-04 12:45:10.99044+01
c4f43511-35a1-47f7-8169-8ac3ef9befe5	6e5b011b-1658-420d-886d-4f0802372d0b	2025-01-19	\N	\N	\N	91.530000	\N	GENERATED	2025-11-04 12:45:10.991087+01
b0292771-9e70-46d8-9807-0cfcbfb75f69	6e5b011b-1658-420d-886d-4f0802372d0b	2025-01-20	\N	\N	\N	92.040000	\N	GENERATED	2025-11-04 12:45:10.99174+01
e66f5f93-2c68-4bb9-a357-157ee8d26ced	6e5b011b-1658-420d-886d-4f0802372d0b	2025-01-21	\N	\N	\N	92.340000	\N	GENERATED	2025-11-04 12:45:10.992385+01
a08cc2ed-0b04-441f-976e-4ac0946205b6	6e5b011b-1658-420d-886d-4f0802372d0b	2025-01-22	\N	\N	\N	91.230000	\N	GENERATED	2025-11-04 12:45:10.993035+01
a1318c14-269d-481b-a5d8-6798e8694bf1	6e5b011b-1658-420d-886d-4f0802372d0b	2025-01-23	\N	\N	\N	91.440000	\N	GENERATED	2025-11-04 12:45:10.993767+01
915b89c4-ffd5-49ad-b8eb-2fc9f7345dac	6e5b011b-1658-420d-886d-4f0802372d0b	2025-01-24	\N	\N	\N	91.360000	\N	GENERATED	2025-11-04 12:45:10.994413+01
39c8d04c-5ddc-4c15-a5f1-ed5afb987605	6e5b011b-1658-420d-886d-4f0802372d0b	2025-01-25	\N	\N	\N	91.500000	\N	GENERATED	2025-11-04 12:45:10.995147+01
d60d5fbb-29b7-419d-bc5c-4c62cc2631a2	6e5b011b-1658-420d-886d-4f0802372d0b	2025-01-26	\N	\N	\N	91.530000	\N	GENERATED	2025-11-04 12:45:10.995794+01
9cd0378e-d06c-484a-a42f-878a85a813b7	6e5b011b-1658-420d-886d-4f0802372d0b	2025-01-27	\N	\N	\N	91.050000	\N	GENERATED	2025-11-04 12:45:10.996438+01
630ee857-bc2c-4e09-88ba-1c200348bbee	6e5b011b-1658-420d-886d-4f0802372d0b	2025-01-28	\N	\N	\N	91.600000	\N	GENERATED	2025-11-04 12:45:10.997106+01
71b48e9b-107a-4ba3-9770-49bfcd3f5c39	6e5b011b-1658-420d-886d-4f0802372d0b	2025-01-29	\N	\N	\N	91.900000	\N	GENERATED	2025-11-04 12:45:10.997766+01
3e4cde54-f0b1-438e-892a-6f740dcd6f77	6e5b011b-1658-420d-886d-4f0802372d0b	2025-01-30	\N	\N	\N	92.200000	\N	GENERATED	2025-11-04 12:45:10.998403+01
b4d3b699-be83-4618-a790-59e02ee6cdd8	6e5b011b-1658-420d-886d-4f0802372d0b	2025-01-31	\N	\N	\N	91.020000	\N	GENERATED	2025-11-04 12:45:10.999046+01
19926fb2-be1b-4881-8c44-2426849a5e71	6e5b011b-1658-420d-886d-4f0802372d0b	2025-02-01	\N	\N	\N	91.440000	\N	GENERATED	2025-11-04 12:45:10.999726+01
60bccc11-d400-4926-ae85-9b604e48e4c3	6e5b011b-1658-420d-886d-4f0802372d0b	2025-02-02	\N	\N	\N	92.030000	\N	GENERATED	2025-11-04 12:45:11.000362+01
ab5d9925-e749-4557-ae03-936872590d85	6e5b011b-1658-420d-886d-4f0802372d0b	2025-02-03	\N	\N	\N	91.960000	\N	GENERATED	2025-11-04 12:45:11.000999+01
e1549cfc-bba9-4458-8a9b-9d1f22ac0af8	6e5b011b-1658-420d-886d-4f0802372d0b	2025-02-04	\N	\N	\N	91.300000	\N	GENERATED	2025-11-04 12:45:11.001644+01
7ae9b675-9216-4165-98c5-582018538d5b	6e5b011b-1658-420d-886d-4f0802372d0b	2025-02-05	\N	\N	\N	91.080000	\N	GENERATED	2025-11-04 12:45:11.002444+01
5a9eea4b-bfb9-4406-b84d-6f9eea529b58	6e5b011b-1658-420d-886d-4f0802372d0b	2025-02-06	\N	\N	\N	91.260000	\N	GENERATED	2025-11-04 12:45:11.003118+01
24eaacf2-f99e-4735-9069-5452440b3c3d	6e5b011b-1658-420d-886d-4f0802372d0b	2025-02-07	\N	\N	\N	91.290000	\N	GENERATED	2025-11-04 12:45:11.00377+01
14e4b84a-0208-4fb3-8cea-59955526474b	6e5b011b-1658-420d-886d-4f0802372d0b	2025-02-08	\N	\N	\N	91.440000	\N	GENERATED	2025-11-04 12:45:11.004427+01
c6cdccd3-ec8a-4d5b-8f75-f0081bfe7d68	6e5b011b-1658-420d-886d-4f0802372d0b	2025-02-09	\N	\N	\N	92.550000	\N	GENERATED	2025-11-04 12:45:11.005139+01
06d16aa5-d9a3-446d-be04-6d975ea45bbb	6e5b011b-1658-420d-886d-4f0802372d0b	2025-02-10	\N	\N	\N	91.140000	\N	GENERATED	2025-11-04 12:45:11.005948+01
18609643-1ae6-4cf9-b119-9e14c2359e8a	6e5b011b-1658-420d-886d-4f0802372d0b	2025-02-11	\N	\N	\N	92.840000	\N	GENERATED	2025-11-04 12:45:11.006605+01
acfe1fe6-0712-42f5-a951-e83aad316fb5	6e5b011b-1658-420d-886d-4f0802372d0b	2025-02-12	\N	\N	\N	91.740000	\N	GENERATED	2025-11-04 12:45:11.007263+01
46f3621d-43a0-4c71-890c-b06e21442231	6e5b011b-1658-420d-886d-4f0802372d0b	2025-02-13	\N	\N	\N	91.730000	\N	GENERATED	2025-11-04 12:45:11.007916+01
e64a13e2-416e-44bd-9029-1f25f84f3673	6e5b011b-1658-420d-886d-4f0802372d0b	2025-02-14	\N	\N	\N	92.890000	\N	GENERATED	2025-11-04 12:45:11.008547+01
5ec23f4d-b99a-4f3b-bb84-e567788dd919	6e5b011b-1658-420d-886d-4f0802372d0b	2025-02-15	\N	\N	\N	92.700000	\N	GENERATED	2025-11-04 12:45:11.009183+01
4704cc0c-b53f-4726-905d-eec0c79a4d4e	6e5b011b-1658-420d-886d-4f0802372d0b	2025-02-16	\N	\N	\N	91.870000	\N	GENERATED	2025-11-04 12:45:11.009843+01
2aca4ff3-9ab4-44cf-a0d1-49aa40568c85	6e5b011b-1658-420d-886d-4f0802372d0b	2025-02-17	\N	\N	\N	91.330000	\N	GENERATED	2025-11-04 12:45:11.010472+01
2704c7ba-b117-472d-9e97-49bb18405860	6e5b011b-1658-420d-886d-4f0802372d0b	2025-02-18	\N	\N	\N	91.540000	\N	GENERATED	2025-11-04 12:45:11.011108+01
2f7871e7-f5c9-4bcb-8515-7b0c8fe5f9bb	6e5b011b-1658-420d-886d-4f0802372d0b	2025-02-19	\N	\N	\N	91.530000	\N	GENERATED	2025-11-04 12:45:11.011766+01
0a6fe9da-6451-4a04-a5c7-6dbd66462a1f	6e5b011b-1658-420d-886d-4f0802372d0b	2025-02-20	\N	\N	\N	91.770000	\N	GENERATED	2025-11-04 12:45:11.012719+01
cd849b67-465c-48b7-99dc-de4f2015942b	6e5b011b-1658-420d-886d-4f0802372d0b	2025-02-21	\N	\N	\N	91.670000	\N	GENERATED	2025-11-04 12:45:11.013435+01
1728e711-73bb-42b2-8a4d-d1bf0198817e	6e5b011b-1658-420d-886d-4f0802372d0b	2025-02-22	\N	\N	\N	92.390000	\N	GENERATED	2025-11-04 12:45:11.014089+01
e3f58f40-c701-4235-a4b7-7c931adf9fc9	6e5b011b-1658-420d-886d-4f0802372d0b	2025-02-23	\N	\N	\N	91.470000	\N	GENERATED	2025-11-04 12:45:11.014717+01
0d2b9c59-30df-4668-b3e3-eec22d38e2b2	6e5b011b-1658-420d-886d-4f0802372d0b	2025-02-24	\N	\N	\N	92.180000	\N	GENERATED	2025-11-04 12:45:11.015345+01
5b8551bc-877b-4997-8468-ba51de236399	6e5b011b-1658-420d-886d-4f0802372d0b	2025-02-25	\N	\N	\N	91.600000	\N	GENERATED	2025-11-04 12:45:11.016091+01
bd5a517e-3118-4442-a710-5d4d47a69e00	6e5b011b-1658-420d-886d-4f0802372d0b	2025-02-26	\N	\N	\N	91.650000	\N	GENERATED	2025-11-04 12:45:11.016853+01
e3c1713e-9343-4ab0-8524-8d0511bcfba3	6e5b011b-1658-420d-886d-4f0802372d0b	2025-02-27	\N	\N	\N	91.820000	\N	GENERATED	2025-11-04 12:45:11.017799+01
7abc6676-a512-4f4a-a029-598c243d33f3	6e5b011b-1658-420d-886d-4f0802372d0b	2025-02-28	\N	\N	\N	92.640000	\N	GENERATED	2025-11-04 12:45:11.018487+01
a990a534-8c29-4ca9-9a50-a6729025de9e	6e5b011b-1658-420d-886d-4f0802372d0b	2025-03-01	\N	\N	\N	92.780000	\N	GENERATED	2025-11-04 12:45:11.019129+01
98473fc9-7b8c-4dac-8177-f5fe161a8552	6e5b011b-1658-420d-886d-4f0802372d0b	2025-03-02	\N	\N	\N	92.760000	\N	GENERATED	2025-11-04 12:45:11.01979+01
b32840fa-21f8-4858-8047-bf2e99c354f5	6e5b011b-1658-420d-886d-4f0802372d0b	2025-03-03	\N	\N	\N	91.500000	\N	GENERATED	2025-11-04 12:45:11.020431+01
7388cc2f-c8e3-4586-8c4b-16aa8e715695	6e5b011b-1658-420d-886d-4f0802372d0b	2025-03-04	\N	\N	\N	93.250000	\N	GENERATED	2025-11-04 12:45:11.021075+01
64b7021e-2b3f-4cf8-bd2c-11980d20444e	6e5b011b-1658-420d-886d-4f0802372d0b	2025-03-05	\N	\N	\N	92.930000	\N	GENERATED	2025-11-04 12:45:11.021717+01
f1a36b08-63e7-473c-8151-7c6e7cbb713e	6e5b011b-1658-420d-886d-4f0802372d0b	2025-03-06	\N	\N	\N	91.960000	\N	GENERATED	2025-11-04 12:45:11.02235+01
3aed94fc-ce84-48eb-ad0a-22ab8863a7c3	6e5b011b-1658-420d-886d-4f0802372d0b	2025-03-07	\N	\N	\N	92.130000	\N	GENERATED	2025-11-04 12:45:11.022999+01
993d37f9-894d-4bb5-87f9-a640bc00a5ef	6e5b011b-1658-420d-886d-4f0802372d0b	2025-03-08	\N	\N	\N	93.010000	\N	GENERATED	2025-11-04 12:45:11.023631+01
34be2778-0ee3-485e-b07e-a29671fc0fa0	6e5b011b-1658-420d-886d-4f0802372d0b	2025-03-09	\N	\N	\N	91.620000	\N	GENERATED	2025-11-04 12:45:11.02426+01
770ab4a1-7862-406a-aa27-56265bd2f9c3	6e5b011b-1658-420d-886d-4f0802372d0b	2025-03-10	\N	\N	\N	92.840000	\N	GENERATED	2025-11-04 12:45:11.0249+01
c8ff4813-66c9-419b-b97e-c582a885b6ab	6e5b011b-1658-420d-886d-4f0802372d0b	2025-03-11	\N	\N	\N	91.760000	\N	GENERATED	2025-11-04 12:45:11.025536+01
548b5027-b159-4fc1-9ea7-160d2c79b8a6	6e5b011b-1658-420d-886d-4f0802372d0b	2025-03-12	\N	\N	\N	92.280000	\N	GENERATED	2025-11-04 12:45:11.026178+01
44cecac1-5121-41cf-8305-905cfced9276	6e5b011b-1658-420d-886d-4f0802372d0b	2025-03-13	\N	\N	\N	93.090000	\N	GENERATED	2025-11-04 12:45:11.026859+01
27ed7179-7367-4096-a23f-79c9d34a2aed	6e5b011b-1658-420d-886d-4f0802372d0b	2025-03-14	\N	\N	\N	92.630000	\N	GENERATED	2025-11-04 12:45:11.027516+01
dc2027a4-8cf3-4296-9f4f-3812e5efd9ae	6e5b011b-1658-420d-886d-4f0802372d0b	2025-03-15	\N	\N	\N	93.110000	\N	GENERATED	2025-11-04 12:45:11.028164+01
108ca585-632e-43b1-a5fa-62e22bb9abe4	6e5b011b-1658-420d-886d-4f0802372d0b	2025-03-16	\N	\N	\N	92.580000	\N	GENERATED	2025-11-04 12:45:11.028797+01
f565fa01-9b60-4b8c-8de1-8c5209afa18d	6e5b011b-1658-420d-886d-4f0802372d0b	2025-03-17	\N	\N	\N	92.950000	\N	GENERATED	2025-11-04 12:45:11.029451+01
404594bb-3612-42cd-bf34-34e0c983b784	6e5b011b-1658-420d-886d-4f0802372d0b	2025-03-18	\N	\N	\N	92.270000	\N	GENERATED	2025-11-04 12:45:11.030089+01
a8d7b4cd-8668-41ed-91e4-12fb15fbb05c	6e5b011b-1658-420d-886d-4f0802372d0b	2025-03-19	\N	\N	\N	92.200000	\N	GENERATED	2025-11-04 12:45:11.030715+01
2f413a63-f2c7-464b-9c27-c2bfaf1901be	6e5b011b-1658-420d-886d-4f0802372d0b	2025-03-20	\N	\N	\N	91.910000	\N	GENERATED	2025-11-04 12:45:11.031351+01
9e9594b0-24b6-406b-8208-47e4194ccaf4	6e5b011b-1658-420d-886d-4f0802372d0b	2025-03-21	\N	\N	\N	92.550000	\N	GENERATED	2025-11-04 12:45:11.032045+01
d9654337-ed05-43d2-a164-d08f214db663	6e5b011b-1658-420d-886d-4f0802372d0b	2025-03-22	\N	\N	\N	92.390000	\N	GENERATED	2025-11-04 12:45:11.032899+01
f5de5e73-1ce1-4a56-90bb-e671579bddd2	6e5b011b-1658-420d-886d-4f0802372d0b	2025-03-23	\N	\N	\N	93.400000	\N	GENERATED	2025-11-04 12:45:11.033895+01
c11c69f2-e3f8-49ea-9316-bc0342ef3dae	6e5b011b-1658-420d-886d-4f0802372d0b	2025-03-24	\N	\N	\N	92.140000	\N	GENERATED	2025-11-04 12:45:11.034765+01
569de803-da54-4b6f-ac39-ea7e035b95c0	6e5b011b-1658-420d-886d-4f0802372d0b	2025-03-25	\N	\N	\N	93.090000	\N	GENERATED	2025-11-04 12:45:11.035623+01
b27e3ce9-7a59-4163-b0f2-9f35427a40ba	6e5b011b-1658-420d-886d-4f0802372d0b	2025-03-26	\N	\N	\N	93.610000	\N	GENERATED	2025-11-04 12:45:11.036476+01
7b4e58f1-681a-48a1-924b-cb81d53d155c	6e5b011b-1658-420d-886d-4f0802372d0b	2025-03-27	\N	\N	\N	92.170000	\N	GENERATED	2025-11-04 12:45:11.037352+01
79f83cd9-038d-4800-b90d-81d470bba158	6e5b011b-1658-420d-886d-4f0802372d0b	2025-03-28	\N	\N	\N	92.710000	\N	GENERATED	2025-11-04 12:45:11.03811+01
f50dd06a-22fa-4eb1-afd7-d96c3c5135c8	6e5b011b-1658-420d-886d-4f0802372d0b	2025-03-29	\N	\N	\N	92.890000	\N	GENERATED	2025-11-04 12:45:11.038766+01
06a01ee3-4321-4fb4-8e7e-6d9057840c00	6e5b011b-1658-420d-886d-4f0802372d0b	2025-03-30	\N	\N	\N	93.390000	\N	GENERATED	2025-11-04 12:45:11.039425+01
5c532ffe-5bf0-46cd-bf55-c5c7c14ecbbc	6e5b011b-1658-420d-886d-4f0802372d0b	2025-03-31	\N	\N	\N	92.500000	\N	GENERATED	2025-11-04 12:45:11.04009+01
004bb5a4-c06e-47ae-9fb3-83115c976437	6e5b011b-1658-420d-886d-4f0802372d0b	2025-04-01	\N	\N	\N	93.350000	\N	GENERATED	2025-11-04 12:45:11.040776+01
28ff0a00-0249-4b88-bd04-e94692767cbb	6e5b011b-1658-420d-886d-4f0802372d0b	2025-04-02	\N	\N	\N	92.740000	\N	GENERATED	2025-11-04 12:45:11.041502+01
8bf924d8-0103-4a5a-b6ce-05eb84eba6e8	6e5b011b-1658-420d-886d-4f0802372d0b	2025-04-03	\N	\N	\N	93.510000	\N	GENERATED	2025-11-04 12:45:11.042173+01
dba6f5cd-92b7-46c2-99d8-8702a2b6eab5	6e5b011b-1658-420d-886d-4f0802372d0b	2025-04-04	\N	\N	\N	92.870000	\N	GENERATED	2025-11-04 12:45:11.042849+01
8616953d-b55e-49aa-8f07-1c5b4d134876	6e5b011b-1658-420d-886d-4f0802372d0b	2025-04-05	\N	\N	\N	92.320000	\N	GENERATED	2025-11-04 12:45:11.043501+01
d8c7f23f-a2c6-4ef8-933d-446356b49b49	6e5b011b-1658-420d-886d-4f0802372d0b	2025-04-06	\N	\N	\N	93.490000	\N	GENERATED	2025-11-04 12:45:11.044157+01
6b4100a0-a4a8-4b56-b050-c1f1a894e278	6e5b011b-1658-420d-886d-4f0802372d0b	2025-04-07	\N	\N	\N	92.520000	\N	GENERATED	2025-11-04 12:45:11.04484+01
5245a8e9-abbb-4d70-b33b-3964ed9dbd0b	6e5b011b-1658-420d-886d-4f0802372d0b	2025-04-08	\N	\N	\N	92.510000	\N	GENERATED	2025-11-04 12:45:11.045481+01
ebedb777-6f66-46ce-bda1-f688875a1ea5	6e5b011b-1658-420d-886d-4f0802372d0b	2025-04-09	\N	\N	\N	93.590000	\N	GENERATED	2025-11-04 12:45:11.046131+01
dc49b111-52a9-4aa3-8369-65bc2aa5b279	6e5b011b-1658-420d-886d-4f0802372d0b	2025-04-10	\N	\N	\N	92.570000	\N	GENERATED	2025-11-04 12:45:11.046774+01
597eb450-5117-4c28-9fa7-26ee392dc3cb	6e5b011b-1658-420d-886d-4f0802372d0b	2025-04-11	\N	\N	\N	93.670000	\N	GENERATED	2025-11-04 12:45:11.047407+01
86986c12-e6f4-4178-889c-1cc58b401117	6e5b011b-1658-420d-886d-4f0802372d0b	2025-04-12	\N	\N	\N	93.220000	\N	GENERATED	2025-11-04 12:45:11.048241+01
9cd60367-cc15-4b8f-a34f-2689194e3896	6e5b011b-1658-420d-886d-4f0802372d0b	2025-04-13	\N	\N	\N	92.400000	\N	GENERATED	2025-11-04 12:45:11.049074+01
6d1aa795-24f2-4836-9ac3-aef600627c20	6e5b011b-1658-420d-886d-4f0802372d0b	2025-04-14	\N	\N	\N	93.680000	\N	GENERATED	2025-11-04 12:45:11.049803+01
02bab5aa-ad9e-4c77-8ddc-01e55128acd1	6e5b011b-1658-420d-886d-4f0802372d0b	2025-04-15	\N	\N	\N	93.370000	\N	GENERATED	2025-11-04 12:45:11.050438+01
eec0d8cf-b52f-4525-8768-5e98f810b3f0	6e5b011b-1658-420d-886d-4f0802372d0b	2025-04-16	\N	\N	\N	93.550000	\N	GENERATED	2025-11-04 12:45:11.051076+01
2fa93032-a14f-43e6-9d56-9f8204a353ef	6e5b011b-1658-420d-886d-4f0802372d0b	2025-04-17	\N	\N	\N	93.910000	\N	GENERATED	2025-11-04 12:45:11.051713+01
74064547-a4d3-4bcc-810b-9c18046b23bf	6e5b011b-1658-420d-886d-4f0802372d0b	2025-04-18	\N	\N	\N	93.670000	\N	GENERATED	2025-11-04 12:45:11.052415+01
4383b181-e840-49f9-ad74-c14fb6681b1b	6e5b011b-1658-420d-886d-4f0802372d0b	2025-04-19	\N	\N	\N	92.740000	\N	GENERATED	2025-11-04 12:45:11.053079+01
90a1a7e8-6b97-43cb-9569-2ec5dfc2bfed	6e5b011b-1658-420d-886d-4f0802372d0b	2025-04-20	\N	\N	\N	92.700000	\N	GENERATED	2025-11-04 12:45:11.053796+01
890b0e1d-23a4-4d2d-9721-0f0108952c5d	6e5b011b-1658-420d-886d-4f0802372d0b	2025-04-21	\N	\N	\N	92.560000	\N	GENERATED	2025-11-04 12:45:11.054448+01
e9de5e76-c3d6-43a0-9f24-e02c55d648c1	6e5b011b-1658-420d-886d-4f0802372d0b	2025-04-22	\N	\N	\N	92.810000	\N	GENERATED	2025-11-04 12:45:11.055093+01
2d164526-a359-484e-b025-71dfe3458509	6e5b011b-1658-420d-886d-4f0802372d0b	2025-04-23	\N	\N	\N	93.110000	\N	GENERATED	2025-11-04 12:45:11.055727+01
3ab34242-d018-4533-b55f-1dae0de27fe6	6e5b011b-1658-420d-886d-4f0802372d0b	2025-04-24	\N	\N	\N	93.650000	\N	GENERATED	2025-11-04 12:45:11.056371+01
204ee712-593a-4589-bdcb-43afea18ec15	6e5b011b-1658-420d-886d-4f0802372d0b	2025-04-25	\N	\N	\N	93.130000	\N	GENERATED	2025-11-04 12:45:11.057002+01
cbe5132d-3ce8-45c6-826a-feee46b73836	6e5b011b-1658-420d-886d-4f0802372d0b	2025-04-26	\N	\N	\N	94.010000	\N	GENERATED	2025-11-04 12:45:11.057672+01
c23f8819-136b-4e4e-a514-2383e2c0432e	6e5b011b-1658-420d-886d-4f0802372d0b	2025-04-27	\N	\N	\N	93.360000	\N	GENERATED	2025-11-04 12:45:11.058305+01
17b8ee01-f97d-4527-b548-adb9970ad9e5	6e5b011b-1658-420d-886d-4f0802372d0b	2025-04-28	\N	\N	\N	93.300000	\N	GENERATED	2025-11-04 12:45:11.058951+01
c38f977e-bf66-43a0-b224-8a4a5af056e0	6e5b011b-1658-420d-886d-4f0802372d0b	2025-04-29	\N	\N	\N	93.050000	\N	GENERATED	2025-11-04 12:45:11.0596+01
c66363c7-bdec-49b7-a3c4-aa61473eae16	6e5b011b-1658-420d-886d-4f0802372d0b	2025-04-30	\N	\N	\N	93.510000	\N	GENERATED	2025-11-04 12:45:11.060237+01
8137fa15-f179-489b-93d7-6e833441cbba	6e5b011b-1658-420d-886d-4f0802372d0b	2025-05-01	\N	\N	\N	93.820000	\N	GENERATED	2025-11-04 12:45:11.060871+01
9817ea48-1f0b-4c9f-97c7-9e2a8b512b8f	6e5b011b-1658-420d-886d-4f0802372d0b	2025-05-02	\N	\N	\N	92.880000	\N	GENERATED	2025-11-04 12:45:11.06152+01
c0cfe2e4-2464-496e-9d87-d15ef1b081c6	6e5b011b-1658-420d-886d-4f0802372d0b	2025-05-03	\N	\N	\N	94.390000	\N	GENERATED	2025-11-04 12:45:11.062149+01
2c4207cb-de0b-43ec-a49a-9bee6e5c5df9	6e5b011b-1658-420d-886d-4f0802372d0b	2025-05-04	\N	\N	\N	94.010000	\N	GENERATED	2025-11-04 12:45:11.062795+01
251655c5-d021-4e6f-89c5-3cac12cb17d3	6e5b011b-1658-420d-886d-4f0802372d0b	2025-05-05	\N	\N	\N	94.140000	\N	GENERATED	2025-11-04 12:45:11.063691+01
4b43411b-d37b-4cbd-8742-13af7ab62777	6e5b011b-1658-420d-886d-4f0802372d0b	2025-05-06	\N	\N	\N	94.150000	\N	GENERATED	2025-11-04 12:45:11.064721+01
88db0420-be48-4767-a135-74d68b3b6a88	6e5b011b-1658-420d-886d-4f0802372d0b	2025-05-07	\N	\N	\N	93.910000	\N	GENERATED	2025-11-04 12:45:11.065499+01
dc666021-9d3e-43ec-bad4-7df57ee7f4a8	6e5b011b-1658-420d-886d-4f0802372d0b	2025-05-08	\N	\N	\N	93.430000	\N	GENERATED	2025-11-04 12:45:11.066244+01
ba2633a3-d75f-4242-8e98-a01fd57684a8	6e5b011b-1658-420d-886d-4f0802372d0b	2025-05-09	\N	\N	\N	93.890000	\N	GENERATED	2025-11-04 12:45:11.066903+01
2cf7df12-3299-491c-b02b-f3262a06c291	6e5b011b-1658-420d-886d-4f0802372d0b	2025-05-10	\N	\N	\N	93.580000	\N	GENERATED	2025-11-04 12:45:11.067558+01
582a814a-1324-4181-b13f-d5cc824606be	6e5b011b-1658-420d-886d-4f0802372d0b	2025-05-11	\N	\N	\N	93.640000	\N	GENERATED	2025-11-04 12:45:11.068192+01
005c7a64-e50c-45df-8a4c-26b7a18f233f	6e5b011b-1658-420d-886d-4f0802372d0b	2025-05-12	\N	\N	\N	93.470000	\N	GENERATED	2025-11-04 12:45:11.068847+01
9496cdfc-8ed4-41fe-9cf8-3f097d2b86f6	6e5b011b-1658-420d-886d-4f0802372d0b	2025-05-13	\N	\N	\N	94.610000	\N	GENERATED	2025-11-04 12:45:11.069495+01
d504c7bd-ab45-4acb-be94-7a5ed8d6e626	6e5b011b-1658-420d-886d-4f0802372d0b	2025-05-14	\N	\N	\N	92.900000	\N	GENERATED	2025-11-04 12:45:11.070125+01
3263311e-aa23-4b60-8897-a9f15783d489	6e5b011b-1658-420d-886d-4f0802372d0b	2025-05-15	\N	\N	\N	94.420000	\N	GENERATED	2025-11-04 12:45:11.070767+01
9025222c-8524-4721-a977-bd294450da55	6e5b011b-1658-420d-886d-4f0802372d0b	2025-05-16	\N	\N	\N	93.130000	\N	GENERATED	2025-11-04 12:45:11.071418+01
2ba3349b-1d4d-46ab-81e4-71c98df0b856	6e5b011b-1658-420d-886d-4f0802372d0b	2025-05-17	\N	\N	\N	93.360000	\N	GENERATED	2025-11-04 12:45:11.072051+01
e80ee04b-bedc-447a-8772-89c326ddfdf6	6e5b011b-1658-420d-886d-4f0802372d0b	2025-05-18	\N	\N	\N	94.650000	\N	GENERATED	2025-11-04 12:45:11.072943+01
a79cb9ea-4e89-43da-806f-ad890315eaa3	6e5b011b-1658-420d-886d-4f0802372d0b	2025-05-19	\N	\N	\N	94.400000	\N	GENERATED	2025-11-04 12:45:11.073677+01
9dec53f0-48e1-472b-9f18-13f93d45afe9	6e5b011b-1658-420d-886d-4f0802372d0b	2025-05-20	\N	\N	\N	94.630000	\N	GENERATED	2025-11-04 12:45:11.074328+01
a651ee6e-f875-4eba-ac93-824f955936f1	6e5b011b-1658-420d-886d-4f0802372d0b	2025-05-21	\N	\N	\N	93.960000	\N	GENERATED	2025-11-04 12:45:11.074974+01
e22549aa-9d43-4941-b0fa-4da3b1b0ad60	6e5b011b-1658-420d-886d-4f0802372d0b	2025-05-22	\N	\N	\N	93.640000	\N	GENERATED	2025-11-04 12:45:11.075614+01
1ff95a01-35b6-467e-9efb-49f3a8394816	6e5b011b-1658-420d-886d-4f0802372d0b	2025-05-23	\N	\N	\N	93.440000	\N	GENERATED	2025-11-04 12:45:11.076249+01
ab24687a-428a-4210-bc81-a6b84d8e2788	6e5b011b-1658-420d-886d-4f0802372d0b	2025-05-24	\N	\N	\N	93.800000	\N	GENERATED	2025-11-04 12:45:11.076884+01
663bcdab-5ec4-4921-bc46-06eb6c7fb2c2	6e5b011b-1658-420d-886d-4f0802372d0b	2025-05-25	\N	\N	\N	94.110000	\N	GENERATED	2025-11-04 12:45:11.077531+01
d0bfc218-d7d6-441a-a6b6-de16bde03f40	6e5b011b-1658-420d-886d-4f0802372d0b	2025-05-26	\N	\N	\N	93.970000	\N	GENERATED	2025-11-04 12:45:11.078177+01
1f28b818-eda4-4c78-a5d9-b7ba43a32871	6e5b011b-1658-420d-886d-4f0802372d0b	2025-05-27	\N	\N	\N	93.270000	\N	GENERATED	2025-11-04 12:45:11.079151+01
50852f65-10ea-40b4-bd72-b6f52412e9ba	6e5b011b-1658-420d-886d-4f0802372d0b	2025-05-28	\N	\N	\N	94.780000	\N	GENERATED	2025-11-04 12:45:11.080117+01
fc60d0fd-e898-4c4d-be28-d69a21e96518	6e5b011b-1658-420d-886d-4f0802372d0b	2025-05-29	\N	\N	\N	93.380000	\N	GENERATED	2025-11-04 12:45:11.080798+01
3e01cdf1-4132-4273-85c6-61a072b8da65	6e5b011b-1658-420d-886d-4f0802372d0b	2025-05-30	\N	\N	\N	93.740000	\N	GENERATED	2025-11-04 12:45:11.081474+01
fe621a0a-4a5c-4ece-a5bf-bdf648c32032	6e5b011b-1658-420d-886d-4f0802372d0b	2025-05-31	\N	\N	\N	93.210000	\N	GENERATED	2025-11-04 12:45:11.082106+01
7a51da4e-9b75-4eea-875f-6030caed2b61	6e5b011b-1658-420d-886d-4f0802372d0b	2025-06-01	\N	\N	\N	93.810000	\N	GENERATED	2025-11-04 12:45:11.082767+01
61f6110a-afda-4d00-83a4-46c0993141be	6e5b011b-1658-420d-886d-4f0802372d0b	2025-06-02	\N	\N	\N	93.740000	\N	GENERATED	2025-11-04 12:45:11.083434+01
058f959e-7f59-414e-be62-727b5735d1f3	6e5b011b-1658-420d-886d-4f0802372d0b	2025-06-03	\N	\N	\N	94.200000	\N	GENERATED	2025-11-04 12:45:11.084067+01
9b7107e6-d095-4945-9605-4f59a66bf472	6e5b011b-1658-420d-886d-4f0802372d0b	2025-06-04	\N	\N	\N	95.070000	\N	GENERATED	2025-11-04 12:45:11.084847+01
a2979540-d365-4861-92aa-386822b5480f	6e5b011b-1658-420d-886d-4f0802372d0b	2025-06-05	\N	\N	\N	93.370000	\N	GENERATED	2025-11-04 12:45:11.085511+01
da3c006d-dc73-461d-98ec-e13eb5532269	6e5b011b-1658-420d-886d-4f0802372d0b	2025-06-06	\N	\N	\N	94.990000	\N	GENERATED	2025-11-04 12:45:11.086145+01
d33fd628-7df5-407f-88cc-fa95d60f08b4	6e5b011b-1658-420d-886d-4f0802372d0b	2025-06-07	\N	\N	\N	94.940000	\N	GENERATED	2025-11-04 12:45:11.086799+01
39988558-50c6-42d1-885e-c0d8ccecca09	6e5b011b-1658-420d-886d-4f0802372d0b	2025-06-08	\N	\N	\N	94.490000	\N	GENERATED	2025-11-04 12:45:11.087466+01
fe834252-b190-4cd0-98a0-bf05b05067cd	6e5b011b-1658-420d-886d-4f0802372d0b	2025-06-09	\N	\N	\N	94.650000	\N	GENERATED	2025-11-04 12:45:11.088098+01
140be189-c010-4caf-b05a-0019079c0115	6e5b011b-1658-420d-886d-4f0802372d0b	2025-06-10	\N	\N	\N	94.370000	\N	GENERATED	2025-11-04 12:45:11.088767+01
290d35ef-680e-4abe-a60f-f48f2df6de08	6e5b011b-1658-420d-886d-4f0802372d0b	2025-06-11	\N	\N	\N	95.010000	\N	GENERATED	2025-11-04 12:45:11.089422+01
bf47fca9-537e-4a01-976f-13807a939cba	6e5b011b-1658-420d-886d-4f0802372d0b	2025-06-12	\N	\N	\N	94.320000	\N	GENERATED	2025-11-04 12:45:11.090076+01
cc68ed3d-6c2b-4615-876b-41f8ffdb9ef1	6e5b011b-1658-420d-886d-4f0802372d0b	2025-06-13	\N	\N	\N	94.920000	\N	GENERATED	2025-11-04 12:45:11.090722+01
4f6b31a1-015d-41ed-8874-6d9f3bf316f0	6e5b011b-1658-420d-886d-4f0802372d0b	2025-06-14	\N	\N	\N	93.960000	\N	GENERATED	2025-11-04 12:45:11.091356+01
af85dda7-ba70-43ce-9e48-073c14e304b2	6e5b011b-1658-420d-886d-4f0802372d0b	2025-06-15	\N	\N	\N	94.750000	\N	GENERATED	2025-11-04 12:45:11.09211+01
cc929b94-dd68-4100-9f42-2757118473ae	6e5b011b-1658-420d-886d-4f0802372d0b	2025-06-16	\N	\N	\N	94.980000	\N	GENERATED	2025-11-04 12:45:11.092761+01
0a98e5e6-33cb-4beb-bb86-da9e210ac9c5	6e5b011b-1658-420d-886d-4f0802372d0b	2025-06-17	\N	\N	\N	93.810000	\N	GENERATED	2025-11-04 12:45:11.093424+01
ce8f4328-8741-4c2c-985d-8606c157b7eb	6e5b011b-1658-420d-886d-4f0802372d0b	2025-06-18	\N	\N	\N	93.690000	\N	GENERATED	2025-11-04 12:45:11.094085+01
2792e236-ebf1-4b45-969c-2931823ed60e	6e5b011b-1658-420d-886d-4f0802372d0b	2025-06-19	\N	\N	\N	94.270000	\N	GENERATED	2025-11-04 12:45:11.094834+01
856b3178-d732-4927-b6e4-17bdf4b617bc	6e5b011b-1658-420d-886d-4f0802372d0b	2025-06-20	\N	\N	\N	94.670000	\N	GENERATED	2025-11-04 12:45:11.096188+01
f579580a-7ebc-4f00-b53f-bb555239f64d	6e5b011b-1658-420d-886d-4f0802372d0b	2025-06-21	\N	\N	\N	94.880000	\N	GENERATED	2025-11-04 12:45:11.097112+01
e0bca0fd-127b-43bf-a8fe-5ac85978b715	6e5b011b-1658-420d-886d-4f0802372d0b	2025-06-22	\N	\N	\N	94.840000	\N	GENERATED	2025-11-04 12:45:11.098201+01
23537478-d0ad-4923-af83-8ed20560023a	6e5b011b-1658-420d-886d-4f0802372d0b	2025-06-23	\N	\N	\N	94.690000	\N	GENERATED	2025-11-04 12:45:11.099129+01
dd71ccc0-780e-4ea3-9675-c536173324fe	6e5b011b-1658-420d-886d-4f0802372d0b	2025-06-24	\N	\N	\N	94.790000	\N	GENERATED	2025-11-04 12:45:11.099884+01
99989371-fee5-4a1e-8894-9171a66436d9	6e5b011b-1658-420d-886d-4f0802372d0b	2025-06-25	\N	\N	\N	94.290000	\N	GENERATED	2025-11-04 12:45:11.100527+01
daede02e-40ae-4532-94ef-8af27a9e3c4b	6e5b011b-1658-420d-886d-4f0802372d0b	2025-06-26	\N	\N	\N	94.240000	\N	GENERATED	2025-11-04 12:45:11.10119+01
e0c2f318-af38-4409-ab92-16847b8c6747	6e5b011b-1658-420d-886d-4f0802372d0b	2025-06-27	\N	\N	\N	95.430000	\N	GENERATED	2025-11-04 12:45:11.101841+01
741b74ce-50fd-4fe5-93d8-0a03b2104fb1	6e5b011b-1658-420d-886d-4f0802372d0b	2025-06-28	\N	\N	\N	93.950000	\N	GENERATED	2025-11-04 12:45:11.102551+01
eff2e3d7-386c-4d18-893b-7f53dd0699f0	6e5b011b-1658-420d-886d-4f0802372d0b	2025-06-29	\N	\N	\N	94.970000	\N	GENERATED	2025-11-04 12:45:11.103195+01
3a769fb4-6844-4487-9955-b5ac53f16cf4	6e5b011b-1658-420d-886d-4f0802372d0b	2025-06-30	\N	\N	\N	93.920000	\N	GENERATED	2025-11-04 12:45:11.103845+01
2b81d36d-02e3-4a55-a0f9-f2e83995a540	6e5b011b-1658-420d-886d-4f0802372d0b	2025-07-01	\N	\N	\N	94.320000	\N	GENERATED	2025-11-04 12:45:11.104529+01
d2c5fd3b-4e8d-496e-9b7b-a18961c5ef09	6e5b011b-1658-420d-886d-4f0802372d0b	2025-07-02	\N	\N	\N	94.440000	\N	GENERATED	2025-11-04 12:45:11.10517+01
b59e0025-1f10-4db3-a230-651d5accdc51	6e5b011b-1658-420d-886d-4f0802372d0b	2025-07-03	\N	\N	\N	95.640000	\N	GENERATED	2025-11-04 12:45:11.105808+01
fc74c701-b1d3-4547-ac3a-d99523fa1cbe	6e5b011b-1658-420d-886d-4f0802372d0b	2025-07-04	\N	\N	\N	94.030000	\N	GENERATED	2025-11-04 12:45:11.106446+01
6d330d9b-7464-44fb-9918-c6cf93433e32	6e5b011b-1658-420d-886d-4f0802372d0b	2025-07-05	\N	\N	\N	95.500000	\N	GENERATED	2025-11-04 12:45:11.1071+01
770d315e-f39a-465b-9742-01769a962146	6e5b011b-1658-420d-886d-4f0802372d0b	2025-07-06	\N	\N	\N	94.040000	\N	GENERATED	2025-11-04 12:45:11.107745+01
3d25109a-2dec-4fe7-89bb-1bb315ba9e0b	6e5b011b-1658-420d-886d-4f0802372d0b	2025-07-07	\N	\N	\N	94.200000	\N	GENERATED	2025-11-04 12:45:11.108385+01
3a1ff02d-4d7c-4222-847e-1e646d647f7e	6e5b011b-1658-420d-886d-4f0802372d0b	2025-07-08	\N	\N	\N	94.370000	\N	GENERATED	2025-11-04 12:45:11.109026+01
84f3a53c-e6d4-4284-804a-2919f56fae21	6e5b011b-1658-420d-886d-4f0802372d0b	2025-07-09	\N	\N	\N	94.920000	\N	GENERATED	2025-11-04 12:45:11.10968+01
48f0416a-80d9-436d-9077-4c5adc49d84d	6e5b011b-1658-420d-886d-4f0802372d0b	2025-07-10	\N	\N	\N	94.780000	\N	GENERATED	2025-11-04 12:45:11.110338+01
0c5d91f8-5289-45a5-8c48-c615168a3aad	6e5b011b-1658-420d-886d-4f0802372d0b	2025-07-11	\N	\N	\N	94.950000	\N	GENERATED	2025-11-04 12:45:11.111064+01
6ae94543-c4c2-4638-b977-0be969dd328b	6e5b011b-1658-420d-886d-4f0802372d0b	2025-07-12	\N	\N	\N	95.180000	\N	GENERATED	2025-11-04 12:45:11.11172+01
5e8f4245-371b-4aae-9e3a-e2451ed4b5fd	6e5b011b-1658-420d-886d-4f0802372d0b	2025-07-13	\N	\N	\N	94.110000	\N	GENERATED	2025-11-04 12:45:11.112361+01
3f8c5c7d-ae0c-4d82-b330-c3bbc0ce08e0	6e5b011b-1658-420d-886d-4f0802372d0b	2025-07-14	\N	\N	\N	95.500000	\N	GENERATED	2025-11-04 12:45:11.113012+01
6b38653b-abf4-48e0-a5b3-37499d05b4c7	6e5b011b-1658-420d-886d-4f0802372d0b	2025-07-15	\N	\N	\N	94.760000	\N	GENERATED	2025-11-04 12:45:11.113734+01
0529fb80-ad54-440f-be5d-958f5c585048	6e5b011b-1658-420d-886d-4f0802372d0b	2025-07-16	\N	\N	\N	95.800000	\N	GENERATED	2025-11-04 12:45:11.114373+01
3e362ff5-fc0a-402f-82e9-d89be0cb4e07	6e5b011b-1658-420d-886d-4f0802372d0b	2025-07-17	\N	\N	\N	94.790000	\N	GENERATED	2025-11-04 12:45:11.115021+01
8d2c0098-77ae-4479-8d30-3c9b90ebd19e	6e5b011b-1658-420d-886d-4f0802372d0b	2025-07-18	\N	\N	\N	95.700000	\N	GENERATED	2025-11-04 12:45:11.115667+01
22a2018c-53ea-49a0-989e-61eb7388cd67	6e5b011b-1658-420d-886d-4f0802372d0b	2025-07-19	\N	\N	\N	95.290000	\N	GENERATED	2025-11-04 12:45:11.116311+01
3e04dfe7-a42b-4914-bd0c-3ba00b27ae44	6e5b011b-1658-420d-886d-4f0802372d0b	2025-07-20	\N	\N	\N	94.740000	\N	GENERATED	2025-11-04 12:45:11.116954+01
0a516664-8a58-49c5-9bd0-3b0af0acf984	6e5b011b-1658-420d-886d-4f0802372d0b	2025-07-21	\N	\N	\N	95.500000	\N	GENERATED	2025-11-04 12:45:11.117584+01
35728769-3369-4c23-b14e-6884a2e1f061	6e5b011b-1658-420d-886d-4f0802372d0b	2025-07-22	\N	\N	\N	95.100000	\N	GENERATED	2025-11-04 12:45:11.118223+01
9e9f3283-47b1-4eed-a8df-73209949a0e6	6e5b011b-1658-420d-886d-4f0802372d0b	2025-07-23	\N	\N	\N	95.010000	\N	GENERATED	2025-11-04 12:45:11.118855+01
4a3a3a4e-dd1c-4a57-89a7-d14f031a2c15	6e5b011b-1658-420d-886d-4f0802372d0b	2025-07-24	\N	\N	\N	95.350000	\N	GENERATED	2025-11-04 12:45:11.119493+01
f4932b79-53af-46ec-9617-da29b10808ee	6e5b011b-1658-420d-886d-4f0802372d0b	2025-07-25	\N	\N	\N	95.300000	\N	GENERATED	2025-11-04 12:45:11.12012+01
0fedf74b-a792-45b1-9eb8-c4c684831cc8	6e5b011b-1658-420d-886d-4f0802372d0b	2025-07-26	\N	\N	\N	95.850000	\N	GENERATED	2025-11-04 12:45:11.120756+01
241cae31-3622-44dd-b360-95b071600e03	6e5b011b-1658-420d-886d-4f0802372d0b	2025-07-27	\N	\N	\N	95.660000	\N	GENERATED	2025-11-04 12:45:11.12139+01
34afb41a-dda1-42f3-816d-5f3df3d50b6d	6e5b011b-1658-420d-886d-4f0802372d0b	2025-07-28	\N	\N	\N	94.910000	\N	GENERATED	2025-11-04 12:45:11.12205+01
22a94570-b91c-4da4-be1a-29b452aba3af	6e5b011b-1658-420d-886d-4f0802372d0b	2025-07-29	\N	\N	\N	95.350000	\N	GENERATED	2025-11-04 12:45:11.1227+01
2a2d07f7-6b91-44d2-902c-03f72b5d6929	6e5b011b-1658-420d-886d-4f0802372d0b	2025-07-30	\N	\N	\N	94.920000	\N	GENERATED	2025-11-04 12:45:11.123339+01
3051e15c-ada0-4552-a3b8-fa6db2b0b132	6e5b011b-1658-420d-886d-4f0802372d0b	2025-07-31	\N	\N	\N	95.310000	\N	GENERATED	2025-11-04 12:45:11.123995+01
07d3fac7-e826-4014-8e4a-9dc6129cc1cf	6e5b011b-1658-420d-886d-4f0802372d0b	2025-08-01	\N	\N	\N	94.600000	\N	GENERATED	2025-11-04 12:45:11.124634+01
20b68e1a-b7ef-48b2-8313-c18cf93a6e03	6e5b011b-1658-420d-886d-4f0802372d0b	2025-08-02	\N	\N	\N	94.940000	\N	GENERATED	2025-11-04 12:45:11.125262+01
76cb3b71-43a6-40a2-a4dd-566a593edacf	6e5b011b-1658-420d-886d-4f0802372d0b	2025-08-03	\N	\N	\N	94.930000	\N	GENERATED	2025-11-04 12:45:11.126054+01
74999449-d1e3-40dc-8a87-65e7b4120ffb	6e5b011b-1658-420d-886d-4f0802372d0b	2025-08-04	\N	\N	\N	96.040000	\N	GENERATED	2025-11-04 12:45:11.126712+01
67be56f2-0a4b-45e1-8b9e-dd8688e046d4	6e5b011b-1658-420d-886d-4f0802372d0b	2025-08-05	\N	\N	\N	95.530000	\N	GENERATED	2025-11-04 12:45:11.127349+01
f5c7cc8f-69cd-4153-b5f9-9de3be55bb01	6e5b011b-1658-420d-886d-4f0802372d0b	2025-08-06	\N	\N	\N	95.240000	\N	GENERATED	2025-11-04 12:45:11.127994+01
f2fb8e38-ecbb-48f2-bdf8-67c071557b4a	6e5b011b-1658-420d-886d-4f0802372d0b	2025-08-07	\N	\N	\N	96.120000	\N	GENERATED	2025-11-04 12:45:11.128738+01
539eb8f0-702a-4db0-9d0f-ac72bcff8884	6e5b011b-1658-420d-886d-4f0802372d0b	2025-08-08	\N	\N	\N	95.920000	\N	GENERATED	2025-11-04 12:45:11.129386+01
d587c8ae-b7fe-48ce-ad1d-a530836a99f4	6e5b011b-1658-420d-886d-4f0802372d0b	2025-08-09	\N	\N	\N	95.520000	\N	GENERATED	2025-11-04 12:45:11.130029+01
0a1a227a-b573-4894-8835-d7935bc18a90	6e5b011b-1658-420d-886d-4f0802372d0b	2025-08-10	\N	\N	\N	95.710000	\N	GENERATED	2025-11-04 12:45:11.130676+01
a3d2b8ad-b92b-410d-8733-b2ff75984521	6e5b011b-1658-420d-886d-4f0802372d0b	2025-08-11	\N	\N	\N	94.860000	\N	GENERATED	2025-11-04 12:45:11.131327+01
c0d968b7-ae97-4385-9330-7b9a15b6ceff	6e5b011b-1658-420d-886d-4f0802372d0b	2025-08-12	\N	\N	\N	95.690000	\N	GENERATED	2025-11-04 12:45:11.131962+01
494322c2-88b2-425d-8518-2aab863bb66b	6e5b011b-1658-420d-886d-4f0802372d0b	2025-08-13	\N	\N	\N	95.860000	\N	GENERATED	2025-11-04 12:45:11.132609+01
4592d3de-6d9c-4219-95a7-2c8cb6057c84	6e5b011b-1658-420d-886d-4f0802372d0b	2025-08-14	\N	\N	\N	96.460000	\N	GENERATED	2025-11-04 12:45:11.133236+01
deba3e66-3c1a-46bc-b4a0-43ad4c5279b0	6e5b011b-1658-420d-886d-4f0802372d0b	2025-08-15	\N	\N	\N	95.040000	\N	GENERATED	2025-11-04 12:45:11.13394+01
895fadb4-195c-415a-8fcd-4de490042c54	6e5b011b-1658-420d-886d-4f0802372d0b	2025-08-16	\N	\N	\N	95.480000	\N	GENERATED	2025-11-04 12:45:11.13458+01
406aef7f-b97f-4a06-af69-b81c7fc8ed19	6e5b011b-1658-420d-886d-4f0802372d0b	2025-08-17	\N	\N	\N	95.030000	\N	GENERATED	2025-11-04 12:45:11.135293+01
cc7d13c7-6411-4af5-8254-6742aa7799f6	6e5b011b-1658-420d-886d-4f0802372d0b	2025-08-18	\N	\N	\N	95.020000	\N	GENERATED	2025-11-04 12:45:11.135928+01
8f21f443-353c-4d48-ac70-9db19dd5ff01	6e5b011b-1658-420d-886d-4f0802372d0b	2025-08-19	\N	\N	\N	96.140000	\N	GENERATED	2025-11-04 12:45:11.136578+01
555ea26c-e800-450e-8148-c2ae335ed666	6e5b011b-1658-420d-886d-4f0802372d0b	2025-08-20	\N	\N	\N	96.070000	\N	GENERATED	2025-11-04 12:45:11.137226+01
33129974-441c-4d03-917b-e108c40d5032	6e5b011b-1658-420d-886d-4f0802372d0b	2025-08-21	\N	\N	\N	95.690000	\N	GENERATED	2025-11-04 12:45:11.137879+01
53f9ff88-42ce-4f5a-b743-8484bfa2b3b2	6e5b011b-1658-420d-886d-4f0802372d0b	2025-08-22	\N	\N	\N	94.860000	\N	GENERATED	2025-11-04 12:45:11.138511+01
3c144690-f52b-4e8c-8d96-6bb53ad550e2	6e5b011b-1658-420d-886d-4f0802372d0b	2025-08-23	\N	\N	\N	96.440000	\N	GENERATED	2025-11-04 12:45:11.139147+01
943853eb-fd20-4415-957f-273390dc571e	6e5b011b-1658-420d-886d-4f0802372d0b	2025-08-24	\N	\N	\N	96.290000	\N	GENERATED	2025-11-04 12:45:11.139809+01
cd3d2bc0-57f9-4bdd-a088-d30cf0fd3f5d	6e5b011b-1658-420d-886d-4f0802372d0b	2025-08-25	\N	\N	\N	95.360000	\N	GENERATED	2025-11-04 12:45:11.140461+01
ce300d10-7639-4714-9669-947eec386c22	6e5b011b-1658-420d-886d-4f0802372d0b	2025-08-26	\N	\N	\N	96.370000	\N	GENERATED	2025-11-04 12:45:11.141404+01
aca54fa0-4c7e-4873-98dc-a0b89fc1f2e8	6e5b011b-1658-420d-886d-4f0802372d0b	2025-08-27	\N	\N	\N	96.070000	\N	GENERATED	2025-11-04 12:45:11.142415+01
61aacdd3-6c11-4394-bc1c-5a39460c363c	6e5b011b-1658-420d-886d-4f0802372d0b	2025-08-28	\N	\N	\N	95.120000	\N	GENERATED	2025-11-04 12:45:11.143356+01
3017bb69-6b16-4ac6-b25a-f2a8918d6a47	6e5b011b-1658-420d-886d-4f0802372d0b	2025-08-29	\N	\N	\N	95.290000	\N	GENERATED	2025-11-04 12:45:11.144104+01
31ba191e-91ae-41b3-a968-1897e7613fbf	6e5b011b-1658-420d-886d-4f0802372d0b	2025-08-30	\N	\N	\N	95.920000	\N	GENERATED	2025-11-04 12:45:11.145545+01
928e0ce9-a857-4e81-806d-57db80701342	6e5b011b-1658-420d-886d-4f0802372d0b	2025-08-31	\N	\N	\N	95.970000	\N	GENERATED	2025-11-04 12:45:11.146339+01
cb714f96-1040-4fa0-8f88-ca77a1ddba30	6e5b011b-1658-420d-886d-4f0802372d0b	2025-09-01	\N	\N	\N	95.530000	\N	GENERATED	2025-11-04 12:45:11.147201+01
66c0e033-37e5-4bbc-b092-8b031452f216	6e5b011b-1658-420d-886d-4f0802372d0b	2025-09-02	\N	\N	\N	95.980000	\N	GENERATED	2025-11-04 12:45:11.148049+01
023e4d56-67d3-4dbf-8816-eb3e12139c6f	6e5b011b-1658-420d-886d-4f0802372d0b	2025-09-03	\N	\N	\N	95.730000	\N	GENERATED	2025-11-04 12:45:11.148863+01
447dc5f8-1e05-47ec-9435-37974b6833cf	6e5b011b-1658-420d-886d-4f0802372d0b	2025-09-04	\N	\N	\N	95.800000	\N	GENERATED	2025-11-04 12:45:11.149672+01
a0d7cf99-530f-46d4-a48c-74dad9730c06	6e5b011b-1658-420d-886d-4f0802372d0b	2025-09-05	\N	\N	\N	96.160000	\N	GENERATED	2025-11-04 12:45:11.150411+01
803e0eba-7459-4f1f-a13f-75d9052fb8f6	6e5b011b-1658-420d-886d-4f0802372d0b	2025-09-06	\N	\N	\N	96.930000	\N	GENERATED	2025-11-04 12:45:11.151263+01
09e56272-2e32-4af1-a49a-88703880866d	6e5b011b-1658-420d-886d-4f0802372d0b	2025-09-07	\N	\N	\N	96.460000	\N	GENERATED	2025-11-04 12:45:11.152156+01
8987a15c-d02a-4678-832b-4ebd2efd8a20	6e5b011b-1658-420d-886d-4f0802372d0b	2025-09-08	\N	\N	\N	96.950000	\N	GENERATED	2025-11-04 12:45:11.153153+01
38fb2fc3-137c-4757-867f-0c9517aa8022	6e5b011b-1658-420d-886d-4f0802372d0b	2025-09-09	\N	\N	\N	96.480000	\N	GENERATED	2025-11-04 12:45:11.154073+01
97be5ef7-c6e4-49e6-ac07-e954a18f9958	6e5b011b-1658-420d-886d-4f0802372d0b	2025-09-10	\N	\N	\N	95.370000	\N	GENERATED	2025-11-04 12:45:11.154937+01
caae6bb0-2923-4511-8ead-5a96d03e1bf2	6e5b011b-1658-420d-886d-4f0802372d0b	2025-09-11	\N	\N	\N	96.880000	\N	GENERATED	2025-11-04 12:45:11.155855+01
f5e0d791-3ede-4566-9cb2-376a8947d3c3	6e5b011b-1658-420d-886d-4f0802372d0b	2025-09-12	\N	\N	\N	95.530000	\N	GENERATED	2025-11-04 12:45:11.156826+01
a63bd404-adc0-4b62-895e-80996dd1b6ee	6e5b011b-1658-420d-886d-4f0802372d0b	2025-09-13	\N	\N	\N	95.690000	\N	GENERATED	2025-11-04 12:45:11.157728+01
ebb00940-0890-41be-9703-42d2ebbb7334	6e5b011b-1658-420d-886d-4f0802372d0b	2025-09-14	\N	\N	\N	95.850000	\N	GENERATED	2025-11-04 12:45:11.158634+01
ec23112b-0802-4a0f-85ed-9bf69fd895dc	6e5b011b-1658-420d-886d-4f0802372d0b	2025-09-15	\N	\N	\N	95.670000	\N	GENERATED	2025-11-04 12:45:11.159555+01
7b0d66e4-64a4-4ef4-9320-68f6fba9a290	6e5b011b-1658-420d-886d-4f0802372d0b	2025-09-16	\N	\N	\N	96.640000	\N	GENERATED	2025-11-04 12:45:11.160427+01
72804b3d-24a6-4424-984c-d5902a33fa90	6e5b011b-1658-420d-886d-4f0802372d0b	2025-09-17	\N	\N	\N	95.650000	\N	GENERATED	2025-11-04 12:45:11.161286+01
7022e0fb-c069-476c-b2ac-071b46878bed	6e5b011b-1658-420d-886d-4f0802372d0b	2025-09-18	\N	\N	\N	96.590000	\N	GENERATED	2025-11-04 12:45:11.162194+01
0fa36139-45c2-4168-b663-a1263ceb7f8f	6e5b011b-1658-420d-886d-4f0802372d0b	2025-09-19	\N	\N	\N	95.750000	\N	GENERATED	2025-11-04 12:45:11.163153+01
8e9379a4-1e39-4a16-8beb-4713300687b9	6e5b011b-1658-420d-886d-4f0802372d0b	2025-09-20	\N	\N	\N	96.530000	\N	GENERATED	2025-11-04 12:45:11.164044+01
fd440529-2a5c-4a07-a006-40a72dc84eac	6e5b011b-1658-420d-886d-4f0802372d0b	2025-09-21	\N	\N	\N	96.940000	\N	GENERATED	2025-11-04 12:45:11.164914+01
8b9226b1-99dd-4e64-b1c0-0c04c302bcc7	6e5b011b-1658-420d-886d-4f0802372d0b	2025-09-22	\N	\N	\N	96.400000	\N	GENERATED	2025-11-04 12:45:11.165814+01
8dbb58f5-ad78-4234-a796-11388a665a92	6e5b011b-1658-420d-886d-4f0802372d0b	2025-09-23	\N	\N	\N	96.830000	\N	GENERATED	2025-11-04 12:45:11.166734+01
562554d2-d194-4077-8b9c-d98ab8a3fa24	6e5b011b-1658-420d-886d-4f0802372d0b	2025-09-24	\N	\N	\N	95.610000	\N	GENERATED	2025-11-04 12:45:11.167602+01
f6c10063-ec6f-4c7b-94c0-30dc8c9a872c	6e5b011b-1658-420d-886d-4f0802372d0b	2025-09-25	\N	\N	\N	95.590000	\N	GENERATED	2025-11-04 12:45:11.168487+01
19fb8071-290c-47d7-83db-ece4ebcece88	6e5b011b-1658-420d-886d-4f0802372d0b	2025-09-26	\N	\N	\N	95.770000	\N	GENERATED	2025-11-04 12:45:11.169396+01
b76e4043-7568-4074-8b6c-eb72fe530121	6e5b011b-1658-420d-886d-4f0802372d0b	2025-09-27	\N	\N	\N	95.640000	\N	GENERATED	2025-11-04 12:45:11.17028+01
d9f79b06-7ed5-457d-a07b-e27c3f9d5cfd	6e5b011b-1658-420d-886d-4f0802372d0b	2025-09-28	\N	\N	\N	96.730000	\N	GENERATED	2025-11-04 12:45:11.171163+01
3b4a9c15-4e1c-41c8-8625-b43e090cdd3e	6e5b011b-1658-420d-886d-4f0802372d0b	2025-09-29	\N	\N	\N	95.630000	\N	GENERATED	2025-11-04 12:45:11.172161+01
e632782d-e567-4b10-bcb4-b3900f39c8f8	6e5b011b-1658-420d-886d-4f0802372d0b	2025-09-30	\N	\N	\N	96.810000	\N	GENERATED	2025-11-04 12:45:11.173044+01
bfb76d18-71d8-4ec0-a485-49f45b20278b	6e5b011b-1658-420d-886d-4f0802372d0b	2025-10-01	\N	\N	\N	96.480000	\N	GENERATED	2025-11-04 12:45:11.173925+01
fcbfcec7-86a5-4d1a-87b3-2efd4889d36c	6e5b011b-1658-420d-886d-4f0802372d0b	2025-10-02	\N	\N	\N	97.410000	\N	GENERATED	2025-11-04 12:45:11.174858+01
3365595d-e8af-4732-856c-37d469963553	6e5b011b-1658-420d-886d-4f0802372d0b	2025-10-03	\N	\N	\N	97.330000	\N	GENERATED	2025-11-04 12:45:11.175736+01
cb289894-fc5d-4ea0-879f-4b0620125a0c	6e5b011b-1658-420d-886d-4f0802372d0b	2025-10-04	\N	\N	\N	96.480000	\N	GENERATED	2025-11-04 12:45:11.176581+01
df7cb0df-87c0-46f4-9fcb-69ceb23fc64d	6e5b011b-1658-420d-886d-4f0802372d0b	2025-10-05	\N	\N	\N	97.470000	\N	GENERATED	2025-11-04 12:45:11.177469+01
4bfdb3f4-9ec5-4dca-ab27-afd0a2fcab74	6e5b011b-1658-420d-886d-4f0802372d0b	2025-10-06	\N	\N	\N	96.790000	\N	GENERATED	2025-11-04 12:45:11.178361+01
aa3dbd8e-9cc7-4367-b1ca-953d9cbef949	6e5b011b-1658-420d-886d-4f0802372d0b	2025-10-07	\N	\N	\N	96.550000	\N	GENERATED	2025-11-04 12:45:11.179294+01
9bdc6787-0577-464a-8b34-9088789b928a	6e5b011b-1658-420d-886d-4f0802372d0b	2025-10-08	\N	\N	\N	96.480000	\N	GENERATED	2025-11-04 12:45:11.180166+01
acb55ae1-9edf-4d17-baa9-26ccd0a255e3	6e5b011b-1658-420d-886d-4f0802372d0b	2025-10-09	\N	\N	\N	97.460000	\N	GENERATED	2025-11-04 12:45:11.181012+01
9e6605af-85ba-431e-9d37-2025166d232a	6e5b011b-1658-420d-886d-4f0802372d0b	2025-10-10	\N	\N	\N	97.520000	\N	GENERATED	2025-11-04 12:45:11.181873+01
c4cc2fff-b1eb-4bc7-a272-9cf88b82ff49	6e5b011b-1658-420d-886d-4f0802372d0b	2025-10-11	\N	\N	\N	97.190000	\N	GENERATED	2025-11-04 12:45:11.182737+01
56df8b3e-abac-477c-a6ff-23f461a6d452	6e5b011b-1658-420d-886d-4f0802372d0b	2025-10-12	\N	\N	\N	96.960000	\N	GENERATED	2025-11-04 12:45:11.183567+01
79905dde-fd5d-4ee6-81b0-af4296c5d99c	6e5b011b-1658-420d-886d-4f0802372d0b	2025-10-13	\N	\N	\N	97.210000	\N	GENERATED	2025-11-04 12:45:11.184424+01
b4128c14-da46-40b5-bd89-f217bf912961	6e5b011b-1658-420d-886d-4f0802372d0b	2025-10-14	\N	\N	\N	96.430000	\N	GENERATED	2025-11-04 12:45:11.185273+01
b4220d01-ed2e-42e2-ad9a-a96fd37b32ef	6e5b011b-1658-420d-886d-4f0802372d0b	2025-10-15	\N	\N	\N	96.670000	\N	GENERATED	2025-11-04 12:45:11.186114+01
7569efd3-82dc-497e-8179-ef7ab064abe9	6e5b011b-1658-420d-886d-4f0802372d0b	2025-10-16	\N	\N	\N	96.840000	\N	GENERATED	2025-11-04 12:45:11.187018+01
cc74e589-c0e2-4b7c-b16a-93d9422dc7ae	6e5b011b-1658-420d-886d-4f0802372d0b	2025-10-17	\N	\N	\N	96.910000	\N	GENERATED	2025-11-04 12:45:11.187963+01
6e1e99bf-3152-4d02-b2d2-3ae9348b9087	6e5b011b-1658-420d-886d-4f0802372d0b	2025-10-18	\N	\N	\N	97.520000	\N	GENERATED	2025-11-04 12:45:11.188815+01
16b98f91-e10e-4ce3-9721-2c188e7e810e	6e5b011b-1658-420d-886d-4f0802372d0b	2025-10-19	\N	\N	\N	97.130000	\N	GENERATED	2025-11-04 12:45:11.189637+01
82062b45-8842-46cd-8286-33baad489890	6e5b011b-1658-420d-886d-4f0802372d0b	2025-10-20	\N	\N	\N	97.490000	\N	GENERATED	2025-11-04 12:45:11.19046+01
86df7495-9d92-455c-9ddc-54a3a5aa3bcf	6e5b011b-1658-420d-886d-4f0802372d0b	2025-10-21	\N	\N	\N	96.630000	\N	GENERATED	2025-11-04 12:45:11.191251+01
9282ae68-8926-4745-b263-f01537d55132	6e5b011b-1658-420d-886d-4f0802372d0b	2025-10-22	\N	\N	\N	97.400000	\N	GENERATED	2025-11-04 12:45:11.192126+01
c001b0de-f00b-4d40-affd-0b818799432a	6e5b011b-1658-420d-886d-4f0802372d0b	2025-10-23	\N	\N	\N	96.720000	\N	GENERATED	2025-11-04 12:45:11.192928+01
8c78ff2c-4679-4295-b9c6-b952de15a552	6e5b011b-1658-420d-886d-4f0802372d0b	2025-10-24	\N	\N	\N	96.310000	\N	GENERATED	2025-11-04 12:45:11.193748+01
9bc0f3b3-97be-4b20-9b46-a4cab1ead67f	6e5b011b-1658-420d-886d-4f0802372d0b	2025-10-25	\N	\N	\N	97.140000	\N	GENERATED	2025-11-04 12:45:11.194665+01
fb44ec5d-b667-4286-8bc5-24b29cc04351	6e5b011b-1658-420d-886d-4f0802372d0b	2025-10-26	\N	\N	\N	96.550000	\N	GENERATED	2025-11-04 12:45:11.195471+01
0a2c1da9-5cfc-4619-898b-da8a5f761c19	6e5b011b-1658-420d-886d-4f0802372d0b	2025-10-27	\N	\N	\N	97.150000	\N	GENERATED	2025-11-04 12:45:11.196261+01
1b283944-ae3b-4486-9c80-ae318d8c09cb	6e5b011b-1658-420d-886d-4f0802372d0b	2025-10-28	\N	\N	\N	97.040000	\N	GENERATED	2025-11-04 12:45:11.197063+01
156fccfa-61b9-45ab-a12d-2dd78ec9f95f	6e5b011b-1658-420d-886d-4f0802372d0b	2025-10-29	\N	\N	\N	97.400000	\N	GENERATED	2025-11-04 12:45:11.197885+01
90eaaf25-ea97-4603-8490-c521ebc0685e	6e5b011b-1658-420d-886d-4f0802372d0b	2025-10-30	\N	\N	\N	97.440000	\N	GENERATED	2025-11-04 12:45:11.198699+01
bcc4b8e2-8b1f-4682-944c-14b2d07b4050	6e5b011b-1658-420d-886d-4f0802372d0b	2025-10-31	\N	\N	\N	97.920000	\N	GENERATED	2025-11-04 12:45:11.199495+01
8eeff5c5-7c68-4b3b-bcfa-2b657f1c6302	6e5b011b-1658-420d-886d-4f0802372d0b	2025-11-01	\N	\N	\N	97.730000	\N	GENERATED	2025-11-04 12:45:11.20031+01
072e164d-4c1a-42dd-acfd-1a2781ca76b9	6e5b011b-1658-420d-886d-4f0802372d0b	2025-11-02	\N	\N	\N	96.900000	\N	GENERATED	2025-11-04 12:45:11.201108+01
ac3f3488-9f9c-468e-803f-25c55f586d47	6e5b011b-1658-420d-886d-4f0802372d0b	2025-11-03	\N	\N	\N	97.720000	\N	GENERATED	2025-11-04 12:45:11.202162+01
78755cc1-a04c-4744-9e29-d3791a03ef97	0ede49d0-617f-451f-b90e-7fd9631cfa04	2024-11-04	\N	\N	\N	69.950000	\N	GENERATED	2025-11-04 12:45:11.203709+01
7a2d3658-b659-4514-980b-d8eefc8e3a56	0ede49d0-617f-451f-b90e-7fd9631cfa04	2024-11-05	\N	\N	\N	70.310000	\N	GENERATED	2025-11-04 12:45:11.204996+01
3e3518da-0130-4f33-ac2c-c820d638a4bd	0ede49d0-617f-451f-b90e-7fd9631cfa04	2024-11-06	\N	\N	\N	69.370000	\N	GENERATED	2025-11-04 12:45:11.205858+01
0b9e89be-35e8-4d70-9b41-7778f32a398e	0ede49d0-617f-451f-b90e-7fd9631cfa04	2024-11-07	\N	\N	\N	70.280000	\N	GENERATED	2025-11-04 12:45:11.206689+01
7443c76b-ca0a-4473-9c05-77188b2087cc	0ede49d0-617f-451f-b90e-7fd9631cfa04	2024-11-08	\N	\N	\N	69.650000	\N	GENERATED	2025-11-04 12:45:11.207579+01
837bf987-5afa-46d7-bac6-cd9e171fccc5	0ede49d0-617f-451f-b90e-7fd9631cfa04	2024-11-09	\N	\N	\N	70.160000	\N	GENERATED	2025-11-04 12:45:11.208417+01
fa1e6501-2c10-4b5f-b7bc-d118045a2c78	0ede49d0-617f-451f-b90e-7fd9631cfa04	2024-11-10	\N	\N	\N	70.300000	\N	GENERATED	2025-11-04 12:45:11.209304+01
375b3368-7cee-459b-b682-f1896bacb2f1	0ede49d0-617f-451f-b90e-7fd9631cfa04	2024-11-11	\N	\N	\N	70.400000	\N	GENERATED	2025-11-04 12:45:11.210242+01
da9702fa-3176-438a-866f-ad36afcedacf	0ede49d0-617f-451f-b90e-7fd9631cfa04	2024-11-12	\N	\N	\N	70.320000	\N	GENERATED	2025-11-04 12:45:11.211168+01
52645a3a-359e-4ffa-8c1b-ab43481049a8	0ede49d0-617f-451f-b90e-7fd9631cfa04	2024-11-13	\N	\N	\N	70.780000	\N	GENERATED	2025-11-04 12:45:11.21211+01
32a38ec5-61eb-41f5-8f28-aae79faafd18	0ede49d0-617f-451f-b90e-7fd9631cfa04	2024-11-14	\N	\N	\N	70.740000	\N	GENERATED	2025-11-04 12:45:11.213037+01
21e2d23b-ea3d-4887-8468-75d69f33b656	0ede49d0-617f-451f-b90e-7fd9631cfa04	2024-11-15	\N	\N	\N	70.010000	\N	GENERATED	2025-11-04 12:45:11.213993+01
0e48a9df-2c9b-453d-a1f9-4837ff18d8e9	0ede49d0-617f-451f-b90e-7fd9631cfa04	2024-11-16	\N	\N	\N	70.610000	\N	GENERATED	2025-11-04 12:45:11.214925+01
059ef9b2-9fab-4e10-9717-f9eca2767c5a	0ede49d0-617f-451f-b90e-7fd9631cfa04	2024-11-17	\N	\N	\N	69.870000	\N	GENERATED	2025-11-04 12:45:11.215864+01
382e1828-921a-4cca-8716-8e4bed85b954	0ede49d0-617f-451f-b90e-7fd9631cfa04	2024-11-18	\N	\N	\N	69.800000	\N	GENERATED	2025-11-04 12:45:11.21681+01
f0a2da12-04d9-44bb-a7cd-ff2fa58dddae	0ede49d0-617f-451f-b90e-7fd9631cfa04	2024-11-19	\N	\N	\N	69.860000	\N	GENERATED	2025-11-04 12:45:11.217974+01
89f16e71-089c-4cee-9ca1-67c886189b99	0ede49d0-617f-451f-b90e-7fd9631cfa04	2024-11-20	\N	\N	\N	70.200000	\N	GENERATED	2025-11-04 12:45:11.21913+01
2995a5f3-8022-42e6-9af6-baa16afea4cf	0ede49d0-617f-451f-b90e-7fd9631cfa04	2024-11-21	\N	\N	\N	70.520000	\N	GENERATED	2025-11-04 12:45:11.220097+01
64973897-6b59-44eb-96b2-572501dd41ee	0ede49d0-617f-451f-b90e-7fd9631cfa04	2024-11-22	\N	\N	\N	70.850000	\N	GENERATED	2025-11-04 12:45:11.22103+01
9fd1531b-3078-4c13-9eff-6e8ebac7fdc4	0ede49d0-617f-451f-b90e-7fd9631cfa04	2024-11-23	\N	\N	\N	70.240000	\N	GENERATED	2025-11-04 12:45:11.222028+01
344cd5f5-f377-4fc7-b503-546bc0277ae7	0ede49d0-617f-451f-b90e-7fd9631cfa04	2024-11-24	\N	\N	\N	70.310000	\N	GENERATED	2025-11-04 12:45:11.223122+01
b1fbf244-4a33-439c-af1b-5637b38c99d2	0ede49d0-617f-451f-b90e-7fd9631cfa04	2024-11-25	\N	\N	\N	70.330000	\N	GENERATED	2025-11-04 12:45:11.224061+01
bb40056f-b8f0-465d-bd9a-a5261a61175e	0ede49d0-617f-451f-b90e-7fd9631cfa04	2024-11-26	\N	\N	\N	70.940000	\N	GENERATED	2025-11-04 12:45:11.224997+01
79dd1443-18cc-4b9e-8790-3eb60c1c7c73	0ede49d0-617f-451f-b90e-7fd9631cfa04	2024-11-27	\N	\N	\N	69.790000	\N	GENERATED	2025-11-04 12:45:11.225939+01
9a44b63c-fe13-48e9-8e8b-fa5e49132eab	0ede49d0-617f-451f-b90e-7fd9631cfa04	2024-11-28	\N	\N	\N	70.740000	\N	GENERATED	2025-11-04 12:45:11.226879+01
0fc6bd46-18b8-4dfa-84a7-7845f40e9f33	0ede49d0-617f-451f-b90e-7fd9631cfa04	2024-11-29	\N	\N	\N	69.990000	\N	GENERATED	2025-11-04 12:45:11.22784+01
bf822070-49c6-4778-94bf-62a150cc8bb5	0ede49d0-617f-451f-b90e-7fd9631cfa04	2024-11-30	\N	\N	\N	70.270000	\N	GENERATED	2025-11-04 12:45:11.228814+01
c9f3553d-6763-430a-a117-81d3a1ef2e0b	0ede49d0-617f-451f-b90e-7fd9631cfa04	2024-12-01	\N	\N	\N	70.750000	\N	GENERATED	2025-11-04 12:45:11.229731+01
5d479aec-2f85-4289-97b9-210cf8418bd9	0ede49d0-617f-451f-b90e-7fd9631cfa04	2024-12-02	\N	\N	\N	69.730000	\N	GENERATED	2025-11-04 12:45:11.230537+01
d8c1efcf-bde6-4843-982f-3d39cb8a0136	0ede49d0-617f-451f-b90e-7fd9631cfa04	2024-12-03	\N	\N	\N	70.400000	\N	GENERATED	2025-11-04 12:45:11.231479+01
a7f7961d-9f45-482b-ac30-02eab09b7d0d	0ede49d0-617f-451f-b90e-7fd9631cfa04	2024-12-04	\N	\N	\N	69.800000	\N	GENERATED	2025-11-04 12:45:11.232404+01
04c39bba-7dfd-4f60-8ee7-e0ee30786665	0ede49d0-617f-451f-b90e-7fd9631cfa04	2024-12-05	\N	\N	\N	70.350000	\N	GENERATED	2025-11-04 12:45:11.23333+01
7d7abebc-3e27-406b-8dee-0f410eaa8eff	0ede49d0-617f-451f-b90e-7fd9631cfa04	2024-12-06	\N	\N	\N	70.800000	\N	GENERATED	2025-11-04 12:45:11.234383+01
1ec37663-f4ad-42c8-a96f-72eeb11e658c	0ede49d0-617f-451f-b90e-7fd9631cfa04	2024-12-07	\N	\N	\N	71.030000	\N	GENERATED	2025-11-04 12:45:11.235194+01
d0358b16-4578-43c7-ba6d-a086a5ea456e	0ede49d0-617f-451f-b90e-7fd9631cfa04	2024-12-08	\N	\N	\N	70.470000	\N	GENERATED	2025-11-04 12:45:11.236133+01
47e080d7-91d8-4493-9559-afcc46c7761a	0ede49d0-617f-451f-b90e-7fd9631cfa04	2024-12-09	\N	\N	\N	70.680000	\N	GENERATED	2025-11-04 12:45:11.237151+01
74d60b38-f091-4368-82a1-bfc43632a1b3	0ede49d0-617f-451f-b90e-7fd9631cfa04	2024-12-10	\N	\N	\N	71.020000	\N	GENERATED	2025-11-04 12:45:11.238274+01
9eefa824-cd9f-4637-b378-edd451c14ba0	0ede49d0-617f-451f-b90e-7fd9631cfa04	2024-12-11	\N	\N	\N	70.550000	\N	GENERATED	2025-11-04 12:45:11.239517+01
bd6ab49d-7013-47ab-87a3-091a5f08c470	0ede49d0-617f-451f-b90e-7fd9631cfa04	2024-12-12	\N	\N	\N	70.870000	\N	GENERATED	2025-11-04 12:45:11.24075+01
176e88b0-187e-4c7d-aaeb-c913a655d6fe	0ede49d0-617f-451f-b90e-7fd9631cfa04	2024-12-13	\N	\N	\N	70.660000	\N	GENERATED	2025-11-04 12:45:11.241971+01
d49e92d3-f916-43be-911b-888e1db8908a	0ede49d0-617f-451f-b90e-7fd9631cfa04	2024-12-14	\N	\N	\N	70.370000	\N	GENERATED	2025-11-04 12:45:11.24318+01
04f46742-e89f-4d55-835e-485162db43b1	0ede49d0-617f-451f-b90e-7fd9631cfa04	2024-12-15	\N	\N	\N	70.270000	\N	GENERATED	2025-11-04 12:45:11.244392+01
fbb47ee2-95d3-43d2-abdd-e4e67dc20817	0ede49d0-617f-451f-b90e-7fd9631cfa04	2024-12-16	\N	\N	\N	70.770000	\N	GENERATED	2025-11-04 12:45:11.245641+01
1488b588-55e4-4acb-8090-0e1eac347119	0ede49d0-617f-451f-b90e-7fd9631cfa04	2024-12-17	\N	\N	\N	70.060000	\N	GENERATED	2025-11-04 12:45:11.24685+01
d19af8e4-ace5-4806-985c-f278b3a9632b	0ede49d0-617f-451f-b90e-7fd9631cfa04	2024-12-18	\N	\N	\N	70.360000	\N	GENERATED	2025-11-04 12:45:11.248047+01
9e9a2aea-442b-4030-afc6-45e84c1854ca	0ede49d0-617f-451f-b90e-7fd9631cfa04	2024-12-19	\N	\N	\N	70.040000	\N	GENERATED	2025-11-04 12:45:11.249293+01
7bfa7f49-738d-49a9-b31d-efecc9a177cc	0ede49d0-617f-451f-b90e-7fd9631cfa04	2024-12-20	\N	\N	\N	70.150000	\N	GENERATED	2025-11-04 12:45:11.250564+01
eacd44c4-6d3a-419d-b4fa-d10170706107	0ede49d0-617f-451f-b90e-7fd9631cfa04	2024-12-21	\N	\N	\N	70.560000	\N	GENERATED	2025-11-04 12:45:11.251784+01
f4d06932-f89f-4eb7-af49-5d6a741d76b2	0ede49d0-617f-451f-b90e-7fd9631cfa04	2024-12-22	\N	\N	\N	71.250000	\N	GENERATED	2025-11-04 12:45:11.252988+01
aa7b8a2e-3305-4d76-b6e9-1914269c8f9b	0ede49d0-617f-451f-b90e-7fd9631cfa04	2024-12-23	\N	\N	\N	71.120000	\N	GENERATED	2025-11-04 12:45:11.254208+01
a394072a-5dff-418f-a84b-9c8af3ed51b8	0ede49d0-617f-451f-b90e-7fd9631cfa04	2024-12-24	\N	\N	\N	71.290000	\N	GENERATED	2025-11-04 12:45:11.25543+01
e8fd7742-6338-4a19-a4e8-f03f2baf1681	0ede49d0-617f-451f-b90e-7fd9631cfa04	2024-12-25	\N	\N	\N	70.470000	\N	GENERATED	2025-11-04 12:45:11.25655+01
8d5e3240-fd5d-40ca-a290-976484786457	0ede49d0-617f-451f-b90e-7fd9631cfa04	2024-12-26	\N	\N	\N	70.250000	\N	GENERATED	2025-11-04 12:45:11.257346+01
c479b12e-4ef9-4b86-ba63-ad074844fb4e	0ede49d0-617f-451f-b90e-7fd9631cfa04	2024-12-27	\N	\N	\N	71.360000	\N	GENERATED	2025-11-04 12:45:11.258024+01
a812ba79-baaa-4c19-9b1a-781d54226bf9	0ede49d0-617f-451f-b90e-7fd9631cfa04	2024-12-28	\N	\N	\N	70.330000	\N	GENERATED	2025-11-04 12:45:11.258706+01
d4778b4d-b253-41c2-ac8b-57098de04e27	0ede49d0-617f-451f-b90e-7fd9631cfa04	2024-12-29	\N	\N	\N	71.270000	\N	GENERATED	2025-11-04 12:45:11.259352+01
da1bf9c9-8be1-4b3d-bd04-291a2931a516	0ede49d0-617f-451f-b90e-7fd9631cfa04	2024-12-30	\N	\N	\N	70.750000	\N	GENERATED	2025-11-04 12:45:11.260187+01
2cb52d2b-69f4-44c1-bc96-fab6f813e5ff	0ede49d0-617f-451f-b90e-7fd9631cfa04	2024-12-31	\N	\N	\N	71.390000	\N	GENERATED	2025-11-04 12:45:11.260833+01
9af20d15-ede7-4887-b272-23b4bdf9a64d	0ede49d0-617f-451f-b90e-7fd9631cfa04	2025-01-01	\N	\N	\N	71.440000	\N	GENERATED	2025-11-04 12:45:11.261484+01
a9841f4e-e0ee-42d2-9aa1-5fff9e08b837	0ede49d0-617f-451f-b90e-7fd9631cfa04	2025-01-02	\N	\N	\N	71.170000	\N	GENERATED	2025-11-04 12:45:11.262131+01
d493878d-97db-4f22-93a0-6d6e2fc1d5cf	0ede49d0-617f-451f-b90e-7fd9631cfa04	2025-01-03	\N	\N	\N	70.660000	\N	GENERATED	2025-11-04 12:45:11.262782+01
8f429962-556d-4db7-b591-8ead8625a1f1	0ede49d0-617f-451f-b90e-7fd9631cfa04	2025-01-04	\N	\N	\N	70.260000	\N	GENERATED	2025-11-04 12:45:11.263434+01
199872e9-78cb-4277-9196-ee2e87d9c26f	0ede49d0-617f-451f-b90e-7fd9631cfa04	2025-01-05	\N	\N	\N	71.380000	\N	GENERATED	2025-11-04 12:45:11.264066+01
69b744b5-2701-49f1-bd57-f9dd603b5072	0ede49d0-617f-451f-b90e-7fd9631cfa04	2025-01-06	\N	\N	\N	70.380000	\N	GENERATED	2025-11-04 12:45:11.264722+01
8d46af51-5900-497b-9434-48cb910b2591	0ede49d0-617f-451f-b90e-7fd9631cfa04	2025-01-07	\N	\N	\N	71.230000	\N	GENERATED	2025-11-04 12:45:11.265441+01
9705687d-5cfd-4457-98c0-dab7616405c3	0ede49d0-617f-451f-b90e-7fd9631cfa04	2025-01-08	\N	\N	\N	71.340000	\N	GENERATED	2025-11-04 12:45:11.266481+01
3055bf4a-5803-4276-b600-54d3d19dcdc0	0ede49d0-617f-451f-b90e-7fd9631cfa04	2025-01-09	\N	\N	\N	70.840000	\N	GENERATED	2025-11-04 12:45:11.267197+01
e6e98ff0-665e-4ace-a892-f1e1b2f76ddc	0ede49d0-617f-451f-b90e-7fd9631cfa04	2025-01-10	\N	\N	\N	71.120000	\N	GENERATED	2025-11-04 12:45:11.267854+01
7c99eb32-19be-476f-992d-f52e9fe0abbc	0ede49d0-617f-451f-b90e-7fd9631cfa04	2025-01-11	\N	\N	\N	71.490000	\N	GENERATED	2025-11-04 12:45:11.268524+01
fe2ea26a-eb46-454c-8e77-4b943a9725ef	0ede49d0-617f-451f-b90e-7fd9631cfa04	2025-01-12	\N	\N	\N	70.810000	\N	GENERATED	2025-11-04 12:45:11.269174+01
76e737fb-0592-4043-8b75-a15c94acf38c	0ede49d0-617f-451f-b90e-7fd9631cfa04	2025-01-13	\N	\N	\N	70.460000	\N	GENERATED	2025-11-04 12:45:11.269818+01
db228d69-4667-44e9-a73d-f5718288a132	0ede49d0-617f-451f-b90e-7fd9631cfa04	2025-01-14	\N	\N	\N	70.760000	\N	GENERATED	2025-11-04 12:45:11.270461+01
010a81ab-c4ac-4048-80fe-a98c72749609	0ede49d0-617f-451f-b90e-7fd9631cfa04	2025-01-15	\N	\N	\N	70.570000	\N	GENERATED	2025-11-04 12:45:11.271106+01
b49c674c-3ed1-4716-aa00-bc80b911957b	0ede49d0-617f-451f-b90e-7fd9631cfa04	2025-01-16	\N	\N	\N	71.110000	\N	GENERATED	2025-11-04 12:45:11.27174+01
b9be5f06-aa39-4163-bebe-1f8a168fa7c7	0ede49d0-617f-451f-b90e-7fd9631cfa04	2025-01-17	\N	\N	\N	71.630000	\N	GENERATED	2025-11-04 12:45:11.272432+01
ecf8ce0b-3ffe-423c-bd39-aa32daa6fbd9	0ede49d0-617f-451f-b90e-7fd9631cfa04	2025-01-18	\N	\N	\N	71.320000	\N	GENERATED	2025-11-04 12:45:11.273095+01
63f35bba-68c6-4dc0-b916-4528b5c489c8	0ede49d0-617f-451f-b90e-7fd9631cfa04	2025-01-19	\N	\N	\N	71.470000	\N	GENERATED	2025-11-04 12:45:11.27376+01
b93bf660-d690-429c-8dd9-5d899f57095f	0ede49d0-617f-451f-b90e-7fd9631cfa04	2025-01-20	\N	\N	\N	71.210000	\N	GENERATED	2025-11-04 12:45:11.274516+01
6801e33c-b0a4-42cf-a808-3e81637e36b6	0ede49d0-617f-451f-b90e-7fd9631cfa04	2025-01-21	\N	\N	\N	71.130000	\N	GENERATED	2025-11-04 12:45:11.275181+01
23c9cf88-7def-41c4-94a7-e74e9afd0892	0ede49d0-617f-451f-b90e-7fd9631cfa04	2025-01-22	\N	\N	\N	71.660000	\N	GENERATED	2025-11-04 12:45:11.275829+01
112d2512-00a5-449e-8662-d7f8f19642fb	0ede49d0-617f-451f-b90e-7fd9631cfa04	2025-01-23	\N	\N	\N	70.580000	\N	GENERATED	2025-11-04 12:45:11.276466+01
2ed397f9-6517-41f9-8527-cc3857d25327	0ede49d0-617f-451f-b90e-7fd9631cfa04	2025-01-24	\N	\N	\N	71.440000	\N	GENERATED	2025-11-04 12:45:11.277099+01
fd520c2e-ec54-4280-a4e3-c330ca34455d	0ede49d0-617f-451f-b90e-7fd9631cfa04	2025-01-25	\N	\N	\N	70.910000	\N	GENERATED	2025-11-04 12:45:11.277735+01
829a3dd4-e749-4350-af52-4e65d77d8a44	0ede49d0-617f-451f-b90e-7fd9631cfa04	2025-01-26	\N	\N	\N	71.080000	\N	GENERATED	2025-11-04 12:45:11.278365+01
a8fdb7b3-3813-4d0b-ba53-5e05023b14f1	0ede49d0-617f-451f-b90e-7fd9631cfa04	2025-01-27	\N	\N	\N	71.360000	\N	GENERATED	2025-11-04 12:45:11.279003+01
e0d96e65-e11c-4412-84eb-8682c5adf9b3	0ede49d0-617f-451f-b90e-7fd9631cfa04	2025-01-28	\N	\N	\N	71.080000	\N	GENERATED	2025-11-04 12:45:11.279636+01
c940d3d5-6c0b-4542-bb85-e85bb607a3b1	0ede49d0-617f-451f-b90e-7fd9631cfa04	2025-01-29	\N	\N	\N	70.830000	\N	GENERATED	2025-11-04 12:45:11.280273+01
02ecf78d-6e33-4f87-bedf-e674f4867248	0ede49d0-617f-451f-b90e-7fd9631cfa04	2025-01-30	\N	\N	\N	71.550000	\N	GENERATED	2025-11-04 12:45:11.280996+01
0780dca8-875c-4113-ad5c-e0f856df2943	0ede49d0-617f-451f-b90e-7fd9631cfa04	2025-01-31	\N	\N	\N	71.540000	\N	GENERATED	2025-11-04 12:45:11.281682+01
3abce4a9-6e53-48eb-bfd6-108ce4d18063	0ede49d0-617f-451f-b90e-7fd9631cfa04	2025-02-01	\N	\N	\N	71.380000	\N	GENERATED	2025-11-04 12:45:11.282553+01
50294c4c-af4a-497f-85a5-c26d20d1d04b	0ede49d0-617f-451f-b90e-7fd9631cfa04	2025-02-02	\N	\N	\N	70.730000	\N	GENERATED	2025-11-04 12:45:11.283192+01
d6cfa18a-61ae-487d-aec7-d62e1c657ba9	0ede49d0-617f-451f-b90e-7fd9631cfa04	2025-02-03	\N	\N	\N	71.000000	\N	GENERATED	2025-11-04 12:45:11.283853+01
1863c754-fa6b-49ff-8d19-5170bd37d025	0ede49d0-617f-451f-b90e-7fd9631cfa04	2025-02-04	\N	\N	\N	71.320000	\N	GENERATED	2025-11-04 12:45:11.284502+01
435628e9-9312-4400-80b3-66f225b6afeb	0ede49d0-617f-451f-b90e-7fd9631cfa04	2025-02-05	\N	\N	\N	70.920000	\N	GENERATED	2025-11-04 12:45:11.285268+01
2989b56b-ebd5-4b4d-8277-198fbbc7823e	0ede49d0-617f-451f-b90e-7fd9631cfa04	2025-02-06	\N	\N	\N	70.860000	\N	GENERATED	2025-11-04 12:45:11.285909+01
90f0e013-1c58-4066-9a83-ac5ccf158df7	0ede49d0-617f-451f-b90e-7fd9631cfa04	2025-02-07	\N	\N	\N	70.760000	\N	GENERATED	2025-11-04 12:45:11.286588+01
2ecc7e1f-6797-4e16-9ce8-b4bb5cd71e36	0ede49d0-617f-451f-b90e-7fd9631cfa04	2025-02-08	\N	\N	\N	71.000000	\N	GENERATED	2025-11-04 12:45:11.28726+01
e1eab1ee-19fd-4175-872d-a6807d89bdb4	0ede49d0-617f-451f-b90e-7fd9631cfa04	2025-02-09	\N	\N	\N	71.820000	\N	GENERATED	2025-11-04 12:45:11.287911+01
ee574549-79be-425d-b1f7-2cd1bbdb5ac5	0ede49d0-617f-451f-b90e-7fd9631cfa04	2025-02-10	\N	\N	\N	71.520000	\N	GENERATED	2025-11-04 12:45:11.288584+01
a6180afc-805c-43b7-a532-ecaad475f2ac	0ede49d0-617f-451f-b90e-7fd9631cfa04	2025-02-11	\N	\N	\N	72.030000	\N	GENERATED	2025-11-04 12:45:11.289239+01
e9ced9c3-70d9-4da6-b77b-c61fe74e82f9	0ede49d0-617f-451f-b90e-7fd9631cfa04	2025-02-12	\N	\N	\N	71.840000	\N	GENERATED	2025-11-04 12:45:11.289886+01
b4bf6a66-6c97-465c-8558-23472c39a6db	0ede49d0-617f-451f-b90e-7fd9631cfa04	2025-02-13	\N	\N	\N	71.030000	\N	GENERATED	2025-11-04 12:45:11.290528+01
e62787a4-9d3f-49b1-902d-1a49fe7276f8	0ede49d0-617f-451f-b90e-7fd9631cfa04	2025-02-14	\N	\N	\N	71.200000	\N	GENERATED	2025-11-04 12:45:11.291368+01
d4db390e-161f-4bbe-9315-7e2a067c377b	0ede49d0-617f-451f-b90e-7fd9631cfa04	2025-02-15	\N	\N	\N	71.340000	\N	GENERATED	2025-11-04 12:45:11.29201+01
641c1d9d-baa9-463e-a9ee-016eefe647ee	0ede49d0-617f-451f-b90e-7fd9631cfa04	2025-02-16	\N	\N	\N	71.500000	\N	GENERATED	2025-11-04 12:45:11.292645+01
3b8833b5-4b4b-4bb5-a3fc-b87f3c340bdd	0ede49d0-617f-451f-b90e-7fd9631cfa04	2025-02-17	\N	\N	\N	71.440000	\N	GENERATED	2025-11-04 12:45:11.293303+01
a18154f8-4215-440f-8e6b-15a20cf5b637	0ede49d0-617f-451f-b90e-7fd9631cfa04	2025-02-18	\N	\N	\N	71.310000	\N	GENERATED	2025-11-04 12:45:11.294094+01
3bd720b6-4f61-4cb7-aac1-fb08b4d6db2d	0ede49d0-617f-451f-b90e-7fd9631cfa04	2025-02-19	\N	\N	\N	71.780000	\N	GENERATED	2025-11-04 12:45:11.294746+01
f0b74332-3be6-4d00-85c3-a769fc5274c9	0ede49d0-617f-451f-b90e-7fd9631cfa04	2025-02-20	\N	\N	\N	71.320000	\N	GENERATED	2025-11-04 12:45:11.295396+01
d15e5fae-146f-4e22-9730-55b4fb37ea0f	0ede49d0-617f-451f-b90e-7fd9631cfa04	2025-02-21	\N	\N	\N	72.080000	\N	GENERATED	2025-11-04 12:45:11.296204+01
667cc727-13f4-4358-8323-75f29c75d7b7	0ede49d0-617f-451f-b90e-7fd9631cfa04	2025-02-22	\N	\N	\N	71.360000	\N	GENERATED	2025-11-04 12:45:11.296883+01
63364d4a-5f1a-46df-b712-7321646f0291	0ede49d0-617f-451f-b90e-7fd9631cfa04	2025-02-23	\N	\N	\N	71.270000	\N	GENERATED	2025-11-04 12:45:11.297549+01
2dd9673a-9248-4836-bc2a-bc700a2a1c03	0ede49d0-617f-451f-b90e-7fd9631cfa04	2025-02-24	\N	\N	\N	71.390000	\N	GENERATED	2025-11-04 12:45:11.298194+01
9333024b-8cab-41fa-8d1d-60a6b22cb726	0ede49d0-617f-451f-b90e-7fd9631cfa04	2025-02-25	\N	\N	\N	71.790000	\N	GENERATED	2025-11-04 12:45:11.298938+01
1d871de0-9bb5-49bf-9549-5e1ad8a970db	0ede49d0-617f-451f-b90e-7fd9631cfa04	2025-02-26	\N	\N	\N	72.220000	\N	GENERATED	2025-11-04 12:45:11.299582+01
34f3dd0a-ab20-4c6c-b635-c1d090e3f5c1	0ede49d0-617f-451f-b90e-7fd9631cfa04	2025-02-27	\N	\N	\N	71.070000	\N	GENERATED	2025-11-04 12:45:11.300218+01
ecf02b02-1e38-4dc2-8ed5-9ccf9ca61625	0ede49d0-617f-451f-b90e-7fd9631cfa04	2025-02-28	\N	\N	\N	72.250000	\N	GENERATED	2025-11-04 12:45:11.300854+01
f603a3c3-1bc4-4454-bc8f-53cbbbc7b50a	0ede49d0-617f-451f-b90e-7fd9631cfa04	2025-03-01	\N	\N	\N	71.640000	\N	GENERATED	2025-11-04 12:45:11.301677+01
62b0c573-59be-404c-99d8-c26e6774c2fc	0ede49d0-617f-451f-b90e-7fd9631cfa04	2025-03-02	\N	\N	\N	72.330000	\N	GENERATED	2025-11-04 12:45:11.302727+01
84a0899f-d790-4611-9077-95fe12b2ae5e	0ede49d0-617f-451f-b90e-7fd9631cfa04	2025-03-03	\N	\N	\N	72.360000	\N	GENERATED	2025-11-04 12:45:11.303658+01
84a30249-2cfb-4a2f-affe-9052e310dd53	0ede49d0-617f-451f-b90e-7fd9631cfa04	2025-03-04	\N	\N	\N	71.150000	\N	GENERATED	2025-11-04 12:45:11.304482+01
9e624e2b-bdb0-418b-b20e-b77d663a5a69	0ede49d0-617f-451f-b90e-7fd9631cfa04	2025-03-05	\N	\N	\N	72.160000	\N	GENERATED	2025-11-04 12:45:11.305137+01
f6185651-215b-4b20-93d5-9205ba5b525a	0ede49d0-617f-451f-b90e-7fd9631cfa04	2025-03-06	\N	\N	\N	71.630000	\N	GENERATED	2025-11-04 12:45:11.30579+01
a91fb478-40af-4a7c-83c4-58c6ba434034	0ede49d0-617f-451f-b90e-7fd9631cfa04	2025-03-07	\N	\N	\N	72.120000	\N	GENERATED	2025-11-04 12:45:11.306447+01
61aabf45-7081-40d0-add3-d1527f0f0681	0ede49d0-617f-451f-b90e-7fd9631cfa04	2025-03-08	\N	\N	\N	71.960000	\N	GENERATED	2025-11-04 12:45:11.307087+01
725d3012-c11f-4d08-a01c-f7472eab9d73	0ede49d0-617f-451f-b90e-7fd9631cfa04	2025-03-09	\N	\N	\N	71.460000	\N	GENERATED	2025-11-04 12:45:11.307731+01
a794c69d-0163-4a0e-a99a-aca5151c09a0	0ede49d0-617f-451f-b90e-7fd9631cfa04	2025-03-10	\N	\N	\N	71.760000	\N	GENERATED	2025-11-04 12:45:11.308421+01
7f69f89c-4636-4056-add8-b594685f72c7	0ede49d0-617f-451f-b90e-7fd9631cfa04	2025-03-11	\N	\N	\N	71.720000	\N	GENERATED	2025-11-04 12:45:11.30908+01
73b81117-67d7-44bd-bc96-eef0c81f21bd	0ede49d0-617f-451f-b90e-7fd9631cfa04	2025-03-12	\N	\N	\N	72.500000	\N	GENERATED	2025-11-04 12:45:11.30973+01
438d4143-d156-4c27-a10d-b74c988bd3df	0ede49d0-617f-451f-b90e-7fd9631cfa04	2025-03-13	\N	\N	\N	71.500000	\N	GENERATED	2025-11-04 12:45:11.310374+01
04effa46-9e38-458c-9654-246a2b91c580	0ede49d0-617f-451f-b90e-7fd9631cfa04	2025-03-14	\N	\N	\N	72.520000	\N	GENERATED	2025-11-04 12:45:11.31101+01
6342f37b-716f-4749-8236-6777adc6b3af	0ede49d0-617f-451f-b90e-7fd9631cfa04	2025-03-15	\N	\N	\N	71.990000	\N	GENERATED	2025-11-04 12:45:11.311847+01
6b4dfa11-e6db-445c-9693-afc98adfe486	0ede49d0-617f-451f-b90e-7fd9631cfa04	2025-03-16	\N	\N	\N	71.880000	\N	GENERATED	2025-11-04 12:45:11.312557+01
abe68d38-355b-4899-9b9c-8db3078eef5e	0ede49d0-617f-451f-b90e-7fd9631cfa04	2025-03-17	\N	\N	\N	72.510000	\N	GENERATED	2025-11-04 12:45:11.313208+01
86059013-1aa3-440e-b2c6-95847e22e6d3	0ede49d0-617f-451f-b90e-7fd9631cfa04	2025-03-18	\N	\N	\N	71.960000	\N	GENERATED	2025-11-04 12:45:11.313858+01
89fbb69a-ccaa-4fad-bb35-2ae871ee1a32	0ede49d0-617f-451f-b90e-7fd9631cfa04	2025-03-19	\N	\N	\N	72.020000	\N	GENERATED	2025-11-04 12:45:11.314519+01
3019930d-7fac-4d75-bed9-6ce019bfbe6c	0ede49d0-617f-451f-b90e-7fd9631cfa04	2025-03-20	\N	\N	\N	71.470000	\N	GENERATED	2025-11-04 12:45:11.315158+01
9f096ec0-6dca-4d85-aeed-bf948157e149	0ede49d0-617f-451f-b90e-7fd9631cfa04	2025-03-21	\N	\N	\N	72.750000	\N	GENERATED	2025-11-04 12:45:11.315815+01
89b80e2e-c9e9-44db-bcda-98e561557097	0ede49d0-617f-451f-b90e-7fd9631cfa04	2025-03-22	\N	\N	\N	72.020000	\N	GENERATED	2025-11-04 12:45:11.31646+01
8938b57b-8c30-4101-b631-3655934eca7f	0ede49d0-617f-451f-b90e-7fd9631cfa04	2025-03-23	\N	\N	\N	72.260000	\N	GENERATED	2025-11-04 12:45:11.317087+01
fb1b22a5-db3d-4fbc-9635-83623523612e	0ede49d0-617f-451f-b90e-7fd9631cfa04	2025-03-24	\N	\N	\N	72.350000	\N	GENERATED	2025-11-04 12:45:11.317758+01
1b552a72-443f-45b1-b24e-9da3237befa1	0ede49d0-617f-451f-b90e-7fd9631cfa04	2025-03-25	\N	\N	\N	72.850000	\N	GENERATED	2025-11-04 12:45:11.318383+01
d620c49d-3df1-49cd-b655-8778e6abcf55	0ede49d0-617f-451f-b90e-7fd9631cfa04	2025-03-26	\N	\N	\N	72.830000	\N	GENERATED	2025-11-04 12:45:11.319024+01
8cc84673-a254-4105-8bd0-39151750a9db	0ede49d0-617f-451f-b90e-7fd9631cfa04	2025-03-27	\N	\N	\N	72.520000	\N	GENERATED	2025-11-04 12:45:11.319658+01
3b4d813a-3501-490d-971d-32b64083bc27	0ede49d0-617f-451f-b90e-7fd9631cfa04	2025-03-28	\N	\N	\N	71.750000	\N	GENERATED	2025-11-04 12:45:11.320285+01
8321f7ac-fe5c-4099-b194-7179550dfa5b	0ede49d0-617f-451f-b90e-7fd9631cfa04	2025-03-29	\N	\N	\N	72.090000	\N	GENERATED	2025-11-04 12:45:11.32092+01
24376719-275f-4a7f-92c9-5a09ca086734	0ede49d0-617f-451f-b90e-7fd9631cfa04	2025-03-30	\N	\N	\N	72.480000	\N	GENERATED	2025-11-04 12:45:11.321561+01
3de65694-317b-44fd-87c8-cf554ad4b20d	0ede49d0-617f-451f-b90e-7fd9631cfa04	2025-03-31	\N	\N	\N	72.120000	\N	GENERATED	2025-11-04 12:45:11.32263+01
d676c914-77ff-4bd6-9d78-672bc546ec90	0ede49d0-617f-451f-b90e-7fd9631cfa04	2025-04-01	\N	\N	\N	71.780000	\N	GENERATED	2025-11-04 12:45:11.323298+01
c19603f4-3763-4a4e-b695-bd60172eff5c	0ede49d0-617f-451f-b90e-7fd9631cfa04	2025-04-02	\N	\N	\N	72.300000	\N	GENERATED	2025-11-04 12:45:11.323934+01
d8ecc2c2-a8bb-4f76-a3bd-fc922d9625d8	0ede49d0-617f-451f-b90e-7fd9631cfa04	2025-04-03	\N	\N	\N	71.880000	\N	GENERATED	2025-11-04 12:45:11.324573+01
f6097102-bdfe-4748-b367-876848378d4b	0ede49d0-617f-451f-b90e-7fd9631cfa04	2025-04-04	\N	\N	\N	72.240000	\N	GENERATED	2025-11-04 12:45:11.325611+01
a4b81af1-ad24-4fa5-a764-44ead0dd83f6	0ede49d0-617f-451f-b90e-7fd9631cfa04	2025-04-05	\N	\N	\N	72.930000	\N	GENERATED	2025-11-04 12:45:11.326251+01
be3c5d9b-9f79-46d9-ae67-d349914cba2b	0ede49d0-617f-451f-b90e-7fd9631cfa04	2025-04-06	\N	\N	\N	72.180000	\N	GENERATED	2025-11-04 12:45:11.327246+01
fb3fa8f6-9fa9-402d-b899-3876e946b273	0ede49d0-617f-451f-b90e-7fd9631cfa04	2025-04-07	\N	\N	\N	72.100000	\N	GENERATED	2025-11-04 12:45:11.327925+01
458a95ac-86d8-4f62-8d42-ea2871248921	0ede49d0-617f-451f-b90e-7fd9631cfa04	2025-04-08	\N	\N	\N	72.650000	\N	GENERATED	2025-11-04 12:45:11.328574+01
928e9615-ab11-460c-ba52-939b4adc52b6	0ede49d0-617f-451f-b90e-7fd9631cfa04	2025-04-09	\N	\N	\N	72.630000	\N	GENERATED	2025-11-04 12:45:11.329216+01
8dcd5d37-f278-4481-8fc4-11ee903e7572	0ede49d0-617f-451f-b90e-7fd9631cfa04	2025-04-10	\N	\N	\N	72.400000	\N	GENERATED	2025-11-04 12:45:11.329874+01
78d51133-f55b-4811-ba4b-99dc6f3aa342	0ede49d0-617f-451f-b90e-7fd9631cfa04	2025-04-11	\N	\N	\N	72.530000	\N	GENERATED	2025-11-04 12:45:11.330528+01
4552dc84-4a6d-4584-bcd0-fe319f4496c6	0ede49d0-617f-451f-b90e-7fd9631cfa04	2025-04-12	\N	\N	\N	72.170000	\N	GENERATED	2025-11-04 12:45:11.331164+01
b5ec4565-3b51-47dd-b059-d2dc2c5fcda2	0ede49d0-617f-451f-b90e-7fd9631cfa04	2025-04-13	\N	\N	\N	73.120000	\N	GENERATED	2025-11-04 12:45:11.331802+01
31d6bb1b-92d4-42de-bfd1-371d52c55ee6	0ede49d0-617f-451f-b90e-7fd9631cfa04	2025-04-14	\N	\N	\N	72.020000	\N	GENERATED	2025-11-04 12:45:11.332745+01
1d4cbbab-d34d-46f2-a0a6-fe1f79052391	0ede49d0-617f-451f-b90e-7fd9631cfa04	2025-04-15	\N	\N	\N	72.470000	\N	GENERATED	2025-11-04 12:45:11.333403+01
a036e187-e51a-4350-812a-f282f2498d6e	0ede49d0-617f-451f-b90e-7fd9631cfa04	2025-04-16	\N	\N	\N	72.720000	\N	GENERATED	2025-11-04 12:45:11.334129+01
b312122a-7b8f-458a-9b70-18c5064641f1	0ede49d0-617f-451f-b90e-7fd9631cfa04	2025-04-17	\N	\N	\N	72.250000	\N	GENERATED	2025-11-04 12:45:11.334777+01
68a3e2ef-4f96-40bd-bef5-62679da98829	0ede49d0-617f-451f-b90e-7fd9631cfa04	2025-04-18	\N	\N	\N	72.830000	\N	GENERATED	2025-11-04 12:45:11.335411+01
2f67b2f8-b950-491b-a71c-335ae34b75ba	0ede49d0-617f-451f-b90e-7fd9631cfa04	2025-04-19	\N	\N	\N	73.160000	\N	GENERATED	2025-11-04 12:45:11.33605+01
b84db3f3-b09a-4fd9-ba72-2e457fba5f2b	0ede49d0-617f-451f-b90e-7fd9631cfa04	2025-04-20	\N	\N	\N	73.220000	\N	GENERATED	2025-11-04 12:45:11.336689+01
ee23456c-f914-404d-a501-00dea8ac8b7c	0ede49d0-617f-451f-b90e-7fd9631cfa04	2025-04-21	\N	\N	\N	72.710000	\N	GENERATED	2025-11-04 12:45:11.33732+01
ff5f5b6b-a4ae-4b7c-868f-c9ae8e8d2b05	0ede49d0-617f-451f-b90e-7fd9631cfa04	2025-04-22	\N	\N	\N	72.500000	\N	GENERATED	2025-11-04 12:45:11.338051+01
892efa4e-1cba-489e-aec7-0c7ac147fa62	0ede49d0-617f-451f-b90e-7fd9631cfa04	2025-04-23	\N	\N	\N	73.100000	\N	GENERATED	2025-11-04 12:45:11.338692+01
77752828-2964-414a-9e4d-6924917a6ce5	0ede49d0-617f-451f-b90e-7fd9631cfa04	2025-04-24	\N	\N	\N	72.660000	\N	GENERATED	2025-11-04 12:45:11.339343+01
66e4731d-d86d-4de6-8e2b-39a0d6fef0ee	0ede49d0-617f-451f-b90e-7fd9631cfa04	2025-04-25	\N	\N	\N	73.080000	\N	GENERATED	2025-11-04 12:45:11.340012+01
fede8888-13f6-48cd-af33-3f57dd685965	0ede49d0-617f-451f-b90e-7fd9631cfa04	2025-04-26	\N	\N	\N	72.780000	\N	GENERATED	2025-11-04 12:45:11.34066+01
d010b673-bec6-4217-bb93-13a3ec6790aa	0ede49d0-617f-451f-b90e-7fd9631cfa04	2025-04-27	\N	\N	\N	73.180000	\N	GENERATED	2025-11-04 12:45:11.341305+01
aa5b8017-8328-4107-ba36-a0ccdca1ba4c	0ede49d0-617f-451f-b90e-7fd9631cfa04	2025-04-28	\N	\N	\N	73.360000	\N	GENERATED	2025-11-04 12:45:11.341998+01
98f4a0db-5c74-4d31-ba78-63ff6c4ea124	0ede49d0-617f-451f-b90e-7fd9631cfa04	2025-04-29	\N	\N	\N	73.380000	\N	GENERATED	2025-11-04 12:45:11.342715+01
8e8ab292-6083-4d84-be0d-dfa1668c5183	0ede49d0-617f-451f-b90e-7fd9631cfa04	2025-04-30	\N	\N	\N	73.040000	\N	GENERATED	2025-11-04 12:45:11.343398+01
ad563050-5a7c-47b9-b8c1-8b16fe19b700	0ede49d0-617f-451f-b90e-7fd9631cfa04	2025-05-01	\N	\N	\N	72.540000	\N	GENERATED	2025-11-04 12:45:11.34405+01
80f76aa0-6eaa-427c-af1d-3491336b0635	0ede49d0-617f-451f-b90e-7fd9631cfa04	2025-05-02	\N	\N	\N	72.230000	\N	GENERATED	2025-11-04 12:45:11.344699+01
7bd94e78-7dbf-461c-a9e6-1873722c5c7f	0ede49d0-617f-451f-b90e-7fd9631cfa04	2025-05-03	\N	\N	\N	72.420000	\N	GENERATED	2025-11-04 12:45:11.345349+01
cbaa27cf-6c2f-4a5e-aa02-4a579f58d444	0ede49d0-617f-451f-b90e-7fd9631cfa04	2025-05-04	\N	\N	\N	72.860000	\N	GENERATED	2025-11-04 12:45:11.345982+01
8f3deaf0-c030-456a-8fc8-44a3310d74c7	0ede49d0-617f-451f-b90e-7fd9631cfa04	2025-05-05	\N	\N	\N	73.380000	\N	GENERATED	2025-11-04 12:45:11.346631+01
e059e50f-86f8-4e05-95d0-a60184461921	0ede49d0-617f-451f-b90e-7fd9631cfa04	2025-05-06	\N	\N	\N	72.540000	\N	GENERATED	2025-11-04 12:45:11.347283+01
f4fc1162-469c-4e21-94c4-38b9678be4de	0ede49d0-617f-451f-b90e-7fd9631cfa04	2025-05-07	\N	\N	\N	73.360000	\N	GENERATED	2025-11-04 12:45:11.347931+01
77d70e97-89a4-4cd7-93fc-be4bc533dc88	0ede49d0-617f-451f-b90e-7fd9631cfa04	2025-05-08	\N	\N	\N	72.800000	\N	GENERATED	2025-11-04 12:45:11.348569+01
06630cc1-f875-4feb-a631-8ea9f79dc700	0ede49d0-617f-451f-b90e-7fd9631cfa04	2025-05-09	\N	\N	\N	72.730000	\N	GENERATED	2025-11-04 12:45:11.34921+01
1c33cf70-63f3-428b-891c-804a14db931b	0ede49d0-617f-451f-b90e-7fd9631cfa04	2025-05-10	\N	\N	\N	73.350000	\N	GENERATED	2025-11-04 12:45:11.349842+01
0208760d-b3d9-4d72-b940-e1d9c0edd1fe	0ede49d0-617f-451f-b90e-7fd9631cfa04	2025-05-11	\N	\N	\N	72.210000	\N	GENERATED	2025-11-04 12:45:11.350481+01
8b604c35-e203-408a-97f0-bbe4a0d2882d	0ede49d0-617f-451f-b90e-7fd9631cfa04	2025-05-12	\N	\N	\N	73.540000	\N	GENERATED	2025-11-04 12:45:11.351112+01
6c67d166-9bdf-40a2-956d-01353abcf14d	0ede49d0-617f-451f-b90e-7fd9631cfa04	2025-05-13	\N	\N	\N	72.260000	\N	GENERATED	2025-11-04 12:45:11.351764+01
a16dcd3f-2480-4de7-9229-c1222f669e9a	0ede49d0-617f-451f-b90e-7fd9631cfa04	2025-05-14	\N	\N	\N	73.220000	\N	GENERATED	2025-11-04 12:45:11.352406+01
ae9ce8d0-6038-486f-9401-a558521ad35a	0ede49d0-617f-451f-b90e-7fd9631cfa04	2025-05-15	\N	\N	\N	73.210000	\N	GENERATED	2025-11-04 12:45:11.353041+01
3c5dd6bd-9122-49af-be26-05fd9a6cacea	0ede49d0-617f-451f-b90e-7fd9631cfa04	2025-05-16	\N	\N	\N	73.320000	\N	GENERATED	2025-11-04 12:45:11.353674+01
2c993972-bf07-4189-8629-4f7bc7181fc5	0ede49d0-617f-451f-b90e-7fd9631cfa04	2025-05-17	\N	\N	\N	72.700000	\N	GENERATED	2025-11-04 12:45:11.354385+01
409d0d66-df93-4f6d-a71b-7bd2dc18544f	0ede49d0-617f-451f-b90e-7fd9631cfa04	2025-05-18	\N	\N	\N	73.160000	\N	GENERATED	2025-11-04 12:45:11.355014+01
9230ae1b-bd53-4305-aac9-61ca6a374545	0ede49d0-617f-451f-b90e-7fd9631cfa04	2025-05-19	\N	\N	\N	73.660000	\N	GENERATED	2025-11-04 12:45:11.355647+01
0d6a522f-ad61-40f3-aed8-2c9da48d57c7	0ede49d0-617f-451f-b90e-7fd9631cfa04	2025-05-20	\N	\N	\N	73.350000	\N	GENERATED	2025-11-04 12:45:11.356291+01
d7a1ca23-4046-4919-a85a-73c9d94ba8cc	0ede49d0-617f-451f-b90e-7fd9631cfa04	2025-05-21	\N	\N	\N	72.740000	\N	GENERATED	2025-11-04 12:45:11.356933+01
d2a47ee8-88c1-49fe-8cce-77babeff7865	0ede49d0-617f-451f-b90e-7fd9631cfa04	2025-05-22	\N	\N	\N	72.600000	\N	GENERATED	2025-11-04 12:45:11.357797+01
8e9a99a1-d587-49f8-9b00-4ee7ec6de5bf	0ede49d0-617f-451f-b90e-7fd9631cfa04	2025-05-23	\N	\N	\N	72.890000	\N	GENERATED	2025-11-04 12:45:11.358811+01
53c67018-ae8f-41d2-911d-80f060eff536	0ede49d0-617f-451f-b90e-7fd9631cfa04	2025-05-24	\N	\N	\N	73.070000	\N	GENERATED	2025-11-04 12:45:11.359471+01
9c636f76-1481-43c2-b369-f602f8e31c39	0ede49d0-617f-451f-b90e-7fd9631cfa04	2025-05-25	\N	\N	\N	73.180000	\N	GENERATED	2025-11-04 12:45:11.360116+01
729e29b3-b7d6-4a98-9a92-d6d08754bf8d	0ede49d0-617f-451f-b90e-7fd9631cfa04	2025-05-26	\N	\N	\N	72.780000	\N	GENERATED	2025-11-04 12:45:11.360768+01
b0ee4941-00ab-4b97-a13e-03d5e41d3407	0ede49d0-617f-451f-b90e-7fd9631cfa04	2025-05-27	\N	\N	\N	73.720000	\N	GENERATED	2025-11-04 12:45:11.361407+01
23e5a6e5-24ae-4ad9-ae5d-6e95e03808a3	0ede49d0-617f-451f-b90e-7fd9631cfa04	2025-05-28	\N	\N	\N	73.230000	\N	GENERATED	2025-11-04 12:45:11.362034+01
49246f05-4f9a-4199-b332-11513d47be08	0ede49d0-617f-451f-b90e-7fd9631cfa04	2025-05-29	\N	\N	\N	72.860000	\N	GENERATED	2025-11-04 12:45:11.362696+01
c9d826fc-76e7-4da6-841c-18fbb0f78b4b	0ede49d0-617f-451f-b90e-7fd9631cfa04	2025-05-30	\N	\N	\N	73.210000	\N	GENERATED	2025-11-04 12:45:11.363452+01
ed0bffa2-f77f-4de0-90a3-a6a89e3463ee	0ede49d0-617f-451f-b90e-7fd9631cfa04	2025-05-31	\N	\N	\N	73.480000	\N	GENERATED	2025-11-04 12:45:11.364179+01
cc9e4d4d-0416-4c1b-84f3-164c1ca821d5	0ede49d0-617f-451f-b90e-7fd9631cfa04	2025-06-01	\N	\N	\N	73.130000	\N	GENERATED	2025-11-04 12:45:11.364828+01
b8561732-9169-40c8-8d80-18906269e6d9	0ede49d0-617f-451f-b90e-7fd9631cfa04	2025-06-02	\N	\N	\N	73.490000	\N	GENERATED	2025-11-04 12:45:11.365465+01
9d009875-95a0-41e6-b845-444ed89eba2b	0ede49d0-617f-451f-b90e-7fd9631cfa04	2025-06-03	\N	\N	\N	73.550000	\N	GENERATED	2025-11-04 12:45:11.366097+01
4c5f7f8e-fe9b-4af1-b5c0-f8dee0cc84c1	0ede49d0-617f-451f-b90e-7fd9631cfa04	2025-06-04	\N	\N	\N	73.100000	\N	GENERATED	2025-11-04 12:45:11.366807+01
d77a6875-6ea5-46a9-9d26-db7323064b31	0ede49d0-617f-451f-b90e-7fd9631cfa04	2025-06-05	\N	\N	\N	72.870000	\N	GENERATED	2025-11-04 12:45:11.367459+01
b6fbc411-d46c-4306-9381-ef954157c2f6	0ede49d0-617f-451f-b90e-7fd9631cfa04	2025-06-06	\N	\N	\N	73.110000	\N	GENERATED	2025-11-04 12:45:11.368108+01
9cbcb080-11e2-4154-918f-dd31fbfec047	0ede49d0-617f-451f-b90e-7fd9631cfa04	2025-06-07	\N	\N	\N	73.950000	\N	GENERATED	2025-11-04 12:45:11.368743+01
3211a7bf-75ba-4a12-a412-1842232f0ddc	0ede49d0-617f-451f-b90e-7fd9631cfa04	2025-06-08	\N	\N	\N	72.970000	\N	GENERATED	2025-11-04 12:45:11.369386+01
dcd138bf-a435-453f-ab0f-a043d154c616	0ede49d0-617f-451f-b90e-7fd9631cfa04	2025-06-09	\N	\N	\N	73.250000	\N	GENERATED	2025-11-04 12:45:11.370018+01
88ead429-453b-4ca0-9550-cfa22a430b3c	0ede49d0-617f-451f-b90e-7fd9631cfa04	2025-06-10	\N	\N	\N	72.720000	\N	GENERATED	2025-11-04 12:45:11.370659+01
77e609bc-5286-4162-b97b-9acf695f628b	0ede49d0-617f-451f-b90e-7fd9631cfa04	2025-06-11	\N	\N	\N	73.870000	\N	GENERATED	2025-11-04 12:45:11.371295+01
66a88ff9-69b3-47e0-8e93-e1ae499cf79c	0ede49d0-617f-451f-b90e-7fd9631cfa04	2025-06-12	\N	\N	\N	73.690000	\N	GENERATED	2025-11-04 12:45:11.371978+01
1eb6f09c-3f72-44fc-81ed-f82363769363	0ede49d0-617f-451f-b90e-7fd9631cfa04	2025-06-13	\N	\N	\N	73.720000	\N	GENERATED	2025-11-04 12:45:11.37261+01
3c67cafa-8a53-4b05-ae18-70420d935584	0ede49d0-617f-451f-b90e-7fd9631cfa04	2025-06-14	\N	\N	\N	73.800000	\N	GENERATED	2025-11-04 12:45:11.37337+01
53276ef1-3329-43b4-928a-d2622a8a2e47	0ede49d0-617f-451f-b90e-7fd9631cfa04	2025-06-15	\N	\N	\N	72.770000	\N	GENERATED	2025-11-04 12:45:11.374222+01
b9181676-cceb-435f-b043-e7c4151f334a	0ede49d0-617f-451f-b90e-7fd9631cfa04	2025-06-16	\N	\N	\N	72.810000	\N	GENERATED	2025-11-04 12:45:11.374886+01
3a0e1bf5-e873-408a-8b93-b9fad53de07e	0ede49d0-617f-451f-b90e-7fd9631cfa04	2025-06-17	\N	\N	\N	73.110000	\N	GENERATED	2025-11-04 12:45:11.375615+01
6116ff90-a5e9-44e6-a113-fe784bb71e61	0ede49d0-617f-451f-b90e-7fd9631cfa04	2025-06-18	\N	\N	\N	73.880000	\N	GENERATED	2025-11-04 12:45:11.376256+01
988287bf-9f10-4e87-b421-80c241c95afc	0ede49d0-617f-451f-b90e-7fd9631cfa04	2025-06-19	\N	\N	\N	73.750000	\N	GENERATED	2025-11-04 12:45:11.376907+01
529ba682-353a-433d-b3ab-ea07d5580233	0ede49d0-617f-451f-b90e-7fd9631cfa04	2025-06-20	\N	\N	\N	73.140000	\N	GENERATED	2025-11-04 12:45:11.377551+01
f0a8e0a4-4b04-4471-a4b9-98e0755a5c33	0ede49d0-617f-451f-b90e-7fd9631cfa04	2025-06-21	\N	\N	\N	73.290000	\N	GENERATED	2025-11-04 12:45:11.378198+01
40edad44-c0ec-4267-b973-7a90beebc166	0ede49d0-617f-451f-b90e-7fd9631cfa04	2025-06-22	\N	\N	\N	73.870000	\N	GENERATED	2025-11-04 12:45:11.378848+01
c95be7f8-0130-4f44-805f-49c4a8535cde	0ede49d0-617f-451f-b90e-7fd9631cfa04	2025-06-23	\N	\N	\N	73.560000	\N	GENERATED	2025-11-04 12:45:11.379494+01
5c5274d6-b535-407b-8078-22e02f1480a1	0ede49d0-617f-451f-b90e-7fd9631cfa04	2025-06-24	\N	\N	\N	74.250000	\N	GENERATED	2025-11-04 12:45:11.380125+01
c8f23977-ad0d-48f1-aa54-01cc7ef84b03	0ede49d0-617f-451f-b90e-7fd9631cfa04	2025-06-25	\N	\N	\N	73.530000	\N	GENERATED	2025-11-04 12:45:11.380749+01
ebf98cef-66cc-4e46-824a-894e185e659b	0ede49d0-617f-451f-b90e-7fd9631cfa04	2025-06-26	\N	\N	\N	73.190000	\N	GENERATED	2025-11-04 12:45:11.381436+01
9d0a8ce6-a664-44f7-b39c-cc2843c72661	0ede49d0-617f-451f-b90e-7fd9631cfa04	2025-06-27	\N	\N	\N	73.460000	\N	GENERATED	2025-11-04 12:45:11.38207+01
245d3abf-3c6e-45e2-b3bf-6086f784e697	0ede49d0-617f-451f-b90e-7fd9631cfa04	2025-06-28	\N	\N	\N	73.350000	\N	GENERATED	2025-11-04 12:45:11.382704+01
816b643f-04ec-48cf-8736-5e2ff1cefb0e	0ede49d0-617f-451f-b90e-7fd9631cfa04	2025-06-29	\N	\N	\N	73.180000	\N	GENERATED	2025-11-04 12:45:11.383336+01
306d82a4-f335-470c-a2f5-0ba71e905755	0ede49d0-617f-451f-b90e-7fd9631cfa04	2025-06-30	\N	\N	\N	73.680000	\N	GENERATED	2025-11-04 12:45:11.383966+01
e5fc6fb0-992a-4bba-85d3-252d43321ac6	0ede49d0-617f-451f-b90e-7fd9631cfa04	2025-07-01	\N	\N	\N	73.720000	\N	GENERATED	2025-11-04 12:45:11.384622+01
2585fd46-4dac-411f-be42-aeba57220068	0ede49d0-617f-451f-b90e-7fd9631cfa04	2025-07-02	\N	\N	\N	73.270000	\N	GENERATED	2025-11-04 12:45:11.385259+01
d2bc881c-acf7-41e0-b190-e7b04d5ea676	0ede49d0-617f-451f-b90e-7fd9631cfa04	2025-07-03	\N	\N	\N	74.310000	\N	GENERATED	2025-11-04 12:45:11.385894+01
aa2576f0-f451-420f-83c6-247f458a1a91	0ede49d0-617f-451f-b90e-7fd9631cfa04	2025-07-04	\N	\N	\N	73.790000	\N	GENERATED	2025-11-04 12:45:11.386552+01
bd606fcf-91cf-4bcf-b88f-a093e6476f66	0ede49d0-617f-451f-b90e-7fd9631cfa04	2025-07-05	\N	\N	\N	74.010000	\N	GENERATED	2025-11-04 12:45:11.387202+01
c75e327f-0e97-4843-a464-7f5148e9b2a1	0ede49d0-617f-451f-b90e-7fd9631cfa04	2025-07-06	\N	\N	\N	73.330000	\N	GENERATED	2025-11-04 12:45:11.387859+01
f4e15d75-dce6-4825-bc80-24105d66213e	0ede49d0-617f-451f-b90e-7fd9631cfa04	2025-07-07	\N	\N	\N	73.970000	\N	GENERATED	2025-11-04 12:45:11.388486+01
106eeac5-d47c-44cb-a594-fd68e624233a	0ede49d0-617f-451f-b90e-7fd9631cfa04	2025-07-08	\N	\N	\N	74.260000	\N	GENERATED	2025-11-04 12:45:11.389266+01
00cae610-6e37-4f8b-9cb9-016f36c58d89	0ede49d0-617f-451f-b90e-7fd9631cfa04	2025-07-09	\N	\N	\N	73.290000	\N	GENERATED	2025-11-04 12:45:11.38993+01
0d332ded-72e1-4871-b777-070c6ec2b866	0ede49d0-617f-451f-b90e-7fd9631cfa04	2025-07-10	\N	\N	\N	73.280000	\N	GENERATED	2025-11-04 12:45:11.39058+01
64e2dc7e-29ff-487d-ab85-0973d5b44127	0ede49d0-617f-451f-b90e-7fd9631cfa04	2025-07-11	\N	\N	\N	73.640000	\N	GENERATED	2025-11-04 12:45:11.391228+01
5749b61e-04f5-4b63-af42-f4cebdb91d59	0ede49d0-617f-451f-b90e-7fd9631cfa04	2025-07-12	\N	\N	\N	74.500000	\N	GENERATED	2025-11-04 12:45:11.391876+01
ce3597fe-0b39-46e3-af90-a825107789d1	0ede49d0-617f-451f-b90e-7fd9631cfa04	2025-07-13	\N	\N	\N	74.050000	\N	GENERATED	2025-11-04 12:45:11.392508+01
500d5414-3d6a-476f-a29f-b4d058faaa47	0ede49d0-617f-451f-b90e-7fd9631cfa04	2025-07-14	\N	\N	\N	73.560000	\N	GENERATED	2025-11-04 12:45:11.393173+01
a4bd151b-da06-4d48-88ef-dfc0096f6170	0ede49d0-617f-451f-b90e-7fd9631cfa04	2025-07-15	\N	\N	\N	74.320000	\N	GENERATED	2025-11-04 12:45:11.393828+01
175e5b47-c308-4663-92f9-e561531f858d	0ede49d0-617f-451f-b90e-7fd9631cfa04	2025-07-16	\N	\N	\N	73.660000	\N	GENERATED	2025-11-04 12:45:11.394566+01
a462f6e3-57bc-4d37-8665-dd4dabba9d91	0ede49d0-617f-451f-b90e-7fd9631cfa04	2025-07-17	\N	\N	\N	73.720000	\N	GENERATED	2025-11-04 12:45:11.395214+01
4f993eb9-339e-49e1-a3a2-066413490919	0ede49d0-617f-451f-b90e-7fd9631cfa04	2025-07-18	\N	\N	\N	73.340000	\N	GENERATED	2025-11-04 12:45:11.395853+01
ba3d76d9-26de-42ca-90c3-acc4fe8a765f	0ede49d0-617f-451f-b90e-7fd9631cfa04	2025-07-19	\N	\N	\N	74.560000	\N	GENERATED	2025-11-04 12:45:11.396481+01
3bd2d7ce-d42d-44dc-b126-63717758551c	0ede49d0-617f-451f-b90e-7fd9631cfa04	2025-07-20	\N	\N	\N	74.170000	\N	GENERATED	2025-11-04 12:45:11.397233+01
75dee13b-5428-42cf-9286-6a717c8aa7d7	0ede49d0-617f-451f-b90e-7fd9631cfa04	2025-07-21	\N	\N	\N	74.360000	\N	GENERATED	2025-11-04 12:45:11.397889+01
8667ef33-dc9a-4e7b-a12f-599c919bee24	0ede49d0-617f-451f-b90e-7fd9631cfa04	2025-07-22	\N	\N	\N	73.340000	\N	GENERATED	2025-11-04 12:45:11.398529+01
880f3061-9d64-4359-a5a0-727ebc7830eb	0ede49d0-617f-451f-b90e-7fd9631cfa04	2025-07-23	\N	\N	\N	73.630000	\N	GENERATED	2025-11-04 12:45:11.399161+01
3fa04e2a-aecf-42e6-b8dc-da8746e806ae	0ede49d0-617f-451f-b90e-7fd9631cfa04	2025-07-24	\N	\N	\N	73.690000	\N	GENERATED	2025-11-04 12:45:11.399801+01
22d91bdb-1173-4b2f-b3fe-a729c98b924f	0ede49d0-617f-451f-b90e-7fd9631cfa04	2025-07-25	\N	\N	\N	73.910000	\N	GENERATED	2025-11-04 12:45:11.400439+01
0205d811-cd32-458a-8d79-e7ff1dff3100	0ede49d0-617f-451f-b90e-7fd9631cfa04	2025-07-26	\N	\N	\N	73.970000	\N	GENERATED	2025-11-04 12:45:11.401073+01
68aef8c3-9de0-4a27-8b1c-61e1d45ce53d	0ede49d0-617f-451f-b90e-7fd9631cfa04	2025-07-27	\N	\N	\N	74.660000	\N	GENERATED	2025-11-04 12:45:11.401743+01
3a4afcdb-105b-4d13-bf0d-e70f58309c13	0ede49d0-617f-451f-b90e-7fd9631cfa04	2025-07-28	\N	\N	\N	73.610000	\N	GENERATED	2025-11-04 12:45:11.402374+01
65adba4a-945b-4f59-80e0-5de3062ee655	0ede49d0-617f-451f-b90e-7fd9631cfa04	2025-07-29	\N	\N	\N	74.140000	\N	GENERATED	2025-11-04 12:45:11.403014+01
aabbddcf-7e86-4a68-84a8-eaa34dc575f2	0ede49d0-617f-451f-b90e-7fd9631cfa04	2025-07-30	\N	\N	\N	73.490000	\N	GENERATED	2025-11-04 12:45:11.40375+01
864216d3-5923-4ff1-acbc-cd6000b75e7b	0ede49d0-617f-451f-b90e-7fd9631cfa04	2025-07-31	\N	\N	\N	74.470000	\N	GENERATED	2025-11-04 12:45:11.404439+01
ebe4782b-28d4-41aa-9382-fdb411143bf1	0ede49d0-617f-451f-b90e-7fd9631cfa04	2025-08-01	\N	\N	\N	74.330000	\N	GENERATED	2025-11-04 12:45:11.405091+01
49086870-0a2f-4716-bd46-91c61a1403b9	0ede49d0-617f-451f-b90e-7fd9631cfa04	2025-08-02	\N	\N	\N	74.160000	\N	GENERATED	2025-11-04 12:45:11.405767+01
eab18e37-629f-4e58-ab1d-427d0d62ff3a	0ede49d0-617f-451f-b90e-7fd9631cfa04	2025-08-03	\N	\N	\N	74.370000	\N	GENERATED	2025-11-04 12:45:11.406409+01
5cfa7e7b-99d1-41f5-bc81-c1101deb6882	0ede49d0-617f-451f-b90e-7fd9631cfa04	2025-08-04	\N	\N	\N	73.680000	\N	GENERATED	2025-11-04 12:45:11.407049+01
31b06ba3-eea8-4c0e-8153-9e7707fc2310	0ede49d0-617f-451f-b90e-7fd9631cfa04	2025-08-05	\N	\N	\N	73.730000	\N	GENERATED	2025-11-04 12:45:11.4077+01
1b67a1a9-3812-40d3-bfcd-f5150d7129a2	0ede49d0-617f-451f-b90e-7fd9631cfa04	2025-08-06	\N	\N	\N	74.860000	\N	GENERATED	2025-11-04 12:45:11.408328+01
3b7a6fb1-076a-4d9e-aec2-73f1a9442f6b	0ede49d0-617f-451f-b90e-7fd9631cfa04	2025-08-07	\N	\N	\N	74.570000	\N	GENERATED	2025-11-04 12:45:11.408976+01
0573d91c-cd1a-4860-8c83-c5cd44b8afae	0ede49d0-617f-451f-b90e-7fd9631cfa04	2025-08-08	\N	\N	\N	74.050000	\N	GENERATED	2025-11-04 12:45:11.409607+01
ae18e55d-06c1-444b-8371-a36dc8589adb	0ede49d0-617f-451f-b90e-7fd9631cfa04	2025-08-09	\N	\N	\N	73.850000	\N	GENERATED	2025-11-04 12:45:11.410235+01
c57083fb-4f7f-4e36-b339-edca1b790c95	0ede49d0-617f-451f-b90e-7fd9631cfa04	2025-08-10	\N	\N	\N	73.700000	\N	GENERATED	2025-11-04 12:45:11.41086+01
db4e5e2b-c9ad-4bb5-9a81-e19e6153a010	0ede49d0-617f-451f-b90e-7fd9631cfa04	2025-08-11	\N	\N	\N	73.710000	\N	GENERATED	2025-11-04 12:45:11.411512+01
5d21aee8-5ef2-4eff-a25e-034db77b6e36	0ede49d0-617f-451f-b90e-7fd9631cfa04	2025-08-12	\N	\N	\N	74.840000	\N	GENERATED	2025-11-04 12:45:11.412148+01
8aa3ad80-9e13-4504-8d3f-7dd0acc8185e	0ede49d0-617f-451f-b90e-7fd9631cfa04	2025-08-13	\N	\N	\N	73.760000	\N	GENERATED	2025-11-04 12:45:11.412881+01
c565a7ed-ccfa-4123-a329-65eeabd95f7f	0ede49d0-617f-451f-b90e-7fd9631cfa04	2025-08-14	\N	\N	\N	74.760000	\N	GENERATED	2025-11-04 12:45:11.413527+01
96cbba6a-ef61-469e-bf5a-7afb5bcef6d3	0ede49d0-617f-451f-b90e-7fd9631cfa04	2025-08-15	\N	\N	\N	74.340000	\N	GENERATED	2025-11-04 12:45:11.414232+01
c1c6bb05-dc47-4c32-82bb-35e8cf8765cb	0ede49d0-617f-451f-b90e-7fd9631cfa04	2025-08-16	\N	\N	\N	74.160000	\N	GENERATED	2025-11-04 12:45:11.414869+01
b168c6c6-cb38-4a0a-9a20-91305e34f040	0ede49d0-617f-451f-b90e-7fd9631cfa04	2025-08-17	\N	\N	\N	74.540000	\N	GENERATED	2025-11-04 12:45:11.41551+01
972a6e25-d3f0-4b22-82b4-8a076740ae36	0ede49d0-617f-451f-b90e-7fd9631cfa04	2025-08-18	\N	\N	\N	74.000000	\N	GENERATED	2025-11-04 12:45:11.416139+01
123baba0-bc24-49af-b314-505d2f6dc0e6	0ede49d0-617f-451f-b90e-7fd9631cfa04	2025-08-19	\N	\N	\N	75.100000	\N	GENERATED	2025-11-04 12:45:11.416783+01
aa7aabb1-736d-4b4c-84d8-6247e8c44728	0ede49d0-617f-451f-b90e-7fd9631cfa04	2025-08-20	\N	\N	\N	74.250000	\N	GENERATED	2025-11-04 12:45:11.417449+01
214f1465-4ae7-4fbc-bbf2-81b20221e6b8	0ede49d0-617f-451f-b90e-7fd9631cfa04	2025-08-21	\N	\N	\N	74.230000	\N	GENERATED	2025-11-04 12:45:11.418079+01
e0f8945c-caf3-4c5a-8ab0-70b76df2fa4e	0ede49d0-617f-451f-b90e-7fd9631cfa04	2025-08-22	\N	\N	\N	74.100000	\N	GENERATED	2025-11-04 12:45:11.418726+01
8b712635-a7b9-4ed7-8098-59e465a23821	0ede49d0-617f-451f-b90e-7fd9631cfa04	2025-08-23	\N	\N	\N	74.340000	\N	GENERATED	2025-11-04 12:45:11.419543+01
583bc01d-8696-49fd-a0e7-bc184cd290fd	0ede49d0-617f-451f-b90e-7fd9631cfa04	2025-08-24	\N	\N	\N	74.980000	\N	GENERATED	2025-11-04 12:45:11.420644+01
fd988b6f-fac1-4f0f-8f7b-dcba319555d9	0ede49d0-617f-451f-b90e-7fd9631cfa04	2025-08-25	\N	\N	\N	74.540000	\N	GENERATED	2025-11-04 12:45:11.42137+01
9134ca52-4d41-4327-a4e0-99df90611159	0ede49d0-617f-451f-b90e-7fd9631cfa04	2025-08-26	\N	\N	\N	74.580000	\N	GENERATED	2025-11-04 12:45:11.422044+01
7e94de60-4be4-455e-b535-0a50ca81bf12	0ede49d0-617f-451f-b90e-7fd9631cfa04	2025-08-27	\N	\N	\N	75.060000	\N	GENERATED	2025-11-04 12:45:11.422709+01
d3277f6e-a01c-431f-a652-9f7767d478f1	0ede49d0-617f-451f-b90e-7fd9631cfa04	2025-08-28	\N	\N	\N	74.840000	\N	GENERATED	2025-11-04 12:45:11.423483+01
d09c0797-a0d0-4d6e-891f-da0bd6ad1ee8	0ede49d0-617f-451f-b90e-7fd9631cfa04	2025-08-29	\N	\N	\N	74.420000	\N	GENERATED	2025-11-04 12:45:11.424161+01
682ba6bb-c653-4673-906c-2c5d4b6803e1	0ede49d0-617f-451f-b90e-7fd9631cfa04	2025-08-30	\N	\N	\N	74.320000	\N	GENERATED	2025-11-04 12:45:11.424851+01
ff8a31e4-0422-4228-b521-67ceb9a3fff2	0ede49d0-617f-451f-b90e-7fd9631cfa04	2025-08-31	\N	\N	\N	74.840000	\N	GENERATED	2025-11-04 12:45:11.425516+01
2a881391-93f5-4b96-a234-0e1b54e0034e	0ede49d0-617f-451f-b90e-7fd9631cfa04	2025-09-01	\N	\N	\N	74.780000	\N	GENERATED	2025-11-04 12:45:11.426159+01
1e4282ce-4560-48cc-a6ce-c4195c57a306	0ede49d0-617f-451f-b90e-7fd9631cfa04	2025-09-02	\N	\N	\N	75.010000	\N	GENERATED	2025-11-04 12:45:11.426904+01
03667839-e81b-48c8-a98b-cd1cf52bfa31	0ede49d0-617f-451f-b90e-7fd9631cfa04	2025-09-03	\N	\N	\N	75.240000	\N	GENERATED	2025-11-04 12:45:11.427552+01
cbfdd4d2-3470-46c0-bdaa-9cc8f24ff729	0ede49d0-617f-451f-b90e-7fd9631cfa04	2025-09-04	\N	\N	\N	75.200000	\N	GENERATED	2025-11-04 12:45:11.428198+01
3e609a24-ee27-4e34-a04d-b01782ad5026	0ede49d0-617f-451f-b90e-7fd9631cfa04	2025-09-05	\N	\N	\N	74.570000	\N	GENERATED	2025-11-04 12:45:11.428885+01
cdb868be-76d6-4e31-a0f2-0d6d37752265	0ede49d0-617f-451f-b90e-7fd9631cfa04	2025-09-06	\N	\N	\N	74.240000	\N	GENERATED	2025-11-04 12:45:11.429541+01
84a1467d-cbbd-48d3-944e-91471a90f413	0ede49d0-617f-451f-b90e-7fd9631cfa04	2025-09-07	\N	\N	\N	74.130000	\N	GENERATED	2025-11-04 12:45:11.430173+01
77426ac5-e9b0-4017-8141-dc62cf9eb339	0ede49d0-617f-451f-b90e-7fd9631cfa04	2025-09-08	\N	\N	\N	75.360000	\N	GENERATED	2025-11-04 12:45:11.430808+01
768c0298-ab29-42b4-aac6-ecdbe26fc53f	0ede49d0-617f-451f-b90e-7fd9631cfa04	2025-09-09	\N	\N	\N	75.240000	\N	GENERATED	2025-11-04 12:45:11.43146+01
0cbeba0a-a8bc-414b-a4b0-b2ed0b33ef04	0ede49d0-617f-451f-b90e-7fd9631cfa04	2025-09-10	\N	\N	\N	74.500000	\N	GENERATED	2025-11-04 12:45:11.432088+01
8d66f0da-14ec-4c17-a952-19ab62b6de97	0ede49d0-617f-451f-b90e-7fd9631cfa04	2025-09-11	\N	\N	\N	74.070000	\N	GENERATED	2025-11-04 12:45:11.432757+01
071de645-caa0-4b38-9faa-4dd364ef8a19	0ede49d0-617f-451f-b90e-7fd9631cfa04	2025-09-12	\N	\N	\N	74.110000	\N	GENERATED	2025-11-04 12:45:11.433392+01
d63eb410-5a4f-4b3e-abf7-2900a7ab25ea	0ede49d0-617f-451f-b90e-7fd9631cfa04	2025-09-13	\N	\N	\N	74.780000	\N	GENERATED	2025-11-04 12:45:11.434069+01
cea1d2b5-788e-4574-8576-3d784a27304a	0ede49d0-617f-451f-b90e-7fd9631cfa04	2025-09-14	\N	\N	\N	75.170000	\N	GENERATED	2025-11-04 12:45:11.434776+01
9afe7207-cb78-444e-9818-27975667a072	0ede49d0-617f-451f-b90e-7fd9631cfa04	2025-09-15	\N	\N	\N	74.220000	\N	GENERATED	2025-11-04 12:45:11.435815+01
9a59753d-9f40-425a-add2-e5879c374074	0ede49d0-617f-451f-b90e-7fd9631cfa04	2025-09-16	\N	\N	\N	74.180000	\N	GENERATED	2025-11-04 12:45:11.436469+01
021b0b83-60ea-4e1a-a410-02088b21cdf9	0ede49d0-617f-451f-b90e-7fd9631cfa04	2025-09-17	\N	\N	\N	74.420000	\N	GENERATED	2025-11-04 12:45:11.437128+01
af211427-c027-4771-b839-02deeb8f780b	0ede49d0-617f-451f-b90e-7fd9631cfa04	2025-09-18	\N	\N	\N	75.220000	\N	GENERATED	2025-11-04 12:45:11.437772+01
0d08da43-100b-4c47-9f4c-a85d31cb39b4	0ede49d0-617f-451f-b90e-7fd9631cfa04	2025-09-19	\N	\N	\N	75.260000	\N	GENERATED	2025-11-04 12:45:11.438389+01
1bb423de-683a-4478-a1cc-0ee717292e2a	0ede49d0-617f-451f-b90e-7fd9631cfa04	2025-09-20	\N	\N	\N	74.850000	\N	GENERATED	2025-11-04 12:45:11.439019+01
ab47e66e-2f2e-42a4-b4c6-71d384cbee78	0ede49d0-617f-451f-b90e-7fd9631cfa04	2025-09-21	\N	\N	\N	74.350000	\N	GENERATED	2025-11-04 12:45:11.439659+01
f898ae94-9431-49d5-b613-570c22afc9ab	0ede49d0-617f-451f-b90e-7fd9631cfa04	2025-09-22	\N	\N	\N	74.910000	\N	GENERATED	2025-11-04 12:45:11.440329+01
9ff29491-671a-429b-94e7-e054d8f10733	0ede49d0-617f-451f-b90e-7fd9631cfa04	2025-09-23	\N	\N	\N	75.590000	\N	GENERATED	2025-11-04 12:45:11.440971+01
50913117-1a29-4b6d-a5ec-34b19be09bda	0ede49d0-617f-451f-b90e-7fd9631cfa04	2025-09-24	\N	\N	\N	74.700000	\N	GENERATED	2025-11-04 12:45:11.441634+01
49fb7b76-45f7-4995-ada6-b282d3641c73	0ede49d0-617f-451f-b90e-7fd9631cfa04	2025-09-25	\N	\N	\N	74.510000	\N	GENERATED	2025-11-04 12:45:11.442287+01
e9890ce8-859f-43ec-8550-90fb3135a641	0ede49d0-617f-451f-b90e-7fd9631cfa04	2025-09-26	\N	\N	\N	75.480000	\N	GENERATED	2025-11-04 12:45:11.44292+01
ce4f6809-b9d1-4912-bd55-67ce5f8b95df	0ede49d0-617f-451f-b90e-7fd9631cfa04	2025-09-27	\N	\N	\N	75.020000	\N	GENERATED	2025-11-04 12:45:11.443567+01
e1e087c4-ca11-4716-8dc1-720c742d849a	0ede49d0-617f-451f-b90e-7fd9631cfa04	2025-09-28	\N	\N	\N	75.550000	\N	GENERATED	2025-11-04 12:45:11.444216+01
c7b1496b-193e-4c2c-90d0-11d6b3bbd429	0ede49d0-617f-451f-b90e-7fd9631cfa04	2025-09-29	\N	\N	\N	75.330000	\N	GENERATED	2025-11-04 12:45:11.444866+01
931fcf5d-a880-4d10-8d34-684cb08f7df5	0ede49d0-617f-451f-b90e-7fd9631cfa04	2025-09-30	\N	\N	\N	75.750000	\N	GENERATED	2025-11-04 12:45:11.445507+01
2d4447e1-28f1-41de-ad6b-e41594e8852d	0ede49d0-617f-451f-b90e-7fd9631cfa04	2025-10-01	\N	\N	\N	75.030000	\N	GENERATED	2025-11-04 12:45:11.446139+01
9d6687d1-7606-452e-8e9f-65c1e8d115f0	0ede49d0-617f-451f-b90e-7fd9631cfa04	2025-10-02	\N	\N	\N	75.420000	\N	GENERATED	2025-11-04 12:45:11.446771+01
d928cfc2-19d7-4c58-aa2d-661f6801def6	0ede49d0-617f-451f-b90e-7fd9631cfa04	2025-10-03	\N	\N	\N	74.650000	\N	GENERATED	2025-11-04 12:45:11.447444+01
63449256-cc28-46e8-98b8-5974c0fea095	0ede49d0-617f-451f-b90e-7fd9631cfa04	2025-10-04	\N	\N	\N	75.160000	\N	GENERATED	2025-11-04 12:45:11.448081+01
22307465-8be0-42f2-8822-133176fae60d	0ede49d0-617f-451f-b90e-7fd9631cfa04	2025-10-05	\N	\N	\N	75.350000	\N	GENERATED	2025-11-04 12:45:11.448713+01
cf633661-4b2e-42f4-856f-9083b73118bb	0ede49d0-617f-451f-b90e-7fd9631cfa04	2025-10-06	\N	\N	\N	75.620000	\N	GENERATED	2025-11-04 12:45:11.449354+01
d5839482-cd5b-4a5f-bafb-626559389081	0ede49d0-617f-451f-b90e-7fd9631cfa04	2025-10-07	\N	\N	\N	74.640000	\N	GENERATED	2025-11-04 12:45:11.449983+01
3ac348bd-b391-4e9f-b743-b1c62c3156fd	0ede49d0-617f-451f-b90e-7fd9631cfa04	2025-10-08	\N	\N	\N	75.790000	\N	GENERATED	2025-11-04 12:45:11.450951+01
9e18628d-5a38-4b55-934c-19f5e2f886a9	0ede49d0-617f-451f-b90e-7fd9631cfa04	2025-10-09	\N	\N	\N	75.340000	\N	GENERATED	2025-11-04 12:45:11.451613+01
00c030df-7438-4a18-8716-98fede196c8d	0ede49d0-617f-451f-b90e-7fd9631cfa04	2025-10-10	\N	\N	\N	75.700000	\N	GENERATED	2025-11-04 12:45:11.452352+01
be3d5165-05cc-42fc-9d82-9170bd4e06ac	0ede49d0-617f-451f-b90e-7fd9631cfa04	2025-10-11	\N	\N	\N	74.950000	\N	GENERATED	2025-11-04 12:45:11.452996+01
8a9cd090-61c7-4609-801d-e5d291a1da33	0ede49d0-617f-451f-b90e-7fd9631cfa04	2025-10-12	\N	\N	\N	74.630000	\N	GENERATED	2025-11-04 12:45:11.453785+01
c63264a8-9ead-4af1-b1c6-8cefef6ff5d6	0ede49d0-617f-451f-b90e-7fd9631cfa04	2025-10-13	\N	\N	\N	75.070000	\N	GENERATED	2025-11-04 12:45:11.454809+01
c8f9c51c-6e43-432c-84d1-45c7b4a05672	0ede49d0-617f-451f-b90e-7fd9631cfa04	2025-10-14	\N	\N	\N	74.860000	\N	GENERATED	2025-11-04 12:45:11.45561+01
9e444da4-6331-479a-a59f-a3e351bc0ddb	0ede49d0-617f-451f-b90e-7fd9631cfa04	2025-10-15	\N	\N	\N	74.890000	\N	GENERATED	2025-11-04 12:45:11.456273+01
b064b35d-2f92-4085-af53-bbfcd915b6de	0ede49d0-617f-451f-b90e-7fd9631cfa04	2025-10-16	\N	\N	\N	74.680000	\N	GENERATED	2025-11-04 12:45:11.456922+01
03dd9f58-4021-4de5-9830-a9c1b01dd2cc	0ede49d0-617f-451f-b90e-7fd9631cfa04	2025-10-17	\N	\N	\N	74.910000	\N	GENERATED	2025-11-04 12:45:11.457572+01
16df9d7f-efaf-4294-8fbd-0399fe1ba4c5	0ede49d0-617f-451f-b90e-7fd9631cfa04	2025-10-18	\N	\N	\N	75.590000	\N	GENERATED	2025-11-04 12:45:11.458222+01
cb3c16f5-0cd0-43f4-9921-43ddec38dd4d	0ede49d0-617f-451f-b90e-7fd9631cfa04	2025-10-19	\N	\N	\N	75.780000	\N	GENERATED	2025-11-04 12:45:11.458858+01
80913005-a9c5-47df-8acc-d9071e5dd0f4	0ede49d0-617f-451f-b90e-7fd9631cfa04	2025-10-20	\N	\N	\N	75.760000	\N	GENERATED	2025-11-04 12:45:11.459502+01
d658c912-1489-49f4-975b-f46bbe8a8052	0ede49d0-617f-451f-b90e-7fd9631cfa04	2025-10-21	\N	\N	\N	75.260000	\N	GENERATED	2025-11-04 12:45:11.460246+01
e3ba7bb5-11fa-4154-a467-74d3454ff879	0ede49d0-617f-451f-b90e-7fd9631cfa04	2025-10-22	\N	\N	\N	75.340000	\N	GENERATED	2025-11-04 12:45:11.460894+01
2c55045c-237f-4dbc-9335-f38220d3fd3b	0ede49d0-617f-451f-b90e-7fd9631cfa04	2025-10-23	\N	\N	\N	75.260000	\N	GENERATED	2025-11-04 12:45:11.461539+01
5ffc372a-9fdc-44a5-b566-d391eb9dbfd7	0ede49d0-617f-451f-b90e-7fd9631cfa04	2025-10-24	\N	\N	\N	75.350000	\N	GENERATED	2025-11-04 12:45:11.462203+01
2af7f2f5-ebfd-4ed8-a8f9-e5b25f711f5f	0ede49d0-617f-451f-b90e-7fd9631cfa04	2025-10-25	\N	\N	\N	76.080000	\N	GENERATED	2025-11-04 12:45:11.46284+01
40de35eb-893d-404e-bba8-99f4b86888b9	0ede49d0-617f-451f-b90e-7fd9631cfa04	2025-10-26	\N	\N	\N	75.530000	\N	GENERATED	2025-11-04 12:45:11.463486+01
96c0cbe9-ea23-4ec8-bfd9-04cd66f7564d	0ede49d0-617f-451f-b90e-7fd9631cfa04	2025-10-27	\N	\N	\N	75.420000	\N	GENERATED	2025-11-04 12:45:11.464129+01
82466fcc-0a34-4e82-9abd-923cd71eeadf	0ede49d0-617f-451f-b90e-7fd9631cfa04	2025-10-28	\N	\N	\N	75.630000	\N	GENERATED	2025-11-04 12:45:11.464754+01
d1ad6943-16e7-431c-8ff3-fb1da94dd70c	0ede49d0-617f-451f-b90e-7fd9631cfa04	2025-10-29	\N	\N	\N	75.260000	\N	GENERATED	2025-11-04 12:45:11.465393+01
9e83ebcd-ed1a-4fa2-93e3-30602b32d462	0ede49d0-617f-451f-b90e-7fd9631cfa04	2025-10-30	\N	\N	\N	75.030000	\N	GENERATED	2025-11-04 12:45:11.466177+01
e96de233-59b7-4528-aa56-f2cecca1705c	0ede49d0-617f-451f-b90e-7fd9631cfa04	2025-10-31	\N	\N	\N	75.910000	\N	GENERATED	2025-11-04 12:45:11.46702+01
8f2b471f-279f-43a1-8c85-1aeef51d3fa1	0ede49d0-617f-451f-b90e-7fd9631cfa04	2025-11-01	\N	\N	\N	75.050000	\N	GENERATED	2025-11-04 12:45:11.467709+01
fc4937dd-5e97-4f51-88fd-72a3a1e7e9ba	0ede49d0-617f-451f-b90e-7fd9631cfa04	2025-11-02	\N	\N	\N	76.090000	\N	GENERATED	2025-11-04 12:45:11.468374+01
1b9b950d-bc93-4079-8335-024aaeeb50fe	0ede49d0-617f-451f-b90e-7fd9631cfa04	2025-11-03	\N	\N	\N	76.230000	\N	GENERATED	2025-11-04 12:45:11.46901+01
8c94a1f4-707f-4da0-849a-f4517376ff92	d2c980bc-c787-4166-8e74-d074800bf867	2024-11-04	\N	\N	\N	23.020000	\N	GENERATED	2025-11-04 12:45:11.470228+01
4908d6c4-8942-4c81-8aec-d4dce86c5a56	d2c980bc-c787-4166-8e74-d074800bf867	2024-11-05	\N	\N	\N	22.950000	\N	GENERATED	2025-11-04 12:45:11.470872+01
30ec151d-3a4a-4510-be30-e2e10146d2fe	d2c980bc-c787-4166-8e74-d074800bf867	2024-11-06	\N	\N	\N	22.850000	\N	GENERATED	2025-11-04 12:45:11.471501+01
29da829a-235c-41e1-be41-5826cf9e6d16	d2c980bc-c787-4166-8e74-d074800bf867	2024-11-07	\N	\N	\N	23.130000	\N	GENERATED	2025-11-04 12:45:11.472138+01
1a7c0445-2749-4a31-87a6-01393d75578c	d2c980bc-c787-4166-8e74-d074800bf867	2024-11-08	\N	\N	\N	22.980000	\N	GENERATED	2025-11-04 12:45:11.472891+01
7333427b-158a-4c50-9030-e4f14588142b	d2c980bc-c787-4166-8e74-d074800bf867	2024-11-09	\N	\N	\N	23.100000	\N	GENERATED	2025-11-04 12:45:11.473526+01
77adb930-7fc2-4f5b-b2d3-a814396c3e13	d2c980bc-c787-4166-8e74-d074800bf867	2024-11-10	\N	\N	\N	22.840000	\N	GENERATED	2025-11-04 12:45:11.474245+01
612b2252-054f-4571-858b-f566b0d9bf54	d2c980bc-c787-4166-8e74-d074800bf867	2024-11-11	\N	\N	\N	23.060000	\N	GENERATED	2025-11-04 12:45:11.474911+01
dae75720-67a2-4c81-864a-5971a1d510bb	d2c980bc-c787-4166-8e74-d074800bf867	2024-11-12	\N	\N	\N	23.120000	\N	GENERATED	2025-11-04 12:45:11.475569+01
9fca2c32-82ba-4c25-bf6a-6b72bb415d8b	d2c980bc-c787-4166-8e74-d074800bf867	2024-11-13	\N	\N	\N	22.960000	\N	GENERATED	2025-11-04 12:45:11.476207+01
1fe9052d-5b6f-496c-9d73-37b5ba90bc96	d2c980bc-c787-4166-8e74-d074800bf867	2024-11-14	\N	\N	\N	23.030000	\N	GENERATED	2025-11-04 12:45:11.476917+01
d766932a-31ab-4869-a61b-52e08fa59ea6	d2c980bc-c787-4166-8e74-d074800bf867	2024-11-15	\N	\N	\N	23.120000	\N	GENERATED	2025-11-04 12:45:11.477549+01
ff7d0172-1844-4399-9635-e86aa40b12fb	d2c980bc-c787-4166-8e74-d074800bf867	2024-11-16	\N	\N	\N	23.150000	\N	GENERATED	2025-11-04 12:45:11.478181+01
f49d70a4-401e-4c70-b96c-34f51389be36	d2c980bc-c787-4166-8e74-d074800bf867	2024-11-17	\N	\N	\N	23.260000	\N	GENERATED	2025-11-04 12:45:11.478821+01
af72de63-44db-43d6-854f-e57b6cbde5d2	d2c980bc-c787-4166-8e74-d074800bf867	2024-11-18	\N	\N	\N	22.940000	\N	GENERATED	2025-11-04 12:45:11.479449+01
951615bb-acba-482c-843a-12d7e59fc1d5	d2c980bc-c787-4166-8e74-d074800bf867	2024-11-19	\N	\N	\N	23.010000	\N	GENERATED	2025-11-04 12:45:11.480093+01
4d0a68d6-537a-4f6a-8ded-2cb5581532fc	d2c980bc-c787-4166-8e74-d074800bf867	2024-11-20	\N	\N	\N	23.010000	\N	GENERATED	2025-11-04 12:45:11.480727+01
1f9552d8-30ad-4b17-8758-1759d964483d	d2c980bc-c787-4166-8e74-d074800bf867	2024-11-21	\N	\N	\N	23.300000	\N	GENERATED	2025-11-04 12:45:11.481535+01
4218e854-7ac7-463e-9330-f47fc0ca9f14	d2c980bc-c787-4166-8e74-d074800bf867	2024-11-22	\N	\N	\N	23.200000	\N	GENERATED	2025-11-04 12:45:11.482193+01
07860186-28b1-42b4-8d39-5f414af24d03	d2c980bc-c787-4166-8e74-d074800bf867	2024-11-23	\N	\N	\N	23.030000	\N	GENERATED	2025-11-04 12:45:11.48283+01
39d6c79c-da24-4945-be6a-0d3e1fc60b91	d2c980bc-c787-4166-8e74-d074800bf867	2024-11-24	\N	\N	\N	23.160000	\N	GENERATED	2025-11-04 12:45:11.48353+01
d8c00779-a712-4055-b42b-2c9ca0925ce6	d2c980bc-c787-4166-8e74-d074800bf867	2024-11-25	\N	\N	\N	22.970000	\N	GENERATED	2025-11-04 12:45:11.484592+01
8ee667c6-8c1f-40c0-b905-38e9df3d1d14	d2c980bc-c787-4166-8e74-d074800bf867	2024-11-26	\N	\N	\N	23.320000	\N	GENERATED	2025-11-04 12:45:11.485253+01
21caffb8-ae9b-415c-80c8-30f153ac2fe2	d2c980bc-c787-4166-8e74-d074800bf867	2024-11-27	\N	\N	\N	23.200000	\N	GENERATED	2025-11-04 12:45:11.485883+01
bfdc2753-843c-475b-8749-668b1e1120f0	d2c980bc-c787-4166-8e74-d074800bf867	2024-11-28	\N	\N	\N	23.120000	\N	GENERATED	2025-11-04 12:45:11.486525+01
b64da834-ae73-4699-a28b-2cb113c86d13	d2c980bc-c787-4166-8e74-d074800bf867	2024-11-29	\N	\N	\N	23.010000	\N	GENERATED	2025-11-04 12:45:11.487155+01
ad69fe4a-10fe-4065-8a13-5be8d3969998	d2c980bc-c787-4166-8e74-d074800bf867	2024-11-30	\N	\N	\N	23.100000	\N	GENERATED	2025-11-04 12:45:11.487803+01
c7264c4b-65f6-46bd-a0cf-bb1644d89e64	d2c980bc-c787-4166-8e74-d074800bf867	2024-12-01	\N	\N	\N	23.330000	\N	GENERATED	2025-11-04 12:45:11.488452+01
26ab3676-a8d6-4866-ab1b-fb40aa5d514a	d2c980bc-c787-4166-8e74-d074800bf867	2024-12-02	\N	\N	\N	23.300000	\N	GENERATED	2025-11-04 12:45:11.489081+01
4d3eba7b-6b04-431b-85ee-a04b667f68fc	d2c980bc-c787-4166-8e74-d074800bf867	2024-12-03	\N	\N	\N	23.130000	\N	GENERATED	2025-11-04 12:45:11.489827+01
d620bc6b-797a-4cbf-ac0a-e62613efd071	d2c980bc-c787-4166-8e74-d074800bf867	2024-12-04	\N	\N	\N	23.040000	\N	GENERATED	2025-11-04 12:45:11.490472+01
30c03c3a-1bd5-463a-b832-74e9c3188090	d2c980bc-c787-4166-8e74-d074800bf867	2024-12-05	\N	\N	\N	23.170000	\N	GENERATED	2025-11-04 12:45:11.491103+01
50e064a9-306d-489b-8ad3-1a89148e2012	d2c980bc-c787-4166-8e74-d074800bf867	2024-12-06	\N	\N	\N	23.230000	\N	GENERATED	2025-11-04 12:45:11.491762+01
3439b8af-66e6-4e3e-9da4-4eca8ce1022f	d2c980bc-c787-4166-8e74-d074800bf867	2024-12-07	\N	\N	\N	23.290000	\N	GENERATED	2025-11-04 12:45:11.492431+01
885acc0d-2401-4232-ae2b-3f89f29e180f	d2c980bc-c787-4166-8e74-d074800bf867	2024-12-08	\N	\N	\N	23.330000	\N	GENERATED	2025-11-04 12:45:11.493061+01
2f627e9a-b6e5-4fac-bc33-3eeefad5fb4a	d2c980bc-c787-4166-8e74-d074800bf867	2024-12-09	\N	\N	\N	23.270000	\N	GENERATED	2025-11-04 12:45:11.493727+01
16593869-501a-47e5-b657-2ee5943d94a5	d2c980bc-c787-4166-8e74-d074800bf867	2024-12-10	\N	\N	\N	23.240000	\N	GENERATED	2025-11-04 12:45:11.494459+01
3cebdcc6-47ff-4908-a547-4e4ba201e5e4	d2c980bc-c787-4166-8e74-d074800bf867	2024-12-11	\N	\N	\N	23.240000	\N	GENERATED	2025-11-04 12:45:11.495119+01
ae78be4f-6621-48be-b5ff-26ead7d62374	d2c980bc-c787-4166-8e74-d074800bf867	2024-12-12	\N	\N	\N	23.370000	\N	GENERATED	2025-11-04 12:45:11.495758+01
07159d6a-7b79-4f27-a9c4-7f378fb80033	d2c980bc-c787-4166-8e74-d074800bf867	2024-12-13	\N	\N	\N	23.310000	\N	GENERATED	2025-11-04 12:45:11.496443+01
7395bc10-b2c3-475a-8645-e22a37fee9d6	d2c980bc-c787-4166-8e74-d074800bf867	2024-12-14	\N	\N	\N	23.170000	\N	GENERATED	2025-11-04 12:45:11.497144+01
78ade223-ccc0-4300-a210-8b566f6d80d2	d2c980bc-c787-4166-8e74-d074800bf867	2024-12-15	\N	\N	\N	23.320000	\N	GENERATED	2025-11-04 12:45:11.498101+01
fd9d4403-8828-494c-b274-645d891d0de8	d2c980bc-c787-4166-8e74-d074800bf867	2024-12-16	\N	\N	\N	23.250000	\N	GENERATED	2025-11-04 12:45:11.499019+01
04b4b8fe-4a84-4afb-b18b-0191fa9a61bf	d2c980bc-c787-4166-8e74-d074800bf867	2024-12-17	\N	\N	\N	23.440000	\N	GENERATED	2025-11-04 12:45:11.500206+01
70445251-a090-4a9b-9ee9-7ddcae4a66e0	d2c980bc-c787-4166-8e74-d074800bf867	2024-12-18	\N	\N	\N	23.140000	\N	GENERATED	2025-11-04 12:45:11.501102+01
d1b188a3-9a1b-476c-b705-438e58cc5f9c	d2c980bc-c787-4166-8e74-d074800bf867	2024-12-19	\N	\N	\N	23.240000	\N	GENERATED	2025-11-04 12:45:11.50209+01
e38fd8e1-253c-4064-a803-484a19fc66e1	d2c980bc-c787-4166-8e74-d074800bf867	2024-12-20	\N	\N	\N	23.130000	\N	GENERATED	2025-11-04 12:45:11.503109+01
0b74c347-358c-4a25-85c8-3294d506371c	d2c980bc-c787-4166-8e74-d074800bf867	2024-12-21	\N	\N	\N	23.020000	\N	GENERATED	2025-11-04 12:45:11.504047+01
c50e76dd-ab4a-4de0-89d0-a36a210c98bb	d2c980bc-c787-4166-8e74-d074800bf867	2024-12-22	\N	\N	\N	23.390000	\N	GENERATED	2025-11-04 12:45:11.505005+01
716099db-5ac9-4cb4-bb60-beae64a47946	d2c980bc-c787-4166-8e74-d074800bf867	2024-12-23	\N	\N	\N	23.170000	\N	GENERATED	2025-11-04 12:45:11.505935+01
59dfca1f-3379-4073-8d9b-0006dd8b6d05	d2c980bc-c787-4166-8e74-d074800bf867	2024-12-24	\N	\N	\N	23.300000	\N	GENERATED	2025-11-04 12:45:11.506847+01
879fc332-9a59-4213-8ee4-0318d9f502ce	d2c980bc-c787-4166-8e74-d074800bf867	2024-12-25	\N	\N	\N	23.050000	\N	GENERATED	2025-11-04 12:45:11.50785+01
be157ed7-7c69-44e4-b896-aa82b8482a38	d2c980bc-c787-4166-8e74-d074800bf867	2024-12-26	\N	\N	\N	23.320000	\N	GENERATED	2025-11-04 12:45:11.508722+01
54c7f2f7-3548-4568-9623-99525c955e46	d2c980bc-c787-4166-8e74-d074800bf867	2024-12-27	\N	\N	\N	23.320000	\N	GENERATED	2025-11-04 12:45:11.509696+01
50dff2f2-0028-4e8d-a7b4-45372c9b3504	d2c980bc-c787-4166-8e74-d074800bf867	2024-12-28	\N	\N	\N	23.060000	\N	GENERATED	2025-11-04 12:45:11.510642+01
206bafb3-92af-464f-b92e-8fbbdcb0332d	d2c980bc-c787-4166-8e74-d074800bf867	2024-12-29	\N	\N	\N	23.460000	\N	GENERATED	2025-11-04 12:45:11.511923+01
d88f31ae-ae87-41a4-a519-9d28acde5ec6	d2c980bc-c787-4166-8e74-d074800bf867	2024-12-30	\N	\N	\N	23.060000	\N	GENERATED	2025-11-04 12:45:11.513075+01
56f610b2-6422-436c-872e-e141db340fa6	d2c980bc-c787-4166-8e74-d074800bf867	2024-12-31	\N	\N	\N	23.320000	\N	GENERATED	2025-11-04 12:45:11.513872+01
22730de2-f5ab-4489-beee-7b9fa3bb6ce9	d2c980bc-c787-4166-8e74-d074800bf867	2025-01-01	\N	\N	\N	23.480000	\N	GENERATED	2025-11-04 12:45:11.514932+01
c5605bbc-4113-4049-bba8-b598d6489e9d	d2c980bc-c787-4166-8e74-d074800bf867	2025-01-02	\N	\N	\N	23.110000	\N	GENERATED	2025-11-04 12:45:11.515946+01
61c5dad3-da7f-438e-b27f-f202856c3167	d2c980bc-c787-4166-8e74-d074800bf867	2025-01-03	\N	\N	\N	23.510000	\N	GENERATED	2025-11-04 12:45:11.517182+01
c672e9d1-7c85-42f0-8459-02025124885f	d2c980bc-c787-4166-8e74-d074800bf867	2025-01-04	\N	\N	\N	23.350000	\N	GENERATED	2025-11-04 12:45:11.51811+01
4f5091a5-21a6-45ea-a565-d44c6bbd3a47	d2c980bc-c787-4166-8e74-d074800bf867	2025-01-05	\N	\N	\N	23.250000	\N	GENERATED	2025-11-04 12:45:11.51919+01
c595d10c-30a9-4ded-980a-5ca5f8b8c1a1	d2c980bc-c787-4166-8e74-d074800bf867	2025-01-06	\N	\N	\N	23.350000	\N	GENERATED	2025-11-04 12:45:11.520099+01
9f969ef3-d4d0-4be7-a47a-e319d96440db	d2c980bc-c787-4166-8e74-d074800bf867	2025-01-07	\N	\N	\N	23.130000	\N	GENERATED	2025-11-04 12:45:11.521056+01
3892017a-365b-46b4-b5fb-70007142dcb9	d2c980bc-c787-4166-8e74-d074800bf867	2025-01-08	\N	\N	\N	23.330000	\N	GENERATED	2025-11-04 12:45:11.521994+01
5504c031-ce5a-437f-95dd-f220ec495dff	d2c980bc-c787-4166-8e74-d074800bf867	2025-01-09	\N	\N	\N	23.470000	\N	GENERATED	2025-11-04 12:45:11.522954+01
9649f9f2-4a05-425f-b746-2b22d830257c	d2c980bc-c787-4166-8e74-d074800bf867	2025-01-10	\N	\N	\N	23.250000	\N	GENERATED	2025-11-04 12:45:11.523739+01
56aa2bfa-e350-4c43-86b6-b86682abadbb	d2c980bc-c787-4166-8e74-d074800bf867	2025-01-11	\N	\N	\N	23.460000	\N	GENERATED	2025-11-04 12:45:11.524948+01
0958898e-c94a-4232-a9b6-c18e4263bc57	d2c980bc-c787-4166-8e74-d074800bf867	2025-01-12	\N	\N	\N	23.440000	\N	GENERATED	2025-11-04 12:45:11.525828+01
ae1f2adc-6edc-413a-b0d4-84f647860dbf	d2c980bc-c787-4166-8e74-d074800bf867	2025-01-13	\N	\N	\N	23.540000	\N	GENERATED	2025-11-04 12:45:11.526814+01
91d0347a-cd4b-472d-a11c-830f800b11ee	d2c980bc-c787-4166-8e74-d074800bf867	2025-01-14	\N	\N	\N	23.340000	\N	GENERATED	2025-11-04 12:45:11.527932+01
57ae5b8a-b4f9-4b7f-85f0-8d56efc30879	d2c980bc-c787-4166-8e74-d074800bf867	2025-01-15	\N	\N	\N	23.280000	\N	GENERATED	2025-11-04 12:45:11.528857+01
3bf6effd-3b7e-480d-b234-75899c6a6d20	d2c980bc-c787-4166-8e74-d074800bf867	2025-01-16	\N	\N	\N	23.280000	\N	GENERATED	2025-11-04 12:45:11.529798+01
3e2eee23-cd3e-4690-a743-5751aeebf7fc	d2c980bc-c787-4166-8e74-d074800bf867	2025-01-17	\N	\N	\N	23.350000	\N	GENERATED	2025-11-04 12:45:11.530663+01
dde8390f-7399-42e6-a28d-6a375bd02886	d2c980bc-c787-4166-8e74-d074800bf867	2025-01-18	\N	\N	\N	23.320000	\N	GENERATED	2025-11-04 12:45:11.531568+01
74f20812-3d65-4162-a7e6-08e34b2c7498	d2c980bc-c787-4166-8e74-d074800bf867	2025-01-19	\N	\N	\N	23.530000	\N	GENERATED	2025-11-04 12:45:11.532862+01
02e69c7b-c5ea-4570-88d1-c1a45fcc8efd	d2c980bc-c787-4166-8e74-d074800bf867	2025-01-20	\N	\N	\N	23.540000	\N	GENERATED	2025-11-04 12:45:11.53379+01
d9350a5d-ae41-4071-b9e2-55e15a5a040b	d2c980bc-c787-4166-8e74-d074800bf867	2025-01-21	\N	\N	\N	23.360000	\N	GENERATED	2025-11-04 12:45:11.534647+01
2d2320b4-e538-4cf5-8502-9cf170b75503	d2c980bc-c787-4166-8e74-d074800bf867	2025-01-22	\N	\N	\N	23.600000	\N	GENERATED	2025-11-04 12:45:11.535477+01
b085db37-cb32-41c8-914d-75362d1364c6	d2c980bc-c787-4166-8e74-d074800bf867	2025-01-23	\N	\N	\N	23.430000	\N	GENERATED	2025-11-04 12:45:11.536364+01
382ebc0a-c58c-4616-9350-b65e98cd2689	d2c980bc-c787-4166-8e74-d074800bf867	2025-01-24	\N	\N	\N	23.490000	\N	GENERATED	2025-11-04 12:45:11.537285+01
b04ed2b9-1f71-44a9-b3eb-5d767e560924	d2c980bc-c787-4166-8e74-d074800bf867	2025-01-25	\N	\N	\N	23.630000	\N	GENERATED	2025-11-04 12:45:11.538383+01
e17e6037-1ea4-42a6-af7a-d6e6af1aad06	d2c980bc-c787-4166-8e74-d074800bf867	2025-01-26	\N	\N	\N	23.330000	\N	GENERATED	2025-11-04 12:45:11.539194+01
77532168-c305-4a46-bb27-293a222bd6dd	d2c980bc-c787-4166-8e74-d074800bf867	2025-01-27	\N	\N	\N	23.240000	\N	GENERATED	2025-11-04 12:45:11.540123+01
01376abf-12e9-435c-86d9-4c8aefa58024	d2c980bc-c787-4166-8e74-d074800bf867	2025-01-28	\N	\N	\N	23.290000	\N	GENERATED	2025-11-04 12:45:11.54122+01
c2ad3999-8929-42aa-97d2-26bc881df8e7	d2c980bc-c787-4166-8e74-d074800bf867	2025-01-29	\N	\N	\N	23.340000	\N	GENERATED	2025-11-04 12:45:11.542238+01
0b4596d5-ae9d-443c-bbe5-2b869b2f1465	d2c980bc-c787-4166-8e74-d074800bf867	2025-01-30	\N	\N	\N	23.430000	\N	GENERATED	2025-11-04 12:45:11.543335+01
b9f69098-c0a8-4fe1-bb30-2587addfc6d4	d2c980bc-c787-4166-8e74-d074800bf867	2025-01-31	\N	\N	\N	23.580000	\N	GENERATED	2025-11-04 12:45:11.544257+01
642175ab-cf92-4ac5-ad42-d2fe685741e0	d2c980bc-c787-4166-8e74-d074800bf867	2025-02-01	\N	\N	\N	23.350000	\N	GENERATED	2025-11-04 12:45:11.54518+01
5e513ad9-cdbf-4e6b-89d6-08e9711fff8c	d2c980bc-c787-4166-8e74-d074800bf867	2025-02-02	\N	\N	\N	23.460000	\N	GENERATED	2025-11-04 12:45:11.546176+01
9daefedd-fcab-4bac-ae6f-0d7ccff0eec1	d2c980bc-c787-4166-8e74-d074800bf867	2025-02-03	\N	\N	\N	23.400000	\N	GENERATED	2025-11-04 12:45:11.547296+01
55f8045f-1470-4085-b4fe-ed524050c5ef	d2c980bc-c787-4166-8e74-d074800bf867	2025-02-04	\N	\N	\N	23.370000	\N	GENERATED	2025-11-04 12:45:11.548246+01
3d7f216d-1c79-4667-ba81-f3b0b82ea3d5	d2c980bc-c787-4166-8e74-d074800bf867	2025-02-05	\N	\N	\N	23.470000	\N	GENERATED	2025-11-04 12:45:11.549265+01
bc11bf8c-aeef-4eb9-8f63-b3659a0da2d0	d2c980bc-c787-4166-8e74-d074800bf867	2025-02-06	\N	\N	\N	23.490000	\N	GENERATED	2025-11-04 12:45:11.550316+01
5b851b00-bf25-46d9-a290-6a01ac9ce8e8	d2c980bc-c787-4166-8e74-d074800bf867	2025-02-07	\N	\N	\N	23.390000	\N	GENERATED	2025-11-04 12:45:11.55122+01
1739814f-8f35-4dc5-a2ad-e3f5060e1192	d2c980bc-c787-4166-8e74-d074800bf867	2025-02-08	\N	\N	\N	23.560000	\N	GENERATED	2025-11-04 12:45:11.552244+01
73a177aa-da26-4218-99ad-5176820c0fcf	d2c980bc-c787-4166-8e74-d074800bf867	2025-02-09	\N	\N	\N	23.410000	\N	GENERATED	2025-11-04 12:45:11.553101+01
1272fd5d-7e62-42c4-abaa-aec313078d8f	d2c980bc-c787-4166-8e74-d074800bf867	2025-02-10	\N	\N	\N	23.370000	\N	GENERATED	2025-11-04 12:45:11.554047+01
777ae4d8-f67a-4f4a-8594-d4a0db9990f0	d2c980bc-c787-4166-8e74-d074800bf867	2025-02-11	\N	\N	\N	23.700000	\N	GENERATED	2025-11-04 12:45:11.554995+01
7ccba734-efa5-4a57-905a-4e4c4ef0e4b5	d2c980bc-c787-4166-8e74-d074800bf867	2025-02-12	\N	\N	\N	23.490000	\N	GENERATED	2025-11-04 12:45:11.555924+01
cb562de8-9e8a-44ed-936a-c6ad2b7bd2ad	d2c980bc-c787-4166-8e74-d074800bf867	2025-02-13	\N	\N	\N	23.640000	\N	GENERATED	2025-11-04 12:45:11.556887+01
15e67f3b-94f0-4ef5-8243-6732d3cd6ecd	d2c980bc-c787-4166-8e74-d074800bf867	2025-02-14	\N	\N	\N	23.410000	\N	GENERATED	2025-11-04 12:45:11.557801+01
ca906816-1f37-4865-9863-d4688bdcc990	d2c980bc-c787-4166-8e74-d074800bf867	2025-02-15	\N	\N	\N	23.400000	\N	GENERATED	2025-11-04 12:45:11.558778+01
a51e4809-2557-45ad-9ebe-7e83b04ea9ea	d2c980bc-c787-4166-8e74-d074800bf867	2025-02-16	\N	\N	\N	23.330000	\N	GENERATED	2025-11-04 12:45:11.559645+01
06a74b54-3e59-48cf-a61c-a1b246db92b9	d2c980bc-c787-4166-8e74-d074800bf867	2025-02-17	\N	\N	\N	23.530000	\N	GENERATED	2025-11-04 12:45:11.560623+01
b0676880-2218-4f9b-87b1-0df27c5798d6	d2c980bc-c787-4166-8e74-d074800bf867	2025-02-18	\N	\N	\N	23.340000	\N	GENERATED	2025-11-04 12:45:11.561628+01
3107b84b-dfdf-494e-926c-28acaeccd725	d2c980bc-c787-4166-8e74-d074800bf867	2025-02-19	\N	\N	\N	23.730000	\N	GENERATED	2025-11-04 12:45:11.562482+01
754dfb76-1d76-4a73-97e0-8efc914f9dfa	d2c980bc-c787-4166-8e74-d074800bf867	2025-02-20	\N	\N	\N	23.610000	\N	GENERATED	2025-11-04 12:45:11.563276+01
355522b3-eeaa-48a0-8935-6386c97e5791	d2c980bc-c787-4166-8e74-d074800bf867	2025-02-21	\N	\N	\N	23.590000	\N	GENERATED	2025-11-04 12:45:11.564135+01
ab35b3a8-86b3-4e32-9e06-f86bd67e7d5a	d2c980bc-c787-4166-8e74-d074800bf867	2025-02-22	\N	\N	\N	23.350000	\N	GENERATED	2025-11-04 12:45:11.564981+01
560a63a2-4f7c-4a67-9ae5-b457186228b2	d2c980bc-c787-4166-8e74-d074800bf867	2025-02-23	\N	\N	\N	23.410000	\N	GENERATED	2025-11-04 12:45:11.565806+01
f74bd798-1a72-4aad-9ec8-044bdafec778	d2c980bc-c787-4166-8e74-d074800bf867	2025-02-24	\N	\N	\N	23.740000	\N	GENERATED	2025-11-04 12:45:11.566629+01
9e256527-4e53-452c-9800-959fb7c07137	d2c980bc-c787-4166-8e74-d074800bf867	2025-02-25	\N	\N	\N	23.480000	\N	GENERATED	2025-11-04 12:45:11.567454+01
e9d62045-bfad-4a50-a00e-c218440e70bf	d2c980bc-c787-4166-8e74-d074800bf867	2025-02-26	\N	\N	\N	23.750000	\N	GENERATED	2025-11-04 12:45:11.568273+01
a27425af-6df2-4055-bcdf-93272cd37990	d2c980bc-c787-4166-8e74-d074800bf867	2025-02-27	\N	\N	\N	23.570000	\N	GENERATED	2025-11-04 12:45:11.56913+01
55d8c890-df88-4149-86ee-46093b123b60	d2c980bc-c787-4166-8e74-d074800bf867	2025-02-28	\N	\N	\N	23.760000	\N	GENERATED	2025-11-04 12:45:11.570097+01
c8ad4042-b5ab-4672-80e4-64ccdc0b5a36	d2c980bc-c787-4166-8e74-d074800bf867	2025-03-01	\N	\N	\N	23.670000	\N	GENERATED	2025-11-04 12:45:11.571003+01
7c198f42-41c1-46b5-a965-3e10515432ba	d2c980bc-c787-4166-8e74-d074800bf867	2025-03-02	\N	\N	\N	23.540000	\N	GENERATED	2025-11-04 12:45:11.571843+01
b3d55e08-5585-45e0-ba42-db239dd7e024	d2c980bc-c787-4166-8e74-d074800bf867	2025-03-03	\N	\N	\N	23.670000	\N	GENERATED	2025-11-04 12:45:11.57273+01
f84a5f39-2ebd-4842-ac96-757d998e5f10	d2c980bc-c787-4166-8e74-d074800bf867	2025-03-04	\N	\N	\N	23.690000	\N	GENERATED	2025-11-04 12:45:11.57356+01
9a160e4c-5bb0-42bc-a465-46d3792b3608	d2c980bc-c787-4166-8e74-d074800bf867	2025-03-05	\N	\N	\N	23.480000	\N	GENERATED	2025-11-04 12:45:11.574493+01
9a35fafd-f19b-4096-94aa-d34e85cdb75c	d2c980bc-c787-4166-8e74-d074800bf867	2025-03-06	\N	\N	\N	23.700000	\N	GENERATED	2025-11-04 12:45:11.575336+01
1f891557-9a14-4225-aa22-e2887f04d06c	d2c980bc-c787-4166-8e74-d074800bf867	2025-03-07	\N	\N	\N	23.800000	\N	GENERATED	2025-11-04 12:45:11.576267+01
6e8e6981-cb96-4c2d-a3a3-73a647659f7b	d2c980bc-c787-4166-8e74-d074800bf867	2025-03-08	\N	\N	\N	23.510000	\N	GENERATED	2025-11-04 12:45:11.577196+01
142ffda8-eb07-401b-a484-6075e0643dfb	d2c980bc-c787-4166-8e74-d074800bf867	2025-03-09	\N	\N	\N	23.820000	\N	GENERATED	2025-11-04 12:45:11.578118+01
e7def88f-ae6b-4ea2-9e03-3a4decebfac2	d2c980bc-c787-4166-8e74-d074800bf867	2025-03-10	\N	\N	\N	23.760000	\N	GENERATED	2025-11-04 12:45:11.579114+01
3ec908b7-a367-4965-9a24-066c5d4b46de	d2c980bc-c787-4166-8e74-d074800bf867	2025-03-11	\N	\N	\N	23.690000	\N	GENERATED	2025-11-04 12:45:11.580045+01
497d896d-4173-4373-9535-ac50bfa358db	d2c980bc-c787-4166-8e74-d074800bf867	2025-03-12	\N	\N	\N	23.560000	\N	GENERATED	2025-11-04 12:45:11.580922+01
f6e3882f-7895-4c4e-b38c-5b46e14d5058	d2c980bc-c787-4166-8e74-d074800bf867	2025-03-13	\N	\N	\N	23.800000	\N	GENERATED	2025-11-04 12:45:11.582042+01
86aa20c9-4b17-460a-8722-8fb3f8964b90	d2c980bc-c787-4166-8e74-d074800bf867	2025-03-14	\N	\N	\N	23.600000	\N	GENERATED	2025-11-04 12:45:11.582895+01
9355dd4a-7cce-41b6-9252-83565cdbcabe	d2c980bc-c787-4166-8e74-d074800bf867	2025-03-15	\N	\N	\N	23.760000	\N	GENERATED	2025-11-04 12:45:11.584098+01
2d8f65bb-3459-438a-a004-e859cd9b3abb	d2c980bc-c787-4166-8e74-d074800bf867	2025-03-16	\N	\N	\N	23.690000	\N	GENERATED	2025-11-04 12:45:11.585014+01
31d2a785-1218-40cd-9279-21b6c68cc655	d2c980bc-c787-4166-8e74-d074800bf867	2025-03-17	\N	\N	\N	23.720000	\N	GENERATED	2025-11-04 12:45:11.586038+01
704da1c2-ac30-4689-b084-d6646be46621	d2c980bc-c787-4166-8e74-d074800bf867	2025-03-18	\N	\N	\N	23.520000	\N	GENERATED	2025-11-04 12:45:11.587128+01
3ff65a77-8dd1-4e96-bf5c-7db37d3421fd	d2c980bc-c787-4166-8e74-d074800bf867	2025-03-19	\N	\N	\N	23.540000	\N	GENERATED	2025-11-04 12:45:11.588061+01
7d34f142-c228-419f-8c07-42e99783c87f	d2c980bc-c787-4166-8e74-d074800bf867	2025-03-20	\N	\N	\N	23.860000	\N	GENERATED	2025-11-04 12:45:11.589121+01
e167a5f9-94ba-42cf-9ad1-226b038a975c	d2c980bc-c787-4166-8e74-d074800bf867	2025-03-21	\N	\N	\N	23.920000	\N	GENERATED	2025-11-04 12:45:11.590194+01
ab6ff8d4-79fd-4774-8987-5d64218d16f4	d2c980bc-c787-4166-8e74-d074800bf867	2025-03-22	\N	\N	\N	23.630000	\N	GENERATED	2025-11-04 12:45:11.591114+01
169481e4-4764-4798-b667-a8e4ba8df226	d2c980bc-c787-4166-8e74-d074800bf867	2025-03-23	\N	\N	\N	23.800000	\N	GENERATED	2025-11-04 12:45:11.592088+01
34112337-0e21-47eb-adb9-c410f8948ca3	d2c980bc-c787-4166-8e74-d074800bf867	2025-03-24	\N	\N	\N	23.570000	\N	GENERATED	2025-11-04 12:45:11.592997+01
9535cfea-4b6a-4ac7-8a16-aec802e1a308	d2c980bc-c787-4166-8e74-d074800bf867	2025-03-25	\N	\N	\N	23.640000	\N	GENERATED	2025-11-04 12:45:11.594094+01
9a16d3b7-dc11-4b58-8348-ffd11db12885	d2c980bc-c787-4166-8e74-d074800bf867	2025-03-26	\N	\N	\N	23.800000	\N	GENERATED	2025-11-04 12:45:11.595031+01
759e8601-a964-4762-b196-1021403f8773	d2c980bc-c787-4166-8e74-d074800bf867	2025-03-27	\N	\N	\N	23.940000	\N	GENERATED	2025-11-04 12:45:11.595954+01
6aa4f70b-d6a1-4537-ab4c-61f6c5522db2	d2c980bc-c787-4166-8e74-d074800bf867	2025-03-28	\N	\N	\N	23.940000	\N	GENERATED	2025-11-04 12:45:11.596847+01
fe9f1902-c277-48b7-a1ce-5ffd8c48a233	d2c980bc-c787-4166-8e74-d074800bf867	2025-03-29	\N	\N	\N	23.680000	\N	GENERATED	2025-11-04 12:45:11.597956+01
228cfe2c-e8c9-42e2-b7a5-06777ecf5036	d2c980bc-c787-4166-8e74-d074800bf867	2025-03-30	\N	\N	\N	23.530000	\N	GENERATED	2025-11-04 12:45:11.599075+01
47bb568e-95e7-4f96-8fc7-ee0871405ef2	d2c980bc-c787-4166-8e74-d074800bf867	2025-03-31	\N	\N	\N	23.730000	\N	GENERATED	2025-11-04 12:45:11.600239+01
7c663a79-f51b-44bb-af62-7be65dc4be55	d2c980bc-c787-4166-8e74-d074800bf867	2025-04-01	\N	\N	\N	23.960000	\N	GENERATED	2025-11-04 12:45:11.601098+01
d1b8dc47-c1e0-43ab-9c0c-d392f8756624	d2c980bc-c787-4166-8e74-d074800bf867	2025-04-02	\N	\N	\N	23.820000	\N	GENERATED	2025-11-04 12:45:11.602289+01
affafe9a-c80d-4d8c-8b21-c95af8b4ad97	d2c980bc-c787-4166-8e74-d074800bf867	2025-04-03	\N	\N	\N	23.890000	\N	GENERATED	2025-11-04 12:45:11.60327+01
430bdfdf-0729-42c9-a8f4-01bd4124dfa3	d2c980bc-c787-4166-8e74-d074800bf867	2025-04-04	\N	\N	\N	23.980000	\N	GENERATED	2025-11-04 12:45:11.604206+01
7a298873-b742-4c96-abf5-6a73eebd7dfe	d2c980bc-c787-4166-8e74-d074800bf867	2025-04-05	\N	\N	\N	23.660000	\N	GENERATED	2025-11-04 12:45:11.605225+01
f30b1869-2ded-43e3-bcd0-09e67f31e139	d2c980bc-c787-4166-8e74-d074800bf867	2025-04-06	\N	\N	\N	23.700000	\N	GENERATED	2025-11-04 12:45:11.606224+01
9e9bb0ae-55f8-4b18-968d-89edddcfe54c	d2c980bc-c787-4166-8e74-d074800bf867	2025-04-07	\N	\N	\N	23.930000	\N	GENERATED	2025-11-04 12:45:11.607162+01
56d54fe9-e254-4a5e-98fd-8dba6405e294	d2c980bc-c787-4166-8e74-d074800bf867	2025-04-08	\N	\N	\N	23.900000	\N	GENERATED	2025-11-04 12:45:11.608091+01
1d6b240b-80bd-4106-8afd-7001f15a2a02	d2c980bc-c787-4166-8e74-d074800bf867	2025-04-09	\N	\N	\N	23.840000	\N	GENERATED	2025-11-04 12:45:11.609008+01
4616ab4a-911d-41b7-b5d8-e5246eb6bff6	d2c980bc-c787-4166-8e74-d074800bf867	2025-04-10	\N	\N	\N	23.990000	\N	GENERATED	2025-11-04 12:45:11.610129+01
6f8ab070-500b-42c5-b2fa-4838d46c7fd8	d2c980bc-c787-4166-8e74-d074800bf867	2025-04-11	\N	\N	\N	23.720000	\N	GENERATED	2025-11-04 12:45:11.611207+01
5ef6e8ac-e682-4815-b3f6-7f01141d9a9b	d2c980bc-c787-4166-8e74-d074800bf867	2025-04-12	\N	\N	\N	23.980000	\N	GENERATED	2025-11-04 12:45:11.612199+01
692912b9-911f-44f5-b6ad-1082a3fe3e09	d2c980bc-c787-4166-8e74-d074800bf867	2025-04-13	\N	\N	\N	23.620000	\N	GENERATED	2025-11-04 12:45:11.613229+01
b82f9708-3bde-4b99-990c-2c0a371b1937	d2c980bc-c787-4166-8e74-d074800bf867	2025-04-14	\N	\N	\N	23.650000	\N	GENERATED	2025-11-04 12:45:11.6141+01
b4ded25f-4cb6-4f27-9386-1d8469d61f35	d2c980bc-c787-4166-8e74-d074800bf867	2025-04-15	\N	\N	\N	23.690000	\N	GENERATED	2025-11-04 12:45:11.615198+01
19799111-8669-4f3b-844b-032de4a968f9	d2c980bc-c787-4166-8e74-d074800bf867	2025-04-16	\N	\N	\N	23.730000	\N	GENERATED	2025-11-04 12:45:11.616171+01
e9be8626-18b8-4e56-aea1-e6106b63682a	d2c980bc-c787-4166-8e74-d074800bf867	2025-04-17	\N	\N	\N	23.870000	\N	GENERATED	2025-11-04 12:45:11.617186+01
88062694-9e60-4176-91d0-d239141906db	d2c980bc-c787-4166-8e74-d074800bf867	2025-04-18	\N	\N	\N	23.690000	\N	GENERATED	2025-11-04 12:45:11.618152+01
93e8789e-a49f-418f-a3d4-e4e2b0c1fe1e	d2c980bc-c787-4166-8e74-d074800bf867	2025-04-19	\N	\N	\N	23.900000	\N	GENERATED	2025-11-04 12:45:11.619152+01
14f64851-689b-4830-a9fe-c0e623f1b027	d2c980bc-c787-4166-8e74-d074800bf867	2025-04-20	\N	\N	\N	23.720000	\N	GENERATED	2025-11-04 12:45:11.620092+01
84077f09-4926-430d-a228-8b120871b379	d2c980bc-c787-4166-8e74-d074800bf867	2025-04-21	\N	\N	\N	23.680000	\N	GENERATED	2025-11-04 12:45:11.621133+01
aab2f87e-43b6-4e62-8780-376a1e85e56c	d2c980bc-c787-4166-8e74-d074800bf867	2025-04-22	\N	\N	\N	23.920000	\N	GENERATED	2025-11-04 12:45:11.622056+01
96ec5216-770d-4606-a33d-925f2e573950	d2c980bc-c787-4166-8e74-d074800bf867	2025-04-23	\N	\N	\N	23.710000	\N	GENERATED	2025-11-04 12:45:11.623001+01
2be327d6-d515-4cda-b9e8-0c813dcdb444	d2c980bc-c787-4166-8e74-d074800bf867	2025-04-24	\N	\N	\N	23.640000	\N	GENERATED	2025-11-04 12:45:11.623929+01
8dc7cf68-ae18-4dba-ba52-c56cca58514a	d2c980bc-c787-4166-8e74-d074800bf867	2025-04-25	\N	\N	\N	23.820000	\N	GENERATED	2025-11-04 12:45:11.624936+01
fbe628db-6fe0-41e5-866f-3a294e74f41b	d2c980bc-c787-4166-8e74-d074800bf867	2025-04-26	\N	\N	\N	23.990000	\N	GENERATED	2025-11-04 12:45:11.625844+01
fd170a60-5718-4a60-a96a-6b7a81d1bc92	d2c980bc-c787-4166-8e74-d074800bf867	2025-04-27	\N	\N	\N	23.960000	\N	GENERATED	2025-11-04 12:45:11.626764+01
3300fbf5-4dba-475e-b4a1-32ac113c907a	d2c980bc-c787-4166-8e74-d074800bf867	2025-04-28	\N	\N	\N	24.110000	\N	GENERATED	2025-11-04 12:45:11.627734+01
eeda46c2-76aa-4608-a171-50f96e29208d	d2c980bc-c787-4166-8e74-d074800bf867	2025-04-29	\N	\N	\N	23.980000	\N	GENERATED	2025-11-04 12:45:11.628652+01
716a2837-5ee1-45b0-a985-7506e635a7fd	d2c980bc-c787-4166-8e74-d074800bf867	2025-04-30	\N	\N	\N	23.930000	\N	GENERATED	2025-11-04 12:45:11.62957+01
01820ee2-442e-4dee-b29d-f68eab12e137	d2c980bc-c787-4166-8e74-d074800bf867	2025-05-01	\N	\N	\N	23.720000	\N	GENERATED	2025-11-04 12:45:11.630498+01
93d23416-4168-44e8-9b44-dbfa2c190ab6	d2c980bc-c787-4166-8e74-d074800bf867	2025-05-02	\N	\N	\N	23.760000	\N	GENERATED	2025-11-04 12:45:11.631806+01
a81e0a0b-afe3-4aca-aa62-38f9a2505e52	d2c980bc-c787-4166-8e74-d074800bf867	2025-05-03	\N	\N	\N	23.740000	\N	GENERATED	2025-11-04 12:45:11.632875+01
451bf363-952f-4957-a68f-28e8f64773db	d2c980bc-c787-4166-8e74-d074800bf867	2025-05-04	\N	\N	\N	24.110000	\N	GENERATED	2025-11-04 12:45:11.633833+01
f5cd4ce0-7cc8-4f8e-81ad-2f6ba2b230ec	d2c980bc-c787-4166-8e74-d074800bf867	2025-05-05	\N	\N	\N	23.860000	\N	GENERATED	2025-11-04 12:45:11.634812+01
73b6da65-6db2-4f25-aedb-f0bd42313026	d2c980bc-c787-4166-8e74-d074800bf867	2025-05-06	\N	\N	\N	24.050000	\N	GENERATED	2025-11-04 12:45:11.635777+01
d3dd6ec5-71dd-447d-ac4d-5d7bfa5be630	d2c980bc-c787-4166-8e74-d074800bf867	2025-05-07	\N	\N	\N	23.870000	\N	GENERATED	2025-11-04 12:45:11.637002+01
81766e44-be01-40b1-997a-7b7bcea9ebf4	d2c980bc-c787-4166-8e74-d074800bf867	2025-05-08	\N	\N	\N	23.940000	\N	GENERATED	2025-11-04 12:45:11.637942+01
a6566ba7-a62c-44e1-90ff-4fa60ba79b60	d2c980bc-c787-4166-8e74-d074800bf867	2025-05-09	\N	\N	\N	23.800000	\N	GENERATED	2025-11-04 12:45:11.639138+01
f6be5b77-7a64-4785-9de3-ac7fa27c5d20	d2c980bc-c787-4166-8e74-d074800bf867	2025-05-10	\N	\N	\N	24.000000	\N	GENERATED	2025-11-04 12:45:11.640102+01
2f611df4-10df-4c01-a5e0-38feb2d94bd7	d2c980bc-c787-4166-8e74-d074800bf867	2025-05-11	\N	\N	\N	23.770000	\N	GENERATED	2025-11-04 12:45:11.641107+01
6f329a57-49f1-4ab1-8ba5-d9e1dc38f770	d2c980bc-c787-4166-8e74-d074800bf867	2025-05-12	\N	\N	\N	23.950000	\N	GENERATED	2025-11-04 12:45:11.6421+01
0f23ca70-92b8-4fcd-a77d-625449de8f6c	d2c980bc-c787-4166-8e74-d074800bf867	2025-05-13	\N	\N	\N	24.080000	\N	GENERATED	2025-11-04 12:45:11.642865+01
128b2649-e9de-400f-ab3f-fb4f030e41af	d2c980bc-c787-4166-8e74-d074800bf867	2025-05-14	\N	\N	\N	24.150000	\N	GENERATED	2025-11-04 12:45:11.643927+01
e3328991-a593-418f-8124-30729b99ce30	d2c980bc-c787-4166-8e74-d074800bf867	2025-05-15	\N	\N	\N	23.850000	\N	GENERATED	2025-11-04 12:45:11.644893+01
0bb1d0c2-db61-4f0d-8fad-accc82ddce3d	d2c980bc-c787-4166-8e74-d074800bf867	2025-05-16	\N	\N	\N	24.150000	\N	GENERATED	2025-11-04 12:45:11.645809+01
f2b3c3b5-54be-4efa-9d6d-066d56785847	d2c980bc-c787-4166-8e74-d074800bf867	2025-05-17	\N	\N	\N	24.170000	\N	GENERATED	2025-11-04 12:45:11.646771+01
29c3c590-21bd-4cf2-87f8-6a8e93eb8dc8	d2c980bc-c787-4166-8e74-d074800bf867	2025-05-18	\N	\N	\N	23.950000	\N	GENERATED	2025-11-04 12:45:11.648001+01
e12427ad-5eea-48f0-94e7-41ecac2b6a2c	d2c980bc-c787-4166-8e74-d074800bf867	2025-05-19	\N	\N	\N	23.770000	\N	GENERATED	2025-11-04 12:45:11.649004+01
63a44533-6917-418f-8a7d-e1a713943948	d2c980bc-c787-4166-8e74-d074800bf867	2025-05-20	\N	\N	\N	24.110000	\N	GENERATED	2025-11-04 12:45:11.649915+01
77020edb-01d0-4a55-b190-77c3b93d7554	d2c980bc-c787-4166-8e74-d074800bf867	2025-05-21	\N	\N	\N	24.010000	\N	GENERATED	2025-11-04 12:45:11.650943+01
507f6580-75ba-4d4c-9fb7-a1cd0c95c36c	d2c980bc-c787-4166-8e74-d074800bf867	2025-05-22	\N	\N	\N	23.910000	\N	GENERATED	2025-11-04 12:45:11.651984+01
2774bd2c-6821-454a-ac48-80238f7dd680	d2c980bc-c787-4166-8e74-d074800bf867	2025-05-23	\N	\N	\N	23.950000	\N	GENERATED	2025-11-04 12:45:11.652778+01
6fdce426-4cd7-43c4-8643-dcb09eb2fa5e	d2c980bc-c787-4166-8e74-d074800bf867	2025-05-24	\N	\N	\N	23.810000	\N	GENERATED	2025-11-04 12:45:11.653541+01
d1ab3f9a-7e2a-409c-b891-3ed2bd53a23a	d2c980bc-c787-4166-8e74-d074800bf867	2025-05-25	\N	\N	\N	24.020000	\N	GENERATED	2025-11-04 12:45:11.654212+01
1f85fcf7-12e9-4ee4-8484-98c90fd9a195	d2c980bc-c787-4166-8e74-d074800bf867	2025-05-26	\N	\N	\N	23.900000	\N	GENERATED	2025-11-04 12:45:11.655019+01
9a156ce7-a89f-4432-b052-b5258fcdb291	d2c980bc-c787-4166-8e74-d074800bf867	2025-05-27	\N	\N	\N	23.890000	\N	GENERATED	2025-11-04 12:45:11.655707+01
1aea2055-dabc-4700-aaed-1493ce213b98	d2c980bc-c787-4166-8e74-d074800bf867	2025-05-28	\N	\N	\N	24.040000	\N	GENERATED	2025-11-04 12:45:11.656368+01
a603f424-8f0c-47d0-b136-302fa03950f1	d2c980bc-c787-4166-8e74-d074800bf867	2025-05-29	\N	\N	\N	23.880000	\N	GENERATED	2025-11-04 12:45:11.657037+01
680f05dd-1631-4711-984e-8192d7221139	d2c980bc-c787-4166-8e74-d074800bf867	2025-05-30	\N	\N	\N	23.900000	\N	GENERATED	2025-11-04 12:45:11.657692+01
f11f8fc2-fbe8-4766-9e9c-09868475115b	d2c980bc-c787-4166-8e74-d074800bf867	2025-05-31	\N	\N	\N	23.910000	\N	GENERATED	2025-11-04 12:45:11.658342+01
ac41cd87-efa9-49f0-93cb-4ecc512adba5	d2c980bc-c787-4166-8e74-d074800bf867	2025-06-01	\N	\N	\N	23.980000	\N	GENERATED	2025-11-04 12:45:11.659019+01
9a67e25e-5761-48f0-a260-97bfccb0d704	d2c980bc-c787-4166-8e74-d074800bf867	2025-06-02	\N	\N	\N	23.990000	\N	GENERATED	2025-11-04 12:45:11.659679+01
d4d263c4-ee6d-4c0c-85c3-102556be7f46	d2c980bc-c787-4166-8e74-d074800bf867	2025-06-03	\N	\N	\N	24.050000	\N	GENERATED	2025-11-04 12:45:11.660326+01
c7d4ba92-c9d9-438a-bbd8-d8023002d66f	d2c980bc-c787-4166-8e74-d074800bf867	2025-06-04	\N	\N	\N	24.110000	\N	GENERATED	2025-11-04 12:45:11.660989+01
43c3777c-9ae6-4721-b8d5-26dafa205e0f	d2c980bc-c787-4166-8e74-d074800bf867	2025-06-05	\N	\N	\N	24.280000	\N	GENERATED	2025-11-04 12:45:11.661656+01
a189aadd-e4e2-415e-8be9-c1fa5e70e2c5	d2c980bc-c787-4166-8e74-d074800bf867	2025-06-06	\N	\N	\N	23.860000	\N	GENERATED	2025-11-04 12:45:11.662349+01
8c7bc1d1-bbdf-495e-a5dc-db7e6fbc3851	d2c980bc-c787-4166-8e74-d074800bf867	2025-06-07	\N	\N	\N	24.190000	\N	GENERATED	2025-11-04 12:45:11.66314+01
a2340691-dc2f-4662-9a33-2aee79838140	d2c980bc-c787-4166-8e74-d074800bf867	2025-06-08	\N	\N	\N	23.910000	\N	GENERATED	2025-11-04 12:45:11.663811+01
d9005354-13aa-400a-89a0-84c70af50642	d2c980bc-c787-4166-8e74-d074800bf867	2025-06-09	\N	\N	\N	24.190000	\N	GENERATED	2025-11-04 12:45:11.664511+01
49dd7863-b46e-4d53-b01e-b6a886bfc3e4	d2c980bc-c787-4166-8e74-d074800bf867	2025-06-10	\N	\N	\N	24.050000	\N	GENERATED	2025-11-04 12:45:11.66522+01
33383b93-29c7-4f38-82c0-b00bd573977e	d2c980bc-c787-4166-8e74-d074800bf867	2025-06-11	\N	\N	\N	23.950000	\N	GENERATED	2025-11-04 12:45:11.665921+01
76d76a44-a309-42d6-a4d6-ccc946881c1e	d2c980bc-c787-4166-8e74-d074800bf867	2025-06-12	\N	\N	\N	24.210000	\N	GENERATED	2025-11-04 12:45:11.666639+01
afc2d6cc-1724-407c-b564-6e7ea3044f16	d2c980bc-c787-4166-8e74-d074800bf867	2025-06-13	\N	\N	\N	24.110000	\N	GENERATED	2025-11-04 12:45:11.667362+01
499a272b-8b01-47c5-8cd4-b1150342bfb0	d2c980bc-c787-4166-8e74-d074800bf867	2025-06-14	\N	\N	\N	24.080000	\N	GENERATED	2025-11-04 12:45:11.668032+01
76da7210-91e2-4265-91d1-dd78f275a95d	d2c980bc-c787-4166-8e74-d074800bf867	2025-06-15	\N	\N	\N	24.200000	\N	GENERATED	2025-11-04 12:45:11.66869+01
9566fc88-1c27-46fa-841f-9e4b0def46a4	d2c980bc-c787-4166-8e74-d074800bf867	2025-06-16	\N	\N	\N	24.230000	\N	GENERATED	2025-11-04 12:45:11.669322+01
bf94315d-4190-4c1b-8cfe-ae7b3b8cc224	d2c980bc-c787-4166-8e74-d074800bf867	2025-06-17	\N	\N	\N	24.360000	\N	GENERATED	2025-11-04 12:45:11.669969+01
49d1e9da-aa0f-4541-a0d2-3a5155377529	d2c980bc-c787-4166-8e74-d074800bf867	2025-06-18	\N	\N	\N	24.040000	\N	GENERATED	2025-11-04 12:45:11.6707+01
80796404-00cb-47a8-98b4-0ffb65182116	d2c980bc-c787-4166-8e74-d074800bf867	2025-06-19	\N	\N	\N	24.220000	\N	GENERATED	2025-11-04 12:45:11.671337+01
ebcc0f63-32cf-4095-a37b-260ae005acdb	d2c980bc-c787-4166-8e74-d074800bf867	2025-06-20	\N	\N	\N	24.130000	\N	GENERATED	2025-11-04 12:45:11.671998+01
49b66e98-a9df-4ac5-90e5-94e03b8e9e14	d2c980bc-c787-4166-8e74-d074800bf867	2025-06-21	\N	\N	\N	24.060000	\N	GENERATED	2025-11-04 12:45:11.672627+01
5f87d43b-d200-460c-b4a6-20394ad69e5f	d2c980bc-c787-4166-8e74-d074800bf867	2025-06-22	\N	\N	\N	24.190000	\N	GENERATED	2025-11-04 12:45:11.673286+01
1f1a590f-1d77-4981-b10f-604fe5947846	d2c980bc-c787-4166-8e74-d074800bf867	2025-06-23	\N	\N	\N	24.290000	\N	GENERATED	2025-11-04 12:45:11.673933+01
bbfbe7ed-3af7-4e98-86a3-18be80441bee	d2c980bc-c787-4166-8e74-d074800bf867	2025-06-24	\N	\N	\N	24.360000	\N	GENERATED	2025-11-04 12:45:11.67469+01
d8c13b83-f672-443e-b451-044f99e8182a	d2c980bc-c787-4166-8e74-d074800bf867	2025-06-25	\N	\N	\N	24.070000	\N	GENERATED	2025-11-04 12:45:11.675342+01
e6aef41d-1bdd-4fa3-ae33-a4c33aaa3a93	d2c980bc-c787-4166-8e74-d074800bf867	2025-06-26	\N	\N	\N	24.100000	\N	GENERATED	2025-11-04 12:45:11.675975+01
35948cae-ca81-4023-8912-57fa0ae75371	d2c980bc-c787-4166-8e74-d074800bf867	2025-06-27	\N	\N	\N	24.240000	\N	GENERATED	2025-11-04 12:45:11.676607+01
67751bf5-20b5-4063-9699-8b1de3af4f0f	d2c980bc-c787-4166-8e74-d074800bf867	2025-06-28	\N	\N	\N	24.340000	\N	GENERATED	2025-11-04 12:45:11.677247+01
0d43cebe-291d-476d-92f2-5e30bca50f00	d2c980bc-c787-4166-8e74-d074800bf867	2025-06-29	\N	\N	\N	24.000000	\N	GENERATED	2025-11-04 12:45:11.67788+01
57b9b83b-d161-4ace-bbe5-a080b03dcb09	d2c980bc-c787-4166-8e74-d074800bf867	2025-06-30	\N	\N	\N	24.350000	\N	GENERATED	2025-11-04 12:45:11.678544+01
1416dce3-8116-4ed4-bc36-7dd2aedd54b7	d2c980bc-c787-4166-8e74-d074800bf867	2025-07-01	\N	\N	\N	24.180000	\N	GENERATED	2025-11-04 12:45:11.679198+01
03477e78-fced-43d2-b720-ee54029e2d2f	d2c980bc-c787-4166-8e74-d074800bf867	2025-07-02	\N	\N	\N	24.220000	\N	GENERATED	2025-11-04 12:45:11.679825+01
dac790c2-70ec-4caa-90dd-99ab4d49f9a7	d2c980bc-c787-4166-8e74-d074800bf867	2025-07-03	\N	\N	\N	24.210000	\N	GENERATED	2025-11-04 12:45:11.680468+01
8ad5a8a6-96a2-4c5b-8fc2-5fe83be26f62	d2c980bc-c787-4166-8e74-d074800bf867	2025-07-04	\N	\N	\N	24.420000	\N	GENERATED	2025-11-04 12:45:11.681093+01
e6d94e3f-30c8-4b6f-95dc-e972ac0da17a	d2c980bc-c787-4166-8e74-d074800bf867	2025-07-05	\N	\N	\N	24.310000	\N	GENERATED	2025-11-04 12:45:11.681726+01
27e284d4-02db-4f85-ab15-26836c3dc4ce	d2c980bc-c787-4166-8e74-d074800bf867	2025-07-06	\N	\N	\N	24.090000	\N	GENERATED	2025-11-04 12:45:11.682586+01
fc7809b9-e9aa-4445-9de8-50e9833097e6	d2c980bc-c787-4166-8e74-d074800bf867	2025-07-07	\N	\N	\N	24.250000	\N	GENERATED	2025-11-04 12:45:11.68368+01
1dd43388-3f6c-401a-9edc-17b2be70bd7d	d2c980bc-c787-4166-8e74-d074800bf867	2025-07-08	\N	\N	\N	24.320000	\N	GENERATED	2025-11-04 12:45:11.68434+01
f9676749-21e7-4019-95aa-a90d4f4fa335	d2c980bc-c787-4166-8e74-d074800bf867	2025-07-09	\N	\N	\N	24.080000	\N	GENERATED	2025-11-04 12:45:11.684981+01
85f422a7-e229-444a-8070-8da169d5aace	d2c980bc-c787-4166-8e74-d074800bf867	2025-07-10	\N	\N	\N	24.090000	\N	GENERATED	2025-11-04 12:45:11.685641+01
a50b2321-b9c4-496e-a84b-b19d539ec80d	d2c980bc-c787-4166-8e74-d074800bf867	2025-07-11	\N	\N	\N	24.180000	\N	GENERATED	2025-11-04 12:45:11.686294+01
c6b942d4-0989-415a-a6d9-14693b2af361	d2c980bc-c787-4166-8e74-d074800bf867	2025-07-12	\N	\N	\N	24.240000	\N	GENERATED	2025-11-04 12:45:11.68693+01
17039487-f71b-418d-bde3-b99e18972e54	d2c980bc-c787-4166-8e74-d074800bf867	2025-07-13	\N	\N	\N	24.290000	\N	GENERATED	2025-11-04 12:45:11.68762+01
9f0eb470-4e3d-45f2-b482-2e392230b45f	d2c980bc-c787-4166-8e74-d074800bf867	2025-07-14	\N	\N	\N	24.330000	\N	GENERATED	2025-11-04 12:45:11.688258+01
19619818-fce2-4fff-b3d3-4ef179a88dcd	d2c980bc-c787-4166-8e74-d074800bf867	2025-07-15	\N	\N	\N	24.070000	\N	GENERATED	2025-11-04 12:45:11.68893+01
0323f9e4-b3e8-4be0-9d51-88cf797f1ca2	d2c980bc-c787-4166-8e74-d074800bf867	2025-07-16	\N	\N	\N	24.310000	\N	GENERATED	2025-11-04 12:45:11.68958+01
21d96ffc-2efc-40b0-832d-56107256ca60	d2c980bc-c787-4166-8e74-d074800bf867	2025-07-17	\N	\N	\N	24.260000	\N	GENERATED	2025-11-04 12:45:11.690219+01
5f278ece-5e9d-4f28-8173-4c97ae10aeb4	d2c980bc-c787-4166-8e74-d074800bf867	2025-07-18	\N	\N	\N	24.250000	\N	GENERATED	2025-11-04 12:45:11.690852+01
0c6c4b7d-2358-4901-a739-33962e61bf11	d2c980bc-c787-4166-8e74-d074800bf867	2025-07-19	\N	\N	\N	24.330000	\N	GENERATED	2025-11-04 12:45:11.691486+01
94d4b8d4-20f2-4c5a-8080-2faaf63a3a0e	d2c980bc-c787-4166-8e74-d074800bf867	2025-07-20	\N	\N	\N	24.190000	\N	GENERATED	2025-11-04 12:45:11.692116+01
c1768ccd-6e22-4181-800e-dfeb903f8498	d2c980bc-c787-4166-8e74-d074800bf867	2025-07-21	\N	\N	\N	24.210000	\N	GENERATED	2025-11-04 12:45:11.692783+01
02299463-799e-471c-8a98-e942c2561c4a	d2c980bc-c787-4166-8e74-d074800bf867	2025-07-22	\N	\N	\N	24.140000	\N	GENERATED	2025-11-04 12:45:11.693437+01
23502e3d-2e5f-4081-9797-d38ee273fe12	d2c980bc-c787-4166-8e74-d074800bf867	2025-07-23	\N	\N	\N	24.360000	\N	GENERATED	2025-11-04 12:45:11.694071+01
09b52e6e-4d80-462f-8b2c-39f065975b95	d2c980bc-c787-4166-8e74-d074800bf867	2025-07-24	\N	\N	\N	24.210000	\N	GENERATED	2025-11-04 12:45:11.694802+01
f8ed1188-82bf-4a4e-a85e-e4072ddd1fcb	d2c980bc-c787-4166-8e74-d074800bf867	2025-07-25	\N	\N	\N	24.310000	\N	GENERATED	2025-11-04 12:45:11.69547+01
1a1475a8-2c06-4d6c-a0be-0b40662ff374	d2c980bc-c787-4166-8e74-d074800bf867	2025-07-26	\N	\N	\N	24.410000	\N	GENERATED	2025-11-04 12:45:11.696113+01
e13fe288-5029-4bdc-a7a1-ee311d8f68b1	d2c980bc-c787-4166-8e74-d074800bf867	2025-07-27	\N	\N	\N	24.220000	\N	GENERATED	2025-11-04 12:45:11.696833+01
f5a7b866-5251-47e1-8db5-9a75266b6e76	d2c980bc-c787-4166-8e74-d074800bf867	2025-07-28	\N	\N	\N	24.510000	\N	GENERATED	2025-11-04 12:45:11.697478+01
d9aa70fe-7830-4256-968b-6a7031f2c033	d2c980bc-c787-4166-8e74-d074800bf867	2025-07-29	\N	\N	\N	24.430000	\N	GENERATED	2025-11-04 12:45:11.698104+01
8201e630-585b-4c23-a88b-2cd086b6df19	d2c980bc-c787-4166-8e74-d074800bf867	2025-07-30	\N	\N	\N	24.520000	\N	GENERATED	2025-11-04 12:45:11.699014+01
a37f42c3-953a-4478-bc49-a57292b0b267	d2c980bc-c787-4166-8e74-d074800bf867	2025-07-31	\N	\N	\N	24.260000	\N	GENERATED	2025-11-04 12:45:11.700124+01
01c52a85-fa6c-42ff-91dd-846e02cb7ece	d2c980bc-c787-4166-8e74-d074800bf867	2025-08-01	\N	\N	\N	24.330000	\N	GENERATED	2025-11-04 12:45:11.701666+01
c44e47d0-b24d-47f5-80b9-8f6f8873381b	d2c980bc-c787-4166-8e74-d074800bf867	2025-08-02	\N	\N	\N	24.170000	\N	GENERATED	2025-11-04 12:45:11.702456+01
f474a6e2-30c5-4635-ba41-be852bc669ce	d2c980bc-c787-4166-8e74-d074800bf867	2025-08-03	\N	\N	\N	24.300000	\N	GENERATED	2025-11-04 12:45:11.703207+01
76fb9a7c-9ffc-471c-a96a-8a3878b82fc3	d2c980bc-c787-4166-8e74-d074800bf867	2025-08-04	\N	\N	\N	24.360000	\N	GENERATED	2025-11-04 12:45:11.703861+01
6951262e-069d-4441-8d4e-b1dabc0c2c63	d2c980bc-c787-4166-8e74-d074800bf867	2025-08-05	\N	\N	\N	24.570000	\N	GENERATED	2025-11-04 12:45:11.704519+01
a3f5fc8c-b06e-4e92-9c3e-c00163a9a8f2	d2c980bc-c787-4166-8e74-d074800bf867	2025-08-06	\N	\N	\N	24.400000	\N	GENERATED	2025-11-04 12:45:11.705225+01
1fd0ac4a-2443-42ff-97df-bf4dc49c49eb	d2c980bc-c787-4166-8e74-d074800bf867	2025-08-07	\N	\N	\N	24.210000	\N	GENERATED	2025-11-04 12:45:11.705862+01
eb1f97ab-2953-4959-928b-fb8845791849	d2c980bc-c787-4166-8e74-d074800bf867	2025-08-08	\N	\N	\N	24.200000	\N	GENERATED	2025-11-04 12:45:11.706534+01
5f314d66-7ba9-4c66-8fee-6514fbb413a2	d2c980bc-c787-4166-8e74-d074800bf867	2025-08-09	\N	\N	\N	24.430000	\N	GENERATED	2025-11-04 12:45:11.70717+01
8a0ea34c-b198-4537-9da5-2e685eda3ac0	d2c980bc-c787-4166-8e74-d074800bf867	2025-08-10	\N	\N	\N	24.360000	\N	GENERATED	2025-11-04 12:45:11.707808+01
a8da5839-a77c-450f-aa29-ec757cc519c0	d2c980bc-c787-4166-8e74-d074800bf867	2025-08-11	\N	\N	\N	24.380000	\N	GENERATED	2025-11-04 12:45:11.70851+01
461c734a-3fc1-4869-b7f9-72da923dc923	d2c980bc-c787-4166-8e74-d074800bf867	2025-08-12	\N	\N	\N	24.490000	\N	GENERATED	2025-11-04 12:45:11.709596+01
82ce8932-6541-4d60-8273-7c372956cd51	d2c980bc-c787-4166-8e74-d074800bf867	2025-08-13	\N	\N	\N	24.460000	\N	GENERATED	2025-11-04 12:45:11.71024+01
0b9f650f-ab90-4c62-b270-157615056776	d2c980bc-c787-4166-8e74-d074800bf867	2025-08-14	\N	\N	\N	24.300000	\N	GENERATED	2025-11-04 12:45:11.710887+01
563f907a-b5f6-4054-889d-c354815b7a27	d2c980bc-c787-4166-8e74-d074800bf867	2025-08-15	\N	\N	\N	24.360000	\N	GENERATED	2025-11-04 12:45:11.711546+01
bc2e6eca-4c2d-4949-bad4-8648ba27fa30	d2c980bc-c787-4166-8e74-d074800bf867	2025-08-16	\N	\N	\N	24.380000	\N	GENERATED	2025-11-04 12:45:11.712181+01
fdf8a4e3-72b6-4dd4-a278-864d772d4859	d2c980bc-c787-4166-8e74-d074800bf867	2025-08-17	\N	\N	\N	24.470000	\N	GENERATED	2025-11-04 12:45:11.712848+01
cfefa2c5-ca66-4b15-8041-48fd78d49514	d2c980bc-c787-4166-8e74-d074800bf867	2025-08-18	\N	\N	\N	24.460000	\N	GENERATED	2025-11-04 12:45:11.713483+01
7de46561-566c-4c21-bc5e-ff5cdd79340e	d2c980bc-c787-4166-8e74-d074800bf867	2025-08-19	\N	\N	\N	24.590000	\N	GENERATED	2025-11-04 12:45:11.71422+01
73cd8da1-9575-4799-9703-d2c9b556b493	d2c980bc-c787-4166-8e74-d074800bf867	2025-08-20	\N	\N	\N	24.270000	\N	GENERATED	2025-11-04 12:45:11.71496+01
9f40cac6-dc1d-499c-85dc-8c30f1f65f52	d2c980bc-c787-4166-8e74-d074800bf867	2025-08-21	\N	\N	\N	24.610000	\N	GENERATED	2025-11-04 12:45:11.715611+01
ab1ee5e8-95b9-4918-b71c-09f35d3680f3	d2c980bc-c787-4166-8e74-d074800bf867	2025-08-22	\N	\N	\N	24.330000	\N	GENERATED	2025-11-04 12:45:11.716243+01
c450d0a4-ec30-47ee-a948-af6c7d6e7151	d2c980bc-c787-4166-8e74-d074800bf867	2025-08-23	\N	\N	\N	24.490000	\N	GENERATED	2025-11-04 12:45:11.71689+01
e8966b0e-1902-46db-b4fb-f71e87009b33	d2c980bc-c787-4166-8e74-d074800bf867	2025-08-24	\N	\N	\N	24.650000	\N	GENERATED	2025-11-04 12:45:11.717534+01
b708b3d3-d573-4915-9d23-60361798b656	d2c980bc-c787-4166-8e74-d074800bf867	2025-08-25	\N	\N	\N	24.620000	\N	GENERATED	2025-11-04 12:45:11.718174+01
e45fe90d-3aa8-4517-b70f-fda503a51051	d2c980bc-c787-4166-8e74-d074800bf867	2025-08-26	\N	\N	\N	24.670000	\N	GENERATED	2025-11-04 12:45:11.7188+01
554983d0-e7f5-4582-aab0-ba33b455acb8	d2c980bc-c787-4166-8e74-d074800bf867	2025-08-27	\N	\N	\N	24.460000	\N	GENERATED	2025-11-04 12:45:11.719445+01
7b2b7611-13c3-4fec-a85f-8c7e46c94961	d2c980bc-c787-4166-8e74-d074800bf867	2025-08-28	\N	\N	\N	24.600000	\N	GENERATED	2025-11-04 12:45:11.720067+01
bab2c988-5ef2-4cb4-98d3-bf10893acb29	d2c980bc-c787-4166-8e74-d074800bf867	2025-08-29	\N	\N	\N	24.450000	\N	GENERATED	2025-11-04 12:45:11.720698+01
b512b939-40f0-4ac8-8f46-50a09e093a03	d2c980bc-c787-4166-8e74-d074800bf867	2025-08-30	\N	\N	\N	24.420000	\N	GENERATED	2025-11-04 12:45:11.721324+01
7a672286-1ca9-40b9-94f4-0e523c357a3e	d2c980bc-c787-4166-8e74-d074800bf867	2025-08-31	\N	\N	\N	24.300000	\N	GENERATED	2025-11-04 12:45:11.721956+01
6d5707f0-f0cd-4a68-ae70-07c242e5b865	d2c980bc-c787-4166-8e74-d074800bf867	2025-09-01	\N	\N	\N	24.680000	\N	GENERATED	2025-11-04 12:45:11.722586+01
24713969-9246-4fab-96d6-5e4ac15d1911	d2c980bc-c787-4166-8e74-d074800bf867	2025-09-02	\N	\N	\N	24.320000	\N	GENERATED	2025-11-04 12:45:11.723211+01
2ec27c50-9229-4b6a-9204-952d3378ecad	d2c980bc-c787-4166-8e74-d074800bf867	2025-09-03	\N	\N	\N	24.390000	\N	GENERATED	2025-11-04 12:45:11.723914+01
b44b1d88-27b7-4ff3-a191-2dcdb6323cd4	d2c980bc-c787-4166-8e74-d074800bf867	2025-09-04	\N	\N	\N	24.510000	\N	GENERATED	2025-11-04 12:45:11.724574+01
b80d7320-04ae-4f58-8f89-09b63dd7fca1	d2c980bc-c787-4166-8e74-d074800bf867	2025-09-05	\N	\N	\N	24.500000	\N	GENERATED	2025-11-04 12:45:11.725222+01
4f77193d-ca21-4e9c-af9c-49d0f8494cc5	d2c980bc-c787-4166-8e74-d074800bf867	2025-09-06	\N	\N	\N	24.550000	\N	GENERATED	2025-11-04 12:45:11.725869+01
3698b815-4ace-4c08-95a5-88366b4256f6	d2c980bc-c787-4166-8e74-d074800bf867	2025-09-07	\N	\N	\N	24.460000	\N	GENERATED	2025-11-04 12:45:11.726508+01
bef0f77c-96fa-4d57-a5a5-be6677c6a74b	d2c980bc-c787-4166-8e74-d074800bf867	2025-09-08	\N	\N	\N	24.420000	\N	GENERATED	2025-11-04 12:45:11.727133+01
6dc9b99f-6a1c-406c-820e-a7ae05f1b04b	d2c980bc-c787-4166-8e74-d074800bf867	2025-09-09	\N	\N	\N	24.540000	\N	GENERATED	2025-11-04 12:45:11.727773+01
e5a931a6-1ec9-4cbc-bbc5-d7bd5b954ad7	d2c980bc-c787-4166-8e74-d074800bf867	2025-09-10	\N	\N	\N	24.730000	\N	GENERATED	2025-11-04 12:45:11.728415+01
3ae2e976-5636-4bbc-9e20-5ab73f3f2e5c	d2c980bc-c787-4166-8e74-d074800bf867	2025-09-11	\N	\N	\N	24.630000	\N	GENERATED	2025-11-04 12:45:11.729566+01
17ec849f-8d79-45b3-8cc4-571f8c80567f	d2c980bc-c787-4166-8e74-d074800bf867	2025-09-12	\N	\N	\N	24.390000	\N	GENERATED	2025-11-04 12:45:11.730257+01
711d1428-d5cb-4422-acc2-925c08fa33b4	d2c980bc-c787-4166-8e74-d074800bf867	2025-09-13	\N	\N	\N	24.490000	\N	GENERATED	2025-11-04 12:45:11.730904+01
d44a63fe-0a02-44f8-9335-b2cd1cf14a6c	d2c980bc-c787-4166-8e74-d074800bf867	2025-09-14	\N	\N	\N	24.430000	\N	GENERATED	2025-11-04 12:45:11.731583+01
79df60e3-99ee-4162-be28-c4e44ffe68f0	d2c980bc-c787-4166-8e74-d074800bf867	2025-09-15	\N	\N	\N	24.580000	\N	GENERATED	2025-11-04 12:45:11.732219+01
d9798bfb-e517-4174-83f2-de4d3d46f8d6	d2c980bc-c787-4166-8e74-d074800bf867	2025-09-16	\N	\N	\N	24.520000	\N	GENERATED	2025-11-04 12:45:11.732856+01
37a8c8a4-683d-499f-9da1-c980b475c842	d2c980bc-c787-4166-8e74-d074800bf867	2025-09-17	\N	\N	\N	24.750000	\N	GENERATED	2025-11-04 12:45:11.73349+01
972a2f67-6355-4909-b439-262d6c856c83	d2c980bc-c787-4166-8e74-d074800bf867	2025-09-18	\N	\N	\N	24.800000	\N	GENERATED	2025-11-04 12:45:11.734114+01
a73927ee-9ea5-429e-a549-1d8d5209c47e	d2c980bc-c787-4166-8e74-d074800bf867	2025-09-19	\N	\N	\N	24.550000	\N	GENERATED	2025-11-04 12:45:11.734821+01
04503e7d-d6f8-465c-a67c-49894141f42d	d2c980bc-c787-4166-8e74-d074800bf867	2025-09-20	\N	\N	\N	24.740000	\N	GENERATED	2025-11-04 12:45:11.735455+01
c83ed1a6-842a-49a1-a409-74eee6f68fdf	d2c980bc-c787-4166-8e74-d074800bf867	2025-09-21	\N	\N	\N	24.720000	\N	GENERATED	2025-11-04 12:45:11.736096+01
6c67d2f5-b2b2-4d94-a669-abb0bbefb02f	d2c980bc-c787-4166-8e74-d074800bf867	2025-09-22	\N	\N	\N	24.560000	\N	GENERATED	2025-11-04 12:45:11.736739+01
404f9e97-97e0-4d15-9911-3c820bbf3951	d2c980bc-c787-4166-8e74-d074800bf867	2025-09-23	\N	\N	\N	24.620000	\N	GENERATED	2025-11-04 12:45:11.737365+01
89b74657-f919-4065-b146-fa649b2b4214	d2c980bc-c787-4166-8e74-d074800bf867	2025-09-24	\N	\N	\N	24.610000	\N	GENERATED	2025-11-04 12:45:11.737996+01
beedb1ad-1005-452c-94f1-34f202816225	d2c980bc-c787-4166-8e74-d074800bf867	2025-09-25	\N	\N	\N	24.570000	\N	GENERATED	2025-11-04 12:45:11.738641+01
71d14957-3ffc-43a9-90ab-4bf009ec73bc	d2c980bc-c787-4166-8e74-d074800bf867	2025-09-26	\N	\N	\N	24.860000	\N	GENERATED	2025-11-04 12:45:11.739267+01
6d8d5f4d-5c7f-45f0-9fdf-454c19e862b5	d2c980bc-c787-4166-8e74-d074800bf867	2025-09-27	\N	\N	\N	24.670000	\N	GENERATED	2025-11-04 12:45:11.739903+01
1bf2be65-dbcb-4ab2-a285-0740f862641b	d2c980bc-c787-4166-8e74-d074800bf867	2025-09-28	\N	\N	\N	24.810000	\N	GENERATED	2025-11-04 12:45:11.740535+01
13069548-89e9-4cda-8aaf-9dcd12c0fcd9	d2c980bc-c787-4166-8e74-d074800bf867	2025-09-29	\N	\N	\N	24.530000	\N	GENERATED	2025-11-04 12:45:11.741155+01
47e4da12-2a78-4f7b-90ff-341f202c8161	d2c980bc-c787-4166-8e74-d074800bf867	2025-09-30	\N	\N	\N	24.720000	\N	GENERATED	2025-11-04 12:45:11.741808+01
630e7596-72d3-48d0-9918-0d57b1308666	d2c980bc-c787-4166-8e74-d074800bf867	2025-10-01	\N	\N	\N	24.720000	\N	GENERATED	2025-11-04 12:45:11.742454+01
1bece8d4-9de5-47e4-a86f-8078f45606cd	d2c980bc-c787-4166-8e74-d074800bf867	2025-10-02	\N	\N	\N	24.890000	\N	GENERATED	2025-11-04 12:45:11.743082+01
4378d34b-0314-4001-9bd2-5cfc0931f555	d2c980bc-c787-4166-8e74-d074800bf867	2025-10-03	\N	\N	\N	24.460000	\N	GENERATED	2025-11-04 12:45:11.743733+01
aaba4304-4019-4452-adbc-6781d536299d	d2c980bc-c787-4166-8e74-d074800bf867	2025-10-04	\N	\N	\N	24.790000	\N	GENERATED	2025-11-04 12:45:11.744364+01
afe376bd-9fa3-4c7b-a7d3-33e9476ab683	d2c980bc-c787-4166-8e74-d074800bf867	2025-10-05	\N	\N	\N	24.470000	\N	GENERATED	2025-11-04 12:45:11.745026+01
c8f5b5e4-f3d9-43e6-b3d4-9618ecb408f4	d2c980bc-c787-4166-8e74-d074800bf867	2025-10-06	\N	\N	\N	24.870000	\N	GENERATED	2025-11-04 12:45:11.74579+01
330ead34-ef00-4e51-92af-cdd074171f20	d2c980bc-c787-4166-8e74-d074800bf867	2025-10-07	\N	\N	\N	24.770000	\N	GENERATED	2025-11-04 12:45:11.746527+01
1df7dd09-04fd-4308-ba6e-513d3e213669	d2c980bc-c787-4166-8e74-d074800bf867	2025-10-08	\N	\N	\N	24.660000	\N	GENERATED	2025-11-04 12:45:11.747181+01
09ee9d63-f04f-44de-bd9f-88fa0719877e	d2c980bc-c787-4166-8e74-d074800bf867	2025-10-09	\N	\N	\N	24.580000	\N	GENERATED	2025-11-04 12:45:11.748016+01
7183f5ad-c0ef-414a-9d36-0e7a45b0e527	d2c980bc-c787-4166-8e74-d074800bf867	2025-10-10	\N	\N	\N	24.640000	\N	GENERATED	2025-11-04 12:45:11.748676+01
beb96bd9-bbce-4c11-9394-c6f1be76c9c1	d2c980bc-c787-4166-8e74-d074800bf867	2025-10-11	\N	\N	\N	24.870000	\N	GENERATED	2025-11-04 12:45:11.749308+01
cc315dce-2ee8-4572-a294-7d63086efbeb	d2c980bc-c787-4166-8e74-d074800bf867	2025-10-12	\N	\N	\N	24.690000	\N	GENERATED	2025-11-04 12:45:11.749959+01
b24d7b07-5c27-4e14-8215-5d5f9b948642	d2c980bc-c787-4166-8e74-d074800bf867	2025-10-13	\N	\N	\N	24.780000	\N	GENERATED	2025-11-04 12:45:11.750596+01
ade27307-e817-4f26-a015-938cfb3c147a	d2c980bc-c787-4166-8e74-d074800bf867	2025-10-14	\N	\N	\N	24.730000	\N	GENERATED	2025-11-04 12:45:11.751232+01
dd1edebe-cf98-4b7d-8f43-e6a775e5d7c6	d2c980bc-c787-4166-8e74-d074800bf867	2025-10-15	\N	\N	\N	24.610000	\N	GENERATED	2025-11-04 12:45:11.75186+01
5225540f-0c0e-4de8-bb3c-77a48719ecd5	d2c980bc-c787-4166-8e74-d074800bf867	2025-10-16	\N	\N	\N	24.780000	\N	GENERATED	2025-11-04 12:45:11.752516+01
adb9d3ee-7c3e-45a5-b094-e3401acf0146	d2c980bc-c787-4166-8e74-d074800bf867	2025-10-17	\N	\N	\N	24.780000	\N	GENERATED	2025-11-04 12:45:11.753153+01
12889b64-fe76-43af-8ed1-21bee29ec4da	d2c980bc-c787-4166-8e74-d074800bf867	2025-10-18	\N	\N	\N	24.800000	\N	GENERATED	2025-11-04 12:45:11.753777+01
688bea1b-213f-4d41-80f4-3187b3494ee0	d2c980bc-c787-4166-8e74-d074800bf867	2025-10-19	\N	\N	\N	24.680000	\N	GENERATED	2025-11-04 12:45:11.754414+01
cf3927aa-29df-4c80-aac2-f415f17777cb	d2c980bc-c787-4166-8e74-d074800bf867	2025-10-20	\N	\N	\N	24.840000	\N	GENERATED	2025-11-04 12:45:11.755111+01
333f167f-a14e-40e8-9962-3c28afe227af	d2c980bc-c787-4166-8e74-d074800bf867	2025-10-21	\N	\N	\N	24.920000	\N	GENERATED	2025-11-04 12:45:11.755733+01
89c978e0-2505-4a3f-95ff-6ff18ea93937	d2c980bc-c787-4166-8e74-d074800bf867	2025-10-22	\N	\N	\N	24.670000	\N	GENERATED	2025-11-04 12:45:11.756395+01
4c2185f5-4a8d-4162-b096-4186f1237b0b	d2c980bc-c787-4166-8e74-d074800bf867	2025-10-23	\N	\N	\N	24.670000	\N	GENERATED	2025-11-04 12:45:11.757427+01
682f0133-454f-4c2e-92b5-367fc9baa00a	d2c980bc-c787-4166-8e74-d074800bf867	2025-10-24	\N	\N	\N	24.810000	\N	GENERATED	2025-11-04 12:45:11.758054+01
605bd175-517f-4f7e-8c1f-d734b8b79386	d2c980bc-c787-4166-8e74-d074800bf867	2025-10-25	\N	\N	\N	24.890000	\N	GENERATED	2025-11-04 12:45:11.758706+01
57936135-c715-4bc6-ae08-ec2060acbc11	d2c980bc-c787-4166-8e74-d074800bf867	2025-10-26	\N	\N	\N	24.980000	\N	GENERATED	2025-11-04 12:45:11.759336+01
377f621e-5b29-4a02-906c-9b4482ef9e5e	d2c980bc-c787-4166-8e74-d074800bf867	2025-10-27	\N	\N	\N	24.850000	\N	GENERATED	2025-11-04 12:45:11.759968+01
5bb946aa-571c-4ad9-b2b6-329b8e1f3a6d	d2c980bc-c787-4166-8e74-d074800bf867	2025-10-28	\N	\N	\N	25.010000	\N	GENERATED	2025-11-04 12:45:11.7606+01
aa19051f-54a3-4705-87be-81ba671e6ce7	d2c980bc-c787-4166-8e74-d074800bf867	2025-10-29	\N	\N	\N	24.810000	\N	GENERATED	2025-11-04 12:45:11.761493+01
41ae86c2-236f-47ba-bbb1-5b8f4cc377af	d2c980bc-c787-4166-8e74-d074800bf867	2025-10-30	\N	\N	\N	24.720000	\N	GENERATED	2025-11-04 12:45:11.762689+01
38d45d43-56f1-4f0e-b78c-b108c2c335ca	d2c980bc-c787-4166-8e74-d074800bf867	2025-10-31	\N	\N	\N	24.840000	\N	GENERATED	2025-11-04 12:45:11.76341+01
1eaffa79-dfd5-402e-93f5-bd302c49defe	d2c980bc-c787-4166-8e74-d074800bf867	2025-11-01	\N	\N	\N	25.010000	\N	GENERATED	2025-11-04 12:45:11.764045+01
cea3943e-c106-46fa-93fa-c0bd7b112fbb	d2c980bc-c787-4166-8e74-d074800bf867	2025-11-02	\N	\N	\N	24.700000	\N	GENERATED	2025-11-04 12:45:11.764682+01
b7881ab1-3152-4a06-9cc0-8985c7d82955	d2c980bc-c787-4166-8e74-d074800bf867	2025-11-03	\N	\N	\N	25.040000	\N	GENERATED	2025-11-04 12:45:11.765306+01
35393412-2759-4d2c-9b4b-e45ca543b2d0	92125d99-571e-42c7-8369-4ce85c866078	2024-11-04	\N	\N	\N	110.550000	\N	GENERATED	2025-11-04 12:45:11.766503+01
c0fe6fb8-5adb-4080-add4-88fdb73eee34	92125d99-571e-42c7-8369-4ce85c866078	2024-11-05	\N	\N	\N	109.040000	\N	GENERATED	2025-11-04 12:45:11.767139+01
58b0b607-55a2-4ef5-a2bf-bf2f9a3d903a	92125d99-571e-42c7-8369-4ce85c866078	2024-11-06	\N	\N	\N	110.460000	\N	GENERATED	2025-11-04 12:45:11.767779+01
240de9bb-4927-4550-bc3a-2292e49309d7	92125d99-571e-42c7-8369-4ce85c866078	2024-11-07	\N	\N	\N	111.080000	\N	GENERATED	2025-11-04 12:45:11.768402+01
5f349f87-908d-4e55-a22f-1b4b23daf0e4	92125d99-571e-42c7-8369-4ce85c866078	2024-11-08	\N	\N	\N	110.650000	\N	GENERATED	2025-11-04 12:45:11.76903+01
6666e54a-5cbd-4e49-9aa8-272319132903	92125d99-571e-42c7-8369-4ce85c866078	2024-11-09	\N	\N	\N	109.610000	\N	GENERATED	2025-11-04 12:45:11.76967+01
70c1ca01-a521-41c3-8bae-a023e28d35b8	92125d99-571e-42c7-8369-4ce85c866078	2024-11-10	\N	\N	\N	109.760000	\N	GENERATED	2025-11-04 12:45:11.770679+01
de36fbe0-32e3-4933-b45c-8f0c79289660	92125d99-571e-42c7-8369-4ce85c866078	2024-11-11	\N	\N	\N	109.340000	\N	GENERATED	2025-11-04 12:45:11.771305+01
b16dbafb-837a-47b3-98fd-95acd257cca0	92125d99-571e-42c7-8369-4ce85c866078	2024-11-12	\N	\N	\N	109.900000	\N	GENERATED	2025-11-04 12:45:11.771966+01
06b56c34-b034-4060-9367-2667875ab59c	92125d99-571e-42c7-8369-4ce85c866078	2024-11-13	\N	\N	\N	109.260000	\N	GENERATED	2025-11-04 12:45:11.772646+01
ca785bb6-e5fe-45f9-b931-b658a591aea5	92125d99-571e-42c7-8369-4ce85c866078	2024-11-14	\N	\N	\N	109.500000	\N	GENERATED	2025-11-04 12:45:11.773315+01
9ca50928-6439-4143-ab85-ba9082b84dd9	92125d99-571e-42c7-8369-4ce85c866078	2024-11-15	\N	\N	\N	110.620000	\N	GENERATED	2025-11-04 12:45:11.773951+01
0bd6c172-b79f-41ac-9232-0a7a8e9890db	92125d99-571e-42c7-8369-4ce85c866078	2024-11-16	\N	\N	\N	110.960000	\N	GENERATED	2025-11-04 12:45:11.774576+01
ae589d24-9119-413c-a987-f84d59ab021f	92125d99-571e-42c7-8369-4ce85c866078	2024-11-17	\N	\N	\N	109.800000	\N	GENERATED	2025-11-04 12:45:11.775323+01
cd82da84-b567-49c0-86b0-f153a2d86c5a	92125d99-571e-42c7-8369-4ce85c866078	2024-11-18	\N	\N	\N	109.550000	\N	GENERATED	2025-11-04 12:45:11.775974+01
49772bb7-bc9e-4900-97d5-85afeccd5241	92125d99-571e-42c7-8369-4ce85c866078	2024-11-19	\N	\N	\N	109.720000	\N	GENERATED	2025-11-04 12:45:11.776623+01
4a8d4bee-18cb-47d0-a643-cab0ddc31a51	92125d99-571e-42c7-8369-4ce85c866078	2024-11-20	\N	\N	\N	109.320000	\N	GENERATED	2025-11-04 12:45:11.777391+01
7ec17cde-3e56-45da-9d0f-ebd92bec17e8	92125d99-571e-42c7-8369-4ce85c866078	2024-11-21	\N	\N	\N	111.050000	\N	GENERATED	2025-11-04 12:45:11.778045+01
4a7408ed-18e4-4e59-adaf-db6fc4027be5	92125d99-571e-42c7-8369-4ce85c866078	2024-11-22	\N	\N	\N	109.590000	\N	GENERATED	2025-11-04 12:45:11.778692+01
577b1987-1c6f-4572-8129-ba8da68d7880	92125d99-571e-42c7-8369-4ce85c866078	2024-11-23	\N	\N	\N	110.430000	\N	GENERATED	2025-11-04 12:45:11.779316+01
f0cf1763-f926-4d4b-91d1-99698ef045e5	92125d99-571e-42c7-8369-4ce85c866078	2024-11-24	\N	\N	\N	109.750000	\N	GENERATED	2025-11-04 12:45:11.779981+01
1d8e3f22-5c0b-4932-a13f-2d60f8c6dba6	92125d99-571e-42c7-8369-4ce85c866078	2024-11-25	\N	\N	\N	110.250000	\N	GENERATED	2025-11-04 12:45:11.780605+01
50d26a3b-e25a-4d86-8e0c-a5c4f0800d80	92125d99-571e-42c7-8369-4ce85c866078	2024-11-26	\N	\N	\N	111.430000	\N	GENERATED	2025-11-04 12:45:11.781228+01
132d8387-6354-42ac-9247-5aef9c699d5b	92125d99-571e-42c7-8369-4ce85c866078	2024-11-27	\N	\N	\N	110.120000	\N	GENERATED	2025-11-04 12:45:11.781865+01
532cb0a6-1098-412a-96f8-e1a77fd06267	92125d99-571e-42c7-8369-4ce85c866078	2024-11-28	\N	\N	\N	110.410000	\N	GENERATED	2025-11-04 12:45:11.782523+01
cf5cce81-f401-41aa-981f-ec63bffeff34	92125d99-571e-42c7-8369-4ce85c866078	2024-11-29	\N	\N	\N	110.450000	\N	GENERATED	2025-11-04 12:45:11.783612+01
710487f9-4bb9-4643-98c8-e99da966d064	92125d99-571e-42c7-8369-4ce85c866078	2024-11-30	\N	\N	\N	109.750000	\N	GENERATED	2025-11-04 12:45:11.78442+01
0891b018-37c7-4537-ac48-ad608ba7d465	92125d99-571e-42c7-8369-4ce85c866078	2024-12-01	\N	\N	\N	111.160000	\N	GENERATED	2025-11-04 12:45:11.785201+01
2dfa1314-de5d-4583-94cf-647a0c50a9ca	92125d99-571e-42c7-8369-4ce85c866078	2024-12-02	\N	\N	\N	109.710000	\N	GENERATED	2025-11-04 12:45:11.785889+01
ea0da1c7-b0ce-4997-b1c4-7744a70ee3db	92125d99-571e-42c7-8369-4ce85c866078	2024-12-03	\N	\N	\N	110.640000	\N	GENERATED	2025-11-04 12:45:11.786551+01
cd9d802c-d3a1-4f0c-98e0-b5b28fce89d1	92125d99-571e-42c7-8369-4ce85c866078	2024-12-04	\N	\N	\N	111.760000	\N	GENERATED	2025-11-04 12:45:11.7872+01
122f9d31-ab35-4758-b302-5a54215a9d7c	92125d99-571e-42c7-8369-4ce85c866078	2024-12-05	\N	\N	\N	110.130000	\N	GENERATED	2025-11-04 12:45:11.787843+01
08d9d96d-b93a-4c11-b313-fceec55f614a	92125d99-571e-42c7-8369-4ce85c866078	2024-12-06	\N	\N	\N	110.340000	\N	GENERATED	2025-11-04 12:45:11.788487+01
4836e091-a56d-4de0-a6d6-e2faafb892a0	92125d99-571e-42c7-8369-4ce85c866078	2024-12-07	\N	\N	\N	110.550000	\N	GENERATED	2025-11-04 12:45:11.789121+01
bb79d43a-8256-4c8d-b45b-8e9f3a607299	92125d99-571e-42c7-8369-4ce85c866078	2024-12-08	\N	\N	\N	111.050000	\N	GENERATED	2025-11-04 12:45:11.789755+01
c3c48b17-0e9b-41bb-ba67-edc1d165df00	92125d99-571e-42c7-8369-4ce85c866078	2024-12-09	\N	\N	\N	110.410000	\N	GENERATED	2025-11-04 12:45:11.790392+01
21294544-cacc-4914-a544-6a81280c4d65	92125d99-571e-42c7-8369-4ce85c866078	2024-12-10	\N	\N	\N	111.880000	\N	GENERATED	2025-11-04 12:45:11.791023+01
0a684ac6-555d-4be5-ab7c-2d59f515db4c	92125d99-571e-42c7-8369-4ce85c866078	2024-12-11	\N	\N	\N	110.950000	\N	GENERATED	2025-11-04 12:45:11.791673+01
df8777e7-7764-4574-adf2-44d92e9922e1	92125d99-571e-42c7-8369-4ce85c866078	2024-12-12	\N	\N	\N	110.130000	\N	GENERATED	2025-11-04 12:45:11.792361+01
9515f17f-11a0-4d83-a4ac-adbd4431f2f2	92125d99-571e-42c7-8369-4ce85c866078	2024-12-13	\N	\N	\N	112.000000	\N	GENERATED	2025-11-04 12:45:11.793175+01
2511445c-1d1a-4ae2-9ed3-33f87ead06b1	92125d99-571e-42c7-8369-4ce85c866078	2024-12-14	\N	\N	\N	111.990000	\N	GENERATED	2025-11-04 12:45:11.793854+01
487166da-9bea-4694-a4a4-4d24fe4a424d	92125d99-571e-42c7-8369-4ce85c866078	2024-12-15	\N	\N	\N	110.830000	\N	GENERATED	2025-11-04 12:45:11.794517+01
8ba3158f-423b-43ba-b338-fe863bb9b37c	92125d99-571e-42c7-8369-4ce85c866078	2024-12-16	\N	\N	\N	109.980000	\N	GENERATED	2025-11-04 12:45:11.795226+01
37ce024a-b6c4-45f0-9f70-8a7d63313805	92125d99-571e-42c7-8369-4ce85c866078	2024-12-17	\N	\N	\N	110.820000	\N	GENERATED	2025-11-04 12:45:11.795876+01
70ae8eb1-8364-472c-8668-1e06e7c1be02	92125d99-571e-42c7-8369-4ce85c866078	2024-12-18	\N	\N	\N	110.090000	\N	GENERATED	2025-11-04 12:45:11.796515+01
eb100189-4ad2-48fd-aae5-f06947574c34	92125d99-571e-42c7-8369-4ce85c866078	2024-12-19	\N	\N	\N	111.150000	\N	GENERATED	2025-11-04 12:45:11.797219+01
d1ac8710-683d-49b5-aec2-928a9cad32d3	92125d99-571e-42c7-8369-4ce85c866078	2024-12-20	\N	\N	\N	110.810000	\N	GENERATED	2025-11-04 12:45:11.797869+01
2f854dc6-2868-4dc9-9386-b6e028cab73f	92125d99-571e-42c7-8369-4ce85c866078	2024-12-21	\N	\N	\N	110.880000	\N	GENERATED	2025-11-04 12:45:11.798505+01
247252d9-a145-4ea7-bdb4-01f354911d7a	92125d99-571e-42c7-8369-4ce85c866078	2024-12-22	\N	\N	\N	111.370000	\N	GENERATED	2025-11-04 12:45:11.799162+01
187e0479-e9fd-40e7-811a-419b30ebeded	92125d99-571e-42c7-8369-4ce85c866078	2024-12-23	\N	\N	\N	110.700000	\N	GENERATED	2025-11-04 12:45:11.799799+01
23e89e28-10e7-4aa8-a8f5-4f6973628644	92125d99-571e-42c7-8369-4ce85c866078	2024-12-24	\N	\N	\N	110.190000	\N	GENERATED	2025-11-04 12:45:11.800431+01
c96cf3e9-512f-4a5d-809c-736dbedf27b1	92125d99-571e-42c7-8369-4ce85c866078	2024-12-25	\N	\N	\N	111.010000	\N	GENERATED	2025-11-04 12:45:11.801072+01
b0e666b1-7f61-44f4-8cbd-468ad40b0583	92125d99-571e-42c7-8369-4ce85c866078	2024-12-26	\N	\N	\N	110.660000	\N	GENERATED	2025-11-04 12:45:11.801704+01
59832683-03fd-4643-a8b8-ae1b5de5a130	92125d99-571e-42c7-8369-4ce85c866078	2024-12-27	\N	\N	\N	111.820000	\N	GENERATED	2025-11-04 12:45:11.802372+01
e439dff2-f6e2-4af9-8cac-0a240a729657	92125d99-571e-42c7-8369-4ce85c866078	2024-12-28	\N	\N	\N	111.590000	\N	GENERATED	2025-11-04 12:45:11.803034+01
840f426d-5354-4adf-b076-bc9f7c59e6a4	92125d99-571e-42c7-8369-4ce85c866078	2024-12-29	\N	\N	\N	111.350000	\N	GENERATED	2025-11-04 12:45:11.803661+01
c57f0043-9f48-4010-893c-9a427ae78d04	92125d99-571e-42c7-8369-4ce85c866078	2024-12-30	\N	\N	\N	111.130000	\N	GENERATED	2025-11-04 12:45:11.804301+01
e8cdad50-5798-494c-9d3d-4aa71dce07df	92125d99-571e-42c7-8369-4ce85c866078	2024-12-31	\N	\N	\N	112.340000	\N	GENERATED	2025-11-04 12:45:11.804941+01
6ec42118-3c68-413d-ad1f-3c29246bc9a1	92125d99-571e-42c7-8369-4ce85c866078	2025-01-01	\N	\N	\N	111.270000	\N	GENERATED	2025-11-04 12:45:11.805575+01
5b82169c-aa97-4482-8158-e84bd248f0fc	92125d99-571e-42c7-8369-4ce85c866078	2025-01-02	\N	\N	\N	110.480000	\N	GENERATED	2025-11-04 12:45:11.806211+01
d2050eba-a458-4d87-87db-e83539f3fb92	92125d99-571e-42c7-8369-4ce85c866078	2025-01-03	\N	\N	\N	112.410000	\N	GENERATED	2025-11-04 12:45:11.806876+01
33711c3d-a2ed-4e12-b5bf-26732acf6440	92125d99-571e-42c7-8369-4ce85c866078	2025-01-04	\N	\N	\N	111.170000	\N	GENERATED	2025-11-04 12:45:11.807511+01
e6d29c9a-e301-46b0-87ad-d2a769d7479a	92125d99-571e-42c7-8369-4ce85c866078	2025-01-05	\N	\N	\N	112.000000	\N	GENERATED	2025-11-04 12:45:11.80832+01
e6851358-d0e5-48b2-ac86-18afbcff4c64	92125d99-571e-42c7-8369-4ce85c866078	2025-01-06	\N	\N	\N	110.980000	\N	GENERATED	2025-11-04 12:45:11.808974+01
6e303f63-0fe5-4b6b-b95f-cb4a02afbd97	92125d99-571e-42c7-8369-4ce85c866078	2025-01-07	\N	\N	\N	112.300000	\N	GENERATED	2025-11-04 12:45:11.809645+01
2499b778-20a3-4d97-917b-6bfe0a20de8f	92125d99-571e-42c7-8369-4ce85c866078	2025-01-08	\N	\N	\N	110.730000	\N	GENERATED	2025-11-04 12:45:11.810286+01
9dc79ecc-746d-49f2-8f53-e84b3b42bbf2	92125d99-571e-42c7-8369-4ce85c866078	2025-01-09	\N	\N	\N	111.140000	\N	GENERATED	2025-11-04 12:45:11.810917+01
0ec4c2bf-16bc-4a41-8408-b9fd132074f5	92125d99-571e-42c7-8369-4ce85c866078	2025-01-10	\N	\N	\N	110.800000	\N	GENERATED	2025-11-04 12:45:11.811561+01
9c256fe1-65bf-47e1-b0da-2efdc764e46f	92125d99-571e-42c7-8369-4ce85c866078	2025-01-11	\N	\N	\N	111.320000	\N	GENERATED	2025-11-04 12:45:11.812191+01
0e4ed530-29d5-4712-b8ff-033d1b56ab46	92125d99-571e-42c7-8369-4ce85c866078	2025-01-12	\N	\N	\N	112.120000	\N	GENERATED	2025-11-04 12:45:11.812824+01
a812f78a-8afd-4527-9517-9b3267952aed	92125d99-571e-42c7-8369-4ce85c866078	2025-01-13	\N	\N	\N	111.830000	\N	GENERATED	2025-11-04 12:45:11.81347+01
52927e08-c2b1-4417-b1bb-52861583c613	92125d99-571e-42c7-8369-4ce85c866078	2025-01-14	\N	\N	\N	112.530000	\N	GENERATED	2025-11-04 12:45:11.814104+01
70cf044d-82a0-452b-aa79-ca5465fa4e75	92125d99-571e-42c7-8369-4ce85c866078	2025-01-15	\N	\N	\N	112.760000	\N	GENERATED	2025-11-04 12:45:11.814747+01
3ea29288-6105-421d-95ab-ced959795d3c	92125d99-571e-42c7-8369-4ce85c866078	2025-01-16	\N	\N	\N	112.580000	\N	GENERATED	2025-11-04 12:45:11.81537+01
6281bbdf-500f-4ae9-8c49-287d50da1efc	92125d99-571e-42c7-8369-4ce85c866078	2025-01-17	\N	\N	\N	111.040000	\N	GENERATED	2025-11-04 12:45:11.816002+01
5c5d3ce2-9761-44c1-8be8-c0f3e71e0455	92125d99-571e-42c7-8369-4ce85c866078	2025-01-18	\N	\N	\N	111.340000	\N	GENERATED	2025-11-04 12:45:11.816635+01
bb81a19e-ec7b-4668-8a96-76b0a8df4546	92125d99-571e-42c7-8369-4ce85c866078	2025-01-19	\N	\N	\N	111.670000	\N	GENERATED	2025-11-04 12:45:11.817276+01
e5d81a94-31d0-40db-a97a-d57fa0218949	92125d99-571e-42c7-8369-4ce85c866078	2025-01-20	\N	\N	\N	111.830000	\N	GENERATED	2025-11-04 12:45:11.817925+01
8c3ad722-85a1-4519-897c-145458039794	92125d99-571e-42c7-8369-4ce85c866078	2025-01-21	\N	\N	\N	112.340000	\N	GENERATED	2025-11-04 12:45:11.818552+01
adb70b67-0bf6-43f5-9653-d88f3a365525	92125d99-571e-42c7-8369-4ce85c866078	2025-01-22	\N	\N	\N	112.120000	\N	GENERATED	2025-11-04 12:45:11.819191+01
cc176a71-0867-4935-a756-8a617851608f	92125d99-571e-42c7-8369-4ce85c866078	2025-01-23	\N	\N	\N	111.140000	\N	GENERATED	2025-11-04 12:45:11.819822+01
fd333bfd-155e-4b98-a91d-b9da142559de	92125d99-571e-42c7-8369-4ce85c866078	2025-01-24	\N	\N	\N	110.860000	\N	GENERATED	2025-11-04 12:45:11.820463+01
0f49fbc8-cf7d-4b02-a465-d373ca175622	92125d99-571e-42c7-8369-4ce85c866078	2025-01-25	\N	\N	\N	111.060000	\N	GENERATED	2025-11-04 12:45:11.82109+01
a52211a3-e9b0-419b-8eb6-777a11b61479	92125d99-571e-42c7-8369-4ce85c866078	2025-01-26	\N	\N	\N	111.580000	\N	GENERATED	2025-11-04 12:45:11.821724+01
10e3cff7-abad-46c2-b520-7b8e26be07af	92125d99-571e-42c7-8369-4ce85c866078	2025-01-27	\N	\N	\N	111.590000	\N	GENERATED	2025-11-04 12:45:11.822368+01
398bd546-6038-4c2c-a0a3-5703a873e217	92125d99-571e-42c7-8369-4ce85c866078	2025-01-28	\N	\N	\N	112.770000	\N	GENERATED	2025-11-04 12:45:11.823005+01
03caceee-16f9-46d9-ac2d-30a775883784	92125d99-571e-42c7-8369-4ce85c866078	2025-01-29	\N	\N	\N	111.000000	\N	GENERATED	2025-11-04 12:45:11.823638+01
d27b4502-77d8-449b-b81b-fd35873d1b0d	92125d99-571e-42c7-8369-4ce85c866078	2025-01-30	\N	\N	\N	111.000000	\N	GENERATED	2025-11-04 12:45:11.824478+01
ce41d111-7967-43ee-93fd-45858f12f2f1	92125d99-571e-42c7-8369-4ce85c866078	2025-01-31	\N	\N	\N	112.830000	\N	GENERATED	2025-11-04 12:45:11.825306+01
bbf1e17e-04df-4b9a-8eeb-7041801e6d96	92125d99-571e-42c7-8369-4ce85c866078	2025-02-01	\N	\N	\N	112.540000	\N	GENERATED	2025-11-04 12:45:11.826042+01
2c2fdd48-dc78-42c5-a7cf-19bdcdc769e2	92125d99-571e-42c7-8369-4ce85c866078	2025-02-02	\N	\N	\N	112.110000	\N	GENERATED	2025-11-04 12:45:11.826711+01
d731a81c-99eb-4dab-96b7-f6f5f3ac0a9b	92125d99-571e-42c7-8369-4ce85c866078	2025-02-03	\N	\N	\N	111.200000	\N	GENERATED	2025-11-04 12:45:11.827734+01
012e7113-df61-427c-8826-fd1d12a2cb70	92125d99-571e-42c7-8369-4ce85c866078	2025-02-04	\N	\N	\N	112.220000	\N	GENERATED	2025-11-04 12:45:11.82854+01
7018e59e-8bc0-4d51-80b9-9bec02a1eea0	92125d99-571e-42c7-8369-4ce85c866078	2025-02-05	\N	\N	\N	112.750000	\N	GENERATED	2025-11-04 12:45:11.829176+01
f4d4e91d-0728-494c-8f6d-3eb17e0c118d	92125d99-571e-42c7-8369-4ce85c866078	2025-02-06	\N	\N	\N	111.730000	\N	GENERATED	2025-11-04 12:45:11.82981+01
45e6bda3-9d37-4908-9cdf-5d1cc0217f5e	92125d99-571e-42c7-8369-4ce85c866078	2025-02-07	\N	\N	\N	113.360000	\N	GENERATED	2025-11-04 12:45:11.830437+01
69854df8-9c69-4ad5-a65a-8fd361b9e88d	92125d99-571e-42c7-8369-4ce85c866078	2025-02-08	\N	\N	\N	111.300000	\N	GENERATED	2025-11-04 12:45:11.831075+01
3478bc38-1163-41a3-b855-78ab5de93cbc	92125d99-571e-42c7-8369-4ce85c866078	2025-02-09	\N	\N	\N	113.130000	\N	GENERATED	2025-11-04 12:45:11.831698+01
c9946375-3e11-40c7-b3ca-0ca50ac737f8	92125d99-571e-42c7-8369-4ce85c866078	2025-02-10	\N	\N	\N	111.990000	\N	GENERATED	2025-11-04 12:45:11.832324+01
ed3771ba-d377-4c1d-b78f-b41bfd35492b	92125d99-571e-42c7-8369-4ce85c866078	2025-02-11	\N	\N	\N	112.690000	\N	GENERATED	2025-11-04 12:45:11.832987+01
9ed0f401-d7d3-4b57-8476-5fac98dcbd58	92125d99-571e-42c7-8369-4ce85c866078	2025-02-12	\N	\N	\N	111.510000	\N	GENERATED	2025-11-04 12:45:11.833889+01
8e4970e1-61a5-47bb-a555-b0f959c4bd71	92125d99-571e-42c7-8369-4ce85c866078	2025-02-13	\N	\N	\N	112.440000	\N	GENERATED	2025-11-04 12:45:11.834542+01
7ed8b823-9276-4504-a4d5-7a6d24d0eab2	92125d99-571e-42c7-8369-4ce85c866078	2025-02-14	\N	\N	\N	112.660000	\N	GENERATED	2025-11-04 12:45:11.83529+01
4fd77f2e-520a-4d13-b8d3-99a527e04471	92125d99-571e-42c7-8369-4ce85c866078	2025-02-15	\N	\N	\N	112.610000	\N	GENERATED	2025-11-04 12:45:11.835925+01
1cd7f620-b863-44df-9b9c-3115b3e4900c	92125d99-571e-42c7-8369-4ce85c866078	2025-02-16	\N	\N	\N	112.210000	\N	GENERATED	2025-11-04 12:45:11.836548+01
c199338f-3da0-4a1d-a6ca-37bc69342cfd	92125d99-571e-42c7-8369-4ce85c866078	2025-02-17	\N	\N	\N	113.030000	\N	GENERATED	2025-11-04 12:45:11.837184+01
fa626d56-c3e5-4327-9737-19fd192a3660	92125d99-571e-42c7-8369-4ce85c866078	2025-02-18	\N	\N	\N	112.040000	\N	GENERATED	2025-11-04 12:45:11.837814+01
21b2d37e-fa69-4457-a954-d2eeaccf3ca7	92125d99-571e-42c7-8369-4ce85c866078	2025-02-19	\N	\N	\N	112.660000	\N	GENERATED	2025-11-04 12:45:11.83845+01
3dd554cc-25d7-4c00-a2fc-7ee141cb0f75	92125d99-571e-42c7-8369-4ce85c866078	2025-02-20	\N	\N	\N	112.860000	\N	GENERATED	2025-11-04 12:45:11.839254+01
cc2dc37e-4992-49f1-b478-2d70e33740e4	92125d99-571e-42c7-8369-4ce85c866078	2025-02-21	\N	\N	\N	113.230000	\N	GENERATED	2025-11-04 12:45:11.840154+01
56d7da07-ad8c-497d-a3a1-c540e34b4d0d	92125d99-571e-42c7-8369-4ce85c866078	2025-02-22	\N	\N	\N	112.350000	\N	GENERATED	2025-11-04 12:45:11.840962+01
89a4ae3c-b80e-4790-b017-192003b7def9	92125d99-571e-42c7-8369-4ce85c866078	2025-02-23	\N	\N	\N	112.760000	\N	GENERATED	2025-11-04 12:45:11.841608+01
7888cc44-9b19-4351-89eb-ae6925e3306d	92125d99-571e-42c7-8369-4ce85c866078	2025-02-24	\N	\N	\N	111.720000	\N	GENERATED	2025-11-04 12:45:11.842245+01
5669447d-fc2a-4dfe-bcd2-a3dcdb187798	92125d99-571e-42c7-8369-4ce85c866078	2025-02-25	\N	\N	\N	113.030000	\N	GENERATED	2025-11-04 12:45:11.842975+01
cbebb1aa-ab46-4695-9aef-7b6ee939dbba	92125d99-571e-42c7-8369-4ce85c866078	2025-02-26	\N	\N	\N	111.950000	\N	GENERATED	2025-11-04 12:45:11.843623+01
da9178c0-b1f0-4440-ba5d-54fa754c2d1d	92125d99-571e-42c7-8369-4ce85c866078	2025-02-27	\N	\N	\N	112.430000	\N	GENERATED	2025-11-04 12:45:11.844248+01
326a5ebd-631e-43ad-a2aa-0e7f40d593c0	92125d99-571e-42c7-8369-4ce85c866078	2025-02-28	\N	\N	\N	111.820000	\N	GENERATED	2025-11-04 12:45:11.844887+01
3455003a-e5eb-4487-a9eb-37220b1e04c5	92125d99-571e-42c7-8369-4ce85c866078	2025-03-01	\N	\N	\N	112.750000	\N	GENERATED	2025-11-04 12:45:11.845518+01
ec2171ec-c301-48ac-af3e-03548cbe3ace	92125d99-571e-42c7-8369-4ce85c866078	2025-03-02	\N	\N	\N	113.150000	\N	GENERATED	2025-11-04 12:45:11.846144+01
61a29d64-29db-48db-a633-555d090845bf	92125d99-571e-42c7-8369-4ce85c866078	2025-03-03	\N	\N	\N	112.350000	\N	GENERATED	2025-11-04 12:45:11.846784+01
66749a05-782c-4f07-b819-e0aec6ba97b0	92125d99-571e-42c7-8369-4ce85c866078	2025-03-04	\N	\N	\N	112.660000	\N	GENERATED	2025-11-04 12:45:11.84741+01
1ecbc0fe-b3fc-45df-b3a5-248a8019829a	92125d99-571e-42c7-8369-4ce85c866078	2025-03-05	\N	\N	\N	112.390000	\N	GENERATED	2025-11-04 12:45:11.848034+01
ff1eef48-91dc-4d66-92f3-847085527d5b	92125d99-571e-42c7-8369-4ce85c866078	2025-03-06	\N	\N	\N	113.020000	\N	GENERATED	2025-11-04 12:45:11.848676+01
5dac53e3-0ec8-436a-b19f-2052524262cc	92125d99-571e-42c7-8369-4ce85c866078	2025-03-07	\N	\N	\N	112.640000	\N	GENERATED	2025-11-04 12:45:11.849414+01
be43bb49-4004-4002-98e9-6c17e0a456f3	92125d99-571e-42c7-8369-4ce85c866078	2025-03-08	\N	\N	\N	112.710000	\N	GENERATED	2025-11-04 12:45:11.850057+01
c05d212a-b03a-4118-b562-f4bc962c6548	92125d99-571e-42c7-8369-4ce85c866078	2025-03-09	\N	\N	\N	112.930000	\N	GENERATED	2025-11-04 12:45:11.850707+01
2f319801-c010-479f-9ea9-e775b06bacfa	92125d99-571e-42c7-8369-4ce85c866078	2025-03-10	\N	\N	\N	111.990000	\N	GENERATED	2025-11-04 12:45:11.851335+01
f480633b-74c7-453b-be88-dcb265ed5391	92125d99-571e-42c7-8369-4ce85c866078	2025-03-11	\N	\N	\N	113.980000	\N	GENERATED	2025-11-04 12:45:11.85214+01
db30d93e-4b9a-449b-b5f2-c4ac71eaaa2b	92125d99-571e-42c7-8369-4ce85c866078	2025-03-12	\N	\N	\N	113.270000	\N	GENERATED	2025-11-04 12:45:11.852787+01
0648443a-c086-4bf3-8a31-34e737cec1d9	92125d99-571e-42c7-8369-4ce85c866078	2025-03-13	\N	\N	\N	113.190000	\N	GENERATED	2025-11-04 12:45:11.853423+01
e1eda638-b4fc-4b2c-8043-80eae595ac89	92125d99-571e-42c7-8369-4ce85c866078	2025-03-14	\N	\N	\N	113.460000	\N	GENERATED	2025-11-04 12:45:11.85405+01
3d57285f-ad54-4619-ba4d-017d2a84fb8c	92125d99-571e-42c7-8369-4ce85c866078	2025-03-15	\N	\N	\N	113.960000	\N	GENERATED	2025-11-04 12:45:11.85495+01
ea78d4e5-b07e-4561-b280-e64689ebc740	92125d99-571e-42c7-8369-4ce85c866078	2025-03-16	\N	\N	\N	112.330000	\N	GENERATED	2025-11-04 12:45:11.856011+01
8c0f120a-eca8-4163-a012-9175d1753d61	92125d99-571e-42c7-8369-4ce85c866078	2025-03-17	\N	\N	\N	113.940000	\N	GENERATED	2025-11-04 12:45:11.856728+01
c0f352b6-53e6-41ed-85d0-a74f006b0475	92125d99-571e-42c7-8369-4ce85c866078	2025-03-18	\N	\N	\N	113.320000	\N	GENERATED	2025-11-04 12:45:11.857363+01
573b2d0b-483d-4a9b-b7c0-29474303a5e5	92125d99-571e-42c7-8369-4ce85c866078	2025-03-19	\N	\N	\N	113.390000	\N	GENERATED	2025-11-04 12:45:11.858008+01
078c0846-d8cf-4ae2-9a92-f6246006f039	92125d99-571e-42c7-8369-4ce85c866078	2025-03-20	\N	\N	\N	114.110000	\N	GENERATED	2025-11-04 12:45:11.858649+01
7e24b0e7-775c-4af5-8731-d17720f95eea	92125d99-571e-42c7-8369-4ce85c866078	2025-03-21	\N	\N	\N	113.210000	\N	GENERATED	2025-11-04 12:45:11.859284+01
0468a2d9-d229-4cb4-8505-7f0f29575524	92125d99-571e-42c7-8369-4ce85c866078	2025-03-22	\N	\N	\N	113.440000	\N	GENERATED	2025-11-04 12:45:11.860034+01
521c99c3-bea6-4d42-b58e-f91cf78f27e4	92125d99-571e-42c7-8369-4ce85c866078	2025-03-23	\N	\N	\N	113.480000	\N	GENERATED	2025-11-04 12:45:11.860674+01
91a656bf-7231-41e9-a07a-ab492b76ee84	92125d99-571e-42c7-8369-4ce85c866078	2025-03-24	\N	\N	\N	112.350000	\N	GENERATED	2025-11-04 12:45:11.861314+01
07fdf40b-29d8-4c6d-97ff-c65476629e5f	92125d99-571e-42c7-8369-4ce85c866078	2025-03-25	\N	\N	\N	114.060000	\N	GENERATED	2025-11-04 12:45:11.861959+01
686bc5cc-e754-4fdd-aca7-c2088b5603df	92125d99-571e-42c7-8369-4ce85c866078	2025-03-26	\N	\N	\N	113.050000	\N	GENERATED	2025-11-04 12:45:11.862874+01
90839b6f-4b6c-4e3d-b773-1a0c672a02d1	92125d99-571e-42c7-8369-4ce85c866078	2025-03-27	\N	\N	\N	112.680000	\N	GENERATED	2025-11-04 12:45:11.863517+01
e05da3fb-7e76-4894-8fe3-771dfa563d2c	92125d99-571e-42c7-8369-4ce85c866078	2025-03-28	\N	\N	\N	112.830000	\N	GENERATED	2025-11-04 12:45:11.864152+01
3cdb2f00-e5ff-4afb-8d70-c6eacdbe49e7	92125d99-571e-42c7-8369-4ce85c866078	2025-03-29	\N	\N	\N	113.650000	\N	GENERATED	2025-11-04 12:45:11.864768+01
afdcf5d9-509f-4723-a251-ff360376cd85	92125d99-571e-42c7-8369-4ce85c866078	2025-03-30	\N	\N	\N	113.100000	\N	GENERATED	2025-11-04 12:45:11.865391+01
05215cc9-c3a4-45e9-9a31-7dc2d821c552	92125d99-571e-42c7-8369-4ce85c866078	2025-03-31	\N	\N	\N	114.190000	\N	GENERATED	2025-11-04 12:45:11.866017+01
efa49e38-ab5b-416c-8568-b7d5f7307218	92125d99-571e-42c7-8369-4ce85c866078	2025-04-01	\N	\N	\N	113.560000	\N	GENERATED	2025-11-04 12:45:11.866655+01
90e22dd4-7a58-49c0-b8cc-ec7e3c92dff8	92125d99-571e-42c7-8369-4ce85c866078	2025-04-02	\N	\N	\N	113.280000	\N	GENERATED	2025-11-04 12:45:11.867315+01
dd473678-dfec-4cf9-8f0e-b2a540c3fd3e	92125d99-571e-42c7-8369-4ce85c866078	2025-04-03	\N	\N	\N	112.730000	\N	GENERATED	2025-11-04 12:45:11.867939+01
441380fd-5578-4e67-bea5-f8637c4d5051	92125d99-571e-42c7-8369-4ce85c866078	2025-04-04	\N	\N	\N	113.790000	\N	GENERATED	2025-11-04 12:45:11.868595+01
2bf74fe3-8b21-46eb-a57d-ff86d8a9c397	92125d99-571e-42c7-8369-4ce85c866078	2025-04-05	\N	\N	\N	112.700000	\N	GENERATED	2025-11-04 12:45:11.869235+01
c38fa1ce-f419-4b10-938a-1b89234a829a	92125d99-571e-42c7-8369-4ce85c866078	2025-04-06	\N	\N	\N	114.470000	\N	GENERATED	2025-11-04 12:45:11.869859+01
e6be14c4-022f-4931-9e27-75f08e7e92e5	92125d99-571e-42c7-8369-4ce85c866078	2025-04-07	\N	\N	\N	114.680000	\N	GENERATED	2025-11-04 12:45:11.870631+01
2af451a5-faed-4e80-bdb8-6fd13283db1d	92125d99-571e-42c7-8369-4ce85c866078	2025-04-08	\N	\N	\N	114.000000	\N	GENERATED	2025-11-04 12:45:11.871532+01
aa6deb6d-3120-4c2a-8fe5-79dfa0f3a635	92125d99-571e-42c7-8369-4ce85c866078	2025-04-09	\N	\N	\N	114.300000	\N	GENERATED	2025-11-04 12:45:11.872274+01
78f7013b-5e89-4e28-9505-9cc2b1a2c03e	92125d99-571e-42c7-8369-4ce85c866078	2025-04-10	\N	\N	\N	113.080000	\N	GENERATED	2025-11-04 12:45:11.872939+01
bc95925e-58b6-4827-b33f-f37d8d65d945	92125d99-571e-42c7-8369-4ce85c866078	2025-04-11	\N	\N	\N	113.920000	\N	GENERATED	2025-11-04 12:45:11.873586+01
8f8958a9-a3bb-471e-8b40-7fc624a91055	92125d99-571e-42c7-8369-4ce85c866078	2025-04-12	\N	\N	\N	114.190000	\N	GENERATED	2025-11-04 12:45:11.874237+01
ff017846-ff0d-4645-9593-d45b0aa0447c	92125d99-571e-42c7-8369-4ce85c866078	2025-04-13	\N	\N	\N	113.210000	\N	GENERATED	2025-11-04 12:45:11.874886+01
a91448ab-76a5-4c41-bae3-af00137d4f29	92125d99-571e-42c7-8369-4ce85c866078	2025-04-14	\N	\N	\N	113.940000	\N	GENERATED	2025-11-04 12:45:11.875537+01
891e963a-5a5a-40c5-a3f6-a09c124a5192	92125d99-571e-42c7-8369-4ce85c866078	2025-04-15	\N	\N	\N	112.920000	\N	GENERATED	2025-11-04 12:45:11.876178+01
6ad4cb19-0439-4a16-aa74-0e869f75ddfa	92125d99-571e-42c7-8369-4ce85c866078	2025-04-16	\N	\N	\N	113.080000	\N	GENERATED	2025-11-04 12:45:11.876816+01
a4b9f30f-0bcd-4fe2-84fc-6cf82b51ed67	92125d99-571e-42c7-8369-4ce85c866078	2025-04-17	\N	\N	\N	114.010000	\N	GENERATED	2025-11-04 12:45:11.877453+01
9698779f-c8ee-41f9-a822-be6661882c5e	92125d99-571e-42c7-8369-4ce85c866078	2025-04-18	\N	\N	\N	114.500000	\N	GENERATED	2025-11-04 12:45:11.878092+01
a48d90b5-ff04-4f20-a0b8-0daf6b173a05	92125d99-571e-42c7-8369-4ce85c866078	2025-04-19	\N	\N	\N	113.870000	\N	GENERATED	2025-11-04 12:45:11.87888+01
b2e69149-2628-4c61-8756-eda1847c9cb5	92125d99-571e-42c7-8369-4ce85c866078	2025-04-20	\N	\N	\N	114.420000	\N	GENERATED	2025-11-04 12:45:11.879522+01
fdbb251a-4f09-4345-9c35-10865a075f8a	92125d99-571e-42c7-8369-4ce85c866078	2025-04-21	\N	\N	\N	115.000000	\N	GENERATED	2025-11-04 12:45:11.880143+01
e741eb59-d268-4f0e-be02-cb2b91b6b09c	92125d99-571e-42c7-8369-4ce85c866078	2025-04-22	\N	\N	\N	113.390000	\N	GENERATED	2025-11-04 12:45:11.880768+01
a5ba13ad-1e7b-4418-853e-23ab9f763312	92125d99-571e-42c7-8369-4ce85c866078	2025-04-23	\N	\N	\N	114.560000	\N	GENERATED	2025-11-04 12:45:11.881438+01
c0a1608f-e2c1-494d-a2b2-39998338d2fb	92125d99-571e-42c7-8369-4ce85c866078	2025-04-24	\N	\N	\N	114.270000	\N	GENERATED	2025-11-04 12:45:11.882067+01
34205916-84ab-4b9d-9589-bef075306e4f	92125d99-571e-42c7-8369-4ce85c866078	2025-04-25	\N	\N	\N	114.010000	\N	GENERATED	2025-11-04 12:45:11.882735+01
90b62666-8dab-4233-b991-94592a39c10e	92125d99-571e-42c7-8369-4ce85c866078	2025-04-26	\N	\N	\N	113.430000	\N	GENERATED	2025-11-04 12:45:11.883366+01
2221f37c-866f-4624-a6db-6a764de21c5c	92125d99-571e-42c7-8369-4ce85c866078	2025-04-27	\N	\N	\N	114.820000	\N	GENERATED	2025-11-04 12:45:11.883994+01
cb942ae6-61e8-4a4f-894c-ca6051e30e14	92125d99-571e-42c7-8369-4ce85c866078	2025-04-28	\N	\N	\N	113.880000	\N	GENERATED	2025-11-04 12:45:11.884633+01
f0496670-efef-422b-8f44-363164e7016e	92125d99-571e-42c7-8369-4ce85c866078	2025-04-29	\N	\N	\N	113.980000	\N	GENERATED	2025-11-04 12:45:11.885256+01
f8b2f8d2-7d46-4a84-9ea4-030c04ae987f	92125d99-571e-42c7-8369-4ce85c866078	2025-04-30	\N	\N	\N	114.310000	\N	GENERATED	2025-11-04 12:45:11.885981+01
06ad8006-0b1e-483c-b0e1-91718674e525	92125d99-571e-42c7-8369-4ce85c866078	2025-05-01	\N	\N	\N	114.500000	\N	GENERATED	2025-11-04 12:45:11.886633+01
d34030d8-d1b0-49af-a843-035879ac9165	92125d99-571e-42c7-8369-4ce85c866078	2025-05-02	\N	\N	\N	113.550000	\N	GENERATED	2025-11-04 12:45:11.887296+01
fda2c942-653a-432d-8b3f-94bb7ff66aa8	92125d99-571e-42c7-8369-4ce85c866078	2025-05-03	\N	\N	\N	115.410000	\N	GENERATED	2025-11-04 12:45:11.887943+01
068b84df-5eee-41f0-9524-21930c242006	92125d99-571e-42c7-8369-4ce85c866078	2025-05-04	\N	\N	\N	115.400000	\N	GENERATED	2025-11-04 12:45:11.888584+01
415072ad-870e-4ca1-a087-1ca3777b5fca	92125d99-571e-42c7-8369-4ce85c866078	2025-05-05	\N	\N	\N	114.790000	\N	GENERATED	2025-11-04 12:45:11.889213+01
e4346207-6cb9-4cd0-87f7-a28b9d250f07	92125d99-571e-42c7-8369-4ce85c866078	2025-05-06	\N	\N	\N	114.980000	\N	GENERATED	2025-11-04 12:45:11.889843+01
0769dd23-a6c3-41d9-a723-06c0aa2b3b5f	92125d99-571e-42c7-8369-4ce85c866078	2025-05-07	\N	\N	\N	113.760000	\N	GENERATED	2025-11-04 12:45:11.89048+01
01658e27-745c-4717-8981-bf95f8ff72cf	92125d99-571e-42c7-8369-4ce85c866078	2025-05-08	\N	\N	\N	114.680000	\N	GENERATED	2025-11-04 12:45:11.891109+01
35053c05-ba79-47da-b7c6-4267b92d9242	92125d99-571e-42c7-8369-4ce85c866078	2025-05-09	\N	\N	\N	114.160000	\N	GENERATED	2025-11-04 12:45:11.891744+01
566619ab-c0d9-41ce-a5e4-04a0c067a516	92125d99-571e-42c7-8369-4ce85c866078	2025-05-10	\N	\N	\N	114.540000	\N	GENERATED	2025-11-04 12:45:11.892381+01
924da5b8-96ef-42fc-b8db-dcc6eccfa51b	92125d99-571e-42c7-8369-4ce85c866078	2025-05-11	\N	\N	\N	114.740000	\N	GENERATED	2025-11-04 12:45:11.893011+01
40e3cc1f-d131-4445-8590-6c32c805427c	92125d99-571e-42c7-8369-4ce85c866078	2025-05-12	\N	\N	\N	113.600000	\N	GENERATED	2025-11-04 12:45:11.893691+01
99fd03e1-8d30-4a9d-850e-fd3f3dd3084b	92125d99-571e-42c7-8369-4ce85c866078	2025-05-13	\N	\N	\N	114.930000	\N	GENERATED	2025-11-04 12:45:11.894321+01
e96dc513-85f0-40ed-87d9-30082da8f96f	92125d99-571e-42c7-8369-4ce85c866078	2025-05-14	\N	\N	\N	115.240000	\N	GENERATED	2025-11-04 12:45:11.895051+01
c7cedd09-2c75-4ef6-ba39-a7bee91b8812	92125d99-571e-42c7-8369-4ce85c866078	2025-05-15	\N	\N	\N	115.480000	\N	GENERATED	2025-11-04 12:45:11.895857+01
1d4cd445-e8b3-482e-bae2-be78fd6ec816	92125d99-571e-42c7-8369-4ce85c866078	2025-05-16	\N	\N	\N	115.370000	\N	GENERATED	2025-11-04 12:45:11.896505+01
557419dd-968c-4f27-ac37-27945e0bcf74	92125d99-571e-42c7-8369-4ce85c866078	2025-05-17	\N	\N	\N	114.970000	\N	GENERATED	2025-11-04 12:45:11.897127+01
8d4c9e52-ec89-4578-8e2a-e7adc6d47ad0	92125d99-571e-42c7-8369-4ce85c866078	2025-05-18	\N	\N	\N	113.860000	\N	GENERATED	2025-11-04 12:45:11.897776+01
b8e27c5b-3052-455c-ba46-d25296dfcda7	92125d99-571e-42c7-8369-4ce85c866078	2025-05-19	\N	\N	\N	114.540000	\N	GENERATED	2025-11-04 12:45:11.89841+01
3ce49106-f764-4943-9bcf-b3185ca6380c	92125d99-571e-42c7-8369-4ce85c866078	2025-05-20	\N	\N	\N	115.850000	\N	GENERATED	2025-11-04 12:45:11.899036+01
427d2908-cf10-41b5-ba2f-a9b20ea06209	92125d99-571e-42c7-8369-4ce85c866078	2025-05-21	\N	\N	\N	113.790000	\N	GENERATED	2025-11-04 12:45:11.899673+01
51c3e857-414e-49ee-8a94-294c9ffacd7b	92125d99-571e-42c7-8369-4ce85c866078	2025-05-22	\N	\N	\N	115.230000	\N	GENERATED	2025-11-04 12:45:11.900388+01
0d1ccd95-6b58-44de-b474-ffa32e97f858	92125d99-571e-42c7-8369-4ce85c866078	2025-05-23	\N	\N	\N	114.020000	\N	GENERATED	2025-11-04 12:45:11.901297+01
3cad993c-cb4b-4a5f-95f9-2ec7cba1d7cf	92125d99-571e-42c7-8369-4ce85c866078	2025-05-24	\N	\N	\N	115.710000	\N	GENERATED	2025-11-04 12:45:11.901979+01
cdec333f-8b8c-4bd4-b96f-e321b8f36e35	92125d99-571e-42c7-8369-4ce85c866078	2025-05-25	\N	\N	\N	114.270000	\N	GENERATED	2025-11-04 12:45:11.90262+01
72af6a44-4f26-4afa-90e0-0457f406c6ca	92125d99-571e-42c7-8369-4ce85c866078	2025-05-26	\N	\N	\N	115.090000	\N	GENERATED	2025-11-04 12:45:11.903258+01
528352f8-99fc-4caa-9b12-ab7850f399d9	92125d99-571e-42c7-8369-4ce85c866078	2025-05-27	\N	\N	\N	115.210000	\N	GENERATED	2025-11-04 12:45:11.903899+01
671da993-a4fd-44d0-8195-05ccc7e6765e	92125d99-571e-42c7-8369-4ce85c866078	2025-05-28	\N	\N	\N	114.480000	\N	GENERATED	2025-11-04 12:45:11.904582+01
2c9d6acf-7769-48f3-bf19-e5c6ce722baa	92125d99-571e-42c7-8369-4ce85c866078	2025-05-29	\N	\N	\N	115.480000	\N	GENERATED	2025-11-04 12:45:11.905235+01
80f414a9-9ccd-4db9-a5ef-d9832a0b4329	92125d99-571e-42c7-8369-4ce85c866078	2025-05-30	\N	\N	\N	115.580000	\N	GENERATED	2025-11-04 12:45:11.905898+01
8be0a846-ab2c-4f9b-ab14-56d98bff2176	92125d99-571e-42c7-8369-4ce85c866078	2025-05-31	\N	\N	\N	115.680000	\N	GENERATED	2025-11-04 12:45:11.906522+01
5500a906-6b63-4f44-bbb2-357189501405	92125d99-571e-42c7-8369-4ce85c866078	2025-06-01	\N	\N	\N	114.800000	\N	GENERATED	2025-11-04 12:45:11.907186+01
d31a45ba-bfdb-4bfa-be79-f7e5b863b44e	92125d99-571e-42c7-8369-4ce85c866078	2025-06-02	\N	\N	\N	116.070000	\N	GENERATED	2025-11-04 12:45:11.907833+01
9989b4bb-22b9-4a7e-9392-269dba860807	92125d99-571e-42c7-8369-4ce85c866078	2025-06-03	\N	\N	\N	114.030000	\N	GENERATED	2025-11-04 12:45:11.908462+01
1745a248-0f23-4ad7-abbb-95aaf43bda59	92125d99-571e-42c7-8369-4ce85c866078	2025-06-04	\N	\N	\N	115.530000	\N	GENERATED	2025-11-04 12:45:11.909101+01
1fb0e9f9-c431-43b6-bffb-42772d2dea75	92125d99-571e-42c7-8369-4ce85c866078	2025-06-05	\N	\N	\N	114.100000	\N	GENERATED	2025-11-04 12:45:11.909731+01
18dd10c0-2ba1-4f61-97d2-c36d4cd5fe9b	92125d99-571e-42c7-8369-4ce85c866078	2025-06-06	\N	\N	\N	114.330000	\N	GENERATED	2025-11-04 12:45:11.91035+01
94dd6671-fb81-48fc-a558-16231fec9670	92125d99-571e-42c7-8369-4ce85c866078	2025-06-07	\N	\N	\N	115.630000	\N	GENERATED	2025-11-04 12:45:11.910991+01
08d21232-531a-4d1a-bafb-58fd8960670e	92125d99-571e-42c7-8369-4ce85c866078	2025-06-08	\N	\N	\N	114.480000	\N	GENERATED	2025-11-04 12:45:11.911619+01
5b936b21-b493-4ea1-bdfe-27ae8b20af59	92125d99-571e-42c7-8369-4ce85c866078	2025-06-09	\N	\N	\N	115.280000	\N	GENERATED	2025-11-04 12:45:11.91227+01
1f03d99c-2e7d-4d87-a09e-f380819e143f	92125d99-571e-42c7-8369-4ce85c866078	2025-06-10	\N	\N	\N	114.590000	\N	GENERATED	2025-11-04 12:45:11.912915+01
0393f7c6-c7cf-4bb0-89dd-912ac9039d25	92125d99-571e-42c7-8369-4ce85c866078	2025-06-11	\N	\N	\N	114.680000	\N	GENERATED	2025-11-04 12:45:11.913536+01
970daadd-5123-4762-af76-5b99291cb354	92125d99-571e-42c7-8369-4ce85c866078	2025-06-12	\N	\N	\N	114.900000	\N	GENERATED	2025-11-04 12:45:11.914164+01
bdc0b182-7960-4006-a602-3a6a2ae3e753	92125d99-571e-42c7-8369-4ce85c866078	2025-06-13	\N	\N	\N	115.870000	\N	GENERATED	2025-11-04 12:45:11.914797+01
3f71d839-178f-4257-8e79-29daf3243237	92125d99-571e-42c7-8369-4ce85c866078	2025-06-14	\N	\N	\N	114.830000	\N	GENERATED	2025-11-04 12:45:11.91548+01
520928d4-fa22-40e8-8083-3f24f70a5f29	92125d99-571e-42c7-8369-4ce85c866078	2025-06-15	\N	\N	\N	115.130000	\N	GENERATED	2025-11-04 12:45:11.91632+01
4bcf3766-222d-4bb8-8710-6fcc534b1975	92125d99-571e-42c7-8369-4ce85c866078	2025-06-16	\N	\N	\N	115.100000	\N	GENERATED	2025-11-04 12:45:11.916975+01
a6310989-7aeb-4111-9b14-643caeecbf7b	92125d99-571e-42c7-8369-4ce85c866078	2025-06-17	\N	\N	\N	115.550000	\N	GENERATED	2025-11-04 12:45:11.917732+01
9180e27b-2c1e-4daa-884a-71e6bbdf968f	92125d99-571e-42c7-8369-4ce85c866078	2025-06-18	\N	\N	\N	115.690000	\N	GENERATED	2025-11-04 12:45:11.918386+01
4ff8fb1f-4963-4302-bcda-b24110603c6a	92125d99-571e-42c7-8369-4ce85c866078	2025-06-19	\N	\N	\N	116.290000	\N	GENERATED	2025-11-04 12:45:11.919019+01
4f166af2-9a4b-4b56-81ec-2aba2f85c0e5	92125d99-571e-42c7-8369-4ce85c866078	2025-06-20	\N	\N	\N	114.760000	\N	GENERATED	2025-11-04 12:45:11.919657+01
a5ec2312-b891-4fd7-91f5-1d2d461e7502	92125d99-571e-42c7-8369-4ce85c866078	2025-06-21	\N	\N	\N	115.800000	\N	GENERATED	2025-11-04 12:45:11.920674+01
cf7e0611-d582-4e74-9439-7cb6bb37133d	92125d99-571e-42c7-8369-4ce85c866078	2025-06-22	\N	\N	\N	114.790000	\N	GENERATED	2025-11-04 12:45:11.921302+01
780f5fd9-e43f-4409-ae30-0198b9f183dc	92125d99-571e-42c7-8369-4ce85c866078	2025-06-23	\N	\N	\N	116.220000	\N	GENERATED	2025-11-04 12:45:11.921947+01
5fa19287-6ca4-4420-812f-0d529acd1388	92125d99-571e-42c7-8369-4ce85c866078	2025-06-24	\N	\N	\N	116.490000	\N	GENERATED	2025-11-04 12:45:11.922577+01
6b19809a-eb1b-461f-b01e-5062e54237f9	92125d99-571e-42c7-8369-4ce85c866078	2025-06-25	\N	\N	\N	114.780000	\N	GENERATED	2025-11-04 12:45:11.923307+01
bcbf30df-382e-475f-849f-c1b6257c0cb9	92125d99-571e-42c7-8369-4ce85c866078	2025-06-26	\N	\N	\N	114.680000	\N	GENERATED	2025-11-04 12:45:11.923943+01
fba6b6d2-e550-460d-a9a9-71e8c543d430	92125d99-571e-42c7-8369-4ce85c866078	2025-06-27	\N	\N	\N	115.040000	\N	GENERATED	2025-11-04 12:45:11.924593+01
5e04e540-6ac8-4fc7-ad7f-385a8a2a522d	92125d99-571e-42c7-8369-4ce85c866078	2025-06-28	\N	\N	\N	115.980000	\N	GENERATED	2025-11-04 12:45:11.925234+01
95edb3e9-2582-468f-82a7-694816df23d6	92125d99-571e-42c7-8369-4ce85c866078	2025-06-29	\N	\N	\N	115.420000	\N	GENERATED	2025-11-04 12:45:11.925873+01
dd78b8eb-0414-49fe-93d0-2d4890bc7630	92125d99-571e-42c7-8369-4ce85c866078	2025-06-30	\N	\N	\N	115.220000	\N	GENERATED	2025-11-04 12:45:11.926499+01
27efce43-ff14-43c1-a515-3620df1503ec	92125d99-571e-42c7-8369-4ce85c866078	2025-07-01	\N	\N	\N	115.910000	\N	GENERATED	2025-11-04 12:45:11.927253+01
1ed7ca8e-19b8-4fa3-a507-da0b88a656e0	92125d99-571e-42c7-8369-4ce85c866078	2025-07-02	\N	\N	\N	116.160000	\N	GENERATED	2025-11-04 12:45:11.927897+01
cab4f362-a1c9-43a7-a7f9-e231da6abf97	92125d99-571e-42c7-8369-4ce85c866078	2025-07-03	\N	\N	\N	114.750000	\N	GENERATED	2025-11-04 12:45:11.928522+01
da647bc8-c99b-4d2d-a8c0-ca81ae8d5a4e	92125d99-571e-42c7-8369-4ce85c866078	2025-07-04	\N	\N	\N	115.730000	\N	GENERATED	2025-11-04 12:45:11.929152+01
6519713a-4396-400f-9f28-a4f97ceef71f	92125d99-571e-42c7-8369-4ce85c866078	2025-07-05	\N	\N	\N	115.250000	\N	GENERATED	2025-11-04 12:45:11.929797+01
28ab3b9f-5464-4c9c-a2d9-7706020a9aea	92125d99-571e-42c7-8369-4ce85c866078	2025-07-06	\N	\N	\N	114.910000	\N	GENERATED	2025-11-04 12:45:11.930423+01
e304501b-04eb-4759-b121-c41adb456a3a	92125d99-571e-42c7-8369-4ce85c866078	2025-07-07	\N	\N	\N	115.270000	\N	GENERATED	2025-11-04 12:45:11.931057+01
39649fea-8ce8-462e-84ae-096d85361c6d	92125d99-571e-42c7-8369-4ce85c866078	2025-07-08	\N	\N	\N	115.330000	\N	GENERATED	2025-11-04 12:45:11.931691+01
9d9bd48f-b29f-409e-8c3e-ebe864ee789a	92125d99-571e-42c7-8369-4ce85c866078	2025-07-09	\N	\N	\N	115.550000	\N	GENERATED	2025-11-04 12:45:11.932551+01
1ab92472-ca0b-4b51-8640-a45218ee0cd8	92125d99-571e-42c7-8369-4ce85c866078	2025-07-10	\N	\N	\N	115.290000	\N	GENERATED	2025-11-04 12:45:11.933207+01
4d05bf54-ca34-4bf8-8fe5-ff1314a179de	92125d99-571e-42c7-8369-4ce85c866078	2025-07-11	\N	\N	\N	116.760000	\N	GENERATED	2025-11-04 12:45:11.933858+01
13a1a825-1179-40a1-885f-184e60979097	92125d99-571e-42c7-8369-4ce85c866078	2025-07-12	\N	\N	\N	117.110000	\N	GENERATED	2025-11-04 12:45:11.934493+01
c8ce3e95-a614-47f8-8565-d429f01c0a98	92125d99-571e-42c7-8369-4ce85c866078	2025-07-13	\N	\N	\N	116.030000	\N	GENERATED	2025-11-04 12:45:11.935184+01
0c9e28da-1573-4293-a5a3-fc32619f94a3	92125d99-571e-42c7-8369-4ce85c866078	2025-07-14	\N	\N	\N	116.770000	\N	GENERATED	2025-11-04 12:45:11.935808+01
e417a194-4efd-46b8-bb22-068eeb7c3978	92125d99-571e-42c7-8369-4ce85c866078	2025-07-15	\N	\N	\N	115.660000	\N	GENERATED	2025-11-04 12:45:11.936452+01
d1ced7ba-8ccf-4723-9a17-28a135ee65d4	92125d99-571e-42c7-8369-4ce85c866078	2025-07-16	\N	\N	\N	116.750000	\N	GENERATED	2025-11-04 12:45:11.937078+01
14072eea-ebc3-40fd-91ea-c86961fcf84e	92125d99-571e-42c7-8369-4ce85c866078	2025-07-17	\N	\N	\N	116.500000	\N	GENERATED	2025-11-04 12:45:11.937725+01
cc940a01-45db-4b2e-b627-4b275cd30b90	92125d99-571e-42c7-8369-4ce85c866078	2025-07-18	\N	\N	\N	116.030000	\N	GENERATED	2025-11-04 12:45:11.938448+01
5a3a7885-6745-47a0-adaa-076341b57dbf	92125d99-571e-42c7-8369-4ce85c866078	2025-07-19	\N	\N	\N	117.230000	\N	GENERATED	2025-11-04 12:45:11.939083+01
d8999766-4992-4201-9afe-3483c4f7c9b8	92125d99-571e-42c7-8369-4ce85c866078	2025-07-20	\N	\N	\N	117.230000	\N	GENERATED	2025-11-04 12:45:11.939727+01
2054d967-d207-487b-93e2-becef37943b4	92125d99-571e-42c7-8369-4ce85c866078	2025-07-21	\N	\N	\N	116.300000	\N	GENERATED	2025-11-04 12:45:11.940361+01
70d75112-4aca-4fdf-ab2c-93bd415fa4fa	92125d99-571e-42c7-8369-4ce85c866078	2025-07-22	\N	\N	\N	116.580000	\N	GENERATED	2025-11-04 12:45:11.940996+01
c967e411-e410-43ed-a732-9733b23d9eca	92125d99-571e-42c7-8369-4ce85c866078	2025-07-23	\N	\N	\N	115.920000	\N	GENERATED	2025-11-04 12:45:11.941624+01
771545ec-4021-45e1-aab3-4b0f5bd7a34f	92125d99-571e-42c7-8369-4ce85c866078	2025-07-24	\N	\N	\N	116.680000	\N	GENERATED	2025-11-04 12:45:11.942303+01
a88464f2-0bcc-43dc-8b92-5fe9fd3ff621	92125d99-571e-42c7-8369-4ce85c866078	2025-07-25	\N	\N	\N	117.150000	\N	GENERATED	2025-11-04 12:45:11.942946+01
c96c600a-a66d-473a-80de-ef12e93cbc94	92125d99-571e-42c7-8369-4ce85c866078	2025-07-26	\N	\N	\N	117.420000	\N	GENERATED	2025-11-04 12:45:11.943599+01
05edb577-cf93-4264-985c-049f2d0392b5	92125d99-571e-42c7-8369-4ce85c866078	2025-07-27	\N	\N	\N	116.620000	\N	GENERATED	2025-11-04 12:45:11.944254+01
9dfb2993-90a3-46fc-8ffa-a6c87e73d628	92125d99-571e-42c7-8369-4ce85c866078	2025-07-28	\N	\N	\N	115.490000	\N	GENERATED	2025-11-04 12:45:11.944895+01
6ebe7223-1206-4bd2-b90b-d1c97b1ec403	92125d99-571e-42c7-8369-4ce85c866078	2025-07-29	\N	\N	\N	116.890000	\N	GENERATED	2025-11-04 12:45:11.945525+01
08abe643-218f-4176-8534-68b9c5e9fc78	92125d99-571e-42c7-8369-4ce85c866078	2025-07-30	\N	\N	\N	116.220000	\N	GENERATED	2025-11-04 12:45:11.946153+01
878837a6-36e9-4b0e-98bf-351ed3f2fe59	92125d99-571e-42c7-8369-4ce85c866078	2025-07-31	\N	\N	\N	117.030000	\N	GENERATED	2025-11-04 12:45:11.946781+01
60edb84f-b6d7-4cd4-9100-f1e066f5e5de	92125d99-571e-42c7-8369-4ce85c866078	2025-08-01	\N	\N	\N	115.480000	\N	GENERATED	2025-11-04 12:45:11.947668+01
f3d6736e-8cb9-4ef0-bcb0-9c3529ce037a	92125d99-571e-42c7-8369-4ce85c866078	2025-08-02	\N	\N	\N	116.310000	\N	GENERATED	2025-11-04 12:45:11.948335+01
b716bcb1-920a-4ce6-acd2-b486f752c00e	92125d99-571e-42c7-8369-4ce85c866078	2025-08-03	\N	\N	\N	116.710000	\N	GENERATED	2025-11-04 12:45:11.949023+01
25cecd2a-db50-4b50-960c-8293f251b9df	92125d99-571e-42c7-8369-4ce85c866078	2025-08-04	\N	\N	\N	116.090000	\N	GENERATED	2025-11-04 12:45:11.949672+01
fe54f66b-dd79-4ad7-bac6-6e11a25f8fbd	92125d99-571e-42c7-8369-4ce85c866078	2025-08-05	\N	\N	\N	116.940000	\N	GENERATED	2025-11-04 12:45:11.950313+01
bbe79a75-3a33-41f7-98da-4c5b312d23db	92125d99-571e-42c7-8369-4ce85c866078	2025-08-06	\N	\N	\N	115.610000	\N	GENERATED	2025-11-04 12:45:11.950949+01
27b53d80-7e1d-40d3-a8c0-6ffe22831ae9	92125d99-571e-42c7-8369-4ce85c866078	2025-08-07	\N	\N	\N	115.640000	\N	GENERATED	2025-11-04 12:45:11.951571+01
20231c57-bb70-4954-83b7-d6b382f4ca19	92125d99-571e-42c7-8369-4ce85c866078	2025-08-08	\N	\N	\N	117.530000	\N	GENERATED	2025-11-04 12:45:11.952228+01
ad331c5b-91a7-4c8e-b06e-ab5b1e2bab7f	92125d99-571e-42c7-8369-4ce85c866078	2025-08-09	\N	\N	\N	117.120000	\N	GENERATED	2025-11-04 12:45:11.952851+01
848ab15e-c10f-4f89-8fc7-12ebb94350cf	92125d99-571e-42c7-8369-4ce85c866078	2025-08-10	\N	\N	\N	117.130000	\N	GENERATED	2025-11-04 12:45:11.953494+01
04775689-d61b-437d-b114-9dc9ba26816a	92125d99-571e-42c7-8369-4ce85c866078	2025-08-11	\N	\N	\N	117.470000	\N	GENERATED	2025-11-04 12:45:11.954134+01
43f1f9af-2473-4a80-9dd7-01dc27b72b70	92125d99-571e-42c7-8369-4ce85c866078	2025-08-12	\N	\N	\N	117.330000	\N	GENERATED	2025-11-04 12:45:11.954759+01
db21c212-9a8d-464c-98bf-00bb5ca87385	92125d99-571e-42c7-8369-4ce85c866078	2025-08-13	\N	\N	\N	117.660000	\N	GENERATED	2025-11-04 12:45:11.955456+01
7491459f-11e6-466f-a61e-80dbd4a5e9b5	92125d99-571e-42c7-8369-4ce85c866078	2025-08-14	\N	\N	\N	117.220000	\N	GENERATED	2025-11-04 12:45:11.956086+01
e6d538b2-9b2d-46c7-ad67-63176a5465db	92125d99-571e-42c7-8369-4ce85c866078	2025-08-15	\N	\N	\N	117.400000	\N	GENERATED	2025-11-04 12:45:11.956729+01
ccbf6cb9-23c7-461a-afe3-1dac50bd0e0b	92125d99-571e-42c7-8369-4ce85c866078	2025-08-16	\N	\N	\N	116.120000	\N	GENERATED	2025-11-04 12:45:11.95737+01
e422dad3-8488-4741-baaa-ca5ce0044584	92125d99-571e-42c7-8369-4ce85c866078	2025-08-17	\N	\N	\N	117.290000	\N	GENERATED	2025-11-04 12:45:11.958029+01
2b924e99-e5d9-4cfd-9fa3-66d5c3587c47	92125d99-571e-42c7-8369-4ce85c866078	2025-08-18	\N	\N	\N	117.100000	\N	GENERATED	2025-11-04 12:45:11.958657+01
046ebd82-172d-40aa-a994-b3974c2cc8eb	92125d99-571e-42c7-8369-4ce85c866078	2025-08-19	\N	\N	\N	116.450000	\N	GENERATED	2025-11-04 12:45:11.959293+01
e68428d1-ce1a-4043-a618-c82f2aa53c1d	92125d99-571e-42c7-8369-4ce85c866078	2025-08-20	\N	\N	\N	116.450000	\N	GENERATED	2025-11-04 12:45:11.959931+01
7f7fa0fa-25f5-4fb6-8708-ccfdd4caf90b	92125d99-571e-42c7-8369-4ce85c866078	2025-08-21	\N	\N	\N	116.900000	\N	GENERATED	2025-11-04 12:45:11.960565+01
7ae0d932-f1e9-4289-b3ef-ce3dbdbf5a9b	92125d99-571e-42c7-8369-4ce85c866078	2025-08-22	\N	\N	\N	117.510000	\N	GENERATED	2025-11-04 12:45:11.961194+01
4e69c934-2f52-44c6-b153-a076933aaadb	92125d99-571e-42c7-8369-4ce85c866078	2025-08-23	\N	\N	\N	116.900000	\N	GENERATED	2025-11-04 12:45:11.961823+01
c17ec407-a6ae-4b6f-8811-e3096a20b6ed	92125d99-571e-42c7-8369-4ce85c866078	2025-08-24	\N	\N	\N	117.520000	\N	GENERATED	2025-11-04 12:45:11.962662+01
9886f61f-3725-4dd7-8754-51ea480ff11a	92125d99-571e-42c7-8369-4ce85c866078	2025-08-25	\N	\N	\N	116.400000	\N	GENERATED	2025-11-04 12:45:11.96333+01
8f80318c-ceaa-44b6-8a7c-971569182a3e	92125d99-571e-42c7-8369-4ce85c866078	2025-08-26	\N	\N	\N	116.720000	\N	GENERATED	2025-11-04 12:45:11.963976+01
a2c7f03e-fd5b-4d70-a096-851036f609b8	92125d99-571e-42c7-8369-4ce85c866078	2025-08-27	\N	\N	\N	117.630000	\N	GENERATED	2025-11-04 12:45:11.964622+01
1ddcbfab-b34f-4956-beae-40f56f16bc34	92125d99-571e-42c7-8369-4ce85c866078	2025-08-28	\N	\N	\N	118.190000	\N	GENERATED	2025-11-04 12:45:11.965246+01
6478dc2a-5908-44f5-af3b-602c2c30e193	92125d99-571e-42c7-8369-4ce85c866078	2025-08-29	\N	\N	\N	118.190000	\N	GENERATED	2025-11-04 12:45:11.965878+01
7790a653-b41e-4a3c-bfdd-69bba519edfa	92125d99-571e-42c7-8369-4ce85c866078	2025-08-30	\N	\N	\N	117.060000	\N	GENERATED	2025-11-04 12:45:11.966517+01
a189dd0e-05b5-4a92-b39f-f60aaac66dfa	92125d99-571e-42c7-8369-4ce85c866078	2025-08-31	\N	\N	\N	116.570000	\N	GENERATED	2025-11-04 12:45:11.967157+01
aad954d8-890d-4388-bb76-ca8bd9e9ebe6	92125d99-571e-42c7-8369-4ce85c866078	2025-09-01	\N	\N	\N	117.480000	\N	GENERATED	2025-11-04 12:45:11.967802+01
841b228f-82cb-4d7e-a0f9-1be8113213e1	92125d99-571e-42c7-8369-4ce85c866078	2025-09-02	\N	\N	\N	116.900000	\N	GENERATED	2025-11-04 12:45:11.968429+01
39b0433a-1f5b-432f-96b1-1a9ee4ec6493	92125d99-571e-42c7-8369-4ce85c866078	2025-09-03	\N	\N	\N	118.190000	\N	GENERATED	2025-11-04 12:45:11.969067+01
cabfcf79-464b-4a14-b83d-81fbbde9025d	92125d99-571e-42c7-8369-4ce85c866078	2025-09-04	\N	\N	\N	117.570000	\N	GENERATED	2025-11-04 12:45:11.969698+01
fa09db44-8b48-4484-9d16-28a62083853f	92125d99-571e-42c7-8369-4ce85c866078	2025-09-05	\N	\N	\N	116.560000	\N	GENERATED	2025-11-04 12:45:11.970322+01
2939ad20-d49b-408f-8450-9486fb3436d3	92125d99-571e-42c7-8369-4ce85c866078	2025-09-06	\N	\N	\N	116.660000	\N	GENERATED	2025-11-04 12:45:11.97096+01
2d2c7ac8-84cd-489d-ba70-f46d4680429f	92125d99-571e-42c7-8369-4ce85c866078	2025-09-07	\N	\N	\N	118.330000	\N	GENERATED	2025-11-04 12:45:11.971591+01
9d4f0fbf-ac72-4df8-a5a9-f271fedd821d	92125d99-571e-42c7-8369-4ce85c866078	2025-09-08	\N	\N	\N	116.560000	\N	GENERATED	2025-11-04 12:45:11.972222+01
226b58aa-0252-4a9d-b142-75d7541027b5	92125d99-571e-42c7-8369-4ce85c866078	2025-09-09	\N	\N	\N	117.950000	\N	GENERATED	2025-11-04 12:45:11.972905+01
8f567a45-516e-441f-8ba3-507cdd9db7bf	92125d99-571e-42c7-8369-4ce85c866078	2025-09-10	\N	\N	\N	117.320000	\N	GENERATED	2025-11-04 12:45:11.973549+01
2b61351a-37d9-4e66-abf3-40ca8c84a387	92125d99-571e-42c7-8369-4ce85c866078	2025-09-11	\N	\N	\N	118.180000	\N	GENERATED	2025-11-04 12:45:11.974173+01
81c79467-db85-49c1-9c28-051768f5425f	92125d99-571e-42c7-8369-4ce85c866078	2025-09-12	\N	\N	\N	116.870000	\N	GENERATED	2025-11-04 12:45:11.974839+01
0581bbf0-cd31-4820-bc3f-0e360023fab5	92125d99-571e-42c7-8369-4ce85c866078	2025-09-13	\N	\N	\N	117.610000	\N	GENERATED	2025-11-04 12:45:11.97558+01
9e0080f9-9eaf-4a57-aed2-6aef234f86db	92125d99-571e-42c7-8369-4ce85c866078	2025-09-14	\N	\N	\N	117.030000	\N	GENERATED	2025-11-04 12:45:11.97623+01
897f4273-7bc7-4381-9111-828a3c050c99	92125d99-571e-42c7-8369-4ce85c866078	2025-09-15	\N	\N	\N	118.680000	\N	GENERATED	2025-11-04 12:45:11.977027+01
d7d5ae23-532e-4d20-b786-5acb824e0a97	92125d99-571e-42c7-8369-4ce85c866078	2025-09-16	\N	\N	\N	117.800000	\N	GENERATED	2025-11-04 12:45:11.977964+01
d1545041-158e-417d-a352-0ddccd3c49d1	92125d99-571e-42c7-8369-4ce85c866078	2025-09-17	\N	\N	\N	116.980000	\N	GENERATED	2025-11-04 12:45:11.978683+01
01ac6d4f-d41b-4491-97c8-888913299660	92125d99-571e-42c7-8369-4ce85c866078	2025-09-18	\N	\N	\N	116.710000	\N	GENERATED	2025-11-04 12:45:11.979307+01
d2e108da-e031-4ad0-baaa-8a33613fcf93	92125d99-571e-42c7-8369-4ce85c866078	2025-09-19	\N	\N	\N	118.470000	\N	GENERATED	2025-11-04 12:45:11.979954+01
58fe1d70-ffe5-47ab-a160-02068c5f0960	92125d99-571e-42c7-8369-4ce85c866078	2025-09-20	\N	\N	\N	117.860000	\N	GENERATED	2025-11-04 12:45:11.980585+01
0596582a-72cc-4f10-a244-b053173d8081	92125d99-571e-42c7-8369-4ce85c866078	2025-09-21	\N	\N	\N	117.680000	\N	GENERATED	2025-11-04 12:45:11.981216+01
176f7bad-13b8-46ef-a913-85213b2ba0a8	92125d99-571e-42c7-8369-4ce85c866078	2025-09-22	\N	\N	\N	118.740000	\N	GENERATED	2025-11-04 12:45:11.981858+01
7efa95b9-91fe-44aa-8e7c-e4dbace1c5c9	92125d99-571e-42c7-8369-4ce85c866078	2025-09-23	\N	\N	\N	117.000000	\N	GENERATED	2025-11-04 12:45:11.982479+01
f3d85d7c-2d2c-46ae-8f6f-8c377668b279	92125d99-571e-42c7-8369-4ce85c866078	2025-09-24	\N	\N	\N	118.070000	\N	GENERATED	2025-11-04 12:45:11.983115+01
74f08d95-7e6b-4158-92c6-0cb00f778637	92125d99-571e-42c7-8369-4ce85c866078	2025-09-25	\N	\N	\N	118.380000	\N	GENERATED	2025-11-04 12:45:11.983747+01
6ce803b2-b52f-4a8f-89c8-70452812dc79	92125d99-571e-42c7-8369-4ce85c866078	2025-09-26	\N	\N	\N	118.420000	\N	GENERATED	2025-11-04 12:45:11.984407+01
790cc26a-a17a-47b7-8a25-aa2a9ae81f09	92125d99-571e-42c7-8369-4ce85c866078	2025-09-27	\N	\N	\N	118.170000	\N	GENERATED	2025-11-04 12:45:11.985049+01
73609941-0d08-4d52-af85-6c073f5ec443	92125d99-571e-42c7-8369-4ce85c866078	2025-09-28	\N	\N	\N	117.730000	\N	GENERATED	2025-11-04 12:45:11.985683+01
23c0e874-8a13-4ff5-86a8-5f654067b926	92125d99-571e-42c7-8369-4ce85c866078	2025-09-29	\N	\N	\N	117.970000	\N	GENERATED	2025-11-04 12:45:11.986313+01
6e769687-6086-4911-880b-3abd4d192ec8	92125d99-571e-42c7-8369-4ce85c866078	2025-09-30	\N	\N	\N	119.040000	\N	GENERATED	2025-11-04 12:45:11.98694+01
882b85cd-b6f9-488f-9240-049ac2a76977	92125d99-571e-42c7-8369-4ce85c866078	2025-10-01	\N	\N	\N	117.960000	\N	GENERATED	2025-11-04 12:45:11.987602+01
07bf18e3-5a01-4d7f-af53-a4282e038caf	92125d99-571e-42c7-8369-4ce85c866078	2025-10-02	\N	\N	\N	116.980000	\N	GENERATED	2025-11-04 12:45:11.988256+01
6f68608e-e775-41ff-930f-e1d0333dd6c8	92125d99-571e-42c7-8369-4ce85c866078	2025-10-03	\N	\N	\N	117.400000	\N	GENERATED	2025-11-04 12:45:11.988885+01
4b2ffac8-c838-4c7c-b371-4383fff0756d	92125d99-571e-42c7-8369-4ce85c866078	2025-10-04	\N	\N	\N	118.470000	\N	GENERATED	2025-11-04 12:45:11.989543+01
45dee3ba-81b0-453b-9ac7-0fcb24a47788	92125d99-571e-42c7-8369-4ce85c866078	2025-10-05	\N	\N	\N	118.370000	\N	GENERATED	2025-11-04 12:45:11.990183+01
6928e8e5-3981-4624-b79e-2788a4771247	92125d99-571e-42c7-8369-4ce85c866078	2025-10-06	\N	\N	\N	118.480000	\N	GENERATED	2025-11-04 12:45:11.990905+01
54078fc1-8424-4399-ae9b-94ed22b76745	92125d99-571e-42c7-8369-4ce85c866078	2025-10-07	\N	\N	\N	118.160000	\N	GENERATED	2025-11-04 12:45:11.991554+01
66b58e5b-f1be-4bb5-94e4-aa821b19a0b6	92125d99-571e-42c7-8369-4ce85c866078	2025-10-08	\N	\N	\N	117.480000	\N	GENERATED	2025-11-04 12:45:11.992525+01
91e75429-91b2-40e3-ba4e-964ff6c49038	92125d99-571e-42c7-8369-4ce85c866078	2025-10-09	\N	\N	\N	117.190000	\N	GENERATED	2025-11-04 12:45:11.993356+01
e3425e8b-4cfe-4fd3-8011-caa0154b2ea0	92125d99-571e-42c7-8369-4ce85c866078	2025-10-10	\N	\N	\N	117.430000	\N	GENERATED	2025-11-04 12:45:11.994108+01
6c012d65-d1c7-4dae-a035-66a3bc47a900	92125d99-571e-42c7-8369-4ce85c866078	2025-10-11	\N	\N	\N	117.510000	\N	GENERATED	2025-11-04 12:45:11.994764+01
0e631320-f3a0-4706-b10c-d53d0597a434	92125d99-571e-42c7-8369-4ce85c866078	2025-10-12	\N	\N	\N	117.300000	\N	GENERATED	2025-11-04 12:45:11.995495+01
c62e0915-561e-444d-8cfd-6fe71feeb985	92125d99-571e-42c7-8369-4ce85c866078	2025-10-13	\N	\N	\N	119.360000	\N	GENERATED	2025-11-04 12:45:11.996133+01
b17b8998-28c8-43a9-bfe6-cd606ef56b74	92125d99-571e-42c7-8369-4ce85c866078	2025-10-14	\N	\N	\N	117.530000	\N	GENERATED	2025-11-04 12:45:11.996775+01
7d52371b-0324-48d1-8709-a9021083caf5	92125d99-571e-42c7-8369-4ce85c866078	2025-10-15	\N	\N	\N	119.220000	\N	GENERATED	2025-11-04 12:45:11.997456+01
321c2a39-4e7a-41f1-bb83-8086145a1759	92125d99-571e-42c7-8369-4ce85c866078	2025-10-16	\N	\N	\N	117.910000	\N	GENERATED	2025-11-04 12:45:11.998112+01
07eec9fd-0c3c-4d84-814f-d4aa252d2e36	92125d99-571e-42c7-8369-4ce85c866078	2025-10-17	\N	\N	\N	118.650000	\N	GENERATED	2025-11-04 12:45:11.998754+01
3ee6d24b-bb4a-4a25-a448-643d08caa11a	92125d99-571e-42c7-8369-4ce85c866078	2025-10-18	\N	\N	\N	117.380000	\N	GENERATED	2025-11-04 12:45:11.999398+01
da6bc3a8-9172-4fbc-ac22-2f9ddadc8dbb	92125d99-571e-42c7-8369-4ce85c866078	2025-10-19	\N	\N	\N	118.400000	\N	GENERATED	2025-11-04 12:45:12.000134+01
7a9dcbe2-9880-4430-9068-a2210e117f70	92125d99-571e-42c7-8369-4ce85c866078	2025-10-20	\N	\N	\N	119.040000	\N	GENERATED	2025-11-04 12:45:12.000902+01
bcfacfc1-ba98-413c-a728-40a85ea4301e	92125d99-571e-42c7-8369-4ce85c866078	2025-10-21	\N	\N	\N	118.980000	\N	GENERATED	2025-11-04 12:45:12.001581+01
bc98ce19-65e9-4c2d-b0eb-d6e3adf1bae9	92125d99-571e-42c7-8369-4ce85c866078	2025-10-22	\N	\N	\N	118.300000	\N	GENERATED	2025-11-04 12:45:12.002229+01
831fc8c2-7f85-4fe7-ab87-f133610dc5ae	92125d99-571e-42c7-8369-4ce85c866078	2025-10-23	\N	\N	\N	118.530000	\N	GENERATED	2025-11-04 12:45:12.002867+01
82f808fe-5b95-4c8a-b460-9c83a786e68f	92125d99-571e-42c7-8369-4ce85c866078	2025-10-24	\N	\N	\N	119.230000	\N	GENERATED	2025-11-04 12:45:12.00351+01
dff988cd-ddc3-471c-be42-185cac8ceee5	92125d99-571e-42c7-8369-4ce85c866078	2025-10-25	\N	\N	\N	118.520000	\N	GENERATED	2025-11-04 12:45:12.004327+01
45b360ea-b63e-4d3f-902a-28a7bb7e622b	92125d99-571e-42c7-8369-4ce85c866078	2025-10-26	\N	\N	\N	117.780000	\N	GENERATED	2025-11-04 12:45:12.004959+01
4f127fb0-e6d4-446f-a4d4-5fdb416af8f5	92125d99-571e-42c7-8369-4ce85c866078	2025-10-27	\N	\N	\N	118.550000	\N	GENERATED	2025-11-04 12:45:12.005593+01
d145aae5-ea0f-4c8c-bff7-58c415188a51	92125d99-571e-42c7-8369-4ce85c866078	2025-10-28	\N	\N	\N	119.580000	\N	GENERATED	2025-11-04 12:45:12.006229+01
ae8a2e21-6c5b-4dfb-95c9-39f0c881fa9a	92125d99-571e-42c7-8369-4ce85c866078	2025-10-29	\N	\N	\N	119.400000	\N	GENERATED	2025-11-04 12:45:12.007651+01
389a84b8-01e3-4e5d-9aec-6230d202711b	92125d99-571e-42c7-8369-4ce85c866078	2025-10-30	\N	\N	\N	119.610000	\N	GENERATED	2025-11-04 12:45:12.008326+01
c8cd4d90-69cb-4670-a35e-9ee0f12c345f	92125d99-571e-42c7-8369-4ce85c866078	2025-10-31	\N	\N	\N	119.680000	\N	GENERATED	2025-11-04 12:45:12.008984+01
49315500-2ce6-4499-a433-86ff0fd09831	92125d99-571e-42c7-8369-4ce85c866078	2025-11-01	\N	\N	\N	119.610000	\N	GENERATED	2025-11-04 12:45:12.009645+01
b2d9f828-6c2c-4e81-98b4-875065902b43	92125d99-571e-42c7-8369-4ce85c866078	2025-11-02	\N	\N	\N	117.800000	\N	GENERATED	2025-11-04 12:45:12.010469+01
5ef32d72-81b4-48cf-ab36-1a356df69e96	92125d99-571e-42c7-8369-4ce85c866078	2025-11-03	\N	\N	\N	119.730000	\N	GENERATED	2025-11-04 12:45:12.0111+01
485c57a0-24bd-4514-8574-02f15d6eb281	cc52fa73-bb3a-49ea-bb36-a0191f934e11	2024-11-04	\N	\N	\N	231.180000	\N	GENERATED	2025-11-04 12:45:12.259491+01
eb3f904d-04cc-46b2-896e-09c62252612f	cc52fa73-bb3a-49ea-bb36-a0191f934e11	2024-11-05	\N	\N	\N	232.170000	\N	GENERATED	2025-11-04 12:45:12.260116+01
16265683-1ac0-416f-8058-31ecb25fccdd	cc52fa73-bb3a-49ea-bb36-a0191f934e11	2024-11-06	\N	\N	\N	231.750000	\N	GENERATED	2025-11-04 12:45:12.26082+01
f556a841-86b3-47f1-9a9e-e1e617b1c671	cc52fa73-bb3a-49ea-bb36-a0191f934e11	2024-11-07	\N	\N	\N	229.150000	\N	GENERATED	2025-11-04 12:45:12.261436+01
f437b09c-e682-424a-9b31-05bd79b32ef6	cc52fa73-bb3a-49ea-bb36-a0191f934e11	2024-11-08	\N	\N	\N	228.980000	\N	GENERATED	2025-11-04 12:45:12.262056+01
ff7eb4ed-e62e-4a3e-ba90-fb927f104ff1	cc52fa73-bb3a-49ea-bb36-a0191f934e11	2024-11-09	\N	\N	\N	232.530000	\N	GENERATED	2025-11-04 12:45:12.262666+01
5b8865e1-ddae-4f4d-bdda-ba6460661e21	cc52fa73-bb3a-49ea-bb36-a0191f934e11	2024-11-10	\N	\N	\N	232.490000	\N	GENERATED	2025-11-04 12:45:12.26328+01
cad6d63b-b825-4ae7-a152-f585678eae1f	cc52fa73-bb3a-49ea-bb36-a0191f934e11	2024-11-11	\N	\N	\N	228.490000	\N	GENERATED	2025-11-04 12:45:12.263893+01
02434033-8819-4359-89cf-082570396a4d	cc52fa73-bb3a-49ea-bb36-a0191f934e11	2024-11-12	\N	\N	\N	229.080000	\N	GENERATED	2025-11-04 12:45:12.264509+01
2354befd-2827-4621-b043-98a8bd5d0219	cc52fa73-bb3a-49ea-bb36-a0191f934e11	2024-11-13	\N	\N	\N	230.580000	\N	GENERATED	2025-11-04 12:45:12.265127+01
b171b474-fc06-4510-a899-39559a1e06f5	cc52fa73-bb3a-49ea-bb36-a0191f934e11	2024-11-14	\N	\N	\N	228.820000	\N	GENERATED	2025-11-04 12:45:12.265743+01
60e4c9c8-fd50-43be-b84e-c17773e120d2	cc52fa73-bb3a-49ea-bb36-a0191f934e11	2024-11-15	\N	\N	\N	231.860000	\N	GENERATED	2025-11-04 12:45:12.266355+01
a66d2669-a78a-46d4-aef7-ac918277f933	cc52fa73-bb3a-49ea-bb36-a0191f934e11	2024-11-16	\N	\N	\N	232.150000	\N	GENERATED	2025-11-04 12:45:12.26697+01
af725906-b22e-411b-b026-280986474e65	cc52fa73-bb3a-49ea-bb36-a0191f934e11	2024-11-17	\N	\N	\N	231.180000	\N	GENERATED	2025-11-04 12:45:12.267581+01
ecd7a432-823d-4a14-b7a8-0bee079f1b8c	cc52fa73-bb3a-49ea-bb36-a0191f934e11	2024-11-18	\N	\N	\N	229.610000	\N	GENERATED	2025-11-04 12:45:12.268214+01
f6c0312d-adb2-479b-b0d3-319c39da5eb5	cc52fa73-bb3a-49ea-bb36-a0191f934e11	2024-11-19	\N	\N	\N	231.320000	\N	GENERATED	2025-11-04 12:45:12.268845+01
a6b6199b-fcb2-47fe-9b8b-1752019fcea9	cc52fa73-bb3a-49ea-bb36-a0191f934e11	2024-11-20	\N	\N	\N	230.780000	\N	GENERATED	2025-11-04 12:45:12.269466+01
6e971afb-981d-4175-88a1-8215db8ddd7e	cc52fa73-bb3a-49ea-bb36-a0191f934e11	2024-11-21	\N	\N	\N	231.880000	\N	GENERATED	2025-11-04 12:45:12.270209+01
f1ba0610-dbae-4f80-9b8a-4a3d8c29b238	cc52fa73-bb3a-49ea-bb36-a0191f934e11	2024-11-22	\N	\N	\N	231.710000	\N	GENERATED	2025-11-04 12:45:12.271169+01
1cd7803d-9603-49ee-b703-09f9652d6c8a	cc52fa73-bb3a-49ea-bb36-a0191f934e11	2024-11-23	\N	\N	\N	232.870000	\N	GENERATED	2025-11-04 12:45:12.271863+01
fccab79d-a212-4a74-a373-830820a8cb72	cc52fa73-bb3a-49ea-bb36-a0191f934e11	2024-11-24	\N	\N	\N	228.720000	\N	GENERATED	2025-11-04 12:45:12.272664+01
302ec858-c98a-4cfb-b2b4-9b8d907045a9	cc52fa73-bb3a-49ea-bb36-a0191f934e11	2024-11-25	\N	\N	\N	230.190000	\N	GENERATED	2025-11-04 12:45:12.273364+01
a0095550-095e-4108-9e18-d0e67d7c71ae	cc52fa73-bb3a-49ea-bb36-a0191f934e11	2024-11-26	\N	\N	\N	230.740000	\N	GENERATED	2025-11-04 12:45:12.274005+01
2bc0b98c-cfe7-48cf-b289-b719a992bd58	cc52fa73-bb3a-49ea-bb36-a0191f934e11	2024-11-27	\N	\N	\N	231.130000	\N	GENERATED	2025-11-04 12:45:12.274755+01
14c884ed-8c7f-4c55-bf9c-20db00e48f71	cc52fa73-bb3a-49ea-bb36-a0191f934e11	2024-11-28	\N	\N	\N	232.610000	\N	GENERATED	2025-11-04 12:45:12.275386+01
5f578ac9-9c69-4c13-aae4-30483c55de19	cc52fa73-bb3a-49ea-bb36-a0191f934e11	2024-11-29	\N	\N	\N	232.500000	\N	GENERATED	2025-11-04 12:45:12.276107+01
8e91c639-5994-41e4-bf0d-7b1132afcfea	cc52fa73-bb3a-49ea-bb36-a0191f934e11	2024-11-30	\N	\N	\N	230.330000	\N	GENERATED	2025-11-04 12:45:12.276747+01
8390a15c-3e37-46a9-a746-d8fef1cc2151	cc52fa73-bb3a-49ea-bb36-a0191f934e11	2024-12-01	\N	\N	\N	230.260000	\N	GENERATED	2025-11-04 12:45:12.277356+01
e7dd3e9f-fa43-4ecd-aec7-c9c6cec7a875	cc52fa73-bb3a-49ea-bb36-a0191f934e11	2024-12-02	\N	\N	\N	229.180000	\N	GENERATED	2025-11-04 12:45:12.277991+01
957a8fbb-9004-4df2-9ab3-83d1660ce03f	cc52fa73-bb3a-49ea-bb36-a0191f934e11	2024-12-03	\N	\N	\N	230.140000	\N	GENERATED	2025-11-04 12:45:12.278603+01
4274c445-9366-4829-b69d-4b99d0143b97	cc52fa73-bb3a-49ea-bb36-a0191f934e11	2024-12-04	\N	\N	\N	229.640000	\N	GENERATED	2025-11-04 12:45:12.279212+01
8b9fd5b5-6257-4910-b08f-5c1815372513	cc52fa73-bb3a-49ea-bb36-a0191f934e11	2024-12-05	\N	\N	\N	232.450000	\N	GENERATED	2025-11-04 12:45:12.279836+01
43087129-6745-41ca-aaaa-d377d87143d6	cc52fa73-bb3a-49ea-bb36-a0191f934e11	2024-12-06	\N	\N	\N	230.650000	\N	GENERATED	2025-11-04 12:45:12.280455+01
63f3dcd1-8a4f-42a6-bab7-37615e42397c	cc52fa73-bb3a-49ea-bb36-a0191f934e11	2024-12-07	\N	\N	\N	232.590000	\N	GENERATED	2025-11-04 12:45:12.28107+01
47b1643a-276f-42ac-a275-493b255db35f	cc52fa73-bb3a-49ea-bb36-a0191f934e11	2024-12-08	\N	\N	\N	233.300000	\N	GENERATED	2025-11-04 12:45:12.281683+01
fc76323b-85b4-4b00-8719-e0fa6d9e3983	cc52fa73-bb3a-49ea-bb36-a0191f934e11	2024-12-09	\N	\N	\N	233.120000	\N	GENERATED	2025-11-04 12:45:12.282311+01
3e862dea-a8da-4968-8e98-fb6595bb8dfe	cc52fa73-bb3a-49ea-bb36-a0191f934e11	2024-12-10	\N	\N	\N	231.710000	\N	GENERATED	2025-11-04 12:45:12.282945+01
1d5f0609-9887-4aed-8991-936a5d1770df	cc52fa73-bb3a-49ea-bb36-a0191f934e11	2024-12-11	\N	\N	\N	230.380000	\N	GENERATED	2025-11-04 12:45:12.283571+01
230d6cc1-dfea-41ec-af4f-06bd7dd1d1cd	cc52fa73-bb3a-49ea-bb36-a0191f934e11	2024-12-12	\N	\N	\N	230.440000	\N	GENERATED	2025-11-04 12:45:12.284198+01
d4741f3c-de32-45e1-ad1d-585c30a62bda	cc52fa73-bb3a-49ea-bb36-a0191f934e11	2024-12-13	\N	\N	\N	229.970000	\N	GENERATED	2025-11-04 12:45:12.284896+01
287c302a-7c75-40ed-a9ce-3009fdd30c34	cc52fa73-bb3a-49ea-bb36-a0191f934e11	2024-12-14	\N	\N	\N	230.580000	\N	GENERATED	2025-11-04 12:45:12.285552+01
38f51b2b-2dbb-4c91-8c05-d5fd185408e5	cc52fa73-bb3a-49ea-bb36-a0191f934e11	2024-12-15	\N	\N	\N	230.120000	\N	GENERATED	2025-11-04 12:45:12.286183+01
6d0f563c-73a8-424e-b376-cc43884c0efe	cc52fa73-bb3a-49ea-bb36-a0191f934e11	2024-12-16	\N	\N	\N	233.510000	\N	GENERATED	2025-11-04 12:45:12.286848+01
38d07a23-40da-41d2-9287-89479fa86a96	cc52fa73-bb3a-49ea-bb36-a0191f934e11	2024-12-17	\N	\N	\N	232.650000	\N	GENERATED	2025-11-04 12:45:12.287753+01
07153dca-2705-4d07-a834-c22bff6e89a8	cc52fa73-bb3a-49ea-bb36-a0191f934e11	2024-12-18	\N	\N	\N	231.450000	\N	GENERATED	2025-11-04 12:45:12.288396+01
7318f446-31d6-44af-9954-e3a8c12b73c8	cc52fa73-bb3a-49ea-bb36-a0191f934e11	2024-12-19	\N	\N	\N	230.030000	\N	GENERATED	2025-11-04 12:45:12.289027+01
4815ef47-06f4-4a0d-a5fa-87bf361a01af	cc52fa73-bb3a-49ea-bb36-a0191f934e11	2024-12-20	\N	\N	\N	233.740000	\N	GENERATED	2025-11-04 12:45:12.289638+01
8246c6ca-ab96-4598-b414-96f18701fa69	cc52fa73-bb3a-49ea-bb36-a0191f934e11	2024-12-21	\N	\N	\N	233.330000	\N	GENERATED	2025-11-04 12:45:12.29027+01
541c0fd5-73e3-48ef-9ac8-4d3c2a04cbf4	cc52fa73-bb3a-49ea-bb36-a0191f934e11	2024-12-22	\N	\N	\N	233.060000	\N	GENERATED	2025-11-04 12:45:12.290892+01
ab207a9c-b46a-48f4-8fad-e02380f65eb1	cc52fa73-bb3a-49ea-bb36-a0191f934e11	2024-12-23	\N	\N	\N	232.200000	\N	GENERATED	2025-11-04 12:45:12.291506+01
85da8f8c-3ce5-4285-a0d3-ffce54d4e754	cc52fa73-bb3a-49ea-bb36-a0191f934e11	2024-12-24	\N	\N	\N	233.660000	\N	GENERATED	2025-11-04 12:45:12.292155+01
45625c82-2217-4a95-82b8-d0cdb8259310	cc52fa73-bb3a-49ea-bb36-a0191f934e11	2024-12-25	\N	\N	\N	233.340000	\N	GENERATED	2025-11-04 12:45:12.292786+01
74e77b2a-876b-43ab-af7a-1f50a387b1cb	cc52fa73-bb3a-49ea-bb36-a0191f934e11	2024-12-26	\N	\N	\N	231.150000	\N	GENERATED	2025-11-04 12:45:12.293466+01
fa759fc1-de8b-4853-b15f-2283d7aed5fc	cc52fa73-bb3a-49ea-bb36-a0191f934e11	2024-12-27	\N	\N	\N	234.520000	\N	GENERATED	2025-11-04 12:45:12.294115+01
fcfb29bd-a41b-409c-9c20-2b8ecc00af0b	cc52fa73-bb3a-49ea-bb36-a0191f934e11	2024-12-28	\N	\N	\N	232.610000	\N	GENERATED	2025-11-04 12:45:12.294741+01
1de4e64c-7230-4d6f-9295-473df14f7397	cc52fa73-bb3a-49ea-bb36-a0191f934e11	2024-12-29	\N	\N	\N	231.090000	\N	GENERATED	2025-11-04 12:45:12.295374+01
a3acba91-3aff-4575-9414-c244c1918e58	cc52fa73-bb3a-49ea-bb36-a0191f934e11	2024-12-30	\N	\N	\N	231.170000	\N	GENERATED	2025-11-04 12:45:12.296122+01
a2d9216f-3793-437d-8a80-ed42a03a2f04	cc52fa73-bb3a-49ea-bb36-a0191f934e11	2024-12-31	\N	\N	\N	231.900000	\N	GENERATED	2025-11-04 12:45:12.296754+01
9386cd04-b45f-4c36-9a4f-13fedd3de118	cc52fa73-bb3a-49ea-bb36-a0191f934e11	2025-01-01	\N	\N	\N	231.970000	\N	GENERATED	2025-11-04 12:45:12.297385+01
7d0ae0eb-122f-4054-b14c-181646e07081	cc52fa73-bb3a-49ea-bb36-a0191f934e11	2025-01-02	\N	\N	\N	233.160000	\N	GENERATED	2025-11-04 12:45:12.298015+01
74c49f1f-0c01-4f35-8af6-fbb4ee84ed7b	cc52fa73-bb3a-49ea-bb36-a0191f934e11	2025-01-03	\N	\N	\N	231.450000	\N	GENERATED	2025-11-04 12:45:12.298626+01
6280d288-1696-4d23-8768-09cfce94b191	cc52fa73-bb3a-49ea-bb36-a0191f934e11	2025-01-04	\N	\N	\N	233.630000	\N	GENERATED	2025-11-04 12:45:12.299254+01
f4ef2572-a0d0-4073-ac7e-e9f7bda12432	cc52fa73-bb3a-49ea-bb36-a0191f934e11	2025-01-05	\N	\N	\N	233.010000	\N	GENERATED	2025-11-04 12:45:12.299881+01
73f7b231-7a7b-47e9-8f39-fe1841a85b3a	cc52fa73-bb3a-49ea-bb36-a0191f934e11	2025-01-06	\N	\N	\N	233.920000	\N	GENERATED	2025-11-04 12:45:12.300746+01
35bc99e9-1e0d-4d0c-9f08-69ef80095efb	cc52fa73-bb3a-49ea-bb36-a0191f934e11	2025-01-07	\N	\N	\N	233.400000	\N	GENERATED	2025-11-04 12:45:12.301488+01
8b36cac6-4153-423b-9515-51b6ccdaa1c5	cc52fa73-bb3a-49ea-bb36-a0191f934e11	2025-01-08	\N	\N	\N	234.610000	\N	GENERATED	2025-11-04 12:45:12.302588+01
455ed297-97a6-4f7d-954d-099faa974b7e	cc52fa73-bb3a-49ea-bb36-a0191f934e11	2025-01-09	\N	\N	\N	234.410000	\N	GENERATED	2025-11-04 12:45:12.303523+01
7a4ed720-5d13-4aea-8b6b-4f4b887cc2d1	cc52fa73-bb3a-49ea-bb36-a0191f934e11	2025-01-10	\N	\N	\N	231.680000	\N	GENERATED	2025-11-04 12:45:12.304367+01
4df93dbf-2f7e-444a-a4c3-8b73c065a63e	cc52fa73-bb3a-49ea-bb36-a0191f934e11	2025-01-11	\N	\N	\N	234.980000	\N	GENERATED	2025-11-04 12:45:12.305211+01
7fd50e28-ddfd-46a6-85e2-eab540f0d09d	cc52fa73-bb3a-49ea-bb36-a0191f934e11	2025-01-12	\N	\N	\N	233.790000	\N	GENERATED	2025-11-04 12:45:12.306047+01
e18b1563-b1aa-4c8f-a9da-0908617c4d90	cc52fa73-bb3a-49ea-bb36-a0191f934e11	2025-01-13	\N	\N	\N	234.250000	\N	GENERATED	2025-11-04 12:45:12.306762+01
c5d1367f-4bb2-41f3-a324-429b0af53e81	cc52fa73-bb3a-49ea-bb36-a0191f934e11	2025-01-14	\N	\N	\N	233.690000	\N	GENERATED	2025-11-04 12:45:12.307406+01
fabff3f5-6e2c-4578-a59c-c2c720f3bc69	cc52fa73-bb3a-49ea-bb36-a0191f934e11	2025-01-15	\N	\N	\N	234.710000	\N	GENERATED	2025-11-04 12:45:12.308032+01
0d7c7594-3b91-44ce-bd45-e81e726c500e	cc52fa73-bb3a-49ea-bb36-a0191f934e11	2025-01-16	\N	\N	\N	232.620000	\N	GENERATED	2025-11-04 12:45:12.308657+01
cc9335a0-e7ac-46e0-a52b-2f683c506023	cc52fa73-bb3a-49ea-bb36-a0191f934e11	2025-01-17	\N	\N	\N	233.710000	\N	GENERATED	2025-11-04 12:45:12.309284+01
4a4dd6c3-e0aa-44f7-86fc-981b0a8ea67a	cc52fa73-bb3a-49ea-bb36-a0191f934e11	2025-01-18	\N	\N	\N	235.110000	\N	GENERATED	2025-11-04 12:45:12.309928+01
59883717-71d7-4459-9f8a-6330564c0d8f	cc52fa73-bb3a-49ea-bb36-a0191f934e11	2025-01-19	\N	\N	\N	233.800000	\N	GENERATED	2025-11-04 12:45:12.310571+01
017ae483-6f35-448e-8471-f6d97a47a543	cc52fa73-bb3a-49ea-bb36-a0191f934e11	2025-01-20	\N	\N	\N	232.560000	\N	GENERATED	2025-11-04 12:45:12.311184+01
939188a9-6826-4126-8dbb-6b1481feaf5e	cc52fa73-bb3a-49ea-bb36-a0191f934e11	2025-01-21	\N	\N	\N	235.120000	\N	GENERATED	2025-11-04 12:45:12.311799+01
9978d193-8f84-46f1-835a-29e97c06845c	cc52fa73-bb3a-49ea-bb36-a0191f934e11	2025-01-22	\N	\N	\N	235.120000	\N	GENERATED	2025-11-04 12:45:12.312428+01
bff42ac6-ce0e-4dc4-b8b2-90178ce48e90	cc52fa73-bb3a-49ea-bb36-a0191f934e11	2025-01-23	\N	\N	\N	232.530000	\N	GENERATED	2025-11-04 12:45:12.313039+01
586039a4-20c6-4981-8321-525b38faa6d3	cc52fa73-bb3a-49ea-bb36-a0191f934e11	2025-01-24	\N	\N	\N	235.100000	\N	GENERATED	2025-11-04 12:45:12.313658+01
c3f2ec5d-d37d-4659-9cd9-59f984b37ac7	cc52fa73-bb3a-49ea-bb36-a0191f934e11	2025-01-25	\N	\N	\N	232.980000	\N	GENERATED	2025-11-04 12:45:12.31427+01
10e1be78-aee0-416b-886f-ab3cfd4ec513	cc52fa73-bb3a-49ea-bb36-a0191f934e11	2025-01-26	\N	\N	\N	232.850000	\N	GENERATED	2025-11-04 12:45:12.314877+01
45be59b6-8398-4121-b9ae-fa6839c2dcc0	cc52fa73-bb3a-49ea-bb36-a0191f934e11	2025-01-27	\N	\N	\N	233.780000	\N	GENERATED	2025-11-04 12:45:12.315487+01
1ec9d792-6fe9-44ce-b7be-09451ff8a2c4	cc52fa73-bb3a-49ea-bb36-a0191f934e11	2025-01-28	\N	\N	\N	233.960000	\N	GENERATED	2025-11-04 12:45:12.316162+01
cdb23d0a-7b05-4f1f-bfee-a4e5299b3b13	cc52fa73-bb3a-49ea-bb36-a0191f934e11	2025-01-29	\N	\N	\N	232.830000	\N	GENERATED	2025-11-04 12:45:12.317003+01
8cf201b5-ceae-4b1c-a183-a4fd5b7a9c02	cc52fa73-bb3a-49ea-bb36-a0191f934e11	2025-01-30	\N	\N	\N	232.210000	\N	GENERATED	2025-11-04 12:45:12.318313+01
fc76a3f9-9ac3-485d-84f2-9bced778f3c5	cc52fa73-bb3a-49ea-bb36-a0191f934e11	2025-01-31	\N	\N	\N	236.480000	\N	GENERATED	2025-11-04 12:45:12.319049+01
6ff86735-2e9a-4574-8630-cb35218c7433	cc52fa73-bb3a-49ea-bb36-a0191f934e11	2025-02-01	\N	\N	\N	236.160000	\N	GENERATED	2025-11-04 12:45:12.319713+01
95e8e8d5-c550-44d3-ac39-070bdd599dcf	cc52fa73-bb3a-49ea-bb36-a0191f934e11	2025-02-02	\N	\N	\N	233.980000	\N	GENERATED	2025-11-04 12:45:12.320342+01
25220802-d9b2-43cb-b4dd-f6f3b3d14ff7	cc52fa73-bb3a-49ea-bb36-a0191f934e11	2025-02-03	\N	\N	\N	236.540000	\N	GENERATED	2025-11-04 12:45:12.320971+01
d1c03d13-52cd-469d-93a3-099d385d7aaa	cc52fa73-bb3a-49ea-bb36-a0191f934e11	2025-02-04	\N	\N	\N	233.520000	\N	GENERATED	2025-11-04 12:45:12.321595+01
8d0deed2-b5c1-460d-b93c-c00e6180ebac	cc52fa73-bb3a-49ea-bb36-a0191f934e11	2025-02-05	\N	\N	\N	232.780000	\N	GENERATED	2025-11-04 12:45:12.32223+01
76ed8da6-0621-4004-b267-26c18b5bb63d	cc52fa73-bb3a-49ea-bb36-a0191f934e11	2025-02-06	\N	\N	\N	236.170000	\N	GENERATED	2025-11-04 12:45:12.322859+01
7048f025-b840-4c49-9072-e7fc29c8e2a5	cc52fa73-bb3a-49ea-bb36-a0191f934e11	2025-02-07	\N	\N	\N	236.620000	\N	GENERATED	2025-11-04 12:45:12.323464+01
2ac88a36-2d70-4802-a2c6-9df0bbfc86d5	cc52fa73-bb3a-49ea-bb36-a0191f934e11	2025-02-08	\N	\N	\N	233.730000	\N	GENERATED	2025-11-04 12:45:12.324073+01
8b216b14-ed57-4f31-b59a-19481feec129	cc52fa73-bb3a-49ea-bb36-a0191f934e11	2025-02-09	\N	\N	\N	234.020000	\N	GENERATED	2025-11-04 12:45:12.324691+01
635d6be5-cb4d-42a3-a1f1-463713faf469	cc52fa73-bb3a-49ea-bb36-a0191f934e11	2025-02-10	\N	\N	\N	233.060000	\N	GENERATED	2025-11-04 12:45:12.325309+01
ae61678f-0191-4c1b-89b2-6959535c239a	cc52fa73-bb3a-49ea-bb36-a0191f934e11	2025-02-11	\N	\N	\N	235.060000	\N	GENERATED	2025-11-04 12:45:12.325927+01
430f64de-1460-44db-8e81-28699d027048	cc52fa73-bb3a-49ea-bb36-a0191f934e11	2025-02-12	\N	\N	\N	233.420000	\N	GENERATED	2025-11-04 12:45:12.326536+01
7c4dad62-fe15-4702-a92c-de79981b92cf	cc52fa73-bb3a-49ea-bb36-a0191f934e11	2025-02-13	\N	\N	\N	235.080000	\N	GENERATED	2025-11-04 12:45:12.327155+01
12a50fc7-d2dd-453f-bb12-07b3dc94740b	cc52fa73-bb3a-49ea-bb36-a0191f934e11	2025-02-14	\N	\N	\N	235.680000	\N	GENERATED	2025-11-04 12:45:12.327784+01
2293ac92-b303-46d2-92ed-45c6f1c7be20	cc52fa73-bb3a-49ea-bb36-a0191f934e11	2025-02-15	\N	\N	\N	233.110000	\N	GENERATED	2025-11-04 12:45:12.328392+01
3c13a5b1-0a6f-4ca2-a383-9938ca52ace3	cc52fa73-bb3a-49ea-bb36-a0191f934e11	2025-02-16	\N	\N	\N	233.810000	\N	GENERATED	2025-11-04 12:45:12.329015+01
5781d0f5-98cc-4826-bd1e-cf5bb4652367	cc52fa73-bb3a-49ea-bb36-a0191f934e11	2025-02-17	\N	\N	\N	235.600000	\N	GENERATED	2025-11-04 12:45:12.329627+01
53b3cb2e-dc47-4a52-a35e-103b66ca0fc5	cc52fa73-bb3a-49ea-bb36-a0191f934e11	2025-02-18	\N	\N	\N	236.670000	\N	GENERATED	2025-11-04 12:45:12.330248+01
4bb9176b-62ec-4178-80e1-f3c2090c6ade	cc52fa73-bb3a-49ea-bb36-a0191f934e11	2025-02-19	\N	\N	\N	236.530000	\N	GENERATED	2025-11-04 12:45:12.330891+01
2258bf66-2d7a-4f59-a5d8-9b280219fc42	cc52fa73-bb3a-49ea-bb36-a0191f934e11	2025-02-20	\N	\N	\N	235.290000	\N	GENERATED	2025-11-04 12:45:12.331509+01
6d6b9b0b-e137-4aab-9e97-c3e3f3ab8a1b	cc52fa73-bb3a-49ea-bb36-a0191f934e11	2025-02-21	\N	\N	\N	236.840000	\N	GENERATED	2025-11-04 12:45:12.33228+01
213df76e-94fb-4f44-9c65-76135540532f	cc52fa73-bb3a-49ea-bb36-a0191f934e11	2025-02-22	\N	\N	\N	233.650000	\N	GENERATED	2025-11-04 12:45:12.332917+01
fdedcf09-252b-4390-ab4c-22cc29d6ab06	cc52fa73-bb3a-49ea-bb36-a0191f934e11	2025-02-23	\N	\N	\N	237.340000	\N	GENERATED	2025-11-04 12:45:12.333556+01
63345948-0a10-4b95-b4e1-f1d8a9d08cc6	cc52fa73-bb3a-49ea-bb36-a0191f934e11	2025-02-24	\N	\N	\N	235.230000	\N	GENERATED	2025-11-04 12:45:12.334173+01
2f5810fc-0a5c-4cca-a8ad-240af6ac147c	cc52fa73-bb3a-49ea-bb36-a0191f934e11	2025-02-25	\N	\N	\N	236.610000	\N	GENERATED	2025-11-04 12:45:12.334794+01
beaf3e20-a0d6-41e2-807b-530f81c896c9	cc52fa73-bb3a-49ea-bb36-a0191f934e11	2025-02-26	\N	\N	\N	235.360000	\N	GENERATED	2025-11-04 12:45:12.335401+01
400d495c-6182-492c-9728-1d346e6d7857	cc52fa73-bb3a-49ea-bb36-a0191f934e11	2025-02-27	\N	\N	\N	234.880000	\N	GENERATED	2025-11-04 12:45:12.336088+01
cd732361-ba43-4b76-8d38-4e64c671798c	cc52fa73-bb3a-49ea-bb36-a0191f934e11	2025-02-28	\N	\N	\N	237.830000	\N	GENERATED	2025-11-04 12:45:12.336699+01
eca66841-ebee-4712-8a0a-87f724fb358c	cc52fa73-bb3a-49ea-bb36-a0191f934e11	2025-03-01	\N	\N	\N	236.520000	\N	GENERATED	2025-11-04 12:45:12.337321+01
b42ffa36-5237-4058-980a-ab87787f7512	cc52fa73-bb3a-49ea-bb36-a0191f934e11	2025-03-02	\N	\N	\N	234.340000	\N	GENERATED	2025-11-04 12:45:12.337948+01
e4a0920e-b13c-4d4f-a940-ab0d46060925	cc52fa73-bb3a-49ea-bb36-a0191f934e11	2025-03-03	\N	\N	\N	233.730000	\N	GENERATED	2025-11-04 12:45:12.33857+01
f81302b7-1637-44fc-a4ef-2d54d6bfff8b	cc52fa73-bb3a-49ea-bb36-a0191f934e11	2025-03-04	\N	\N	\N	235.440000	\N	GENERATED	2025-11-04 12:45:12.33919+01
b0501ac4-2f35-4dfd-bc9b-ee7ad5649d7e	cc52fa73-bb3a-49ea-bb36-a0191f934e11	2025-03-05	\N	\N	\N	234.000000	\N	GENERATED	2025-11-04 12:45:12.3398+01
a3033ccc-e70b-4fb1-b06d-da7f2c350908	cc52fa73-bb3a-49ea-bb36-a0191f934e11	2025-03-06	\N	\N	\N	235.900000	\N	GENERATED	2025-11-04 12:45:12.34041+01
5d1543d4-ffc5-4171-9e09-e88188538b3a	cc52fa73-bb3a-49ea-bb36-a0191f934e11	2025-03-07	\N	\N	\N	234.610000	\N	GENERATED	2025-11-04 12:45:12.341031+01
0de0c5c2-3556-4b3d-b023-7b3e95ce55e3	cc52fa73-bb3a-49ea-bb36-a0191f934e11	2025-03-08	\N	\N	\N	235.310000	\N	GENERATED	2025-11-04 12:45:12.341649+01
37d8f6f6-635d-43c6-80ef-f854d7fc9cff	cc52fa73-bb3a-49ea-bb36-a0191f934e11	2025-03-09	\N	\N	\N	238.380000	\N	GENERATED	2025-11-04 12:45:12.342266+01
1c3830cb-0a4f-4679-8cd3-51ddc62fad37	cc52fa73-bb3a-49ea-bb36-a0191f934e11	2025-03-10	\N	\N	\N	238.200000	\N	GENERATED	2025-11-04 12:45:12.342888+01
26b36983-d9d3-405a-bf51-49417bf15533	cc52fa73-bb3a-49ea-bb36-a0191f934e11	2025-03-11	\N	\N	\N	234.320000	\N	GENERATED	2025-11-04 12:45:12.343494+01
12b39516-8377-4abd-beb4-43df3b03b1bb	cc52fa73-bb3a-49ea-bb36-a0191f934e11	2025-03-12	\N	\N	\N	237.340000	\N	GENERATED	2025-11-04 12:45:12.344117+01
664ed36d-e537-4c89-93db-61f61bf68441	cc52fa73-bb3a-49ea-bb36-a0191f934e11	2025-03-13	\N	\N	\N	237.870000	\N	GENERATED	2025-11-04 12:45:12.344723+01
04ba14ba-a55a-4de2-93b1-5f8a45a5c820	cc52fa73-bb3a-49ea-bb36-a0191f934e11	2025-03-14	\N	\N	\N	236.150000	\N	GENERATED	2025-11-04 12:45:12.345355+01
4bec761e-e2da-467d-b75f-b7bc3db9aca7	cc52fa73-bb3a-49ea-bb36-a0191f934e11	2025-03-15	\N	\N	\N	235.130000	\N	GENERATED	2025-11-04 12:45:12.345979+01
0724e145-cd1e-4015-ad27-93a33671c052	cc52fa73-bb3a-49ea-bb36-a0191f934e11	2025-03-16	\N	\N	\N	237.630000	\N	GENERATED	2025-11-04 12:45:12.346593+01
614f4dbc-62b7-4fcb-9608-55836213a673	cc52fa73-bb3a-49ea-bb36-a0191f934e11	2025-03-17	\N	\N	\N	236.250000	\N	GENERATED	2025-11-04 12:45:12.347234+01
0b847ed1-2a02-4985-89e7-7db3c43b91aa	cc52fa73-bb3a-49ea-bb36-a0191f934e11	2025-03-18	\N	\N	\N	236.190000	\N	GENERATED	2025-11-04 12:45:12.34794+01
697494dd-58a7-4e42-86fe-a72ee7cda43b	cc52fa73-bb3a-49ea-bb36-a0191f934e11	2025-03-19	\N	\N	\N	238.610000	\N	GENERATED	2025-11-04 12:45:12.348764+01
aaa58006-a234-45b2-ab29-8dcd03d841ef	cc52fa73-bb3a-49ea-bb36-a0191f934e11	2025-03-20	\N	\N	\N	235.760000	\N	GENERATED	2025-11-04 12:45:12.349555+01
00f025c8-02fb-41b0-a205-832a5c075f46	cc52fa73-bb3a-49ea-bb36-a0191f934e11	2025-03-21	\N	\N	\N	236.520000	\N	GENERATED	2025-11-04 12:45:12.350291+01
4800d840-1b59-479f-84ec-f3ea2694adba	cc52fa73-bb3a-49ea-bb36-a0191f934e11	2025-03-22	\N	\N	\N	237.700000	\N	GENERATED	2025-11-04 12:45:12.350932+01
c394ea1b-74e6-404c-8e41-e00c82be680c	cc52fa73-bb3a-49ea-bb36-a0191f934e11	2025-03-23	\N	\N	\N	237.670000	\N	GENERATED	2025-11-04 12:45:12.351563+01
4eac2579-8094-4db3-9c59-25d105d67805	cc52fa73-bb3a-49ea-bb36-a0191f934e11	2025-03-24	\N	\N	\N	236.300000	\N	GENERATED	2025-11-04 12:45:12.35219+01
cef8ff7d-6ee9-4532-8f93-43ea6cdd82aa	cc52fa73-bb3a-49ea-bb36-a0191f934e11	2025-03-25	\N	\N	\N	238.890000	\N	GENERATED	2025-11-04 12:45:12.35284+01
f198f377-f2eb-4807-935f-2935e1395458	cc52fa73-bb3a-49ea-bb36-a0191f934e11	2025-03-26	\N	\N	\N	238.130000	\N	GENERATED	2025-11-04 12:45:12.353455+01
c43e3489-1d21-4286-9175-64a03eff3760	cc52fa73-bb3a-49ea-bb36-a0191f934e11	2025-03-27	\N	\N	\N	239.320000	\N	GENERATED	2025-11-04 12:45:12.3541+01
0f8c7b89-ca3f-4248-a146-8378fcee78dd	cc52fa73-bb3a-49ea-bb36-a0191f934e11	2025-03-28	\N	\N	\N	235.860000	\N	GENERATED	2025-11-04 12:45:12.354717+01
2f2466a7-04ad-4145-81e4-d290946d59ef	cc52fa73-bb3a-49ea-bb36-a0191f934e11	2025-03-29	\N	\N	\N	236.400000	\N	GENERATED	2025-11-04 12:45:12.355344+01
5cb2db72-c075-4ac8-b36c-e06c699213dc	cc52fa73-bb3a-49ea-bb36-a0191f934e11	2025-03-30	\N	\N	\N	238.950000	\N	GENERATED	2025-11-04 12:45:12.356039+01
c70e0c8e-6f2c-412c-b159-dd70f209a33f	cc52fa73-bb3a-49ea-bb36-a0191f934e11	2025-03-31	\N	\N	\N	238.860000	\N	GENERATED	2025-11-04 12:45:12.35665+01
39788c56-d688-4ed5-8d97-7d0ba31479fc	cc52fa73-bb3a-49ea-bb36-a0191f934e11	2025-04-01	\N	\N	\N	238.890000	\N	GENERATED	2025-11-04 12:45:12.357273+01
f01f226c-017c-4a19-8e55-8013c4769feb	cc52fa73-bb3a-49ea-bb36-a0191f934e11	2025-04-02	\N	\N	\N	238.160000	\N	GENERATED	2025-11-04 12:45:12.357895+01
a370cbb2-4b61-4569-bc51-415f028218dc	cc52fa73-bb3a-49ea-bb36-a0191f934e11	2025-04-03	\N	\N	\N	237.710000	\N	GENERATED	2025-11-04 12:45:12.358516+01
2c715bec-3aaa-49a7-971f-51283c4ed461	cc52fa73-bb3a-49ea-bb36-a0191f934e11	2025-04-04	\N	\N	\N	237.590000	\N	GENERATED	2025-11-04 12:45:12.359145+01
46f74f3d-7bfc-42f8-b43a-8c546b00d2b3	cc52fa73-bb3a-49ea-bb36-a0191f934e11	2025-04-05	\N	\N	\N	239.230000	\N	GENERATED	2025-11-04 12:45:12.359755+01
9ebf22da-097d-44a9-bfe5-9eb6bc5e01da	cc52fa73-bb3a-49ea-bb36-a0191f934e11	2025-04-06	\N	\N	\N	239.960000	\N	GENERATED	2025-11-04 12:45:12.36037+01
5ad0192d-6b52-4901-bcb9-40a966e101ea	cc52fa73-bb3a-49ea-bb36-a0191f934e11	2025-04-07	\N	\N	\N	236.960000	\N	GENERATED	2025-11-04 12:45:12.360985+01
a28d13b5-5e48-43b4-be48-a2509b43cfaf	cc52fa73-bb3a-49ea-bb36-a0191f934e11	2025-04-08	\N	\N	\N	237.330000	\N	GENERATED	2025-11-04 12:45:12.361611+01
2146e5c3-366a-45e8-8e1e-cf8b598307e2	cc52fa73-bb3a-49ea-bb36-a0191f934e11	2025-04-09	\N	\N	\N	235.900000	\N	GENERATED	2025-11-04 12:45:12.362274+01
41a87290-cd15-45bc-94cf-73b9de039fea	cc52fa73-bb3a-49ea-bb36-a0191f934e11	2025-04-10	\N	\N	\N	237.130000	\N	GENERATED	2025-11-04 12:45:12.362884+01
49b96930-35e4-4973-acde-02eb93423dec	cc52fa73-bb3a-49ea-bb36-a0191f934e11	2025-04-11	\N	\N	\N	237.670000	\N	GENERATED	2025-11-04 12:45:12.363671+01
ac62ab33-000f-4c8c-aa2f-9fef91a02e58	cc52fa73-bb3a-49ea-bb36-a0191f934e11	2025-04-12	\N	\N	\N	239.360000	\N	GENERATED	2025-11-04 12:45:12.364361+01
33c2c879-0f34-4048-89d1-f97d25e8d751	cc52fa73-bb3a-49ea-bb36-a0191f934e11	2025-04-13	\N	\N	\N	239.460000	\N	GENERATED	2025-11-04 12:45:12.364985+01
68caa3fd-8ed9-4de1-b472-2a8b7e7c67e2	cc52fa73-bb3a-49ea-bb36-a0191f934e11	2025-04-14	\N	\N	\N	239.820000	\N	GENERATED	2025-11-04 12:45:12.365603+01
8c4298e7-16bc-4677-b07c-973ceaee0545	cc52fa73-bb3a-49ea-bb36-a0191f934e11	2025-04-15	\N	\N	\N	239.040000	\N	GENERATED	2025-11-04 12:45:12.366219+01
337f3b97-a4c2-498c-a080-4ed626c246dd	cc52fa73-bb3a-49ea-bb36-a0191f934e11	2025-04-16	\N	\N	\N	236.570000	\N	GENERATED	2025-11-04 12:45:12.366858+01
8634c3ce-8940-4697-935b-5c9e6436e08a	cc52fa73-bb3a-49ea-bb36-a0191f934e11	2025-04-17	\N	\N	\N	238.340000	\N	GENERATED	2025-11-04 12:45:12.367479+01
cc8cc92c-c0e9-4001-99f8-48e4e5fa633d	cc52fa73-bb3a-49ea-bb36-a0191f934e11	2025-04-18	\N	\N	\N	238.490000	\N	GENERATED	2025-11-04 12:45:12.368089+01
bd5e0f05-dbcc-4725-9915-e8c48eecdfe5	cc52fa73-bb3a-49ea-bb36-a0191f934e11	2025-04-19	\N	\N	\N	236.320000	\N	GENERATED	2025-11-04 12:45:12.368722+01
5f8d923d-51dc-4f87-b1cf-504cf3d09782	cc52fa73-bb3a-49ea-bb36-a0191f934e11	2025-04-20	\N	\N	\N	240.230000	\N	GENERATED	2025-11-04 12:45:12.369351+01
cb97f3ce-bf84-40ca-8e14-dfeabe5e73fc	cc52fa73-bb3a-49ea-bb36-a0191f934e11	2025-04-21	\N	\N	\N	238.880000	\N	GENERATED	2025-11-04 12:45:12.369967+01
a1c2f534-a042-4fb8-b11d-04a4b5c4e3ae	cc52fa73-bb3a-49ea-bb36-a0191f934e11	2025-04-22	\N	\N	\N	237.320000	\N	GENERATED	2025-11-04 12:45:12.370586+01
8c7c2bd8-541c-4630-bb5f-05f209fe3b86	cc52fa73-bb3a-49ea-bb36-a0191f934e11	2025-04-23	\N	\N	\N	240.440000	\N	GENERATED	2025-11-04 12:45:12.371192+01
6cc7f5fc-94cd-43d4-b9b8-5ee4357e1657	cc52fa73-bb3a-49ea-bb36-a0191f934e11	2025-04-24	\N	\N	\N	237.450000	\N	GENERATED	2025-11-04 12:45:12.371818+01
229dde87-03ea-4829-8ead-cad4971d3b74	cc52fa73-bb3a-49ea-bb36-a0191f934e11	2025-04-25	\N	\N	\N	237.480000	\N	GENERATED	2025-11-04 12:45:12.372441+01
8d7392cd-cf06-4a7f-ac7f-5d3e4bc5c05d	cc52fa73-bb3a-49ea-bb36-a0191f934e11	2025-04-26	\N	\N	\N	238.150000	\N	GENERATED	2025-11-04 12:45:12.37305+01
08e9c537-d37d-4fd3-bae7-45e19e2c357d	cc52fa73-bb3a-49ea-bb36-a0191f934e11	2025-04-27	\N	\N	\N	238.770000	\N	GENERATED	2025-11-04 12:45:12.373702+01
56080dd6-1eef-416b-9ca6-0d2a56531911	cc52fa73-bb3a-49ea-bb36-a0191f934e11	2025-04-28	\N	\N	\N	238.700000	\N	GENERATED	2025-11-04 12:45:12.374327+01
53921082-b32e-4a9b-b1ba-9042ac122319	cc52fa73-bb3a-49ea-bb36-a0191f934e11	2025-04-29	\N	\N	\N	240.940000	\N	GENERATED	2025-11-04 12:45:12.374936+01
c031552c-b22c-4795-aa0b-b7704cfd6c52	cc52fa73-bb3a-49ea-bb36-a0191f934e11	2025-04-30	\N	\N	\N	239.370000	\N	GENERATED	2025-11-04 12:45:12.37555+01
e79768a7-fc03-407a-bd72-039537f43235	cc52fa73-bb3a-49ea-bb36-a0191f934e11	2025-05-01	\N	\N	\N	239.300000	\N	GENERATED	2025-11-04 12:45:12.376262+01
362a769e-ccc6-42a6-aa2a-bce5e6e1bdcd	cc52fa73-bb3a-49ea-bb36-a0191f934e11	2025-05-02	\N	\N	\N	240.400000	\N	GENERATED	2025-11-04 12:45:12.376907+01
bf9b6be3-955f-43a8-8691-bb6e1661bbc9	cc52fa73-bb3a-49ea-bb36-a0191f934e11	2025-05-03	\N	\N	\N	239.840000	\N	GENERATED	2025-11-04 12:45:12.377559+01
022d7aca-c8ad-4974-a2b9-b23ff4f6c067	cc52fa73-bb3a-49ea-bb36-a0191f934e11	2025-05-04	\N	\N	\N	239.810000	\N	GENERATED	2025-11-04 12:45:12.378168+01
e3648317-cb4b-4a1c-9623-52f7d14e474b	cc52fa73-bb3a-49ea-bb36-a0191f934e11	2025-05-05	\N	\N	\N	241.460000	\N	GENERATED	2025-11-04 12:45:12.379004+01
0205f167-5c21-489c-807a-858fb46a83d8	cc52fa73-bb3a-49ea-bb36-a0191f934e11	2025-05-06	\N	\N	\N	238.290000	\N	GENERATED	2025-11-04 12:45:12.379672+01
087e30cf-93e0-44d9-9bf5-378cf09d7b08	cc52fa73-bb3a-49ea-bb36-a0191f934e11	2025-05-07	\N	\N	\N	237.030000	\N	GENERATED	2025-11-04 12:45:12.380293+01
14479e14-3d2a-4120-abe6-f6e271f5acb0	cc52fa73-bb3a-49ea-bb36-a0191f934e11	2025-05-08	\N	\N	\N	238.630000	\N	GENERATED	2025-11-04 12:45:12.380911+01
6270d780-1870-4f23-acfb-de03b265180f	cc52fa73-bb3a-49ea-bb36-a0191f934e11	2025-05-09	\N	\N	\N	238.220000	\N	GENERATED	2025-11-04 12:45:12.381555+01
8ef9b9e6-19ba-4445-bdfe-2299e47ea4e9	cc52fa73-bb3a-49ea-bb36-a0191f934e11	2025-05-10	\N	\N	\N	240.880000	\N	GENERATED	2025-11-04 12:45:12.382168+01
c64db3f4-863c-47cb-b1ba-49338c6c159a	cc52fa73-bb3a-49ea-bb36-a0191f934e11	2025-05-11	\N	\N	\N	241.660000	\N	GENERATED	2025-11-04 12:45:12.382798+01
5878100f-12fc-4f17-9437-d074235678d7	cc52fa73-bb3a-49ea-bb36-a0191f934e11	2025-05-12	\N	\N	\N	241.730000	\N	GENERATED	2025-11-04 12:45:12.383438+01
dda5125c-5060-4d17-bb17-99d9d02c747b	cc52fa73-bb3a-49ea-bb36-a0191f934e11	2025-05-13	\N	\N	\N	239.460000	\N	GENERATED	2025-11-04 12:45:12.384048+01
61919edc-4b72-4f32-8846-6df782523f5b	cc52fa73-bb3a-49ea-bb36-a0191f934e11	2025-05-14	\N	\N	\N	240.690000	\N	GENERATED	2025-11-04 12:45:12.384684+01
90442091-c762-4341-9dbd-a8a4e8359e28	cc52fa73-bb3a-49ea-bb36-a0191f934e11	2025-05-15	\N	\N	\N	240.290000	\N	GENERATED	2025-11-04 12:45:12.385303+01
9e6a03a6-605a-4429-8b79-00a17e49ce3a	cc52fa73-bb3a-49ea-bb36-a0191f934e11	2025-05-16	\N	\N	\N	240.420000	\N	GENERATED	2025-11-04 12:45:12.385918+01
df0d9e75-a0e5-48d6-9fbc-cce74a1d4588	cc52fa73-bb3a-49ea-bb36-a0191f934e11	2025-05-17	\N	\N	\N	239.630000	\N	GENERATED	2025-11-04 12:45:12.386556+01
8d7e76ae-09f8-46c3-8259-81c7a1cfd7e5	cc52fa73-bb3a-49ea-bb36-a0191f934e11	2025-05-18	\N	\N	\N	241.000000	\N	GENERATED	2025-11-04 12:45:12.387168+01
f52e52cf-a0ad-45ae-9b21-c96d55014f21	cc52fa73-bb3a-49ea-bb36-a0191f934e11	2025-05-19	\N	\N	\N	237.970000	\N	GENERATED	2025-11-04 12:45:12.387781+01
19b1369b-ad6f-49cc-a94e-61b819c7d802	cc52fa73-bb3a-49ea-bb36-a0191f934e11	2025-05-20	\N	\N	\N	241.280000	\N	GENERATED	2025-11-04 12:45:12.388403+01
65aca80f-5612-44a6-9228-9fb732836fb4	cc52fa73-bb3a-49ea-bb36-a0191f934e11	2025-05-21	\N	\N	\N	240.350000	\N	GENERATED	2025-11-04 12:45:12.389019+01
2af5e03d-9af6-4a82-a31b-78f6d81938c7	cc52fa73-bb3a-49ea-bb36-a0191f934e11	2025-05-22	\N	\N	\N	239.140000	\N	GENERATED	2025-11-04 12:45:12.389649+01
14700f26-de88-4bcd-9782-55dbc8a843e3	cc52fa73-bb3a-49ea-bb36-a0191f934e11	2025-05-23	\N	\N	\N	240.910000	\N	GENERATED	2025-11-04 12:45:12.390258+01
2492fc59-33dd-4cf5-bfe0-c70d84aa71f6	cc52fa73-bb3a-49ea-bb36-a0191f934e11	2025-05-24	\N	\N	\N	237.930000	\N	GENERATED	2025-11-04 12:45:12.390871+01
3873235c-6257-432d-9fb6-cac04fb51e73	cc52fa73-bb3a-49ea-bb36-a0191f934e11	2025-05-25	\N	\N	\N	240.310000	\N	GENERATED	2025-11-04 12:45:12.391508+01
5a0b3b1a-fd2b-4a07-a93c-19d7248a9253	cc52fa73-bb3a-49ea-bb36-a0191f934e11	2025-05-26	\N	\N	\N	239.910000	\N	GENERATED	2025-11-04 12:45:12.392126+01
6eb62473-243e-4213-82ab-d10b26e2d678	cc52fa73-bb3a-49ea-bb36-a0191f934e11	2025-05-27	\N	\N	\N	242.580000	\N	GENERATED	2025-11-04 12:45:12.39287+01
dae92193-7838-4af4-a561-51e1acfc7e93	cc52fa73-bb3a-49ea-bb36-a0191f934e11	2025-05-28	\N	\N	\N	241.460000	\N	GENERATED	2025-11-04 12:45:12.39352+01
91b2727f-6ad4-40ef-a076-df632a6569ef	cc52fa73-bb3a-49ea-bb36-a0191f934e11	2025-05-29	\N	\N	\N	241.690000	\N	GENERATED	2025-11-04 12:45:12.394133+01
cb997e28-053a-4f22-aac8-0e233a3cc436	cc52fa73-bb3a-49ea-bb36-a0191f934e11	2025-05-30	\N	\N	\N	242.350000	\N	GENERATED	2025-11-04 12:45:12.394996+01
8561eab6-a8c2-41a6-92ed-87bb81f58c47	cc52fa73-bb3a-49ea-bb36-a0191f934e11	2025-05-31	\N	\N	\N	240.620000	\N	GENERATED	2025-11-04 12:45:12.395662+01
5f4eb4f5-7b75-4b64-b6f9-3673299e502d	cc52fa73-bb3a-49ea-bb36-a0191f934e11	2025-06-01	\N	\N	\N	241.310000	\N	GENERATED	2025-11-04 12:45:12.396393+01
1b670955-1b66-4325-82ff-be8eb7a05bb0	cc52fa73-bb3a-49ea-bb36-a0191f934e11	2025-06-02	\N	\N	\N	238.870000	\N	GENERATED	2025-11-04 12:45:12.397482+01
ace0d3a4-5d91-432f-871d-e435abf20ff1	cc52fa73-bb3a-49ea-bb36-a0191f934e11	2025-06-03	\N	\N	\N	242.680000	\N	GENERATED	2025-11-04 12:45:12.398175+01
37abb2b8-ca3d-41ab-807f-536510b4db84	cc52fa73-bb3a-49ea-bb36-a0191f934e11	2025-06-04	\N	\N	\N	242.940000	\N	GENERATED	2025-11-04 12:45:12.398831+01
29575ba7-9b4e-4628-a81d-9a7eaeb5e216	cc52fa73-bb3a-49ea-bb36-a0191f934e11	2025-06-05	\N	\N	\N	242.330000	\N	GENERATED	2025-11-04 12:45:12.399475+01
db5f34a1-35d7-42d4-96bf-034b4d6bf8a1	cc52fa73-bb3a-49ea-bb36-a0191f934e11	2025-06-06	\N	\N	\N	240.130000	\N	GENERATED	2025-11-04 12:45:12.400094+01
8bc341a4-e130-4349-9c72-0029d40a9ac9	cc52fa73-bb3a-49ea-bb36-a0191f934e11	2025-06-07	\N	\N	\N	240.780000	\N	GENERATED	2025-11-04 12:45:12.40071+01
e4a37b21-4790-41dd-92d6-3a1600ba958e	cc52fa73-bb3a-49ea-bb36-a0191f934e11	2025-06-08	\N	\N	\N	238.750000	\N	GENERATED	2025-11-04 12:45:12.401322+01
e5325bf9-9ddd-481e-8244-0eaf558bac66	cc52fa73-bb3a-49ea-bb36-a0191f934e11	2025-06-09	\N	\N	\N	240.130000	\N	GENERATED	2025-11-04 12:45:12.40193+01
c97681fd-c3a1-4090-8a8f-7ca7fbc25441	cc52fa73-bb3a-49ea-bb36-a0191f934e11	2025-06-10	\N	\N	\N	242.900000	\N	GENERATED	2025-11-04 12:45:12.402546+01
568bb827-3b1f-4f35-b553-e8122e283e0e	cc52fa73-bb3a-49ea-bb36-a0191f934e11	2025-06-11	\N	\N	\N	239.290000	\N	GENERATED	2025-11-04 12:45:12.403159+01
57377e7d-26fe-4d58-bb5e-72a908f076c8	cc52fa73-bb3a-49ea-bb36-a0191f934e11	2025-06-12	\N	\N	\N	242.170000	\N	GENERATED	2025-11-04 12:45:12.40378+01
6e1ba57d-006f-4d6e-9ba3-a33c73fdbcc1	cc52fa73-bb3a-49ea-bb36-a0191f934e11	2025-06-13	\N	\N	\N	241.870000	\N	GENERATED	2025-11-04 12:45:12.404411+01
b4a23cf4-5389-4b08-be75-1692c22acb46	cc52fa73-bb3a-49ea-bb36-a0191f934e11	2025-06-14	\N	\N	\N	242.220000	\N	GENERATED	2025-11-04 12:45:12.405019+01
7650163d-0842-4f24-ab86-5f7e9253bf35	cc52fa73-bb3a-49ea-bb36-a0191f934e11	2025-06-15	\N	\N	\N	242.480000	\N	GENERATED	2025-11-04 12:45:12.40563+01
407542ae-24de-4143-b4a1-01ed8f918b6f	cc52fa73-bb3a-49ea-bb36-a0191f934e11	2025-06-16	\N	\N	\N	239.250000	\N	GENERATED	2025-11-04 12:45:12.406246+01
4f2cecf5-3163-4243-877d-3a1d3fae2d67	cc52fa73-bb3a-49ea-bb36-a0191f934e11	2025-06-17	\N	\N	\N	239.590000	\N	GENERATED	2025-11-04 12:45:12.407052+01
bc0ef727-b267-4b0a-87ac-ee57aaacfdf7	cc52fa73-bb3a-49ea-bb36-a0191f934e11	2025-06-18	\N	\N	\N	239.310000	\N	GENERATED	2025-11-04 12:45:12.407707+01
4c74a1e7-a17e-42d5-b009-8d89367f8785	cc52fa73-bb3a-49ea-bb36-a0191f934e11	2025-06-19	\N	\N	\N	241.840000	\N	GENERATED	2025-11-04 12:45:12.408323+01
b334e133-8b66-4123-96f3-7c1e6980ce8b	cc52fa73-bb3a-49ea-bb36-a0191f934e11	2025-06-20	\N	\N	\N	243.220000	\N	GENERATED	2025-11-04 12:45:12.408937+01
4d6b4c09-81c8-4848-8953-6f6c6cb8c44b	cc52fa73-bb3a-49ea-bb36-a0191f934e11	2025-06-21	\N	\N	\N	241.120000	\N	GENERATED	2025-11-04 12:45:12.409593+01
a9db4d29-ff3e-4c5d-b2b2-738832cb0ca3	cc52fa73-bb3a-49ea-bb36-a0191f934e11	2025-06-22	\N	\N	\N	240.580000	\N	GENERATED	2025-11-04 12:45:12.410253+01
8ee57904-7c15-4f33-b971-e56061a34ea7	cc52fa73-bb3a-49ea-bb36-a0191f934e11	2025-06-23	\N	\N	\N	241.100000	\N	GENERATED	2025-11-04 12:45:12.410958+01
4c723309-7839-41b5-a955-f3ddd25981da	cc52fa73-bb3a-49ea-bb36-a0191f934e11	2025-06-24	\N	\N	\N	243.450000	\N	GENERATED	2025-11-04 12:45:12.411617+01
ec6bc94b-2d9e-424a-a01a-b6d10c8e8286	cc52fa73-bb3a-49ea-bb36-a0191f934e11	2025-06-25	\N	\N	\N	241.230000	\N	GENERATED	2025-11-04 12:45:12.412237+01
1aa5c6cd-f92f-47f8-90a5-784c52cc371d	cc52fa73-bb3a-49ea-bb36-a0191f934e11	2025-06-26	\N	\N	\N	242.790000	\N	GENERATED	2025-11-04 12:45:12.412857+01
19a879db-1433-4f56-9278-dc2e4afd80e8	cc52fa73-bb3a-49ea-bb36-a0191f934e11	2025-06-27	\N	\N	\N	242.810000	\N	GENERATED	2025-11-04 12:45:12.413481+01
acd0565f-d74a-4a15-ad81-7670fed1fb29	cc52fa73-bb3a-49ea-bb36-a0191f934e11	2025-06-28	\N	\N	\N	243.260000	\N	GENERATED	2025-11-04 12:45:12.414097+01
82d23c1c-fd95-43d3-9332-d59626ab299a	cc52fa73-bb3a-49ea-bb36-a0191f934e11	2025-06-29	\N	\N	\N	241.250000	\N	GENERATED	2025-11-04 12:45:12.414718+01
acd24fdd-74bb-4649-bd6f-994e2c795a9f	cc52fa73-bb3a-49ea-bb36-a0191f934e11	2025-06-30	\N	\N	\N	240.590000	\N	GENERATED	2025-11-04 12:45:12.415332+01
dcbcd87d-1520-418b-a373-ecce23b67cf8	cc52fa73-bb3a-49ea-bb36-a0191f934e11	2025-07-01	\N	\N	\N	242.280000	\N	GENERATED	2025-11-04 12:45:12.416012+01
0ebb0474-fa20-4a79-8aaf-8fb8f821f117	cc52fa73-bb3a-49ea-bb36-a0191f934e11	2025-07-02	\N	\N	\N	240.030000	\N	GENERATED	2025-11-04 12:45:12.416643+01
e0b12592-2175-4ef1-a5b6-78b377c8adf9	cc52fa73-bb3a-49ea-bb36-a0191f934e11	2025-07-03	\N	\N	\N	241.500000	\N	GENERATED	2025-11-04 12:45:12.417256+01
4889550d-df29-428b-8269-5571d94b35b6	cc52fa73-bb3a-49ea-bb36-a0191f934e11	2025-07-04	\N	\N	\N	244.220000	\N	GENERATED	2025-11-04 12:45:12.417872+01
61ab97ce-67a2-43ee-b711-1daece09f0cd	cc52fa73-bb3a-49ea-bb36-a0191f934e11	2025-07-05	\N	\N	\N	243.130000	\N	GENERATED	2025-11-04 12:45:12.418505+01
c4a925a7-669f-4390-a7de-56257035c471	cc52fa73-bb3a-49ea-bb36-a0191f934e11	2025-07-06	\N	\N	\N	241.590000	\N	GENERATED	2025-11-04 12:45:12.419115+01
b568c7db-ba81-4758-9e58-076a1f2187a1	cc52fa73-bb3a-49ea-bb36-a0191f934e11	2025-07-07	\N	\N	\N	242.110000	\N	GENERATED	2025-11-04 12:45:12.419746+01
6249f9f8-3dbf-4115-b70f-ea9992bbeb9c	cc52fa73-bb3a-49ea-bb36-a0191f934e11	2025-07-08	\N	\N	\N	240.660000	\N	GENERATED	2025-11-04 12:45:12.420369+01
a8b5d903-a491-4df2-b004-8367830b01be	cc52fa73-bb3a-49ea-bb36-a0191f934e11	2025-07-09	\N	\N	\N	242.870000	\N	GENERATED	2025-11-04 12:45:12.420979+01
d5100503-3503-43f3-a5e3-ff18ecf9008c	cc52fa73-bb3a-49ea-bb36-a0191f934e11	2025-07-10	\N	\N	\N	240.300000	\N	GENERATED	2025-11-04 12:45:12.421619+01
3c042eb2-cb59-46e9-ad6b-aab45924afed	cc52fa73-bb3a-49ea-bb36-a0191f934e11	2025-07-11	\N	\N	\N	243.330000	\N	GENERATED	2025-11-04 12:45:12.422236+01
ad37a4f7-988d-4f65-8b83-c13d893c40c5	cc52fa73-bb3a-49ea-bb36-a0191f934e11	2025-07-12	\N	\N	\N	242.210000	\N	GENERATED	2025-11-04 12:45:12.422948+01
35813e58-4fdb-4cf2-b7c2-0ed6d165adf6	cc52fa73-bb3a-49ea-bb36-a0191f934e11	2025-07-13	\N	\N	\N	242.110000	\N	GENERATED	2025-11-04 12:45:12.423575+01
991cf618-41f1-406b-8e68-0cffa644120c	cc52fa73-bb3a-49ea-bb36-a0191f934e11	2025-07-14	\N	\N	\N	242.600000	\N	GENERATED	2025-11-04 12:45:12.424188+01
00a58c0d-c1ba-4353-8d35-689da52f6376	cc52fa73-bb3a-49ea-bb36-a0191f934e11	2025-07-15	\N	\N	\N	243.520000	\N	GENERATED	2025-11-04 12:45:12.424807+01
7d998349-c0e1-4f51-a5a9-cc77704a2834	cc52fa73-bb3a-49ea-bb36-a0191f934e11	2025-07-16	\N	\N	\N	244.490000	\N	GENERATED	2025-11-04 12:45:12.425503+01
21db4feb-5873-495f-9df9-5f4342f133b5	cc52fa73-bb3a-49ea-bb36-a0191f934e11	2025-07-17	\N	\N	\N	243.240000	\N	GENERATED	2025-11-04 12:45:12.426545+01
c7988592-4e12-4e9f-8640-39b00e9b4eb8	cc52fa73-bb3a-49ea-bb36-a0191f934e11	2025-07-18	\N	\N	\N	240.710000	\N	GENERATED	2025-11-04 12:45:12.427179+01
84d6977b-d428-4b24-97ac-9bc188427e0e	cc52fa73-bb3a-49ea-bb36-a0191f934e11	2025-07-19	\N	\N	\N	241.430000	\N	GENERATED	2025-11-04 12:45:12.427814+01
6d05ca9a-3b21-48d2-801a-e8f56df5f91a	cc52fa73-bb3a-49ea-bb36-a0191f934e11	2025-07-20	\N	\N	\N	242.990000	\N	GENERATED	2025-11-04 12:45:12.42843+01
0813f734-7e11-4f89-acee-b952b8f43cb7	cc52fa73-bb3a-49ea-bb36-a0191f934e11	2025-07-21	\N	\N	\N	241.380000	\N	GENERATED	2025-11-04 12:45:12.42906+01
1554d978-137b-44a8-914c-c74b8042323e	cc52fa73-bb3a-49ea-bb36-a0191f934e11	2025-07-22	\N	\N	\N	244.570000	\N	GENERATED	2025-11-04 12:45:12.429686+01
6bef6435-8e28-45fd-958c-cbdcb02d8d05	cc52fa73-bb3a-49ea-bb36-a0191f934e11	2025-07-23	\N	\N	\N	241.460000	\N	GENERATED	2025-11-04 12:45:12.430296+01
2b0ac0dc-3357-4c32-86e7-1b5df5420f9b	cc52fa73-bb3a-49ea-bb36-a0191f934e11	2025-07-24	\N	\N	\N	245.350000	\N	GENERATED	2025-11-04 12:45:12.430914+01
2e0078b1-4ad9-4416-8b07-3ea5d35f8b9e	cc52fa73-bb3a-49ea-bb36-a0191f934e11	2025-07-25	\N	\N	\N	242.670000	\N	GENERATED	2025-11-04 12:45:12.431522+01
3c3c77e0-290e-42dc-bf42-62b566dad93c	cc52fa73-bb3a-49ea-bb36-a0191f934e11	2025-07-26	\N	\N	\N	243.860000	\N	GENERATED	2025-11-04 12:45:12.432143+01
9ee3eefd-ac0e-4dc3-9ddf-4c21cb538243	cc52fa73-bb3a-49ea-bb36-a0191f934e11	2025-07-27	\N	\N	\N	241.910000	\N	GENERATED	2025-11-04 12:45:12.432753+01
bfedf3a8-4bdf-4ec4-8508-1e8fe484150b	cc52fa73-bb3a-49ea-bb36-a0191f934e11	2025-07-28	\N	\N	\N	243.200000	\N	GENERATED	2025-11-04 12:45:12.433359+01
e2c72726-2b7c-4769-9584-accf179870f5	cc52fa73-bb3a-49ea-bb36-a0191f934e11	2025-07-29	\N	\N	\N	244.020000	\N	GENERATED	2025-11-04 12:45:12.433994+01
540c398c-3eb0-42e3-899a-5cc8f41b66dc	cc52fa73-bb3a-49ea-bb36-a0191f934e11	2025-07-30	\N	\N	\N	243.250000	\N	GENERATED	2025-11-04 12:45:12.434603+01
6651bf28-a927-44de-acce-5378e5eb7ddc	cc52fa73-bb3a-49ea-bb36-a0191f934e11	2025-07-31	\N	\N	\N	243.110000	\N	GENERATED	2025-11-04 12:45:12.435236+01
d79f183d-04ab-43b6-adc0-2e20e45f9d7e	cc52fa73-bb3a-49ea-bb36-a0191f934e11	2025-08-01	\N	\N	\N	244.710000	\N	GENERATED	2025-11-04 12:45:12.43589+01
15d9dd02-348e-4f09-b109-c83c0b446da9	cc52fa73-bb3a-49ea-bb36-a0191f934e11	2025-08-02	\N	\N	\N	245.480000	\N	GENERATED	2025-11-04 12:45:12.436534+01
b18bc020-e2b5-4d1a-8fc5-f339499f4c5a	cc52fa73-bb3a-49ea-bb36-a0191f934e11	2025-08-03	\N	\N	\N	244.030000	\N	GENERATED	2025-11-04 12:45:12.437146+01
dcd6b55c-cc5f-4646-9eaf-03578f735030	cc52fa73-bb3a-49ea-bb36-a0191f934e11	2025-08-04	\N	\N	\N	242.720000	\N	GENERATED	2025-11-04 12:45:12.437799+01
06d330f7-8a09-4296-8906-e86589c9cb15	cc52fa73-bb3a-49ea-bb36-a0191f934e11	2025-08-05	\N	\N	\N	242.070000	\N	GENERATED	2025-11-04 12:45:12.438413+01
c7721787-ae61-4982-becc-12d0f0501c10	cc52fa73-bb3a-49ea-bb36-a0191f934e11	2025-08-06	\N	\N	\N	243.920000	\N	GENERATED	2025-11-04 12:45:12.439036+01
6d17aa4f-77c0-481e-9082-d9ee035c546e	cc52fa73-bb3a-49ea-bb36-a0191f934e11	2025-08-07	\N	\N	\N	243.030000	\N	GENERATED	2025-11-04 12:45:12.439655+01
799bb14e-65c6-4fbd-af0d-db96e16d364a	cc52fa73-bb3a-49ea-bb36-a0191f934e11	2025-08-08	\N	\N	\N	244.090000	\N	GENERATED	2025-11-04 12:45:12.440267+01
c619cbdf-d7d7-41e7-a247-8095646c6984	cc52fa73-bb3a-49ea-bb36-a0191f934e11	2025-08-09	\N	\N	\N	244.020000	\N	GENERATED	2025-11-04 12:45:12.440882+01
214ff7b2-8b0c-4629-aca4-c2eca47ed5da	cc52fa73-bb3a-49ea-bb36-a0191f934e11	2025-08-10	\N	\N	\N	243.260000	\N	GENERATED	2025-11-04 12:45:12.44169+01
fa5f4eed-1981-4662-b611-51847de3fbdc	cc52fa73-bb3a-49ea-bb36-a0191f934e11	2025-08-11	\N	\N	\N	244.420000	\N	GENERATED	2025-11-04 12:45:12.442328+01
5404ea46-07a5-4b84-ae69-6ce0d8d1d792	cc52fa73-bb3a-49ea-bb36-a0191f934e11	2025-08-12	\N	\N	\N	242.880000	\N	GENERATED	2025-11-04 12:45:12.442945+01
53da26f5-e0bc-449f-a4e2-671c3a586f5a	cc52fa73-bb3a-49ea-bb36-a0191f934e11	2025-08-13	\N	\N	\N	245.240000	\N	GENERATED	2025-11-04 12:45:12.443576+01
dfeb5a43-90b1-4357-9869-a658e4b25dc7	cc52fa73-bb3a-49ea-bb36-a0191f934e11	2025-08-14	\N	\N	\N	243.050000	\N	GENERATED	2025-11-04 12:45:12.444199+01
42243268-8d1e-4074-9e5f-51a605521d24	cc52fa73-bb3a-49ea-bb36-a0191f934e11	2025-08-15	\N	\N	\N	244.510000	\N	GENERATED	2025-11-04 12:45:12.444819+01
6465d864-d42f-41fe-bbee-49273656fdd0	cc52fa73-bb3a-49ea-bb36-a0191f934e11	2025-08-16	\N	\N	\N	242.380000	\N	GENERATED	2025-11-04 12:45:12.445448+01
b4c4c479-75db-4baa-93ee-4f338627b261	cc52fa73-bb3a-49ea-bb36-a0191f934e11	2025-08-17	\N	\N	\N	244.530000	\N	GENERATED	2025-11-04 12:45:12.446096+01
649639c0-871d-4982-b32e-aa6d49b496f7	cc52fa73-bb3a-49ea-bb36-a0191f934e11	2025-08-18	\N	\N	\N	246.110000	\N	GENERATED	2025-11-04 12:45:12.446722+01
bbc6f164-5331-44ba-a466-a8bcd931e62f	cc52fa73-bb3a-49ea-bb36-a0191f934e11	2025-08-19	\N	\N	\N	246.730000	\N	GENERATED	2025-11-04 12:45:12.447343+01
4db8343c-e3c6-4edd-9e30-018e5689b189	cc52fa73-bb3a-49ea-bb36-a0191f934e11	2025-08-20	\N	\N	\N	245.500000	\N	GENERATED	2025-11-04 12:45:12.44797+01
1cd162fb-4ba5-4924-9cf9-057577175fb5	cc52fa73-bb3a-49ea-bb36-a0191f934e11	2025-08-21	\N	\N	\N	246.350000	\N	GENERATED	2025-11-04 12:45:12.448597+01
c0f674f4-97a5-4085-b875-f0673e91ae6c	cc52fa73-bb3a-49ea-bb36-a0191f934e11	2025-08-22	\N	\N	\N	245.130000	\N	GENERATED	2025-11-04 12:45:12.449228+01
a7737304-d69c-4b4e-b777-a0ab4926eec7	cc52fa73-bb3a-49ea-bb36-a0191f934e11	2025-08-23	\N	\N	\N	242.720000	\N	GENERATED	2025-11-04 12:45:12.449842+01
3dd4d5dc-eaad-480b-ab7e-2e4bef87178d	cc52fa73-bb3a-49ea-bb36-a0191f934e11	2025-08-24	\N	\N	\N	244.340000	\N	GENERATED	2025-11-04 12:45:12.450464+01
70a1dd0c-b2bd-455a-88cf-e78f60617d7a	cc52fa73-bb3a-49ea-bb36-a0191f934e11	2025-08-25	\N	\N	\N	244.130000	\N	GENERATED	2025-11-04 12:45:12.45109+01
e0aacafb-974b-4d95-bbae-23ea6d5b55c9	cc52fa73-bb3a-49ea-bb36-a0191f934e11	2025-08-26	\N	\N	\N	245.230000	\N	GENERATED	2025-11-04 12:45:12.45171+01
95ea41bf-a15c-4efb-9369-d2fe54d1ea46	cc52fa73-bb3a-49ea-bb36-a0191f934e11	2025-08-27	\N	\N	\N	245.380000	\N	GENERATED	2025-11-04 12:45:12.452359+01
bf161740-06eb-4068-8464-470001711743	cc52fa73-bb3a-49ea-bb36-a0191f934e11	2025-08-28	\N	\N	\N	246.180000	\N	GENERATED	2025-11-04 12:45:12.452977+01
5ba1ec3e-a482-454c-8eba-376798e5863a	cc52fa73-bb3a-49ea-bb36-a0191f934e11	2025-08-29	\N	\N	\N	243.640000	\N	GENERATED	2025-11-04 12:45:12.453614+01
69444855-cf92-4dc6-8efc-46d43c517cbf	cc52fa73-bb3a-49ea-bb36-a0191f934e11	2025-08-30	\N	\N	\N	245.870000	\N	GENERATED	2025-11-04 12:45:12.454232+01
285c368f-9b8d-447a-af98-4be02d8421be	cc52fa73-bb3a-49ea-bb36-a0191f934e11	2025-08-31	\N	\N	\N	244.180000	\N	GENERATED	2025-11-04 12:45:12.454845+01
5473b131-14a2-4545-8792-ea4a32b687b5	cc52fa73-bb3a-49ea-bb36-a0191f934e11	2025-09-01	\N	\N	\N	245.800000	\N	GENERATED	2025-11-04 12:45:12.455469+01
6cb7a6f0-fec6-40c0-b98a-2c1b92324d9d	cc52fa73-bb3a-49ea-bb36-a0191f934e11	2025-09-02	\N	\N	\N	243.310000	\N	GENERATED	2025-11-04 12:45:12.456266+01
8ca65e6f-d593-4f33-9c1e-fa00004801cd	cc52fa73-bb3a-49ea-bb36-a0191f934e11	2025-09-03	\N	\N	\N	243.640000	\N	GENERATED	2025-11-04 12:45:12.457232+01
e892007c-5121-49eb-bfa5-932dd3148b7c	cc52fa73-bb3a-49ea-bb36-a0191f934e11	2025-09-04	\N	\N	\N	243.850000	\N	GENERATED	2025-11-04 12:45:12.457861+01
632da331-61cb-4b07-bbab-10793aa5bff4	cc52fa73-bb3a-49ea-bb36-a0191f934e11	2025-09-05	\N	\N	\N	244.880000	\N	GENERATED	2025-11-04 12:45:12.458569+01
62a932ef-758b-4edf-9102-7efbd5f8b7c5	cc52fa73-bb3a-49ea-bb36-a0191f934e11	2025-09-06	\N	\N	\N	243.190000	\N	GENERATED	2025-11-04 12:45:12.459214+01
1d780ece-0bd6-4323-be48-baaeb61299b1	cc52fa73-bb3a-49ea-bb36-a0191f934e11	2025-09-07	\N	\N	\N	247.460000	\N	GENERATED	2025-11-04 12:45:12.459835+01
006065a2-92f8-433e-93a4-e126e6b05d4f	cc52fa73-bb3a-49ea-bb36-a0191f934e11	2025-09-08	\N	\N	\N	246.710000	\N	GENERATED	2025-11-04 12:45:12.460456+01
f8eef888-bb67-4361-844e-75c862da1304	cc52fa73-bb3a-49ea-bb36-a0191f934e11	2025-09-09	\N	\N	\N	247.020000	\N	GENERATED	2025-11-04 12:45:12.461092+01
3279e7c4-b8c3-40db-a9d0-c9970ae54818	cc52fa73-bb3a-49ea-bb36-a0191f934e11	2025-09-10	\N	\N	\N	245.720000	\N	GENERATED	2025-11-04 12:45:12.461946+01
1f14c826-0375-4b45-a0a7-4394d89c368a	cc52fa73-bb3a-49ea-bb36-a0191f934e11	2025-09-11	\N	\N	\N	244.080000	\N	GENERATED	2025-11-04 12:45:12.462598+01
cf7b7d3b-609e-4953-a322-74091413870c	cc52fa73-bb3a-49ea-bb36-a0191f934e11	2025-09-12	\N	\N	\N	244.740000	\N	GENERATED	2025-11-04 12:45:12.463224+01
fc78c116-b8fc-4422-af7c-76100bbee6a7	cc52fa73-bb3a-49ea-bb36-a0191f934e11	2025-09-13	\N	\N	\N	247.340000	\N	GENERATED	2025-11-04 12:45:12.46384+01
10503646-dd2c-4250-975d-98cc1e6c06ca	cc52fa73-bb3a-49ea-bb36-a0191f934e11	2025-09-14	\N	\N	\N	246.100000	\N	GENERATED	2025-11-04 12:45:12.464478+01
01bf3541-0979-4695-847d-c1d9013c66cd	cc52fa73-bb3a-49ea-bb36-a0191f934e11	2025-09-15	\N	\N	\N	247.940000	\N	GENERATED	2025-11-04 12:45:12.465096+01
a9757076-7687-4284-afbe-ff1d2ac2420d	cc52fa73-bb3a-49ea-bb36-a0191f934e11	2025-09-16	\N	\N	\N	246.240000	\N	GENERATED	2025-11-04 12:45:12.465718+01
9d475bb1-e8cc-40c6-9c35-4c859f7670e0	cc52fa73-bb3a-49ea-bb36-a0191f934e11	2025-09-17	\N	\N	\N	245.980000	\N	GENERATED	2025-11-04 12:45:12.466469+01
441cbd04-50e5-4359-8fff-58eef59075e7	cc52fa73-bb3a-49ea-bb36-a0191f934e11	2025-09-18	\N	\N	\N	247.480000	\N	GENERATED	2025-11-04 12:45:12.467086+01
ec1bab4b-f90f-4b79-8e13-6f33ea568919	cc52fa73-bb3a-49ea-bb36-a0191f934e11	2025-09-19	\N	\N	\N	245.190000	\N	GENERATED	2025-11-04 12:45:12.467753+01
2996758d-67de-4a13-a961-cca03fa7aa21	cc52fa73-bb3a-49ea-bb36-a0191f934e11	2025-09-20	\N	\N	\N	246.500000	\N	GENERATED	2025-11-04 12:45:12.46839+01
14a79d66-84b4-4925-97ef-65c1e8a19208	cc52fa73-bb3a-49ea-bb36-a0191f934e11	2025-09-21	\N	\N	\N	245.360000	\N	GENERATED	2025-11-04 12:45:12.469002+01
dee8d890-5ac9-44a2-b615-b85aa89728df	cc52fa73-bb3a-49ea-bb36-a0191f934e11	2025-09-22	\N	\N	\N	245.310000	\N	GENERATED	2025-11-04 12:45:12.469634+01
873d9a18-476d-41b5-bb3f-64679e3840cf	cc52fa73-bb3a-49ea-bb36-a0191f934e11	2025-09-23	\N	\N	\N	244.170000	\N	GENERATED	2025-11-04 12:45:12.470242+01
2f41639e-7e75-474c-8cf9-5582403b5774	cc52fa73-bb3a-49ea-bb36-a0191f934e11	2025-09-24	\N	\N	\N	244.110000	\N	GENERATED	2025-11-04 12:45:12.470875+01
18156d2d-d94e-4933-99ea-86129eabcb56	cc52fa73-bb3a-49ea-bb36-a0191f934e11	2025-09-25	\N	\N	\N	246.010000	\N	GENERATED	2025-11-04 12:45:12.471712+01
a963c00f-2393-42f5-8f76-0ed6353394a6	cc52fa73-bb3a-49ea-bb36-a0191f934e11	2025-09-26	\N	\N	\N	247.560000	\N	GENERATED	2025-11-04 12:45:12.472729+01
cb011aac-964a-4a70-9be3-0abeec2a806e	cc52fa73-bb3a-49ea-bb36-a0191f934e11	2025-09-27	\N	\N	\N	247.230000	\N	GENERATED	2025-11-04 12:45:12.473427+01
e3ca7b11-dc3b-4cc3-86e2-fb1368d24188	cc52fa73-bb3a-49ea-bb36-a0191f934e11	2025-09-28	\N	\N	\N	246.980000	\N	GENERATED	2025-11-04 12:45:12.474116+01
de1effed-3008-4bad-a391-8abe5440c067	cc52fa73-bb3a-49ea-bb36-a0191f934e11	2025-09-29	\N	\N	\N	247.580000	\N	GENERATED	2025-11-04 12:45:12.474764+01
748740f0-148a-4e31-94ff-124e2c67346c	cc52fa73-bb3a-49ea-bb36-a0191f934e11	2025-09-30	\N	\N	\N	245.920000	\N	GENERATED	2025-11-04 12:45:12.475398+01
58061bf1-43ee-4f44-92c5-75fae1bd2f76	cc52fa73-bb3a-49ea-bb36-a0191f934e11	2025-10-01	\N	\N	\N	247.870000	\N	GENERATED	2025-11-04 12:45:12.476201+01
0715fce7-8b75-47bd-b82f-53e964443f87	cc52fa73-bb3a-49ea-bb36-a0191f934e11	2025-10-02	\N	\N	\N	245.900000	\N	GENERATED	2025-11-04 12:45:12.476851+01
c69a0f31-4bc3-4cb0-9188-95c9938517d7	cc52fa73-bb3a-49ea-bb36-a0191f934e11	2025-10-03	\N	\N	\N	245.460000	\N	GENERATED	2025-11-04 12:45:12.477476+01
044fe75a-c3ee-452e-806d-385eafab5c74	cc52fa73-bb3a-49ea-bb36-a0191f934e11	2025-10-04	\N	\N	\N	247.800000	\N	GENERATED	2025-11-04 12:45:12.47809+01
5cb4090e-f60b-4742-b024-4a94d6cd9d38	cc52fa73-bb3a-49ea-bb36-a0191f934e11	2025-10-05	\N	\N	\N	249.030000	\N	GENERATED	2025-11-04 12:45:12.478715+01
4193fd36-140b-4291-8d63-9f66eed18148	cc52fa73-bb3a-49ea-bb36-a0191f934e11	2025-10-06	\N	\N	\N	248.190000	\N	GENERATED	2025-11-04 12:45:12.479342+01
c2447711-9192-47ea-9de8-af8be018e938	cc52fa73-bb3a-49ea-bb36-a0191f934e11	2025-10-07	\N	\N	\N	247.160000	\N	GENERATED	2025-11-04 12:45:12.479989+01
791e559d-92b3-4bcd-a0b7-06528896a16c	cc52fa73-bb3a-49ea-bb36-a0191f934e11	2025-10-08	\N	\N	\N	246.970000	\N	GENERATED	2025-11-04 12:45:12.48062+01
92211409-84c6-46cd-bc8b-25ce62e2fa1f	cc52fa73-bb3a-49ea-bb36-a0191f934e11	2025-10-09	\N	\N	\N	245.860000	\N	GENERATED	2025-11-04 12:45:12.481239+01
81983aab-4ab2-493f-ba8f-f3bc42dc7bc9	cc52fa73-bb3a-49ea-bb36-a0191f934e11	2025-10-10	\N	\N	\N	246.600000	\N	GENERATED	2025-11-04 12:45:12.48196+01
883865e4-d307-4b61-b3af-c96f376687ad	cc52fa73-bb3a-49ea-bb36-a0191f934e11	2025-10-11	\N	\N	\N	247.370000	\N	GENERATED	2025-11-04 12:45:12.482622+01
26f82d1d-c1f4-47ff-a94d-c329e7404755	cc52fa73-bb3a-49ea-bb36-a0191f934e11	2025-10-12	\N	\N	\N	248.310000	\N	GENERATED	2025-11-04 12:45:12.48324+01
01323d36-cc71-47a6-b44b-7222180283de	cc52fa73-bb3a-49ea-bb36-a0191f934e11	2025-10-13	\N	\N	\N	247.010000	\N	GENERATED	2025-11-04 12:45:12.483847+01
2c1c3faf-7bd4-41c8-80c5-ddd77539faec	cc52fa73-bb3a-49ea-bb36-a0191f934e11	2025-10-14	\N	\N	\N	248.750000	\N	GENERATED	2025-11-04 12:45:12.484466+01
7e542cbb-7a45-45ef-9d6d-d91eb25d440a	cc52fa73-bb3a-49ea-bb36-a0191f934e11	2025-10-15	\N	\N	\N	245.370000	\N	GENERATED	2025-11-04 12:45:12.485083+01
3debd856-1285-4145-bde1-4cc7605c1b30	cc52fa73-bb3a-49ea-bb36-a0191f934e11	2025-10-16	\N	\N	\N	246.330000	\N	GENERATED	2025-11-04 12:45:12.485694+01
48f90584-a742-4010-a45a-a08cca8b4b14	cc52fa73-bb3a-49ea-bb36-a0191f934e11	2025-10-17	\N	\N	\N	246.470000	\N	GENERATED	2025-11-04 12:45:12.486321+01
af6246e9-c830-490d-a056-59ebb1b54a54	cc52fa73-bb3a-49ea-bb36-a0191f934e11	2025-10-18	\N	\N	\N	247.550000	\N	GENERATED	2025-11-04 12:45:12.486933+01
82837111-0aca-49a5-aa8c-93bf4d9b1a97	cc52fa73-bb3a-49ea-bb36-a0191f934e11	2025-10-19	\N	\N	\N	249.700000	\N	GENERATED	2025-11-04 12:45:12.487783+01
5af7ce95-1cfc-4626-b6a4-29846b201a50	cc52fa73-bb3a-49ea-bb36-a0191f934e11	2025-10-20	\N	\N	\N	246.520000	\N	GENERATED	2025-11-04 12:45:12.488845+01
0799f7f2-95c0-4412-bf26-0f1d29825e2c	cc52fa73-bb3a-49ea-bb36-a0191f934e11	2025-10-21	\N	\N	\N	248.040000	\N	GENERATED	2025-11-04 12:45:12.489543+01
a6af78d8-c248-4cea-8c45-b7fa5a3f1333	cc52fa73-bb3a-49ea-bb36-a0191f934e11	2025-10-22	\N	\N	\N	249.050000	\N	GENERATED	2025-11-04 12:45:12.490166+01
fe87db6f-5dda-4f46-b235-1c62095f3d66	cc52fa73-bb3a-49ea-bb36-a0191f934e11	2025-10-23	\N	\N	\N	249.040000	\N	GENERATED	2025-11-04 12:45:12.490791+01
68a4a0f4-917f-46eb-82da-3e8bc0b98585	cc52fa73-bb3a-49ea-bb36-a0191f934e11	2025-10-24	\N	\N	\N	249.240000	\N	GENERATED	2025-11-04 12:45:12.491476+01
faab9f5f-237c-4287-87de-10191601901a	cc52fa73-bb3a-49ea-bb36-a0191f934e11	2025-10-25	\N	\N	\N	247.260000	\N	GENERATED	2025-11-04 12:45:12.492102+01
618e2adf-f8a1-404a-bbb4-ac45131e9b64	cc52fa73-bb3a-49ea-bb36-a0191f934e11	2025-10-26	\N	\N	\N	247.930000	\N	GENERATED	2025-11-04 12:45:12.49273+01
0081995e-f340-4ac8-b081-928a705dd8e5	cc52fa73-bb3a-49ea-bb36-a0191f934e11	2025-10-27	\N	\N	\N	248.790000	\N	GENERATED	2025-11-04 12:45:12.493373+01
f33911cd-5ec0-40f3-8edb-e09b7bc62bcf	cc52fa73-bb3a-49ea-bb36-a0191f934e11	2025-10-28	\N	\N	\N	247.200000	\N	GENERATED	2025-11-04 12:45:12.493994+01
74d4d188-1cdf-4add-a76a-915e23d797e9	cc52fa73-bb3a-49ea-bb36-a0191f934e11	2025-10-29	\N	\N	\N	248.180000	\N	GENERATED	2025-11-04 12:45:12.494622+01
9873529f-16a5-489a-a528-0e621a88dfbd	cc52fa73-bb3a-49ea-bb36-a0191f934e11	2025-10-30	\N	\N	\N	250.090000	\N	GENERATED	2025-11-04 12:45:12.495244+01
a4f838fb-0dc7-43a9-8497-a5080cdb91cf	cc52fa73-bb3a-49ea-bb36-a0191f934e11	2025-10-31	\N	\N	\N	248.900000	\N	GENERATED	2025-11-04 12:45:12.496094+01
cc3450d0-ba84-4c96-a1e3-b3767368fc17	cc52fa73-bb3a-49ea-bb36-a0191f934e11	2025-11-01	\N	\N	\N	248.340000	\N	GENERATED	2025-11-04 12:45:12.49676+01
09405f86-153d-4f5e-be35-3db55cb3482b	cc52fa73-bb3a-49ea-bb36-a0191f934e11	2025-11-02	\N	\N	\N	249.340000	\N	GENERATED	2025-11-04 12:45:12.49752+01
672e9573-516c-4b4b-a751-2d64253e0461	cc52fa73-bb3a-49ea-bb36-a0191f934e11	2025-11-03	\N	\N	\N	248.620000	\N	GENERATED	2025-11-04 12:45:12.498141+01
118ee837-eb0e-47cd-9ae1-a2ffff06e95a	3a15e4de-589b-450d-93d1-a19b0c7bdb28	2024-11-04	\N	\N	\N	145.180000	\N	GENERATED	2025-11-04 12:45:12.499332+01
59d8d8cf-419d-4766-8dc5-7403c617f9d2	3a15e4de-589b-450d-93d1-a19b0c7bdb28	2024-11-05	\N	\N	\N	145.060000	\N	GENERATED	2025-11-04 12:45:12.499959+01
eef5ffcd-2a0d-4841-8603-af2caa505190	3a15e4de-589b-450d-93d1-a19b0c7bdb28	2024-11-06	\N	\N	\N	145.170000	\N	GENERATED	2025-11-04 12:45:12.500566+01
fd5d84e0-a291-42db-899e-369548339684	3a15e4de-589b-450d-93d1-a19b0c7bdb28	2024-11-07	\N	\N	\N	144.680000	\N	GENERATED	2025-11-04 12:45:12.501174+01
05ec4075-f23b-4763-8a55-5508cc2caf70	3a15e4de-589b-450d-93d1-a19b0c7bdb28	2024-11-08	\N	\N	\N	144.320000	\N	GENERATED	2025-11-04 12:45:12.501795+01
5c923020-1a96-4faf-b0ff-03a48406bb6c	3a15e4de-589b-450d-93d1-a19b0c7bdb28	2024-11-09	\N	\N	\N	145.340000	\N	GENERATED	2025-11-04 12:45:12.502408+01
c440ae00-e4c9-40a6-8274-8585f744e70e	3a15e4de-589b-450d-93d1-a19b0c7bdb28	2024-11-10	\N	\N	\N	145.710000	\N	GENERATED	2025-11-04 12:45:12.503013+01
0591e2c3-8281-4477-833f-5cb982e40079	3a15e4de-589b-450d-93d1-a19b0c7bdb28	2024-11-11	\N	\N	\N	146.220000	\N	GENERATED	2025-11-04 12:45:12.503803+01
ff0fcfc0-e755-443c-b792-f068a7da19aa	3a15e4de-589b-450d-93d1-a19b0c7bdb28	2024-11-12	\N	\N	\N	144.310000	\N	GENERATED	2025-11-04 12:45:12.504828+01
4d8c4438-025c-4909-baa8-916318cbb285	3a15e4de-589b-450d-93d1-a19b0c7bdb28	2024-11-13	\N	\N	\N	145.390000	\N	GENERATED	2025-11-04 12:45:12.505543+01
1d50f49e-0999-4e65-a7a3-3238961fd8e3	3a15e4de-589b-450d-93d1-a19b0c7bdb28	2024-11-14	\N	\N	\N	145.100000	\N	GENERATED	2025-11-04 12:45:12.506161+01
e5a4944e-0258-40b3-8e61-d3b72bca2d3a	3a15e4de-589b-450d-93d1-a19b0c7bdb28	2024-11-15	\N	\N	\N	145.090000	\N	GENERATED	2025-11-04 12:45:12.506822+01
43c406ad-09c7-44bc-a5dd-fcfcfa6cac69	3a15e4de-589b-450d-93d1-a19b0c7bdb28	2024-11-16	\N	\N	\N	144.280000	\N	GENERATED	2025-11-04 12:45:12.507463+01
22dcf8bb-aefa-4902-82fe-eb16b5c8ecc9	3a15e4de-589b-450d-93d1-a19b0c7bdb28	2024-11-17	\N	\N	\N	144.300000	\N	GENERATED	2025-11-04 12:45:12.50809+01
f047405c-0fd4-477b-bbac-e2c3fbe09689	3a15e4de-589b-450d-93d1-a19b0c7bdb28	2024-11-18	\N	\N	\N	145.320000	\N	GENERATED	2025-11-04 12:45:12.508715+01
b30bccb2-9c3b-4357-9d73-22de460bfc3b	3a15e4de-589b-450d-93d1-a19b0c7bdb28	2024-11-19	\N	\N	\N	144.280000	\N	GENERATED	2025-11-04 12:45:12.509336+01
8442e11a-5ec9-49ca-a5d5-14106f88f8f7	3a15e4de-589b-450d-93d1-a19b0c7bdb28	2024-11-20	\N	\N	\N	145.740000	\N	GENERATED	2025-11-04 12:45:12.509959+01
dcef5e0e-c61c-4efe-9172-43a4504203dd	3a15e4de-589b-450d-93d1-a19b0c7bdb28	2024-11-21	\N	\N	\N	144.530000	\N	GENERATED	2025-11-04 12:45:12.510566+01
fd191e5e-70dd-41cb-af52-01b9d134d9dd	3a15e4de-589b-450d-93d1-a19b0c7bdb28	2024-11-22	\N	\N	\N	145.750000	\N	GENERATED	2025-11-04 12:45:12.511203+01
74675e60-e6f3-42b3-b49c-d6fcb36cb160	3a15e4de-589b-450d-93d1-a19b0c7bdb28	2024-11-23	\N	\N	\N	145.320000	\N	GENERATED	2025-11-04 12:45:12.511813+01
9c67a51a-9741-4c62-8d18-49defc1dac87	3a15e4de-589b-450d-93d1-a19b0c7bdb28	2024-11-24	\N	\N	\N	144.720000	\N	GENERATED	2025-11-04 12:45:12.51244+01
458a35db-92fd-4271-ba63-a9feba4a4d49	3a15e4de-589b-450d-93d1-a19b0c7bdb28	2024-11-25	\N	\N	\N	145.310000	\N	GENERATED	2025-11-04 12:45:12.513064+01
2c4cea80-e096-4aa3-a0d5-d845d989a5b5	3a15e4de-589b-450d-93d1-a19b0c7bdb28	2024-11-26	\N	\N	\N	146.340000	\N	GENERATED	2025-11-04 12:45:12.51369+01
b8a67f88-f2ab-4390-bc12-fc0216619dc4	3a15e4de-589b-450d-93d1-a19b0c7bdb28	2024-11-27	\N	\N	\N	144.410000	\N	GENERATED	2025-11-04 12:45:12.514307+01
223be254-8a70-47a0-a804-860b9271caa0	3a15e4de-589b-450d-93d1-a19b0c7bdb28	2024-11-28	\N	\N	\N	144.320000	\N	GENERATED	2025-11-04 12:45:12.514919+01
05021989-397e-4131-b84e-d983dfb590ca	3a15e4de-589b-450d-93d1-a19b0c7bdb28	2024-11-29	\N	\N	\N	146.540000	\N	GENERATED	2025-11-04 12:45:12.515529+01
683ee4da-1e11-434a-9029-a4c0da8164b2	3a15e4de-589b-450d-93d1-a19b0c7bdb28	2024-11-30	\N	\N	\N	145.110000	\N	GENERATED	2025-11-04 12:45:12.516201+01
27cc1278-d08e-4f2c-a2f5-847af6f1e880	3a15e4de-589b-450d-93d1-a19b0c7bdb28	2024-12-01	\N	\N	\N	144.590000	\N	GENERATED	2025-11-04 12:45:12.516811+01
f12b5b73-35de-491b-9a5e-904492309616	3a15e4de-589b-450d-93d1-a19b0c7bdb28	2024-12-02	\N	\N	\N	145.890000	\N	GENERATED	2025-11-04 12:45:12.517429+01
91bea438-72fd-4a43-8d2f-44caf6e34e4e	3a15e4de-589b-450d-93d1-a19b0c7bdb28	2024-12-03	\N	\N	\N	145.610000	\N	GENERATED	2025-11-04 12:45:12.518038+01
4ed3362e-91f9-4ff5-92f7-46647d0f9368	3a15e4de-589b-450d-93d1-a19b0c7bdb28	2024-12-04	\N	\N	\N	145.190000	\N	GENERATED	2025-11-04 12:45:12.518807+01
326c65d7-8887-4090-99c9-75751f08b010	3a15e4de-589b-450d-93d1-a19b0c7bdb28	2024-12-05	\N	\N	\N	145.260000	\N	GENERATED	2025-11-04 12:45:12.519479+01
a38b6bc2-10d9-4cd9-93d1-7096fcbf6a4b	3a15e4de-589b-450d-93d1-a19b0c7bdb28	2024-12-06	\N	\N	\N	145.390000	\N	GENERATED	2025-11-04 12:45:12.520102+01
f27d9794-62ee-4ece-8afa-e9a4eef378e9	3a15e4de-589b-450d-93d1-a19b0c7bdb28	2024-12-07	\N	\N	\N	146.490000	\N	GENERATED	2025-11-04 12:45:12.520734+01
008ac1d2-e393-4947-9499-22d2cfb674d2	3a15e4de-589b-450d-93d1-a19b0c7bdb28	2024-12-08	\N	\N	\N	145.230000	\N	GENERATED	2025-11-04 12:45:12.521351+01
f7fade16-e062-47da-b5bc-4c966644d172	3a15e4de-589b-450d-93d1-a19b0c7bdb28	2024-12-09	\N	\N	\N	146.560000	\N	GENERATED	2025-11-04 12:45:12.521982+01
000b980a-7233-48eb-a277-2981a315e0e5	3a15e4de-589b-450d-93d1-a19b0c7bdb28	2024-12-10	\N	\N	\N	146.560000	\N	GENERATED	2025-11-04 12:45:12.522809+01
142904a8-0b4f-4b99-9ffa-a432d1eeccb2	3a15e4de-589b-450d-93d1-a19b0c7bdb28	2024-12-11	\N	\N	\N	146.180000	\N	GENERATED	2025-11-04 12:45:12.523504+01
f7e11ce4-895a-4fbe-8dbd-34b18e88edb1	3a15e4de-589b-450d-93d1-a19b0c7bdb28	2024-12-12	\N	\N	\N	147.280000	\N	GENERATED	2025-11-04 12:45:12.524123+01
1fef8e44-03b3-4a4e-82fd-737dee198a91	3a15e4de-589b-450d-93d1-a19b0c7bdb28	2024-12-13	\N	\N	\N	146.980000	\N	GENERATED	2025-11-04 12:45:12.524739+01
9c60886e-6978-46b7-a10e-b5f137a7a1e0	3a15e4de-589b-450d-93d1-a19b0c7bdb28	2024-12-14	\N	\N	\N	146.710000	\N	GENERATED	2025-11-04 12:45:12.525352+01
7fcfee18-8a42-4c99-9eff-7909236f3f80	3a15e4de-589b-450d-93d1-a19b0c7bdb28	2024-12-15	\N	\N	\N	145.640000	\N	GENERATED	2025-11-04 12:45:12.525979+01
7539a468-54a4-4970-9051-033a2b0af35c	3a15e4de-589b-450d-93d1-a19b0c7bdb28	2024-12-16	\N	\N	\N	147.490000	\N	GENERATED	2025-11-04 12:45:12.526591+01
3a45f99d-5e81-4db6-82b6-32e444c4b153	3a15e4de-589b-450d-93d1-a19b0c7bdb28	2024-12-17	\N	\N	\N	146.460000	\N	GENERATED	2025-11-04 12:45:12.527241+01
9bf21a8c-23d9-4d80-bb08-775c889463a8	3a15e4de-589b-450d-93d1-a19b0c7bdb28	2024-12-18	\N	\N	\N	145.980000	\N	GENERATED	2025-11-04 12:45:12.527868+01
23ad0374-1789-4f6d-9f45-1726432ead05	3a15e4de-589b-450d-93d1-a19b0c7bdb28	2024-12-19	\N	\N	\N	146.070000	\N	GENERATED	2025-11-04 12:45:12.528475+01
73b4671e-d394-4c5d-9854-39f5394bd346	3a15e4de-589b-450d-93d1-a19b0c7bdb28	2024-12-20	\N	\N	\N	145.840000	\N	GENERATED	2025-11-04 12:45:12.529122+01
ad0a4e45-250d-4ddf-bac4-7dccb16bffcf	3a15e4de-589b-450d-93d1-a19b0c7bdb28	2024-12-21	\N	\N	\N	147.400000	\N	GENERATED	2025-11-04 12:45:12.529748+01
18a1afed-e232-40be-ab59-3db64c91c38a	3a15e4de-589b-450d-93d1-a19b0c7bdb28	2024-12-22	\N	\N	\N	145.380000	\N	GENERATED	2025-11-04 12:45:12.530366+01
4d3bcce1-5326-43a9-b596-83c490400448	3a15e4de-589b-450d-93d1-a19b0c7bdb28	2024-12-23	\N	\N	\N	145.600000	\N	GENERATED	2025-11-04 12:45:12.530993+01
c4525522-4062-4ad6-8665-28d8047135f5	3a15e4de-589b-450d-93d1-a19b0c7bdb28	2024-12-24	\N	\N	\N	146.520000	\N	GENERATED	2025-11-04 12:45:12.531606+01
8260717f-99a1-41c1-9dce-48315937b9cb	3a15e4de-589b-450d-93d1-a19b0c7bdb28	2024-12-25	\N	\N	\N	146.340000	\N	GENERATED	2025-11-04 12:45:12.532224+01
6c6e1ce2-69d3-4fa3-a839-444dd0ec2d48	3a15e4de-589b-450d-93d1-a19b0c7bdb28	2024-12-26	\N	\N	\N	146.470000	\N	GENERATED	2025-11-04 12:45:12.532845+01
02fb00ac-1e3a-4826-b4d7-b7ee96effff2	3a15e4de-589b-450d-93d1-a19b0c7bdb28	2024-12-27	\N	\N	\N	147.100000	\N	GENERATED	2025-11-04 12:45:12.533459+01
3e24a095-dd07-4639-aeed-2865b03e9e60	3a15e4de-589b-450d-93d1-a19b0c7bdb28	2024-12-28	\N	\N	\N	146.920000	\N	GENERATED	2025-11-04 12:45:12.534296+01
19ceaac6-431e-48b6-85c6-f77b99b3e08f	3a15e4de-589b-450d-93d1-a19b0c7bdb28	2024-12-29	\N	\N	\N	146.340000	\N	GENERATED	2025-11-04 12:45:12.5352+01
f37f088b-0959-49cf-8520-ca16cb03a6d2	3a15e4de-589b-450d-93d1-a19b0c7bdb28	2024-12-30	\N	\N	\N	147.670000	\N	GENERATED	2025-11-04 12:45:12.535977+01
df784566-db96-40f6-9df1-24a9389da90d	3a15e4de-589b-450d-93d1-a19b0c7bdb28	2024-12-31	\N	\N	\N	146.760000	\N	GENERATED	2025-11-04 12:45:12.536685+01
979b3723-27df-4e3e-8bbe-087ba05b42e4	3a15e4de-589b-450d-93d1-a19b0c7bdb28	2025-01-01	\N	\N	\N	146.060000	\N	GENERATED	2025-11-04 12:45:12.537378+01
fe6664a2-b7f3-4a23-9651-751e19a61121	3a15e4de-589b-450d-93d1-a19b0c7bdb28	2025-01-02	\N	\N	\N	145.990000	\N	GENERATED	2025-11-04 12:45:12.538022+01
7c14a6a9-c077-4387-9d50-bcecb74cd7bf	3a15e4de-589b-450d-93d1-a19b0c7bdb28	2025-01-03	\N	\N	\N	146.660000	\N	GENERATED	2025-11-04 12:45:12.538658+01
11f457e8-774e-46ad-b3bb-681c35058eee	3a15e4de-589b-450d-93d1-a19b0c7bdb28	2025-01-04	\N	\N	\N	145.580000	\N	GENERATED	2025-11-04 12:45:12.539274+01
165f5148-7578-4de6-883d-f9d7cafda10a	3a15e4de-589b-450d-93d1-a19b0c7bdb28	2025-01-05	\N	\N	\N	146.360000	\N	GENERATED	2025-11-04 12:45:12.539892+01
0cf86979-63bc-47cc-b7da-c39092a7024f	3a15e4de-589b-450d-93d1-a19b0c7bdb28	2025-01-06	\N	\N	\N	147.360000	\N	GENERATED	2025-11-04 12:45:12.5405+01
7597721f-ac40-4f81-aa0b-c0a500c8c407	3a15e4de-589b-450d-93d1-a19b0c7bdb28	2025-01-07	\N	\N	\N	145.900000	\N	GENERATED	2025-11-04 12:45:12.541109+01
98224181-84f1-4bd2-a532-e040407fa291	3a15e4de-589b-450d-93d1-a19b0c7bdb28	2025-01-08	\N	\N	\N	147.550000	\N	GENERATED	2025-11-04 12:45:12.541842+01
afbb5baf-b50c-4dee-9fd5-e697db43526e	3a15e4de-589b-450d-93d1-a19b0c7bdb28	2025-01-09	\N	\N	\N	148.190000	\N	GENERATED	2025-11-04 12:45:12.542591+01
f0601f55-2432-46e2-8e9e-5722fae9d589	3a15e4de-589b-450d-93d1-a19b0c7bdb28	2025-01-10	\N	\N	\N	148.390000	\N	GENERATED	2025-11-04 12:45:12.543351+01
c49d5d93-e1cf-4d22-a8fd-00d75f05a177	3a15e4de-589b-450d-93d1-a19b0c7bdb28	2025-01-11	\N	\N	\N	148.170000	\N	GENERATED	2025-11-04 12:45:12.543968+01
ca4e6a68-fe56-41d1-8a99-ca06987f6f27	3a15e4de-589b-450d-93d1-a19b0c7bdb28	2025-01-12	\N	\N	\N	146.650000	\N	GENERATED	2025-11-04 12:45:12.544594+01
7ee1d832-92c7-4e57-8d92-e7d258e3c39e	3a15e4de-589b-450d-93d1-a19b0c7bdb28	2025-01-13	\N	\N	\N	146.840000	\N	GENERATED	2025-11-04 12:45:12.545201+01
ec6cf0c1-f9a3-43fe-99b8-663e30872c69	3a15e4de-589b-450d-93d1-a19b0c7bdb28	2025-01-14	\N	\N	\N	148.370000	\N	GENERATED	2025-11-04 12:45:12.545824+01
045fefec-cedd-42ec-b957-0457674709a2	3a15e4de-589b-450d-93d1-a19b0c7bdb28	2025-01-15	\N	\N	\N	148.700000	\N	GENERATED	2025-11-04 12:45:12.546448+01
b252cb2f-7eb1-42fb-ae07-d6bcfab2f207	3a15e4de-589b-450d-93d1-a19b0c7bdb28	2025-01-16	\N	\N	\N	148.450000	\N	GENERATED	2025-11-04 12:45:12.547062+01
58d954fe-0602-4542-8732-eeece21dfaad	3a15e4de-589b-450d-93d1-a19b0c7bdb28	2025-01-17	\N	\N	\N	147.590000	\N	GENERATED	2025-11-04 12:45:12.547764+01
42f200c0-e658-432c-9390-31ed0df131c0	3a15e4de-589b-450d-93d1-a19b0c7bdb28	2025-01-18	\N	\N	\N	147.670000	\N	GENERATED	2025-11-04 12:45:12.548402+01
8015a984-c60a-4fdf-a3bb-ad54b3032b35	3a15e4de-589b-450d-93d1-a19b0c7bdb28	2025-01-19	\N	\N	\N	148.590000	\N	GENERATED	2025-11-04 12:45:12.549014+01
91d1ef36-f420-46af-9106-f3a3ff62ad3a	3a15e4de-589b-450d-93d1-a19b0c7bdb28	2025-01-20	\N	\N	\N	146.700000	\N	GENERATED	2025-11-04 12:45:12.549839+01
8de7a66e-6ebe-4641-a159-74adb2fc98e7	3a15e4de-589b-450d-93d1-a19b0c7bdb28	2025-01-21	\N	\N	\N	147.630000	\N	GENERATED	2025-11-04 12:45:12.550477+01
67f778b8-1508-4a17-a8c0-b03275902a7d	3a15e4de-589b-450d-93d1-a19b0c7bdb28	2025-01-22	\N	\N	\N	148.590000	\N	GENERATED	2025-11-04 12:45:12.551098+01
d6857067-5c72-4a5b-8945-f7fd57689be8	3a15e4de-589b-450d-93d1-a19b0c7bdb28	2025-01-23	\N	\N	\N	147.180000	\N	GENERATED	2025-11-04 12:45:12.551741+01
72a1c341-d4bc-49f3-a47b-f469b06b238e	3a15e4de-589b-450d-93d1-a19b0c7bdb28	2025-01-24	\N	\N	\N	146.470000	\N	GENERATED	2025-11-04 12:45:12.552395+01
154ea11b-f3dc-4828-b53a-4fd241b06096	3a15e4de-589b-450d-93d1-a19b0c7bdb28	2025-01-25	\N	\N	\N	148.250000	\N	GENERATED	2025-11-04 12:45:12.553001+01
091d9357-5466-4f97-8906-5c1f98485fbd	3a15e4de-589b-450d-93d1-a19b0c7bdb28	2025-01-26	\N	\N	\N	148.080000	\N	GENERATED	2025-11-04 12:45:12.553624+01
9a9f2177-40dc-4c72-82c3-1672d2a0cec3	3a15e4de-589b-450d-93d1-a19b0c7bdb28	2025-01-27	\N	\N	\N	148.200000	\N	GENERATED	2025-11-04 12:45:12.554426+01
a6feb588-6c50-4a66-b2ff-cef2d0ec4c91	3a15e4de-589b-450d-93d1-a19b0c7bdb28	2025-01-28	\N	\N	\N	148.490000	\N	GENERATED	2025-11-04 12:45:12.555081+01
9a4b3d4c-81b9-4662-bbd1-3c9583a77edf	3a15e4de-589b-450d-93d1-a19b0c7bdb28	2025-01-29	\N	\N	\N	148.760000	\N	GENERATED	2025-11-04 12:45:12.555723+01
eea6b622-5aac-4e8e-bf9d-1595973a5878	3a15e4de-589b-450d-93d1-a19b0c7bdb28	2025-01-30	\N	\N	\N	147.050000	\N	GENERATED	2025-11-04 12:45:12.556414+01
c7abc3ee-b52a-4fca-8abf-68e863053354	3a15e4de-589b-450d-93d1-a19b0c7bdb28	2025-01-31	\N	\N	\N	148.690000	\N	GENERATED	2025-11-04 12:45:12.557026+01
468094ba-0b86-4ed6-ba93-a37b55911b41	3a15e4de-589b-450d-93d1-a19b0c7bdb28	2025-02-01	\N	\N	\N	147.720000	\N	GENERATED	2025-11-04 12:45:12.557678+01
27683df7-f44e-4db1-bb4c-a07e9e52a159	3a15e4de-589b-450d-93d1-a19b0c7bdb28	2025-02-02	\N	\N	\N	147.130000	\N	GENERATED	2025-11-04 12:45:12.558319+01
43a709a8-ff6e-4c9a-b477-2f9fd6f4228e	3a15e4de-589b-450d-93d1-a19b0c7bdb28	2025-02-03	\N	\N	\N	147.680000	\N	GENERATED	2025-11-04 12:45:12.558929+01
4f9200e2-f848-4d97-ae6b-b4348556c8eb	3a15e4de-589b-450d-93d1-a19b0c7bdb28	2025-02-04	\N	\N	\N	147.330000	\N	GENERATED	2025-11-04 12:45:12.559556+01
bba172e1-0bee-463e-af99-5cd47f981b8c	3a15e4de-589b-450d-93d1-a19b0c7bdb28	2025-02-05	\N	\N	\N	148.690000	\N	GENERATED	2025-11-04 12:45:12.560174+01
83c5cbad-3506-4765-9c4b-da457358ff88	3a15e4de-589b-450d-93d1-a19b0c7bdb28	2025-02-06	\N	\N	\N	147.000000	\N	GENERATED	2025-11-04 12:45:12.560796+01
d15580dd-12e1-4e18-b24e-8b295fb4adc2	3a15e4de-589b-450d-93d1-a19b0c7bdb28	2025-02-07	\N	\N	\N	147.310000	\N	GENERATED	2025-11-04 12:45:12.561414+01
5de0238a-4d30-452f-8f3d-86e3cd989322	3a15e4de-589b-450d-93d1-a19b0c7bdb28	2025-02-08	\N	\N	\N	148.840000	\N	GENERATED	2025-11-04 12:45:12.562024+01
c173ba74-a021-4ec1-85ef-32ac1ad683ae	3a15e4de-589b-450d-93d1-a19b0c7bdb28	2025-02-09	\N	\N	\N	147.040000	\N	GENERATED	2025-11-04 12:45:12.562652+01
d6a22297-83e5-43d3-a23e-d334b196db53	3a15e4de-589b-450d-93d1-a19b0c7bdb28	2025-02-10	\N	\N	\N	147.070000	\N	GENERATED	2025-11-04 12:45:12.563274+01
8725074b-d408-4d49-a107-aa411eed84f8	3a15e4de-589b-450d-93d1-a19b0c7bdb28	2025-02-11	\N	\N	\N	146.880000	\N	GENERATED	2025-11-04 12:45:12.563888+01
3d739b9b-b31f-4651-8b25-8105750450b8	3a15e4de-589b-450d-93d1-a19b0c7bdb28	2025-02-12	\N	\N	\N	147.030000	\N	GENERATED	2025-11-04 12:45:12.564505+01
d443fc5d-7d29-4982-8060-506b7b27ba4a	3a15e4de-589b-450d-93d1-a19b0c7bdb28	2025-02-13	\N	\N	\N	147.720000	\N	GENERATED	2025-11-04 12:45:12.565117+01
e71e3406-e227-4e2c-ac88-49c76a503d04	3a15e4de-589b-450d-93d1-a19b0c7bdb28	2025-02-14	\N	\N	\N	148.750000	\N	GENERATED	2025-11-04 12:45:12.566469+01
1ef69f52-274d-40c7-b0f5-5e169699a53a	3a15e4de-589b-450d-93d1-a19b0c7bdb28	2025-02-15	\N	\N	\N	148.420000	\N	GENERATED	2025-11-04 12:45:12.567158+01
12d686b4-1c3f-4af9-ae85-6ec9ff046aea	3a15e4de-589b-450d-93d1-a19b0c7bdb28	2025-02-16	\N	\N	\N	149.280000	\N	GENERATED	2025-11-04 12:45:12.567807+01
aa1e475c-091b-4503-a783-ea68e1b6086a	3a15e4de-589b-450d-93d1-a19b0c7bdb28	2025-02-17	\N	\N	\N	149.050000	\N	GENERATED	2025-11-04 12:45:12.568455+01
c3a0ca06-6941-47b3-b2ee-c5982702f3d5	3a15e4de-589b-450d-93d1-a19b0c7bdb28	2025-02-18	\N	\N	\N	147.110000	\N	GENERATED	2025-11-04 12:45:12.569088+01
a3d085d1-42bb-4a26-970d-d40af357d53c	3a15e4de-589b-450d-93d1-a19b0c7bdb28	2025-02-19	\N	\N	\N	149.420000	\N	GENERATED	2025-11-04 12:45:12.569711+01
1e240638-9b03-4bf9-97b8-51145977ce7a	3a15e4de-589b-450d-93d1-a19b0c7bdb28	2025-02-20	\N	\N	\N	149.110000	\N	GENERATED	2025-11-04 12:45:12.570346+01
355b4a85-2263-404e-9826-d57350d913fe	3a15e4de-589b-450d-93d1-a19b0c7bdb28	2025-02-21	\N	\N	\N	147.900000	\N	GENERATED	2025-11-04 12:45:12.57098+01
f46c1a54-ad0b-40e1-837d-d720b9d64059	3a15e4de-589b-450d-93d1-a19b0c7bdb28	2025-02-22	\N	\N	\N	148.810000	\N	GENERATED	2025-11-04 12:45:12.571604+01
370d11bd-37a7-4a32-a2d4-15170f0b4f9d	3a15e4de-589b-450d-93d1-a19b0c7bdb28	2025-02-23	\N	\N	\N	149.250000	\N	GENERATED	2025-11-04 12:45:12.572259+01
4f0a9144-2894-4032-97a0-72dba680bda9	3a15e4de-589b-450d-93d1-a19b0c7bdb28	2025-02-24	\N	\N	\N	148.670000	\N	GENERATED	2025-11-04 12:45:12.57288+01
4016cfc9-a855-4dfb-96c2-823c4188eace	3a15e4de-589b-450d-93d1-a19b0c7bdb28	2025-02-25	\N	\N	\N	149.210000	\N	GENERATED	2025-11-04 12:45:12.573617+01
efba4dbc-ccc3-4caf-b59c-04c234ffe257	3a15e4de-589b-450d-93d1-a19b0c7bdb28	2025-02-26	\N	\N	\N	147.980000	\N	GENERATED	2025-11-04 12:45:12.574781+01
ff9736ac-4f9c-4afd-9b12-4ca573708c6d	3a15e4de-589b-450d-93d1-a19b0c7bdb28	2025-02-27	\N	\N	\N	148.880000	\N	GENERATED	2025-11-04 12:45:12.57584+01
abd0ba4d-743c-44c4-b78f-56cbd5e925f9	3a15e4de-589b-450d-93d1-a19b0c7bdb28	2025-02-28	\N	\N	\N	147.930000	\N	GENERATED	2025-11-04 12:45:12.576594+01
0abab095-36c0-45a4-8088-b06be3a4c4ba	3a15e4de-589b-450d-93d1-a19b0c7bdb28	2025-03-01	\N	\N	\N	147.960000	\N	GENERATED	2025-11-04 12:45:12.577403+01
71512135-99cb-4807-ae22-dac251a86b61	3a15e4de-589b-450d-93d1-a19b0c7bdb28	2025-03-02	\N	\N	\N	148.730000	\N	GENERATED	2025-11-04 12:45:12.578223+01
de709d47-9396-42af-b955-6493c46b53ec	3a15e4de-589b-450d-93d1-a19b0c7bdb28	2025-03-03	\N	\N	\N	147.550000	\N	GENERATED	2025-11-04 12:45:12.578879+01
9b363f6b-a52b-47dc-8542-6407aef51bd6	3a15e4de-589b-450d-93d1-a19b0c7bdb28	2025-03-04	\N	\N	\N	148.670000	\N	GENERATED	2025-11-04 12:45:12.579535+01
07b4d7f1-329a-418f-81e3-6aeadc55316f	3a15e4de-589b-450d-93d1-a19b0c7bdb28	2025-03-05	\N	\N	\N	149.450000	\N	GENERATED	2025-11-04 12:45:12.580165+01
51710cf1-6bae-4eda-8da9-76c16dad814c	3a15e4de-589b-450d-93d1-a19b0c7bdb28	2025-03-06	\N	\N	\N	149.610000	\N	GENERATED	2025-11-04 12:45:12.580978+01
a21bf284-1c95-4a53-a643-dab24fb65383	3a15e4de-589b-450d-93d1-a19b0c7bdb28	2025-03-07	\N	\N	\N	149.010000	\N	GENERATED	2025-11-04 12:45:12.581946+01
eb77e422-ece5-4a10-936f-da6de3978098	3a15e4de-589b-450d-93d1-a19b0c7bdb28	2025-03-08	\N	\N	\N	150.300000	\N	GENERATED	2025-11-04 12:45:12.582607+01
695348df-43a5-4001-a88f-234dc8fe611d	3a15e4de-589b-450d-93d1-a19b0c7bdb28	2025-03-09	\N	\N	\N	149.290000	\N	GENERATED	2025-11-04 12:45:12.583232+01
31b5e344-9300-4d14-b196-530c1341f67f	3a15e4de-589b-450d-93d1-a19b0c7bdb28	2025-03-10	\N	\N	\N	150.170000	\N	GENERATED	2025-11-04 12:45:12.584009+01
cc0ddace-497b-46d9-816f-7effe22b5aab	3a15e4de-589b-450d-93d1-a19b0c7bdb28	2025-03-11	\N	\N	\N	147.860000	\N	GENERATED	2025-11-04 12:45:12.584646+01
1da267e3-679c-4885-bee8-235f099f072e	3a15e4de-589b-450d-93d1-a19b0c7bdb28	2025-03-12	\N	\N	\N	149.630000	\N	GENERATED	2025-11-04 12:45:12.585262+01
b5bc90db-3697-4417-a480-82a00fc88f8f	3a15e4de-589b-450d-93d1-a19b0c7bdb28	2025-03-13	\N	\N	\N	149.680000	\N	GENERATED	2025-11-04 12:45:12.58592+01
84e42e6c-dfaa-46ff-9e25-cb16edce8378	3a15e4de-589b-450d-93d1-a19b0c7bdb28	2025-03-14	\N	\N	\N	149.500000	\N	GENERATED	2025-11-04 12:45:12.586591+01
1c65a961-e994-4cb5-af04-0512d41f374f	3a15e4de-589b-450d-93d1-a19b0c7bdb28	2025-03-15	\N	\N	\N	148.020000	\N	GENERATED	2025-11-04 12:45:12.587249+01
4e98501d-d062-4eea-91dc-48d855400cde	3a15e4de-589b-450d-93d1-a19b0c7bdb28	2025-03-16	\N	\N	\N	148.560000	\N	GENERATED	2025-11-04 12:45:12.587873+01
88eaf7c9-3960-4355-b63c-c3d72fc427ad	3a15e4de-589b-450d-93d1-a19b0c7bdb28	2025-03-17	\N	\N	\N	149.650000	\N	GENERATED	2025-11-04 12:45:12.588485+01
19f06005-b026-4991-a311-fcab86f7019b	3a15e4de-589b-450d-93d1-a19b0c7bdb28	2025-03-18	\N	\N	\N	148.200000	\N	GENERATED	2025-11-04 12:45:12.589102+01
2d3881ae-e001-4703-8f37-879a513d734a	3a15e4de-589b-450d-93d1-a19b0c7bdb28	2025-03-19	\N	\N	\N	148.610000	\N	GENERATED	2025-11-04 12:45:12.589737+01
7eb8794e-7a08-44b3-8304-cfcb7b08e27e	3a15e4de-589b-450d-93d1-a19b0c7bdb28	2025-03-20	\N	\N	\N	149.220000	\N	GENERATED	2025-11-04 12:45:12.59035+01
e6dde675-ba33-4f23-a4be-4c049d96b6cb	3a15e4de-589b-450d-93d1-a19b0c7bdb28	2025-03-21	\N	\N	\N	150.350000	\N	GENERATED	2025-11-04 12:45:12.59098+01
104e292f-65ce-4c9c-97db-c7150fb59209	3a15e4de-589b-450d-93d1-a19b0c7bdb28	2025-03-22	\N	\N	\N	149.990000	\N	GENERATED	2025-11-04 12:45:12.591591+01
bea79750-2e9e-4f71-8ca5-c2ab2ba58641	3a15e4de-589b-450d-93d1-a19b0c7bdb28	2025-03-23	\N	\N	\N	148.020000	\N	GENERATED	2025-11-04 12:45:12.59224+01
a8afcdc2-b2ed-40e7-9dd0-bbbc3261f893	3a15e4de-589b-450d-93d1-a19b0c7bdb28	2025-03-24	\N	\N	\N	149.140000	\N	GENERATED	2025-11-04 12:45:12.592887+01
25da036e-09f0-4eca-9d30-7ed2f7b473f9	3a15e4de-589b-450d-93d1-a19b0c7bdb28	2025-03-25	\N	\N	\N	149.020000	\N	GENERATED	2025-11-04 12:45:12.593532+01
c363d0c6-dfaf-4edc-9bcb-32eedbe2eaff	3a15e4de-589b-450d-93d1-a19b0c7bdb28	2025-03-26	\N	\N	\N	149.690000	\N	GENERATED	2025-11-04 12:45:12.594174+01
5da49c99-e964-4102-a3e5-88bd07725e85	3a15e4de-589b-450d-93d1-a19b0c7bdb28	2025-03-27	\N	\N	\N	148.380000	\N	GENERATED	2025-11-04 12:45:12.594788+01
52f4937f-1b6f-4b4c-8efc-747a6b3543f4	3a15e4de-589b-450d-93d1-a19b0c7bdb28	2025-03-28	\N	\N	\N	149.220000	\N	GENERATED	2025-11-04 12:45:12.595411+01
109855f1-066a-4503-b3e7-5dd6b0dc0617	3a15e4de-589b-450d-93d1-a19b0c7bdb28	2025-03-29	\N	\N	\N	149.480000	\N	GENERATED	2025-11-04 12:45:12.596023+01
39af3d98-48e1-4119-bae6-23dfc7b4e7f4	3a15e4de-589b-450d-93d1-a19b0c7bdb28	2025-03-30	\N	\N	\N	149.890000	\N	GENERATED	2025-11-04 12:45:12.596945+01
0414706d-f6b3-45f2-9aaa-c84fa4456d94	3a15e4de-589b-450d-93d1-a19b0c7bdb28	2025-03-31	\N	\N	\N	149.400000	\N	GENERATED	2025-11-04 12:45:12.597625+01
be52ed6e-7866-4b64-891d-06d1c7875828	3a15e4de-589b-450d-93d1-a19b0c7bdb28	2025-04-01	\N	\N	\N	148.970000	\N	GENERATED	2025-11-04 12:45:12.598251+01
bfd2dfff-70db-44f1-a95e-629793994984	3a15e4de-589b-450d-93d1-a19b0c7bdb28	2025-04-02	\N	\N	\N	149.690000	\N	GENERATED	2025-11-04 12:45:12.598886+01
8e9ecf43-1c66-42d2-8492-19425434e54e	3a15e4de-589b-450d-93d1-a19b0c7bdb28	2025-04-03	\N	\N	\N	149.820000	\N	GENERATED	2025-11-04 12:45:12.599538+01
45e1e385-b8f1-4f67-b6b9-4e2bac281d71	3a15e4de-589b-450d-93d1-a19b0c7bdb28	2025-04-04	\N	\N	\N	151.150000	\N	GENERATED	2025-11-04 12:45:12.600146+01
a2abd9aa-019b-43e5-afc3-b94364288016	3a15e4de-589b-450d-93d1-a19b0c7bdb28	2025-04-05	\N	\N	\N	151.190000	\N	GENERATED	2025-11-04 12:45:12.60077+01
6c4fa530-8c4b-4f6d-be6d-403f4aed7f63	3a15e4de-589b-450d-93d1-a19b0c7bdb28	2025-04-06	\N	\N	\N	149.320000	\N	GENERATED	2025-11-04 12:45:12.601378+01
ee8eba21-b16b-4c7c-a1c5-542af46a75d4	3a15e4de-589b-450d-93d1-a19b0c7bdb28	2025-04-07	\N	\N	\N	149.850000	\N	GENERATED	2025-11-04 12:45:12.602023+01
30315eee-a957-47ef-ba44-f7b09c55acb9	3a15e4de-589b-450d-93d1-a19b0c7bdb28	2025-04-08	\N	\N	\N	148.560000	\N	GENERATED	2025-11-04 12:45:12.602642+01
d040df4f-a362-4301-8994-ed5875182932	3a15e4de-589b-450d-93d1-a19b0c7bdb28	2025-04-09	\N	\N	\N	149.440000	\N	GENERATED	2025-11-04 12:45:12.603247+01
72271e93-b043-41fe-b554-eb20a3c2c8a6	3a15e4de-589b-450d-93d1-a19b0c7bdb28	2025-04-10	\N	\N	\N	150.060000	\N	GENERATED	2025-11-04 12:45:12.603874+01
0e2eeff6-5e75-4312-a052-a504d3bc76f4	3a15e4de-589b-450d-93d1-a19b0c7bdb28	2025-04-11	\N	\N	\N	151.140000	\N	GENERATED	2025-11-04 12:45:12.60449+01
3c680b3d-4bd7-4620-b5f5-188002630e30	3a15e4de-589b-450d-93d1-a19b0c7bdb28	2025-04-12	\N	\N	\N	149.820000	\N	GENERATED	2025-11-04 12:45:12.605101+01
6ec71ab5-54c7-4473-9874-85ce0daf8b0b	3a15e4de-589b-450d-93d1-a19b0c7bdb28	2025-04-13	\N	\N	\N	151.200000	\N	GENERATED	2025-11-04 12:45:12.605713+01
a51d6d8d-9e67-47a3-a543-05de33c8e4d4	3a15e4de-589b-450d-93d1-a19b0c7bdb28	2025-04-14	\N	\N	\N	150.620000	\N	GENERATED	2025-11-04 12:45:12.606324+01
b2ca4232-7a40-4500-852f-2d37b8ca1576	3a15e4de-589b-450d-93d1-a19b0c7bdb28	2025-04-15	\N	\N	\N	149.020000	\N	GENERATED	2025-11-04 12:45:12.606956+01
b57c15f7-d077-48ca-8a25-69b997f267e1	3a15e4de-589b-450d-93d1-a19b0c7bdb28	2025-04-16	\N	\N	\N	148.870000	\N	GENERATED	2025-11-04 12:45:12.607569+01
d6dc9a30-0d0b-48b2-8d73-77700b1541e4	3a15e4de-589b-450d-93d1-a19b0c7bdb28	2025-04-17	\N	\N	\N	150.760000	\N	GENERATED	2025-11-04 12:45:12.60818+01
ecc38bbb-c35d-49ca-b191-05697b0321ad	3a15e4de-589b-450d-93d1-a19b0c7bdb28	2025-04-18	\N	\N	\N	151.560000	\N	GENERATED	2025-11-04 12:45:12.608802+01
90074835-74d6-4d31-99cb-38e1907187e3	3a15e4de-589b-450d-93d1-a19b0c7bdb28	2025-04-19	\N	\N	\N	150.770000	\N	GENERATED	2025-11-04 12:45:12.609413+01
c0725539-91dc-40b8-bee0-7b7b603c5f65	3a15e4de-589b-450d-93d1-a19b0c7bdb28	2025-04-20	\N	\N	\N	150.260000	\N	GENERATED	2025-11-04 12:45:12.610037+01
8ad5db3d-3b99-4a09-9746-5baa8193969c	3a15e4de-589b-450d-93d1-a19b0c7bdb28	2025-04-21	\N	\N	\N	149.780000	\N	GENERATED	2025-11-04 12:45:12.610668+01
24dc3547-5893-4727-a2f1-47d2e5fa311b	3a15e4de-589b-450d-93d1-a19b0c7bdb28	2025-04-22	\N	\N	\N	149.780000	\N	GENERATED	2025-11-04 12:45:12.611279+01
101b1ef4-a046-4c15-98ae-c2c710bcfe76	3a15e4de-589b-450d-93d1-a19b0c7bdb28	2025-04-23	\N	\N	\N	149.440000	\N	GENERATED	2025-11-04 12:45:12.612008+01
a09fe979-eebd-40a5-82ec-2febd2a1f9a6	3a15e4de-589b-450d-93d1-a19b0c7bdb28	2025-04-24	\N	\N	\N	150.690000	\N	GENERATED	2025-11-04 12:45:12.612653+01
31090fc5-c8c4-429d-a34c-2ca711165910	3a15e4de-589b-450d-93d1-a19b0c7bdb28	2025-04-25	\N	\N	\N	150.280000	\N	GENERATED	2025-11-04 12:45:12.613287+01
08b929c1-53da-419a-b5af-e284bfe52cd6	3a15e4de-589b-450d-93d1-a19b0c7bdb28	2025-04-26	\N	\N	\N	150.740000	\N	GENERATED	2025-11-04 12:45:12.614026+01
7668bca2-3c9d-478e-a3f2-36c1acd95e09	3a15e4de-589b-450d-93d1-a19b0c7bdb28	2025-04-27	\N	\N	\N	149.970000	\N	GENERATED	2025-11-04 12:45:12.614657+01
cb897a20-e315-42c8-89fe-464620d42670	3a15e4de-589b-450d-93d1-a19b0c7bdb28	2025-04-28	\N	\N	\N	150.010000	\N	GENERATED	2025-11-04 12:45:12.615287+01
58f6f29e-d064-4c8b-b120-9d108b6ff78b	3a15e4de-589b-450d-93d1-a19b0c7bdb28	2025-04-29	\N	\N	\N	149.410000	\N	GENERATED	2025-11-04 12:45:12.615909+01
3b9f7acc-8005-4073-83cd-541263ebeadd	3a15e4de-589b-450d-93d1-a19b0c7bdb28	2025-04-30	\N	\N	\N	151.240000	\N	GENERATED	2025-11-04 12:45:12.616621+01
d737664f-f019-4692-9c38-be6af3055cf4	3a15e4de-589b-450d-93d1-a19b0c7bdb28	2025-05-01	\N	\N	\N	151.440000	\N	GENERATED	2025-11-04 12:45:12.617236+01
947d2040-42b4-4d79-bda2-8644ea570536	3a15e4de-589b-450d-93d1-a19b0c7bdb28	2025-05-02	\N	\N	\N	150.140000	\N	GENERATED	2025-11-04 12:45:12.617849+01
356c15e0-aa83-4e74-ab6e-541b3a300139	3a15e4de-589b-450d-93d1-a19b0c7bdb28	2025-05-03	\N	\N	\N	150.280000	\N	GENERATED	2025-11-04 12:45:12.618463+01
1065da3a-62cc-415a-81f4-1cd0de6e1e74	3a15e4de-589b-450d-93d1-a19b0c7bdb28	2025-05-04	\N	\N	\N	149.320000	\N	GENERATED	2025-11-04 12:45:12.61908+01
89ce72dc-1314-4f7c-9f18-c11cd8759356	3a15e4de-589b-450d-93d1-a19b0c7bdb28	2025-05-05	\N	\N	\N	151.000000	\N	GENERATED	2025-11-04 12:45:12.61971+01
5a6f9ecc-95eb-4758-a75b-b49b2e5b64bd	3a15e4de-589b-450d-93d1-a19b0c7bdb28	2025-05-06	\N	\N	\N	149.610000	\N	GENERATED	2025-11-04 12:45:12.620324+01
47572b7f-b238-4393-b540-b000e2984b60	3a15e4de-589b-450d-93d1-a19b0c7bdb28	2025-05-07	\N	\N	\N	150.830000	\N	GENERATED	2025-11-04 12:45:12.620946+01
9ea9e905-2840-46f3-b417-ab0f0ff86f69	3a15e4de-589b-450d-93d1-a19b0c7bdb28	2025-05-08	\N	\N	\N	150.520000	\N	GENERATED	2025-11-04 12:45:12.621555+01
859bb3d4-fa60-4164-aa18-1b6cb8977a00	3a15e4de-589b-450d-93d1-a19b0c7bdb28	2025-05-09	\N	\N	\N	150.580000	\N	GENERATED	2025-11-04 12:45:12.622178+01
7949de33-74f5-4625-9d7a-8b62ad8299a4	3a15e4de-589b-450d-93d1-a19b0c7bdb28	2025-05-10	\N	\N	\N	151.650000	\N	GENERATED	2025-11-04 12:45:12.622804+01
33de6f5b-1c9d-4f44-80b9-8604c467f7a0	3a15e4de-589b-450d-93d1-a19b0c7bdb28	2025-05-11	\N	\N	\N	152.370000	\N	GENERATED	2025-11-04 12:45:12.623442+01
042a9f04-6b93-4603-a039-ee14d2e05eee	3a15e4de-589b-450d-93d1-a19b0c7bdb28	2025-05-12	\N	\N	\N	151.990000	\N	GENERATED	2025-11-04 12:45:12.624067+01
88ffcc88-a0dd-4a4d-a27a-b596fee5bc93	3a15e4de-589b-450d-93d1-a19b0c7bdb28	2025-05-13	\N	\N	\N	150.490000	\N	GENERATED	2025-11-04 12:45:12.624689+01
e654d8fc-709a-4584-98c2-23afef0b042f	3a15e4de-589b-450d-93d1-a19b0c7bdb28	2025-05-14	\N	\N	\N	150.090000	\N	GENERATED	2025-11-04 12:45:12.625725+01
7e6fdc74-e5a4-4eca-a592-04720d18db07	3a15e4de-589b-450d-93d1-a19b0c7bdb28	2025-05-15	\N	\N	\N	150.520000	\N	GENERATED	2025-11-04 12:45:12.626333+01
69361a1e-61cc-4c95-b9bc-2682ee4317e1	3a15e4de-589b-450d-93d1-a19b0c7bdb28	2025-05-16	\N	\N	\N	150.420000	\N	GENERATED	2025-11-04 12:45:12.627186+01
58aa8b22-919e-4696-8c91-768f285a6b91	3a15e4de-589b-450d-93d1-a19b0c7bdb28	2025-05-17	\N	\N	\N	150.490000	\N	GENERATED	2025-11-04 12:45:12.628086+01
cd1d6df3-3b01-4250-8d1e-b1f24b24adaa	3a15e4de-589b-450d-93d1-a19b0c7bdb28	2025-05-18	\N	\N	\N	150.790000	\N	GENERATED	2025-11-04 12:45:12.628792+01
aca66dfa-8430-4894-92f7-55fd7a5bce97	3a15e4de-589b-450d-93d1-a19b0c7bdb28	2025-05-19	\N	\N	\N	152.020000	\N	GENERATED	2025-11-04 12:45:12.629402+01
316e84cf-1a64-482e-958d-40526598cc1c	3a15e4de-589b-450d-93d1-a19b0c7bdb28	2025-05-20	\N	\N	\N	150.300000	\N	GENERATED	2025-11-04 12:45:12.630048+01
f2e124ee-eb7e-4478-a187-604857319c76	3a15e4de-589b-450d-93d1-a19b0c7bdb28	2025-05-21	\N	\N	\N	150.570000	\N	GENERATED	2025-11-04 12:45:12.630665+01
dee1cac7-5efe-411b-bd9e-c2e3ab316b3f	3a15e4de-589b-450d-93d1-a19b0c7bdb28	2025-05-22	\N	\N	\N	151.360000	\N	GENERATED	2025-11-04 12:45:12.631297+01
e7eeed8c-b3fb-4eb2-8bd8-d4e225ec44fa	3a15e4de-589b-450d-93d1-a19b0c7bdb28	2025-05-23	\N	\N	\N	150.300000	\N	GENERATED	2025-11-04 12:45:12.63196+01
2bb3938b-6a49-4b36-9322-613ec188fce2	3a15e4de-589b-450d-93d1-a19b0c7bdb28	2025-05-24	\N	\N	\N	152.620000	\N	GENERATED	2025-11-04 12:45:12.632568+01
1db3fed3-03fb-4358-8900-d207567b5885	3a15e4de-589b-450d-93d1-a19b0c7bdb28	2025-05-25	\N	\N	\N	152.050000	\N	GENERATED	2025-11-04 12:45:12.633193+01
a4431cc4-c33f-411f-81e8-e2f6e2994e60	3a15e4de-589b-450d-93d1-a19b0c7bdb28	2025-05-26	\N	\N	\N	152.710000	\N	GENERATED	2025-11-04 12:45:12.633811+01
2fbf3291-e557-46a8-a0fd-7f84dd4d6d29	3a15e4de-589b-450d-93d1-a19b0c7bdb28	2025-05-27	\N	\N	\N	152.120000	\N	GENERATED	2025-11-04 12:45:12.634427+01
e984bc69-1427-4087-bb0e-fc5433227fcf	3a15e4de-589b-450d-93d1-a19b0c7bdb28	2025-05-28	\N	\N	\N	152.350000	\N	GENERATED	2025-11-04 12:45:12.635192+01
5ab328d6-5b5b-43f2-8ef5-fad4a22c0e0b	3a15e4de-589b-450d-93d1-a19b0c7bdb28	2025-05-29	\N	\N	\N	150.360000	\N	GENERATED	2025-11-04 12:45:12.635822+01
a4b2e958-068d-4e79-a257-a88e3e754bf9	3a15e4de-589b-450d-93d1-a19b0c7bdb28	2025-05-30	\N	\N	\N	150.130000	\N	GENERATED	2025-11-04 12:45:12.63653+01
92459342-4224-4ccd-8556-16c5f0b2e4e6	3a15e4de-589b-450d-93d1-a19b0c7bdb28	2025-05-31	\N	\N	\N	150.260000	\N	GENERATED	2025-11-04 12:45:12.637171+01
be92713f-1720-4c0b-8bfd-3e6bfdcd11e6	3a15e4de-589b-450d-93d1-a19b0c7bdb28	2025-06-01	\N	\N	\N	151.890000	\N	GENERATED	2025-11-04 12:45:12.637796+01
08866bda-486d-40da-8d1f-7ea218c3d272	3a15e4de-589b-450d-93d1-a19b0c7bdb28	2025-06-02	\N	\N	\N	150.370000	\N	GENERATED	2025-11-04 12:45:12.638405+01
65ef8744-943d-4b67-926b-e855e6f3fee2	3a15e4de-589b-450d-93d1-a19b0c7bdb28	2025-06-03	\N	\N	\N	150.650000	\N	GENERATED	2025-11-04 12:45:12.639086+01
bb3c2a74-6c95-44ac-bcee-f91e74a24bbf	3a15e4de-589b-450d-93d1-a19b0c7bdb28	2025-06-04	\N	\N	\N	152.950000	\N	GENERATED	2025-11-04 12:45:12.639709+01
607b14b1-367e-4e31-a783-aad97e315857	3a15e4de-589b-450d-93d1-a19b0c7bdb28	2025-06-05	\N	\N	\N	152.780000	\N	GENERATED	2025-11-04 12:45:12.640319+01
a0086ab7-5ff2-4064-82a0-999916bb1067	3a15e4de-589b-450d-93d1-a19b0c7bdb28	2025-06-06	\N	\N	\N	152.750000	\N	GENERATED	2025-11-04 12:45:12.640936+01
a801e2f6-c9de-4db9-acda-9074a00ed16c	3a15e4de-589b-450d-93d1-a19b0c7bdb28	2025-06-07	\N	\N	\N	150.910000	\N	GENERATED	2025-11-04 12:45:12.641567+01
a1d59c7a-499d-4ce8-8efc-9b09904aec78	3a15e4de-589b-450d-93d1-a19b0c7bdb28	2025-06-08	\N	\N	\N	150.620000	\N	GENERATED	2025-11-04 12:45:12.642271+01
4bace2eb-81ef-4870-8e8f-f817e0f4e885	3a15e4de-589b-450d-93d1-a19b0c7bdb28	2025-06-09	\N	\N	\N	150.600000	\N	GENERATED	2025-11-04 12:45:12.643051+01
b170e2ae-d035-41c9-905a-2dd41e08c552	3a15e4de-589b-450d-93d1-a19b0c7bdb28	2025-06-10	\N	\N	\N	150.750000	\N	GENERATED	2025-11-04 12:45:12.643688+01
9e80a169-c1ab-4e67-bcb6-0bd275b8c102	3a15e4de-589b-450d-93d1-a19b0c7bdb28	2025-06-11	\N	\N	\N	151.520000	\N	GENERATED	2025-11-04 12:45:12.644329+01
b48917a8-b074-4df4-a4f8-65e256ab07f0	3a15e4de-589b-450d-93d1-a19b0c7bdb28	2025-06-12	\N	\N	\N	152.250000	\N	GENERATED	2025-11-04 12:45:12.644949+01
a1c596c3-818d-48bc-b3b8-4d1e0cacf728	3a15e4de-589b-450d-93d1-a19b0c7bdb28	2025-06-13	\N	\N	\N	151.200000	\N	GENERATED	2025-11-04 12:45:12.645562+01
2c939e86-1eed-45a5-b90c-67d608c95c51	3a15e4de-589b-450d-93d1-a19b0c7bdb28	2025-06-14	\N	\N	\N	151.410000	\N	GENERATED	2025-11-04 12:45:12.64619+01
3e464426-45bd-460e-bac3-3d12d88928d9	3a15e4de-589b-450d-93d1-a19b0c7bdb28	2025-06-15	\N	\N	\N	151.020000	\N	GENERATED	2025-11-04 12:45:12.646816+01
e53f67fa-1104-414d-a6ad-12f485be7f00	3a15e4de-589b-450d-93d1-a19b0c7bdb28	2025-06-16	\N	\N	\N	152.430000	\N	GENERATED	2025-11-04 12:45:12.647647+01
13d29d47-6fe3-4afc-a9b9-04146f3ce101	3a15e4de-589b-450d-93d1-a19b0c7bdb28	2025-06-17	\N	\N	\N	151.710000	\N	GENERATED	2025-11-04 12:45:12.648802+01
eb741b8f-e37c-4e14-a691-25957d41f9b4	3a15e4de-589b-450d-93d1-a19b0c7bdb28	2025-06-18	\N	\N	\N	152.460000	\N	GENERATED	2025-11-04 12:45:12.649629+01
51e6c9d4-d1f6-4a62-a1b5-1838db23f77d	3a15e4de-589b-450d-93d1-a19b0c7bdb28	2025-06-19	\N	\N	\N	151.980000	\N	GENERATED	2025-11-04 12:45:12.65026+01
fda623ac-8df6-4edd-807f-442d0b28a7b3	3a15e4de-589b-450d-93d1-a19b0c7bdb28	2025-06-20	\N	\N	\N	151.560000	\N	GENERATED	2025-11-04 12:45:12.650883+01
d27ce13d-5e53-4376-8055-344d29f27236	3a15e4de-589b-450d-93d1-a19b0c7bdb28	2025-06-21	\N	\N	\N	152.530000	\N	GENERATED	2025-11-04 12:45:12.651506+01
fa5ef6d7-815f-4738-b602-2ca3072b983b	3a15e4de-589b-450d-93d1-a19b0c7bdb28	2025-06-22	\N	\N	\N	152.890000	\N	GENERATED	2025-11-04 12:45:12.652117+01
c7cf3c7b-aae2-4902-a97c-7e4713ea89dd	3a15e4de-589b-450d-93d1-a19b0c7bdb28	2025-06-23	\N	\N	\N	151.510000	\N	GENERATED	2025-11-04 12:45:12.652739+01
4c89bada-9c6c-42d5-9e11-81610df6bd57	3a15e4de-589b-450d-93d1-a19b0c7bdb28	2025-06-24	\N	\N	\N	151.890000	\N	GENERATED	2025-11-04 12:45:12.653357+01
cb126e2e-b5fc-4377-b82f-23c7979ca73a	3a15e4de-589b-450d-93d1-a19b0c7bdb28	2025-06-25	\N	\N	\N	153.550000	\N	GENERATED	2025-11-04 12:45:12.653968+01
441205c3-fabd-454b-a698-1d4a6241b807	3a15e4de-589b-450d-93d1-a19b0c7bdb28	2025-06-26	\N	\N	\N	152.610000	\N	GENERATED	2025-11-04 12:45:12.654588+01
94781d2d-b08a-497e-b896-c50ca517aa75	3a15e4de-589b-450d-93d1-a19b0c7bdb28	2025-06-27	\N	\N	\N	153.840000	\N	GENERATED	2025-11-04 12:45:12.655199+01
c3e4da23-928f-41b6-b4ee-d1b959e90599	3a15e4de-589b-450d-93d1-a19b0c7bdb28	2025-06-28	\N	\N	\N	152.930000	\N	GENERATED	2025-11-04 12:45:12.655811+01
ca0558f7-7b86-4082-8adb-d60a5a6c6c6c	3a15e4de-589b-450d-93d1-a19b0c7bdb28	2025-06-29	\N	\N	\N	152.300000	\N	GENERATED	2025-11-04 12:45:12.656504+01
4ce32446-3257-4c8e-962b-5a56684fd1f8	3a15e4de-589b-450d-93d1-a19b0c7bdb28	2025-06-30	\N	\N	\N	152.790000	\N	GENERATED	2025-11-04 12:45:12.657112+01
8575e04b-4c47-41ea-be59-2c48c10a37d5	3a15e4de-589b-450d-93d1-a19b0c7bdb28	2025-07-01	\N	\N	\N	151.630000	\N	GENERATED	2025-11-04 12:45:12.657727+01
23187c9f-fb91-4e20-94e1-bfc216937533	3a15e4de-589b-450d-93d1-a19b0c7bdb28	2025-07-02	\N	\N	\N	151.800000	\N	GENERATED	2025-11-04 12:45:12.658458+01
c5ed667f-49d5-4cfe-a938-e0b07dff669b	3a15e4de-589b-450d-93d1-a19b0c7bdb28	2025-07-03	\N	\N	\N	152.110000	\N	GENERATED	2025-11-04 12:45:12.659407+01
af6f6dec-2d39-4fa4-b807-633b3e89296b	3a15e4de-589b-450d-93d1-a19b0c7bdb28	2025-07-04	\N	\N	\N	153.180000	\N	GENERATED	2025-11-04 12:45:12.660213+01
c07b02b3-0216-4b87-b664-26a715f83228	3a15e4de-589b-450d-93d1-a19b0c7bdb28	2025-07-05	\N	\N	\N	152.330000	\N	GENERATED	2025-11-04 12:45:12.660842+01
391a6ff3-97e5-47d4-bbc2-84fb6b87103d	3a15e4de-589b-450d-93d1-a19b0c7bdb28	2025-07-06	\N	\N	\N	154.110000	\N	GENERATED	2025-11-04 12:45:12.661471+01
34b3d5fa-cabe-490e-b5f8-a53c85d1f4f3	3a15e4de-589b-450d-93d1-a19b0c7bdb28	2025-07-07	\N	\N	\N	154.050000	\N	GENERATED	2025-11-04 12:45:12.662093+01
03ae545d-3e69-4a4b-898d-c2368c704b52	3a15e4de-589b-450d-93d1-a19b0c7bdb28	2025-07-08	\N	\N	\N	151.720000	\N	GENERATED	2025-11-04 12:45:12.662743+01
98e9c7f6-f05b-41d9-8733-4bc3b6b74544	3a15e4de-589b-450d-93d1-a19b0c7bdb28	2025-07-09	\N	\N	\N	153.660000	\N	GENERATED	2025-11-04 12:45:12.663362+01
21fbd224-7064-488a-a7fd-6afb216cb6a2	3a15e4de-589b-450d-93d1-a19b0c7bdb28	2025-07-10	\N	\N	\N	151.730000	\N	GENERATED	2025-11-04 12:45:12.663975+01
20d73ff8-40c6-409c-8a2b-4818a930837e	3a15e4de-589b-450d-93d1-a19b0c7bdb28	2025-07-11	\N	\N	\N	154.220000	\N	GENERATED	2025-11-04 12:45:12.664597+01
8eb3577e-b8e1-403e-bfc5-fc42131546a1	3a15e4de-589b-450d-93d1-a19b0c7bdb28	2025-07-12	\N	\N	\N	152.200000	\N	GENERATED	2025-11-04 12:45:12.665204+01
13124338-249d-41d1-8f07-b8d2ca418fb7	3a15e4de-589b-450d-93d1-a19b0c7bdb28	2025-07-13	\N	\N	\N	152.310000	\N	GENERATED	2025-11-04 12:45:12.665811+01
e4afa5e3-204f-4899-a2b8-92cb8c88bcf9	3a15e4de-589b-450d-93d1-a19b0c7bdb28	2025-07-14	\N	\N	\N	153.480000	\N	GENERATED	2025-11-04 12:45:12.6666+01
ef9338b1-b091-490e-a2b1-8dfa58b8a9db	3a15e4de-589b-450d-93d1-a19b0c7bdb28	2025-07-15	\N	\N	\N	151.660000	\N	GENERATED	2025-11-04 12:45:12.667217+01
ce4e97fb-2df3-47ac-bbec-4ee5c1d89b66	3a15e4de-589b-450d-93d1-a19b0c7bdb28	2025-07-16	\N	\N	\N	152.220000	\N	GENERATED	2025-11-04 12:45:12.667827+01
46c502fb-2a4d-42c2-a557-780945254762	3a15e4de-589b-450d-93d1-a19b0c7bdb28	2025-07-17	\N	\N	\N	152.570000	\N	GENERATED	2025-11-04 12:45:12.668444+01
d5b0f31e-b795-4f16-9184-bc7dddd2389a	3a15e4de-589b-450d-93d1-a19b0c7bdb28	2025-07-18	\N	\N	\N	152.750000	\N	GENERATED	2025-11-04 12:45:12.669056+01
62167640-2d30-4873-bb5e-069b47690155	3a15e4de-589b-450d-93d1-a19b0c7bdb28	2025-07-19	\N	\N	\N	152.010000	\N	GENERATED	2025-11-04 12:45:12.669682+01
a4b3bf4c-cf2d-4ada-a172-237aa177f2c6	3a15e4de-589b-450d-93d1-a19b0c7bdb28	2025-07-20	\N	\N	\N	152.030000	\N	GENERATED	2025-11-04 12:45:12.670314+01
2dab809e-29d9-4267-9d85-2b8b0c9e09db	3a15e4de-589b-450d-93d1-a19b0c7bdb28	2025-07-21	\N	\N	\N	154.660000	\N	GENERATED	2025-11-04 12:45:12.670923+01
d723f532-869b-4638-bd0f-eb0a1abc94a0	3a15e4de-589b-450d-93d1-a19b0c7bdb28	2025-07-22	\N	\N	\N	151.870000	\N	GENERATED	2025-11-04 12:45:12.671541+01
ff7eeb04-89f2-49cd-9bdb-e24f4002f687	3a15e4de-589b-450d-93d1-a19b0c7bdb28	2025-07-23	\N	\N	\N	153.110000	\N	GENERATED	2025-11-04 12:45:12.672144+01
46b78853-9802-46ac-99e7-a5a1881b41dd	3a15e4de-589b-450d-93d1-a19b0c7bdb28	2025-07-24	\N	\N	\N	153.970000	\N	GENERATED	2025-11-04 12:45:12.672922+01
bcf58962-6042-40d2-a241-46a26dd1d497	3a15e4de-589b-450d-93d1-a19b0c7bdb28	2025-07-25	\N	\N	\N	153.530000	\N	GENERATED	2025-11-04 12:45:12.673732+01
883404a1-29b0-4daa-8470-60be6986255c	3a15e4de-589b-450d-93d1-a19b0c7bdb28	2025-07-26	\N	\N	\N	153.680000	\N	GENERATED	2025-11-04 12:45:12.674705+01
46e68d4e-8043-4c93-be63-6d4501edff68	3a15e4de-589b-450d-93d1-a19b0c7bdb28	2025-07-27	\N	\N	\N	152.560000	\N	GENERATED	2025-11-04 12:45:12.675353+01
ae291a23-93b2-4c49-9756-1bc35e38718c	3a15e4de-589b-450d-93d1-a19b0c7bdb28	2025-07-28	\N	\N	\N	153.300000	\N	GENERATED	2025-11-04 12:45:12.675977+01
61e6b3b5-5463-4139-ab78-60f91a170096	3a15e4de-589b-450d-93d1-a19b0c7bdb28	2025-07-29	\N	\N	\N	152.780000	\N	GENERATED	2025-11-04 12:45:12.676702+01
0b34e0b9-fb17-405e-aaa5-c80a58f99102	3a15e4de-589b-450d-93d1-a19b0c7bdb28	2025-07-30	\N	\N	\N	152.910000	\N	GENERATED	2025-11-04 12:45:12.677374+01
01ea167f-597b-4438-b030-ba58b3b91487	3a15e4de-589b-450d-93d1-a19b0c7bdb28	2025-07-31	\N	\N	\N	154.730000	\N	GENERATED	2025-11-04 12:45:12.677994+01
3155aadc-d308-491a-b4d3-a0c21d787b30	3a15e4de-589b-450d-93d1-a19b0c7bdb28	2025-08-01	\N	\N	\N	152.820000	\N	GENERATED	2025-11-04 12:45:12.678641+01
a70b0cbd-cad6-422f-99b5-2d3d12633a69	3a15e4de-589b-450d-93d1-a19b0c7bdb28	2025-08-02	\N	\N	\N	155.040000	\N	GENERATED	2025-11-04 12:45:12.679436+01
37e6c2dd-5a26-450b-b4ff-0f6b1d31f9e3	3a15e4de-589b-450d-93d1-a19b0c7bdb28	2025-08-03	\N	\N	\N	154.940000	\N	GENERATED	2025-11-04 12:45:12.680047+01
5816b13e-123b-4055-a33f-9719067f20a9	3a15e4de-589b-450d-93d1-a19b0c7bdb28	2025-08-04	\N	\N	\N	154.580000	\N	GENERATED	2025-11-04 12:45:12.680661+01
3040a885-9d3a-428c-a4f6-decc1354caff	3a15e4de-589b-450d-93d1-a19b0c7bdb28	2025-08-05	\N	\N	\N	155.130000	\N	GENERATED	2025-11-04 12:45:12.681279+01
b561a255-25cc-413c-849b-afba97a7cadc	3a15e4de-589b-450d-93d1-a19b0c7bdb28	2025-08-06	\N	\N	\N	154.710000	\N	GENERATED	2025-11-04 12:45:12.681879+01
6ffb0d1e-b8f3-43e3-b5c5-2568bb87bd63	3a15e4de-589b-450d-93d1-a19b0c7bdb28	2025-08-07	\N	\N	\N	154.330000	\N	GENERATED	2025-11-04 12:45:12.68249+01
0bb09836-227b-4ddc-95d9-6a4b65d96e12	3a15e4de-589b-450d-93d1-a19b0c7bdb28	2025-08-08	\N	\N	\N	153.210000	\N	GENERATED	2025-11-04 12:45:12.683097+01
1716f289-cc19-4460-a52a-2588ca189b30	3a15e4de-589b-450d-93d1-a19b0c7bdb28	2025-08-09	\N	\N	\N	154.480000	\N	GENERATED	2025-11-04 12:45:12.683732+01
3c80d442-1bd6-4be6-bae9-cfc43de20aff	3a15e4de-589b-450d-93d1-a19b0c7bdb28	2025-08-10	\N	\N	\N	155.270000	\N	GENERATED	2025-11-04 12:45:12.684363+01
52c16923-89a2-4243-ad1b-3707b43e3d77	3a15e4de-589b-450d-93d1-a19b0c7bdb28	2025-08-11	\N	\N	\N	154.220000	\N	GENERATED	2025-11-04 12:45:12.684973+01
ce8c358c-e868-4623-938f-d9be05edbf78	3a15e4de-589b-450d-93d1-a19b0c7bdb28	2025-08-12	\N	\N	\N	153.410000	\N	GENERATED	2025-11-04 12:45:12.68575+01
17cfdb51-38b2-4b5c-aa84-bb00b53220b9	3a15e4de-589b-450d-93d1-a19b0c7bdb28	2025-08-13	\N	\N	\N	154.490000	\N	GENERATED	2025-11-04 12:45:12.686363+01
f78c16e8-42f5-4848-8f3a-44ec37982fe1	3a15e4de-589b-450d-93d1-a19b0c7bdb28	2025-08-14	\N	\N	\N	154.490000	\N	GENERATED	2025-11-04 12:45:12.686998+01
273f4cc9-f378-4815-a338-c9f4d389d4ba	3a15e4de-589b-450d-93d1-a19b0c7bdb28	2025-08-15	\N	\N	\N	155.000000	\N	GENERATED	2025-11-04 12:45:12.687614+01
0b95da35-96c3-4057-827e-2cdeb04fe64f	3a15e4de-589b-450d-93d1-a19b0c7bdb28	2025-08-16	\N	\N	\N	155.190000	\N	GENERATED	2025-11-04 12:45:12.688231+01
29d929e6-fc8f-48e4-aece-9998eb421495	3a15e4de-589b-450d-93d1-a19b0c7bdb28	2025-08-17	\N	\N	\N	152.810000	\N	GENERATED	2025-11-04 12:45:12.688974+01
43e1a70f-5597-4a50-b612-5041fd4550ad	3a15e4de-589b-450d-93d1-a19b0c7bdb28	2025-08-18	\N	\N	\N	152.790000	\N	GENERATED	2025-11-04 12:45:12.689973+01
ab8f7582-75f5-4610-bed2-4c8e9f7b1616	3a15e4de-589b-450d-93d1-a19b0c7bdb28	2025-08-19	\N	\N	\N	155.010000	\N	GENERATED	2025-11-04 12:45:12.690629+01
56325aaa-bf02-4786-99b4-08b0e0f1dba5	3a15e4de-589b-450d-93d1-a19b0c7bdb28	2025-08-20	\N	\N	\N	155.180000	\N	GENERATED	2025-11-04 12:45:12.691247+01
1d2ad39b-bc47-490a-9d1b-2b2079fd5bec	3a15e4de-589b-450d-93d1-a19b0c7bdb28	2025-08-21	\N	\N	\N	154.010000	\N	GENERATED	2025-11-04 12:45:12.692122+01
b621eff7-99da-4f95-af42-207fdbfdf4d3	3a15e4de-589b-450d-93d1-a19b0c7bdb28	2025-08-22	\N	\N	\N	153.260000	\N	GENERATED	2025-11-04 12:45:12.693056+01
91a88604-7293-46d0-b595-03db91b07527	3a15e4de-589b-450d-93d1-a19b0c7bdb28	2025-08-23	\N	\N	\N	153.470000	\N	GENERATED	2025-11-04 12:45:12.693692+01
75e7f018-7d50-40c3-97e2-3a7583dd4d41	3a15e4de-589b-450d-93d1-a19b0c7bdb28	2025-08-24	\N	\N	\N	154.240000	\N	GENERATED	2025-11-04 12:45:12.694318+01
6f2de948-c0c1-4d1e-84b6-f7b9a146d281	3a15e4de-589b-450d-93d1-a19b0c7bdb28	2025-08-25	\N	\N	\N	152.900000	\N	GENERATED	2025-11-04 12:45:12.69493+01
e6900e9c-bbee-4d34-af12-722a43ec9c59	3a15e4de-589b-450d-93d1-a19b0c7bdb28	2025-08-26	\N	\N	\N	153.160000	\N	GENERATED	2025-11-04 12:45:12.695534+01
b6f838f5-e124-44bd-acf9-985490a2190a	3a15e4de-589b-450d-93d1-a19b0c7bdb28	2025-08-27	\N	\N	\N	155.640000	\N	GENERATED	2025-11-04 12:45:12.696152+01
75420010-8426-47ff-9096-06327dabff9d	3a15e4de-589b-450d-93d1-a19b0c7bdb28	2025-08-28	\N	\N	\N	155.420000	\N	GENERATED	2025-11-04 12:45:12.696877+01
5a5a23ed-d35c-4202-8f52-3d1bd6c008fd	3a15e4de-589b-450d-93d1-a19b0c7bdb28	2025-08-29	\N	\N	\N	154.890000	\N	GENERATED	2025-11-04 12:45:12.697539+01
8b2141b2-aa5e-4635-aee5-9f6fef1a761e	3a15e4de-589b-450d-93d1-a19b0c7bdb28	2025-08-30	\N	\N	\N	153.230000	\N	GENERATED	2025-11-04 12:45:12.69826+01
efac4200-8a62-4643-bc2c-502433d1d69e	3a15e4de-589b-450d-93d1-a19b0c7bdb28	2025-08-31	\N	\N	\N	153.660000	\N	GENERATED	2025-11-04 12:45:12.698882+01
676a42d3-c0c2-4bed-830d-96d294f6811d	3a15e4de-589b-450d-93d1-a19b0c7bdb28	2025-09-01	\N	\N	\N	154.920000	\N	GENERATED	2025-11-04 12:45:12.699514+01
b6f3e80e-a2c6-478a-b787-cd8f9cf6408f	3a15e4de-589b-450d-93d1-a19b0c7bdb28	2025-09-02	\N	\N	\N	155.880000	\N	GENERATED	2025-11-04 12:45:12.700136+01
7fb1a0d3-25db-4720-9239-21ad0bb79135	3a15e4de-589b-450d-93d1-a19b0c7bdb28	2025-09-03	\N	\N	\N	153.730000	\N	GENERATED	2025-11-04 12:45:12.700738+01
b250f433-00cb-4b63-9e0f-8c97dd78661e	3a15e4de-589b-450d-93d1-a19b0c7bdb28	2025-09-04	\N	\N	\N	153.360000	\N	GENERATED	2025-11-04 12:45:12.701357+01
3b372719-2da2-4632-9044-0d5fc1e5c4ec	3a15e4de-589b-450d-93d1-a19b0c7bdb28	2025-09-05	\N	\N	\N	153.840000	\N	GENERATED	2025-11-04 12:45:12.701961+01
ba1cbf67-915f-429e-8454-82946e06f660	3a15e4de-589b-450d-93d1-a19b0c7bdb28	2025-09-06	\N	\N	\N	153.400000	\N	GENERATED	2025-11-04 12:45:12.702575+01
4c2502a6-700b-44c2-b0cf-388e429d32b9	3a15e4de-589b-450d-93d1-a19b0c7bdb28	2025-09-07	\N	\N	\N	155.910000	\N	GENERATED	2025-11-04 12:45:12.703183+01
f966556a-64da-4ba5-87d7-2a55da922cb4	3a15e4de-589b-450d-93d1-a19b0c7bdb28	2025-09-08	\N	\N	\N	154.870000	\N	GENERATED	2025-11-04 12:45:12.703796+01
c92c58bc-7cff-445b-a79f-c46b9684931c	3a15e4de-589b-450d-93d1-a19b0c7bdb28	2025-09-09	\N	\N	\N	155.180000	\N	GENERATED	2025-11-04 12:45:12.704863+01
923ccc85-b942-4851-9b75-f6245bafacda	3a15e4de-589b-450d-93d1-a19b0c7bdb28	2025-09-10	\N	\N	\N	154.840000	\N	GENERATED	2025-11-04 12:45:12.705901+01
63ca8174-817d-4be6-a090-23bd77b13a7c	3a15e4de-589b-450d-93d1-a19b0c7bdb28	2025-09-11	\N	\N	\N	155.070000	\N	GENERATED	2025-11-04 12:45:12.706589+01
0918b46d-9685-4019-997a-d37708875243	3a15e4de-589b-450d-93d1-a19b0c7bdb28	2025-09-12	\N	\N	\N	155.220000	\N	GENERATED	2025-11-04 12:45:12.707219+01
8d746d37-5b11-44f7-b9fb-ec82ab95b738	3a15e4de-589b-450d-93d1-a19b0c7bdb28	2025-09-13	\N	\N	\N	155.210000	\N	GENERATED	2025-11-04 12:45:12.707886+01
762454c5-e5c1-43cd-a07a-9098f027891c	3a15e4de-589b-450d-93d1-a19b0c7bdb28	2025-09-14	\N	\N	\N	153.940000	\N	GENERATED	2025-11-04 12:45:12.708513+01
7a7a1231-be5a-43ce-bfda-67b2074333a0	3a15e4de-589b-450d-93d1-a19b0c7bdb28	2025-09-15	\N	\N	\N	154.920000	\N	GENERATED	2025-11-04 12:45:12.709136+01
a357795a-08a6-4f36-a93c-15d520684973	3a15e4de-589b-450d-93d1-a19b0c7bdb28	2025-09-16	\N	\N	\N	154.530000	\N	GENERATED	2025-11-04 12:45:12.709778+01
dfe6a949-685f-46a3-8155-2af7a178423a	3a15e4de-589b-450d-93d1-a19b0c7bdb28	2025-09-17	\N	\N	\N	154.900000	\N	GENERATED	2025-11-04 12:45:12.710386+01
771b7bdf-3901-483c-b01e-c6999b596aff	3a15e4de-589b-450d-93d1-a19b0c7bdb28	2025-09-18	\N	\N	\N	156.430000	\N	GENERATED	2025-11-04 12:45:12.711006+01
66cadc66-8830-46e7-9bb2-5eb1f731d93a	3a15e4de-589b-450d-93d1-a19b0c7bdb28	2025-09-19	\N	\N	\N	155.520000	\N	GENERATED	2025-11-04 12:45:12.711619+01
9c14486a-c969-4b3c-9292-5fab16f71840	3a15e4de-589b-450d-93d1-a19b0c7bdb28	2025-09-20	\N	\N	\N	155.710000	\N	GENERATED	2025-11-04 12:45:12.712256+01
f00df217-afc0-4e60-9627-4ef096701b1e	3a15e4de-589b-450d-93d1-a19b0c7bdb28	2025-09-21	\N	\N	\N	154.530000	\N	GENERATED	2025-11-04 12:45:12.712886+01
e2d950ac-0bde-401e-82e1-d57f98fa2c10	3a15e4de-589b-450d-93d1-a19b0c7bdb28	2025-09-22	\N	\N	\N	156.020000	\N	GENERATED	2025-11-04 12:45:12.713505+01
3b700a2d-b0d6-4bc4-8253-822b69099aac	3a15e4de-589b-450d-93d1-a19b0c7bdb28	2025-09-23	\N	\N	\N	155.020000	\N	GENERATED	2025-11-04 12:45:12.714112+01
abfecb72-f010-400b-95c3-1f3c78bd6725	3a15e4de-589b-450d-93d1-a19b0c7bdb28	2025-09-24	\N	\N	\N	156.710000	\N	GENERATED	2025-11-04 12:45:12.714736+01
c1b4ae76-bff8-4ee9-8cf1-04b6274df923	3a15e4de-589b-450d-93d1-a19b0c7bdb28	2025-09-25	\N	\N	\N	154.450000	\N	GENERATED	2025-11-04 12:45:12.715341+01
df9ba9cb-63fc-4c6d-aee7-4393846a7cc9	3a15e4de-589b-450d-93d1-a19b0c7bdb28	2025-09-26	\N	\N	\N	154.170000	\N	GENERATED	2025-11-04 12:45:12.715985+01
9e3d4f2a-d7bd-4bb3-a7f9-7dc9ea2fcb44	3a15e4de-589b-450d-93d1-a19b0c7bdb28	2025-09-27	\N	\N	\N	155.800000	\N	GENERATED	2025-11-04 12:45:12.716675+01
c1b3a50f-6691-413f-8d75-768f799ae17d	3a15e4de-589b-450d-93d1-a19b0c7bdb28	2025-09-28	\N	\N	\N	155.450000	\N	GENERATED	2025-11-04 12:45:12.717285+01
7409a7ee-0f48-4e2c-aeca-febbb4f7ff98	3a15e4de-589b-450d-93d1-a19b0c7bdb28	2025-09-29	\N	\N	\N	156.900000	\N	GENERATED	2025-11-04 12:45:12.71791+01
eb5cef14-432f-45be-a71f-f6a3e595a45f	3a15e4de-589b-450d-93d1-a19b0c7bdb28	2025-09-30	\N	\N	\N	154.470000	\N	GENERATED	2025-11-04 12:45:12.71852+01
e10d1132-2729-4216-bc81-0a9728779f1a	3a15e4de-589b-450d-93d1-a19b0c7bdb28	2025-10-01	\N	\N	\N	154.610000	\N	GENERATED	2025-11-04 12:45:12.719134+01
1e05a869-6804-4fbc-989f-4d206d501ba9	3a15e4de-589b-450d-93d1-a19b0c7bdb28	2025-10-02	\N	\N	\N	154.260000	\N	GENERATED	2025-11-04 12:45:12.719906+01
0c65d602-223d-4256-a128-01a23e3a36c1	3a15e4de-589b-450d-93d1-a19b0c7bdb28	2025-10-03	\N	\N	\N	156.960000	\N	GENERATED	2025-11-04 12:45:12.720564+01
0f00fa0e-f7f6-49f5-9003-d549ad9b95ca	3a15e4de-589b-450d-93d1-a19b0c7bdb28	2025-10-04	\N	\N	\N	154.720000	\N	GENERATED	2025-11-04 12:45:12.721182+01
901808de-2315-4439-a668-6491ed5481b0	3a15e4de-589b-450d-93d1-a19b0c7bdb28	2025-10-05	\N	\N	\N	156.220000	\N	GENERATED	2025-11-04 12:45:12.721848+01
45aab873-43fe-46b9-a9c9-997cd1a6db8b	3a15e4de-589b-450d-93d1-a19b0c7bdb28	2025-10-06	\N	\N	\N	155.300000	\N	GENERATED	2025-11-04 12:45:12.722457+01
e613e5f7-57b0-497b-b0a0-27cec1c57fc5	3a15e4de-589b-450d-93d1-a19b0c7bdb28	2025-10-07	\N	\N	\N	155.890000	\N	GENERATED	2025-11-04 12:45:12.723079+01
8d45e4b5-ed42-43c5-ba6a-e8a1a0a69a78	3a15e4de-589b-450d-93d1-a19b0c7bdb28	2025-10-08	\N	\N	\N	156.040000	\N	GENERATED	2025-11-04 12:45:12.723802+01
50f0a20c-9b58-4ca9-b662-bdf2fe86e32c	3a15e4de-589b-450d-93d1-a19b0c7bdb28	2025-10-09	\N	\N	\N	155.070000	\N	GENERATED	2025-11-04 12:45:12.724513+01
476c86bd-2179-481f-8108-8bd75998892c	3a15e4de-589b-450d-93d1-a19b0c7bdb28	2025-10-10	\N	\N	\N	155.980000	\N	GENERATED	2025-11-04 12:45:12.725157+01
679d395d-2cfd-455d-9cec-55b20008f60e	3a15e4de-589b-450d-93d1-a19b0c7bdb28	2025-10-11	\N	\N	\N	154.700000	\N	GENERATED	2025-11-04 12:45:12.725788+01
a87bc5ed-4fa8-4ae1-9c76-e594f3b9812c	3a15e4de-589b-450d-93d1-a19b0c7bdb28	2025-10-12	\N	\N	\N	157.310000	\N	GENERATED	2025-11-04 12:45:12.726401+01
9f0b3d24-36fc-48d0-80f0-e2785a6e481a	3a15e4de-589b-450d-93d1-a19b0c7bdb28	2025-10-13	\N	\N	\N	155.330000	\N	GENERATED	2025-11-04 12:45:12.727029+01
69fbdc80-f0f0-4130-b0b1-9cbd10ace87a	3a15e4de-589b-450d-93d1-a19b0c7bdb28	2025-10-14	\N	\N	\N	155.070000	\N	GENERATED	2025-11-04 12:45:12.727644+01
e689deb5-bf45-44e4-bca3-06365184624d	3a15e4de-589b-450d-93d1-a19b0c7bdb28	2025-10-15	\N	\N	\N	154.910000	\N	GENERATED	2025-11-04 12:45:12.728252+01
f5574679-d980-4cce-a030-b04fc7958984	3a15e4de-589b-450d-93d1-a19b0c7bdb28	2025-10-16	\N	\N	\N	156.750000	\N	GENERATED	2025-11-04 12:45:12.728875+01
5863b4e3-f132-4a5f-a734-8f870de23d7f	3a15e4de-589b-450d-93d1-a19b0c7bdb28	2025-10-17	\N	\N	\N	155.910000	\N	GENERATED	2025-11-04 12:45:12.729486+01
69d8906c-510e-408f-a417-2921136b7f7e	3a15e4de-589b-450d-93d1-a19b0c7bdb28	2025-10-18	\N	\N	\N	156.650000	\N	GENERATED	2025-11-04 12:45:12.730112+01
965624b9-e50b-4557-a23f-fcf8f8e02c81	3a15e4de-589b-450d-93d1-a19b0c7bdb28	2025-10-19	\N	\N	\N	156.330000	\N	GENERATED	2025-11-04 12:45:12.730732+01
43b2d6a4-a41f-4adb-ae05-90b8d7ba224a	3a15e4de-589b-450d-93d1-a19b0c7bdb28	2025-10-20	\N	\N	\N	157.440000	\N	GENERATED	2025-11-04 12:45:12.731342+01
c15b1a4f-5d09-4ec9-86aa-d71aee2d7c90	3a15e4de-589b-450d-93d1-a19b0c7bdb28	2025-10-21	\N	\N	\N	155.320000	\N	GENERATED	2025-11-04 12:45:12.73197+01
86a7be04-eda7-4c90-9d36-01ab65ca950f	3a15e4de-589b-450d-93d1-a19b0c7bdb28	2025-10-22	\N	\N	\N	155.120000	\N	GENERATED	2025-11-04 12:45:12.732578+01
9fa73d0e-191f-4645-b38a-96d73f83a4c9	3a15e4de-589b-450d-93d1-a19b0c7bdb28	2025-10-23	\N	\N	\N	156.730000	\N	GENERATED	2025-11-04 12:45:12.733196+01
a0de3897-2856-4ba8-8c6c-9eac78ff990d	3a15e4de-589b-450d-93d1-a19b0c7bdb28	2025-10-24	\N	\N	\N	156.890000	\N	GENERATED	2025-11-04 12:45:12.733807+01
74883225-2fcd-47fc-a6b9-26238cef49af	3a15e4de-589b-450d-93d1-a19b0c7bdb28	2025-10-25	\N	\N	\N	155.640000	\N	GENERATED	2025-11-04 12:45:12.734418+01
b24bb12f-3c60-436f-bf5c-50104dce6172	3a15e4de-589b-450d-93d1-a19b0c7bdb28	2025-10-26	\N	\N	\N	155.880000	\N	GENERATED	2025-11-04 12:45:12.73527+01
40bc76d7-0fae-4494-be4a-7d27c0423b44	3a15e4de-589b-450d-93d1-a19b0c7bdb28	2025-10-27	\N	\N	\N	155.390000	\N	GENERATED	2025-11-04 12:45:12.735919+01
d30cf765-f362-484e-a86a-4a8cb3896938	3a15e4de-589b-450d-93d1-a19b0c7bdb28	2025-10-28	\N	\N	\N	156.400000	\N	GENERATED	2025-11-04 12:45:12.736617+01
105a03aa-36df-44fe-a9b7-c58148e37b0e	3a15e4de-589b-450d-93d1-a19b0c7bdb28	2025-10-29	\N	\N	\N	157.320000	\N	GENERATED	2025-11-04 12:45:12.73726+01
c9c5e411-ee90-4a4f-a55d-9df50086a28c	3a15e4de-589b-450d-93d1-a19b0c7bdb28	2025-10-30	\N	\N	\N	157.340000	\N	GENERATED	2025-11-04 12:45:12.737884+01
6a0223f6-4201-4493-8e67-c2d854beaeea	3a15e4de-589b-450d-93d1-a19b0c7bdb28	2025-10-31	\N	\N	\N	157.010000	\N	GENERATED	2025-11-04 12:45:12.738499+01
e74dea4c-547a-4834-ab43-18974596c546	3a15e4de-589b-450d-93d1-a19b0c7bdb28	2025-11-01	\N	\N	\N	157.600000	\N	GENERATED	2025-11-04 12:45:12.739129+01
c4d384e0-c276-4d74-9a33-8378dcec4d2b	3a15e4de-589b-450d-93d1-a19b0c7bdb28	2025-11-02	\N	\N	\N	155.910000	\N	GENERATED	2025-11-04 12:45:12.739741+01
c2615a18-8b8e-42dd-b44c-f71789f311d1	3a15e4de-589b-450d-93d1-a19b0c7bdb28	2025-11-03	\N	\N	\N	155.690000	\N	GENERATED	2025-11-04 12:45:12.740354+01
6e2664de-5a46-43ff-b6b5-9ea336805231	b46bba4b-525d-483d-bf4e-f195bde3d6bc	2025-11-04	\N	\N	\N	624.500000	\N	MANUAL	2025-11-04 12:45:09.875565+01
d1857456-86b8-4793-ae3d-0733b7832396	0999dc6a-e6f9-4bbf-9bd2-30a25658de89	2025-11-05	170.679993	170.919998	170.279999	170.310000	268	YAHOO_FINANCE	2025-11-05 18:21:32.790038+01
5ff382d9-6a9e-4001-9aad-aa3a61eee20c	719121c9-908d-49b7-a047-23464f0960ab	2025-11-05	272.339996	275.390015	272.329987	274.830000	8139	YAHOO_FINANCE	2025-11-05 18:21:33.608787+01
0fb934c8-bbd5-44dd-9531-664865c9a7cf	8f706b9d-54ae-4ac7-8ce5-0ed005362d68	2025-11-05	91.269997	91.773399	91.199997	91.720000	13067	YAHOO_FINANCE	2025-11-05 18:21:34.205156+01
8f776c04-799b-48d4-9de6-dea9f194ef3c	b46bba4b-525d-483d-bf4e-f195bde3d6bc	2025-11-05	629.140015	634.130005	628.140015	634.130000	20778	YAHOO_FINANCE	2025-11-05 18:21:34.819692+01
7c94e198-392e-4b8f-a543-55cc376ed261	bcdff4ec-d4bf-419e-afb1-49beea99eeaf	2025-11-05	54.270000	54.509998	53.880001	54.070000	642874	YAHOO_FINANCE	2025-11-05 18:21:35.420871+01
2c785f82-75fa-43d2-b44a-e10768822190	bf3b3448-1ec3-4f29-87e3-7fc90bc83308	2025-11-05	102.779999	103.940002	102.779999	103.940000	3976	YAHOO_FINANCE	2025-11-05 18:21:36.028198+01
a43261ca-277c-4bc1-91ed-04f3f9a5c99d	c117885f-43f8-4be0-8df2-f6d30a200cca	2025-11-05	127.239998	128.240005	127.160004	128.240000	378052	YAHOO_FINANCE	2025-11-05 18:21:36.624275+01
a8a51dba-b1fe-4f14-9273-b259b894a422	c743dda6-c6ba-43c2-a14e-75490a1b06b0	2025-11-05	127.489998	127.519997	127.449997	127.450000	2156	YAHOO_FINANCE	2025-11-05 18:21:37.216136+01
0fd405e4-f1e6-424e-bf97-c9a618da937c	cc52fa73-bb3a-49ea-bb36-a0191f934e11	2025-11-05	382.709991	383.920013	381.000000	383.240000	40354	YAHOO_FINANCE	2025-11-05 18:21:37.816551+01
e0922c69-a746-423d-a82f-ede7eac4a0a4	d2c980bc-c787-4166-8e74-d074800bf867	2025-11-05	27.340000	27.340000	27.049999	27.055000	292189	YAHOO_FINANCE	2025-11-05 18:21:38.424053+01
e9015a9d-c0c2-4588-bf29-f0dbf3e421ce	e0534574-8100-43c6-a396-f954f8ac95be	2025-11-05	16.750000	16.823999	16.726900	16.796000	22624	YAHOO_FINANCE	2025-11-05 18:21:39.044046+01
4555b0f6-d690-4d47-baea-402b69201e83	fc48529f-7c1b-41f4-9975-fc576e2788bd	2025-11-05	5.556000	5.556000	5.556000	5.556000	\N	YAHOO_FINANCE	2025-11-05 18:21:39.840893+01
d6a03b76-a9d9-4410-86fc-c9bc196e2e12	fda2e7d3-54a5-4b6b-a504-48873da1c697	2025-11-05	16.660000	16.959999	16.655001	16.770000	450827	YAHOO_FINANCE	2025-11-05 18:21:40.46611+01
414ef587-2ef5-41fe-af2f-575fc063f361	bf3b3448-1ec3-4f29-87e3-7fc90bc83308	2025-11-06	89.919998	90.419998	89.120003	89.320000	14683	YAHOO_FINANCE	2025-11-06 10:04:11.682306+01
51aadf2b-568f-49d4-aea9-0b71778718b2	c117885f-43f8-4be0-8df2-f6d30a200cca	2025-11-06	111.169998	111.559998	110.599998	110.810000	131624	YAHOO_FINANCE	2025-11-06 10:04:12.277207+01
f09695e9-70f5-4fb4-93b7-37525d1c370e	cc52fa73-bb3a-49ea-bb36-a0191f934e11	2025-11-06	335.170013	336.040009	332.500000	332.820000	47520	YAHOO_FINANCE	2025-11-06 10:04:12.950657+01
dfd89278-6f8d-4059-b24c-7ceca9f81746	0999dc6a-e6f9-4bbf-9bd2-30a25658de89	2025-11-06	170.509995	170.520004	170.279999	170.520000	3932	YAHOO_FINANCE	2025-11-06 15:11:07.637885+01
ac06e151-a9a8-496d-a7e4-5abaeabf2c05	3a15e4de-589b-450d-93d1-a19b0c7bdb28	2025-11-06	147.610992	147.638000	147.610001	147.630000	61026	YAHOO_FINANCE	2025-11-06 15:30:39.718691+01
b7ba553c-498e-4ab1-926c-2206b86cdca0	719121c9-908d-49b7-a047-23464f0960ab	2025-11-06	274.350006	274.799988	273.299988	273.450000	11259	YAHOO_FINANCE	2025-11-06 15:30:40.481087+01
802b10dc-2f52-45a2-b4c0-0b2c494293ec	8f706b9d-54ae-4ac7-8ce5-0ed005362d68	2025-11-06	79.709999	80.010002	79.309998	79.660000	1059	YAHOO_FINANCE	2025-11-06 10:04:10.397314+01
1cc23088-507c-4025-bb33-02ef53780d5a	b46bba4b-525d-483d-bf4e-f195bde3d6bc	2025-11-06	629.950012	632.330017	626.969971	626.970000	9280	YAHOO_FINANCE	2025-11-06 10:04:11.00248+01
4d0b770d-d129-411b-9c8d-5313b22ffebe	bcdff4ec-d4bf-419e-afb1-49beea99eeaf	2025-11-06	53.709999	53.779999	52.950001	53.100000	297842	YAHOO_FINANCE	2025-11-06 15:30:42.315826+01
239e5e3e-6699-4fd0-b957-e3dbfce100d6	c743dda6-c6ba-43c2-a14e-75490a1b06b0	2025-11-06	127.510002	127.519997	127.459999	127.520000	5840	YAHOO_FINANCE	2025-11-06 15:11:11.037646+01
b3c6484f-315f-4689-884b-7130cec33ba7	d2c980bc-c787-4166-8e74-d074800bf867	2025-11-06	23.514999	23.559999	23.475000	23.545000	144447	YAHOO_FINANCE	2025-11-06 10:04:13.546585+01
4c205b8f-03b6-4396-b7d8-dd07eb28d582	e0534574-8100-43c6-a396-f954f8ac95be	2025-11-06	19.170000	19.238001	19.142000	19.146000	32274	YAHOO_FINANCE	2025-11-06 10:04:14.154944+01
8f8f6798-1177-4361-bc53-f71a06bd9f37	f1daeb66-3038-40d7-beea-ba11dd317ae9	2025-11-06	215.250000	216.050003	214.199997	214.300000	4539	YAHOO_FINANCE	2025-11-06 15:11:13.550712+01
100800c7-2b9b-45d6-8517-5e6449115869	fc48529f-7c1b-41f4-9975-fc576e2788bd	2025-11-06	5.643000	5.655000	5.612000	5.622000	255666	YAHOO_FINANCE	2025-11-06 15:30:47.462875+01
19ee87bb-f5ae-4172-91bb-4c195c3b80b6	fda2e7d3-54a5-4b6b-a504-48873da1c697	2025-11-06	16.760000	17.049999	16.635000	16.720000	234380	YAHOO_FINANCE	2025-11-06 10:04:15.552186+01
36b658f7-598a-492b-9e26-d7d81d2ecf45	0999dc6a-e6f9-4bbf-9bd2-30a25658de89	2025-11-08	170.229996	170.429993	170.149994	170.290000	4514	YAHOO_FINANCE	2025-11-08 18:51:31.921749+01
df603d02-5cde-4b3d-a5c3-0dc93117f040	3a15e4de-589b-450d-93d1-a19b0c7bdb28	2025-11-08	147.630005	147.658997	147.617996	147.659000	116622	YAHOO_FINANCE	2025-11-08 18:51:32.530591+01
455efe11-15e0-48ea-a447-b6bcb0949c3b	719121c9-908d-49b7-a047-23464f0960ab	2025-11-08	273.700012	273.700012	270.600006	271.450000	9182	YAHOO_FINANCE	2025-11-08 18:51:33.214475+01
fa293b72-fd4c-48e2-9ec4-c02eb5d04edb	8f706b9d-54ae-4ac7-8ce5-0ed005362d68	2025-11-08	79.230003	79.230003	78.070000	77.950000	1926	YAHOO_FINANCE	2025-11-08 18:51:33.894127+01
a439f3cf-2105-4515-bc69-d433bc7398e6	b46bba4b-525d-483d-bf4e-f195bde3d6bc	2025-11-08	625.500000	625.799988	613.710022	614.200000	30483	YAHOO_FINANCE	2025-11-08 18:51:34.501813+01
bd4d9e9f-3368-4328-a7e5-edf30ba94af0	bcdff4ec-d4bf-419e-afb1-49beea99eeaf	2025-11-08	52.330002	52.549999	51.610001	52.040000	534655	YAHOO_FINANCE	2025-11-08 18:51:35.101867+01
cbb0cc5f-4547-499e-85f3-225d6d0660e3	bf3b3448-1ec3-4f29-87e3-7fc90bc83308	2025-11-08	88.790001	88.790001	86.440002	86.600000	25208	YAHOO_FINANCE	2025-11-08 18:51:35.699562+01
5e04b15a-0ac8-4cc9-8794-ecf824458f2b	c117885f-43f8-4be0-8df2-f6d30a200cca	2025-11-08	110.470001	110.519997	108.629997	108.730000	210173	YAHOO_FINANCE	2025-11-08 18:51:36.36282+01
76848fdc-8ccf-4b58-b692-822017be52be	c743dda6-c6ba-43c2-a14e-75490a1b06b0	2025-11-08	127.550003	127.550003	127.459999	127.490000	3285	YAHOO_FINANCE	2025-11-08 18:51:36.984427+01
eec49d18-00c1-4bdb-aded-ea35fff1ac3c	cc52fa73-bb3a-49ea-bb36-a0191f934e11	2025-11-08	334.529999	334.850006	331.339996	333.950000	22455	YAHOO_FINANCE	2025-11-08 18:51:37.653292+01
d5bcff76-969e-451e-9d82-a2333e2a555a	d2c980bc-c787-4166-8e74-d074800bf867	2025-11-08	23.520000	23.520000	23.434999	23.465000	3033	YAHOO_FINANCE	2025-11-08 18:51:38.262847+01
f02b2441-7430-4150-8f36-c9509856dd03	e0534574-8100-43c6-a396-f954f8ac95be	2025-11-08	19.125999	19.125999	18.908001	18.920000	85499	YAHOO_FINANCE	2025-11-08 18:51:38.862747+01
844765ef-531f-411a-a3f0-46f413b2840f	f1daeb66-3038-40d7-beea-ba11dd317ae9	2025-11-08	214.399994	214.649994	211.699997	212.100000	5329	YAHOO_FINANCE	2025-11-08 18:51:39.474+01
0d9265f2-3d89-4490-8b4a-a3ae21d24311	fc48529f-7c1b-41f4-9975-fc576e2788bd	2025-11-08	5.564000	5.568000	5.481000	5.501000	705595	YAHOO_FINANCE	2025-11-08 18:51:40.071943+01
8af7fe1c-8d75-4b05-bba9-22b5ae019450	fda2e7d3-54a5-4b6b-a504-48873da1c697	2025-11-08	16.639999	16.860001	16.450001	16.550000	1404300	YAHOO_FINANCE	2025-11-08 18:51:40.713772+01
5c9cfaa3-3815-4941-85cb-5998fde2187a	0999dc6a-e6f9-4bbf-9bd2-30a25658de89	2025-11-15	170.169998	170.389999	170.000000	170.030000	3549	YAHOO_FINANCE	2025-11-15 19:39:25.34491+01
4fcd5b45-9db0-4164-889e-50cd85140481	3a15e4de-589b-450d-93d1-a19b0c7bdb28	2025-11-15	147.679001	147.710007	147.675995	147.710000	84223	YAHOO_FINANCE	2025-11-15 19:39:25.928805+01
be68d676-2a61-4634-97f5-57d76498d764	719121c9-908d-49b7-a047-23464f0960ab	2025-11-15	277.049988	277.250000	273.899994	276.400000	29157	YAHOO_FINANCE	2025-11-15 19:39:26.50003+01
0dbc19f8-f4f1-4072-b768-74baca4c10a1	8f706b9d-54ae-4ac7-8ce5-0ed005362d68	2025-11-15	79.099998	79.129997	78.139999	79.350000	2724	YAHOO_FINANCE	2025-11-15 19:39:27.067811+01
43a23b33-4867-42f2-a253-db3bb3bdf6bc	b46bba4b-525d-483d-bf4e-f195bde3d6bc	2025-11-15	618.500000	622.859985	611.690002	622.070000	36339	YAHOO_FINANCE	2025-11-15 19:39:27.650893+01
e9db24fb-3da3-4269-91f1-269f0dd1214d	bcdff4ec-d4bf-419e-afb1-49beea99eeaf	2025-11-15	51.770000	52.290001	50.880001	52.160000	467932	YAHOO_FINANCE	2025-11-15 19:39:28.298712+01
2ecc132b-7229-42df-8091-cf331bb13d2b	bf3b3448-1ec3-4f29-87e3-7fc90bc83308	2025-11-15	86.849998	87.940002	85.599998	87.770000	39223	YAHOO_FINANCE	2025-11-15 19:39:28.871019+01
61366a1f-0072-4f3d-88dd-3d155d414e0b	c117885f-43f8-4be0-8df2-f6d30a200cca	2025-11-15	109.680000	110.349998	108.519997	110.230000	296037	YAHOO_FINANCE	2025-11-15 19:39:29.447458+01
2746c691-b3bd-44e8-aedb-8a1dc5e9711f	c743dda6-c6ba-43c2-a14e-75490a1b06b0	2025-11-15	127.470001	127.519997	127.419998	127.480000	4814	YAHOO_FINANCE	2025-11-15 19:39:30.102283+01
3735e323-5b1c-4aae-8121-7b04cbb5e6f7	cc52fa73-bb3a-49ea-bb36-a0191f934e11	2025-11-15	345.890015	346.380005	333.679993	339.560000	265034	YAHOO_FINANCE	2025-11-15 19:39:30.677609+01
e7939236-2184-4f41-b826-ca772af31dc7	d2c980bc-c787-4166-8e74-d074800bf867	2025-11-15	23.305000	23.370001	23.305000	23.320000	6250	YAHOO_FINANCE	2025-11-15 19:39:31.250344+01
d4445957-644d-448e-9b53-5f0a93a37f53	e0534574-8100-43c6-a396-f954f8ac95be	2025-11-15	19.086000	19.219999	19.014000	19.220000	104087	YAHOO_FINANCE	2025-11-15 19:39:31.827217+01
2ebbb614-b107-4822-9a12-543e6f7a92d3	f1daeb66-3038-40d7-beea-ba11dd317ae9	2025-11-15	217.350006	217.500000	214.649994	216.900000	7340	YAHOO_FINANCE	2025-11-15 19:39:32.416315+01
1c725c3c-d428-480c-b92e-80b5a6101077	fc48529f-7c1b-41f4-9975-fc576e2788bd	2025-11-15	5.551000	5.587000	5.505000	5.582000	825598	YAHOO_FINANCE	2025-11-15 19:39:32.98634+01
d50348b5-df6e-491a-b535-31a9f618d163	fda2e7d3-54a5-4b6b-a504-48873da1c697	2025-11-15	16.500000	16.730000	16.400000	16.490000	1511300	YAHOO_FINANCE	2025-11-15 19:39:33.596384+01
\.


--
-- TOC entry 5421 (class 0 OID 100110)
-- Dependencies: 223
-- Data for Name: target_allocations; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.target_allocations (target_id, portfolio_id, allocation_name, target_azionario, target_obbligazionario, target_monetario, target_oro, target_crypto, is_active, created_at, updated_at) FROM stdin;
\.


--
-- TOC entry 5417 (class 0 OID 100027)
-- Dependencies: 219
-- Data for Name: transactions; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.transactions (transaction_id, portfolio_id, asset_id, transaction_type, transaction_date, settlement_date, quantity, price_per_share, total_amount, commission, fees, taxes, currency, exchange_rate, amount_in_base_currency, order_id, notes, created_at, updated_at) FROM stdin;
46fd74d9-1f0d-43cf-aa27-df38bbfaf274	a5938c95-ba8e-46f6-98f2-4e670ba3b2a4	cc52fa73-bb3a-49ea-bb36-a0191f934e11	BUY	2025-11-04	\N	9.000000	334.895560	3014.06	5.72	0.00	0.00	EUR	1.000000	3014.06	\N	Importato da Excel: GLDFIXPM/SOURCE 00	2025-11-05 12:35:29.892777+01	2025-11-05 12:35:29.892777+01
f525b5bc-e519-4ea4-a1f0-324071d9e928	a5938c95-ba8e-46f6-98f2-4e670ba3b2a4	e0534574-8100-43c6-a396-f954f8ac95be	BUY	2025-10-07	\N	80.000000	18.702880	1496.23	2.95	0.00	0.00	EUR	1.000000	1496.23	\N	Importato da Excel: MUL AM MS J UEC	2025-11-05 12:35:29.892777+01	2025-11-05 12:35:29.892777+01
b60a5cfa-1fb6-4192-9c7e-c4ca7fc56c04	a5938c95-ba8e-46f6-98f2-4e670ba3b2a4	cc52fa73-bb3a-49ea-bb36-a0191f934e11	BUY	2025-10-07	\N	4.000000	326.727500	1306.91	2.95	0.00	0.00	EUR	1.000000	1306.91	\N	Importato da Excel: GLDFIXPM/SOURCE 00	2025-11-05 12:35:29.892777+01	2025-11-05 12:35:29.892777+01
6b255668-ffde-463b-a27f-5808f92ad032	a5938c95-ba8e-46f6-98f2-4e670ba3b2a4	fc48529f-7c1b-41f4-9975-fc576e2788bd	BUY	2025-10-07	\N	250.000000	5.745800	1436.45	2.95	0.00	0.00	EUR	1.000000	1436.45	\N	Importato da Excel: MSCI CHINA USD-AC	2025-11-05 12:35:29.892777+01	2025-11-05 12:35:29.892777+01
79cb09d2-c634-489c-b490-2976b15a5d6f	a5938c95-ba8e-46f6-98f2-4e670ba3b2a4	f1daeb66-3038-40d7-beea-ba11dd317ae9	BUY	2025-10-07	\N	7.000000	214.421430	1500.95	2.95	0.00	0.00	EUR	1.000000	1500.95	\N	Importato da Excel: ISHS CR STX EUR-AC	2025-11-05 12:35:29.892777+01	2025-11-05 12:35:29.892777+01
6a7cccb5-3177-4d55-ba82-080c3489ead7	a5938c95-ba8e-46f6-98f2-4e670ba3b2a4	fc48529f-7c1b-41f4-9975-fc576e2788bd	BUY	2025-09-03	\N	550.000000	5.291040	2910.07	5.52	0.00	0.00	EUR	1.000000	2910.07	\N	Importato da Excel: MSCI CHINA USD-AC	2025-11-05 12:35:29.892777+01	2025-11-05 12:35:29.892777+01
7fa86ccf-5df5-42f3-8447-fc8ac72fed37	a5938c95-ba8e-46f6-98f2-4e670ba3b2a4	c117885f-43f8-4be0-8df2-f6d30a200cca	BUY	2025-08-13	\N	23.000000	104.430000	2401.89	0.00	0.00	0.00	EUR	1.000000	2401.89	\N	Importato da Excel: ISHS CR WD USD-AC	2025-11-05 12:35:29.892777+01	2025-11-05 12:35:29.892777+01
3356c371-1975-481a-a8d1-9030a9f1dddf	a5938c95-ba8e-46f6-98f2-4e670ba3b2a4	f1daeb66-3038-40d7-beea-ba11dd317ae9	BUY	2025-07-07	\N	27.000000	201.632220	5444.07	10.32	0.00	0.00	EUR	1.000000	5444.07	\N	Importato da Excel: ISHS CR STX EUR-AC	2025-11-05 12:35:29.892777+01	2025-11-05 12:35:29.892777+01
d1f98f5f-8b43-4c20-ad70-652e595ced39	a5938c95-ba8e-46f6-98f2-4e670ba3b2a4	fda2e7d3-54a5-4b6b-a504-48873da1c697	BUY	2025-07-02	\N	16.000000	16.516290	264.26	2.95	0.00	0.00	USD	1.000000	264.26	\N	Importato da Excel: BRIGHTSTAR LOTTERY	2025-11-05 12:35:29.892777+01	2025-11-05 12:35:29.892777+01
04235719-0eb3-4e48-861c-f3e80927634c	a5938c95-ba8e-46f6-98f2-4e670ba3b2a4	fda2e7d3-54a5-4b6b-a504-48873da1c697	BUY	2025-07-02	\N	84.000000	16.300000	1369.20	0.00	0.00	0.00	USD	1.000000	1369.20	\N	Importato da Excel: BRIGHTSTAR LOTTERY	2025-11-05 12:35:29.892777+01	2025-11-05 12:35:29.892777+01
c1794642-4413-442c-bfc8-bd79c46477b3	a5938c95-ba8e-46f6-98f2-4e670ba3b2a4	f1daeb66-3038-40d7-beea-ba11dd317ae9	BUY	2025-06-02	\N	1.000000	205.600000	205.60	2.95	0.00	0.00	EUR	1.000000	205.60	\N	Importato da Excel: ISHS CR STX EUR-AC	2025-11-05 12:35:29.892777+01	2025-11-05 12:35:29.892777+01
9c6b055b-7dd2-49bb-b3af-5c926edac456	a5938c95-ba8e-46f6-98f2-4e670ba3b2a4	f1daeb66-3038-40d7-beea-ba11dd317ae9	BUY	2025-06-02	\N	4.000000	202.650000	810.60	0.00	0.00	0.00	EUR	1.000000	810.60	\N	Importato da Excel: ISHS CR STX EUR-AC	2025-11-05 12:35:29.892777+01	2025-11-05 12:35:29.892777+01
f20deb3d-1b3f-4f5f-806e-2ae27441c734	a5938c95-ba8e-46f6-98f2-4e670ba3b2a4	719121c9-908d-49b7-a047-23464f0960ab	BUY	2025-06-02	\N	5.000000	262.440000	1312.20	2.95	0.00	0.00	EUR	1.000000	1312.20	\N	Importato da Excel: LIF C S EU 600 UEAC	2025-11-05 12:35:29.892777+01	2025-11-05 12:35:29.892777+01
e6b2370f-8319-4fff-8334-38cca4e647ca	a5938c95-ba8e-46f6-98f2-4e670ba3b2a4	f1daeb66-3038-40d7-beea-ba11dd317ae9	BUY	2025-04-30	\N	10.000000	192.886000	1928.86	3.66	0.00	0.00	EUR	1.000000	1928.86	\N	Importato da Excel: ISHS CR STX EUR-AC	2025-11-05 12:35:29.892777+01	2025-11-05 12:35:29.892777+01
9d62233c-e1e5-4b1a-b668-3367d6c04ef7	a5938c95-ba8e-46f6-98f2-4e670ba3b2a4	c117885f-43f8-4be0-8df2-f6d30a200cca	BUY	2025-04-10	\N	65.000000	89.450000	5814.25	0.00	0.00	0.00	EUR	1.000000	5814.25	\N	Importato da Excel: ISHS CR WD USD-AC	2025-11-05 12:35:29.892777+01	2025-11-05 12:35:29.892777+01
aa178589-a12b-43fa-9698-bc8177b10589	a5938c95-ba8e-46f6-98f2-4e670ba3b2a4	cc52fa73-bb3a-49ea-bb36-a0191f934e11	BUY	2025-04-01	\N	14.000000	280.010710	3920.15	7.43	0.00	0.00	EUR	1.000000	3920.15	\N	Importato da Excel: GLDFIXPM/SOURCE 00	2025-11-05 12:35:29.892777+01	2025-11-05 12:35:29.892777+01
4eb60318-f0b8-4372-a3e7-9c159aaf45ee	a5938c95-ba8e-46f6-98f2-4e670ba3b2a4	bcdff4ec-d4bf-419e-afb1-49beea99eeaf	BUY	2025-03-04	\N	150.000000	40.632070	6094.81	11.56	0.00	0.00	EUR	1.000000	6094.81	\N	Importato da Excel: VAN DEF USD-A-ACC	2025-11-05 12:35:29.892777+01	2025-11-05 12:35:29.892777+01
a7fb12dc-aeeb-46d7-af85-20f1f8c625d9	a5938c95-ba8e-46f6-98f2-4e670ba3b2a4	0999dc6a-e6f9-4bbf-9bd2-30a25658de89	BUY	2025-02-28	\N	13.000000	168.470000	2190.11	0.00	0.00	0.00	EUR	1.000000	2190.11	\N	Importato da Excel: MUL LEGB 7-10Y AC	2025-11-05 12:35:29.892777+01	2025-11-05 12:35:29.892777+01
552c9336-5c2c-44ca-82a8-207c77cdc0a5	a5938c95-ba8e-46f6-98f2-4e670ba3b2a4	f1daeb66-3038-40d7-beea-ba11dd317ae9	BUY	2025-02-28	\N	15.000000	201.964000	3029.46	4.71	0.00	0.00	EUR	1.000000	3029.46	\N	Importato da Excel: ISHS CR STX EUR-AC	2025-11-05 12:35:29.892777+01	2025-11-05 12:35:29.892777+01
33f462f6-0c18-41bf-a7b9-3f65ac9f64d6	a5938c95-ba8e-46f6-98f2-4e670ba3b2a4	e0534574-8100-43c6-a396-f954f8ac95be	BUY	2025-02-28	\N	650.000000	17.241230	11206.80	19.00	0.00	0.00	EUR	1.000000	11206.80	\N	Importato da Excel: MUL AM MS J UEC	2025-11-05 12:35:29.892777+01	2025-11-05 12:35:29.892777+01
772a722a-f86a-4bfa-bf31-c3747e293dde	a5938c95-ba8e-46f6-98f2-4e670ba3b2a4	f1daeb66-3038-40d7-beea-ba11dd317ae9	BUY	2025-02-28	\N	5.000000	202.240000	1011.20	2.95	0.00	0.00	EUR	1.000000	1011.20	\N	Importato da Excel: ISHS CR STX EUR-AC	2025-11-05 12:35:29.892777+01	2025-11-05 12:35:29.892777+01
35c6d636-bc5d-4c78-9134-19212254acf8	a5938c95-ba8e-46f6-98f2-4e670ba3b2a4	c743dda6-c6ba-43c2-a14e-75490a1b06b0	BUY	2025-02-28	\N	26.000000	125.670000	3267.42	0.00	0.00	0.00	EUR	1.000000	3267.42	\N	Importato da Excel: MUL L 1-3Y IG CC	2025-11-05 12:35:29.892777+01	2025-11-05 12:35:29.892777+01
07b06aa1-20f0-48dd-86eb-ecfc9f1206b5	a5938c95-ba8e-46f6-98f2-4e670ba3b2a4	cc52fa73-bb3a-49ea-bb36-a0191f934e11	BUY	2025-02-28	\N	20.000000	265.303000	5306.06	10.06	0.00	0.00	EUR	1.000000	5306.06	\N	Importato da Excel: GLDFIXPM/SOURCE 00	2025-11-05 12:35:29.892777+01	2025-11-05 12:35:29.892777+01
f3fa8cca-aa13-4ce7-947e-718f33fb4d8a	a5938c95-ba8e-46f6-98f2-4e670ba3b2a4	0999dc6a-e6f9-4bbf-9bd2-30a25658de89	BUY	2025-02-28	\N	6.000000	168.470000	1010.82	0.00	0.00	0.00	EUR	1.000000	1010.82	\N	Importato da Excel: MUL LEGB 7-10Y AC	2025-11-05 12:35:29.892777+01	2025-11-05 12:35:29.892777+01
e684237d-50e8-41c7-8925-4b601b9cb25d	a5938c95-ba8e-46f6-98f2-4e670ba3b2a4	719121c9-908d-49b7-a047-23464f0960ab	BUY	2025-02-28	\N	15.000000	260.043330	3900.65	7.40	0.00	0.00	EUR	1.000000	3900.65	\N	Importato da Excel: LIF C S EU 600 UEAC	2025-11-05 12:35:29.892777+01	2025-11-05 12:35:29.892777+01
ea160c63-3d42-4360-b6a0-80c7831911ca	a5938c95-ba8e-46f6-98f2-4e670ba3b2a4	0999dc6a-e6f9-4bbf-9bd2-30a25658de89	BUY	2025-02-28	\N	1.000000	168.470000	168.47	0.00	0.00	0.00	EUR	1.000000	168.47	\N	Importato da Excel: MUL LEGB 7-10Y AC	2025-11-05 12:35:29.892777+01	2025-11-05 12:35:29.892777+01
5c6f6419-08bc-4fef-98dd-2c5482b158e4	a5938c95-ba8e-46f6-98f2-4e670ba3b2a4	cc52fa73-bb3a-49ea-bb36-a0191f934e11	BUY	2025-01-17	\N	85.000000	254.123530	21600.50	19.00	0.00	0.00	EUR	1.000000	21600.50	\N	Importato da Excel: GLDFIXPM/SOURCE 00	2025-11-05 12:35:29.892777+01	2025-11-05 12:35:29.892777+01
a25f8178-87da-4d6d-99b5-00a55cdd63bb	a5938c95-ba8e-46f6-98f2-4e670ba3b2a4	bf3b3448-1ec3-4f29-87e3-7fc90bc83308	BUY	2025-01-17	\N	100.000000	84.270000	8427.00	0.00	0.00	0.00	EUR	1.000000	8427.00	\N	Importato da Excel: LYXOR NASDAQ 100 ETF	2025-11-05 12:35:29.892777+01	2025-11-05 12:35:29.892777+01
1ba63204-4778-4dc0-855e-85e30274c1dc	a5938c95-ba8e-46f6-98f2-4e670ba3b2a4	c117885f-43f8-4be0-8df2-f6d30a200cca	BUY	2025-01-17	\N	103.000000	106.500000	10969.50	0.00	0.00	0.00	EUR	1.000000	10969.50	\N	Importato da Excel: ISHS CR WD USD-AC	2025-11-05 12:35:29.892777+01	2025-11-05 12:35:29.892777+01
8103951d-ecd5-4c6e-8354-25cfda6fa850	a5938c95-ba8e-46f6-98f2-4e670ba3b2a4	b46bba4b-525d-483d-bf4e-f195bde3d6bc	BUY	2025-01-17	\N	10.000000	618.573000	6185.73	11.73	0.00	0.00	EUR	1.000000	6185.73	\N	Importato da Excel: ISHS CR 500 USD-AC	2025-11-05 12:35:29.892777+01	2025-11-05 12:35:29.892777+01
9ac777e3-2785-43e0-9f8c-8529a1f8e860	a5938c95-ba8e-46f6-98f2-4e670ba3b2a4	d2c980bc-c787-4166-8e74-d074800bf867	BUY	2025-01-17	\N	691.000000	24.902500	17207.63	19.00	0.00	0.00	EUR	1.000000	17207.63	\N	Importato da Excel: VAN TREA BD USD-ACC	2025-11-05 12:35:29.892777+01	2025-11-05 12:35:29.892777+01
aa5fd4ad-3b71-47e3-bb05-7b930446ea2c	a5938c95-ba8e-46f6-98f2-4e670ba3b2a4	b46bba4b-525d-483d-bf4e-f195bde3d6bc	BUY	2025-01-17	\N	4.000000	618.582500	2474.33	4.69	0.00	0.00	EUR	1.000000	2474.33	\N	Importato da Excel: ISHS CR 500 USD-AC	2025-11-05 12:35:29.892777+01	2025-11-05 12:35:29.892777+01
9b792461-421c-4e0e-980e-64bb6ac58ef5	a5938c95-ba8e-46f6-98f2-4e670ba3b2a4	d2c980bc-c787-4166-8e74-d074800bf867	BUY	2025-01-17	\N	709.000000	24.870000	17632.83	0.00	0.00	0.00	EUR	1.000000	17632.83	\N	Importato da Excel: VAN TREA BD USD-ACC	2025-11-05 12:35:29.892777+01	2025-11-05 12:35:29.892777+01
8be08a04-52b2-4990-aec7-4327f13c4d5c	a5938c95-ba8e-46f6-98f2-4e670ba3b2a4	3a15e4de-589b-450d-93d1-a19b0c7bdb28	BUY	2025-01-13	\N	155.000000	144.979800	22471.87	0.00	0.00	0.00	EUR	1.000000	22471.87	\N	Importato da Excel: XTR2 EUR OR SW 1CC	2025-11-05 12:35:29.892777+01	2025-11-05 12:35:29.892777+01
90d0a256-c72b-41e3-91b3-fec513ef8ae6	a5938c95-ba8e-46f6-98f2-4e670ba3b2a4	d2c980bc-c787-4166-8e74-d074800bf867	BUY	2025-01-06	\N	500.000000	24.623000	12311.50	19.00	0.00	0.00	EUR	1.000000	12311.50	\N	Importato da Excel: VAN TREA BD USD-ACC	2025-11-05 12:35:29.892777+01	2025-11-05 12:35:29.892777+01
914a17bd-4dcb-4c1b-81b1-0809d2f6741d	a5938c95-ba8e-46f6-98f2-4e670ba3b2a4	bf3b3448-1ec3-4f29-87e3-7fc90bc83308	BUY	2025-01-02	\N	405.000000	83.290000	33732.45	0.00	0.00	0.00	EUR	1.000000	33732.45	\N	Importato da Excel: LYXOR NASDAQ 100 ETF	2025-11-05 12:35:29.892777+01	2025-11-05 12:35:29.892777+01
5e4d8353-0f92-4f1f-affe-b09026d04d81	a5938c95-ba8e-46f6-98f2-4e670ba3b2a4	b46bba4b-525d-483d-bf4e-f195bde3d6bc	BUY	2025-01-02	\N	48.000000	610.864170	29321.48	7.40	0.00	0.00	EUR	1.000000	29321.48	\N	Importato da Excel: ISHS CR 500 USD-AC	2025-11-05 12:35:29.892777+01	2025-11-05 12:35:29.892777+01
c3afc4b8-0837-46ff-91e9-1032e26db198	a5938c95-ba8e-46f6-98f2-4e670ba3b2a4	b46bba4b-525d-483d-bf4e-f195bde3d6bc	BUY	2025-01-02	\N	10.000000	611.860000	6118.60	11.60	0.00	0.00	EUR	1.000000	6118.60	\N	Importato da Excel: ISHS CR 500 USD-AC	2025-11-05 12:35:29.892777+01	2025-11-05 12:35:29.892777+01
94dec14b-d699-4286-af20-f2647dfdf4b9	a5938c95-ba8e-46f6-98f2-4e670ba3b2a4	c117885f-43f8-4be0-8df2-f6d30a200cca	BUY	2025-01-02	\N	87.000000	105.100000	9143.70	0.00	0.00	0.00	EUR	1.000000	9143.70	\N	Importato da Excel: ISHS CR WD USD-AC	2025-11-05 12:35:29.892777+01	2025-11-05 12:35:29.892777+01
51b82a3f-f1c0-4730-b0b2-38aa5b1d6620	a5938c95-ba8e-46f6-98f2-4e670ba3b2a4	c117885f-43f8-4be0-8df2-f6d30a200cca	BUY	2025-01-02	\N	113.000000	105.120000	11878.56	0.00	0.00	0.00	EUR	1.000000	11878.56	\N	Importato da Excel: ISHS CR WD USD-AC	2025-11-05 12:35:29.892777+01	2025-11-05 12:35:29.892777+01
c6a44c64-2d18-49ed-b55b-82f365c3d48e	a5938c95-ba8e-46f6-98f2-4e670ba3b2a4	bf3b3448-1ec3-4f29-87e3-7fc90bc83308	BUY	2024-12-10	\N	19.000000	82.160000	1561.04	0.00	0.00	0.00	EUR	1.000000	1561.04	\N	Importato da Excel: LYXOR NASDAQ 100 ETF	2025-11-05 12:35:29.892777+01	2025-11-05 12:35:29.892777+01
ae89c75f-4eca-4520-a104-efd7b0e405ba	a5938c95-ba8e-46f6-98f2-4e670ba3b2a4	b46bba4b-525d-483d-bf4e-f195bde3d6bc	BUY	2024-12-10	\N	20.000000	609.340000	12186.80	19.00	0.00	0.00	EUR	1.000000	12186.80	\N	Importato da Excel: ISHS CR 500 USD-AC	2025-11-05 12:35:29.892777+01	2025-11-05 12:35:29.892777+01
9d3f2574-f049-4680-be5e-fb8f02475901	a5938c95-ba8e-46f6-98f2-4e670ba3b2a4	8f706b9d-54ae-4ac7-8ce5-0ed005362d68	BUY	2024-12-10	\N	29.000000	76.885860	2229.69	4.23	0.00	0.00	EUR	1.000000	2229.69	\N	Importato da Excel: INVESCO GLB USD-ACC	2025-11-05 12:35:29.892777+01	2025-11-05 12:35:29.892777+01
2e51949a-5384-47e4-848d-b4d6bfe31fb6	a5938c95-ba8e-46f6-98f2-4e670ba3b2a4	bf3b3448-1ec3-4f29-87e3-7fc90bc83308	BUY	2024-12-10	\N	48.000000	82.160000	3943.68	0.00	0.00	0.00	EUR	1.000000	3943.68	\N	Importato da Excel: LYXOR NASDAQ 100 ETF	2025-11-05 12:35:29.892777+01	2025-11-05 12:35:29.892777+01
ed966de2-5271-4135-80d0-482b746237dd	a5938c95-ba8e-46f6-98f2-4e670ba3b2a4	8f706b9d-54ae-4ac7-8ce5-0ed005362d68	BUY	2024-12-10	\N	1.000000	76.880000	76.88	0.14	0.00	0.00	EUR	1.000000	76.88	\N	Importato da Excel: INVESCO GLB USD-ACC	2025-11-05 12:35:29.892777+01	2025-11-05 12:35:29.892777+01
e29399ce-d44f-4b3e-bfc8-8dde579d90ae	a5938c95-ba8e-46f6-98f2-4e670ba3b2a4	bf3b3448-1ec3-4f29-87e3-7fc90bc83308	BUY	2024-12-10	\N	33.000000	82.160000	2711.28	0.00	0.00	0.00	EUR	1.000000	2711.28	\N	Importato da Excel: LYXOR NASDAQ 100 ETF	2025-11-05 12:35:29.892777+01	2025-11-05 12:35:29.892777+01
\.


--
-- TOC entry 5230 (class 2606 OID 113808)
-- Name: allocation_categories allocation_categories_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.allocation_categories
    ADD CONSTRAINT allocation_categories_pkey PRIMARY KEY (category_id);


--
-- TOC entry 5232 (class 2606 OID 113810)
-- Name: allocation_categories allocation_categories_unique_name; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.allocation_categories
    ADD CONSTRAINT allocation_categories_unique_name UNIQUE (portfolio_id, category_name);


--
-- TOC entry 5164 (class 2606 OID 100026)
-- Name: assets assets_isin_key; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.assets
    ADD CONSTRAINT assets_isin_key UNIQUE (isin);


--
-- TOC entry 5166 (class 2606 OID 100024)
-- Name: assets assets_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.assets
    ADD CONSTRAINT assets_pkey PRIMARY KEY (asset_id);


--
-- TOC entry 5186 (class 2606 OID 100099)
-- Name: dividends dividends_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.dividends
    ADD CONSTRAINT dividends_pkey PRIMARY KEY (dividend_id);


--
-- TOC entry 5216 (class 2606 OID 102265)
-- Name: etf_asset_allocation etf_asset_allocation_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.etf_asset_allocation
    ADD CONSTRAINT etf_asset_allocation_pkey PRIMARY KEY (asset_allocation_id);


--
-- TOC entry 5218 (class 2606 OID 102267)
-- Name: etf_asset_allocation etf_asset_allocation_unique; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.etf_asset_allocation
    ADD CONSTRAINT etf_asset_allocation_unique UNIQUE (asset_id, allocation_type);


--
-- TOC entry 5226 (class 2606 OID 102297)
-- Name: etf_bond_maturity etf_bond_maturity_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.etf_bond_maturity
    ADD CONSTRAINT etf_bond_maturity_pkey PRIMARY KEY (bond_maturity_id);


--
-- TOC entry 5222 (class 2606 OID 102282)
-- Name: etf_bond_ratings etf_bond_ratings_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.etf_bond_ratings
    ADD CONSTRAINT etf_bond_ratings_pkey PRIMARY KEY (bond_rating_id);


--
-- TOC entry 5210 (class 2606 OID 102247)
-- Name: etf_geographic_weights etf_geographic_weights_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.etf_geographic_weights
    ADD CONSTRAINT etf_geographic_weights_pkey PRIMARY KEY (geographic_weight_id);


--
-- TOC entry 5212 (class 2606 OID 102249)
-- Name: etf_geographic_weights etf_geographic_weights_unique; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.etf_geographic_weights
    ADD CONSTRAINT etf_geographic_weights_unique UNIQUE (asset_id, region_name);


--
-- TOC entry 5200 (class 2606 OID 102215)
-- Name: etf_holdings etf_holdings_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.etf_holdings
    ADD CONSTRAINT etf_holdings_pkey PRIMARY KEY (holding_id);


--
-- TOC entry 5204 (class 2606 OID 102230)
-- Name: etf_sector_weights etf_sector_weights_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.etf_sector_weights
    ADD CONSTRAINT etf_sector_weights_pkey PRIMARY KEY (sector_weight_id);


--
-- TOC entry 5206 (class 2606 OID 102232)
-- Name: etf_sector_weights etf_sector_weights_unique; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.etf_sector_weights
    ADD CONSTRAINT etf_sector_weights_unique UNIQUE (asset_id, sector_name);


--
-- TOC entry 5182 (class 2606 OID 100083)
-- Name: portfolio_snapshots portfolio_snapshots_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.portfolio_snapshots
    ADD CONSTRAINT portfolio_snapshots_pkey PRIMARY KEY (snapshot_id);


--
-- TOC entry 5184 (class 2606 OID 100085)
-- Name: portfolio_snapshots portfolio_snapshots_portfolio_id_snapshot_date_key; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.portfolio_snapshots
    ADD CONSTRAINT portfolio_snapshots_portfolio_id_snapshot_date_key UNIQUE (portfolio_id, snapshot_date);


--
-- TOC entry 5162 (class 2606 OID 100008)
-- Name: portfolios portfolios_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.portfolios
    ADD CONSTRAINT portfolios_pkey PRIMARY KEY (portfolio_id);


--
-- TOC entry 5175 (class 2606 OID 100062)
-- Name: positions positions_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.positions
    ADD CONSTRAINT positions_pkey PRIMARY KEY (position_id);


--
-- TOC entry 5177 (class 2606 OID 100064)
-- Name: positions positions_portfolio_id_asset_id_key; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.positions
    ADD CONSTRAINT positions_portfolio_id_asset_id_key UNIQUE (portfolio_id, asset_id);


--
-- TOC entry 5196 (class 2606 OID 100166)
-- Name: price_history price_history_asset_id_price_date_key; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.price_history
    ADD CONSTRAINT price_history_asset_id_price_date_key UNIQUE (asset_id, price_date);


--
-- TOC entry 5198 (class 2606 OID 100164)
-- Name: price_history price_history_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.price_history
    ADD CONSTRAINT price_history_pkey PRIMARY KEY (price_id);


--
-- TOC entry 5191 (class 2606 OID 100124)
-- Name: target_allocations target_allocations_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.target_allocations
    ADD CONSTRAINT target_allocations_pkey PRIMARY KEY (target_id);


--
-- TOC entry 5173 (class 2606 OID 100042)
-- Name: transactions transactions_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.transactions
    ADD CONSTRAINT transactions_pkey PRIMARY KEY (transaction_id);


--
-- TOC entry 5233 (class 1259 OID 113816)
-- Name: idx_allocation_categories_portfolio; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_allocation_categories_portfolio ON public.allocation_categories USING btree (portfolio_id) WHERE (is_active = true);


--
-- TOC entry 5167 (class 1259 OID 100151)
-- Name: idx_assets_active; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_assets_active ON public.assets USING btree (is_active);


--
-- TOC entry 5168 (class 1259 OID 102310)
-- Name: idx_assets_composition_last_updated; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_assets_composition_last_updated ON public.assets USING btree (composition_last_updated DESC);


--
-- TOC entry 5169 (class 1259 OID 100149)
-- Name: idx_assets_isin; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_assets_isin ON public.assets USING btree (isin);


--
-- TOC entry 5170 (class 1259 OID 100142)
-- Name: idx_assets_name_search; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_assets_name_search ON public.assets USING gin (to_tsvector('italian'::regconfig, (name)::text));


--
-- TOC entry 5171 (class 1259 OID 100150)
-- Name: idx_assets_type; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_assets_type ON public.assets USING btree (asset_type);


--
-- TOC entry 5187 (class 1259 OID 100147)
-- Name: idx_dividends_asset; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_dividends_asset ON public.dividends USING btree (asset_id);


--
-- TOC entry 5188 (class 1259 OID 100148)
-- Name: idx_dividends_date; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_dividends_date ON public.dividends USING btree (payment_date DESC);


--
-- TOC entry 5189 (class 1259 OID 100146)
-- Name: idx_dividends_portfolio; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_dividends_portfolio ON public.dividends USING btree (portfolio_id);


--
-- TOC entry 5219 (class 1259 OID 102273)
-- Name: idx_etf_asset_allocation_asset_id; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_etf_asset_allocation_asset_id ON public.etf_asset_allocation USING btree (asset_id);


--
-- TOC entry 5220 (class 1259 OID 102274)
-- Name: idx_etf_asset_allocation_updated_at; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_etf_asset_allocation_updated_at ON public.etf_asset_allocation USING btree (updated_at);


--
-- TOC entry 5227 (class 1259 OID 102303)
-- Name: idx_etf_bond_maturity_asset_id; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_etf_bond_maturity_asset_id ON public.etf_bond_maturity USING btree (asset_id);


--
-- TOC entry 5228 (class 1259 OID 102304)
-- Name: idx_etf_bond_maturity_updated_at; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_etf_bond_maturity_updated_at ON public.etf_bond_maturity USING btree (updated_at);


--
-- TOC entry 5223 (class 1259 OID 102288)
-- Name: idx_etf_bond_ratings_asset_id; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_etf_bond_ratings_asset_id ON public.etf_bond_ratings USING btree (asset_id);


--
-- TOC entry 5224 (class 1259 OID 102289)
-- Name: idx_etf_bond_ratings_updated_at; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_etf_bond_ratings_updated_at ON public.etf_bond_ratings USING btree (updated_at);


--
-- TOC entry 5213 (class 1259 OID 102255)
-- Name: idx_etf_geographic_weights_asset_id; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_etf_geographic_weights_asset_id ON public.etf_geographic_weights USING btree (asset_id);


--
-- TOC entry 5214 (class 1259 OID 102256)
-- Name: idx_etf_geographic_weights_updated_at; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_etf_geographic_weights_updated_at ON public.etf_geographic_weights USING btree (updated_at);


--
-- TOC entry 5201 (class 1259 OID 102221)
-- Name: idx_etf_holdings_asset_id; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_etf_holdings_asset_id ON public.etf_holdings USING btree (asset_id);


--
-- TOC entry 5202 (class 1259 OID 102222)
-- Name: idx_etf_holdings_updated_at; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_etf_holdings_updated_at ON public.etf_holdings USING btree (updated_at);


--
-- TOC entry 5207 (class 1259 OID 102238)
-- Name: idx_etf_sector_weights_asset_id; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_etf_sector_weights_asset_id ON public.etf_sector_weights USING btree (asset_id);


--
-- TOC entry 5208 (class 1259 OID 102239)
-- Name: idx_etf_sector_weights_updated_at; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_etf_sector_weights_updated_at ON public.etf_sector_weights USING btree (updated_at);


--
-- TOC entry 5192 (class 1259 OID 100172)
-- Name: idx_price_history_asset; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_price_history_asset ON public.price_history USING btree (asset_id);


--
-- TOC entry 5193 (class 1259 OID 100174)
-- Name: idx_price_history_asset_date; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_price_history_asset_date ON public.price_history USING btree (asset_id, price_date DESC);


--
-- TOC entry 5194 (class 1259 OID 100173)
-- Name: idx_price_history_date; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_price_history_date ON public.price_history USING btree (price_date DESC);


--
-- TOC entry 5178 (class 1259 OID 100144)
-- Name: idx_snapshots_date; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_snapshots_date ON public.portfolio_snapshots USING btree (snapshot_date DESC);


--
-- TOC entry 5179 (class 1259 OID 100143)
-- Name: idx_snapshots_portfolio; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_snapshots_portfolio ON public.portfolio_snapshots USING btree (portfolio_id);


--
-- TOC entry 5180 (class 1259 OID 100145)
-- Name: idx_snapshots_portfolio_date; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_snapshots_portfolio_date ON public.portfolio_snapshots USING btree (portfolio_id, snapshot_date DESC);


--
-- TOC entry 5256 (class 2620 OID 113817)
-- Name: allocation_categories update_allocation_categories_updated_at; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER update_allocation_categories_updated_at BEFORE UPDATE ON public.allocation_categories FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();


--
-- TOC entry 5251 (class 2620 OID 100154)
-- Name: assets update_assets_updated_at; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER update_assets_updated_at BEFORE UPDATE ON public.assets FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();


--
-- TOC entry 5250 (class 2620 OID 100153)
-- Name: portfolios update_portfolios_updated_at; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER update_portfolios_updated_at BEFORE UPDATE ON public.portfolios FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();


--
-- TOC entry 5252 (class 2620 OID 100191)
-- Name: transactions update_position_on_transaction; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER update_position_on_transaction AFTER INSERT ON public.transactions FOR EACH ROW EXECUTE FUNCTION public.update_position_after_transaction();


--
-- TOC entry 5254 (class 2620 OID 100156)
-- Name: positions update_positions_updated_at; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER update_positions_updated_at BEFORE UPDATE ON public.positions FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();


--
-- TOC entry 5255 (class 2620 OID 100157)
-- Name: target_allocations update_target_allocations_updated_at; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER update_target_allocations_updated_at BEFORE UPDATE ON public.target_allocations FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();


--
-- TOC entry 5253 (class 2620 OID 100155)
-- Name: transactions update_transactions_updated_at; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER update_transactions_updated_at BEFORE UPDATE ON public.transactions FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();


--
-- TOC entry 5249 (class 2606 OID 113811)
-- Name: allocation_categories allocation_categories_portfolio_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.allocation_categories
    ADD CONSTRAINT allocation_categories_portfolio_fkey FOREIGN KEY (portfolio_id) REFERENCES public.portfolios(portfolio_id) ON DELETE CASCADE;


--
-- TOC entry 5239 (class 2606 OID 100105)
-- Name: dividends dividends_asset_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.dividends
    ADD CONSTRAINT dividends_asset_id_fkey FOREIGN KEY (asset_id) REFERENCES public.assets(asset_id);


--
-- TOC entry 5240 (class 2606 OID 100100)
-- Name: dividends dividends_portfolio_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.dividends
    ADD CONSTRAINT dividends_portfolio_id_fkey FOREIGN KEY (portfolio_id) REFERENCES public.portfolios(portfolio_id) ON DELETE CASCADE;


--
-- TOC entry 5246 (class 2606 OID 102268)
-- Name: etf_asset_allocation etf_asset_allocation_asset_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.etf_asset_allocation
    ADD CONSTRAINT etf_asset_allocation_asset_fkey FOREIGN KEY (asset_id) REFERENCES public.assets(asset_id) ON DELETE CASCADE;


--
-- TOC entry 5248 (class 2606 OID 102298)
-- Name: etf_bond_maturity etf_bond_maturity_asset_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.etf_bond_maturity
    ADD CONSTRAINT etf_bond_maturity_asset_fkey FOREIGN KEY (asset_id) REFERENCES public.assets(asset_id) ON DELETE CASCADE;


--
-- TOC entry 5247 (class 2606 OID 102283)
-- Name: etf_bond_ratings etf_bond_ratings_asset_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.etf_bond_ratings
    ADD CONSTRAINT etf_bond_ratings_asset_fkey FOREIGN KEY (asset_id) REFERENCES public.assets(asset_id) ON DELETE CASCADE;


--
-- TOC entry 5245 (class 2606 OID 102250)
-- Name: etf_geographic_weights etf_geographic_weights_asset_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.etf_geographic_weights
    ADD CONSTRAINT etf_geographic_weights_asset_fkey FOREIGN KEY (asset_id) REFERENCES public.assets(asset_id) ON DELETE CASCADE;


--
-- TOC entry 5243 (class 2606 OID 102216)
-- Name: etf_holdings etf_holdings_asset_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.etf_holdings
    ADD CONSTRAINT etf_holdings_asset_fkey FOREIGN KEY (asset_id) REFERENCES public.assets(asset_id) ON DELETE CASCADE;


--
-- TOC entry 5244 (class 2606 OID 102233)
-- Name: etf_sector_weights etf_sector_weights_asset_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.etf_sector_weights
    ADD CONSTRAINT etf_sector_weights_asset_fkey FOREIGN KEY (asset_id) REFERENCES public.assets(asset_id) ON DELETE CASCADE;


--
-- TOC entry 5238 (class 2606 OID 100086)
-- Name: portfolio_snapshots portfolio_snapshots_portfolio_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.portfolio_snapshots
    ADD CONSTRAINT portfolio_snapshots_portfolio_id_fkey FOREIGN KEY (portfolio_id) REFERENCES public.portfolios(portfolio_id) ON DELETE CASCADE;


--
-- TOC entry 5236 (class 2606 OID 100070)
-- Name: positions positions_asset_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.positions
    ADD CONSTRAINT positions_asset_id_fkey FOREIGN KEY (asset_id) REFERENCES public.assets(asset_id);


--
-- TOC entry 5237 (class 2606 OID 100065)
-- Name: positions positions_portfolio_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.positions
    ADD CONSTRAINT positions_portfolio_id_fkey FOREIGN KEY (portfolio_id) REFERENCES public.portfolios(portfolio_id) ON DELETE CASCADE;


--
-- TOC entry 5242 (class 2606 OID 100167)
-- Name: price_history price_history_asset_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.price_history
    ADD CONSTRAINT price_history_asset_id_fkey FOREIGN KEY (asset_id) REFERENCES public.assets(asset_id) ON DELETE CASCADE;


--
-- TOC entry 5241 (class 2606 OID 100125)
-- Name: target_allocations target_allocations_portfolio_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.target_allocations
    ADD CONSTRAINT target_allocations_portfolio_id_fkey FOREIGN KEY (portfolio_id) REFERENCES public.portfolios(portfolio_id) ON DELETE CASCADE;


--
-- TOC entry 5234 (class 2606 OID 100048)
-- Name: transactions transactions_asset_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.transactions
    ADD CONSTRAINT transactions_asset_id_fkey FOREIGN KEY (asset_id) REFERENCES public.assets(asset_id);


--
-- TOC entry 5235 (class 2606 OID 100043)
-- Name: transactions transactions_portfolio_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.transactions
    ADD CONSTRAINT transactions_portfolio_id_fkey FOREIGN KEY (portfolio_id) REFERENCES public.portfolios(portfolio_id) ON DELETE CASCADE;


-- Completed on 2025-11-28 16:12:21

--
-- PostgreSQL database dump complete
--

