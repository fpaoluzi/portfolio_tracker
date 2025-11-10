--
-- PostgreSQL database dump
--

-- Dumped from database version 16.0
-- Dumped by pg_dump version 16.0

-- Started on 2025-11-10 19:43:55

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
-- TOC entry 5347 (class 0 OID 0)
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
-- TOC entry 5348 (class 0 OID 0)
-- Dependencies: 2
-- Name: EXTENSION "uuid-ossp"; Type: COMMENT; Schema: -; Owner: 
--

COMMENT ON EXTENSION "uuid-ossp" IS 'generate universally unique identifiers (UUIDs)';


--
-- TOC entry 328 (class 1255 OID 100192)
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
-- TOC entry 297 (class 1255 OID 100190)
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
-- TOC entry 410 (class 1255 OID 100152)
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
-- TOC entry 5349 (class 0 OID 0)
-- Dependencies: 218
-- Name: TABLE assets; Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON TABLE public.assets IS 'Anagrafica completa di tutti i titoli/asset';


--
-- TOC entry 5350 (class 0 OID 0)
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
-- TOC entry 5351 (class 0 OID 0)
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
-- TOC entry 5352 (class 0 OID 0)
-- Dependencies: 231
-- Name: TABLE etf_asset_allocation; Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON TABLE public.etf_asset_allocation IS 'Asset class allocation breakdown for ETF assets (Stocks, Bonds, Cash, etc.)';


--
-- TOC entry 5353 (class 0 OID 0)
-- Dependencies: 231
-- Name: COLUMN etf_asset_allocation.allocation_type; Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON COLUMN public.etf_asset_allocation.allocation_type IS 'Type of asset class (Equity, Bond, Cash, Other, Commodity, Real Estate)';


--
-- TOC entry 5354 (class 0 OID 0)
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
-- TOC entry 5355 (class 0 OID 0)
-- Dependencies: 233
-- Name: TABLE etf_bond_maturity; Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON TABLE public.etf_bond_maturity IS 'Bond maturity/duration distribution for bond ETFs';


--
-- TOC entry 5356 (class 0 OID 0)
-- Dependencies: 233
-- Name: COLUMN etf_bond_maturity.maturity_range; Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON COLUMN public.etf_bond_maturity.maturity_range IS 'Maturity range category (0-1Y, 1-3Y, 3-5Y, 5-10Y, 10-20Y, 20+Y)';


--
-- TOC entry 5357 (class 0 OID 0)
-- Dependencies: 233
-- Name: COLUMN etf_bond_maturity.weight_percent; Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON COLUMN public.etf_bond_maturity.weight_percent IS 'Percentage of bonds with this maturity (0-1)';


--
-- TOC entry 5358 (class 0 OID 0)
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
-- TOC entry 5359 (class 0 OID 0)
-- Dependencies: 232
-- Name: TABLE etf_bond_ratings; Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON TABLE public.etf_bond_ratings IS 'Bond quality ratings distribution for bond ETFs (AAA, AA, A, BBB, etc.)';


--
-- TOC entry 5360 (class 0 OID 0)
-- Dependencies: 232
-- Name: COLUMN etf_bond_ratings.rating_category; Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON COLUMN public.etf_bond_ratings.rating_category IS 'Bond rating category (AAA, AA, A, BBB, BB, B, Below B, Not Rated)';


--
-- TOC entry 5361 (class 0 OID 0)
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
-- TOC entry 5362 (class 0 OID 0)
-- Dependencies: 230
-- Name: TABLE etf_geographic_weights; Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON TABLE public.etf_geographic_weights IS 'Geographic allocation breakdown for ETF assets (US, Europe, Asia, etc.)';


--
-- TOC entry 5363 (class 0 OID 0)
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
-- TOC entry 5364 (class 0 OID 0)
-- Dependencies: 228
-- Name: TABLE etf_holdings; Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON TABLE public.etf_holdings IS 'Top holdings (companies) within ETF assets with their weight percentages';


--
-- TOC entry 5365 (class 0 OID 0)
-- Dependencies: 228
-- Name: COLUMN etf_holdings.holding_percent; Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON COLUMN public.etf_holdings.holding_percent IS 'Percentage weight of holding in ETF (0-1, e.g., 0.045 = 4.5%)';


