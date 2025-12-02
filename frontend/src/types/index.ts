// ============================================
// TYPE DEFINITIONS
// ============================================

export interface Portfolio {
  portfolio_id: string;
  name: string;
  broker?: string;
  account_number?: string;
  currency: string;
  notes?: string;
  is_active: boolean;
  created_at: string;
  updated_at: string;
}

export interface Asset {
  asset_id: string;
  isin: string;
  ticker?: string;
  name: string;
  asset_type: 'Azionario' | 'Obbligazionario' | 'Monetario' | 'Oro' | 'Crypto' | 'ETF' | 'Azione Singola' | 'Obbligazione Singola';
  asset_category?: string;
  currency: string;
  country?: string;
  region?: string;
  sector?: string;
  industry?: string;
  benchmark_index?: string;
  ter?: number;
  transaction_cost?: number;
  esg_rating?: string;
  is_accumulation?: boolean;
  description?: string;
  sharpe_ratio?: number;
  annual_fees?: number;
  standard_deviation?: number;
  isr?: number;
  factsheet_url?: string;
  composition_last_updated?: string;
  is_active: boolean;
  created_at: string;
  updated_at: string;
}

export interface Transaction {
  transaction_id: string;
  portfolio_id: string;
  asset_id: string;
  transaction_type: 'BUY' | 'SELL';
  transaction_date: string;
  quantity: number;
  price_per_share: number;
  total_amount: number;
  commission: number;
  fees: number;
  taxes?: number;
  currency: string;
  exchange_rate: number;
  amount_in_base_currency: number;
  notes?: string;
  asset_name?: string;
  isin?: string;
  created_at: string;
}

export interface Position {
  position_id: string;
  portfolio_id: string;
  portfolio_name: string;
  asset_id: string;
  asset_name: string;
  isin: string;
  asset_type: string;
  country?: string;
  sector?: string;
  quantity: number | string;
  average_buy_price: number | string;
  current_price: number | string;
  current_value: number | string;
  total_invested: number | string;
  gross_buy_invested?: number | string;
  gain_loss: number | string;
  gain_loss_pct: number | string;
  last_price_date?: string;
  ownership_pct?: number | string;
  invested_pct?: number | string;
}

export interface Performance {
  portfolio_id: string;
  portfolio_name: string;
  current_value: number | string;
  total_invested: number | string;
  total_gain_loss: number | string;
  total_gain_loss_pct: number | string;
  number_of_positions?: number;
}

export interface Allocation {
  portfolio_id: string;
  portfolio_name: string;
  asset_type: string;
  total_value: number | string;
  percentage: number | string;
}

export interface Snapshot {
  snapshot_id: string;
  portfolio_id: string;
  snapshot_date: string;
  total_value: number | string;
  total_invested: number | string;
  total_gain_loss: number | string;
  total_gain_loss_pct: number | string;
}

export interface TargetAllocation {
  target_id: string;
  portfolio_id: string;
  allocation_name: string;
  target_azionario: number;
  target_obbligazionario: number;
  target_monetario: number;
  target_oro: number;
  target_crypto: number;
  is_active: boolean;
  created_at: string;
  updated_at: string;
}

export interface GeoAllocation {
  name: string;
  value: number;
}

export interface SimulationResult {
  mode: 'target' | 'manual';
  currentTotal: number;
  newTotal: number;
  newCapital: number;
  totalAllocated?: number;
  remaining?: number;
  suggestions: {
    [key: string]: {
      current: number;
      target?: number;
      toInvest: number;
      newValue?: number;
      currentPct: number;
      targetPct?: number;
      newPct: number;
    };
  };
}

export interface PortfolioFormData {
  name: string;
  broker: string;
  currency: string;
  notes: string;
}

export interface AssetFormData {
  isin: string;
  name: string;
  ticker: string;
  asset_type: Asset['asset_type'];
  sector: string;
  country: string;
  region: string;
  currency: string;
  ter: number;
  sharpe_ratio: number;
  annual_fees: number;
  standard_deviation: number;
  isr: number;
  factsheet_url: string;
}

export interface TransactionFormData {
  asset_id: string;
  transaction_type: 'BUY' | 'SELL';
  transaction_date: string;
  quantity: number;
  price_per_share: number;
  commission: number;
  fees: number;
  notes: string;
}

export interface TargetFormData {
  target_azionario: number;
  target_obbligazionario: number;
  target_monetario: number;
  target_oro: number;
  target_crypto: number;
}

export interface MonthlyPerformance {
  performance_id: string;
  portfolio_id: string;
  asset_id: string;
  asset_name: string;
  ticker?: string;
  asset_type: string;
  month_year: string;
  quantity: number | string;
  average_buy_price: number | string;
  month_start_price: number | string;
  month_end_price: number | string;
  month_return_pct: number | string;
  total_invested: number | string;
  month_start_value: number | string;
  month_end_value: number | string;
  unrealized_gain_loss: number | string;
}

export interface MonthlyPortfolioPerformance {
  portfolio_id: string;
  portfolio_name: string;
  month_year: string;
  num_positions: number;
  total_invested: number | string;
  month_end_value: number | string;
  total_unrealized_gain_loss: number | string;
  total_return_pct: number | string;
  weighted_monthly_return_pct: number | string;
}
