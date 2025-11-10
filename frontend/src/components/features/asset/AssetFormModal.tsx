'use client';

import { useState, useEffect, FormEvent } from 'react';
import { Save } from 'lucide-react';
import { Modal, Button, Input, Select } from '@/components/ui';
import { assetsApi } from '@/lib/api';
import type { Asset, AssetFormData } from '@/types';

interface AssetFormModalProps {
  asset?: Asset | null;
  onClose: () => void;
  onSuccess: () => void;
}

export const AssetFormModal: React.FC<AssetFormModalProps> = ({ asset, onClose, onSuccess }) => {
  const [form, setForm] = useState<AssetFormData>({
    isin: '',
    name: '',
    ticker: '',
    asset_type: 'Azionario',
    sector: '',
    country: '',
    region: '',
    currency: 'EUR',
    ter: 0,
    sharpe_ratio: 0,
    annual_fees: 0,
    standard_deviation: 0,
    isr: 1,
    factsheet_url: '',
  });

  useEffect(() => {
    if (asset) {
      setForm({
        isin: asset.isin,
        name: asset.name,
        ticker: asset.ticker || '',
        asset_type: asset.asset_type,
        sector: asset.sector || '',
        country: asset.country || '',
        region: asset.region || '',
        currency: asset.currency,
        ter: asset.ter || 0,
        sharpe_ratio: asset.sharpe_ratio || 0,
        annual_fees: asset.annual_fees || 0,
        standard_deviation: asset.standard_deviation || 0,
        isr: asset.isr || 1,
        factsheet_url: asset.factsheet_url || '',
      });
    }
  }, [asset]);

  const handleSubmit = async (e: FormEvent) => {
    e.preventDefault();
    try {
      if (asset) {
        await assetsApi.update(asset.asset_id, form);
      } else {
        await assetsApi.create(form);
      }
      onSuccess();
      onClose();
    } catch (error) {
      console.error('Error saving asset:', error);
      alert(`Errore nel ${asset ? 'aggiornamento' : 'creazione'} dell\'asset`);
    }
  };

  return (
    <Modal title={asset ? 'Modifica Asset' : 'Nuovo Asset'} onClose={onClose}>
      <form onSubmit={handleSubmit} className="space-y-4">
        <div className="grid grid-cols-2 gap-4">
          <Input
            label="ISIN *"
            type="text"
            required
            value={form.isin}
            onChange={(e) => setForm({ ...form, isin: e.target.value.toUpperCase() })}
            placeholder="ES: IE00B5BMR087"
            maxLength={12}
          />

          <Input
            label="Ticker"
            type="text"
            value={form.ticker}
            onChange={(e) => setForm({ ...form, ticker: e.target.value.toUpperCase() })}
            placeholder="ES: CSPX"
          />
        </div>

        <Input
          label="Nome Asset *"
          type="text"
          required
          value={form.name}
          onChange={(e) => setForm({ ...form, name: e.target.value })}
          placeholder="Es: iShares Core S&P 500 UCITS ETF"
        />

        <div className="grid grid-cols-2 gap-4">
          <Select
            label="Tipo Asset"
            value={form.asset_type}
            onChange={(e) => setForm({ ...form, asset_type: e.target.value as AssetFormData['asset_type'] })}
          >
            <option value="Azionario">Azionario</option>
            <option value="Obbligazionario">Obbligazionario</option>
            <option value="Monetario">Monetario</option>
            <option value="Oro">Oro</option>
            <option value="Crypto">Crypto</option>
            <option value="ETF">ETF</option>
            <option value="Azione Singola">Azione Singola</option>
            <option value="Obbligazione Singola">Obbligazione Singola</option>
          </Select>

          <Select
            label="Valuta"
            value={form.currency}
            onChange={(e) => setForm({ ...form, currency: e.target.value })}
          >
            <option value="EUR">EUR</option>
            <option value="USD">USD</option>
            <option value="GBP">GBP</option>
          </Select>
        </div>

        <div className="grid grid-cols-2 gap-4">
          <Input
            label="Settore"
            type="text"
            value={form.sector}
            onChange={(e) => setForm({ ...form, sector: e.target.value })}
            placeholder="Es: Tecnologia"
          />

          <Input
            label="Paese"
            type="text"
            value={form.country}
            onChange={(e) => setForm({ ...form, country: e.target.value })}
            placeholder="Es: USA"
          />
        </div>

        <div className="grid grid-cols-3 gap-4">
          <Input
            label="Sharpe Ratio"
            type="number"
            step="0.01"
            value={form.sharpe_ratio}
            onChange={(e) => setForm({ ...form, sharpe_ratio: parseFloat(e.target.value) || 0 })}
            placeholder="Es: 1.25"
          />

          <Input
            label="Commissioni Annue (%)"
            type="number"
            step="0.01"
            value={form.annual_fees}
            onChange={(e) => setForm({ ...form, annual_fees: parseFloat(e.target.value) || 0 })}
            placeholder="Es: 0.20"
          />

          <Input
            label="Deviazione Standard (%)"
            type="number"
            step="0.01"
            value={form.standard_deviation}
            onChange={(e) => setForm({ ...form, standard_deviation: parseFloat(e.target.value) || 0 })}
            placeholder="Es: 15.50"
          />
        </div>

        <div className="grid grid-cols-1 gap-4">
          <Select
            label="ISR - Indice Sintetico di Rischio (1-7)"
            value={form.isr}
            onChange={(e) => setForm({ ...form, isr: parseInt(e.target.value) })}
          >
            <option value="1">1 - Rischio Molto Basso</option>
            <option value="2">2 - Rischio Basso</option>
            <option value="3">3 - Rischio Medio-Basso</option>
            <option value="4">4 - Rischio Medio</option>
            <option value="5">5 - Rischio Medio-Alto</option>
            <option value="6">6 - Rischio Alto</option>
            <option value="7">7 - Rischio Molto Alto</option>
          </Select>
        </div>

        <Input
          label="Link Factsheet"
          type="url"
          value={form.factsheet_url}
          onChange={(e) => setForm({ ...form, factsheet_url: e.target.value })}
          placeholder="https://esempio.com/factsheet.pdf"
        />

        <div className="flex gap-3 justify-end pt-4">
          <Button type="button" variant="secondary" onClick={onClose}>
            Annulla
          </Button>
          <Button type="submit" variant="primary" icon={Save}>
            Salva Asset
          </Button>
        </div>
      </form>
    </Modal>
  );
};
