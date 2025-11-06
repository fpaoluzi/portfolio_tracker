import { apiClient } from './client';
import type { Position, Performance, Allocation, Snapshot, TargetAllocation, TargetFormData } from '@/types';

export const analyticsApi = {
  getPositions: (portfolioId: string) =>
    apiClient.get<Position[]>(`/portfolios/${portfolioId}/positions`),

  getPerformance: (portfolioId: string) =>
    apiClient.get<Performance>(`/portfolios/${portfolioId}/performance`),

  getAllocation: (portfolioId: string) =>
    apiClient.get<Allocation[]>(`/portfolios/${portfolioId}/allocation`),

  getSnapshots: (portfolioId: string, days = 365) =>
    apiClient.get<Snapshot[]>(`/portfolios/${portfolioId}/snapshots?days=${days}`),

  getTargetAllocation: (portfolioId: string) =>
    apiClient.get<TargetAllocation>(`/target-allocations/${portfolioId}`),

  createTargetAllocation: (data: TargetFormData & { portfolio_id: string; allocation_name: string }) =>
    apiClient.post<TargetAllocation>('/target-allocations', data),

  updateTargetAllocation: (id: string, data: TargetFormData & { allocation_name: string }) =>
    apiClient.put<TargetAllocation>(`/target-allocations/${id}`, data),
};
