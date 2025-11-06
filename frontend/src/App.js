import React, { useState, useEffect } from 'react';
import { LineChart, Line, PieChart, Pie, Cell, BarChart, Bar, XAxis, YAxis, CartesianGrid, Tooltip, Legend, ResponsiveContainer } from 'recharts';
import { TrendingUp, TrendingDown, RefreshCw, Download, Plus, Search, Edit2, Trash2, Save, X, Upload, FileSpreadsheet, DollarSign, Percent, Calendar } from 'lucide-react';

const API_URL = 'http://localhost:3001/api';

// ============================================
// MODAL COMPONENT (SPOSTATO QUI)
// ============================================
const Modal = ({ title, onClose, children }) => (
  <div className="fixed inset-0 bg-black/60 backdrop-blur-sm flex items-center justify-center z-50 p-4">
    <div className="bg-slate-800 rounded-2xl max-w-2xl w-full max-h-[90vh] overflow-y-auto border border-white/20">
      <div className="p-6 border-b border-white/10 flex justify-between items-center sticky top-0 bg-slate-800 z-10">
        <h2 className="text-2xl font-bold text-white">{title}</h2>
        <button onClick={onClose} className="p-2 hover:bg-white/10 rounded-lg transition-colors">
          <X className="w-6 h-6 text-white" />
        </button>
      </div>
      <div className="p-6">
        {children}
      </div>
    </div>
  </div>
);

