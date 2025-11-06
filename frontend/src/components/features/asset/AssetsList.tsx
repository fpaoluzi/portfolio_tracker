'use client';

import { useState, useMemo } from 'react';
import { Edit2, Trash2, ExternalLink } from 'lucide-react';
import { Button } from '@/components/ui';
import type { Asset } from '@/types';

interface AssetsListProps {
  assets: Asset[];
  onEdit: (asset: Asset) => void;
  onDelete: (asset: Asset) => void;
}

export const AssetsList: React.FC<AssetsListProps> = ({ assets, onEdit, onDelete }) => {
  const [filter, setFilter] = useState('');
  const [sort, setSort] = useState<{ field: string; direction: 'asc' | 'desc' }>({
    field: 'name',
    direction: 'asc'
  });

  const toggleSort = (field: string) => {
    setSort(prev => ({
      field,
      direction: prev.field === field && prev.direction === 'asc' ? 'desc' : 'asc'
    }));
  };

  const filteredAndSortedAssets = useMemo(() => {
    let filtered = assets.filter(asset =>
      asset.name.toLowerCase().includes(filter.toLowerCase()) ||
      asset.isin.toLowerCase().includes(filter.toLowerCase()) ||
      (asset.ticker && asset.ticker.toLowerCase().includes(filter.toLowerCase())) ||
      (asset.asset_type && asset.asset_type.toLowerCase().includes(filter.toLowerCase()))
    );

    return filtered.sort((a, b) => {
      const aVal = a[sort.field as keyof typeof a];
      const bVal = b[sort.field as keyof typeof b];
      const multiplier = sort.direction === 'asc' ? 1 : -1;

      if (typeof aVal === 'string' && typeof bVal === 'string') {
        return multiplier * aVal.localeCompare(bVal);
      }
      return multiplier * (Number(aVal) - Number(bVal));
    });
  }, [assets, filter, sort]);

  return (
    <div className="bg-white/10 backdrop-blur-lg rounded-2xl border border-white/20 overflow-hidden">
      <div className="p-6 border-b border-white/20 space-y-4">
        <h2 className="text-xl font-bold text-white">
          Lista Asset ({filteredAndSortedAssets.length})
        </h2>

        {/* Filtro */}
        <input
          type="text"
          placeholder="Cerca per nome, ISIN, ticker o tipo..."
          value={filter}
          onChange={(e) => setFilter(e.target.value)}
          className="w-full px-4 py-2 bg-white/10 border border-white/20 rounded-lg text-white placeholder-blue-300 focus:outline-none focus:ring-2 focus:ring-blue-500"
        />

        {/* Statistiche */}
        <div className="grid grid-cols-3 gap-4">
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
                <td className="px-6 py-4 text-right">
                  <div className="flex gap-2 justify-end">
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
    </div>
  );
};
