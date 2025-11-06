// ============================================
// FORMATTING UTILITIES
// ============================================

export const formatCurrency = (value: number | string, currency = 'EUR'): string => {
  const numValue = typeof value === 'string' ? parseFloat(value) : value;
  return new Intl.NumberFormat('it-IT', {
    style: 'currency',
    currency
  }).format(numValue || 0);
};

export const formatPercent = (value: number | string): string => {
  const numValue = typeof value === 'string' ? parseFloat(value) : value;
  return `${numValue >= 0 ? '+' : ''}${(numValue || 0).toFixed(2)}%`;
};

export const formatDate = (date: string | Date): string => {
  const dateObj = typeof date === 'string' ? new Date(date) : date;
  return dateObj.toLocaleDateString('it-IT');
};

export const formatNumber = (value: number | string, decimals = 2): string => {
  const numValue = typeof value === 'string' ? parseFloat(value) : value;
  return numValue.toFixed(decimals);
};
