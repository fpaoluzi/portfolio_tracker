/**
 * TypeScript types for rebalancing and allocation features
 */

export interface AllocationCategory {
    category_id: string;
    portfolio_id: string;
    category_name: string;
    target_percent: number;
    display_order: number;
    color_hex: string;
    is_active: boolean;
    created_at: string;
    updated_at: string;
}

export interface DriftAnalysis {
    category_id: string;
    category_name: string;
    target_percent: number;
    current_value: number;
    current_percent: number;
    drift_percent: number;
    drift_value: number;
    status: 'overweight' | 'underweight' | 'balanced';
    color_hex: string;
}

export interface DriftAnalysisResponse {
    categories: DriftAnalysis[];
    totalValue: number;
    portfolioId: string;
    warning?: string | null;
}

export interface SmartDepositAllocation {
    category_id: string;
    category_name: string;
    amount: number;
    reason: string;
    current_value: number;
    new_value: number;
}

export interface ProjectedDrift extends DriftAnalysis {
    new_value: number;
    new_percent: number;
    new_drift_percent: number;
}

export interface SmartDepositResponse {
    deposit_amount: number;
    allocations: SmartDepositAllocation[];
    projected_drift: ProjectedDrift[];
    new_total_value: number;
}

export interface SimulatedAllocation {
    category_id: string;
    category_name: string;
    target_percent: number;
    current_value: number;
    current_percent: number;
    new_value: number;
    new_percent: number;
    change_percent: number;
    new_drift_percent: number;
    color_hex: string;
}

export interface SimulationResponse {
    category_name: string;
    transaction_amount: number;
    current_total_value: number;
    new_total_value: number;
    projected_allocations: SimulatedAllocation[];
}

export interface ValidationResult {
    isValid: boolean;
    total: number;
    error: string | null;
}

export interface CategoriesResponse {
    categories: AllocationCategory[];
    validation: ValidationResult;
}
