// ============================================
// ETF COMPOSITION API CLIENT
// API calls for ETF composition data
// ============================================

import { apiClient } from './client';

export interface Holding {
  holding_id: string;
  asset_id: string;
  holding_symbol: string | null;
  holding_name: string;
  holding_percent: number;
  rank_position: number;
  updated_at: string;
}

export interface SectorWeight {
  sector_weight_id: string;
  asset_id: string;
  sector_name: string;
  weight_percent: number;
  updated_at: string;
}

export interface GeographicWeight {
  geographic_weight_id: string;
  asset_id: string;
  region_name: string;
  weight_percent: number;
  updated_at: string;
}

export interface AssetAllocation {
  asset_allocation_id: string;
  asset_id: string;
  allocation_type: 'Equity' | 'Bond' | 'Cash' | 'Other' | 'Commodity' | 'Real Estate';
  weight_percent: number;
  updated_at: string;
}

export interface BondRating {
  bond_rating_id: string;
  asset_id: string;
  rating_category: string;
  weight_percent: number;
  updated_at: string;
}

export interface BondMaturity {
  bond_maturity_id: string;
  asset_id: string;
  maturity_range: string;
  weight_percent: number;
  avg_duration_years: number | null;
  updated_at: string;
}

export interface ETFComposition {
  holdings: Holding[];
  sectors: SectorWeight[];
  regions: GeographicWeight[];
  allocation: AssetAllocation[];
  bondRatings: BondRating[];
  bondMaturity: BondMaturity[];
  hasData: boolean;
}

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

/**
 * Get ETF composition data for a single asset
 */
export async function getCompositionByAsset(assetId: string): Promise<ETFComposition> {
  return await apiClient.get<ETFComposition>(`/etf-composition/asset/${assetId}`);
}

/**
 * Fetch and save ETF composition from Yahoo Finance
 */
export async function fetchAndSaveComposition(assetId: string): Promise<{
  success: boolean;
  message: string;
  stats: {
    holdings: number;
    sectors: number;
    regions: number;
    allocation: number;
    bondRatings: number;
    bondMaturity: number;
  };
}> {
  return await apiClient.post<{
    success: boolean;
    message: string;
    stats: {
      holdings: number;
      sectors: number;
      regions: number;
      allocation: number;
      bondRatings: number;
      bondMaturity: number;
    };
  }>(`/etf-composition/asset/${assetId}/fetch`, {});
}

/**
 * Get aggregated composition for a portfolio
 * Uses new modular API endpoints with correct look-through calculations
 */
export async function getPortfolioComposition(portfolioId: string, expand: boolean = false): Promise<PortfolioComposition> {
  const expandParam = expand ? '?expand=true' : '';
  // Call all modular endpoints in parallel
  const [holdingsRes, sectorsRes, regionsRes, allocationRes, bondRatingsRes, bondMaturityRes] = await Promise.all([
    apiClient.get<{ holdings?: AggregatedHolding[] }>(`/composition/holdings/portfolio/${portfolioId}${expandParam}`).catch(() => ({ holdings: [] })),
    apiClient.get<{ sectors?: AggregatedSector[] }>(`/composition/sectors/portfolio/${portfolioId}${expandParam}`).catch(() => ({ sectors: [] })),
    apiClient.get<{ regions?: AggregatedRegion[] }>(`/composition/geographic/portfolio/${portfolioId}${expandParam}`).catch(() => ({ regions: [] })),
    apiClient.get<{ allocation?: AggregatedAllocation[] }>(`/composition/allocation/portfolio/${portfolioId}${expandParam}`).catch(() => ({ allocation: [] })),
    apiClient.get<{ bondRatings?: AggregatedBondRating[] }>(`/composition/bond-ratings/portfolio/${portfolioId}${expandParam}`).catch(() => ({ bondRatings: [] })),
    apiClient.get<{ bondMaturity?: AggregatedBondMaturity[] }>(`/composition/bond-maturity/portfolio/${portfolioId}${expandParam}`).catch(() => ({ bondMaturity: [] })),
  ]);

  return {
    holdings: holdingsRes.holdings || [],
    sectors: sectorsRes.sectors || [],
    regions: regionsRes.regions || [],
    allocation: allocationRes.allocation || [],
    bondRatings: bondRatingsRes.bondRatings || [],
    bondMaturity: bondMaturityRes.bondMaturity || [],
  };
}

/**
 * Get aggregated composition for multiple portfolios
 * Uses new modular API endpoints with correct look-through calculations
 */