--
-- TOC entry 5366 (class 0 OID 0)
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
-- TOC entry 5367 (class 0 OID 0)
-- Dependencies: 229
-- Name: TABLE etf_sector_weights; Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON TABLE public.etf_sector_weights IS 'Sector allocation breakdown for ETF assets (Technology, Healthcare, etc.)';


--
-- TOC entry 5368 (class 0 OID 0)
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
-- TOC entry 5369 (class 0 OID 0)
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
-- TOC entry 5370 (class 0 OID 0)
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
-- TOC entry 5371 (class 0 OID 0)
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
-- TOC entry 5372 (class 0 OID 0)
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
-- TOC entry 5373 (class 0 OID 0)
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
-- TOC entry 5374 (class 0 OID 0)
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
-- TOC entry 5375 (class 0 OID 0)
-- Dependencies: 227
-- Name: VIEW v_current_positions; Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON VIEW public.v_current_positions IS 'Vista posizioni correnti con percentuali di possesso e investita';


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
-- TOC entry 5376 (class 0 OID 0)
-- Dependencies: 234
-- Name: VIEW v_etf_composition_summary; Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON VIEW public.v_etf_composition_summary IS 'Summary of available ETF composition data for each asset';


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
-- TOC entry 5109 (class 2606 OID 100026)
-- Name: assets assets_isin_key; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.assets
    ADD CONSTRAINT assets_isin_key UNIQUE (isin);


--
-- TOC entry 5111 (class 2606 OID 100024)
-- Name: assets assets_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.assets
    ADD CONSTRAINT assets_pkey PRIMARY KEY (asset_id);


--
-- TOC entry 5131 (class 2606 OID 100099)
-- Name: dividends dividends_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.dividends
    ADD CONSTRAINT dividends_pkey PRIMARY KEY (dividend_id);


--
-- TOC entry 5161 (class 2606 OID 102265)
-- Name: etf_asset_allocation etf_asset_allocation_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.etf_asset_allocation
    ADD CONSTRAINT etf_asset_allocation_pkey PRIMARY KEY (asset_allocation_id);


--
-- TOC entry 5163 (class 2606 OID 102267)
-- Name: etf_asset_allocation etf_asset_allocation_unique; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.etf_asset_allocation
    ADD CONSTRAINT etf_asset_allocation_unique UNIQUE (asset_id, allocation_type);


--
-- TOC entry 5171 (class 2606 OID 102297)
-- Name: etf_bond_maturity etf_bond_maturity_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.etf_bond_maturity
    ADD CONSTRAINT etf_bond_maturity_pkey PRIMARY KEY (bond_maturity_id);


--
-- TOC entry 5167 (class 2606 OID 102282)
-- Name: etf_bond_ratings etf_bond_ratings_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.etf_bond_ratings
    ADD CONSTRAINT etf_bond_ratings_pkey PRIMARY KEY (bond_rating_id);


--
-- TOC entry 5155 (class 2606 OID 102247)
-- Name: etf_geographic_weights etf_geographic_weights_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.etf_geographic_weights
    ADD CONSTRAINT etf_geographic_weights_pkey PRIMARY KEY (geographic_weight_id);


--
-- TOC entry 5157 (class 2606 OID 102249)
-- Name: etf_geographic_weights etf_geographic_weights_unique; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.etf_geographic_weights
    ADD CONSTRAINT etf_geographic_weights_unique UNIQUE (asset_id, region_name);


--
-- TOC entry 5145 (class 2606 OID 102215)
-- Name: etf_holdings etf_holdings_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.etf_holdings
    ADD CONSTRAINT etf_holdings_pkey PRIMARY KEY (holding_id);


--
-- TOC entry 5149 (class 2606 OID 102230)
-- Name: etf_sector_weights etf_sector_weights_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.etf_sector_weights
    ADD CONSTRAINT etf_sector_weights_pkey PRIMARY KEY (sector_weight_id);


--
-- TOC entry 5151 (class 2606 OID 102232)
-- Name: etf_sector_weights etf_sector_weights_unique; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.etf_sector_weights
    ADD CONSTRAINT etf_sector_weights_unique UNIQUE (asset_id, sector_name);


--
-- TOC entry 5127 (class 2606 OID 100083)
-- Name: portfolio_snapshots portfolio_snapshots_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.portfolio_snapshots
    ADD CONSTRAINT portfolio_snapshots_pkey PRIMARY KEY (snapshot_id);


