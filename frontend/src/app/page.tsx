'use client';

import { useState, useEffect } from 'react';
import {
  TrendingUp,
  TrendingDown,
  RefreshCw,
  Download,
  Plus,
  Upload,
  DollarSign,
  Percent,
  Edit2,
  Trash2,
} from 'lucide-react';
import {
  LineChart,
  Line,
  PieChart,
  Pie,
  Cell,
  BarChart,
  Bar,
  XAxis,
  YAxis,
  CartesianGrid,
  Tooltip,
  Legend,
  ResponsiveContainer,
} from 'recharts';
import { Button } from '@/components/ui';
import { PortfolioFormModal } from '@/components/features/portfolio/PortfolioFormModal';
import { AssetFormModal } from '@/components/features/asset/AssetFormModal';
import { AssetsList } from '@/components/features/asset/AssetsList';
import { TransactionFormModal } from '@/components/features/transaction/TransactionFormModal';
import { ImportExcelModal } from '@/components/features/transaction/ImportExcelModal';
import { MonthlyPerformanceChart } from '@/components/features/performance/MonthlyPerformanceChart';
import { portfoliosApi, assetsApi, transactionsApi } from '@/lib/api';
import { usePortfolio } from '@/lib/hooks/usePortfolio';
import { formatCurrency, formatPercent, formatDate } from '@/lib/utils/format';
import { getColorByIndex } from '@/lib/utils/colors';
import type { Portfolio, Asset } from '@/types';

