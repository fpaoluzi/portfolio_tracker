/**
 * TypeScript types for composition analysis components
 */

export interface AggregatedHolding {
    holding_symbol: string | null;
    holding_name: string;
    weighted_percent: number;
}

export interface AggregatedSector {
    sector_name: string;
    weighted_percent: number;
}

export interface AggregatedRegion {
    region_name: string;
    weighted_percent: number;
}

export interface AggregatedAllocation {
    allocation_type: string;
    weighted_percent: number;
}

export interface AggregatedBondRating {
    rating_category: string;
    weighted_percent: number;
}

export interface AggregatedBondMaturity {
    maturity_range: string;
    weighted_percent: number;
    avg_duration_years: number | null;
}

export interface PortfolioComposition {
    holdings: AggregatedHolding[];
    sectors: AggregatedSector[];
    regions: AggregatedRegion[];
    allocation: AggregatedAllocation[];
    bondRatings: AggregatedBondRating[];
    bondMaturity: AggregatedBondMaturity[];
}

export interface RiskStatsDetail {
    asset_id: string;
    ticker: string | null;
    asset_name: string;
    isr: number | null;
    standard_deviation: number | null;
    sharpe_ratio: number | null;
    current_value: number;
    weight_percent: number;
}

export interface RiskStats {
    isr: number | null;
    standard_deviation: number | null;
    sharpe_ratio: number | null;
    asset_count: number;
    total_value: number;
    details: RiskStatsDetail[];
}

export interface ChartDataItem {
    name: string;
    value: number;
    symbol?: string;
    duration?: number | null;
}
