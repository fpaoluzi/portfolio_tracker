'use client';

import { useState, useEffect } from 'react';
import { Save, Plus, Trash2, X } from 'lucide-react';
import { Modal, Button } from '@/components/ui';
import { saveManualComposition, getCompositionByAsset, type ManualCompositionData } from '@/lib/api';
import { useToastContext } from '@/lib/context/ToastContext';
import { isEquityType, isBondType } from '@/lib/utils/assetHelpers';
import type { Asset } from '@/types';

interface ManualCompositionFormProps {
  asset: Asset;
  onClose: () => void;
  onSuccess: () => void;
}

type TabType = 'holdings' | 'sectors' | 'regions' | 'allocation' | 'bondRatings' | 'bondMaturity';

export const ManualCompositionForm: React.FC<ManualCompositionFormProps> = ({
  asset,
  onClose,
  onSuccess,
}) => {
  const toast = useToastContext();

  // Determine asset type first
  const isEquity = isEquityType(asset.asset_type);
  const isBond = isBondType(asset.asset_type);

  // Set initial tab based on asset type
  const [activeTab, setActiveTab] = useState<TabType>(isEquity ? 'holdings' : 'sectors');
  const [saving, setSaving] = useState(false);
  const [loading, setLoading] = useState(true);

  // Holdings data
  const [holdings, setHoldings] = useState<Array<{ symbol: string; name: string; percent: number }>>([
    { symbol: '', name: '', percent: 0 },
  ]);

  // Sectors data
  const [sectors, setSectors] = useState<Array<{ name: string; percent: number }>>([
    { name: '', percent: 0 },
  ]);

  // Regions data
  const [regions, setRegions] = useState<Array<{ name: string; percent: number }>>([
    { name: '', percent: 0 },
  ]);

  // Allocation data
  const [allocation, setAllocation] = useState<Array<{ type: string; percent: number }>>([
    { type: 'Equity', percent: 100 },
  ]);

  // Bond Ratings data
  const [bondRatings, setBondRatings] = useState<Array<{ category: string; percent: number }>>([
    { category: '', percent: 0 },
  ]);

  // Bond Maturity data
  const [bondMaturity, setBondMaturity] = useState<
    Array<{ range: string; percent: number; duration?: number }>
  >([{ range: '', percent: 0, duration: 0 }]);

  // Fetch existing composition data when component mounts
  useEffect(() => {
    const fetchExistingData = async () => {
      try {
        setLoading(true);
        const composition = await getCompositionByAsset(asset.asset_id);

        // Populate holdings only for equity assets (convert from decimal to percentage)
        if (isEquity && composition.holdings && composition.holdings.length > 0) {
          setHoldings(
            composition.holdings.map((h) => ({
              symbol: h.holding_symbol || '',
              name: h.holding_name,
              percent: parseFloat((h.holding_percent * 100).toFixed(2)), // Convert 0-1 to 0-100 with 2 decimals
            }))
          );
        }

        // Populate sectors
        if (composition.sectors && composition.sectors.length > 0) {
          setSectors(
            composition.sectors.map((s) => ({
              name: s.sector_name,
              percent: parseFloat((s.weight_percent * 100).toFixed(2)),
            }))
          );
        }

        // Populate regions
        if (composition.regions && composition.regions.length > 0) {
          setRegions(
            composition.regions.map((r) => ({
              name: r.region_name,
              percent: parseFloat((r.weight_percent * 100).toFixed(2)),
            }))
          );
        }

        // Populate allocation
        if (composition.allocation && composition.allocation.length > 0) {
          setAllocation(
            composition.allocation.map((a) => ({
              type: a.allocation_type,
              percent: parseFloat((a.weight_percent * 100).toFixed(2)),
            }))
          );
        }

        // Populate bond ratings
        if (composition.bondRatings && composition.bondRatings.length > 0) {
          setBondRatings(
            composition.bondRatings.map((b) => ({
              category: b.rating_category,
              percent: parseFloat((b.weight_percent * 100).toFixed(2)),
            }))
          );
        }

        // Populate bond maturity
        if (composition.bondMaturity && composition.bondMaturity.length > 0) {
          setBondMaturity(
            composition.bondMaturity.map((m) => ({
              range: m.maturity_range,
              percent: parseFloat((m.weight_percent * 100).toFixed(2)),
              duration: m.avg_duration_years ? parseFloat(m.avg_duration_years.toFixed(2)) : undefined,
            }))
          );
        }
      } catch (error: any) {
        // If no data exists, that's fine - form starts empty
        console.log('No existing composition data:', error.message);
      } finally {
        setLoading(false);
      }
    };

    fetchExistingData();
  }, [asset.asset_id, isEquity, isBond]);

  const handleSubmit = async () => {
    // Validazione base - holdings solo per equity
    const hasData =
      (isEquity && holdings.some((h) => h.name)) ||
      sectors.some((s) => s.name) ||
      regions.some((r) => r.name) ||
      allocation.some((a) => a.type) ||
      (isBond && bondRatings.some((b) => b.category)) ||
      (isBond && bondMaturity.some((m) => m.range));

    if (!hasData) {
      toast.error('Nessun dato inserito', 'Inserisci almeno un dato di composizione');
      return;
    }

    setSaving(true);

    try {
      const data: ManualCompositionData = {
        // Include holdings only for equity assets
        holdings: isEquity ? holdings.filter((h) => h.name).map((h) => ({ ...h, rank: 0 })) : [],
        sectors: sectors.filter((s) => s.name),
        regions: regions.filter((r) => r.name),
        allocation: allocation.filter((a) => a.type),
        // Include bond data only for bond assets
        bondRatings: isBond ? bondRatings.filter((b) => b.category) : [],
        bondMaturity: isBond ? bondMaturity.filter((m) => m.range) : [],
      };

      const result = await saveManualComposition(asset.asset_id, data);

      toast.success(
        'Composizione salvata!',
        `Holdings: ${result.stats.holdings} | Settori: ${result.stats.sectors} | Regioni: ${result.stats.regions}`
      );

      onSuccess();
      onClose();
    } catch (error: any) {
      toast.error('Errore salvataggio', error.message);
    } finally {
      setSaving(false);
    }
  };

  const tabs: Array<{ id: TabType; label: string; visible: boolean }> = [
    { id: 'holdings', label: 'Holdings', visible: isEquity },
    { id: 'sectors', label: 'Settori', visible: true },
    { id: 'regions', label: 'Regioni', visible: true },
    { id: 'allocation', label: 'Asset Class', visible: true },
    { id: 'bondRatings', label: 'Rating', visible: isBond },
    { id: 'bondMaturity', label: 'Maturity', visible: isBond },
  ];

  return (
    <Modal
      title={`Inserimento Manuale Composizione - ${asset.name}`}
      onClose={onClose}
      size="large"
    >
      <div className="space-y-4">
        {/* Tabs */}
        <div className="flex gap-2 border-b border-white/20 overflow-x-auto">
          {tabs
            .filter((tab) => tab.visible)
            .map((tab) => (
              <button
                key={tab.id}
                onClick={() => setActiveTab(tab.id)}
                className={`px-4 py-2 font-medium transition-colors whitespace-nowrap ${
                  activeTab === tab.id
                    ? 'text-blue-400 border-b-2 border-blue-400'
                    : 'text-blue-200 hover:text-white'
                }`}
              >
                {tab.label}
              </button>
            ))}
        </div>

        {/* Loading State */}
        {loading ? (
          <div className="min-h-[400px] flex items-center justify-center">
            <div className="text-center">
              <div className="w-12 h-12 border-4 border-blue-500/30 border-t-blue-500 rounded-full animate-spin mx-auto mb-4"></div>
              <p className="text-blue-300">Caricamento dati composizione...</p>
            </div>
          </div>
        ) : (
          /* Tab Content */
          <div className="min-h-[400px] max-h-[500px] overflow-y-auto">
          {/* Holdings Tab */}
          {activeTab === 'holdings' && (
            <HoldingsTab holdings={holdings} setHoldings={setHoldings} />
          )}

          {/* Sectors Tab */}
          {activeTab === 'sectors' && <SectorsTab sectors={sectors} setSectors={setSectors} />}

          {/* Regions Tab */}
          {activeTab === 'regions' && <RegionsTab regions={regions} setRegions={setRegions} />}

          {/* Allocation Tab */}
          {activeTab === 'allocation' && (
            <AllocationTab allocation={allocation} setAllocation={setAllocation} />
          )}

          {/* Bond Ratings Tab */}
          {activeTab === 'bondRatings' && (
            <BondRatingsTab bondRatings={bondRatings} setBondRatings={setBondRatings} />
          )}

          {/* Bond Maturity Tab */}
          {activeTab === 'bondMaturity' && (
            <BondMaturityTab bondMaturity={bondMaturity} setBondMaturity={setBondMaturity} />
          )}
          </div>
        )}

        {/* Actions */}
        <div className="flex gap-3 justify-end pt-4 border-t border-white/20">
          <Button type="button" variant="secondary" onClick={onClose} disabled={saving}>
            Annulla
          </Button>
          <Button
            type="button"
            variant="primary"
            icon={Save}
            onClick={handleSubmit}
            disabled={saving}
          >
            {saving ? 'Salvataggio...' : 'Salva Composizione'}
          </Button>
        </div>
      </div>
    </Modal>
  );
};

