// ============================================
// ASSET HELPERS
// Utility functions for asset type checking
// ============================================

/**
 * Check if an asset type can have composition data
 */
export const canHaveComposition = (assetType: string): boolean => {
  return ['Azionario', 'Obbligazionario', 'ETF', 'Azione Singola', 'Obbligazione Singola'].includes(assetType);
};

/**
 * Check if an asset type is equity-based
 */
export const isEquityType = (assetType: string): boolean => {
  return ['Azionario', 'Azione Singola'].includes(assetType);
};

/**
 * Check if an asset type is bond-based
 */
export const isBondType = (assetType: string): boolean => {
  return ['Obbligazionario', 'Obbligazione Singola'].includes(assetType);
};