export async function getMultiplePortfoliosComposition(
  portfolioIds: string[],
  expand: boolean = false
): Promise<PortfolioComposition> {
  const portfolioIdsParam = portfolioIds.join(',');
  const expandParam = expand ? '&expand=true' : '';

  // Call all modular endpoints in parallel
  const [holdingsRes, sectorsRes, regionsRes, allocationRes, bondRatingsRes, bondMaturityRes] = await Promise.all([
    apiClient.get<{ holdings?: AggregatedHolding[] }>(`/composition/holdings/portfolios/multiple?portfolioIds=${portfolioIdsParam}${expandParam}`).catch(() => ({ holdings: [] })),
    apiClient.get<{ sectors?: AggregatedSector[] }>(`/composition/sectors/portfolios/multiple?portfolioIds=${portfolioIdsParam}${expandParam}`).catch(() => ({ sectors: [] })),
    apiClient.get<{ regions?: AggregatedRegion[] }>(`/composition/geographic/portfolios/multiple?portfolioIds=${portfolioIdsParam}${expandParam}`).catch(() => ({ regions: [] })),
    apiClient.get<{ allocation?: AggregatedAllocation[] }>(`/composition/allocation/portfolios/multiple?portfolioIds=${portfolioIdsParam}${expandParam}`).catch(() => ({ allocation: [] })),
    apiClient.get<{ bondRatings?: AggregatedBondRating[] }>(`/composition/bond-ratings/portfolios/multiple?portfolioIds=${portfolioIdsParam}${expandParam}`).catch(() => ({ bondRatings: [] })),
    apiClient.get<{ bondMaturity?: AggregatedBondMaturity[] }>(`/composition/bond-maturity/portfolios/multiple?portfolioIds=${portfolioIdsParam}${expandParam}`).catch(() => ({ bondMaturity: [] })),
  ]);

  return {
    holdings: holdingsRes.holdings || [],
    sectors: sectorsRes.sectors || [],
    regions: regionsRes.regions || [],
    allocation: allocationRes.allocation || [],
    bondRatings: bondRatingsRes.bondRatings || [],
    bondMaturity: bondMaturityRes.bondMaturity || [],
  };
}

/**
 * Get aggregated composition for multiple assets
 * Uses new modular API endpoints with correct look-through calculations
 */
export async function getMultipleAssetsComposition(
  assetIds: string[],
  portfolioId?: string,
  expand: boolean = false
): Promise<PortfolioComposition> {
  const assetIdsParam = assetIds.join(',');
  const portfolioParam = portfolioId ? `&portfolioId=${portfolioId}` : '';
  const expandParam = expand ? `&expand=true` : '';

  // Call all modular endpoints in parallel
  const [holdingsRes, sectorsRes, regionsRes, allocationRes, bondRatingsRes, bondMaturityRes] = await Promise.all([
    apiClient.get<{ holdings?: AggregatedHolding[] }>(`/composition/holdings/assets/multiple?assetIds=${assetIdsParam}${portfolioParam}${expandParam}`).catch(() => ({ holdings: [] })),
    apiClient.get<{ sectors?: AggregatedSector[] }>(`/composition/sectors/assets/multiple?assetIds=${assetIdsParam}${portfolioParam}${expandParam}`).catch(() => ({ sectors: [] })),
    apiClient.get<{ regions?: AggregatedRegion[] }>(`/composition/geographic/assets/multiple?assetIds=${assetIdsParam}${portfolioParam}${expandParam}`).catch(() => ({ regions: [] })),
    apiClient.get<{ allocation?: AggregatedAllocation[] }>(`/composition/allocation/assets/multiple?assetIds=${assetIdsParam}${portfolioParam}${expandParam}`).catch(() => ({ allocation: [] })),
    apiClient.get<{ bondRatings?: AggregatedBondRating[] }>(`/composition/bond-ratings/assets/multiple?assetIds=${assetIdsParam}${portfolioParam}${expandParam}`).catch(() => ({ bondRatings: [] })),
    apiClient.get<{ bondMaturity?: AggregatedBondMaturity[] }>(`/composition/bond-maturity/assets/multiple?assetIds=${assetIdsParam}${portfolioParam}${expandParam}`).catch(() => ({ bondMaturity: [] })),
  ]);

  return {
    holdings: holdingsRes.holdings || [],
    sectors: sectorsRes.sectors || [],
    regions: regionsRes.regions || [],
    allocation: allocationRes.allocation || [],
    bondRatings: bondRatingsRes.bondRatings || [],
    bondMaturity: bondMaturityRes.bondMaturity || [],
  };
}

/**
 * Bulk update compositions for all assets (fire-and-forget)
 * Returns immediately, processing happens in background
 */
export async function bulkUpdateCompositions(assetIds?: string[]): Promise<{
  success: boolean;
  message: string;
  assetsCount: number;
}> {
  return await apiClient.post<{
    success: boolean;
    message: string;
    assetsCount: number;
  }>('/etf-composition/bulk-update', { assetIds });
}

/**
 * Delete composition data for a single asset
 * Does NOT delete the asset itself, only composition data (holdings, sectors, regions, bond data)
 */
