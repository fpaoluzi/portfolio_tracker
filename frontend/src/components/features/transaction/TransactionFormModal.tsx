'use client';

import { useState, useEffect, FormEvent } from 'react';
import { Save } from 'lucide-react';
import { Modal, Button, Input, Select } from '@/components/ui';
import { transactionsApi } from '@/lib/api';
import { formatCurrency } from '@/lib/utils/format';
import type { Asset, TransactionFormData } from '@/types';

interface TransactionFormModalProps {
  portfolioId: string;
  assets: Asset[];
  transaction?: any | null;
  onClose: () => void;
  onSuccess: () => void;
}

export const TransactionFormModal: React.FC<TransactionFormModalProps> = ({
  portfolioId,
  assets,
  transaction,
  onClose,
  onSuccess,
}) => {
  const [form, setForm] = useState<TransactionFormData>({
    asset_id: '',
    transaction_type: 'BUY',
    transaction_date: new Date().toISOString().split('T')[0],
    quantity: 0,
    price_per_share: 0,
    commission: 0,
    fees: 0,
    notes: '',
  });

  useEffect(() => {
    if (transaction) {
      setForm({
        asset_id: transaction.asset_id?.toString() || '',
        transaction_type: transaction.transaction_type || 'BUY',
        transaction_date: transaction.transaction_date?.split('T')[0] || new Date().toISOString().split('T')[0],
        quantity: transaction.quantity || 0,
        price_per_share: transaction.price_per_share || 0,
        commission: transaction.commission || 0,
        fees: transaction.fees || 0,
        notes: transaction.notes || '',
      });
    }
  }, [transaction]);

  const totalAmount =
    form.quantity * form.price_per_share + form.commission + form.fees;

  const handleSubmit = async (e: FormEvent) => {
    e.preventDefault();
    try {
      if (transaction) {
        await transactionsApi.update(transaction.transaction_id, {
          ...form,
          portfolio_id: portfolioId,
        });
      } else {
        await transactionsApi.create({
          ...form,
          portfolio_id: portfolioId,
        });
      }
      onSuccess();
      onClose();
    } catch (error) {
      console.error('Error saving transaction:', error);
      alert(`Errore nel ${transaction ? 'aggiornamento' : 'creazione'} della transazione`);
    }
  };

  return (
    <Modal title={transaction ? 'Modifica Transazione' : 'Nuova Transazione'} onClose={onClose}>
      <form onSubmit={handleSubmit} className="space-y-4">
        <Select
          label="Asset *"
          required
          value={form.asset_id}
          onChange={(e) => setForm({ ...form, asset_id: e.target.value })}
        >
          <option value="">Seleziona asset...</option>
          {assets.map((asset) => (
            <option key={asset.asset_id} value={asset.asset_id}>
              {asset.name} ({asset.isin})
            </option>
          ))}
        </Select>

        <div className="grid grid-cols-2 gap-4">
          <Select
            label="Tipo"
            value={form.transaction_type}
            onChange={(e) =>
              setForm({
                ...form,
                transaction_type: e.target.value as 'BUY' | 'SELL',
              })
            }
          >
            <option value="BUY">ACQUISTO</option>
            <option value="SELL">VENDITA</option>
          </Select>

          <Input
            label="Data *"
            type="date"
            required
            value={form.transaction_date}
            onChange={(e) =>
              setForm({ ...form, transaction_date: e.target.value })
            }
          />
        </div>

        <div className="grid grid-cols-2 gap-4">
          <Input
            label="Quantità *"
            type="number"
            required
            step="0.000001"
            value={form.quantity}
            onChange={(e) =>
              setForm({ ...form, quantity: parseFloat(e.target.value) || 0 })
            }
            placeholder="0.00"
          />

          <Input
            label="Prezzo *"
            type="number"
            required
            step="0.01"
            value={form.price_per_share}
            onChange={(e) =>
              setForm({
                ...form,
                price_per_share: parseFloat(e.target.value) || 0,
              })
            }
            placeholder="0.00"
          />
        </div>

        <div className="grid grid-cols-2 gap-4">
          <Input
            label="Commissioni"
            type="number"
            step="0.01"
            value={form.commission}
            onChange={(e) =>
              setForm({ ...form, commission: parseFloat(e.target.value) || 0 })
            }
            placeholder="0.00"
          />

          <Input
            label="Spese"
            type="number"
            step="0.01"
            value={form.fees}
            onChange={(e) =>
              setForm({ ...form, fees: parseFloat(e.target.value) || 0 })
            }
            placeholder="0.00"
          />
        </div>

        <div className="bg-blue-500/10 border border-blue-400/30 rounded-lg p-4">
          <div className="text-sm text-blue-200 mb-1">Totale operazione</div>
          <div className="text-2xl font-bold text-white">
            {formatCurrency(totalAmount)}
          </div>
        </div>

        <div className="flex gap-3 justify-end pt-4">
          <Button type="button" variant="secondary" onClick={onClose}>
            Annulla
          </Button>
          <Button type="submit" variant="primary" icon={Save}>
            Salva Transazione
          </Button>
        </div>
      </form>
    </Modal>
  );
};
