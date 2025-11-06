import { apiClient } from './client';
import type { Asset, AssetFormData } from '@/types';

export const assetsApi = {
  getAll: () => apiClient.get<Asset[]>('/assets'),

  getByIsin: (isin: string) => apiClient.get<Asset>(`/assets/isin/${isin}`),

  create: (data: AssetFormData) => apiClient.post<Asset>('/assets', data),

  update: (id: string, data: AssetFormData) =>
    apiClient.put<Asset>(`/assets/${id}`, data),

  delete: (id: string) =>
    apiClient.delete<{ message: string; asset: Asset }>(`/assets/${id}`),
};
