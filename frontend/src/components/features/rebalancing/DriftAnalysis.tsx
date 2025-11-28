import React, { useState, useEffect } from 'react';
import { DriftAnalysisResponse, DriftAnalysis as DriftData } from '../../../types/rebalancing';
import { apiClient } from '../../../lib/api/client';

interface DriftAnalysisProps {
    portfolioId: string;
    refreshTrigger?: number;
    onFixAllocation?: () => void;
}

export const DriftAnalysis: React.FC<DriftAnalysisProps> = ({ portfolioId, refreshTrigger, onFixAllocation }) => {
    const [driftData, setDriftData] = useState<DriftAnalysisResponse | null>(null);
    const [loading, setLoading] = useState(false);
    const [error, setError] = useState<string | null>(null);

    useEffect(() => {
        fetchDriftAnalysis();
    }, [portfolioId, refreshTrigger]);

    const fetchDriftAnalysis = async () => {
        try {
            setLoading(true);
            const data = await apiClient.get<DriftAnalysisResponse>(`/rebalancing/${portfolioId}/drift-analysis`);
            setDriftData(data);
            setError(null);
        } catch (err) {
            setError(err instanceof Error ? err.message : 'Errore sconosciuto');
        } finally {
            setLoading(false);
        }
    };

    const getStatusIcon = (status: string) => {
        switch (status) {
            case 'balanced':
                return '🟢';
            case 'overweight':
                return '🔴';
            case 'underweight':
                return '🟡';
            default:
                return '⚪';
        }
    };

    const getStatusLabel = (status: string) => {
        switch (status) {
            case 'balanced':
                return 'Bilanciata';
            case 'overweight':
                return 'Sovrappesata';
            case 'underweight':
                return 'Sottopesata';
            default:
                return 'N/A';
        }
    };

    const getStatusColor = (status: string) => {
        switch (status) {
            case 'balanced':
                return 'text-green-400';
            case 'overweight':
                return 'text-red-400';
            case 'underweight':
                return 'text-yellow-400';
            default:
                return 'text-gray-400';
        }
    };

    if (loading) {
        return (
            <div className="flex items-center justify-center py-12">
                <div className="text-gray-400">Caricamento analisi...</div>
            </div>
        );
    }

    if (error) {
        const isAllocationError = error.includes('must equal 100%') || error.includes('allocation');
        return (
            <div className="bg-red-500/10 border border-red-500/50 rounded-lg p-6">
                <div className="flex items-start space-x-3">
                    <span className="text-2xl">⚠️</span>
                    <div className="flex-1">
                        <h4 className="text-red-400 font-semibold mb-2">Errore nell'analisi</h4>
                        <p className="text-red-300 mb-4">{error}</p>
                        {isAllocationError && onFixAllocation && (
                            <button
                                onClick={onFixAllocation}
                                className="px-4 py-2 bg-blue-600 hover:bg-blue-700 text-white rounded-lg transition-colors font-medium"
                            >
                                📋 Vai alle Categorie per Correggere
                            </button>
                        )}
                    </div>
                </div>
            </div>
        );
    }

    if (!driftData || driftData.categories.length === 0) {
        return (
            <div className="text-center py-12 text-gray-400">
                <p className="text-lg">Nessuna categoria definita</p>
                <p className="text-sm mt-2">Definisci le categorie di allocazione per vedere l'analisi</p>
            </div>
        );
    }

    const sortedCategories = [...driftData.categories].sort(
        (a, b) => Math.abs(Number(b.drift_percent)) - Math.abs(Number(a.drift_percent))
    );

    return (
        <div className="space-y-6">
            <div className="flex items-center justify-between">
                <h3 className="text-xl font-semibold text-white">Verifica rispetto allocazione attuale</h3>
                <button
                    onClick={fetchDriftAnalysis}
                    className="px-4 py-2 bg-blue-600 hover:bg-blue-700 text-white rounded-lg transition-colors"
                >
                    🔄 Aggiorna
                </button>
            </div>

            {driftData.warning && (
                <div className="bg-yellow-500/10 border border-yellow-500/50 rounded-lg p-4">
                    <div className="flex items-start space-x-3">
                        <span className="text-2xl">⚠️</span>
                        <div className="flex-1">
                            <h4 className="text-yellow-400 font-semibold mb-1">Attenzione</h4>
                            <p className="text-yellow-300 text-sm">{driftData.warning}</p>
                            <p className="text-yellow-200 text-xs mt-2">
                                I calcoli di drift sono comunque visualizzati, ma potrebbero non essere accurati.
                                Si consiglia di correggere le allocazioni per ottenere risultati precisi.
                            </p>
                        </div>
                    </div>
                </div>
            )}

            <div className="bg-white/5 border border-white/10 rounded-lg p-6">
                <div className="flex items-center justify-between mb-2">
                    <span className="text-gray-300">Valore Totale Portafoglio:</span>
                    <span className="text-2xl font-bold text-white">
                        €{driftData.totalValue.toLocaleString('it-IT', { minimumFractionDigits: 2, maximumFractionDigits: 2 })}
                    </span>
                </div>
            </div>

            <div className="overflow-x-auto">
                <table className="w-full">
                    <thead>
                        <tr className="border-b border-white/20">
                            <th className="text-left py-3 px-2 text-sm font-medium text-gray-300">Categoria</th>
                            <th className="text-right py-3 px-2 text-sm font-medium text-gray-300">Target %</th>
                            <th className="text-right py-3 px-2 text-sm font-medium text-gray-300">Attuale %</th>
                            <th className="text-right py-3 px-2 text-sm font-medium text-gray-300">Valore €</th>
                            <th className="text-right py-3 px-2 text-sm font-medium text-gray-300">Drift %</th>
                            <th className="text-right py-3 px-2 text-sm font-medium text-gray-300">Delta €</th>
                            <th className="text-center py-3 px-2 text-sm font-medium text-gray-300">Stato</th>
                        </tr>
                    </thead>
                    <tbody>
                        {sortedCategories.map((category) => (
                            <tr key={category.category_id} className="border-b border-white/10 hover:bg-white/5">
                                <td className="py-3 px-2">
                                    <div className="flex items-center space-x-2">
                                        <div
                                            className="w-3 h-3 rounded-full"
                                            style={{ backgroundColor: category.color_hex }}
                                        />
                                        <span className="text-white font-medium">{category.category_name}</span>
                                    </div>
                                </td>
                                <td className="text-right py-3 px-2 text-blue-400 font-medium">
                                    {Number(category.target_percent).toFixed(2)}%
                                </td>
                                <td className="text-right py-3 px-2 text-white font-medium">
                                    {Number(category.current_percent).toFixed(2)}%
                                </td>
                                <td className="text-right py-3 px-2 text-gray-300">
                                    €{category.current_value.toLocaleString('it-IT', { minimumFractionDigits: 2 })}
                                </td>
                                <td className={`text-right py-3 px-2 font-bold ${Number(category.drift_percent) > 0 ? 'text-red-400' :
                                    Number(category.drift_percent) < 0 ? 'text-yellow-400' :
                                        'text-green-400'
                                    }`}>
                                    {Number(category.drift_percent) > 0 ? '+' : ''}{Number(category.drift_percent).toFixed(2)}%
                                </td>
                                <td className={`text-right py-3 px-2 font-medium ${category.drift_value > 0 ? 'text-red-400' :
                                    category.drift_value < 0 ? 'text-yellow-400' :
                                        'text-green-400'
                                    }`}>
                                    {category.drift_value > 0 ? '+' : ''}€{category.drift_value.toLocaleString('it-IT', { minimumFractionDigits: 2 })}
                                </td>
                                <td className="text-center py-3 px-2">
                                    <div className="flex items-center justify-center space-x-2">
                                        <span>{getStatusIcon(category.status)}</span>
                                        <span className={`text-sm font-medium ${getStatusColor(category.status)}`}>
                                            {getStatusLabel(category.status)}
                                        </span>
                                    </div>
                                </td>
                            </tr>
                        ))}
                    </tbody>
                </table>
            </div>

            <div className="grid grid-cols-1 md:grid-cols-3 gap-4">
                <div className="bg-green-500/10 border border-green-500/50 rounded-lg p-4">
                    <div className="text-green-400 text-sm font-medium mb-1">Bilanciate</div>
                    <div className="text-2xl font-bold text-white">
                        {driftData.categories.filter(c => c.status === 'balanced').length}
                    </div>
                </div>
                <div className="bg-red-500/10 border border-red-500/50 rounded-lg p-4">
                    <div className="text-red-400 text-sm font-medium mb-1">Sovrappesate</div>
                    <div className="text-2xl font-bold text-white">
                        {driftData.categories.filter(c => c.status === 'overweight').length}
                    </div>
                </div>
                <div className="bg-yellow-500/10 border border-yellow-500/50 rounded-lg p-4">
                    <div className="text-yellow-400 text-sm font-medium mb-1">Sottopesate</div>
                    <div className="text-2xl font-bold text-white">
                        {driftData.categories.filter(c => c.status === 'underweight').length}
                    </div>
                </div>
            </div>

            <div className="bg-white/5 border border-white/10 rounded-lg p-4 text-sm text-gray-400">
                <p className="font-medium text-white mb-2">📊 Legenda:</p>
                <ul className="space-y-1">
                    <li><strong className="text-blue-400">Target %:</strong> Percentuale obiettivo definita</li>
                    <li><strong className="text-white">Attuale %:</strong> Percentuale attuale nel portafoglio</li>
                    <li><strong className="text-yellow-400">Drift %:</strong> Differenza tra attuale e target (positivo = sovrappesata, negativo = sottopesata)</li>
                    <li><strong className="text-green-400">Delta €:</strong> Valore in euro da aggiungere/rimuovere per raggiungere il target</li>
                </ul>
            </div>
        </div>
    );
};