const PortfolioApp = () => {
  const [portfolios, setPortfolios] = useState([]);
  const [selectedPortfolio, setSelectedPortfolio] = useState(null);
  const [positions, setPositions] = useState([]);
  const [transactions, setTransactions] = useState([]);
  const [assets, setAssets] = useState([]);
  const [performance, setPerformance] = useState(null);
  const [allocation, setAllocation] = useState([]);
  const [snapshots, setSnapshots] = useState([]);
  const [geoAllocation, setGeoAllocation] = useState([]);
  const [targetAllocation, setTargetAllocation] = useState(null);
  
  const [activeTab, setActiveTab] = useState('overview');
  const [showModal, setShowModal] = useState(null);
  const [loading, setLoading] = useState(false);
  const [editingItem, setEditingItem] = useState(null);

  // Nuovo stato per simulazione liquidità
  const [newCapital, setNewCapital] = useState(0);
  const [allocationMode, setAllocationMode] = useState('target'); // 'target' o 'manual'
  const [manualAllocation, setManualAllocation] = useState({});
  const [simulationResult, setSimulationResult] = useState(null);

  // Form states
  const [portfolioForm, setPortfolioForm] = useState({ name: '', broker: '', currency: 'EUR', notes: '' });
  const [assetForm, setAssetForm] = useState({ 
    isin: '', name: '', ticker: '', asset_type: 'Azionario', 
    sector: '', country: '', region: '', currency: 'EUR', ter: 0 
  });
  const [transactionForm, setTransactionForm] = useState({
    asset_id: '', transaction_type: 'BUY', transaction_date: new Date().toISOString().split('T')[0],
    quantity: 0, price_per_share: 0, commission: 0, fees: 0, notes: ''
  });
  const [targetForm, setTargetForm] = useState({
    target_azionario: 65,
    target_obbligazionario: 15,
    target_monetario: 8,
    target_oro: 12,
    target_crypto: 0
  });

  // Carica dati iniziali
  useEffect(() => {
    loadPortfolios();
    loadAssets();
  }, []);

  useEffect(() => {
    if (selectedPortfolio) {
      loadPortfolioData(selectedPortfolio.portfolio_id);
    }
  }, [selectedPortfolio]);

  // ============================================
  // API CALLS
  // ============================================

  const loadPortfolios = async () => {
    try {
      const response = await fetch(`${API_URL}/portfolios`);
      const data = await response.json();
      setPortfolios(data);
      if (data.length > 0 && !selectedPortfolio) {
        setSelectedPortfolio(data[0]);
      }
    } catch (err) {
      console.error('Errore caricamento portafogli:', err);
    }
  };

  const loadAssets = async () => {
    try {
      const response = await fetch(`${API_URL}/assets`);
      const data = await response.json();
      setAssets(data);
    } catch (err) {
      console.error('Errore caricamento asset:', err);
    }
  };

  const loadPortfolioData = async (portfolioId) => {
    setLoading(true);
    try {
      const [posRes, transRes, perfRes, allocRes, snapRes, targetRes] = await Promise.all([
        fetch(`${API_URL}/portfolios/${portfolioId}/positions`),
        fetch(`${API_URL}/portfolios/${portfolioId}/transactions?limit=100`),
        fetch(`${API_URL}/portfolios/${portfolioId}/performance`),
        fetch(`${API_URL}/portfolios/${portfolioId}/allocation`),
        fetch(`${API_URL}/portfolios/${portfolioId}/snapshots?days=365`),
        fetch(`${API_URL}/target-allocations/${portfolioId}`)
      ]);

      const posData = await posRes.json();
      setPositions(posData);
      setTransactions(await transRes.json());
      setPerformance(await perfRes.json());
      setAllocation(await allocRes.json());
      setSnapshots(await snapRes.json());
      
      // Carica target allocation
      if (targetRes.ok) {
        const targetData = await targetRes.json();
        setTargetAllocation(targetData);
        if (targetData) {
          setTargetForm({
            target_azionario: targetData.target_azionario || 0,
            target_obbligazionario: targetData.target_obbligazionario || 0,
            target_monetario: targetData.target_monetario || 0,
            target_oro: targetData.target_oro || 0,
            target_crypto: targetData.target_crypto || 0
          });
        }
      }

      // Calcola distribuzione geografica
      calculateGeoAllocation(posData);
    } catch (err) {
      console.error('Errore caricamento dati portafoglio:', err);
    }
    setLoading(false);
  };

  const calculateGeoAllocation = (positionsData) => {
    const geoMap = {};
    positionsData.forEach(pos => {
      const country = pos.country || 'Non specificato';
      if (!geoMap[country]) {
        geoMap[country] = 0;
      }
      geoMap[country] += parseFloat(pos.current_value || 0);
    });

    const geoArray = Object.entries(geoMap).map(([name, value]) => ({
      name,
      value
    })).sort((a, b) => b.value - a.value);

    setGeoAllocation(geoArray);
  };

  // ============================================
  // CRUD OPERATIONS
  // ============================================

  const createPortfolio = async (e) => {
    e.preventDefault();
    try {
      const response = await fetch(`${API_URL}/portfolios`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify(portfolioForm)
      });
      if (response.ok) {
        await loadPortfolios();
        setShowModal(null);
        setPortfolioForm({ name: '', broker: '', currency: 'EUR', notes: '' });
      }
    } catch (err) {
      console.error('Errore creazione portafoglio:', err);
    }
  };

  const createAsset = async (e) => {
    e.preventDefault();
    try {
      const response = await fetch(`${API_URL}/assets`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify(assetForm)
      });
      if (response.ok) {
        await loadAssets();
        setShowModal(null);
        setAssetForm({ 
          isin: '', name: '', ticker: '', asset_type: 'Azionario', 
          sector: '', country: '', region: '', currency: 'EUR', ter: 0 
        });
      }
    } catch (err) {
      console.error('Errore creazione asset:', err);
    }
  };

  const createTransaction = async (e) => {
    e.preventDefault();
    try {
      const response = await fetch(`${API_URL}/transactions`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          ...transactionForm,
          portfolio_id: selectedPortfolio.portfolio_id
        })
      });
      if (response.ok) {
        await loadPortfolioData(selectedPortfolio.portfolio_id);
        setShowModal(null);
        setTransactionForm({
          asset_id: '', transaction_type: 'BUY', transaction_date: new Date().toISOString().split('T')[0],
          quantity: 0, price_per_share: 0, commission: 0, fees: 0, notes: ''
        });
      }
    } catch (err) {
      console.error('Errore creazione transazione:', err);
    }
  };

  const updatePrices = async () => {
    if (!selectedPortfolio) return;
    setLoading(true);
    try {
      const response = await fetch(`${API_URL}/portfolios/${selectedPortfolio.portfolio_id}/update-prices`, {
        method: 'POST'
      });
      if (response.ok) {
        await loadPortfolioData(selectedPortfolio.portfolio_id);
      }
    } catch (err) {
      console.error('Errore aggiornamento prezzi:', err);
    }
    setLoading(false);
  };

  const exportToExcel = async () => {
    // Implementazione export Excel
    const data = {
      portfolios,
      positions,
      transactions,
      performance,
      allocation
    };
    
    // In produzione usare libreria come xlsx
    const jsonStr = JSON.stringify(data, null, 2);
    const blob = new Blob([jsonStr], { type: 'application/json' });
    const url = URL.createObjectURL(blob);
    const a = document.createElement('a');
    a.href = url;
    a.download = `portfolio_export_${new Date().toISOString().split('T')[0]}.json`;
    a.click();
  };

  const saveTargetAllocation = async (e) => {
    e.preventDefault();
    if (!selectedPortfolio) return;

    // Verifica che la somma sia 100
    const sum = Object.values(targetForm).reduce((a, b) => a + b, 0);
    if (Math.abs(sum - 100) > 0.01) {
      alert('La somma delle percentuali deve essere 100%');
      return;
    }

    try {
      const method = targetAllocation ? 'PUT' : 'POST';
      const url = targetAllocation 
        ? `${API_URL}/target-allocations/${targetAllocation.target_id}`
        : `${API_URL}/target-allocations`;

      const response = await fetch(url, {
        method,
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          portfolio_id: selectedPortfolio.portfolio_id,
          allocation_name: 'Target Standard',
          ...targetForm
        })
      });

      if (response.ok) {
        await loadPortfolioData(selectedPortfolio.portfolio_id);
        setShowModal(null);
      }
    } catch (err) {
      console.error('Errore salvataggio target:', err);
    }
  };

  const simulateAllocation = () => {
    if (!performance || newCapital <= 0) return;

    const currentTotal = parseFloat(performance.current_value || 0);
    const newTotal = currentTotal + newCapital;

    if (allocationMode === 'target') {
      // Allocazione basata su target
      const suggestions = {};
      const currentAlloc = {};

      // Calcola allocazione corrente
      allocation.forEach(item => {
        currentAlloc[item.asset_type] = parseFloat(item.total_value || 0);
      });

      // Calcola quanto investire per tipo per raggiungere i target
      Object.keys(targetForm).forEach(key => {
        const assetType = key.replace('target_', '').charAt(0).toUpperCase() + key.replace('target_', '').slice(1);
        const targetPct = targetForm[key] / 100;
        const targetValue = newTotal * targetPct;
        const currentValue = currentAlloc[assetType] || 0;
        const toInvest = targetValue - currentValue;

        suggestions[assetType] = {
          current: currentValue,
          target: targetValue,
          toInvest: Math.max(0, toInvest),
          currentPct: (currentValue / currentTotal * 100),
          targetPct: targetForm[key],
          newPct: (targetValue / newTotal * 100)
        };
      });

      setSimulationResult({
        mode: 'target',
        currentTotal,
        newTotal,
        newCapital,
        suggestions
      });
    } else {
      // Allocazione manuale
      const suggestions = {};
      let totalAllocated = 0;

      Object.entries(manualAllocation).forEach(([assetType, amount]) => {
        const amt = parseFloat(amount || 0);
        totalAllocated += amt;

        const currentValue = allocation.find(a => a.asset_type === assetType)?.total_value || 0;
        const newValue = parseFloat(currentValue) + amt;

        suggestions[assetType] = {
          current: parseFloat(currentValue),
          toInvest: amt,
          newValue: newValue,
          currentPct: (parseFloat(currentValue) / currentTotal * 100),
          newPct: (newValue / newTotal * 100)
        };
      });

      setSimulationResult({
        mode: 'manual',
        currentTotal,
        newTotal,
        newCapital,
        totalAllocated,
        remaining: newCapital - totalAllocated,
        suggestions
      });
    }

    setShowModal('simulation-result');
  };

  // ============================================
  // UTILITY FUNCTIONS
  // ============================================

  const formatCurrency = (value) => {
    return new Intl.NumberFormat('it-IT', { style: 'currency', currency: 'EUR' }).format(value || 0);
  };

  const formatPercent = (value) => {
    return `${value >= 0 ? '+' : ''}${(value || 0).toFixed(2)}%`;
  };

  const COLORS = ['#3b82f6', '#10b981', '#f59e0b', '#8b5cf6', '#ef4444', '#06b6d4'];

  // ============================================
  // MODALS (Definizione rimossa da qui)
  // ============================================

  return (
    <div className="min-h-screen bg-gradient-to-br from-slate-900 via-blue-900 to-slate-900 p-4">
      <div className="max-w-7xl mx-auto">
        
        {/* Header */}
        <div className="bg-white/10 backdrop-blur-lg rounded-2xl p-6 mb-6 border border-white/20 shadow-2xl">
          <div className="flex flex-col md:flex-row justify-between items-start md:items-center gap-4">
            <div>
              <h1 className="text-3xl font-bold text-white mb-2">Portfolio Tracker Pro</h1>
              <p className="text-blue-200">Gestione completa con database PostgreSQL</p>
            </div>
            <div className="flex gap-3 flex-wrap">
              <button 
                onClick={() => setShowModal('portfolio')}
                className="px-4 py-2 bg-green-500 hover:bg-green-600 text-white rounded-lg flex items-center gap-2 transition-all"
              >
                <Plus className="w-4 h-4" />
                Nuovo Portafoglio
              </button>
              <button 
                onClick={() => setShowModal('asset')}
                className="px-4 py-2 bg-purple-500 hover:bg-purple-600 text-white rounded-lg flex items-center gap-2 transition-all"
              >
                <Plus className="w-4 h-4" />
                Nuovo Asset
              </button>
              <button 
                onClick={exportToExcel}
                className="px-4 py-2 bg-blue-500 hover:bg-blue-600 text-white rounded-lg flex items-center gap-2 transition-all"
              >
                <Download className="w-4 h-4" />
                Export
              </button>
              <button 
                onClick={updatePrices}
                disabled={loading}
                className="px-4 py-2 bg-orange-500 hover:bg-orange-600 text-white rounded-lg flex items-center gap-2 transition-all disabled:opacity-50"
              >
                <RefreshCw className={`w-4 h-4 ${loading ? 'animate-spin' : ''}`} />
                Aggiorna Prezzi
              </button>
            </div>
          </div>

          {portfolios.length > 0 && (
            <div className="mt-4 flex gap-2 overflow-x-auto pb-2">
              {portfolios.map(p => (
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
              <div className="text-2xl font-bold text-white">{formatCurrency(performance.current_value)}</div>
            </div>

            <div className="bg-gradient-to-br from-purple-500/20 to-purple-600/20 backdrop-blur-lg rounded-xl p-6 border border-purple-400/30">
              <div className="flex items-center justify-between mb-2">
                <span className="text-purple-200 text-sm">Investito</span>
                <DollarSign className="w-5 h-5 text-purple-400" />
              </div>
              <div className="text-2xl font-bold text-white">{formatCurrency(performance.total_invested)}</div>
            </div>

            <div className={`bg-gradient-to-br ${performance.total_gain_loss >= 0 ? 'from-green-500/20 to-green-600/20' : 'from-red-500/20 to-red-600/20'} backdrop-blur-lg rounded-xl p-6 border ${performance.total_gain_loss >= 0 ? 'border-green-400/30' : 'border-red-400/30'}`}>
              <div className="flex items-center justify-between mb-2">
                <span className={`${performance.total_gain_loss >= 0 ? 'text-green-200' : 'text-red-200'} text-sm`}>G/P</span>
                {performance.total_gain_loss >= 0 ? <TrendingUp className="w-5 h-5 text-green-400" /> : <TrendingDown className="w-5 h-5 text-red-400" />}
              </div>
              <div className="text-2xl font-bold text-white">{formatCurrency(performance.total_gain_loss)}</div>
            </div>

            <div className={`bg-gradient-to-br ${performance.total_gain_loss_pct >= 0 ? 'from-green-500/20 to-green-600/20' : 'from-red-500/20 to-red-600/20'} backdrop-blur-lg rounded-xl p-6 border ${performance.total_gain_loss_pct >= 0 ? 'border-green-400/30' : 'border-red-400/30'}`}>
              <div className="flex items-center justify-between mb-2">
                <span className={`${performance.total_gain_loss_pct >= 0 ? 'text-green-200' : 'text-red-200'} text-sm`}>Performance</span>
                <Percent className={`w-5 h-5 ${performance.total_gain_loss_pct >= 0 ? 'text-green-400' : 'text-red-400'}`} />
              </div>
              <div className="text-2xl font-bold text-white">{formatPercent(performance.total_gain_loss_pct)}</div>
            </div>
          </div>
        )}

        {/* Navigation Tabs */}
        <div className="bg-white/10 backdrop-blur-lg rounded-xl p-2 mb-6 border border-white/20 flex gap-2 overflow-x-auto">
          {['overview', 'positions', 'transactions', 'allocation', 'geography', 'rebalance'].map(tab => (
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
              {tab === 'allocation' && 'Allocazione'}
              {tab === 'geography' && 'Geografia'}
              {tab === 'rebalance' && 'Ribilanciamento'}
            </button>
          ))}
        </div>

        {/* Overview Tab */}
        {activeTab === 'overview' && snapshots.length > 0 && (
          <div className="space-y-6">
            <div className="bg-white/10 backdrop-blur-lg rounded-2xl p-6 border border-white/20">
              <h2 className="text-xl font-bold text-white mb-4">Andamento Storico</h2>
              <ResponsiveContainer width="100%" height={300}>
                <LineChart data={snapshots.slice().reverse()}>
                  <CartesianGrid strokeDasharray="3 3" stroke="#ffffff20" />
                  <XAxis dataKey="snapshot_date" stroke="#94a3b8" />
                  <YAxis stroke="#94a3b8" tickFormatter={(value) => `€${(value/1000).toFixed(0)}k`} />
                  <Tooltip 
                    contentStyle={{ backgroundColor: '#1e293b', border: '1px solid #475569', borderRadius: '8px' }}
                    formatter={(value) => formatCurrency(value)}
                  />
                  <Legend />
                  <Line type="monotone" dataKey="total_value" stroke="#3b82f6" strokeWidth={3} name="Valore" />
                  <Line type="monotone" dataKey="total_invested" stroke="#8b5cf6" strokeWidth={2} name="Investito" strokeDasharray="5 5" />
                </LineChart>
              </ResponsiveContainer>
            </div>

            {allocation.length > 0 && (
              <div className="bg-white/10 backdrop-blur-lg rounded-2xl p-6 border border-white/20">
                <h2 className="text-xl font-bold text-white mb-4">Allocazione Asset</h2>
                <ResponsiveContainer width="100%" height={300}>
                  <PieChart>
                    <Pie
                      data={allocation}
                      dataKey="total_value"
                      nameKey="asset_type"
                      cx="50%"
                      cy="50%"
                      label={({ asset_type, percentage }) => `${asset_type} ${parseFloat(percentage).toFixed(1)}%`}
                      outerRadius={100}
                    >
                      {allocation.map((entry, index) => (
                        <Cell key={`cell-${index}`} fill={COLORS[index % COLORS.length]} />
                      ))}
                    </Pie>
                    <Tooltip formatter={(value) => formatCurrency(value)} />
                  </PieChart>
                </ResponsiveContainer>
              </div>
            )}
          </div>
        )}

        {/* Positions Tab */}
        {activeTab === 'positions' && (
          <div className="bg-white/10 backdrop-blur-lg rounded-2xl border border-white/20 overflow-hidden">
            <div className="p-6 border-b border-white/20">
              <div className="flex justify-between items-center">
                <h2 className="text-xl font-bold text-white">Posizioni Correnti ({positions.length})</h2>
                <button 
                  onClick={() => setShowModal('transaction')}
                  className="px-4 py-2 bg-green-500 hover:bg-green-600 text-white rounded-lg flex items-center gap-2"
                >
                  <Plus className="w-4 h-4" />
                  Nuova Transazione
                </button>
              </div>
            </div>
            <div className="overflow-x-auto">
              <table className="w-full">
                <thead className="bg-white/5">
                  <tr>
                    <th className="px-6 py-3 text-left text-xs font-medium text-blue-200 uppercase">Asset</th>
                    <th className="px-6 py-3 text-right text-xs font-medium text-blue-200 uppercase">Quantità</th>
                    <th className="px-6 py-3 text-right text-xs font-medium text-blue-200 uppercase">Prezzo Medio</th>
                    <th className="px-6 py-3 text-right text-xs font-medium text-blue-200 uppercase">Prezzo Attuale</th>
                    <th className="px-6 py-3 text-right text-xs font-medium text-blue-200 uppercase">Valore</th>
                    <th className="px-6 py-3 text-right text-xs font-medium text-blue-200 uppercase">G/P</th>
                    <th className="px-6 py-3 text-right text-xs font-medium text-blue-200 uppercase">G/P %</th>
                  </tr>
                </thead>
                <tbody className="divide-y divide-white/10">
                  {positions.map(pos => (
                    <tr key={pos.position_id} className="hover:bg-white/5 transition-colors">
                      <td className="px-6 py-4">
                        <div className="text-sm font-medium text-white">{pos.asset_name}</div>
                        <div className="text-xs text-blue-300">{pos.isin}</div>
                      </td>
                      <td className="px-6 py-4 text-right text-white">{parseFloat(pos.quantity).toFixed(2)}</td>
                      <td className="px-6 py-4 text-right text-white">{formatCurrency(pos.average_buy_price)}</td>
                      <td className="px-6 py-4 text-right text-white font-medium">{formatCurrency(pos.current_price)}</td>
                      <td className="px-6 py-4 text-right text-white font-bold">{formatCurrency(pos.current_value)}</td>
                      <td className={`px-6 py-4 text-right font-medium ${pos.gain_loss >= 0 ? 'text-green-400' : 'text-red-400'}`}>
                        {formatCurrency(pos.gain_loss)}
                      </td>
                      <td className={`px-6 py-4 text-right font-bold ${pos.gain_loss_pct >= 0 ? 'text-green-400' : 'text-red-400'}`}>
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
            <div className="p-6 border-b border-white/20">
              <div className="flex justify-between items-center">
                <h2 className="text-xl font-bold text-white">Transazioni ({transactions.length})</h2>
                <button 
                  onClick={() => setShowModal('transaction')}
                  className="px-4 py-2 bg-green-500 hover:bg-green-600 text-white rounded-lg flex items-center gap-2"
                >
                  <Plus className="w-4 h-4" />
                  Nuova Transazione
                </button>
              </div>
            </div>
            <div className="overflow-x-auto">
              <table className="w-full">
                <thead className="bg-white/5">
                  <tr>
                    <th className="px-6 py-3 text-left text-xs font-medium text-blue-200 uppercase">Data</th>
                    <th className="px-6 py-3 text-left text-xs font-medium text-blue-200 uppercase">Tipo</th>
                    <th className="px-6 py-3 text-left text-xs font-medium text-blue-200 uppercase">Asset</th>
                    <th className="px-6 py-3 text-right text-xs font-medium text-blue-200 uppercase">Quantità</th>
                    <th className="px-6 py-3 text-right text-xs font-medium text-blue-200 uppercase">Prezzo</th>
                    <th className="px-6 py-3 text-right text-xs font-medium text-blue-200 uppercase">Totale</th>
                  </tr>
                </thead>
                <tbody className="divide-y divide-white/10">
                  {transactions.map(tx => (
                    <tr key={tx.transaction_id} className="hover:bg-white/5 transition-colors">
                      <td className="px-6 py-4 text-white">{new Date(tx.transaction_date).toLocaleDateString('it-IT')}</td>
                      <td className="px-6 py-4">
                        <span className={`px-3 py-1 rounded-full text-xs font-medium ${
                          tx.transaction_type === 'BUY' ? 'bg-green-500/20 text-green-300' : 'bg-red-500/20 text-red-300'
                        }`}>
                          {tx.transaction_type}
                        </span>
                      </td>
                      <td className="px-6 py-4 text-white">{tx.asset_name}</td>
                      <td className="px-6 py-4 text-right text-white">{parseFloat(tx.quantity).toFixed(2)}</td>
                      <td className="px-6 py-4 text-right text-white">{formatCurrency(tx.price_per_share)}</td>
                      <td className="px-6 py-4 text-right text-white font-bold">{formatCurrency(tx.total_amount)}</td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
          </div>
        )}

        {/* Allocation Tab */}
        {activeTab === 'allocation' && allocation.length > 0 && (
          <div className="space-y-6">
            <div className="bg-white/10 backdrop-blur-lg rounded-2xl p-6 border border-white/20">
              <div className="flex justify-between items-center mb-6">
                <h2 className="text-xl font-bold text-white">Allocazione Dettagliata</h2>
                <button
                  onClick={() => setShowModal('target')}
                  className="px-4 py-2 bg-purple-500 hover:bg-purple-600 text-white rounded-lg flex items-center gap-2"
                >
                  <Edit2 className="w-4 h-4" />
                  Imposta Target
                </button>
              </div>
              
              <div className="space-y-4">
                {allocation.map((item, idx) => {
                  const targetKey = `target_${item.asset_type.toLowerCase()}`;
                  const targetPct = targetForm[targetKey] || 0;
                  const currentPct = parseFloat(item.percentage);
                  const diff = currentPct - targetPct;
                  const isAligned = Math.abs(diff) < 1;

                  return (
                    <div key={idx} className="bg-white/5 rounded-lg p-4">
                      <div className="flex justify-between items-center mb-2">
                        <div className="flex items-center gap-3">
                          <span className="text-white font-medium">{item.asset_type}</span>
                          <span className="text-blue-300 font-bold">{currentPct.toFixed(2)}%</span>
                          {targetPct > 0 && (
                            <span className={`text-sm ${isAligned ? 'text-green-400' : 'text-yellow-400'}`}>
                              Target: {targetPct}% ({diff > 0 ? '+' : ''}{diff.toFixed(2)}%)
                            </span>
                          )}
                        </div>
                        <span className="text-blue-200">{formatCurrency(item.total_value)}</span>
                      </div>
                      <div className="relative w-full bg-white/20 rounded-full h-3">
                        <div 
                          className="h-3 rounded-full transition-all"
                          style={{ 
                            width: `${currentPct}%`,
                            backgroundColor: COLORS[idx % COLORS.length]
                          }}
                        />
                        {targetPct > 0 && (
                          <div
                            className="absolute top-0 h-3 w-0.5 bg-white"
                            style={{ left: `${targetPct}%` }}
                            title={`Target: ${targetPct}%`}
                          />
                        )}
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
              <h2 className="text-xl font-bold text-white mb-6">Distribuzione Geografica</h2>
              <ResponsiveContainer width="100%" height={400}>
                <BarChart data={geoAllocation.slice(0, 10)} layout="vertical">
                  <CartesianGrid strokeDasharray="3 3" stroke="#ffffff20" />
                  <XAxis type="number" stroke="#94a3b8" tickFormatter={(value) => `€${(value/1000).toFixed(0)}k`} />
                  <YAxis dataKey="name" type="category" stroke="#94a3b8" width={100} />
                  <Tooltip 
                    contentStyle={{ backgroundColor: '#1e293b', border: '1px solid #475569', borderRadius: '8px' }}
                    formatter={(value) => formatCurrency(value)}
                  />
                  <Bar dataKey="value" fill="#3b82f6" radius={[0, 8, 8, 0]} />
                </BarChart>
              </ResponsiveContainer>
            </div>

            <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
              {geoAllocation.slice(0, 8).map((geo, idx) => {
                const totalValue = geoAllocation.reduce((sum, g) => sum + g.value, 0);
                const pct = (geo.value / totalValue * 100).toFixed(1);
                return (
                  <div key={idx} className="bg-white/10 backdrop-blur-lg rounded-xl p-4 border border-white/20">
                    <div className="flex justify-between items-center mb-2">
                      <span className="text-white font-medium">{geo.name}</span>
                      <span className="text-blue-300 font-bold">{pct}%</span>
                    </div>
                    <div className="text-lg font-bold text-white mb-2">{formatCurrency(geo.value)}</div>
                    <div className="w-full bg-white/20 rounded-full h-2">
                      <div 
                        className="h-2 rounded-full"
                        style={{ 
                          width: `${pct}%`,
                          backgroundColor: COLORS[idx % COLORS.length]
                        }}
                      />
                    </div>
                  </div>
                );
              })}
            </div>
          </div>
        )}

        {/* Rebalance Tab */}
        {activeTab === 'rebalance' && (
          <div className="space-y-6">
            <div className="bg-white/10 backdrop-blur-lg rounded-2xl p-6 border border-white/20">
              <h2 className="text-2xl font-bold text-white mb-6">💰 Simulatore Allocazione Nuova Liquidità</h2>
              
              <div className="grid grid-cols-1 md:grid-cols-2 gap-6 mb-6">
                <div>
                  <label className="block text-sm font-medium text-blue-200 mb-2">Nuova Liquidità da Investire</label>
                  <input
                    type="number"
                    value={newCapital}
                    onChange={(e) => setNewCapital(parseFloat(e.target.value) || 0)}
                    className="w-full px-4 py-3 bg-white/10 border border-white/20 rounded-lg text-white text-xl font-bold focus:outline-none focus:ring-2 focus:ring-blue-500"
                    placeholder="0.00"
                    step="100"
                  />
                </div>

                <div>
                  <label className="block text-sm font-medium text-blue-200 mb-2">Modalità Allocazione</label>
                  <div className="flex gap-3">
                    <button
                      onClick={() => setAllocationMode('target')}
                      className={`flex-1 px-4 py-3 rounded-lg transition-all ${
                        allocationMode === 'target'
                          ? 'bg-blue-500 text-white'
                          : 'bg-white/10 text-blue-200 hover:bg-white/20'
                      }`}
                    >
                      Segui Target
                    </button>
                    <button
                      onClick={() => setAllocationMode('manual')}
                      className={`flex-1 px-4 py-3 rounded-lg transition-all ${
                        allocationMode === 'manual'
                          ? 'bg-purple-500 text-white'
                          : 'bg-white/10 text-blue-200 hover:bg-white/20'
                      }`}
                    >
                      Manuale
                    </button>
                  </div>
                </div>
              </div>

              {allocationMode === 'manual' && (
                <div className="bg-white/5 rounded-lg p-4 mb-6">
                  <h3 className="text-white font-medium mb-4">Allocazione Manuale per Tipo Asset</h3>
                  <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
                    {allocation.map(item => (
                      <div key={item.asset_type}>
                        <label className="block text-sm text-blue-200 mb-2">{item.asset_type}</label>
                        <input
                          type="number"
                          value={manualAllocation[item.asset_type] || 0}
                          onChange={(e) => setManualAllocation({
                            ...manualAllocation,
                            [item.asset_type]: parseFloat(e.target.value) || 0
                          })}
                          className="w-full px-3 py-2 bg-white/10 border border-white/20 rounded-lg text-white focus:outline-none focus:ring-2 focus:ring-purple-500"
                          placeholder="0.00"
                          step="10"
                        />
                      </div>
                    ))}
                  </div>
                  {allocationMode === 'manual' && (
                    <div className="mt-4 flex justify-between text-sm">
                      <span className="text-blue-200">Totale allocato:</span>
                      <span className="text-white font-bold">
                        {formatCurrency(Object.values(manualAllocation).reduce((sum, val) => sum + (parseFloat(val) || 0), 0))}
                      </span>
                    </div>
                  )}
                </div>
              )}

              <button
                onClick={simulateAllocation}
                disabled={newCapital <= 0}
                className="w-full px-6 py-4 bg-gradient-to-r from-blue-500 to-purple-500 hover:from-blue-600 hover:to-purple-600 text-white rounded-lg font-bold text-lg transition-all disabled:opacity-50 disabled:cursor-not-allowed"
              >
                🚀 Simula Allocazione
              </button>
            </div>
          </div>
        )}

        {/* MODALS */}
        
        {/* Target Allocation Modal */}
        {showModal === 'target' && (
          <Modal title="Imposta Target Allocation" onClose={() => setShowModal(null)}>
            <form onSubmit={saveTargetAllocation} className="space-y-4">
              <div className="bg-blue-500/10 border border-blue-400/30 rounded-lg p-4 mb-4">
                <p className="text-blue-200 text-sm">
                  Imposta le percentuali target per ogni tipo di asset. La somma deve essere 100%.
                </p>
              </div>

              {Object.entries(targetForm).map(([key, value]) => {
                const assetType = key.replace('target_', '').charAt(0).toUpperCase() + key.replace('target_', '').slice(1);
                return (
                  <div key={key}>
                    <label className="block text-sm font-medium text-blue-200 mb-2">
                      {assetType} %
                    </label>
                    <input
                      type="number"
                      min="0"
                      max="100"
                      step="0.1"
                      value={value}
                      onChange={(e) => setTargetForm({
                        ...targetForm,
                        [key]: parseFloat(e.target.value) || 0
                      })}
                      className="w-full px-4 py-2 bg-white/10 border border-white/20 rounded-lg text-white focus:outline-none focus:ring-2 focus:ring-blue-500"
                    />
                  </div>
                );
              })}

              <div className={`p-4 rounded-lg ${
                Math.abs(Object.values(targetForm).reduce((a, b) => a + b, 0) - 100) < 0.01
                  ? 'bg-green-500/10 border border-green-400/30'
                  : 'bg-red-500/10 border border-red-400/30'
              }`}>
                <div className="flex justify-between items-center">
                  <span className="text-white font-medium">Totale:</span>
                  <span className="text-white font-bold text-xl">
                    {Object.values(targetForm).reduce((a, b) => a + b, 0).toFixed(1)}%
                  </span>
                </div>
              </div>

              <div className="flex gap-3 justify-end">
                <button
                  type="button"
                  onClick={() => setShowModal(null)}
                  className="px-6 py-2 bg-white/10 hover:bg-white/20 text-white rounded-lg transition-all"
                >
                  Annulla
                </button>
                <button
                  type="submit"
                  className="px-6 py-2 bg-blue-500 hover:bg-blue-600 text-white rounded-lg flex items-center gap-2 transition-all"
                >
                  <Save className="w-4 h-4" />
                  Salva Target
                </button>
              </div>
            </form>
          </Modal>
        )}

        {/* Simulation Result Modal */}
        {showModal === 'simulation-result' && simulationResult && (
          <Modal title="📊 Risultato Simulazione" onClose={() => setShowModal(null)}>
            <div className="space-y-6">
              <div className="grid grid-cols-3 gap-4">
                <div className="bg-blue-500/10 border border-blue-400/30 rounded-lg p-4">
                  <div className="text-blue-200 text-sm mb-1">Valore Attuale</div>
                  <div className="text-white font-bold text-xl">{formatCurrency(simulationResult.currentTotal)}</div>
                </div>
                <div className="bg-green-500/10 border border-green-400/30 rounded-lg p-4">
                  <div className="text-green-200 text-sm mb-1">Nuova Liquidità</div>
                  <div className="text-white font-bold text-xl">{formatCurrency(simulationResult.newCapital)}</div>
                </div>
                <div className="bg-purple-500/10 border border-purple-400/30 rounded-lg p-4">
                  <div className="text-purple-200 text-sm mb-1">Valore Totale</div>
                  <div className="text-white font-bold text-xl">{formatCurrency(simulationResult.newTotal)}</div>
                </div>
              </div>

              {simulationResult.mode === 'manual' && simulationResult.remaining !== 0 && (
                <div className={`p-4 rounded-lg ${
                  simulationResult.remaining >= 0
                    ? 'bg-yellow-500/10 border border-yellow-400/30'
                    : 'bg-red-500/10 border border-red-400/30'
                }`}>
                  <div className="flex justify-between items-center">
                    <span className="text-white">Liquidità Residua:</span>
                    <span className="text-white font-bold">{formatCurrency(simulationResult.remaining)}</span>
                  </div>
                </div>
              )}

              <div className="space-y-3">
                <h3 className="text-white font-bold text-lg">Suggerimenti di Acquisto:</h3>
                {Object.entries(simulationResult.suggestions).map(([assetType, data]) => (
                  data.toInvest > 0 && (
                    <div key={assetType} className="bg-white/5 rounded-lg p-4">
                      <div className="flex justify-between items-start mb-3">
                        <div>
                          <div className="text-white font-medium text-lg">{assetType}</div>
                          <div className="text-blue-300 text-sm">
                            {data.currentPct?.toFixed(1)}% → {data.newPct?.toFixed(1)}%
                            {simulationResult.mode === 'target' && data.targetPct && (
                              <span className="text-green-400 ml-2">(Target: {data.targetPct}%)</span>
                            )}
                          </div>
                        </div>
                        <div className="text-right">
                          <div className="text-green-400 font-bold text-xl">
                            +{formatCurrency(data.toInvest)}
                          </div>
                          <div className="text-blue-200 text-sm">
                            {formatCurrency(data.current)} → {formatCurrency(data.current + data.toInvest)}
                          </div>
                        </div>
                      </div>
                      <div className="w-full bg-white/20 rounded-full h-2">
                        <div 
                          className="h-2 rounded-full bg-gradient-to-r from-blue-500 to-green-500"
                          style={{ width: `${data.newPct}%` }}
                        />
                      </div>
                    </div>
                  )
                ))}
              </div>

              <div className="bg-gradient-to-r from-blue-500/20 to-purple-500/20 border border-blue-400/30 rounded-lg p-4">
                <h4 className="text-white font-medium mb-3">💡 Consigli:</h4>
                <ul className="space-y-2 text-blue-200 text-sm">
                  {simulationResult.mode === 'target' ? (
                    <>
                      <li>• Seguendo i target impostati, mantieni il bilanciamento ideale del portafoglio</li>
                      <li>• Considera di diversificare gli acquisti in più operazioni per mediare il prezzo</li>
                      <li>• Verifica i costi di transazione prima di procedere</li>
                    </>
                  ) : (
                    <>
                      <li>• Hai scelto un'allocazione manuale personalizzata</li>
                      <li>• Verifica che sia coerente con la tua strategia di investimento</li>
                      <li>• Considera il rischio complessivo del portafoglio</li>
                    </>
                  )}
                </ul>
              </div>

              <button
                onClick={() => setShowModal(null)}
                className="w-full px-6 py-3 bg-blue-500 hover:bg-blue-600 text-white rounded-lg font-medium transition-all"
              >
                Chiudi Simulazione
              </button>
            </div>
          </Modal>
        )}
        
        {/* Nuovo Portafoglio */}
        {showModal === 'portfolio' && (
          <Modal title="Nuovo Portafoglio" onClose={() => setShowModal(null)}>
            <form onSubmit={createPortfolio} className="space-y-4">
              <div>
                <label className="block text-sm font-medium text-blue-200 mb-2">Nome Portafoglio *</label>
                <input
                  type="text"
                  required
                  value={portfolioForm.name}
                  onChange={(e) => setPortfolioForm({...portfolioForm, name: e.target.value})}
                  className="w-full px-4 py-2 bg-white/10 border border-white/20 rounded-lg text-white focus:outline-none focus:ring-2 focus:ring-blue-500"
                  placeholder="Es: Portafoglio Principale"
                />
              </div>
              <div>
                <label className="block text-sm font-medium text-blue-200 mb-2">Broker</label>
                <input
                  type="text"
                  value={portfolioForm.broker}
                  onChange={(e) => setPortfolioForm({...portfolioForm, broker: e.target.value})}
                  className="w-full px-4 py-2 bg-white/10 border border-white/20 rounded-lg text-white focus:outline-none focus:ring-2 focus:ring-blue-500"
                  placeholder="Es: FinecoBank"
                />
              </div>
              <div>
                <label className="block text-sm font-medium text-blue-200 mb-2">Valuta</label>
                <select
                  value={portfolioForm.currency}
                  onChange={(e) => setPortfolioForm({...portfolioForm, currency: e.target.value})}
                  className="w-full px-4 py-2 bg-white/10 border border-white/20 rounded-lg text-white focus:outline-none focus:ring-2 focus:ring-blue-500"
                >
                  <option value="EUR">EUR</option>
                  <option value="USD">USD</option>
                  <option value="GBP">GBP</option>
                </select>
              </div>
              <div>
                <label className="block text-sm font-medium text-blue-200 mb-2">Note</label>
                <textarea
                  value={portfolioForm.notes}
                  onChange={(e) => setPortfolioForm({...portfolioForm, notes: e.target.value})}
                  className="w-full px-4 py-2 bg-white/10 border border-white/20 rounded-lg text-white focus:outline-none focus:ring-2 focus:ring-blue-500"
                  rows="3"
                  placeholder="Note aggiuntive..."
                />
              </div>
              <div className="flex gap-3 justify-end">
                <button
                  type="button"
                  onClick={() => setShowModal(null)}
                  className="px-6 py-2 bg-white/10 hover:bg-white/20 text-white rounded-lg transition-all"
                >
                  Annulla
                </button>
                <button
                  type="submit"
                  className="px-6 py-2 bg-blue-500 hover:bg-blue-600 text-white rounded-lg flex items-center gap-2 transition-all"
                >
                  <Save className="w-4 h-4" />
                  Salva Portafoglio
                </button>
              </div>
            </form>
          </Modal>
        )}

        {/* Nuovo Asset */}
        {showModal === 'asset' && (
          <Modal title="Nuovo Asset" onClose={() => setShowModal(null)}>
            <form onSubmit={createAsset} className="space-y-4">
              <div className="grid grid-cols-2 gap-4">
                <div>
                  <label className="block text-sm font-medium text-blue-200 mb-2">ISIN *</label>
                  <input
                    type="text"
                    required
                    value={assetForm.isin}
                    onChange={(e) => setAssetForm({...assetForm, isin: e.target.value.toUpperCase()})}
                    className="w-full px-4 py-2 bg-white/10 border border-white/20 rounded-lg text-white focus:outline-none focus:ring-2 focus:ring-blue-500"
                    placeholder="ES: IE00B5BMR087"
                    maxLength="12"
                  />
                </div>
                <div>
                  <label className="block text-sm font-medium text-blue-200 mb-2">Ticker</label>
                  <input
                    type="text"
                    value={assetForm.ticker}
                    onChange={(e) => setAssetForm({...assetForm, ticker: e.target.value.toUpperCase()})}
                    className="w-full px-4 py-2 bg-white/10 border border-white/20 rounded-lg text-white focus:outline-none focus:ring-2 focus:ring-blue-500"
                    placeholder="ES: CSPX"
                  />
                </div>
              </div>
              <div>
                <label className="block text-sm font-medium text-blue-200 mb-2">Nome Asset *</label>
                <input
                  type="text"
                  required
                  value={assetForm.name}
                  onChange={(e) => setAssetForm({...assetForm, name: e.target.value})}
                  className="w-full px-4 py-2 bg-white/10 border border-white/20 rounded-lg text-white focus:outline-none focus:ring-2 focus:ring-blue-500"
                  placeholder="Es: iShares Core S&P 500 UCITS ETF"
                />
              </div>
              <div className="grid grid-cols-2 gap-4">
                <div>
                  <label className="block text-sm font-medium text-blue-200 mb-2">Tipo Asset</label>
                  <select
                    value={assetForm.asset_type}
                    onChange={(e) => setAssetForm({...assetForm, asset_type: e.target.value})}
                    className="w-full px-4 py-2 bg-white/10 border border-white/20 rounded-lg text-white focus:outline-none focus:ring-2 focus:ring-blue-500"
                  >
                    <option value="Azionario">Azionario</option>
                    <option value="Obbligazionario">Obbligazionario</option>
                    <option value="Monetario">Monetario</option>
                    <option value="Oro">Oro</option>
                    <option value="Crypto">Crypto</option>
                    <option value="ETF">ETF</option>
                  </select>
                </div>
                <div>
                  <label className="block text-sm font-medium text-blue-200 mb-2">Valuta</label>
                  <select
                    value={assetForm.currency}
                    onChange={(e) => setAssetForm({...assetForm, currency: e.target.value})}
                    className="w-full px-4 py-2 bg-white/10 border border-white/20 rounded-lg text-white focus:outline-none focus:ring-2 focus:ring-blue-500"
                  >
                    <option value="EUR">EUR</option>
                    <option value="USD">USD</option>
                    <option value="GBP">GBP</option>
                  </select>
                </div>
              </div>
              <div className="grid grid-cols-2 gap-4">
                <div>
                  <label className="block text-sm font-medium text-blue-200 mb-2">Settore</label>
                  <input
                    type="text"
                    value={assetForm.sector}
                    onChange={(e) => setAssetForm({...assetForm, sector: e.target.value})}
                    className="w-full px-4 py-2 bg-white/10 border border-white/20 rounded-lg text-white focus:outline-none focus:ring-2 focus:ring-blue-500"
                    placeholder="Es: Tecnologia"
                  />
                </div>
                <div>
                  <label className="block text-sm font-medium text-blue-200 mb-2">Paese</label>
                  <input
                    type="text"
                    value={assetForm.country}
                    onChange={(e) => setAssetForm({...assetForm, country: e.target.value})}
                    className="w-full px-4 py-2 bg-white/10 border border-white/20 rounded-lg text-white focus:outline-none focus:ring-2 focus:ring-blue-500"
                    placeholder="Es: USA"
                  />
                </div>
              </div>
              <div className="flex gap-3 justify-end">
                <button
                  type="button"
                  onClick={() => setShowModal(null)}
                  className="px-6 py-2 bg-white/10 hover:bg-white/20 text-white rounded-lg transition-all"
                >
                  Annulla
                </button>
                <button
                  type="submit"
                  className="px-6 py-2 bg-blue-500 hover:bg-blue-600 text-white rounded-lg flex items-center gap-2 transition-all"
                >
                  <Save className="w-4 h-4" />
                  Salva Asset
                </button>
              </div>
            </form>
          </Modal>
        )}

        {/* Nuova Transazione */}
        {showModal === 'transaction' && (
          <Modal title="Nuova Transazione" onClose={() => setShowModal(null)}>
            <form onSubmit={createTransaction} className="space-y-4">
              <div>
                <label className="block text-sm font-medium text-blue-200 mb-2">Asset *</label>
                <select
                  required
                  value={transactionForm.asset_id}
                  onChange={(e) => setTransactionForm({...transactionForm, asset_id: e.target.value})}
                  className="w-full px-4 py-2 bg-white/10 border border-white/20 rounded-lg text-white focus:outline-none focus:ring-2 focus:ring-blue-500"
                >
                  <option value="">Seleziona asset...</option>
                  {assets.map(asset => (
                    <option key={asset.asset_id} value={asset.asset_id}>
                      {asset.name} ({asset.isin})
                    </option>
                  ))}
                </select>
              </div>
              <div className="grid grid-cols-2 gap-4">
                <div>
                  <label className="block text-sm font-medium text-blue-200 mb-2">Tipo</label>
                  <select
                    value={transactionForm.transaction_type}
                    onChange={(e) => setTransactionForm({...transactionForm, transaction_type: e.target.value})}
                    className="w-full px-4 py-2 bg-white/10 border border-white/20 rounded-lg text-white focus:outline-none focus:ring-2 focus:ring-blue-500"
                  >
                    <option value="BUY">ACQUISTO</option>
                    <option value="SELL">VENDITA</option>
                  </select>
                </div>
                <div>
                  <label className="block text-sm font-medium text-blue-200 mb-2">Data *</label>
                  <input
                    type="date"
                    required
                    value={transactionForm.transaction_date}
                    onChange={(e) => setTransactionForm({...transactionForm, transaction_date: e.target.value})}
                    className="w-full px-4 py-2 bg-white/10 border border-white/20 rounded-lg text-white focus:outline-none focus:ring-2 focus:ring-blue-500"
                  />
                </div>
              </div>
              <div className="grid grid-cols-2 gap-4">
                <div>
                  <label className="block text-sm font-medium text-blue-200 mb-2">Quantità *</label>
                  <input
                    type="number"
                    required
                    step="0.000001"
                    value={transactionForm.quantity}
                    onChange={(e) => setTransactionForm({...transactionForm, quantity: parseFloat(e.target.value)})}
                    className="w-full px-4 py-2 bg-white/10 border border-white/20 rounded-lg text-white focus:outline-none focus:ring-2 focus:ring-blue-500"
                    placeholder="0.00"
                  />
                </div>
                <div>
                  <label className="block text-sm font-medium text-blue-200 mb-2">Prezzo *</label>
                  <input
                    type="number"
                    required
                    step="0.01"
                    value={transactionForm.price_per_share}
                    onChange={(e) => setTransactionForm({...transactionForm, price_per_share: parseFloat(e.target.value)})}
                    className="w-full px-4 py-2 bg-white/10 border border-white/20 rounded-lg text-white focus:outline-none focus:ring-2 focus:ring-blue-500"
                    placeholder="0.00"
                  />
                </div>
              </div>
              <div className="grid grid-cols-2 gap-4">
                <div>
                  <label className="block text-sm font-medium text-blue-200 mb-2">Commissioni</label>
                  <input
                    type="number"
                    step="0.01"
                    value={transactionForm.commission}
                    onChange={(e) => setTransactionForm({...transactionForm, commission: parseFloat(e.target.value)})}
                    className="w-full px-4 py-2 bg-white/10 border border-white/20 rounded-lg text-white focus:outline-none focus:ring-2 focus:ring-blue-500"
                    placeholder="0.00"
                  />
                </div>
                <div>
                  <label className="block text-sm font-medium text-blue-200 mb-2">Spese</label>
                  <input
                    type="number"
                    step="0.01"
                    value={transactionForm.fees}
                    onChange={(e) => setTransactionForm({...transactionForm, fees: parseFloat(e.target.value)})}
                    className="w-full px-4 py-2 bg-white/10 border border-white/20 rounded-lg text-white focus:outline-none focus:ring-2 focus:ring-blue-500"
                    placeholder="0.00"
                  />
                </div>
              </div>
              <div className="bg-blue-500/10 border border-blue-400/30 rounded-lg p-4">
                <div className="text-sm text-blue-200 mb-1">Totale operazione</div>
                <div className="text-2xl font-bold text-white">
                  {formatCurrency((transactionForm.quantity * transactionForm.price_per_share) + transactionForm.commission + transactionForm.fees)}
                </div>
              </div>
              <div className="flex gap-3 justify-end">
                <button
                  type="button"
                  onClick={() => setShowModal(null)}
                  className="px-6 py-2 bg-white/10 hover:bg-white/20 text-white rounded-lg transition-all"
                >
                  Annulla
                </button>
                <button
                  type="submit"
                  className="px-6 py-2 bg-blue-500 hover:bg-blue-600 text-white rounded-lg flex items-center gap-2 transition-all"
                >
                  <Save className="w-4 h-4" />
                  Salva Transazione
                </button>
              </div>
            </form>
          </Modal>
        )}
      </div>
    </div>
  );
};

export default PortfolioApp;