export async function deleteComposition(assetId: string): Promise<{
  success: boolean;
  message: string;
  deletedRecords: {
    holdings: number;
    sectors: number;
    regions: number;
    allocation: number;
    bondRatings: number;
    bondMaturity: number;
    total: number;
  };
}> {
  return await apiClient.delete<{
    success: boolean;
    message: string;
    deletedRecords: {
      holdings: number;
      sectors: number;
      regions: number;
      allocation: number;
      bondRatings: number;
      bondMaturity: number;
      total: number;
    };
  }>(`/etf-composition/asset/${assetId}`);
}

export interface ManualCompositionData {
  holdings?: Array<{
    symbol?: string;
    name: string;
    percent: number;
    rank?: number;
  }>;
  sectors?: Array<{
    name: string;
    percent: number;
  }>;
  regions?: Array<{
    name: string;
    percent: number;
  }>;
  allocation?: Array<{
    type: string;
    percent: number;
  }>;
  bondRatings?: Array<{
    category: string;
    percent: number;
  }>;
  bondMaturity?: Array<{
    range: string;
    percent: number;
    duration?: number;
  }>;
}

/**
 * Save manually entered composition data for an asset
 */
export async function saveManualComposition(
  assetId: string,
  data: ManualCompositionData
): Promise<{
  success: boolean;
  message: string;
  stats: {
    holdings: number;
    sectors: number;
    regions: number;
    allocation: number;
    bondRatings: number;
    bondMaturity: number;
  };
}> {
  return await apiClient.post<{
    success: boolean;
    message: string;
    stats: {
      holdings: number;
      sectors: number;
      regions: number;
      allocation: number;
      bondRatings: number;
      bondMaturity: number;
    };
  }>(`/etf-composition/asset/${assetId}/manual`, data);
}

// Detail interfaces for click functionality
export interface HoldingDetail {
  asset_id: string;
  ticker: string;
  asset_name: string;
  current_value: number;
  holding_percent: number;
  holding_value: number;
  contribution_percent: number;
}

export interface SectorDetail {
  asset_id: string;
  ticker: string;
  asset_name: string;
  current_value: number;
  sector_percent: number;
  sector_value: number;
  contribution_percent: number;
}

export interface RegionDetail {
  asset_id: string;
  ticker: string;
  asset_name: string;
  current_value: number;
  region_percent: number;
  region_value: number;
  contribution_percent: number;
}

export interface AllocationDetail {
  asset_id: string;
  ticker: string;
  asset_name: string;
  current_value: number;
  allocation_percent: number;
  allocation_value: number;
  contribution_percent: number;
}

export interface BondRatingDetail {
  asset_id: string;
  ticker: string;
  asset_name: string;
  current_value: number;
  rating_percent: number;
  rating_value: number;
  contribution_percent: number;
}

export interface BondMaturityDetail {
  asset_id: string;
  ticker: string;
  asset_name: string;
  current_value: number;
  maturity_percent: number;
  maturity_value: number;
  contribution_percent: number;
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

/**
 * Get detail for a specific holding
 */
export async function getHoldingDetail(portfolioId: string, holdingSymbol?: string, holdingName?: string): Promise<{
  holding_symbol?: string;
  holding_name?: string;
  details: HoldingDetail[];
  total_value: number;
  count: number;
}> {
  const params = new URLSearchParams({ portfolioId });
  if (holdingSymbol) params.append('holdingSymbol', holdingSymbol);
  if (holdingName) params.append('holdingName', holdingName);
  return await apiClient.get(`/composition/holdings/detail?${params.toString()}`);
}

/**
 * Get detail for a specific sector
 */
export async function getSectorDetail(portfolioId: string, sectorName: string): Promise<{
  sector_name: string;
  details: SectorDetail[];
  total_value: number;
  count: number;
}> {
  return await apiClient.get(`/composition/sectors/detail?portfolioId=${portfolioId}&sectorName=${encodeURIComponent(sectorName)}`);
}

/**
 * Get detail for a specific region
 */
export async function getRegionDetail(portfolioId: string, regionName: string): Promise<{
  region_name: string;
  details: RegionDetail[];
  total_value: number;
  count: number;
}> {
  return await apiClient.get(`/composition/geographic/detail?portfolioId=${portfolioId}&regionName=${encodeURIComponent(regionName)}`);
}

/**
 * Get risk statistics for a portfolio
 */
export async function getPortfolioRiskStats(portfolioId: string): Promise<RiskStats> {
  return await apiClient.get(`/composition/risk-stats/portfolio/${portfolioId}`);
}

/**
 * Get risk statistics for multiple assets
 */
export async function getMultipleAssetsRiskStats(
  assetIds: string[],
  portfolioId?: string
): Promise<RiskStats> {
  const assetIdsParam = assetIds.join(',');
  const portfolioParam = portfolioId ? `&portfolioId=${portfolioId}` : '';
  return await apiClient.get(`/composition/risk-stats/assets/multiple?assetIds=${assetIdsParam}${portfolioParam}`);
}

