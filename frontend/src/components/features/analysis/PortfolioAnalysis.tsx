import React, { useState, useEffect } from 'react';
import {
  PieChart,
  Pie,
  Cell,
  ResponsiveContainer,
  Legend,
  Tooltip,
  BarChart,
  Bar,
  XAxis,
  YAxis,
  CartesianGrid,
  LabelList,
} from 'recharts';
import { ComposableMap, Geographies, Geography } from 'react-simple-maps';
import { TrendingUp, Loader2, RefreshCw, Filter, Maximize2, Minimize2 } from 'lucide-react';
import { Button } from '../../ui/Button';
import { Modal } from '../../ui/Modal';
import {
  getPortfolioComposition,
  getMultiplePortfoliosComposition,
  getMultipleAssetsComposition,
  PortfolioComposition,
  getHoldingDetail,
  getSectorDetail,
  getRegionDetail,
  getMultipleAssetsRiskStats,
  RiskStats,
  RiskStatsDetail,
  HoldingDetail,
  SectorDetail,
  RegionDetail,
} from '../../../lib/api';
import { assetsApi } from '../../../lib/api';
import { isEquityType, isBondType, canHaveComposition } from '../../../lib/utils/assetHelpers';
import type { Asset } from '../../../types';

interface PortfolioAnalysisProps {
  availablePortfolios: Array<{ portfolio_id: string; name: string }>;
  selectedPortfolioId: string | null;
}

const COLORS = [
  '#3b82f6', // blue
  '#10b981', // green
  '#f59e0b', // amber
  '#ef4444', // red
  '#8b5cf6', // purple
  '#ec4899', // pink
  '#06b6d4', // cyan
  '#84cc16', // lime
  '#f97316', // orange
  '#6366f1', // indigo
  '#14b8a6', // teal
  '#a855f7', // violet
  '#eab308', // yellow
  '#64748b', // slate
  '#22c55e', // emerald
];

// World map topology URL
const GEO_URL = 'https://cdn.jsdelivr.net/npm/world-atlas@2/countries-110m.json';

// Helper: Map region names to country names (as they appear in the map's properties.name)
// Backend normalizes all country names to Italian standard names
const REGION_TO_COUNTRIES: Record<string, string[]> = {
  // Individual countries (Italian names → Map country names)
  'Stati Uniti': ['United States of America'],
  'Giappone': ['Japan'],
  'Cina': ['China'],
  'Canada': ['Canada'],
  'Australia': ['Australia'],
  'Regno Unito': ['United Kingdom'],
  'Germania': ['Germany'],
  'Francia': ['France'],
  'Italia': ['Italy'],
  'Spagna': ['Spain'],
  'Svizzera': ['Switzerland'],
  'Paesi Bassi': ['Netherlands'], // Normalized from "Olanda", "Paesi bassi"
  'Belgio': ['Belgium'],
  'Austria': ['Austria'],
  'Svezia': ['Sweden'],
  'Norvegia': ['Norway'],
  'Danimarca': ['Denmark'],
  'Finlandia': ['Finland'],
  'Irlanda': ['Ireland'],
  'Portogallo': ['Portugal'],
  'Polonia': ['Poland'],
  'Grecia': ['Greece'],
  'Brasile': ['Brazil'],
  'Messico': ['Mexico'],
  'India': ['India'],
  'Corea del Sud': ['South Korea'], // Normalized from "Corea", "South Korea", "Korea"
  'Russia': ['Russia'],
  'Sudafrica': ['South Africa'],
  'Turchia': ['Turkey'],
  'Argentina': ['Argentina'],
  'Cile': ['Chile'],
  'Singapore': ['Singapore'],
  'Hong Kong': ['Hong Kong'],
  'Taiwan': ['Taiwan'],
  'Tailandia': ['Thailand'],
  'Malesia': ['Malaysia'],
  'Indonesia': ['Indonesia'],
  'Filippine': ['Philippines'],
  'Vietnam': ['Vietnam'],
  'Nuova Zelanda': ['New Zealand'],
  'Israele': ['Israel'],
  'Emirati Arabi Uniti': ['United Arab Emirates'],
  'Arabia Saudita': ['Saudi Arabia'],

  // Regional groupings (in case they appear in data)
  'Europa': ['Germany', 'France', 'United Kingdom', 'Italy', 'Spain', 'Netherlands', 'Belgium', 'Switzerland', 'Austria', 'Sweden', 'Norway', 'Denmark', 'Finland', 'Ireland', 'Portugal', 'Poland'],
  'Europe': ['Germany', 'France', 'United Kingdom', 'Italy', 'Spain', 'Netherlands', 'Belgium', 'Switzerland', 'Austria', 'Sweden', 'Norway', 'Denmark', 'Finland', 'Ireland', 'Portugal', 'Poland'],
  'Eurozona': ['Germany', 'France', 'Italy', 'Spain', 'Netherlands', 'Belgium', 'Austria', 'Ireland', 'Portugal', 'Finland'],
  'Eurozone': ['Germany', 'France', 'Italy', 'Spain', 'Netherlands', 'Belgium', 'Austria', 'Ireland', 'Portugal', 'Finland'],
  'Asia': ['Japan', 'China', 'South Korea', 'India', 'Singapore', 'Hong Kong', 'Taiwan', 'Thailand', 'Malaysia', 'Indonesia', 'Philippines', 'Vietnam'],
  'Mercati Emergenti': ['China', 'India', 'Brazil', 'Russia', 'South Africa', 'Mexico', 'Turkey', 'Indonesia', 'Thailand', 'Malaysia', 'Poland'],
  'Emerging Markets': ['China', 'India', 'Brazil', 'Russia', 'South Africa', 'Mexico', 'Turkey', 'Indonesia', 'Thailand', 'Malaysia', 'Poland'],
  'America Latina': ['Brazil', 'Mexico', 'Argentina', 'Chile', 'Colombia', 'Peru'],
  'Latin America': ['Brazil', 'Mexico', 'Argentina', 'Chile', 'Colombia', 'Peru'],
};

