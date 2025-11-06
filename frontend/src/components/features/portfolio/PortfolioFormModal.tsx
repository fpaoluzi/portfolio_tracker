'use client';

import { useState, FormEvent } from 'react';
import { Save } from 'lucide-react';
import { Modal, Button, Input, Select, Textarea } from '@/components/ui';
import { portfoliosApi } from '@/lib/api';
import type { PortfolioFormData } from '@/types';

interface PortfolioFormModalProps {
  onClose: () => void;
  onSuccess: () => void;
}

export const PortfolioFormModal: React.FC<PortfolioFormModalProps> = ({ onClose, onSuccess }) => {
  const [form, setForm] = useState<PortfolioFormData>({
    name: '',
    broker: '',
    currency: 'EUR',
    notes: '',
  });

  const handleSubmit = async (e: FormEvent) => {
    e.preventDefault();
    try {
      await portfoliosApi.create(form);
      onSuccess();
      onClose();
    } catch (error) {
      console.error('Error creating portfolio:', error);
      alert('Errore nella creazione del portafoglio');
    }
  };

  return (
    <Modal title="Nuovo Portafoglio" onClose={onClose}>
      <form onSubmit={handleSubmit} className="space-y-4">
        <Input
          label="Nome Portafoglio *"
          type="text"
          required
          value={form.name}
          onChange={(e) => setForm({ ...form, name: e.target.value })}
          placeholder="Es: Portafoglio Principale"
        />

        <Input
          label="Broker"
          type="text"
          value={form.broker}
          onChange={(e) => setForm({ ...form, broker: e.target.value })}
          placeholder="Es: FinecoBank"
        />

        <Select
          label="Valuta"
          value={form.currency}
          onChange={(e) => setForm({ ...form, currency: e.target.value })}
        >
          <option value="EUR">EUR</option>
          <option value="USD">USD</option>
          <option value="GBP">GBP</option>
        </Select>

        <Textarea
          label="Note"
          value={form.notes}
          onChange={(e) => setForm({ ...form, notes: e.target.value })}
          rows={3}
          placeholder="Note aggiuntive..."
        />

        <div className="flex gap-3 justify-end pt-4">
          <Button type="button" variant="secondary" onClick={onClose}>
            Annulla
          </Button>
          <Button type="submit" variant="primary" icon={Save}>
            Salva Portafoglio
          </Button>
        </div>
      </form>
    </Modal>
  );
};
