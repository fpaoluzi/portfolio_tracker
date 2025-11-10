'use client';

import { useState, useMemo } from 'react';
import { Edit2, Trash2, ExternalLink, RefreshCw, RefreshCcw, PenTool } from 'lucide-react';
import { fetchAndSaveComposition, bulkUpdateCompositions, deleteComposition } from '@/lib/api';
import { useToastContext } from '@/lib/context/ToastContext';
import { canHaveComposition } from '@/lib/utils/assetHelpers';
import { ManualCompositionForm } from './ManualCompositionForm';
import type { Asset } from '@/types';

interface AssetsListProps {
  assets: Asset[];
  onEdit: (asset: Asset) => void;
  onDelete: (asset: Asset) => void;
  onRefresh?: () => void;
}

export const AssetsList: React.FC<AssetsListProps> = ({ assets, onEdit, onDelete, onRefresh }) => {
  const toast = useToastContext();
  const [filter, setFilter] = useState('');
  const [sort, setSort] = useState<{ field: string; direction: 'asc' | 'desc' }>({
    field: 'name',
    direction: 'asc'
  });
  const [updatingComposition, setUpdatingComposition] = useState<string | null>(null);
  const [bulkUpdating, setBulkUpdating] = useState(false);
  const [conditionalUpdating, setConditionalUpdating] = useState(false);
  const [minUpdateDate, setMinUpdateDate] = useState<string>(() => {
    // Default: 30 giorni fa
    const date = new Date();
    date.setDate(date.getDate() - 30);
    return date.toISOString().split('T')[0];
  });
  const [manualCompositionAsset, setManualCompositionAsset] = useState<Asset | null>(null);

  const toggleSort = (field: string) => {
    setSort(prev => ({
      field,
      direction: prev.field === field && prev.direction === 'asc' ? 'desc' : 'asc'
    }));
  };

  const handleUpdateComposition = async (asset: Asset) => {
    if (!asset.isin) {
      toast.error(
        'ISIN mancante',
        'Questo asset non ha un ISIN valido. Impossibile aggiornare la composizione.'
      );
      return;
    }

    if (!confirm(`Aggiornare la composizione per ${asset.name}?\n\nQuesta operazione può richiedere 1-2 minuti.`)) {
      return;
    }

    setUpdatingComposition(asset.asset_id);

    // Mostra notifica di caricamento
    const loadingToastId = toast.loading(
      'Aggiornamento in corso',
      `Recupero composizione per ${asset.name}...`
    );

    try {
      const result = await fetchAndSaveComposition(asset.asset_id);

      // Rimuovi il toast di loading
      toast.dismissToast(loadingToastId);

      // 1. Controllo per risposte null/undefined
      if (!result) {
        toast.error(
          'Aggiornamento fallito',
          'Risposta inattesa o vuota dal server.'
        );
        return;
      }

      // 2. Verifica successo (presenza di 'stats')
      if (result.stats) {
        toast.success(
          'Composizione aggiornata!',
          `Holdings: ${result.stats.holdings} | Settori: ${result.stats.sectors} | Regioni: ${result.stats.regions} | Asset Classes: ${result.stats.allocation}`,
          7000
        );
        // Ricarica la lista degli asset per mostrare la data aggiornata
        if (onRefresh) {
          onRefresh();
        }
      }
      // 3. Verifica errore strutturato dal backend
      else if (typeof result === 'object' && 'error' in result) {
        const errorResult = result as any;
        toast.error(
          'Errore Backend',
          `${errorResult.error} - ${errorResult.details || 'Verifica i log del server.'}`,
          10000
        );
      }
      // 4. Gestione di risposte non strutturate
      else {
        toast.error(
          'Risposta inattesa',
          'Il risultato non ha la struttura attesa (né stats, né error).'
        );
      }

    } catch (error: any) {
      // Rimuovi il toast di loading in caso di errore
      toast.dismissToast(loadingToastId);

      console.error('Error updating composition:', error);
      toast.error(
        'Errore critico',
        `${error.message || 'Si è verificato un errore durante il recupero dei dati.'}`,
        10000
      );
    } finally {
      setUpdatingComposition(null);
    }
  };

  const handleConditionalUpdate = async () => {
    const minDate = new Date(minUpdateDate);

    // Filtra asset che necessitano aggiornamento
    const assetsToUpdate = filteredAndSortedAssets.filter(asset => {
      if (!asset.ticker) return false;

      // Se non ha mai avuto aggiornamento, deve essere aggiornato
      if (!asset.composition_last_updated) return true;

      // Se la data di aggiornamento è precedente alla data minima, deve essere aggiornato
      const lastUpdate = new Date(asset.composition_last_updated);
      return lastUpdate < minDate;
    });

    if (assetsToUpdate.length === 0) {
      toast.info(
        'Nessun aggiornamento necessario',
        `Tutti gli asset con ticker hanno composizione aggiornata dopo il ${new Date(minUpdateDate).toLocaleDateString('it-IT')}.`
      );
      return;
    }

    if (!confirm(
      `Aggiornare ${assetsToUpdate.length} asset con composizione mancante o obsoleta?\n\n` +
      `Criteri: mai aggiornato o aggiornato prima del ${new Date(minUpdateDate).toLocaleDateString('it-IT')}\n\n` +
      `L'operazione verrà eseguita in background e potrebbe richiedere diversi minuti.`
    )) {
      return;
    }

    setConditionalUpdating(true);

    // Mostra notifica di avvio
    const loadingToastId = toast.loading(
      'Avvio aggiornamento selettivo',
      `Inizializzazione per ${assetsToUpdate.length} asset obsoleti...`
    );

    try {
      // Aggiorna ogni asset sequenzialmente (potremmo fare batch nel backend in futuro)
      let successCount = 0;
      let errorCount = 0;

      for (const asset of assetsToUpdate) {
        try {
          await fetchAndSaveComposition(asset.asset_id);
          successCount++;
        } catch (error) {
          console.error(`Error updating ${asset.name}:`, error);
          errorCount++;
        }
      }

      toast.dismissToast(loadingToastId);

      if (successCount > 0) {
        toast.success(
          'Aggiornamento completato!',
          `${successCount} asset aggiornati con successo${errorCount > 0 ? `, ${errorCount} errori` : ''}.`,
          10000
        );
        // Ricarica la lista degli asset
        if (onRefresh) {
          onRefresh();
        }
      } else {
        toast.error(
          'Aggiornamento fallito',
          `Nessun asset è stato aggiornato. ${errorCount} errori.`
        );
      }
    } catch (error: any) {
      toast.dismissToast(loadingToastId);
      console.error('Error in conditional update:', error);
      toast.error(
        'Errore aggiornamento selettivo',
        error.message || 'Errore sconosciuto',
        10000
      );
    } finally {
      setConditionalUpdating(false);
    }
  };

  const handleBulkUpdate = async () => {
    const assetsWithTicker = filteredAndSortedAssets.filter(a => a.ticker);

    if (assetsWithTicker.length === 0) {
      toast.error(
        'Nessun asset disponibile',
        'Non ci sono asset con ticker valido per l\'aggiornamento.'
      );
      return;
    }

    if (!confirm(
      `Aggiornare la composizione per ${assetsWithTicker.length} asset?\n\n` +
      `L'operazione verrà eseguita in background e potrebbe richiedere diversi minuti.\n` +
      `Riceverai una notifica al completamento.`
    )) {
      return;
    }

    setBulkUpdating(true);

    // Mostra notifica di avvio
    const loadingToastId = toast.loading(
      'Avvio aggiornamento massivo',
      `Inizializzazione per ${assetsWithTicker.length} asset...`
    );

    try {
      const result = await bulkUpdateCompositions();

      toast.dismissToast(loadingToastId);

      if (result && result.success) {
        toast.success(
          'Aggiornamento massivo avviato!',
          `${result.assetsCount} asset verranno aggiornati in background. Puoi continuare a navigare.`,
          10000
        );
        // Ricarica la lista degli asset dopo l'avvio dell'aggiornamento massivo
        if (onRefresh) {
          onRefresh();
        }
      } else {
        toast.error(
          'Avvio fallito',
          'Risposta inattesa dal server durante l\'avvio dell\'aggiornamento massivo.'
        );
      }
    } catch (error: any) {
      toast.dismissToast(loadingToastId);
      console.error('Error in bulk update:', error);
      toast.error(
        'Errore avvio aggiornamento',
        error.message || 'Errore sconosciuto',
        10000
      );
    } finally {
      setBulkUpdating(false);
    }
  };

  const handleDeleteComposition = async (asset: Asset) => {
    if (!confirm(`Cancellare tutti i dati di composizione per ${asset.name}?\n\nQuesta azione è irreversibile.`)) {
      return;
    }

    try {
      const result = await deleteComposition(asset.asset_id);
      toast.success(
        'Composizione cancellata',
        `${result.deletedRecords.total} record rimossi con successo per ${asset.name}`
      );
      if (onRefresh) {
        onRefresh();
      }
    } catch (error: any) {
      toast.error('Errore cancellazione', error.message);
    }
  };

  const filteredAndSortedAssets = useMemo(() => {
    let filtered = assets.filter(asset =>
      asset.name.toLowerCase().includes(filter.toLowerCase()) ||
      asset.isin.toLowerCase().includes(filter.toLowerCase()) ||
      (asset.ticker && asset.ticker.toLowerCase().includes(filter.toLowerCase())) ||
      (asset.asset_type && asset.asset_type.toLowerCase().includes(filter.toLowerCase()))
    );

    return filtered.sort((a, b) => {
      // Nota: Ho aggiunto un controllo per prevenire errori se i valori non esistono o sono null/undefined
      const aVal = a[sort.field as keyof typeof a] || '';
      const bVal = b[sort.field as keyof typeof b] || '';
      const multiplier = sort.direction === 'asc' ? 1 : -1;

      if (typeof aVal === 'string' && typeof bVal === 'string') {
        return multiplier * aVal.localeCompare(bVal);
      }
      // Conversione a numero con fallback a 0 per un ordinamento sicuro
      return multiplier * (Number(aVal) - Number(bVal));
    });
  }, [assets, filter, sort]);

  // Calcola asset che necessitano aggiornamento
  const assetsNeedingUpdate = useMemo(() => {
    const minDate = new Date(minUpdateDate);
    return filteredAndSortedAssets.filter(asset => {
      if (!asset.ticker) return false;
      if (!asset.composition_last_updated) return true;
      const lastUpdate = new Date(asset.composition_last_updated);
      return lastUpdate < minDate;
    });
  }, [filteredAndSortedAssets, minUpdateDate]);

  return (
    <div className="bg-white/10 backdrop-blur-lg rounded-2xl border border-white/20 overflow-hidden">
      <div className="p-6 border-b border-white/20 space-y-4">
        <div className="flex justify-between items-start gap-4">
          <h2 className="text-xl font-bold text-white">
            Lista Asset ({filteredAndSortedAssets.length})
          </h2>
          <div className="flex flex-col gap-2">
            {/* Aggiornamento condizionale */}
            <div className="flex items-center gap-2">
              <label className="text-sm text-blue-200 whitespace-nowrap">
                Aggiorna se obsoleti dal:
              </label>
              <input
                type="date"
                value={minUpdateDate}
                onChange={(e) => setMinUpdateDate(e.target.value)}
                className="px-3 py-1 bg-white/10 border border-white/20 rounded text-white text-sm focus:outline-none focus:ring-2 focus:ring-blue-500"
              />
              <button
                onClick={handleConditionalUpdate}
                disabled={conditionalUpdating || filteredAndSortedAssets.filter(a => a.ticker).length === 0}
                className="flex items-center gap-2 px-3 py-1 bg-gradient-to-r from-blue-500 to-cyan-600 text-white rounded-lg text-sm font-medium hover:from-blue-600 hover:to-cyan-700 transition-all disabled:opacity-50 disabled:cursor-not-allowed"
                title="Aggiorna solo gli asset con composizione mancante o obsoleta"
              >
                <RefreshCw className={`w-4 h-4 ${conditionalUpdating ? 'animate-spin' : ''}`} />
                {conditionalUpdating ? 'Aggiornando...' : 'Aggiorna Obsoleti'}
              </button>
            </div>
            {/* Aggiornamento massivo */}
            <button
              onClick={handleBulkUpdate}
              disabled={bulkUpdating || filteredAndSortedAssets.filter(a => a.ticker).length === 0}
              className="flex items-center gap-2 px-4 py-2 bg-gradient-to-r from-green-500 to-emerald-600 text-white rounded-lg font-medium hover:from-green-600 hover:to-emerald-700 transition-all disabled:opacity-50 disabled:cursor-not-allowed"
              title="Aggiorna composizione per tutti gli asset"
            >
              <RefreshCcw className={`w-4 h-4 ${bulkUpdating ? 'animate-spin' : ''}`} />
              {bulkUpdating ? 'Avvio...' : 'Aggiorna Tutti'}
            </button>
          </div>
        </div>

        {/* Filtro */}
        <input
          type="text"
          placeholder="Cerca per nome, ISIN, ticker o tipo..."
          value={filter}
          onChange={(e) => setFilter(e.target.value)}
          className="w-full px-4 py-2 bg-white/10 border border-white/20 rounded-lg text-white placeholder-blue-300 focus:outline-none focus:ring-2 focus:ring-blue-500"
        />

        {/* Statistiche */}
        <div className="grid grid-cols-4 gap-4">
          <div className="bg-white/5 rounded-lg p-4">
            <div className="text-xs text-blue-300 mb-1">Totale Asset</div>
            <div className="text-lg font-bold text-white">{filteredAndSortedAssets.length}</div>
          </div>
          <div className="bg-white/5 rounded-lg p-4">
            <div className="text-xs text-blue-300 mb-1">Tipi Unici</div>
            <div className="text-lg font-bold text-white">
              {new Set(filteredAndSortedAssets.map(a => a.asset_type)).size}
            </div>
          </div>
          <div className="bg-white/5 rounded-lg p-4">
            <div className="text-xs text-blue-300 mb-1">Con Ticker</div>
            <div className="text-lg font-bold text-white">
              {filteredAndSortedAssets.filter(a => a.ticker).length}
            </div>
          </div>
          <div className={`bg-white/5 rounded-lg p-4 ${assetsNeedingUpdate.length > 0 ? 'ring-2 ring-yellow-500/50' : ''}`}>
            <div className="text-xs text-blue-300 mb-1">Da Aggiornare</div>
            <div className={`text-lg font-bold ${assetsNeedingUpdate.length > 0 ? 'text-yellow-400' : 'text-green-400'}`}>
              {assetsNeedingUpdate.length}
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
                onClick={() => toggleSort('isin')}
              >
                ISIN {sort.field === 'isin' && (sort.direction === 'asc' ? '▲' : '▼')}
              </th>
              <th
                className="px-6 py-3 text-left text-xs font-medium text-blue-200 uppercase cursor-pointer hover:text-white"
                onClick={() => toggleSort('name')}
              >
                Nome {sort.field === 'name' && (sort.direction === 'asc' ? '▲' : '▼')}
              </th>
              <th
                className="px-6 py-3 text-left text-xs font-medium text-blue-200 uppercase cursor-pointer hover:text-white"
                onClick={() => toggleSort('ticker')}
              >
                Ticker {sort.field === 'ticker' && (sort.direction === 'asc' ? '▲' : '▼')}
              </th>
              <th
                className="px-6 py-3 text-left text-xs font-medium text-blue-200 uppercase cursor-pointer hover:text-white"
                onClick={() => toggleSort('asset_type')}
              >
                Tipo {sort.field === 'asset_type' && (sort.direction === 'asc' ? '▲' : '▼')}
              </th>
              <th
                className="px-6 py-3 text-left text-xs font-medium text-blue-200 uppercase cursor-pointer hover:text-white"
                onClick={() => toggleSort('country')}
              >
                Paese {sort.field === 'country' && (sort.direction === 'asc' ? '▲' : '▼')}
              </th>
              <th
                className="px-6 py-3 text-left text-xs font-medium text-blue-200 uppercase cursor-pointer hover:text-white"
                onClick={() => toggleSort('sector')}
              >
                Settore {sort.field === 'sector' && (sort.direction === 'asc' ? '▲' : '▼')}
              </th>
              <th className="px-6 py-3 text-center text-xs font-medium text-blue-200 uppercase">
                Factsheet
              </th>
              <th className="px-6 py-3 text-center text-xs font-medium text-blue-200 uppercase">
                Composizione
              </th>
              <th className="px-6 py-3 text-right text-xs font-medium text-blue-200 uppercase">
                Azioni
              </th>
            </tr>
          </thead>
          <tbody className="divide-y divide-white/10">
            {filteredAndSortedAssets.map((asset) => (
              <tr
                key={asset.asset_id}
                className="hover:bg-white/5 transition-colors"
              >
                <td className="px-6 py-4 text-white font-mono text-sm">
                  {asset.isin}
                </td>
                <td className="px-6 py-4">
                  <div className="text-white font-medium">{asset.name}</div>
                  {asset.description && (
                    <div className="text-xs text-blue-300 mt-1">
                      {asset.description.substring(0, 50)}
                      {asset.description.length > 50 && '...'}
                    </div>
                  )}
                </td>
                <td className="px-6 py-4 text-white font-mono">
                  {asset.ticker || '-'}
                </td>
                <td className="px-6 py-4">
                  <span className="px-3 py-1 rounded-full text-xs font-medium bg-blue-500/20 text-blue-300">
                    {asset.asset_type}
                  </span>
                </td>
                <td className="px-6 py-4 text-white">{asset.country || '-'}</td>
                <td className="px-6 py-4 text-white">{asset.sector || '-'}</td>
                <td className="px-6 py-4 text-center">
                  {asset.factsheet_url ? (
                    <a
                      href={asset.factsheet_url}
                      target="_blank"
                      rel="noopener noreferrer"
                      className="inline-flex items-center gap-1 text-blue-400 hover:text-blue-300 transition-colors"
                      title="Apri Factsheet"
                    >
                      <ExternalLink className="w-4 h-4" />
                    </a>
                  ) : (
                    <span className="text-blue-300/30">-</span>
                  )}
                </td>
                <td className="px-6 py-4 text-center">
                  {asset.composition_last_updated ? (
                    <div className="text-xs">
                      <div className="text-green-400">
                        {new Date(asset.composition_last_updated).toLocaleDateString('it-IT')}
                      </div>
                      <div className="text-blue-300/70">
                        {new Date(asset.composition_last_updated).toLocaleTimeString('it-IT', {
                          hour: '2-digit',
                          minute: '2-digit'
                        })}
                      </div>
                    </div>
                  ) : (
                    <span className="text-blue-300/30 text-xs">Mai aggiornato</span>
                  )}
                </td>
                <td className="px-6 py-4 text-right">
                  <div className="flex gap-2 justify-end">
                    {asset.ticker && canHaveComposition(asset.asset_type) && (
                      <button
                        onClick={() => handleUpdateComposition(asset)}
                        disabled={updatingComposition === asset.asset_id}
                        className="p-2 hover:bg-green-500/20 rounded-lg transition-colors disabled:opacity-50 disabled:cursor-not-allowed"
                        title="Aggiorna composizione ETF da Yahoo Finance"
                      >
                        <RefreshCw className={`w-4 h-4 text-green-400 ${updatingComposition === asset.asset_id ? 'animate-spin' : ''}`} />
                      </button>
                    )}
                    {canHaveComposition(asset.asset_type) && (
                      <button
                        onClick={() => setManualCompositionAsset(asset)}
                        className="p-2 hover:bg-purple-500/20 rounded-lg transition-colors"
                        title="Inserimento manuale composizione"
                      >
                        <PenTool className="w-4 h-4 text-purple-400" />
                      </button>
                    )}
                    {canHaveComposition(asset.asset_type) && asset.composition_last_updated && (
                      <button
                        onClick={() => handleDeleteComposition(asset)}
                        className="p-2 hover:bg-orange-500/20 rounded-lg transition-colors"
                        title="Cancella dati composizione"
                      >
                        <Trash2 className="w-4 h-4 text-orange-400" />
                      </button>
                    )}
                    <button
                      onClick={() => onEdit(asset)}
                      className="p-2 hover:bg-blue-500/20 rounded-lg transition-colors"
                      title="Modifica asset"
                    >
                      <Edit2 className="w-4 h-4 text-blue-400" />
                    </button>
                    <button
                      onClick={() => onDelete(asset)}
                      className="p-2 hover:bg-red-500/20 rounded-lg transition-colors"
                      title="Elimina asset"
                    >
                      <Trash2 className="w-4 h-4 text-red-400" />
                    </button>
                  </div>
                </td>
              </tr>
            ))}
          </tbody>
        </table>
        {filteredAndSortedAssets.length === 0 && (
          <div className="text-center py-12">
            <p className="text-blue-200">
              {filter ? 'Nessun asset trovato con i criteri di ricerca' : 'Nessun asset trovato'}
            </p>
            <p className="text-sm text-blue-300 mt-2">
              {filter ? 'Prova a modificare i criteri di ricerca' : 'Clicca su "Nuovo Asset" per aggiungerne uno'}
            </p>
          </div>
        )}
      </div>

      {/* Manual Composition Form Modal */}
      {manualCompositionAsset && (
        <ManualCompositionForm
          asset={manualCompositionAsset}
          onClose={() => setManualCompositionAsset(null)}
          onSuccess={() => {
            if (onRefresh) {
              onRefresh();
            }
          }}
        />
      )}
    </div>
  );
};