// Holdings Tab Component
const HoldingsTab: React.FC<{
  holdings: Array<{ symbol: string; name: string; percent: number }>;
  setHoldings: React.Dispatch<
    React.SetStateAction<Array<{ symbol: string; name: string; percent: number }>>
  >;
}> = ({ holdings, setHoldings }) => {
  const addRow = () => {
    setHoldings([...holdings, { symbol: '', name: '', percent: 0 }]);
  };

  const removeRow = (index: number) => {
    setHoldings(holdings.filter((_, i) => i !== index));
  };

  const updateRow = (index: number, field: string, value: any) => {
    const updated = [...holdings];
    updated[index] = { ...updated[index], [field]: value };
    setHoldings(updated);
  };

  return (
    <div className="space-y-3">
      <div className="flex justify-between items-center">
        <p className="text-sm text-blue-200">Inserisci le principali holdings (azioni)</p>
        <button
          onClick={addRow}
          className="flex items-center gap-1 px-3 py-1 bg-blue-500/20 hover:bg-blue-500/30 rounded text-sm text-blue-300"
        >
          <Plus className="w-4 h-4" />
          Aggiungi
        </button>
      </div>

      {holdings.map((holding, index) => (
        <div key={index} className="grid grid-cols-12 gap-2 items-center">
          <input
            type="text"
            placeholder="Symbol (es. AAPL)"
            value={holding.symbol}
            onChange={(e) => updateRow(index, 'symbol', e.target.value.toUpperCase())}
            className="col-span-2 px-3 py-2 bg-slate-700 border border-white/20 rounded text-white text-sm focus:outline-none focus:ring-2 focus:ring-blue-500 placeholder-slate-400"
          />
          <input
            type="text"
            placeholder="Nome holding *"
            value={holding.name}
            onChange={(e) => updateRow(index, 'name', e.target.value)}
            className="col-span-7 px-3 py-2 bg-slate-700 border border-white/20 rounded text-white text-sm focus:outline-none focus:ring-2 focus:ring-blue-500 placeholder-slate-400"
          />
          <div className="col-span-2 relative">
            <input
              type="number"
              step="0.01"
              placeholder="0.00"
              value={holding.percent || ''}
              onChange={(e) => updateRow(index, 'percent', parseFloat(e.target.value) || 0)}
              className="w-full px-3 py-2 pr-8 bg-slate-700 border border-white/20 rounded text-white text-sm text-right focus:outline-none focus:ring-2 focus:ring-blue-500 placeholder-slate-400"
            />
            <span className="absolute right-3 top-1/2 -translate-y-1/2 text-blue-300 text-sm pointer-events-none">%</span>
          </div>
          <button
            onClick={() => removeRow(index)}
            className="col-span-1 p-2 hover:bg-red-500/20 rounded text-red-400"
            disabled={holdings.length === 1}
          >
            <Trash2 className="w-4 h-4" />
          </button>
        </div>
      ))}
    </div>
  );
};

