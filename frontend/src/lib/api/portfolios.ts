import { apiClient } from './client';
import type { Portfolio, PortfolioFormData } from '@/types';

export const portfoliosApi = {
  getAll: () => apiClient.get<Portfolio[]>('/portfolios'),

  getById: (id: string) => apiClient.get<Portfolio>(`/portfolios/${id}`),

  create: (data: PortfolioFormData) => apiClient.post<Portfolio>('/portfolios', data),

  update: (id: string, data: PortfolioFormData) =>
    apiClient.put<Portfolio>(`/portfolios/${id}`, data),

  delete: (id: string) =>
    apiClient.delete<{ message: string; portfolio: Portfolio }>(`/portfolios/${id}`),

  updatePrices: (id: string) => apiClient.post(`/portfolios/${id}/update-prices`, {}),
};