export const PortfolioAnalysis: React.FC<PortfolioAnalysisProps> = ({ availablePortfolios, selectedPortfolioId }) => {
  const [assets, setAssets] = useState<Asset[]>([]);
  const [selectedAssets, setSelectedAssets] = useState<string[]>([]);
  const [composition, setComposition] = useState<PortfolioComposition | null>(null);
  const [riskStats, setRiskStats] = useState<RiskStats | null>(null);
  const [loading, setLoading] = useState(false);
  const [hasLoaded, setHasLoaded] = useState(false);
  const [assetCategory, setAssetCategory] = useState<'equity' | 'bond'>('equity');
  const [activeTab, setActiveTab] = useState<'holdings' | 'sectors' | 'regions' | 'allocation' | 'bondRatings' | 'bondMaturity' | 'riskStats'>(
    'holdings'
  );
  const [mapTooltip, setMapTooltip] = useState<{ name: string; value: number } | null>(null);
  const [expand, setExpand] = useState(false);
  const [detailModal, setDetailModal] = useState<{
    type: 'holding' | 'sector' | 'region' | 'allocation' | 'bondRating' | 'bondMaturity' | 'riskStats';
    name: string;
    symbol?: string;
    details: any[];
  } | null>(null);
  const [loadingDetails, setLoadingDetails] = useState(false);

  // Carica gli asset all'avvio
  useEffect(() => {
    loadAssets();
  }, []);

  // Reset active tab when switching between equity and bond categories
  useEffect(() => {
    if (assetCategory === 'bond' && activeTab === 'holdings') {
      setActiveTab('sectors');
    } else if (assetCategory === 'equity' && (activeTab === 'bondRatings' || activeTab === 'bondMaturity')) {
      setActiveTab('holdings');
    }
    // Reset riskStats tab when switching categories
    if (activeTab === 'riskStats') {
      // Keep riskStats tab active when switching categories
    }
  }, [assetCategory, activeTab]);

  const loadAssets = async () => {
    try {
      const data = await assetsApi.getAll();
      setAssets(data);
    } catch (error) {
      console.error('Error loading assets:', error);
    }
  };

  const handleLoadData = async () => {
    if (selectedAssets.length === 0) {
      alert('Seleziona almeno un asset');
      return;
    }

    setLoading(true);
    try {
      let data: PortfolioComposition;
      let riskData: RiskStats;

      // Usa il nuovo endpoint per filtrare per asset
      // Se c'è un portafoglio selezionato, pesa in base alle sue posizioni
      [data, riskData] = await Promise.all([
        getMultipleAssetsComposition(selectedAssets, selectedPortfolioId || undefined, expand),
        getMultipleAssetsRiskStats(selectedAssets, selectedPortfolioId || undefined),
      ]);

      setComposition(data);
      setRiskStats(riskData);
      setHasLoaded(true);
    } catch (error) {
      console.error('Error loading composition:', error);
      alert('Errore nel caricamento dei dati di composizione');
    } finally {
      setLoading(false);
    }
  };

  const toggleAsset = (assetId: string) => {
    setSelectedAssets((prev) =>
      prev.includes(assetId) ? prev.filter((id) => id !== assetId) : [...prev, assetId]
    );
  };

  const selectAll = () => {
    setSelectedAssets(filteredAssets.map((a) => a.asset_id));
  };

  const clearAll = () => {
    setSelectedAssets([]);
  };

  const handleBarClick = async (data: any, type: 'holding' | 'sector' | 'region' | 'allocation' | 'bondRating' | 'bondMaturity') => {
    if (!selectedPortfolioId) {
      alert('Seleziona un portafoglio per vedere i dettagli');
      return;
    }

    setLoadingDetails(true);
    try {
      let details: any[] = [];

      if (type === 'holding') {
        const result = await getHoldingDetail(
          selectedPortfolioId,
          data.symbol,
          data.name
        );
        details = result.details;
      } else if (type === 'sector') {
        const result = await getSectorDetail(selectedPortfolioId, data.name);
        details = result.details;
      } else if (type === 'region') {
        const result = await getRegionDetail(selectedPortfolioId, data.name);
        details = result.details;
      }
      // TODO: Aggiungere altri tipi quando gli endpoint sono pronti

      setDetailModal({
        type,
        name: data.name,
        symbol: data.symbol,
        details,
      });
    } catch (error) {
      console.error('Error loading details:', error);
      alert('Errore nel caricamento dei dettagli');
    } finally {
      setLoadingDetails(false);
    }
  };

  // Custom label component per LabelList
  const CustomLabel = (props: any) => {
    const { x, y, width, value } = props;
    if (width < 30) return null; // Non mostrare label se la barra è troppo piccola
    return (
      <text
        x={x + width + 5}
        y={y + 15}
        fill="white"
        fontSize={12}
        fontWeight="bold"
      >
        {value.toFixed(2)}%
      </text>
    );
  };

  // Helper function to check if a name is a variation of "Altri"
  const isAltriVariation = (name: string): boolean => {
    const normalized = name.trim().toLowerCase();
    return normalized === 'altri' || normalized === 'altro' || normalized === 'other' || normalized === 'others';
  };

  // Helper function to filter out "Altri" variations and sum their percentages
  const filterAndSumAltri = (items: Array<{ name: string; value: number }>) => {
    let altriSum = 0;
    const filtered = items.filter(item => {
      if (isAltriVariation(item.name)) {
        altriSum += item.value;
        return false; // Remove from list
      }
      return true; // Keep in list
    });
    return { filtered, altriSum };
  };

  // Prepara dati per i grafici
  const holdingsChartData =
    composition?.holdings
      .filter(h => !isAltriVariation(h.holding_name))
      .map((h) => ({
        name: h.holding_name,
        value: h.weighted_percent, // Backend now returns percentages (0-100)
        symbol: h.holding_symbol,
      })) || [];

  const sectorsChartData =
    composition?.sectors
      .filter(s => !isAltriVariation(s.sector_name))
      .map((s) => ({
        name: s.sector_name,
        value: s.weighted_percent, // Già in percentuale dal backend
      })) || [];

  const regionsChartData =
    composition?.regions
      .filter(r => !isAltriVariation(r.region_name))
      .map((r) => ({
        name: r.region_name,
        value: r.weighted_percent, // Già in percentuale dal backend
      }))
      .filter((r) => r.value > 0) // Filtra regioni con valore > 0
      .sort((a, b) => b.value - a.value) || []; // Ordina per valore decrescente

  const allocationChartData =
    composition?.allocation
      .filter(a => !isAltriVariation(a.allocation_type))
      .map((a) => ({
        name: a.allocation_type,
        value: a.weighted_percent, // Già in percentuale dal backend
      })) || [];

  const bondRatingsChartData =
    composition?.bondRatings
      .filter(br => !isAltriVariation(br.rating_category))
      .map((br) => ({
        name: br.rating_category,
        value: br.weighted_percent, // Già in percentuale dal backend
      })) || [];

  const bondMaturityChartData =
    composition?.bondMaturity.map((bm) => ({
      name: bm.maturity_range,
      value: bm.weighted_percent, // Già in percentuale dal backend
      duration: bm.avg_duration_years,
    })) || [];

  // Filter assets based on selected category
  const filteredAssets = assets.filter((asset) => {
    if (!canHaveComposition(asset.asset_type)) return false;
    if (assetCategory === 'equity') return isEquityType(asset.asset_type);
    if (assetCategory === 'bond') return isBondType(asset.asset_type);
    return false;
  });

  // Vista iniziale: selezione asset
  if (!hasLoaded) {
    return (
      <div className="bg-white/10 backdrop-blur-lg rounded-2xl border border-white/20 p-8">
        <div className="flex items-center justify-between mb-6">
          <div className="flex items-center gap-3">
            <TrendingUp className="w-8 h-8 text-blue-400" />
            <h2 className="text-2xl font-bold text-white">Analisi Composizione Asset</h2>
          </div>
        </div>

        <div className="mb-6">
          <p className="text-blue-200 mb-4">
            Seleziona uno o più asset per visualizzare l'analisi aggregata della composizione.
            {selectedPortfolioId && (
              <span className="block mt-2 text-blue-300 text-sm">
                I pesi saranno calcolati in base alle posizioni del portafoglio selezionato.
              </span>
            )}
          </p>

          {/* Category Toggle */}
          <div className="flex gap-2 mb-4 p-1 bg-white/5 rounded-lg border border-white/20 w-fit">
            <button
              onClick={() => {
                setAssetCategory('equity');
                setSelectedAssets([]);
                // Reset to holdings tab for equity
                setActiveTab('holdings');
              }}
              className={`px-6 py-2 rounded-md font-medium transition-colors ${assetCategory === 'equity'
                ? 'bg-blue-500 text-white'
                : 'text-blue-200 hover:text-white'
                }`}
            >
              Azionario
            </button>
            <button
              onClick={() => {
                setAssetCategory('bond');
                setSelectedAssets([]);
                // Reset to sectors tab for bonds (no holdings for bonds)
                setActiveTab('sectors');
              }}
              className={`px-6 py-2 rounded-md font-medium transition-colors ${assetCategory === 'bond'
                ? 'bg-blue-500 text-white'
                : 'text-blue-200 hover:text-white'
                }`}
            >
              Obbligazionario
            </button>
          </div>

          <div className="flex gap-2 mb-4">
            <Button onClick={selectAll} variant="secondary">
              Seleziona Tutti
            </Button>
            <Button onClick={clearAll} variant="secondary">
              Deseleziona Tutti
            </Button>
          </div>

          <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-3">
            {filteredAssets.map((asset) => {
              const hasCompositionData = !!asset.composition_last_updated;
              const isSelected = selectedAssets.includes(asset.asset_id);

              return (
                <label
                  key={asset.asset_id}
                  className={`flex items-center gap-3 p-4 rounded-lg border-2 cursor-pointer transition-all ${isSelected
                    ? hasCompositionData
                      ? 'border-green-500 bg-green-500/20'
                      : 'border-blue-500 bg-blue-500/20'
                    : hasCompositionData
                      ? 'border-green-500/40 bg-green-500/5 hover:border-green-500/60'
                      : 'border-white/20 bg-white/5 hover:border-white/40'
                    }`}
                >
                  <input
                    type="checkbox"
                    checked={isSelected}
                    onChange={() => toggleAsset(asset.asset_id)}
                    className="w-5 h-5"
                  />
                  <div className="flex-1">
                    <div className="flex items-center gap-2">
                      <span className="text-white font-medium">{asset.name}</span>
                      {hasCompositionData && (
                        <span className="px-2 py-0.5 bg-green-500/30 text-green-300 text-xs rounded-full">
                          ✓ Dati
                        </span>
                      )}
                    </div>
                    <span className="text-blue-300 text-xs">{asset.isin}</span>
                  </div>
                </label>
              );
            })}
          </div>
        </div>

        <Button
          onClick={handleLoadData}
          disabled={selectedAssets.length === 0 || loading}
          className="w-full py-4 text-lg"
        >
          {loading ? (
            <>
              <Loader2 className="w-5 h-5 mr-2 animate-spin" />
              Caricamento in corso...
            </>
          ) : (
            <>
              <TrendingUp className="w-5 h-5 mr-2" />
              Carica Analisi Composizione
            </>
          )}
        </Button>
      </div>
    );
  }

  // Vista principale con dati caricati
  return (
    <div className="space-y-6">
      {/* Header con filtri */}
      <div className="bg-white/10 backdrop-blur-lg rounded-2xl border border-white/20 p-6">
        <div className="flex items-center justify-between mb-4">
          <div className="flex items-center gap-3">
            <TrendingUp className="w-8 h-8 text-blue-400" />
            <div>
              <h2 className="text-2xl font-bold text-white">Analisi Composizione</h2>
              <p className="text-sm text-blue-200">
                {selectedAssets.length === 1
                  ? assets.find((a) => a.asset_id === selectedAssets[0])?.name
                  : `${selectedAssets.length} asset selezionati`}
              </p>
            </div>
          </div>

          <div className="flex gap-2">
            <Button
              onClick={() => setHasLoaded(false)}
              variant="secondary"
              className="flex items-center gap-2"
            >
              <Filter className="w-4 h-4" />
              Cambia Selezione
            </Button>
            <Button
              onClick={() => {
                setExpand(!expand);
                if (hasLoaded) {
                  handleLoadData();
                }
              }}
              variant="secondary"
              className="flex items-center gap-2"
            >
              {expand ? (
                <>
                  <Minimize2 className="w-4 h-4" />
                  Mostra Prime 15
                </>
              ) : (
                <>
                  <Maximize2 className="w-4 h-4" />
                  Espandi Tutto
                </>
              )}
            </Button>
            <Button
              onClick={handleLoadData}
              variant="secondary"
              disabled={loading}
              className="flex items-center gap-2"
            >
              {loading ? (
                <Loader2 className="w-4 h-4 animate-spin" />
              ) : (
                <RefreshCw className="w-4 h-4" />
              )}
              Aggiorna
            </Button>
          </div>
        </div>

        {/* Tabs */}
        <div className="flex gap-2 border-b border-white/20">
          {assetCategory === 'equity' && (
            <button
              onClick={() => setActiveTab('holdings')}
              className={`px-4 py-2 font-medium transition-colors ${activeTab === 'holdings'
                ? 'text-blue-400 border-b-2 border-blue-400'
                : 'text-gray-400 hover:text-white'
                }`}
            >
              Top Holdings ({composition?.holdings.length || 0})
            </button>
          )}
          <button
            onClick={() => setActiveTab('sectors')}
            className={`px-4 py-2 font-medium transition-colors ${activeTab === 'sectors'
              ? 'text-blue-400 border-b-2 border-blue-400'
              : 'text-gray-400 hover:text-white'
              }`}
          >
            Settori ({composition?.sectors.length || 0})
          </button>
          <button
            onClick={() => setActiveTab('regions')}
            className={`px-4 py-2 font-medium transition-colors ${activeTab === 'regions'
              ? 'text-blue-400 border-b-2 border-blue-400'
              : 'text-gray-400 hover:text-white'
              }`}
          >
            Geografia ({composition?.regions.length || 0})
          </button>
          <button
            onClick={() => setActiveTab('allocation')}
            className={`px-4 py-2 font-medium transition-colors ${activeTab === 'allocation'
              ? 'text-blue-400 border-b-2 border-blue-400'
              : 'text-gray-400 hover:text-white'
              }`}
          >
            Asset Allocation ({composition?.allocation.length || 0})
          </button>
          {assetCategory === 'bond' && (
            <>
              <button
                onClick={() => setActiveTab('bondRatings')}
                className={`px-4 py-2 font-medium transition-colors ${activeTab === 'bondRatings'
                  ? 'text-blue-400 border-b-2 border-blue-400'
                  : 'text-gray-400 hover:text-white'
                  }`}
              >
                Rating ({composition?.bondRatings.length || 0})
              </button>
              <button
                onClick={() => setActiveTab('bondMaturity')}
                className={`px-4 py-2 font-medium transition-colors ${activeTab === 'bondMaturity'
                  ? 'text-blue-400 border-b-2 border-blue-400'
                  : 'text-gray-400 hover:text-white'
                  }`}
              >
                Maturity ({composition?.bondMaturity.length || 0})
              </button>
            </>
          )}
          <button
            onClick={() => setActiveTab('riskStats')}
            className={`px-4 py-2 font-medium transition-colors ${activeTab === 'riskStats'
              ? 'text-blue-400 border-b-2 border-blue-400'
              : 'text-gray-400 hover:text-white'
              }`}
          >
            Statistiche Rischio
          </button>
        </div>
      </div>

      {/* Portfolio Summary - Show total value and asset weights */}
      {selectedPortfolioId && riskStats && riskStats.details && riskStats.details.length > 0 && (
        <div className="bg-gradient-to-br from-blue-500/20 to-purple-500/20 backdrop-blur-lg rounded-2xl border border-blue-400/30 p-6 mb-6">
          <h3 className="text-xl font-bold text-white mb-4">📊 Riepilogo Selezione</h3>
          <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
            <div className="bg-white/5 rounded-lg p-4">
              <div className="text-sm text-gray-300 mb-1">Valore Totale Asset Selezionati</div>
              <div className="text-2xl font-bold text-blue-300">
                {new Intl.NumberFormat('it-IT', { style: 'currency', currency: 'EUR' }).format(riskStats.total_value)}
              </div>
            </div>
            <div className="bg-white/5 rounded-lg p-4">
              <div className="text-sm text-gray-300 mb-2">Peso nel Portafoglio</div>
              <div className="space-y-2">
                {riskStats.details.map((detail, idx) => (
                  <div key={idx} className="flex justify-between items-center">
                    <span className="text-white text-sm">{detail.asset_name}</span>
                    <span className="text-blue-300 font-bold">{detail.weight_percent.toFixed(2)}%</span>
                  </div>
                ))}
              </div>
            </div>
          </div>
        </div>
      )}

      {/* Content Area */}
      <div className="grid grid-cols-1 lg:grid-cols-2 gap-6">
        {/* Chart */}
        <div className="bg-white/10 backdrop-blur-lg rounded-2xl border border-white/20 p-6">
          <h3 className="text-xl font-bold text-white mb-4">
            {activeTab === 'holdings' && 'Top Holdings'}
            {activeTab === 'sectors' && 'Distribuzione Settoriale'}
            {activeTab === 'regions' && 'Distribuzione Geografica'}
            {activeTab === 'allocation' && 'Asset Allocation'}
            {activeTab === 'bondRatings' && 'Rating Obbligazionari'}
            {activeTab === 'bondMaturity' && 'Scadenze Obbligazionarie'}
            {activeTab === 'riskStats' && 'Statistiche di Rischio'}
          </h3>

          {/* Holdings: Horizontal Bar Chart */}
          {activeTab === 'holdings' && (
            <ResponsiveContainer width="100%" height={400}>
              <BarChart data={holdingsChartData} layout="vertical" margin={{ left: 100 }}>
                <CartesianGrid strokeDasharray="3 3" stroke="rgba(255,255,255,0.1)" />
                <XAxis type="number" stroke="rgba(255,255,255,0.5)" />
                <YAxis
                  type="category"
                  dataKey="name"
                  stroke="rgba(255,255,255,0.5)"
                  width={90}
                  style={{ fontSize: '11px' }}
                />
                <Tooltip
                  contentStyle={{
                    backgroundColor: 'rgba(0, 0, 0, 0.9)',
                    border: '1px solid rgba(255, 255, 255, 0.2)',
                    borderRadius: '8px',
                    color: 'white',
                  }}
                  labelStyle={{
                    color: 'white',
                    fontWeight: '600',
                  }}
                  itemStyle={{
                    color: '#60a5fa',
                    fontWeight: 'bold',
                  }}
                  formatter={(value: number) => `${value.toFixed(2)}%`}
                />
                <Bar
                  dataKey="value"
                  radius={[0, 4, 4, 0]}
                  onClick={(data: any) => handleBarClick(data, 'holding')}
                  style={{ cursor: 'pointer' }}
                >
                  {holdingsChartData.map((entry, index) => (
                    <Cell key={`cell-${index}`} fill={COLORS[index % COLORS.length]} />
                  ))}
                  <LabelList content={<CustomLabel />} />
                </Bar>
              </BarChart>
            </ResponsiveContainer>
          )}

          {/* Sectors: Horizontal Bar Chart */}
          {activeTab === 'sectors' && (
            <ResponsiveContainer width="100%" height={400}>
              <BarChart data={sectorsChartData} layout="vertical" margin={{ left: 100 }}>
                <CartesianGrid strokeDasharray="3 3" stroke="rgba(255,255,255,0.1)" />
                <XAxis type="number" stroke="rgba(255,255,255,0.5)" />
                <YAxis
                  type="category"
                  dataKey="name"
                  stroke="rgba(255,255,255,0.5)"
                  width={90}
                  style={{ fontSize: '11px' }}
                />
                <Tooltip
                  contentStyle={{
                    backgroundColor: 'rgba(0, 0, 0, 0.9)',
                    border: '1px solid rgba(255, 255, 255, 0.2)',
                    borderRadius: '8px',
                    color: 'white',
                  }}
                  labelStyle={{
                    color: 'white',
                    fontWeight: '600',
                  }}
                  itemStyle={{
                    color: '#60a5fa',
                    fontWeight: 'bold',
                  }}
                  formatter={(value: number) => `${value.toFixed(2)}%`}
                />
                <Bar
                  dataKey="value"
                  radius={[0, 4, 4, 0]}
                  onClick={(data: any) => handleBarClick(data, 'sector')}
                  style={{ cursor: 'pointer' }}
                >
                  {sectorsChartData.map((entry, index) => (
                    <Cell key={`cell-${index}`} fill={COLORS[index % COLORS.length]} />
                  ))}
                  <LabelList content={<CustomLabel />} />
                </Bar>
              </BarChart>
            </ResponsiveContainer>
          )}

          {/* Regions: World Map */}
          {activeTab === 'regions' && (
            <>
              {/* Map Container */}
              <div className="h-[400px] relative">
                <ComposableMap
                  projection="geoMercator"
                  projectionConfig={{
                    scale: 120,
                  }}
                >
                  <Geographies geography={GEO_URL}>
                    {({ geographies }) => {
                      return geographies.map((geo) => {
                        // Find matching region data with its index for color assignment
                        let regionData = null;
                        let regionIndex = -1;

                        for (let i = 0; i < regionsChartData.length; i++) {
                          const region = regionsChartData[i];
                          const countries = REGION_TO_COUNTRIES[region.name] || [];

                          const matches = countries.some(
                            (countryName) =>
                              geo.properties?.name === countryName
                          );
                          if (matches) {
                            regionData = region;
                            regionIndex = i;
                            break;
                          }
                        }

                        const fillColor = regionData
                          ? COLORS[regionIndex % COLORS.length]
                          : 'rgba(100, 116, 139, 0.2)';

                        return (
                          <Geography
                            key={geo.rsmKey}
                            geography={geo}
                            fill={fillColor}
                            stroke="rgba(255, 255, 255, 0.3)"
                            strokeWidth={0.5}
                            onMouseEnter={() => {
                              if (regionData) {
                                setMapTooltip({ name: regionData.name, value: regionData.value });
                              }
                            }}
                            onMouseLeave={() => {
                              setMapTooltip(null);
                            }}
                            style={{
                              default: { outline: 'none' },
                              hover: {
                                fill: regionData ? COLORS[regionIndex % COLORS.length] : 'rgba(100, 116, 139, 0.4)',
                                outline: 'none',
                                cursor: 'pointer',
                                opacity: 0.8,
                              },
                              pressed: { outline: 'none' },
                            }}
                          />
                        );
                      });
                    }}
                  </Geographies>
                </ComposableMap>

                {/* Tooltip */}
                {mapTooltip && (
                  <div className="absolute top-4 right-4 bg-black/80 text-white px-4 py-2 rounded-lg border border-white/20 shadow-lg">
                    <div className="text-sm font-semibold">{mapTooltip.name}</div>
                    <div className="text-lg font-bold text-blue-400">{mapTooltip.value.toFixed(2)}%</div>
                  </div>
                )}
              </div>
            </>
          )}

          {/* Allocation, Bond Ratings, Bond Maturity: Pie Chart */}
          {(activeTab === 'allocation' || activeTab === 'bondRatings' || activeTab === 'bondMaturity') && (
            <ResponsiveContainer width="100%" height={400}>
              <PieChart>
                <Pie
                  data={
                    activeTab === 'allocation'
                      ? allocationChartData
                      : activeTab === 'bondRatings'
                        ? bondRatingsChartData
                        : bondMaturityChartData
                  }
                  cx="50%"
                  cy="50%"
                  labelLine={false}
                  label={(props: any) => `${props.name}: ${Number(props.value).toFixed(2)}%`}
                  outerRadius={120}
                  fill="#8884d8"
                  dataKey="value"
                  onClick={(data: any) => {
                    if (activeTab === 'allocation') {
                      handleBarClick(data, 'allocation');
                    }
                  }}
                  style={{ cursor: activeTab === 'allocation' ? 'pointer' : 'default' }}
                >
                  {(activeTab === 'allocation'
                    ? allocationChartData
                    : activeTab === 'bondRatings'
                      ? bondRatingsChartData
                      : bondMaturityChartData
                  ).map((entry, index) => (
                    <Cell key={`cell-${index}`} fill={COLORS[index % COLORS.length]} />
                  ))}
                </Pie>
                <Tooltip
                  contentStyle={{
                    backgroundColor: 'rgba(0, 0, 0, 0.9)',
                    border: '1px solid rgba(255, 255, 255, 0.2)',
                    borderRadius: '8px',
                    color: 'white',
                  }}
                  labelStyle={{
                    color: 'white',
                    fontWeight: '600',
                  }}
                  itemStyle={{
                    color: '#60a5fa',
                    fontWeight: 'bold',
                  }}
                />
                <Legend />
              </PieChart>
            </ResponsiveContainer>
          )}

          {/* Risk Stats: Summary Cards */}
          {activeTab === 'riskStats' && riskStats && (
            <div className="space-y-4">
              <div className="grid grid-cols-3 gap-4">
                <div
                  className="bg-white/5 rounded-lg p-4 border border-white/20 cursor-pointer hover:bg-white/10 transition-colors"
                  onClick={() => {
                    if (riskStats.details && riskStats.details.length > 0) {
                      setDetailModal({
                        type: 'riskStats',
                        name: 'ISR - Indice Sintetico di Rischio',
                        details: riskStats.details,
                      });
                    }
                  }}
                >
                  <div className="text-sm text-gray-400 mb-1">ISR Medio</div>
                  <div className="text-2xl font-bold text-blue-400">
                    {riskStats.isr !== null ? riskStats.isr.toFixed(2) : 'N/A'}
                  </div>
                </div>
                <div
                  className="bg-white/5 rounded-lg p-4 border border-white/20 cursor-pointer hover:bg-white/10 transition-colors"
                  onClick={() => {
                    if (riskStats.details && riskStats.details.length > 0) {
                      setDetailModal({
                        type: 'riskStats',
                        name: 'Deviazione Standard',
                        details: riskStats.details,
                      });
                    }
                  }}
                >
                  <div className="text-sm text-gray-400 mb-1">Deviazione Standard</div>
                  <div className="text-2xl font-bold text-green-400">
                    {riskStats.standard_deviation !== null ? `${riskStats.standard_deviation.toFixed(2)}%` : 'N/A'}
                  </div>
                </div>
                <div
                  className="bg-white/5 rounded-lg p-4 border border-white/20 cursor-pointer hover:bg-white/10 transition-colors"
                  onClick={() => {
                    if (riskStats.details && riskStats.details.length > 0) {
                      setDetailModal({
                        type: 'riskStats',
                        name: 'Sharpe Ratio',
                        details: riskStats.details,
                      });
                    }
                  }}
                >
                  <div className="text-sm text-gray-400 mb-1">Sharpe Ratio</div>
                  <div className="text-2xl font-bold text-purple-400">
                    {riskStats.sharpe_ratio !== null ? riskStats.sharpe_ratio.toFixed(2) : 'N/A'}
                  </div>
                </div>
              </div>
              <div className="text-sm text-gray-400 text-center">
                Clicca su un indicatore per vedere il dettaglio per asset
              </div>
            </div>
          )}
        </div>

        {/* Detail Section */}
        <div className="bg-white/10 backdrop-blur-lg rounded-2xl border border-white/20 p-6">
          <h3 className="text-xl font-bold text-white mb-4">Dettaglio</h3>

          {/* Bar chart for regions */}
          {activeTab === 'regions' && (
            <>
              <ResponsiveContainer width="100%" height={400}>
                <BarChart data={regionsChartData} layout="vertical" margin={{ left: 140, right: 20, top: 5, bottom: 5 }}>
                  <CartesianGrid strokeDasharray="3 3" stroke="rgba(255,255,255,0.1)" />
                  <XAxis type="number" stroke="rgba(255,255,255,0.5)" />
                  <YAxis
                    type="category"
                    dataKey="name"
                    stroke="rgba(255,255,255,0.5)"
                    width={140}
                    tick={{ fill: 'rgba(255,255,255,0.9)', fontSize: 12 }}
                    tickLine={{ stroke: 'rgba(255,255,255,0.5)' }}
                    interval={0}
                  />
                  <Tooltip
                    contentStyle={{
                      backgroundColor: 'rgba(0, 0, 0, 0.9)',
                      border: '1px solid rgba(255, 255, 255, 0.2)',
                      borderRadius: '8px',
                      color: 'white',
                    }}
                    labelStyle={{
                      color: 'white',
                      fontWeight: '600',
                    }}
                    itemStyle={{
                      color: '#60a5fa',
                      fontWeight: 'bold',
                    }}
                    formatter={(value: number) => `${value.toFixed(2)}%`}
                  />
                  <Bar
                    dataKey="value"
                    radius={[0, 4, 4, 0]}
                    onClick={(data: any) => handleBarClick(data, 'region')}
                    style={{ cursor: 'pointer' }}
                  >
                    {regionsChartData.map((entry, index) => (
                      <Cell key={`cell-${index}`} fill={COLORS[index % COLORS.length]} />
                    ))}
                    <LabelList content={<CustomLabel />} />
                  </Bar>
                </BarChart>
              </ResponsiveContainer>

              {/* Legend Box */}
              <div className="mt-6 bg-white/5 rounded-lg p-4 border border-white/10">
                <h4 className="text-sm font-semibold text-white mb-3">Legenda Regioni</h4>
                <div className="flex flex-wrap gap-3">
                  {regionsChartData.map((region, index) => (
                    <div key={index} className="flex items-center gap-2 bg-white/5 px-3 py-2 rounded border border-white/10">
                      <div
                        className="w-4 h-4 rounded"
                        style={{
                          backgroundColor: COLORS[index % COLORS.length],
                        }}
                      />
                      <span className="text-sm text-white font-medium">
                        {region.name}
                      </span>
                      <span className="text-sm text-blue-300 font-bold">
                        {region.value.toFixed(2)}%
                      </span>
                    </div>
                  ))}
                  {/* Altri for regions */}
                  {composition?.regions && composition.regions.length > 0 && (() => {
                    const { altriSum } = filterAndSumAltri(composition.regions.map(r => ({ name: r.region_name, value: r.weighted_percent })));
                    const filteredRegions = composition.regions.filter(r => !isAltriVariation(r.region_name) && r.weighted_percent > 0);
                    const totalShown = filteredRegions.reduce((sum, r) => sum + r.weighted_percent, 0);
                    const othersPercent = 100 - totalShown - altriSum;
                    if (othersPercent > 0.01 || altriSum > 0) {
                      return (
                        <div className="flex items-center gap-2 bg-gray-500/10 px-3 py-2 rounded border border-white/10">
                          <div className="w-4 h-4 rounded bg-gray-400" />
                          <span className="text-sm text-gray-300 font-medium italic">
                            Altri
                          </span>
                          <span className="text-sm text-gray-400 font-bold">
                            {(othersPercent + altriSum).toFixed(2)}%
                          </span>
                        </div>
                      );
                    }
                    return null;
                  })()}
                </div>
              </div>
            </>
          )}

          {/* Table for other tabs */}
          {activeTab !== 'regions' && (
            <div className="overflow-x-auto">
              <table className="w-full">
                <thead>
                  <tr className="border-b border-white/20">
                    <th className="text-left py-3 px-2 text-sm font-medium text-gray-300">
                      {activeTab === 'holdings' && 'Azienda'}
                      {activeTab === 'sectors' && 'Settore'}
                      {activeTab === 'allocation' && 'Asset Class'}
                      {activeTab === 'bondRatings' && 'Categoria Rating'}
                      {activeTab === 'bondMaturity' && 'Range Scadenza'}
                      {activeTab === 'riskStats' && 'Asset'}
                    </th>
                    {(activeTab === 'holdings' || activeTab === 'riskStats') && (
                      <th className="text-left py-3 px-2 text-sm font-medium text-gray-300">
                        Ticker
                      </th>
                    )}
                    {activeTab === 'bondMaturity' && (
                      <th className="text-right py-3 px-2 text-sm font-medium text-gray-300">
                        Duration
                      </th>
                    )}
                    {activeTab === 'riskStats' && (
                      <>
                        <th className="text-right py-3 px-2 text-sm font-medium text-gray-300">ISR</th>
                        <th className="text-right py-3 px-2 text-sm font-medium text-gray-300">Dev. Std.</th>
                        <th className="text-right py-3 px-2 text-sm font-medium text-gray-300">Sharpe</th>
                      </>
                    )}
                    <th className="text-right py-3 px-2 text-sm font-medium text-gray-300">Peso %</th>
                  </tr>
                </thead>
                <tbody>
                  {activeTab === 'holdings' && (
                    <>
                      {composition?.holdings.filter(h => !isAltriVariation(h.holding_name)).map((holding, index) => (
                        <tr key={index} className="border-b border-white/10">
                          <td className="py-3 px-2 text-sm text-white">{holding.holding_name}</td>
                          <td className="py-3 px-2 text-sm text-gray-400">
                            {holding.holding_symbol || 'N/A'}
                          </td>
                          <td className="py-3 px-2 text-sm text-right font-medium text-blue-400">
                            {holding.weighted_percent.toFixed(2)}%
                          </td>
                        </tr>
                      ))}
                      {/* Altri row for holdings */}
                      {composition?.holdings && composition.holdings.length > 0 && (() => {
                        // Filter out backend "Altri" variations and sum them
                        const { altriSum } = filterAndSumAltri(composition.holdings.map(h => ({ name: h.holding_name, value: h.weighted_percent })));
                        const filteredHoldings = composition.holdings.filter(h => !isAltriVariation(h.holding_name));
                        const totalShown = filteredHoldings.reduce((sum, h) => sum + h.weighted_percent, 0);
                        const othersPercent = 100 - totalShown - altriSum;
                        if (othersPercent > 0.01 || altriSum > 0) {
                          return (
                            <tr className="border-b border-white/10 bg-gray-500/10">
                              <td className="py-3 px-2 text-sm text-gray-300 italic">Altri</td>
                              <td className="py-3 px-2 text-sm text-gray-400">-</td>
                              <td className="py-3 px-2 text-sm text-right font-medium text-gray-400">
                                {(othersPercent + altriSum).toFixed(2)}%
                              </td>
                            </tr>
                          );
                        }
                        return null;
                      })()}
                    </>
                  )}

                  {activeTab === 'sectors' && (
                    <>
                      {composition?.sectors.filter(s => !isAltriVariation(s.sector_name)).map((sector, index) => (
                        <tr key={index} className="border-b border-white/10">
                          <td className="py-3 px-2 text-sm text-white">{sector.sector_name}</td>
                          <td className="py-3 px-2 text-sm text-right font-medium text-blue-400">
                            {sector.weighted_percent.toFixed(2)}%
                          </td>
                        </tr>
                      ))}
                      {/* Altri row for sectors */}
                      {composition?.sectors && composition.sectors.length > 0 && (() => {
                        const { altriSum } = filterAndSumAltri(composition.sectors.map(s => ({ name: s.sector_name, value: s.weighted_percent })));
                        const filteredSectors = composition.sectors.filter(s => !isAltriVariation(s.sector_name));
                        const totalShown = filteredSectors.reduce((sum, s) => sum + s.weighted_percent, 0);
                        const othersPercent = 100 - totalShown - altriSum;
                        if (othersPercent > 0.01 || altriSum > 0) {
                          return (
                            <tr className="border-b border-white/10 bg-gray-500/10">
                              <td className="py-3 px-2 text-sm text-gray-300 italic">Altri</td>
                              <td className="py-3 px-2 text-sm text-right font-medium text-gray-400">
                                {(othersPercent + altriSum).toFixed(2)}%
                              </td>
                            </tr>
                          );
                        }
                        return null;
                      })()}
                    </>
                  )}

                  {activeTab === 'allocation' && (
                    <>
                      {composition?.allocation.filter(a => !isAltriVariation(a.allocation_type)).map((alloc, index) => (
                        <tr key={index} className="border-b border-white/10">
                          <td className="py-3 px-2 text-sm text-white">{alloc.allocation_type}</td>
                          <td className="py-3 px-2 text-sm text-right font-medium text-blue-400">
                            {alloc.weighted_percent.toFixed(2)}%
                          </td>
                        </tr>
                      ))}
                      {/* Altri row for allocation */}
                      {composition?.allocation && composition.allocation.length > 0 && (() => {
                        const { altriSum } = filterAndSumAltri(composition.allocation.map(a => ({ name: a.allocation_type, value: a.weighted_percent })));
                        const filteredAllocation = composition.allocation.filter(a => !isAltriVariation(a.allocation_type));
                        const totalShown = filteredAllocation.reduce((sum, a) => sum + a.weighted_percent, 0);
                        const othersPercent = 100 - totalShown - altriSum;
                        if (othersPercent > 0.01 || altriSum > 0) {
                          return (
                            <tr className="border-b border-white/10 bg-gray-500/10">
                              <td className="py-3 px-2 text-sm text-gray-300 italic">Altri</td>
                              <td className="py-3 px-2 text-sm text-right font-medium text-gray-400">
                                {(othersPercent + altriSum).toFixed(2)}%
                              </td>
                            </tr>
                          );
                        }
                        return null;
                      })()}
                    </>
                  )}

                  {activeTab === 'bondRatings' && (
                    <>
                      {composition?.bondRatings.filter(br => !isAltriVariation(br.rating_category)).map((rating, index) => (
                        <tr key={index} className="border-b border-white/10">
                          <td className="py-3 px-2 text-sm text-white">{rating.rating_category}</td>
                          <td className="py-3 px-2 text-sm text-right font-medium text-blue-400">
                            {rating.weighted_percent.toFixed(2)}%
                          </td>
                        </tr>
                      ))}
                      {/* Altri row for bond ratings */}
                      {composition?.bondRatings && composition.bondRatings.length > 0 && (() => {
                        const { altriSum } = filterAndSumAltri(composition.bondRatings.map(br => ({ name: br.rating_category, value: br.weighted_percent })));
                        const filteredBondRatings = composition.bondRatings.filter(br => !isAltriVariation(br.rating_category));
                        const totalShown = filteredBondRatings.reduce((sum, br) => sum + br.weighted_percent, 0);
                        const othersPercent = 100 - totalShown - altriSum;
                        if (othersPercent > 0.01 || altriSum > 0) {
                          return (
                            <tr className="border-b border-white/10 bg-gray-500/10">
                              <td className="py-3 px-2 text-sm text-gray-300 italic">Altri</td>
                              <td className="py-3 px-2 text-sm text-right font-medium text-gray-400">
                                {(othersPercent + altriSum).toFixed(2)}%
                              </td>
                            </tr>
                          );
                        }
                        return null;
                      })()}
                    </>
                  )}

                  {activeTab === 'bondMaturity' && (
                    <>
                      {composition?.bondMaturity.map((maturity, index) => (
                        <tr key={index} className="border-b border-white/10">
                          <td className="py-3 px-2 text-sm text-white">{maturity.maturity_range}</td>
                          <td className="py-3 px-2 text-sm text-right text-gray-400">
                            {maturity.avg_duration_years ? `${maturity.avg_duration_years.toFixed(2)} anni` : 'N/A'}
                          </td>
                          <td className="py-3 px-2 text-sm text-right font-medium text-blue-400">
                            {maturity.weighted_percent.toFixed(2)}%
                          </td>
                        </tr>
                      ))}
                      {composition?.bondMaturity && composition.bondMaturity.length > 0 && (
                        <tr className="border-t-2 border-blue-500 bg-blue-500/10">
                          <td className="py-3 px-2 text-sm font-bold text-white">Totale</td>
                          <td className="py-3 px-2 text-sm text-right text-gray-400">-</td>
                          <td className="py-3 px-2 text-sm text-right font-bold text-blue-300">
                            {(
                              composition.bondMaturity.reduce(
                                (sum, bm) => sum + bm.weighted_percent,
                                0
                              )
                            ).toFixed(2)}%
                          </td>
                        </tr>
                      )}
                    </>
                  )}

                  {activeTab === 'riskStats' && (
                    <>
                      {riskStats?.details.map((detail, index) => (
                        <tr key={index} className="border-b border-white/10">
                          <td className="py-3 px-2 text-sm text-white">{detail.asset_name}</td>
                          <td className="py-3 px-2 text-sm text-gray-400">{detail.ticker || 'N/A'}</td>
                          <td className="py-3 px-2 text-sm text-right text-white">
                            {detail.isr !== null ? detail.isr.toFixed(2) : 'N/A'}
                          </td>
                          <td className="py-3 px-2 text-sm text-right text-white">
                            {detail.standard_deviation !== null ? `${detail.standard_deviation.toFixed(2)}%` : 'N/A'}
                          </td>
                          <td className="py-3 px-2 text-sm text-right text-white">
                            {detail.sharpe_ratio !== null ? detail.sharpe_ratio.toFixed(2) : 'N/A'}
                          </td>
                          <td className="py-3 px-2 text-sm text-right font-medium text-blue-400">
                            {detail.weight_percent.toFixed(2)}%
                          </td>
                        </tr>
                      ))}
                      {riskStats?.details && riskStats.details.length > 0 && (
                        <tr className="border-t-2 border-blue-500 bg-blue-500/10">
                          <td className="py-3 px-2 text-sm font-bold text-white" colSpan={2}>Media Ponderata</td>
                          <td className="py-3 px-2 text-sm text-right font-bold text-blue-300">
                            {riskStats.isr !== null ? riskStats.isr.toFixed(2) : 'N/A'}
                          </td>
                          <td className="py-3 px-2 text-sm text-right font-bold text-blue-300">
                            {riskStats.standard_deviation !== null ? `${riskStats.standard_deviation.toFixed(2)}%` : 'N/A'}
                          </td>
                          <td className="py-3 px-2 text-sm text-right font-bold text-blue-300">
                            {riskStats.sharpe_ratio !== null ? riskStats.sharpe_ratio.toFixed(2) : 'N/A'}
                          </td>
                          <td className="py-3 px-2 text-sm text-right font-bold text-blue-300">100.00%</td>
                        </tr>
                      )}
                    </>
                  )}
                </tbody>
              </table>
            </div>
          )}
        </div>
      </div>

      {/* Detail Modal */}
      {
        detailModal && (
          <Modal
            title={`Dettagli: ${detailModal.name}${detailModal.symbol ? ` (${detailModal.symbol})` : ''}`}
            onClose={() => setDetailModal(null)}
            size="large"
          >
            {loadingDetails ? (
              <div className="flex items-center justify-center py-8">
                <Loader2 className="w-8 h-8 animate-spin text-blue-400" />
              </div>
            ) : (
              <div className="overflow-x-auto">
                <table className="w-full">
                  <thead>
                    <tr className="border-b border-white/20">
                      <th className="text-left py-3 px-4 text-sm font-medium text-gray-300">Asset</th>
                      <th className="text-left py-3 px-4 text-sm font-medium text-gray-300">Ticker</th>
                      <th className="text-right py-3 px-4 text-sm font-medium text-gray-300">Valore Asset</th>
                      {detailModal.type === 'riskStats' ? (
                        <>
                          <th className="text-right py-3 px-4 text-sm font-medium text-gray-300">ISR</th>
                          <th className="text-right py-3 px-4 text-sm font-medium text-gray-300">Dev. Std.</th>
                          <th className="text-right py-3 px-4 text-sm font-medium text-gray-300">Sharpe</th>
                          <th className="text-right py-3 px-4 text-sm font-medium text-gray-300">Peso %</th>
                        </>
                      ) : (
                        <>
                          <th className="text-right py-3 px-4 text-sm font-medium text-gray-300">
                            {detailModal.type === 'holding' && 'Peso Holding'}
                            {detailModal.type === 'sector' && 'Peso Settore'}
                            {detailModal.type === 'region' && 'Peso Regione'}
                            {detailModal.type === 'allocation' && 'Peso Allocation'}
                            {detailModal.type === 'bondRating' && 'Peso Rating'}
                            {detailModal.type === 'bondMaturity' && 'Peso Maturity'}
                          </th>
                          <th className="text-right py-3 px-4 text-sm font-medium text-gray-300">Valore Assoluto</th>
                          <th className="text-right py-3 px-4 text-sm font-medium text-gray-300">Contributo %</th>
                        </>
                      )}
                    </tr>
                  </thead>
                  <tbody>
                    {detailModal.type === 'riskStats' ? (
                      detailModal.details.map((detail: RiskStatsDetail, index) => (
                        <tr key={index} className="border-b border-white/10">
                          <td className="py-3 px-4 text-sm text-white">{detail.asset_name}</td>
                          <td className="py-3 px-4 text-sm text-gray-400">{detail.ticker || 'N/A'}</td>
                          <td className="py-3 px-4 text-sm text-right text-white">
                            {detail.isr !== null ? detail.isr.toFixed(2) : 'N/A'}
                          </td>
                          <td className="py-3 px-4 text-sm text-right text-white">
                            {detail.standard_deviation !== null ? `${detail.standard_deviation.toFixed(2)}%` : 'N/A'}
                          </td>
                          <td className="py-3 px-4 text-sm text-right text-white">
                            {detail.sharpe_ratio !== null ? detail.sharpe_ratio.toFixed(2) : 'N/A'}
                          </td>
                          <td className="py-3 px-4 text-sm text-right font-medium text-blue-400">
                            {detail.weight_percent.toFixed(2)}%
                          </td>
                        </tr>
                      ))
                    ) : (
                      detailModal.details.map((detail, index) => (
                        <tr key={index} className="border-b border-white/10">
                          <td className="py-3 px-4 text-sm text-white">{detail.asset_name}</td>
                          <td className="py-3 px-4 text-sm text-gray-400">{detail.ticker}</td>
                          <td className="py-3 px-4 text-sm text-right text-white">
                            €{detail.current_value.toLocaleString('it-IT', { minimumFractionDigits: 2, maximumFractionDigits: 2 })}
                          </td>
                          <td className="py-3 px-4 text-sm text-right text-blue-400">
                            {(
                              detail.holding_percent ||
                              detail.sector_percent ||
                              detail.region_percent ||
                              detail.allocation_percent ||
                              detail.rating_percent ||
                              detail.maturity_percent
                            )?.toFixed(2)}%
                          </td>
                          <td className="py-3 px-4 text-sm text-right text-white">
                            €{(
                              detail.holding_value ||
                              detail.sector_value ||
                              detail.region_value ||
                              detail.allocation_value ||
                              detail.rating_value ||
                              detail.maturity_value
                            )?.toLocaleString('it-IT', { minimumFractionDigits: 2, maximumFractionDigits: 2 })}
                          </td>
                          <td className="py-3 px-4 text-sm text-right text-green-400 font-medium">
                            {detail.contribution_percent?.toFixed(2)}%
                          </td>
                        </tr>
                      ))
                    )}
                    {detailModal.details.length > 0 && detailModal.type !== 'riskStats' && (
                      <tr className="border-t-2 border-blue-500 bg-blue-500/10">
                        <td colSpan={3} className="py-3 px-4 text-sm font-bold text-white">Totale</td>
                        <td className="py-3 px-4 text-sm text-right font-bold text-blue-300">-</td>
                        <td className="py-3 px-4 text-sm text-right font-bold text-blue-300">
                          €{detailModal.details
                            .reduce((sum, d) => sum + (
                              d.holding_value ||
                              d.sector_value ||
                              d.region_value ||
                              d.allocation_value ||
                              d.rating_value ||
                              d.maturity_value || 0
                            ), 0)
                            .toLocaleString('it-IT', { minimumFractionDigits: 2, maximumFractionDigits: 2 })}
                        </td>
                        <td className="py-3 px-4 text-sm text-right font-bold text-blue-300">100.00%</td>
                      </tr>
                    )}
                    {detailModal.details.length > 0 && detailModal.type === 'riskStats' && riskStats && (
                      <tr className="border-t-2 border-blue-500 bg-blue-500/10">
                        <td colSpan={2} className="py-3 px-4 text-sm font-bold text-white">Media Ponderata</td>
                        <td className="py-3 px-4 text-sm text-right font-bold text-blue-300">
                          {riskStats.isr !== null ? riskStats.isr.toFixed(2) : 'N/A'}
                        </td>
                        <td className="py-3 px-4 text-sm text-right font-bold text-blue-300">
                          {riskStats.standard_deviation !== null ? `${riskStats.standard_deviation.toFixed(2)}%` : 'N/A'}
                        </td>
                        <td className="py-3 px-4 text-sm text-right font-bold text-blue-300">
                          {riskStats.sharpe_ratio !== null ? riskStats.sharpe_ratio.toFixed(2) : 'N/A'}
                        </td>
                        <td className="py-3 px-4 text-sm text-right font-bold text-blue-300">100.00%</td>
                      </tr>
                    )}
                  </tbody>
                </table>
                {detailModal.details.length === 0 && (
                  <div className="text-center py-8 text-gray-400">
                    Nessun dettaglio disponibile
                  </div>
                )}
              </div>
            )}
          </Modal>
        )
      }
    </div >
  );
};