// Sectors Tab Component
const SectorsTab: React.FC<{
  sectors: Array<{ name: string; percent: number }>;
  setSectors: React.Dispatch<React.SetStateAction<Array<{ name: string; percent: number }>>>;
}> = ({ sectors, setSectors }) => {
  const addRow = () => {
    setSectors([...sectors, { name: '', percent: 0 }]);
  };

  const removeRow = (index: number) => {
    setSectors(sectors.filter((_, i) => i !== index));
  };

  const updateRow = (index: number, field: string, value: any) => {
    const updated = [...sectors];
    updated[index] = { ...updated[index], [field]: value };
    setSectors(updated);
  };

  return (
    <div className="space-y-3">
      <div className="flex justify-between items-center">
        <p className="text-sm text-blue-200">Inserisci la distribuzione settoriale</p>
        <button
          onClick={addRow}
          className="flex items-center gap-1 px-3 py-1 bg-blue-500/20 hover:bg-blue-500/30 rounded text-sm text-blue-300"
        >
          <Plus className="w-4 h-4" />
          Aggiungi
        </button>
      </div>

      {sectors.map((sector, index) => (
        <div key={index} className="grid grid-cols-12 gap-2 items-center">
          <input
            type="text"
            placeholder="Nome settore *"
            value={sector.name}
            onChange={(e) => updateRow(index, 'name', e.target.value)}
            className="col-span-9 px-3 py-2 bg-slate-700 border border-white/20 rounded text-white text-sm focus:outline-none focus:ring-2 focus:ring-blue-500 placeholder-slate-400"
          />
          <div className="col-span-2 relative">
            <input
              type="number"
              step="0.01"
              placeholder="0.00"
              value={sector.percent || ''}
              onChange={(e) => updateRow(index, 'percent', parseFloat(e.target.value) || 0)}
              className="w-full px-3 py-2 pr-8 bg-slate-700 border border-white/20 rounded text-white text-sm text-right focus:outline-none focus:ring-2 focus:ring-blue-500 placeholder-slate-400"
            />
            <span className="absolute right-3 top-1/2 -translate-y-1/2 text-blue-300 text-sm pointer-events-none">%</span>
          </div>
          <button
            onClick={() => removeRow(index)}
            className="col-span-1 p-2 hover:bg-red-500/20 rounded text-red-400"
            disabled={sectors.length === 1}
          >
            <Trash2 className="w-4 h-4" />
          </button>
        </div>
      ))}
    </div>
  );
};

