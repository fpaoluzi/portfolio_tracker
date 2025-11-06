import { apiClient } from './client';
import type { Transaction, TransactionFormData } from '@/types';

export const transactionsApi = {
  getByPortfolio: (portfolioId: string, limit = 100, offset = 0) =>
    apiClient.get<Transaction[]>(`/portfolios/${portfolioId}/transactions?limit=${limit}&offset=${offset}`),

  create: (data: TransactionFormData & { portfolio_id: string }) =>
    apiClient.post<Transaction>('/transactions', data),

  update: (id: string, data: TransactionFormData & { portfolio_id: string }) =>
    apiClient.put<Transaction>(`/transactions/${id}`, data),

  delete: (id: string) =>
    apiClient.delete<{ message: string; transaction: Transaction }>(`/transactions/${id}`),
};