--
-- TOC entry 5129 (class 2606 OID 100085)
-- Name: portfolio_snapshots portfolio_snapshots_portfolio_id_snapshot_date_key; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.portfolio_snapshots
    ADD CONSTRAINT portfolio_snapshots_portfolio_id_snapshot_date_key UNIQUE (portfolio_id, snapshot_date);


--
-- TOC entry 5107 (class 2606 OID 100008)
-- Name: portfolios portfolios_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.portfolios
    ADD CONSTRAINT portfolios_pkey PRIMARY KEY (portfolio_id);


--
-- TOC entry 5120 (class 2606 OID 100062)
-- Name: positions positions_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.positions
    ADD CONSTRAINT positions_pkey PRIMARY KEY (position_id);


--
-- TOC entry 5122 (class 2606 OID 100064)
-- Name: positions positions_portfolio_id_asset_id_key; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.positions
    ADD CONSTRAINT positions_portfolio_id_asset_id_key UNIQUE (portfolio_id, asset_id);


--
-- TOC entry 5141 (class 2606 OID 100166)
-- Name: price_history price_history_asset_id_price_date_key; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.price_history
    ADD CONSTRAINT price_history_asset_id_price_date_key UNIQUE (asset_id, price_date);


--
-- TOC entry 5143 (class 2606 OID 100164)
-- Name: price_history price_history_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.price_history
    ADD CONSTRAINT price_history_pkey PRIMARY KEY (price_id);


--
-- TOC entry 5136 (class 2606 OID 100124)
-- Name: target_allocations target_allocations_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.target_allocations
    ADD CONSTRAINT target_allocations_pkey PRIMARY KEY (target_id);


--
-- TOC entry 5118 (class 2606 OID 100042)
-- Name: transactions transactions_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.transactions
    ADD CONSTRAINT transactions_pkey PRIMARY KEY (transaction_id);


--
-- TOC entry 5112 (class 1259 OID 100151)
-- Name: idx_assets_active; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_assets_active ON public.assets USING btree (is_active);


--
-- TOC entry 5113 (class 1259 OID 102310)
-- Name: idx_assets_composition_last_updated; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_assets_composition_last_updated ON public.assets USING btree (composition_last_updated DESC);


--
-- TOC entry 5114 (class 1259 OID 100149)
-- Name: idx_assets_isin; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_assets_isin ON public.assets USING btree (isin);


--
-- TOC entry 5115 (class 1259 OID 100142)
-- Name: idx_assets_name_search; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_assets_name_search ON public.assets USING gin (to_tsvector('italian'::regconfig, (name)::text));


--
-- TOC entry 5116 (class 1259 OID 100150)
-- Name: idx_assets_type; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_assets_type ON public.assets USING btree (asset_type);


--
-- TOC entry 5132 (class 1259 OID 100147)
-- Name: idx_dividends_asset; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_dividends_asset ON public.dividends USING btree (asset_id);


--
-- TOC entry 5133 (class 1259 OID 100148)
-- Name: idx_dividends_date; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_dividends_date ON public.dividends USING btree (payment_date DESC);


--
-- TOC entry 5134 (class 1259 OID 100146)
-- Name: idx_dividends_portfolio; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_dividends_portfolio ON public.dividends USING btree (portfolio_id);


--
-- TOC entry 5164 (class 1259 OID 102273)
-- Name: idx_etf_asset_allocation_asset_id; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_etf_asset_allocation_asset_id ON public.etf_asset_allocation USING btree (asset_id);


--
-- TOC entry 5165 (class 1259 OID 102274)
-- Name: idx_etf_asset_allocation_updated_at; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_etf_asset_allocation_updated_at ON public.etf_asset_allocation USING btree (updated_at);


--
-- TOC entry 5172 (class 1259 OID 102303)
-- Name: idx_etf_bond_maturity_asset_id; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_etf_bond_maturity_asset_id ON public.etf_bond_maturity USING btree (asset_id);


--
-- TOC entry 5173 (class 1259 OID 102304)
-- Name: idx_etf_bond_maturity_updated_at; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_etf_bond_maturity_updated_at ON public.etf_bond_maturity USING btree (updated_at);


--
-- TOC entry 5168 (class 1259 OID 102288)
-- Name: idx_etf_bond_ratings_asset_id; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_etf_bond_ratings_asset_id ON public.etf_bond_ratings USING btree (asset_id);