// Regions Tab Component (similar to Sectors)
const RegionsTab: React.FC<{
  regions: Array<{ name: string; percent: number }>;
  setRegions: React.Dispatch<React.SetStateAction<Array<{ name: string; percent: number }>>>;
}> = ({ regions, setRegions }) => {
  const addRow = () => {
    setRegions([...regions, { name: '', percent: 0 }]);
  };

  const removeRow = (index: number) => {
    setRegions(regions.filter((_, i) => i !== index));
  };

  const updateRow = (index: number, field: string, value: any) => {
    const updated = [...regions];
    updated[index] = { ...updated[index], [field]: value };
    setRegions(updated);
  };

  return (
    <div className="space-y-3">
      <div className="flex justify-between items-center">
        <p className="text-sm text-blue-200">Inserisci la distribuzione geografica</p>
        <button
          onClick={addRow}
          className="flex items-center gap-1 px-3 py-1 bg-blue-500/20 hover:bg-blue-500/30 rounded text-sm text-blue-300"
        >
          <Plus className="w-4 h-4" />
          Aggiungi
        </button>
      </div>

      {regions.map((region, index) => (
        <div key={index} className="grid grid-cols-12 gap-2 items-center">
          <input
            type="text"
            placeholder="Nome regione/paese *"
            value={region.name}
            onChange={(e) => updateRow(index, 'name', e.target.value)}
            className="col-span-9 px-3 py-2 bg-slate-700 border border-white/20 rounded text-white text-sm focus:outline-none focus:ring-2 focus:ring-blue-500 placeholder-slate-400"
          />
          <div className="col-span-2 relative">
            <input
              type="number"
              step="0.01"
              placeholder="0.00"
              value={region.percent || ''}
              onChange={(e) => updateRow(index, 'percent', parseFloat(e.target.value) || 0)}
              className="w-full px-3 py-2 pr-8 bg-slate-700 border border-white/20 rounded text-white text-sm text-right focus:outline-none focus:ring-2 focus:ring-blue-500 placeholder-slate-400"
            />
            <span className="absolute right-3 top-1/2 -translate-y-1/2 text-blue-300 text-sm pointer-events-none">%</span>
          </div>
          <button
            onClick={() => removeRow(index)}
            className="col-span-1 p-2 hover:bg-red-500/20 rounded text-red-400"
            disabled={regions.length === 1}
          >
            <Trash2 className="w-4 h-4" />
          </button>
        </div>
      ))}
    </div>
  );
};