export default function Home() {
  const [portfolios, setPortfolios] = useState<Portfolio[]>([]);
  const [selectedPortfolio, setSelectedPortfolio] = useState<Portfolio | null>(null);
  const [assets, setAssets] = useState<Asset[]>([]);
  const [editingAsset, setEditingAsset] = useState<Asset | null>(null);
  const [editingTransaction, setEditingTransaction] = useState<any | null>(null);
  const [activeTab, setActiveTab] = useState('overview');
  const [showModal, setShowModal] = useState<string | null>(null);

  // Stati per filtri e ordinamento
  const [positionFilter, setPositionFilter] = useState('');
  const [positionTypeFilter, setPositionTypeFilter] = useState('');
  const [positionSort, setPositionSort] = useState<{ field: string; direction: 'asc' | 'desc' }>({ field: 'asset_name', direction: 'asc' });
  const [transactionFilter, setTransactionFilter] = useState('');
  const [transactionTypeFilter, setTransactionTypeFilter] = useState('');
  const [transactionSort, setTransactionSort] = useState<{ field: string; direction: 'asc' | 'desc' }>({ field: 'transaction_date', direction: 'desc' });
  const [assetFilter, setAssetFilter] = useState('');
  const [assetSort, setAssetSort] = useState<{ field: string; direction: 'asc' | 'desc' }>({ field: 'name', direction: 'asc' });

  const {
    loading,
    positions,
    transactions,
    performance,
    allocation,
    snapshots,
    geoAllocation,
    updatePrices,
    refreshData,
  } = usePortfolio(selectedPortfolio?.portfolio_id || null);

  useEffect(() => {
    loadPortfolios();
    loadAssets();
  }, []);

  const loadPortfolios = async () => {
    try {
      const data = await portfoliosApi.getAll();
      setPortfolios(data);
      if (data.length > 0 && !selectedPortfolio) {
        setSelectedPortfolio(data[0]);
      }
    } catch (error) {
      console.error('Error loading portfolios:', error);
    }
  };

  const loadAssets = async () => {
    try {
      const data = await assetsApi.getAll();
      setAssets(data);
    } catch (error) {
      console.error('Error loading assets:', error);
    }
  };

  const handleEditAsset = (asset: Asset) => {
    setEditingAsset(asset);
    setShowModal('asset');
  };

  const handleDeleteAsset = async (asset: Asset) => {
    if (!confirm(`Sei sicuro di voler eliminare l'asset "${asset.name}"?`)) {
      return;
    }

    try {
      await assetsApi.delete(asset.asset_id);
      await loadAssets();
    } catch (error) {
      console.error('Error deleting asset:', error);
      alert('Errore nell\'eliminazione dell\'asset');
    }
  };

  const handleCloseAssetModal = () => {
    setShowModal(null);
    setEditingAsset(null);
  };

  const handleEditTransaction = (transaction: any) => {
    setEditingTransaction(transaction);
    setShowModal('transaction');
  };

  const handleDeleteTransaction = async (transaction: any) => {
    if (!confirm(`Sei sicuro di voler eliminare questa transazione?`)) {
      return;
    }

    try {
      await transactionsApi.delete(transaction.transaction_id);
      await refreshData();
    } catch (error) {
      console.error('Error deleting transaction:', error);
      alert('Errore nell\'eliminazione della transazione');
    }
  };

  const handleCloseTransactionModal = () => {
    setShowModal(null);
    setEditingTransaction(null);
  };

  const exportToExcel = () => {
    const data = {
      portfolios,
      positions,
      transactions,
      performance,
      allocation,
    };

    const jsonStr = JSON.stringify(data, null, 2);
    const blob = new Blob([jsonStr], { type: 'application/json' });
    const url = URL.createObjectURL(blob);
    const a = document.createElement('a');
    a.href = url;
    a.download = `portfolio_export_${new Date().toISOString().split('T')[0]}.json`;
    a.click();
    URL.revokeObjectURL(url);
  };

  // Funzioni helper per filtrare e ordinare
  const filterAndSortPositions = () => {
    let filtered = positions.filter(pos =>
      (pos.asset_name.toLowerCase().includes(positionFilter.toLowerCase()) ||
       pos.isin.toLowerCase().includes(positionFilter.toLowerCase())) &&
      (!positionTypeFilter || pos.asset_type === positionTypeFilter)
    );

    return filtered.sort((a, b) => {
      const aVal = a[positionSort.field as keyof typeof a];
      const bVal = b[positionSort.field as keyof typeof b];
      const multiplier = positionSort.direction === 'asc' ? 1 : -1;

      if (typeof aVal === 'string' && typeof bVal === 'string') {
        return multiplier * aVal.localeCompare(bVal);
      }
      return multiplier * (Number(aVal) - Number(bVal));
    });
  };

  const filterAndSortTransactions = () => {
    let filtered = transactions.filter(tx =>
      (tx.asset_name?.toLowerCase().includes(transactionFilter.toLowerCase()) ||
      tx.isin?.toLowerCase().includes(transactionFilter.toLowerCase()) ||
      tx.transaction_type.toLowerCase().includes(transactionFilter.toLowerCase())) &&
      (!transactionTypeFilter || tx.transaction_type === transactionTypeFilter)
    );

    return filtered.sort((a, b) => {
      const aVal = a[transactionSort.field as keyof typeof a];
      const bVal = b[transactionSort.field as keyof typeof b];
      const multiplier = transactionSort.direction === 'asc' ? 1 : -1;

      if (transactionSort.field === 'transaction_date') {
        return multiplier * (new Date(String(aVal)).getTime() - new Date(String(bVal)).getTime());
      }

      if (typeof aVal === 'string' && typeof bVal === 'string') {
        return multiplier * aVal.localeCompare(bVal);
      }
      return multiplier * (Number(aVal) - Number(bVal));
    });
  };

  const filterAndSortAssets = () => {
    let filtered = assets.filter(asset =>
      asset.name.toLowerCase().includes(assetFilter.toLowerCase()) ||
      asset.isin.toLowerCase().includes(assetFilter.toLowerCase()) ||
      (asset.ticker && asset.ticker.toLowerCase().includes(assetFilter.toLowerCase()))
    );

    return filtered.sort((a, b) => {
      const aVal = a[assetSort.field as keyof typeof a];
      const bVal = b[assetSort.field as keyof typeof b];
      const multiplier = assetSort.direction === 'asc' ? 1 : -1;

      if (typeof aVal === 'string' && typeof bVal === 'string') {
        return multiplier * aVal.localeCompare(bVal);
      }
      return multiplier * (Number(aVal) - Number(bVal));
    });
  };

  const toggleSort = (section: 'position' | 'transaction' | 'asset', field: string) => {
    if (section === 'position') {
      setPositionSort(prev => ({
        field,
        direction: prev.field === field && prev.direction === 'asc' ? 'desc' : 'asc'
      }));
    } else if (section === 'transaction') {
      setTransactionSort(prev => ({
        field,
        direction: prev.field === field && prev.direction === 'asc' ? 'desc' : 'asc'
      }));
    } else {
      setAssetSort(prev => ({
        field,
        direction: prev.field === field && prev.direction === 'asc' ? 'desc' : 'asc'
      }));
    }
  };

  // Calcola i totali
  const filteredPositions = filterAndSortPositions();
  const positionTotals = filteredPositions.reduce((acc, pos) => ({
    invested: acc.invested + Number(pos.total_invested),
    value: acc.value + Number(pos.current_value),
    gainLoss: acc.gainLoss + Number(pos.gain_loss)
  }), { invested: 0, value: 0, gainLoss: 0 });

  const filteredTransactions = filterAndSortTransactions();
  const transactionTotals = filteredTransactions.reduce((acc, tx) => ({
    buy: acc.buy + (tx.transaction_type === 'BUY' ? Number(tx.total_amount) : 0),
    sell: acc.sell + (tx.transaction_type === 'SELL' ? Number(tx.total_amount) : 0),
    commission: acc.commission + Number(tx.commission),
    fees: acc.fees + Number(tx.fees)
  }), { buy: 0, sell: 0, commission: 0, fees: 0 });

  const filteredAssets = filterAndSortAssets();

  // Helper per i colori dei badge dei tipi di asset
  const getAssetTypeColor = (assetType: string) => {
    const colors: { [key: string]: string } = {
      'Azionario': 'bg-blue-500/20 text-blue-300',
      'Obbligazionario': 'bg-green-500/20 text-green-300',
      'Monetario': 'bg-yellow-500/20 text-yellow-300',
      'Oro': 'bg-amber-500/20 text-amber-300',
      'Crypto': 'bg-purple-500/20 text-purple-300',
      'ETF': 'bg-cyan-500/20 text-cyan-300',
    };
    return colors[assetType] || 'bg-gray-500/20 text-gray-300';
  };

  return (
    <div className="min-h-screen bg-gradient-to-br from-slate-900 via-blue-900 to-slate-900 p-4">
      <div className="max-w-[1920px] mx-auto px-4">
        {/* Header */}
        <div className="bg-white/10 backdrop-blur-lg rounded-2xl p-6 mb-6 border border-white/20 shadow-2xl">
          <div className="flex flex-col md:flex-row justify-between items-start md:items-center gap-4">
            <div>
              <h1 className="text-3xl font-bold text-white mb-2">
                Portfolio Tracker Pro
              </h1>
              <p className="text-blue-200">
                Gestione completa con database PostgreSQL (Next.js)
              </p>
            </div>
            <div className="flex gap-3 flex-wrap">
              <Button
                variant="success"
                icon={Plus}
                onClick={() => setShowModal('portfolio')}
              >
                Nuovo Portafoglio
              </Button>
              <Button
                variant="purple"
                icon={Plus}
                onClick={() => setShowModal('asset')}
              >
                Nuovo Asset
              </Button>
              <Button variant="primary" icon={Download} onClick={exportToExcel}>
                Export
              </Button>
              <Button
                variant="warning"
                icon={RefreshCw}
                onClick={updatePrices}
                disabled={loading}
                className={loading ? 'animate-spin' : ''}
              >
                Aggiorna Prezzi
              </Button>
            </div>
          </div>

          {portfolios.length > 0 && (
            <div className="mt-4 flex gap-2 overflow-x-auto pb-2">
              {portfolios.map((p) => (
                <button
                  key={p.portfolio_id}
                  onClick={() => setSelectedPortfolio(p)}
                  className={`px-4 py-2 rounded-lg whitespace-nowrap transition-all ${
                    selectedPortfolio?.portfolio_id === p.portfolio_id
                      ? 'bg-blue-500 text-white'
                      : 'bg-white/10 text-blue-200 hover:bg-white/20'
                  }`}
                >
                  {p.name}
                </button>
              ))}
            </div>
          )}
        </div>

        {/* Stats Cards */}
        {performance && (
          <div className="grid grid-cols-1 md:grid-cols-4 gap-4 mb-6">
            <div className="bg-gradient-to-br from-blue-500/20 to-blue-600/20 backdrop-blur-lg rounded-xl p-6 border border-blue-400/30">
              <div className="flex items-center justify-between mb-2">
                <span className="text-blue-200 text-sm">Valore Totale</span>
                <DollarSign className="w-5 h-5 text-blue-400" />
              </div>
              <div className="text-2xl font-bold text-white">
                {formatCurrency(performance.current_value)}
              </div>
            </div>

            <div className="bg-gradient-to-br from-purple-500/20 to-purple-600/20 backdrop-blur-lg rounded-xl p-6 border border-purple-400/30">
              <div className="flex items-center justify-between mb-2">
                <span className="text-purple-200 text-sm">Investito</span>
                <DollarSign className="w-5 h-5 text-purple-400" />
              </div>
              <div className="text-2xl font-bold text-white">
                {formatCurrency(performance.total_invested)}
              </div>
            </div>

            <div
              className={`bg-gradient-to-br ${
                Number(performance.total_gain_loss) >= 0
                  ? 'from-green-500/20 to-green-600/20'
                  : 'from-red-500/20 to-red-600/20'
              } backdrop-blur-lg rounded-xl p-6 border ${
                Number(performance.total_gain_loss) >= 0
                  ? 'border-green-400/30'
                  : 'border-red-400/30'
              }`}
            >
              <div className="flex items-center justify-between mb-2">
                <span
                  className={`${
                    Number(performance.total_gain_loss) >= 0
                      ? 'text-green-200'
                      : 'text-red-200'
                  } text-sm`}
                >
                  G/P
                </span>
                {Number(performance.total_gain_loss) >= 0 ? (
                  <TrendingUp className="w-5 h-5 text-green-400" />
                ) : (
                  <TrendingDown className="w-5 h-5 text-red-400" />
                )}
              </div>
              <div className="text-2xl font-bold text-white">
                {formatCurrency(performance.total_gain_loss)}
              </div>
            </div>

            <div
              className={`bg-gradient-to-br ${
                Number(performance.total_gain_loss_pct) >= 0
                  ? 'from-green-500/20 to-green-600/20'
                  : 'from-red-500/20 to-red-600/20'
              } backdrop-blur-lg rounded-xl p-6 border ${
                Number(performance.total_gain_loss_pct) >= 0
                  ? 'border-green-400/30'
                  : 'border-red-400/30'
              }`}
            >
              <div className="flex items-center justify-between mb-2">
                <span
                  className={`${
                    Number(performance.total_gain_loss_pct) >= 0
                      ? 'text-green-200'
                      : 'text-red-200'
                  } text-sm`}
                >
                  Performance
                </span>
                <Percent
                  className={`w-5 h-5 ${
                    Number(performance.total_gain_loss_pct) >= 0
                      ? 'text-green-400'
                      : 'text-red-400'
                  }`}
                />
              </div>
              <div className="text-2xl font-bold text-white">
                {formatPercent(performance.total_gain_loss_pct)}
              </div>
            </div>
          </div>
        )}

        {/* Navigation Tabs */}
        <div className="bg-white/10 backdrop-blur-lg rounded-xl p-2 mb-6 border border-white/20 flex gap-2 overflow-x-auto">
          {['overview', 'positions', 'transactions', 'assets', 'allocation', 'geography'].map((tab) => (
            <button
              key={tab}
              onClick={() => setActiveTab(tab)}
              className={`px-6 py-2 rounded-lg transition-all whitespace-nowrap ${
                activeTab === tab
                  ? 'bg-blue-500 text-white shadow-lg'
                  : 'text-blue-200 hover:bg-white/10'
              }`}
            >
              {tab === 'overview' && 'Panoramica'}
              {tab === 'positions' && 'Posizioni'}
              {tab === 'transactions' && 'Transazioni'}
              {tab === 'assets' && 'Asset'}
              {tab === 'allocation' && 'Allocazione'}
              {tab === 'geography' && 'Geografia'}
            </button>
          ))}
        </div>

        {/* Overview Tab */}
        {activeTab === 'overview' && (
          <div className="space-y-6">
            {snapshots.length > 0 && (
              <div className="bg-white/10 backdrop-blur-lg rounded-2xl p-6 border border-white/20">
                <h2 className="text-xl font-bold text-white mb-4">
                  Andamento Storico
                </h2>
                <ResponsiveContainer width="100%" height={300}>
                  <LineChart data={snapshots.slice().reverse()}>
                    <CartesianGrid strokeDasharray="3 3" stroke="#ffffff20" />
                    <XAxis dataKey="snapshot_date" stroke="#94a3b8" />
                    <YAxis
                      stroke="#94a3b8"
                      tickFormatter={(value) => `€${(value / 1000).toFixed(0)}k`}
                    />
                    <Tooltip
                      contentStyle={{
                        backgroundColor: '#1e293b',
                        border: '1px solid #475569',
                        borderRadius: '8px',
                      }}
                      formatter={(value: any) => formatCurrency(value)}
                    />
                    <Legend />
                    <Line
                      type="monotone"
                      dataKey="total_value"
                      stroke="#3b82f6"
                      strokeWidth={3}
                      name="Valore"
                    />
                    <Line
                      type="monotone"
                      dataKey="total_invested"
                      stroke="#8b5cf6"
                      strokeWidth={2}
                      name="Investito"
                      strokeDasharray="5 5"
                    />
                  </LineChart>
                </ResponsiveContainer>
              </div>
            )}

            {allocation.length > 0 && (
              <div className="bg-white/10 backdrop-blur-lg rounded-2xl p-6 border border-white/20">
                <h2 className="text-xl font-bold text-white mb-4">
                  Allocazione Asset
                </h2>
                <ResponsiveContainer width="100%" height={300}>
                  <PieChart>
                    <Pie
                      data={allocation.map(a => ({
                        ...a,
                        total_value: parseFloat(String(a.total_value)),
                        percentage: parseFloat(String(a.percentage))
                      }))}
                      dataKey="total_value"
                      nameKey="asset_type"
                      cx="50%"
                      cy="50%"
                      label={({ asset_type, percentage }: any) =>
                        `${asset_type} ${parseFloat(percentage).toFixed(1)}%`
                      }
                      outerRadius={100}
                    >
                      {allocation.map((entry, index) => (
                        <Cell
                          key={`cell-${index}`}
                          fill={getColorByIndex(index)}
                        />
                      ))}
                    </Pie>
                    <Tooltip formatter={(value: any) => formatCurrency(value)} />
                  </PieChart>
                </ResponsiveContainer>
              </div>
            )}

            {/* Monthly Performance Chart */}
            {selectedPortfolio && positions.length > 0 && (
              <MonthlyPerformanceChart portfolioId={selectedPortfolio.portfolio_id} />
            )}

            {snapshots.length === 0 && allocation.length === 0 && (
              <div className="bg-white/10 backdrop-blur-lg rounded-2xl p-12 border border-white/20 text-center">
                <p className="text-blue-200 text-lg">
                  Nessun dato disponibile per la panoramica. Aggiungi transazioni per vedere i grafici.
                </p>
              </div>
            )}
          </div>
        )}

        {/* Positions Tab */}
        {activeTab === 'positions' && (
          <div className="bg-white/10 backdrop-blur-lg rounded-2xl border border-white/20 overflow-hidden">
            <div className="p-6 border-b border-white/20 space-y-4">
              <div className="flex justify-between items-center">
                <h2 className="text-xl font-bold text-white">
                  Posizioni Correnti ({filteredPositions.length})
                </h2>
                <Button
                  variant="success"
                  icon={Plus}
                  onClick={() => setShowModal('transaction')}
                >
                  Nuova Transazione
                </Button>
              </div>

              {/* Filtri */}
              <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
                <input
                  type="text"
                  placeholder="Cerca per nome asset o ISIN..."
                  value={positionFilter}
                  onChange={(e) => setPositionFilter(e.target.value)}
                  className="px-4 py-2 bg-white/10 border border-white/20 rounded-lg text-white placeholder-blue-300 focus:outline-none focus:ring-2 focus:ring-blue-500"
                />
                <select
                  value={positionTypeFilter}
                  onChange={(e) => setPositionTypeFilter(e.target.value)}
                  className="px-4 py-2 bg-white/10 border border-white/20 rounded-lg text-white focus:outline-none focus:ring-2 focus:ring-blue-500"
                >
                  <option value="">Tutti i tipi</option>
                  <option value="Azionario">Azionario</option>
                  <option value="Obbligazionario">Obbligazionario</option>
                  <option value="Monetario">Monetario</option>
                  <option value="Oro">Oro</option>
                  <option value="Crypto">Crypto</option>
                  <option value="ETF">ETF</option>
                </select>
              </div>

              {/* Totali */}
              <div className="grid grid-cols-3 gap-4">
                <div className="bg-white/5 rounded-lg p-4">
                  <div className="text-xs text-blue-300 mb-1">Totale Investito</div>
                  <div className="text-lg font-bold text-purple-300">{formatCurrency(positionTotals.invested)}</div>
                </div>
                <div className="bg-white/5 rounded-lg p-4">
                  <div className="text-xs text-blue-300 mb-1">Valore Attuale</div>
                  <div className="text-lg font-bold text-white">{formatCurrency(positionTotals.value)}</div>
                </div>
                <div className="bg-white/5 rounded-lg p-4">
                  <div className="text-xs text-blue-300 mb-1">Guadagno/Perdita</div>
                  <div className={`text-lg font-bold ${positionTotals.gainLoss >= 0 ? 'text-green-400' : 'text-red-400'}`}>
                    {formatCurrency(positionTotals.gainLoss)} ({formatPercent((positionTotals.gainLoss / positionTotals.invested) * 100)})
                  </div>
                </div>
              </div>
            </div>
            <div className="overflow-x-auto">
              <table className="w-full">
                <thead className="bg-white/5">
                  <tr>
                    <th
                      className="px-6 py-3 text-left text-xs font-medium text-blue-200 uppercase cursor-pointer hover:text-white"
                      onClick={() => toggleSort('position', 'asset_name')}
                    >
                      Asset {positionSort.field === 'asset_name' && (positionSort.direction === 'asc' ? '▲' : '▼')}
                    </th>
                    <th
                      className="px-6 py-3 text-left text-xs font-medium text-blue-200 uppercase cursor-pointer hover:text-white"
                      onClick={() => toggleSort('position', 'asset_type')}
                    >
                      Tipo {positionSort.field === 'asset_type' && (positionSort.direction === 'asc' ? '▲' : '▼')}
                    </th>
                    <th
                      className="px-6 py-3 text-right text-xs font-medium text-blue-200 uppercase cursor-pointer hover:text-white"
                      onClick={() => toggleSort('position', 'quantity')}
                    >
                      Quantità {positionSort.field === 'quantity' && (positionSort.direction === 'asc' ? '▲' : '▼')}
                    </th>
                    <th
                      className="px-6 py-3 text-right text-xs font-medium text-blue-200 uppercase cursor-pointer hover:text-white"
                      onClick={() => toggleSort('position', 'average_buy_price')}
                    >
                      Prezzo Medio {positionSort.field === 'average_buy_price' && (positionSort.direction === 'asc' ? '▲' : '▼')}
                    </th>
                    <th
                      className="px-6 py-3 text-right text-xs font-medium text-blue-200 uppercase cursor-pointer hover:text-white"
                      onClick={() => toggleSort('position', 'total_invested')}
                    >
                      Investito {positionSort.field === 'total_invested' && (positionSort.direction === 'asc' ? '▲' : '▼')}
                    </th>
                    <th
                      className="px-6 py-3 text-right text-xs font-medium text-blue-200 uppercase cursor-pointer hover:text-white"
                      onClick={() => toggleSort('position', 'invested_pct')}
                    >
                      % Investita {positionSort.field === 'invested_pct' && (positionSort.direction === 'asc' ? '▲' : '▼')}
                    </th>
                    <th
                      className="px-6 py-3 text-right text-xs font-medium text-blue-200 uppercase cursor-pointer hover:text-white"
                      onClick={() => toggleSort('position', 'current_price')}
                    >
                      Prezzo Attuale {positionSort.field === 'current_price' && (positionSort.direction === 'asc' ? '▲' : '▼')}
                    </th>
                    <th
                      className="px-6 py-3 text-right text-xs font-medium text-blue-200 uppercase cursor-pointer hover:text-white"
                      onClick={() => toggleSort('position', 'current_value')}
                    >
                      Valore Attuale {positionSort.field === 'current_value' && (positionSort.direction === 'asc' ? '▲' : '▼')}
                    </th>
                    <th
                      className="px-6 py-3 text-right text-xs font-medium text-blue-200 uppercase cursor-pointer hover:text-white"
                      onClick={() => toggleSort('position', 'ownership_pct')}
                    >
                      % Possesso {positionSort.field === 'ownership_pct' && (positionSort.direction === 'asc' ? '▲' : '▼')}
                    </th>
                    <th
                      className="px-6 py-3 text-right text-xs font-medium text-blue-200 uppercase cursor-pointer hover:text-white"
                      onClick={() => toggleSort('position', 'gain_loss')}
                    >
                      G/P {positionSort.field === 'gain_loss' && (positionSort.direction === 'asc' ? '▲' : '▼')}
                    </th>
                    <th
                      className="px-6 py-3 text-right text-xs font-medium text-blue-200 uppercase cursor-pointer hover:text-white"
                      onClick={() => toggleSort('position', 'gain_loss_pct')}
                    >
                      G/P % {positionSort.field === 'gain_loss_pct' && (positionSort.direction === 'asc' ? '▲' : '▼')}
                    </th>
                  </tr>
                </thead>
                <tbody className="divide-y divide-white/10">
                  {filteredPositions.map((pos) => (
                    <tr
                      key={pos.position_id}
                      className="hover:bg-white/5 transition-colors"
                    >
                      <td className="px-6 py-4">
                        <div className="text-sm font-medium text-white">
                          {pos.asset_name}
                        </div>
                        <div className="text-xs text-blue-300">{pos.isin}</div>
                      </td>
                      <td className="px-6 py-4">
                        <span className={`px-3 py-1 rounded-full text-xs font-medium ${getAssetTypeColor(pos.asset_type)}`}>
                          {pos.asset_type}
                        </span>
                      </td>
                      <td className="px-6 py-4 text-right text-white">
                        {parseFloat(String(pos.quantity)).toFixed(2)}
                      </td>
                      <td className="px-6 py-4 text-right text-white">
                        {formatCurrency(pos.average_buy_price)}
                      </td>
                      <td className="px-6 py-4 text-right text-purple-300 font-medium">
                        {formatCurrency(pos.total_invested)}
                      </td>
                      <td className="px-6 py-4 text-right text-purple-200">
                        {pos.invested_pct ? formatPercent(pos.invested_pct) : '-'}
                      </td>
                      <td className="px-6 py-4 text-right text-white font-medium">
                        {formatCurrency(pos.current_price)}
                      </td>
                      <td className="px-6 py-4 text-right text-white font-bold">
                        {formatCurrency(pos.current_value)}
                      </td>
                      <td className="px-6 py-4 text-right text-blue-200">
                        {pos.ownership_pct ? formatPercent(pos.ownership_pct) : '-'}
                      </td>
                      <td
                        className={`px-6 py-4 text-right font-medium ${
                          Number(pos.gain_loss) >= 0 ? 'text-green-400' : 'text-red-400'
                        }`}
                      >
                        {formatCurrency(pos.gain_loss)}
                      </td>
                      <td
                        className={`px-6 py-4 text-right font-bold ${
                          Number(pos.gain_loss_pct) >= 0
                            ? 'text-green-400'
                            : 'text-red-400'
                        }`}
                      >
                        {formatPercent(pos.gain_loss_pct)}
                      </td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
          </div>
        )}

        {/* Transactions Tab */}
        {activeTab === 'transactions' && (
          <div className="bg-white/10 backdrop-blur-lg rounded-2xl border border-white/20 overflow-hidden">
            <div className="p-6 border-b border-white/20 space-y-4">
              <div className="flex justify-between items-center">
                <h2 className="text-xl font-bold text-white">
                  Transazioni ({filteredTransactions.length})
                </h2>
                <div className="flex gap-3">
                  <Button
                    variant="warning"
                    icon={Upload}
                    onClick={() => setShowModal('import')}
                  >
                    Importa Excel
                  </Button>
                  <Button
                    variant="success"
                    icon={Plus}
                    onClick={() => setShowModal('transaction')}
                  >
                    Nuova Transazione
                  </Button>
                </div>
              </div>

              {/* Filtri */}
              <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
                <input
                  type="text"
                  placeholder="Cerca per asset o ISIN..."
                  value={transactionFilter}
                  onChange={(e) => setTransactionFilter(e.target.value)}
                  className="px-4 py-2 bg-white/10 border border-white/20 rounded-lg text-white placeholder-blue-300 focus:outline-none focus:ring-2 focus:ring-blue-500"
                />
                <select
                  value={transactionTypeFilter}
                  onChange={(e) => setTransactionTypeFilter(e.target.value)}
                  className="px-4 py-2 bg-white/10 border border-white/20 rounded-lg text-white focus:outline-none focus:ring-2 focus:ring-blue-500 [&>option]:bg-slate-800 [&>option]:text-white"
                >
                  <option value="">Tutti i tipi</option>
                  <option value="BUY">BUY</option>
                  <option value="SELL">SELL</option>
                </select>
              </div>

              {/* Totali */}
              <div className="grid grid-cols-4 gap-4">
                <div className="bg-white/5 rounded-lg p-4">
                  <div className="text-xs text-blue-300 mb-1">Acquisti Totali</div>
                  <div className="text-lg font-bold text-green-400">{formatCurrency(transactionTotals.buy)}</div>
                </div>
                <div className="bg-white/5 rounded-lg p-4">
                  <div className="text-xs text-blue-300 mb-1">Vendite Totali</div>
                  <div className="text-lg font-bold text-red-400">{formatCurrency(transactionTotals.sell)}</div>
                </div>
                <div className="bg-white/5 rounded-lg p-4">
                  <div className="text-xs text-blue-300 mb-1">Commissioni</div>
                  <div className="text-lg font-bold text-orange-400">{formatCurrency(transactionTotals.commission)}</div>
                </div>
                <div className="bg-white/5 rounded-lg p-4">
                  <div className="text-xs text-blue-300 mb-1">Costi</div>
                  <div className="text-lg font-bold text-yellow-400">{formatCurrency(transactionTotals.fees)}</div>
                </div>
              </div>
            </div>
            <div className="overflow-x-auto">
              <table className="w-full">
                <thead className="bg-white/5">
                  <tr>
                    <th
                      className="px-6 py-3 text-left text-xs font-medium text-blue-200 uppercase cursor-pointer hover:text-white"
                      onClick={() => toggleSort('transaction', 'transaction_date')}
                    >
                      Data {transactionSort.field === 'transaction_date' && (transactionSort.direction === 'asc' ? '▲' : '▼')}
                    </th>
                    <th
                      className="px-6 py-3 text-left text-xs font-medium text-blue-200 uppercase cursor-pointer hover:text-white"
                      onClick={() => toggleSort('transaction', 'transaction_type')}
                    >
                      Tipo {transactionSort.field === 'transaction_type' && (transactionSort.direction === 'asc' ? '▲' : '▼')}
                    </th>
                    <th
                      className="px-6 py-3 text-left text-xs font-medium text-blue-200 uppercase cursor-pointer hover:text-white"
                      onClick={() => toggleSort('transaction', 'asset_name')}
                    >
                      Asset {transactionSort.field === 'asset_name' && (transactionSort.direction === 'asc' ? '▲' : '▼')}
                    </th>
                    <th
                      className="px-6 py-3 text-left text-xs font-medium text-blue-200 uppercase cursor-pointer hover:text-white"
                      onClick={() => toggleSort('transaction', 'isin')}
                    >
                      ISIN {transactionSort.field === 'isin' && (transactionSort.direction === 'asc' ? '▲' : '▼')}
                    </th>
                    <th
                      className="px-6 py-3 text-right text-xs font-medium text-blue-200 uppercase cursor-pointer hover:text-white"
                      onClick={() => toggleSort('transaction', 'quantity')}
                    >
                      Quantità {transactionSort.field === 'quantity' && (transactionSort.direction === 'asc' ? '▲' : '▼')}
                    </th>
                    <th
                      className="px-6 py-3 text-right text-xs font-medium text-blue-200 uppercase cursor-pointer hover:text-white"
                      onClick={() => toggleSort('transaction', 'price_per_share')}
                    >
                      Prezzo {transactionSort.field === 'price_per_share' && (transactionSort.direction === 'asc' ? '▲' : '▼')}
                    </th>
                    <th
                      className="px-6 py-3 text-right text-xs font-medium text-blue-200 uppercase cursor-pointer hover:text-white"
                      onClick={() => toggleSort('transaction', 'total_amount')}
                    >
                      Totale {transactionSort.field === 'total_amount' && (transactionSort.direction === 'asc' ? '▲' : '▼')}
                    </th>
                    <th className="px-6 py-3 text-center text-xs font-medium text-blue-200 uppercase">
                      Azioni
                    </th>
                  </tr>
                </thead>
                <tbody className="divide-y divide-white/10">
                  {filteredTransactions.map((tx) => (
                    <tr
                      key={tx.transaction_id}
                      className="hover:bg-white/5 transition-colors"
                    >
                      <td className="px-6 py-4 text-white">
                        {formatDate(tx.transaction_date)}
                      </td>
                      <td className="px-6 py-4">
                        <span
                          className={`px-3 py-1 rounded-full text-xs font-medium ${
                            tx.transaction_type === 'BUY'
                              ? 'bg-green-500/20 text-green-300'
                              : 'bg-red-500/20 text-red-300'
                          }`}
                        >
                          {tx.transaction_type}
                        </span>
                      </td>
                      <td className="px-6 py-4">
                        <div className="text-sm font-medium text-white">
                          {tx.asset_name}
                        </div>
                      </td>
                      <td className="px-6 py-4 text-white font-mono text-sm">
                        {tx.isin || '-'}
                      </td>
                      <td className="px-6 py-4 text-right text-white">
                        {parseFloat(String(tx.quantity)).toFixed(2)}
                      </td>
                      <td className="px-6 py-4 text-right text-white">
                        {formatCurrency(tx.price_per_share)}
                      </td>
                      <td className="px-6 py-4 text-right text-white font-bold">
                        {formatCurrency(tx.total_amount)}
                      </td>
                      <td className="px-6 py-4">
                        <div className="flex items-center justify-center gap-2">
                          <button
                            onClick={() => handleEditTransaction(tx)}
                            className="p-2 hover:bg-blue-500/20 rounded-lg transition-colors"
                            title="Modifica transazione"
                          >
                            <Edit2 className="w-4 h-4 text-blue-400" />
                          </button>
                          <button
                            onClick={() => handleDeleteTransaction(tx)}
                            className="p-2 hover:bg-red-500/20 rounded-lg transition-colors"
                            title="Elimina transazione"
                          >
                            <Trash2 className="w-4 h-4 text-red-400" />
                          </button>
                        </div>
                      </td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
          </div>
        )}

        {/* Assets Tab */}
        {activeTab === 'assets' && (
          <div className="space-y-6">
            <div className="flex justify-end mb-4">
              <Button
                variant="success"
                icon={Plus}
                onClick={() => {
                  setEditingAsset(null);
                  setShowModal('asset');
                }}
              >
                Nuovo Asset
              </Button>
            </div>
            <AssetsList
              assets={assets}
              onEdit={handleEditAsset}
              onDelete={handleDeleteAsset}
            />
          </div>
        )}

        {/* Allocation Tab */}
        {activeTab === 'allocation' && allocation.length > 0 && (
          <div className="space-y-6">
            <div className="bg-white/10 backdrop-blur-lg rounded-2xl p-6 border border-white/20">
              <div className="flex justify-between items-center mb-6">
                <h2 className="text-xl font-bold text-white">
                  Allocazione Dettagliata
                </h2>
              </div>

              <div className="space-y-4">
                {allocation.map((item, idx) => {
                  const currentPct = parseFloat(String(item.percentage));

                  return (
                    <div key={idx} className="bg-white/5 rounded-lg p-4">
                      <div className="flex justify-between items-center mb-2">
                        <div className="flex items-center gap-3">
                          <span className="text-white font-medium">
                            {item.asset_type}
                          </span>
                          <span className="text-blue-300 font-bold">
                            {currentPct.toFixed(2)}%
                          </span>
                        </div>
                        <span className="text-blue-200">
                          {formatCurrency(item.total_value)}
                        </span>
                      </div>
                      <div className="relative w-full bg-white/20 rounded-full h-3">
                        <div
                          className="h-3 rounded-full transition-all"
                          style={{
                            width: `${currentPct}%`,
                            backgroundColor: getColorByIndex(idx),
                          }}
                        />
                      </div>
                    </div>
                  );
                })}
              </div>
            </div>
          </div>
        )}

        {/* Geography Tab */}
        {activeTab === 'geography' && geoAllocation.length > 0 && (
          <div className="space-y-6">
            <div className="bg-white/10 backdrop-blur-lg rounded-2xl p-6 border border-white/20">
              <h2 className="text-xl font-bold text-white mb-6">
                Distribuzione Geografica
              </h2>
              <ResponsiveContainer width="100%" height={400}>
                <BarChart data={geoAllocation.slice(0, 10)} layout="vertical">
                  <CartesianGrid strokeDasharray="3 3" stroke="#ffffff20" />
                  <XAxis
                    type="number"
                    stroke="#94a3b8"
                    tickFormatter={(value) => `€${(value / 1000).toFixed(0)}k`}
                  />
                  <YAxis
                    dataKey="name"
                    type="category"
                    stroke="#94a3b8"
                    width={100}
                  />
                  <Tooltip
                    contentStyle={{
                      backgroundColor: '#1e293b',
                      border: '1px solid #475569',
                      borderRadius: '8px',
                    }}
                    formatter={(value: any) => formatCurrency(value)}
                  />
                  <Bar dataKey="value" fill="#3b82f6" radius={[0, 8, 8, 0]} />
                </BarChart>
              </ResponsiveContainer>
            </div>

            <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
              {geoAllocation.slice(0, 8).map((geo, idx) => {
                const totalValue = geoAllocation.reduce(
                  (sum, g) => sum + g.value,
                  0
                );
                const pct = ((geo.value / totalValue) * 100).toFixed(1);
                return (
                  <div
                    key={idx}
                    className="bg-white/10 backdrop-blur-lg rounded-xl p-4 border border-white/20"
                  >
                    <div className="flex justify-between items-center mb-2">
                      <span className="text-white font-medium">{geo.name}</span>
                      <span className="text-blue-300 font-bold">{pct}%</span>
                    </div>
                    <div className="text-lg font-bold text-white mb-2">
                      {formatCurrency(geo.value)}
                    </div>
                    <div className="w-full bg-white/20 rounded-full h-2">
                      <div
                        className="h-2 rounded-full"
                        style={{
                          width: `${pct}%`,
                          backgroundColor: getColorByIndex(idx),
                        }}
                      />
                    </div>
                  </div>
                );
              })}
            </div>
          </div>
        )}

        {/* MODALS */}
        {showModal === 'portfolio' && (
          <PortfolioFormModal
            onClose={() => setShowModal(null)}
            onSuccess={loadPortfolios}
          />
        )}

        {showModal === 'asset' && (
          <AssetFormModal
            asset={editingAsset}
            onClose={handleCloseAssetModal}
            onSuccess={loadAssets}
          />
        )}

        {showModal === 'transaction' && selectedPortfolio && (
          <TransactionFormModal
            portfolioId={selectedPortfolio.portfolio_id}
            assets={assets}
            transaction={editingTransaction}
            onClose={handleCloseTransactionModal}
            onSuccess={refreshData}
          />
        )}

        {showModal === 'import' && selectedPortfolio && (
          <ImportExcelModal
            portfolioId={selectedPortfolio.portfolio_id}
            onClose={() => setShowModal(null)}
            onSuccess={refreshData}
          />
        )}
      </div>
    </div>
  );
}
