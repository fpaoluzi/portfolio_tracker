import React, { useState } from 'react';
import { SmartDepositResponse } from '../../../types/rebalancing';
import { apiClient } from '../../../lib/api/client';

interface SmartDepositProps {
    portfolioId: string;
}

export const SmartDeposit: React.FC<SmartDepositProps> = ({ portfolioId }) => {
    const [depositAmount, setDepositAmount] = useState('');
    const [result, setResult] = useState<SmartDepositResponse | null>(null);
    const [loading, setLoading] = useState(false);
    const [error, setError] = useState<string | null>(null);

    const handleCalculate = async () => {
        const amount = parseFloat(depositAmount);
        if (isNaN(amount) || amount <= 0) {
            setError('Inserisci un importo valido maggiore di 0');
            return;
        }

        try {
            setLoading(true);
            setError(null);

            const data = await apiClient.post<SmartDepositResponse>(`/rebalancing/${portfolioId}/smart-deposit`, {
                amount
            });

            setResult(data);
        } catch (err) {
            setError(err instanceof Error ? err.message : 'Errore sconosciuto');
            setResult(null);
        } finally {
            setLoading(false);
        }
    };

    const handleReset = () => {
        setDepositAmount('');
        setResult(null);
        setError(null);
    };

    return (
        <div className="space-y-6">
            <div>
                <h3 className="text-xl font-semibold text-white mb-4">Smart Deposit - Allocazione Intelligente</h3>
                <p className="text-gray-400 text-sm">
                    Inserisci l'importo di nuova liquidità e ricevi suggerimenti su come investirla per minimizzare lo scostamento dal target.
                </p>
            </div>

            <div className="bg-white/5 border border-white/10 rounded-lg p-6">
                <div className="flex flex-col md:flex-row gap-4">
                    <div className="flex-1">
                        <label className="block text-sm font-medium text-gray-300 mb-2">
                            Importo da Investire (€)
                        </label>
                        <input
                            type="number"
                            value={depositAmount}
                            onChange={(e) => setDepositAmount(e.target.value)}
                            placeholder="es. 1000"
                            min="0"
                            step="0.01"
                            className="w-full px-4 py-3 bg-white/10 border border-white/20 rounded-lg text-white text-lg placeholder-gray-400 focus:outline-none focus:ring-2 focus:ring-blue-500"
                        />
                    </div>
                    <div className="flex items-end gap-2">
                        <button
                            onClick={handleCalculate}
                            disabled={loading || !depositAmount}
                            className="px-6 py-3 bg-blue-600 hover:bg-blue-700 text-white rounded-lg transition-colors font-medium disabled:opacity-50 disabled:cursor-not-allowed"
                        >
                            {loading ? 'Calcolo...' : '🧮 Calcola'}
                        </button>
                        {result && (
                            <button
                                onClick={handleReset}
                                className="px-6 py-3 bg-gray-600 hover:bg-gray-700 text-white rounded-lg transition-colors font-medium"
                            >
                                Reset
                            </button>
                        )}
                    </div>
                </div>

                {error && (
                    <div className="mt-4 bg-red-500/10 border border-red-500/50 rounded-lg p-4 text-red-400">
                        {error}
                    </div>
                )}
            </div>

            {result && (
                <div className="space-y-6">
                    <div className="bg-green-500/10 border border-green-500/50 rounded-lg p-6">
                        <h4 className="text-lg font-semibold text-green-400 mb-4">
                            💡 Suggerimenti di Allocazione
                        </h4>
                        <div className="space-y-3">
                            {result.allocations.map((allocation, index) => (
                                <div
                                    key={allocation.category_id}
                                    className="bg-white/5 border border-white/10 rounded-lg p-4"
                                >
                                    <div className="flex items-center justify-between mb-2">
                                        <div className="flex items-center space-x-3">
                                            <div className="bg-blue-600 text-white w-8 h-8 rounded-full flex items-center justify-center font-bold">
                                                {index + 1}
                                            </div>
                                            <div>
                                                <h5 className="text-white font-medium text-lg">{allocation.category_name}</h5>
                                                <p className="text-sm text-gray-400">{allocation.reason}</p>
                                            </div>
                                        </div>
                                        <div className="text-right">
                                            <p className="text-2xl font-bold text-green-400">
                                                €{allocation.amount.toLocaleString('it-IT', { minimumFractionDigits: 2 })}
                                            </p>
                                            <p className="text-xs text-gray-400">
                                                {((allocation.amount / result.deposit_amount) * 100).toFixed(1)}% del deposito
                                            </p>
                                        </div>
                                    </div>
                                    <div className="mt-3 grid grid-cols-2 gap-4 text-sm">
                                        <div>
                                            <span className="text-gray-400">Valore attuale:</span>
                                            <span className="ml-2 text-white">
                                                €{allocation.current_value.toLocaleString('it-IT', { minimumFractionDigits: 2 })}
                                            </span>
                                        </div>
                                        <div>
                                            <span className="text-gray-400">Nuovo valore:</span>
                                            <span className="ml-2 text-green-400 font-medium">
                                                €{allocation.new_value.toLocaleString('it-IT', { minimumFractionDigits: 2 })}
                                            </span>
                                        </div>
                                    </div>
                                </div>
                            ))}
                        </div>
                    </div>

                    <div className="bg-white/5 border border-white/10 rounded-lg p-6">
                        <h4 className="text-lg font-semibold text-white mb-4">
                            📈 Drift Previsto Dopo Allocazione
                        </h4>
                        <div className="overflow-x-auto">
                            <table className="w-full">
                                <thead>
                                    <tr className="border-b border-white/20">
                                        <th className="text-left py-2 px-2 text-sm font-medium text-gray-300">Categoria</th>
                                        <th className="text-right py-2 px-2 text-sm font-medium text-gray-300">Target %</th>
                                        <th className="text-right py-2 px-2 text-sm font-medium text-gray-300">Nuovo %</th>
                                        <th className="text-right py-2 px-2 text-sm font-medium text-gray-300">Nuovo Drift</th>
                                    </tr>
                                </thead>
                                <tbody>
                                    {result.projected_drift.map((category) => (
                                        <tr key={category.category_id} className="border-b border-white/10">
                                            <td className="py-2 px-2 text-white">{category.category_name}</td>
                                            <td className="text-right py-2 px-2 text-blue-400">
                                                {Number(category.target_percent).toFixed(2)}%
                                            </td>
                                            <td className="text-right py-2 px-2 text-white font-medium">
                                                {Number(category.new_percent).toFixed(2)}%
                                            </td>
                                            <td className={`text-right py-2 px-2 font-bold ${Math.abs(Number(category.new_drift_percent)) < 0.5 ? 'text-green-400' :
                                                Math.abs(Number(category.new_drift_percent)) < 2 ? 'text-yellow-400' :
                                                    'text-red-400'
                                                }`}>
                                                {Number(category.new_drift_percent) > 0 ? '+' : ''}{Number(category.new_drift_percent).toFixed(2)}%
                                            </td>
                                        </tr>
                                    ))}
                                </tbody>
                            </table>
                        </div>
                    </div>

                    <div className="bg-blue-500/10 border border-blue-500/50 rounded-lg p-4">
                        <div className="flex items-center justify-between">
                            <span className="text-blue-400 font-medium">Nuovo Valore Totale Portafoglio:</span>
                            <span className="text-2xl font-bold text-white">
                                €{result.new_total_value.toLocaleString('it-IT', { minimumFractionDigits: 2 })}
                            </span>
                        </div>
                    </div>

                    <div className="bg-white/5 border border-white/10 rounded-lg p-4 text-sm text-gray-400">
                        <p className="font-medium text-white mb-2">ℹ️ Nota:</p>
                        <p>
                            Questi sono suggerimenti di allocazione basati sull'algoritmo greedy che prioritizza le categorie più sottopesate.
                            Questa è una simulazione: non vengono eseguiti acquisti automatici.
                            Usa questi dati per prendere decisioni informate sui tuoi investimenti.
                        </p>
                    </div>
                </div>
            )}
        </div>
    );
};