--
-- TOC entry 5169 (class 1259 OID 102289)
-- Name: idx_etf_bond_ratings_updated_at; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_etf_bond_ratings_updated_at ON public.etf_bond_ratings USING btree (updated_at);


--
-- TOC entry 5158 (class 1259 OID 102255)
-- Name: idx_etf_geographic_weights_asset_id; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_etf_geographic_weights_asset_id ON public.etf_geographic_weights USING btree (asset_id);


--
-- TOC entry 5159 (class 1259 OID 102256)
-- Name: idx_etf_geographic_weights_updated_at; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_etf_geographic_weights_updated_at ON public.etf_geographic_weights USING btree (updated_at);


--
-- TOC entry 5146 (class 1259 OID 102221)
-- Name: idx_etf_holdings_asset_id; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_etf_holdings_asset_id ON public.etf_holdings USING btree (asset_id);


--
-- TOC entry 5147 (class 1259 OID 102222)
-- Name: idx_etf_holdings_updated_at; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_etf_holdings_updated_at ON public.etf_holdings USING btree (updated_at);


--
-- TOC entry 5152 (class 1259 OID 102238)
-- Name: idx_etf_sector_weights_asset_id; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_etf_sector_weights_asset_id ON public.etf_sector_weights USING btree (asset_id);


--
-- TOC entry 5153 (class 1259 OID 102239)
-- Name: idx_etf_sector_weights_updated_at; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_etf_sector_weights_updated_at ON public.etf_sector_weights USING btree (updated_at);


--
-- TOC entry 5137 (class 1259 OID 100172)
-- Name: idx_price_history_asset; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_price_history_asset ON public.price_history USING btree (asset_id);


--
-- TOC entry 5138 (class 1259 OID 100174)
-- Name: idx_price_history_asset_date; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_price_history_asset_date ON public.price_history USING btree (asset_id, price_date DESC);


--
-- TOC entry 5139 (class 1259 OID 100173)
-- Name: idx_price_history_date; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_price_history_date ON public.price_history USING btree (price_date DESC);


--
-- TOC entry 5123 (class 1259 OID 100144)
-- Name: idx_snapshots_date; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_snapshots_date ON public.portfolio_snapshots USING btree (snapshot_date DESC);


--
-- TOC entry 5124 (class 1259 OID 100143)
-- Name: idx_snapshots_portfolio; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_snapshots_portfolio ON public.portfolio_snapshots USING btree (portfolio_id);


--
-- TOC entry 5125 (class 1259 OID 100145)
-- Name: idx_snapshots_portfolio_date; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_snapshots_portfolio_date ON public.portfolio_snapshots USING btree (portfolio_id, snapshot_date DESC);


--
-- TOC entry 5190 (class 2620 OID 100154)
-- Name: assets update_assets_updated_at; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER update_assets_updated_at BEFORE UPDATE ON public.assets FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();


--
-- TOC entry 5189 (class 2620 OID 100153)
-- Name: portfolios update_portfolios_updated_at; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER update_portfolios_updated_at BEFORE UPDATE ON public.portfolios FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();


--
-- TOC entry 5191 (class 2620 OID 100191)
-- Name: transactions update_position_on_transaction; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER update_position_on_transaction AFTER INSERT ON public.transactions FOR EACH ROW EXECUTE FUNCTION public.update_position_after_transaction();


--
-- TOC entry 5193 (class 2620 OID 100156)
-- Name: positions update_positions_updated_at; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER update_positions_updated_at BEFORE UPDATE ON public.positions FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();


--
-- TOC entry 5194 (class 2620 OID 100157)
-- Name: target_allocations update_target_allocations_updated_at; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER update_target_allocations_updated_at BEFORE UPDATE ON public.target_allocations FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();


--
-- TOC entry 5192 (class 2620 OID 100155)
-- Name: transactions update_transactions_updated_at; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER update_transactions_updated_at BEFORE UPDATE ON public.transactions FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();


--
-- TOC entry 5179 (class 2606 OID 100105)
-- Name: dividends dividends_asset_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.dividends
    ADD CONSTRAINT dividends_asset_id_fkey FOREIGN KEY (asset_id) REFERENCES public.assets(asset_id);


--
-- TOC entry 5180 (class 2606 OID 100100)
-- Name: dividends dividends_portfolio_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.dividends
    ADD CONSTRAINT dividends_portfolio_id_fkey FOREIGN KEY (portfolio_id) REFERENCES public.portfolios(portfolio_id) ON DELETE CASCADE;