// Allocation Tab Component
const AllocationTab: React.FC<{
  allocation: Array<{ type: string; percent: number }>;
  setAllocation: React.Dispatch<React.SetStateAction<Array<{ type: string; percent: number }>>>;
}> = ({ allocation, setAllocation }) => {
  const addRow = () => {
    setAllocation([...allocation, { type: '', percent: 0 }]);
  };

  const removeRow = (index: number) => {
    setAllocation(allocation.filter((_, i) => i !== index));
  };

  const updateRow = (index: number, field: string, value: any) => {
    const updated = [...allocation];
    updated[index] = { ...updated[index], [field]: value };
    setAllocation(updated);
  };

  const allocationTypes = ['Equity', 'Bond', 'Cash', 'Other', 'Commodity', 'Real Estate'];

  return (
    <div className="space-y-3">
      <div className="flex justify-between items-center">
        <p className="text-sm text-blue-200">Inserisci la distribuzione per asset class</p>
        <button
          onClick={addRow}
          className="flex items-center gap-1 px-3 py-1 bg-blue-500/20 hover:bg-blue-500/30 rounded text-sm text-blue-300"
        >
          <Plus className="w-4 h-4" />
          Aggiungi
        </button>
      </div>

      {allocation.map((alloc, index) => (
        <div key={index} className="grid grid-cols-12 gap-2 items-center">
          <select
            value={alloc.type}
            onChange={(e) => updateRow(index, 'type', e.target.value)}
            className="col-span-9 px-3 py-2 bg-slate-700 border border-white/20 rounded text-white text-sm focus:outline-none focus:ring-2 focus:ring-blue-500 [&>option]:bg-slate-700 [&>option]:text-white"
          >
            <option value="">Seleziona tipo *</option>
            {allocationTypes.map((type) => (
              <option key={type} value={type}>
                {type}
              </option>
            ))}
          </select>
          <div className="col-span-2 relative">
            <input
              type="number"
              step="0.01"
              placeholder="0.00"
              value={alloc.percent || ''}
              onChange={(e) => updateRow(index, 'percent', parseFloat(e.target.value) || 0)}
              className="w-full px-3 py-2 pr-8 bg-slate-700 border border-white/20 rounded text-white text-sm text-right focus:outline-none focus:ring-2 focus:ring-blue-500 placeholder-slate-400"
            />
            <span className="absolute right-3 top-1/2 -translate-y-1/2 text-blue-300 text-sm pointer-events-none">%</span>
          </div>
          <button
            onClick={() => removeRow(index)}
            className="col-span-1 p-2 hover:bg-red-500/20 rounded text-red-400"
            disabled={allocation.length === 1}
          >
            <Trash2 className="w-4 h-4" />
          </button>
        </div>
      ))}
    </div>
  );
};

// Bond Ratings Tab Component
const BondRatingsTab: React.FC<{
  bondRatings: Array<{ category: string; percent: number }>;
  setBondRatings: React.Dispatch<React.SetStateAction<Array<{ category: string; percent: number }>>>;
}> = ({ bondRatings, setBondRatings }) => {
  const addRow = () => {
    setBondRatings([...bondRatings, { category: '', percent: 0 }]);
  };

  const removeRow = (index: number) => {
    setBondRatings(bondRatings.filter((_, i) => i !== index));
  };

  const updateRow = (index: number, field: string, value: any) => {
    const updated = [...bondRatings];
    updated[index] = { ...updated[index], [field]: value };
    setBondRatings(updated);
  };

  const ratingCategories = ['AAA', 'AA', 'A', 'BBB', 'BB', 'B', 'CCC and Below', 'Not Rated'];

  return (
    <div className="space-y-3">
      <div className="flex justify-between items-center">
        <p className="text-sm text-blue-200">Inserisci la distribuzione dei rating obbligazionari</p>
        <button
          onClick={addRow}
          className="flex items-center gap-1 px-3 py-1 bg-blue-500/20 hover:bg-blue-500/30 rounded text-sm text-blue-300"
        >
          <Plus className="w-4 h-4" />
          Aggiungi
        </button>
      </div>

      {bondRatings.map((rating, index) => (
        <div key={index} className="grid grid-cols-12 gap-2 items-center">
          <select
            value={rating.category}
            onChange={(e) => updateRow(index, 'category', e.target.value)}
            className="col-span-9 px-3 py-2 bg-slate-700 border border-white/20 rounded text-white text-sm focus:outline-none focus:ring-2 focus:ring-blue-500 [&>option]:bg-slate-700 [&>option]:text-white"
          >
            <option value="">Seleziona rating *</option>
            {ratingCategories.map((cat) => (
              <option key={cat} value={cat}>
                {cat}
              </option>
            ))}
          </select>
          <div className="col-span-2 relative">
            <input
              type="number"
              step="0.01"
              placeholder="0.00"
              value={rating.percent || ''}
              onChange={(e) => updateRow(index, 'percent', parseFloat(e.target.value) || 0)}
              className="w-full px-3 py-2 pr-8 bg-slate-700 border border-white/20 rounded text-white text-sm text-right focus:outline-none focus:ring-2 focus:ring-blue-500 placeholder-slate-400"
            />
            <span className="absolute right-3 top-1/2 -translate-y-1/2 text-blue-300 text-sm pointer-events-none">%</span>
          </div>
          <button
            onClick={() => removeRow(index)}
            className="col-span-1 p-2 hover:bg-red-500/20 rounded text-red-400"
            disabled={bondRatings.length === 1}
          >
            <Trash2 className="w-4 h-4" />
          </button>
        </div>
      ))}
    </div>
  );
};

