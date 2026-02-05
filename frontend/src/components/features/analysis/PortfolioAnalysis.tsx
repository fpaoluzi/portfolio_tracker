import React, { useState, useEffect } from 'react';
import { Loader2, RefreshCw, Filter, TrendingUp } from 'lucide-react';
import { Button } from '../../ui/Button';
import { Modal } from '../../ui/Modal';
import {
  getMultipleAssetsComposition,
  getMultipleAssetsRiskStats,
} from '../../../lib/api';
import { assetsApi } from '../../../lib/api';
import { isEquityType, isBondType, canHaveComposition } from '../../../lib/utils/assetHelpers';
import type { Asset } from '../../../types';

// Import new components
import { PortfolioSummary } from './shared/PortfolioSummary';
import { EquityAnalysis } from './equity/EquityAnalysis';
import { BondAnalysis } from './bond/BondAnalysis';

import { PortfolioComposition, RiskStats } from './utils/types';
import { isAltriVariation, filterAndSumAltri } from './utils/altriNormalization';

interface PortfolioAnalysisProps {
  availablePortfolios: Array<{ portfolio_id: string; name: string }>;
  selectedPortfolioId: string | null;
}

export const PortfolioAnalysis: React.FC<PortfolioAnalysisProps> = ({
  availablePortfolios,
  selectedPortfolioId,
}) => {
  const [selectedAssets, setSelectedAssets] = useState<Asset[]>([]);
  const [composition, setComposition] = useState<PortfolioComposition | null>(null);
  const [riskStats, setRiskStats] = useState<RiskStats | null>(null);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [isAssetModalOpen, setIsAssetModalOpen] = useState(false);
  const [availableAssets, setAvailableAssets] = useState<Asset[]>([]);
  const [analysisType, setAnalysisType] = useState<'equity' | 'bond'>('equity');


  // Fetch available assets when portfolio changes
  useEffect(() => {
    const fetchAssets = async () => {
      if (!selectedPortfolioId) return;

      try {
        // Get all assets that can have composition
        // Note: Assets don't have portfolio_id, they're linked via transactions
        // For now, show all composable assets
        const allAssets = await assetsApi.getAll();
        const composableAssets = allAssets.filter(a => canHaveComposition(a.asset_type));
        setAvailableAssets(composableAssets);
      } catch (err) {
        console.error('Error fetching assets:', err);
      }
    };

    fetchAssets();
  }, [selectedPortfolioId]);

  // Reset asset selection when portfolio changes
  useEffect(() => {
    setSelectedAssets([]);
    setComposition(null);
    setRiskStats(null);
    setError(null);
  }, [selectedPortfolioId]);

  // Fetch composition when selected assets change
  useEffect(() => {
    const fetchComposition = async () => {
      if (!selectedPortfolioId) {
        setComposition(null);
        setRiskStats(null);
        return;
      }

      if (selectedAssets.length === 0) {
        setComposition(null);
        setRiskStats(null);
        return;
      }

      setLoading(true);
      setError(null);

      try {
        const assetIds = selectedAssets.map(a => a.asset_id);

        // Fetch composition
        const comp = await getMultipleAssetsComposition(assetIds, selectedPortfolioId!);
        setComposition(comp);

        // Fetch risk stats
        const stats = await getMultipleAssetsRiskStats(assetIds, selectedPortfolioId!);
        setRiskStats(stats);

        // Determine analysis type based on selected assets
        const hasEquity = selectedAssets.some(a => isEquityType(a.asset_type));
        const hasBond = selectedAssets.some(a => isBondType(a.asset_type));

        if (hasEquity && !hasBond) {
          setAnalysisType('equity');
        } else if (hasBond && !hasEquity) {
          setAnalysisType('bond');
        } else if (hasEquity) {
          // Default to equity if mixed
          setAnalysisType('equity');
        }
      } catch (err: any) {
        console.error('Error fetching composition:', err);
        setError(err.message || 'Errore nel caricamento dei dati');
      } finally {
        setLoading(false);
      }
    };

    fetchComposition();
  }, [selectedAssets, selectedPortfolioId]);

  const handleAssetToggle = (asset: Asset) => {
    setSelectedAssets(prev => {
      const exists = prev.find(a => a.asset_id === asset.asset_id);
      if (exists) {
        return prev.filter(a => a.asset_id !== asset.asset_id);
      } else {
        return [...prev, asset];
      }
    });
  };

  const handleRefresh = () => {
    setSelectedAssets([...selectedAssets]); // Trigger re-fetch
  };

  if (!selectedPortfolioId) {
    return (
      <div className="space-y-6">
        <div className="flex items-center justify-between">
          <div>
            <h2 className="text-3xl font-bold text-white flex items-center gap-3">
              <TrendingUp className="w-8 h-8 text-blue-400" />
              Analisi Composizione
            </h2>
          </div>
        </div>
        <div className="bg-blue-500/10 border border-blue-500/30 rounded-lg p-6 text-center">
          <p className="text-blue-200 text-lg">Seleziona un portafoglio per visualizzare l'analisi di composizione</p>
        </div>
      </div>
    );
  }

  return (
    <div className="space-y-6">
      {/* Header */}
      <div className="flex items-center justify-between">
        <div>
          <h2 className="text-3xl font-bold text-white flex items-center gap-3">
            <TrendingUp className="w-8 h-8 text-blue-400" />
            Analisi Composizione
          </h2>
          <p className="text-gray-400 mt-1">
            {selectedAssets.length > 0
              ? `${selectedAssets.length} asset selezionato/i`
              : 'Seleziona uno o più asset per iniziare l\'analisi'}
          </p>
        </div>

        <div className="flex gap-3">
          <Button
            onClick={() => setIsAssetModalOpen(true)}
            variant="primary"
          >
            <Filter className="w-4 h-4 mr-2" />
            Cambia Selezione
          </Button>
          {selectedAssets.length > 0 && (
            <Button
              onClick={handleRefresh}
              variant="secondary"
            >
              <RefreshCw className="w-4 h-4 mr-2" />
              Aggiorna
            </Button>
          )}
        </div>
      </div>

      {/* Portfolio Summary */}
      <PortfolioSummary riskStats={riskStats} selectedPortfolioId={selectedPortfolioId} />

      {/* Analysis Type Toggle (if mixed assets) */}
      {selectedAssets.length > 0 &&
        selectedAssets.some(a => isEquityType(a.asset_type)) &&
        selectedAssets.some(a => isBondType(a.asset_type)) && (
          <div className="flex gap-2 bg-white/5 p-2 rounded-xl w-fit">
            <button
              onClick={() => setAnalysisType('equity')}
              className={`px-4 py-2 font-medium transition-colors ${analysisType === 'equity'
                ? 'bg-blue-500 text-white'
                : 'bg-white/10 text-gray-300 hover:bg-white/20'
                } rounded-lg`}
            >
              Analisi Azionaria
            </button>
            <button
              onClick={() => setAnalysisType('bond')}
              className={`px-4 py-2 font-medium transition-colors ${analysisType === 'bond'
                ? 'bg-blue-500 text-white'
                : 'bg-white/10 text-gray-300 hover:bg-white/20'
                } rounded-lg`}
            >
              Analisi Obbligazionaria
            </button>
          </div>
        )}

      {/* Loading State */}
      {loading && (
        <div className="flex items-center justify-center py-12">
          <Loader2 className="w-8 h-8 text-blue-400 animate-spin" />
          <span className="ml-3 text-gray-300">Caricamento analisi...</span>
        </div>
      )}

      {/* Error State */}
      {error && (
        <div className="bg-red-500/20 border border-red-500/50 rounded-lg p-4 text-red-200">
          <p className="font-semibold">Errore</p>
          <p className="text-sm mt-1">{error}</p>
        </div>
      )}

      {/* Analysis Content */}
      {!loading && !error && selectedAssets.length > 0 && (
        <>
          {analysisType === 'equity' && (
            <EquityAnalysis composition={composition} riskStats={riskStats} />
          )}
          {analysisType === 'bond' && (
            <BondAnalysis composition={composition} riskStats={riskStats} />
          )}
        </>
      )}

      {/* Asset Selection Modal */}
      {isAssetModalOpen && (
        <Modal
          onClose={() => setIsAssetModalOpen(false)}
          title="Seleziona Asset"
        >
          <div className="space-y-4">
            <p className="text-gray-300 text-sm">
              Seleziona uno o più asset per visualizzare l'analisi di composizione
            </p>

            <div className="space-y-2 max-h-96 overflow-y-auto">
              {availableAssets.map((asset) => (
                <label
                  key={asset.asset_id}
                  className="flex items-center gap-3 p-3 bg-white/5 hover:bg-white/10 rounded-lg cursor-pointer transition-colors"
                >
                  <input
                    type="checkbox"
                    checked={selectedAssets.some(a => a.asset_id === asset.asset_id)}
                    onChange={() => handleAssetToggle(asset)}
                    className="w-4 h-4"
                  />
                  <div className="flex-1">
                    <div className="text-white font-medium">{asset.name}</div>
                    <div className="text-gray-400 text-sm">{asset.ticker || 'N/A'}</div>
                  </div>
                  <div className="text-xs text-gray-500 bg-white/10 px-2 py-1 rounded">
                    {asset.asset_type}
                  </div>
                </label>
              ))}
            </div>

            <div className="flex justify-end gap-3 pt-4 border-t border-white/10">
              <Button onClick={() => setIsAssetModalOpen(false)} variant="secondary">
                Chiudi
              </Button>
            </div>
          </div>
        </Modal>
      )}
    </div>
  );
};