--
-- TOC entry 5186 (class 2606 OID 102268)
-- Name: etf_asset_allocation etf_asset_allocation_asset_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.etf_asset_allocation
    ADD CONSTRAINT etf_asset_allocation_asset_fkey FOREIGN KEY (asset_id) REFERENCES public.assets(asset_id) ON DELETE CASCADE;


--
-- TOC entry 5188 (class 2606 OID 102298)
-- Name: etf_bond_maturity etf_bond_maturity_asset_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.etf_bond_maturity
    ADD CONSTRAINT etf_bond_maturity_asset_fkey FOREIGN KEY (asset_id) REFERENCES public.assets(asset_id) ON DELETE CASCADE;


--
-- TOC entry 5187 (class 2606 OID 102283)
-- Name: etf_bond_ratings etf_bond_ratings_asset_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.etf_bond_ratings
    ADD CONSTRAINT etf_bond_ratings_asset_fkey FOREIGN KEY (asset_id) REFERENCES public.assets(asset_id) ON DELETE CASCADE;


--
-- TOC entry 5185 (class 2606 OID 102250)
-- Name: etf_geographic_weights etf_geographic_weights_asset_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.etf_geographic_weights
    ADD CONSTRAINT etf_geographic_weights_asset_fkey FOREIGN KEY (asset_id) REFERENCES public.assets(asset_id) ON DELETE CASCADE;


--
-- TOC entry 5183 (class 2606 OID 102216)
-- Name: etf_holdings etf_holdings_asset_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.etf_holdings
    ADD CONSTRAINT etf_holdings_asset_fkey FOREIGN KEY (asset_id) REFERENCES public.assets(asset_id) ON DELETE CASCADE;


--
-- TOC entry 5184 (class 2606 OID 102233)
-- Name: etf_sector_weights etf_sector_weights_asset_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.etf_sector_weights
    ADD CONSTRAINT etf_sector_weights_asset_fkey FOREIGN KEY (asset_id) REFERENCES public.assets(asset_id) ON DELETE CASCADE;


--
-- TOC entry 5178 (class 2606 OID 100086)
-- Name: portfolio_snapshots portfolio_snapshots_portfolio_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.portfolio_snapshots
    ADD CONSTRAINT portfolio_snapshots_portfolio_id_fkey FOREIGN KEY (portfolio_id) REFERENCES public.portfolios(portfolio_id) ON DELETE CASCADE;


--
-- TOC entry 5176 (class 2606 OID 100070)
-- Name: positions positions_asset_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.positions
    ADD CONSTRAINT positions_asset_id_fkey FOREIGN KEY (asset_id) REFERENCES public.assets(asset_id);


--
-- TOC entry 5177 (class 2606 OID 100065)
-- Name: positions positions_portfolio_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.positions
    ADD CONSTRAINT positions_portfolio_id_fkey FOREIGN KEY (portfolio_id) REFERENCES public.portfolios(portfolio_id) ON DELETE CASCADE;


--
-- TOC entry 5182 (class 2606 OID 100167)
-- Name: price_history price_history_asset_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.price_history
    ADD CONSTRAINT price_history_asset_id_fkey FOREIGN KEY (asset_id) REFERENCES public.assets(asset_id) ON DELETE CASCADE;


--
-- TOC entry 5181 (class 2606 OID 100125)
-- Name: target_allocations target_allocations_portfolio_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.target_allocations
    ADD CONSTRAINT target_allocations_portfolio_id_fkey FOREIGN KEY (portfolio_id) REFERENCES public.portfolios(portfolio_id) ON DELETE CASCADE;


--
-- TOC entry 5174 (class 2606 OID 100048)
-- Name: transactions transactions_asset_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.transactions
    ADD CONSTRAINT transactions_asset_id_fkey FOREIGN KEY (asset_id) REFERENCES public.assets(asset_id);


--
-- TOC entry 5175 (class 2606 OID 100043)
-- Name: transactions transactions_portfolio_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.transactions
    ADD CONSTRAINT transactions_portfolio_id_fkey FOREIGN KEY (portfolio_id) REFERENCES public.portfolios(portfolio_id) ON DELETE CASCADE;


-- Completed on 2025-11-10 19:43:56

--
-- PostgreSQL database dump complete
--