// Bond Maturity Tab Component
const BondMaturityTab: React.FC<{
  bondMaturity: Array<{ range: string; percent: number; duration?: number }>;
  setBondMaturity: React.Dispatch<
    React.SetStateAction<Array<{ range: string; percent: number; duration?: number }>>
  >;
}> = ({ bondMaturity, setBondMaturity }) => {
  const addRow = () => {
    setBondMaturity([...bondMaturity, { range: '', percent: 0, duration: 0 }]);
  };

  const removeRow = (index: number) => {
    setBondMaturity(bondMaturity.filter((_, i) => i !== index));
  };

  const updateRow = (index: number, field: string, value: any) => {
    const updated = [...bondMaturity];
    updated[index] = { ...updated[index], [field]: value };
    setBondMaturity(updated);
  };

  const maturityRanges = [
    '0-1 Years',
    '1-3 Years',
    '3-5 Years',
    '5-7 Years',
    '7-10 Years',
    '10-15 Years',
    '15-20 Years',
    '20+ Years',
  ];

  return (
    <div className="space-y-3">
      <div className="flex justify-between items-center">
        <p className="text-sm text-blue-200">Inserisci la distribuzione delle scadenze obbligazionarie</p>
        <button
          onClick={addRow}
          className="flex items-center gap-1 px-3 py-1 bg-blue-500/20 hover:bg-blue-500/30 rounded text-sm text-blue-300"
        >
          <Plus className="w-4 h-4" />
          Aggiungi
        </button>
      </div>

      {bondMaturity.map((maturity, index) => (
        <div key={index} className="grid grid-cols-12 gap-2 items-center">
          <select
            value={maturity.range}
            onChange={(e) => updateRow(index, 'range', e.target.value)}
            className="col-span-7 px-3 py-2 bg-slate-700 border border-white/20 rounded text-white text-sm focus:outline-none focus:ring-2 focus:ring-blue-500 [&>option]:bg-slate-700 [&>option]:text-white"
          >
            <option value="">Seleziona range *</option>
            {maturityRanges.map((range) => (
              <option key={range} value={range}>
                {range}
              </option>
            ))}
          </select>
          <div className="col-span-2 relative">
            <input
              type="number"
              step="0.01"
              placeholder="0.00"
              value={maturity.percent || ''}
              onChange={(e) => updateRow(index, 'percent', parseFloat(e.target.value) || 0)}
              className="w-full px-3 py-2 pr-8 bg-slate-700 border border-white/20 rounded text-white text-sm text-right focus:outline-none focus:ring-2 focus:ring-blue-500 placeholder-slate-400"
            />
            <span className="absolute right-3 top-1/2 -translate-y-1/2 text-blue-300 text-sm pointer-events-none">%</span>
          </div>
          <div className="col-span-2 relative">
            <input
              type="number"
              step="0.1"
              placeholder="0.0"
              value={maturity.duration || ''}
              onChange={(e) => updateRow(index, 'duration', parseFloat(e.target.value) || undefined)}
              className="w-full px-3 py-2 pr-12 bg-slate-700 border border-white/20 rounded text-white text-sm text-right focus:outline-none focus:ring-2 focus:ring-blue-500 placeholder-slate-400"
            />
            <span className="absolute right-3 top-1/2 -translate-y-1/2 text-blue-300 text-sm pointer-events-none">anni</span>
          </div>
          <button
            onClick={() => removeRow(index)}
            className="col-span-1 p-2 hover:bg-red-500/20 rounded text-red-400"
            disabled={bondMaturity.length === 1}
          >
            <Trash2 className="w-4 h-4" />
          </button>
        </div>
      ))}
    </div>
  );
};
