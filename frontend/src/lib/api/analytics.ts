import { apiClient } from './client';
import type { Position, Performance, Allocation, Snapshot } from '@/types';

export const analyticsApi = {
  getPositions: (portfolioId: string) =>
    apiClient.get<Position[]>(`/portfolios/${portfolioId}/positions`),

  getPerformance: (portfolioId: string) =>
    apiClient.get<Performance>(`/portfolios/${portfolioId}/performance`),

  getAllocation: (portfolioId: string) =>
    apiClient.get<Allocation[]>(`/portfolios/${portfolioId}/allocation`),

  getSnapshots: (portfolioId: string, days = 365) =>
    apiClient.get<Snapshot[]>(`/portfolios/${portfolioId}/snapshots?days=${days}`),
};
