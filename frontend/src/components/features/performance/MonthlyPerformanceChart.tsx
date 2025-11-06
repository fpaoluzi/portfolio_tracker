'use client';

import { useState, useEffect } from 'react';
import { LineChart, Line, XAxis, YAxis, CartesianGrid, Tooltip, Legend, ResponsiveContainer } from 'recharts';
import { TrendingUp, Loader2 } from 'lucide-react';
import { Button } from '@/components/ui';

const API_URL = 'http://localhost:3001';

interface MonthlyData {
  asset_id: string;
  asset_name: string;
  asset_type: string;
  ticker?: string;
  month_year: string;
  price: number;
  quantity: number;
  value: number;
  total_invested: number;
  gain_loss: number;
  gain_loss_pct: number;
  month_return_pct: number;
}

interface AggregatedData {
  month_year: string;
  total_value: number;
  total_invested: number;
  total_gain_loss: number;
  total_return_pct: number;
  num_positions: number;
  positions: MonthlyData[];
}

interface MonthlyPerformanceChartProps {
  portfolioId: string;
}

const COLORS = [
  '#3b82f6', // blue
  '#10b981', // green
  '#f59e0b', // amber
  '#ef4444', // red
  '#8b5cf6', // violet
  '#ec4899', // pink
  '#06b6d4', // cyan
  '#f97316', // orange
  '#14b8a6', // teal
  '#a855f7', // purple
];

export const MonthlyPerformanceChart: React.FC<MonthlyPerformanceChartProps> = ({ portfolioId }) => {
  const [loading, setLoading] = useState(false);
  const [months, setMonths] = useState(12);
  const [viewMode, setViewMode] = useState<'portfolio' | 'assets'>('portfolio');
  const [selectedAssets, setSelectedAssets] = useState<string[]>([]);
  const [hasLoaded, setHasLoaded] = useState(false);
  const [data, setData] = useState<{
    positions: MonthlyData[];
    aggregated: AggregatedData[];
  } | null>(null);

  // Rimosso useEffect - l'utente deve cliccare esplicitamente

  const fetchData = async () => {
    setLoading(true);
    try {
      console.log('[MonthlyPerformance] Fetching data for portfolio:', portfolioId, 'months:', months);
      const url = `${API_URL}/api/portfolios/${portfolioId}/monthly-performance-live?months=${months}`;
      console.log('[MonthlyPerformance] URL:', url);

      const response = await fetch(url);
      console.log('[MonthlyPerformance] Response status:', response.status);

      const result = await response.json();
      console.log('[MonthlyPerformance] Result:', result);
      console.log('[MonthlyPerformance] Positions count:', result.positions?.length || 0);
      console.log('[MonthlyPerformance] Aggregated count:', result.aggregated?.length || 0);

      setData(result);
      setHasLoaded(true);

      // Seleziona automaticamente i primi 5 asset per la vista dettaglio
      if (result.positions && result.positions.length > 0) {
        const uniqueAssets = Array.from(new Set<string>(result.positions.map((p: MonthlyData) => p.asset_id)));
        console.log('[MonthlyPerformance] Unique assets:', uniqueAssets.length);
        setSelectedAssets(uniqueAssets.slice(0, 5));
      }
    } catch (error) {
      console.error('[MonthlyPerformance] Errore nel recupero performance mensili:', error);
    } finally {
      setLoading(false);
    }
  };

  // Handler per il bottone carica/aggiorna
  const handleLoadData = () => {
    fetchData();
  };

  const toggleAssetSelection = (assetId: string) => {
    setSelectedAssets(prev =>
      prev.includes(assetId)
        ? prev.filter(id => id !== assetId)
        : [...prev, assetId]
    );
  };

  // Prepara dati per grafico portafoglio
  const portfolioChartData = data?.aggregated.map(month => ({
    month: new Date(month.month_year).toLocaleDateString('it-IT', { month: 'short', year: '2-digit' }),
    'Valore Portafoglio': month.total_value,
    'Investito': month.total_invested,
  })) || [];

  // Prepara dati per grafico asset individuali
  const assetsChartData = () => {
    if (!data || selectedAssets.length === 0) return [];

    const months = Array.from(new Set(data.positions.map(p => p.month_year))).sort();

    return months.map(month => {
      const monthData: any = {
        month: new Date(month).toLocaleDateString('it-IT', { month: 'short', year: '2-digit' }),
      };

      selectedAssets.forEach(assetId => {
        const position = data.positions.find(p => p.month_year === month && p.asset_id === assetId);
        if (position) {
          monthData[position.asset_name] = position.value;
        }
      });

      return monthData;
    });
  };

  // Lista asset unici
  const uniqueAssets = data?.positions.reduce((acc, pos) => {
    if (!acc.find(a => a.asset_id === pos.asset_id)) {
      acc.push({
        asset_id: pos.asset_id,
        asset_name: pos.asset_name,
        asset_type: pos.asset_type,
      });
    }
    return acc;
  }, [] as { asset_id: string; asset_name: string; asset_type: string }[]) || [];

  const formatCurrency = (value: number) => {
    return new Intl.NumberFormat('it-IT', {
      style: 'currency',
      currency: 'EUR',
      minimumFractionDigits: 0,
      maximumFractionDigits: 0,
    }).format(value);
  };

  const formatPercent = (value: number) => {
    return `${value >= 0 ? '+' : ''}${value.toFixed(2)}%`;
  };

  // Vista iniziale: mostra bottone per caricare dati
  if (!hasLoaded && !loading) {
    return (
      <div className="bg-white/10 backdrop-blur-lg rounded-2xl border border-white/20 p-12">
        <div className="flex flex-col items-center justify-center text-center">
          <TrendingUp className="w-16 h-16 text-blue-400 mb-4" />
          <h3 className="text-xl font-bold text-white mb-2">Analisi Storica Performance</h3>
          <p className="text-blue-200 mb-6 max-w-md">
            Clicca sul pulsante per caricare l'analisi delle performance mensili.
            I dati vengono recuperati da Yahoo Finance in tempo reale.
          </p>

          <div className="flex gap-3 items-center mb-4">
            <select
              value={months}
              onChange={(e) => setMonths(parseInt(e.target.value))}
              className="px-4 py-2 bg-white/10 border border-white/20 rounded-lg text-white focus:outline-none focus:ring-2 focus:ring-blue-500 [&>option]:bg-slate-800 [&>option]:text-white"
            >
              <option value="6">Ultimi 6 mesi</option>
              <option value="12">Ultimi 12 mesi</option>
              <option value="24">Ultimi 24 mesi</option>
              <option value="36">Ultimi 36 mesi</option>
            </select>
          </div>

          <Button
            onClick={handleLoadData}
            variant="primary"
            className="px-8 py-3 text-lg"
          >
            <TrendingUp className="w-5 h-5 mr-2" />
            Carica Analisi Storica
          </Button>

          <p className="text-xs text-blue-300 mt-4">
            ⚠️ Il caricamento può richiedere alcuni secondi
          </p>
        </div>
      </div>
    );
  }

  // Stato di caricamento
  if (loading) {
    return (
      <div className="bg-white/10 backdrop-blur-lg rounded-2xl border border-white/20 p-12">
        <div className="flex flex-col items-center justify-center">
          <Loader2 className="w-12 h-12 text-blue-400 animate-spin mb-4" />
          <p className="text-blue-200">Caricamento performance mensili...</p>
          <p className="text-sm text-blue-300 mt-2">Recupero dati da Yahoo Finance (può richiedere 30-60 secondi)</p>
          <div className="w-full max-w-md mt-4">
            <div className="h-2 bg-white/10 rounded-full overflow-hidden">
              <div className="h-full bg-blue-500 animate-pulse" style={{ width: '60%' }}></div>
            </div>
          </div>
        </div>
      </div>
    );
  }

  // Nessun dato disponibile
  if (!data || data.aggregated.length === 0) {
    return (
      <div className="bg-white/10 backdrop-blur-lg rounded-2xl border border-white/20 p-12 text-center">
        <TrendingUp className="w-12 h-12 text-blue-400 mx-auto mb-4" />
        <p className="text-blue-200 mb-2">Nessun dato disponibile</p>
        <p className="text-sm text-blue-300 mb-6">
          Aggiungi transazioni con asset che hanno ticker validi
        </p>
        <Button onClick={handleLoadData} variant="secondary">
          Riprova
        </Button>
      </div>
    );
  }

  const currentData = data.aggregated[data.aggregated.length - 1];
  const previousData = data.aggregated[data.aggregated.length - 2];
  const monthChange = previousData
    ? ((currentData.total_value - previousData.total_value) / previousData.total_value) * 100
    : 0;

  return (
    <div className="bg-white/10 backdrop-blur-lg rounded-2xl border border-white/20 overflow-hidden">
      {/* Header */}
      <div className="p-6 border-b border-white/20">
        <div className="flex flex-col lg:flex-row justify-between items-start lg:items-center gap-4">
          <div>
            <h2 className="text-xl font-bold text-white flex items-center gap-2">
              <TrendingUp className="w-6 h-6" />
              Andamento Mensile
            </h2>
            <p className="text-sm text-blue-300 mt-1">
              Performance degli ultimi {months} mesi
            </p>
          </div>

          <div className="flex gap-3 flex-wrap">
            <select
              value={months}
              onChange={(e) => setMonths(parseInt(e.target.value))}
              className="px-4 py-2 bg-white/10 border border-white/20 rounded-lg text-white focus:outline-none focus:ring-2 focus:ring-blue-500 [&>option]:bg-slate-800 [&>option]:text-white"
            >
              <option value="6">6 mesi</option>
              <option value="12">12 mesi</option>
              <option value="24">24 mesi</option>
              <option value="36">36 mesi</option>
            </select>

            <Button
              onClick={handleLoadData}
              variant="secondary"
              disabled={loading}
              className="flex items-center gap-2"
            >
              {loading ? (
                <Loader2 className="w-4 h-4 animate-spin" />
              ) : (
                <TrendingUp className="w-4 h-4" />
              )}
              {loading ? 'Aggiornamento...' : 'Aggiorna Dati'}
            </Button>

            <Button
              variant={viewMode === 'portfolio' ? 'primary' : 'secondary'}
              onClick={() => setViewMode('portfolio')}
            >
              Portafoglio
            </Button>
            <Button
              variant={viewMode === 'assets' ? 'primary' : 'secondary'}
              onClick={() => setViewMode('assets')}
            >
              Per Asset
            </Button>
          </div>
        </div>

        {/* Stats */}
        <div className="grid grid-cols-1 md:grid-cols-4 gap-4 mt-6">
          <div className="bg-white/5 rounded-lg p-4">
            <div className="text-xs text-blue-300 mb-1">Valore Corrente</div>
            <div className="text-lg font-bold text-white">
              {formatCurrency(currentData.total_value)}
            </div>
          </div>
          <div className="bg-white/5 rounded-lg p-4">
            <div className="text-xs text-blue-300 mb-1">Investito</div>
            <div className="text-lg font-bold text-purple-300">
              {formatCurrency(currentData.total_invested)}
            </div>
          </div>
          <div className="bg-white/5 rounded-lg p-4">
            <div className="text-xs text-blue-300 mb-1">Guadagno/Perdita</div>
            <div className={`text-lg font-bold ${currentData.total_gain_loss >= 0 ? 'text-green-400' : 'text-red-400'}`}>
              {formatCurrency(currentData.total_gain_loss)}
            </div>
          </div>
          <div className="bg-white/5 rounded-lg p-4">
            <div className="text-xs text-blue-300 mb-1">Rendimento Totale</div>
            <div className={`text-lg font-bold ${currentData.total_return_pct >= 0 ? 'text-green-400' : 'text-red-400'}`}>
              {formatPercent(currentData.total_return_pct)}
            </div>
          </div>
        </div>
      </div>

      {/* Chart */}
      <div className="p-6">
        {viewMode === 'portfolio' ? (
          <ResponsiveContainer width="100%" height={400}>
            <LineChart data={portfolioChartData}>
              <CartesianGrid strokeDasharray="3 3" stroke="rgba(255,255,255,0.1)" />
              <XAxis
                dataKey="month"
                stroke="rgba(255,255,255,0.5)"
                style={{ fontSize: '12px' }}
              />
              <YAxis
                stroke="rgba(255,255,255,0.5)"
                style={{ fontSize: '12px' }}
                tickFormatter={(value) => `€${(value / 1000).toFixed(0)}k`}
              />
              <Tooltip
                contentStyle={{
                  backgroundColor: 'rgba(15, 23, 42, 0.95)',
                  border: '1px solid rgba(255,255,255,0.2)',
                  borderRadius: '8px',
                  color: '#fff',
                }}
                formatter={(value: any) => formatCurrency(value)}
              />
              <Legend
                wrapperStyle={{ color: '#fff' }}
              />
              <Line
                type="monotone"
                dataKey="Valore Portafoglio"
                stroke="#3b82f6"
                strokeWidth={3}
                dot={{ fill: '#3b82f6', r: 4 }}
                activeDot={{ r: 6 }}
              />
              <Line
                type="monotone"
                dataKey="Investito"
                stroke="#8b5cf6"
                strokeWidth={2}
                strokeDasharray="5 5"
                dot={{ fill: '#8b5cf6', r: 3 }}
              />
            </LineChart>
          </ResponsiveContainer>
        ) : (
          <>
            {/* Selezione Asset */}
            <div className="mb-6">
              <h3 className="text-sm font-medium text-blue-200 mb-3">
                Seleziona Asset da Visualizzare (max 10)
              </h3>
              <div className="flex flex-wrap gap-2">
                {uniqueAssets.map((asset, index) => (
                  <button
                    key={asset.asset_id}
                    onClick={() => toggleAssetSelection(asset.asset_id)}
                    disabled={!selectedAssets.includes(asset.asset_id) && selectedAssets.length >= 10}
                    className={`px-3 py-1.5 rounded-lg text-sm font-medium transition-all ${
                      selectedAssets.includes(asset.asset_id)
                        ? 'bg-blue-500 text-white'
                        : 'bg-white/10 text-blue-300 hover:bg-white/20'
                    } ${
                      !selectedAssets.includes(asset.asset_id) && selectedAssets.length >= 10
                        ? 'opacity-50 cursor-not-allowed'
                        : ''
                    }`}
                  >
                    {asset.asset_name}
                  </button>
                ))}
              </div>
            </div>

            {/* Grafico Asset */}
            {selectedAssets.length > 0 ? (
              <ResponsiveContainer width="100%" height={400}>
                <LineChart data={assetsChartData()}>
                  <CartesianGrid strokeDasharray="3 3" stroke="rgba(255,255,255,0.1)" />
                  <XAxis
                    dataKey="month"
                    stroke="rgba(255,255,255,0.5)"
                    style={{ fontSize: '12px' }}
                  />
                  <YAxis
                    stroke="rgba(255,255,255,0.5)"
                    style={{ fontSize: '12px' }}
                    tickFormatter={(value) => `€${(value / 1000).toFixed(0)}k`}
                  />
                  <Tooltip
                    contentStyle={{
                      backgroundColor: 'rgba(15, 23, 42, 0.95)',
                      border: '1px solid rgba(255,255,255,0.2)',
                      borderRadius: '8px',
                      color: '#fff',
                    }}
                    formatter={(value: any) => formatCurrency(value)}
                  />
                  <Legend
                    wrapperStyle={{ color: '#fff' }}
                  />
                  {selectedAssets.map((assetId, index) => {
                    const asset = uniqueAssets.find(a => a.asset_id === assetId);
                    return asset ? (
                      <Line
                        key={assetId}
                        type="monotone"
                        dataKey={asset.asset_name}
                        stroke={COLORS[index % COLORS.length]}
                        strokeWidth={2}
                        dot={{ fill: COLORS[index % COLORS.length], r: 3 }}
                        activeDot={{ r: 5 }}
                      />
                    ) : null;
                  })}
                </LineChart>
              </ResponsiveContainer>
            ) : (
              <div className="h-[400px] flex items-center justify-center text-blue-300">
                Seleziona almeno un asset per visualizzare il grafico
              </div>
            )}
          </>
        )}
      </div>

      {/* Dettagli Rendimenti */}
      <div className="p-6 border-t border-white/20">
        <h3 className="text-sm font-medium text-blue-200 mb-3">
          Rendimenti Mensili per Asset (ultimo mese)
        </h3>
        <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-3">
          {uniqueAssets.map(asset => {
            const lastMonth = data.positions
              .filter(p => p.asset_id === asset.asset_id)
              .sort((a, b) => b.month_year.localeCompare(a.month_year))[0];

            if (!lastMonth) return null;

            return (
              <div
                key={asset.asset_id}
                className="bg-white/5 rounded-lg p-3 hover:bg-white/10 transition-colors"
              >
                <div className="flex justify-between items-start mb-2">
                  <div className="flex-1">
                    <div className="text-sm font-medium text-white truncate">
                      {asset.asset_name}
                    </div>
                    <div className="text-xs text-blue-300">{asset.asset_type}</div>
                  </div>
                  <div className={`text-sm font-bold ${lastMonth.month_return_pct >= 0 ? 'text-green-400' : 'text-red-400'}`}>
                    {formatPercent(lastMonth.month_return_pct)}
                  </div>
                </div>
                <div className="text-xs text-blue-200">
                  Valore: {formatCurrency(lastMonth.value)}
                </div>
              </div>
            );
          })}
        </div>
      </div>
    </div>
  );
};
