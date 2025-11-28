import React, { useState, useEffect } from 'react';
import { SimulationResponse, AllocationCategory } from '../../../types/rebalancing';
import { apiClient } from '../../../lib/api/client';

interface ManualSimulationProps {
    portfolioId: string;
}

export const ManualSimulation: React.FC<ManualSimulationProps> = ({ portfolioId }) => {
    const [categories, setCategories] = useState<AllocationCategory[]>([]);
    const [selectedCategory, setSelectedCategory] = useState('');
    const [amount, setAmount] = useState('');
    const [result, setResult] = useState<SimulationResponse | null>(null);
    const [loading, setLoading] = useState(false);
    const [error, setError] = useState<string | null>(null);

    useEffect(() => {
        fetchCategories();
    }, [portfolioId]);

    const fetchCategories = async () => {
        try {
            const data = await apiClient.get<{ categories: AllocationCategory[] }>(`/rebalancing/${portfolioId}/categories`);
            setCategories(data.categories);
        } catch (err) {
            setError(err instanceof Error ? err.message : 'Errore sconosciuto');
        }
    };

    const handleSimulate = async () => {
        if (!selectedCategory) {
            setError('Seleziona una categoria');
            return;
        }

        const amountNum = parseFloat(amount);
        if (isNaN(amountNum) || amountNum === 0) {
            setError('Inserisci un importo valido diverso da 0');
            return;
        }

        try {
            setLoading(true);
            setError(null);

            const data = await apiClient.post<SimulationResponse>(`/rebalancing/${portfolioId}/simulate-transaction`, {
                category_name: selectedCategory,
                amount: amountNum,
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
        setSelectedCategory('');
        setAmount('');
        setResult(null);
        setError(null);
    };

    return (
        <div className="space-y-6">
            <div>
                <h3 className="text-xl font-semibold text-white mb-4">Simulazione Manuale Transazione</h3>
                <p className="text-gray-400 text-sm">
                    Simula l'impatto di un acquisto (importo positivo) o vendita (importo negativo) su una categoria specifica.
                </p>
            </div>

            <div className="bg-white/5 border border-white/10 rounded-lg p-6">
                <div className="grid grid-cols-1 md:grid-cols-2 gap-4 mb-4">
                    <div>
                        <label className="block text-sm font-medium text-gray-300 mb-2">
                            Categoria
                        </label>
                        <select
                            value={selectedCategory}
                            onChange={(e) => setSelectedCategory(e.target.value)}
                            className="w-full px-4 py-3 bg-white/10 border border-white/20 rounded-lg text-white focus:outline-none focus:ring-2 focus:ring-blue-500"
                        >
                            <option value="" className="bg-gray-800 text-white">Seleziona categoria...</option>
                            {categories.map((cat) => (
                                <option key={cat.category_id} value={cat.category_name} className="bg-gray-800 text-white">
                                    {cat.category_name}
                                </option>
                            ))}
                        </select>
                    </div>
                    <div>
                        <label className="block text-sm font-medium text-gray-300 mb-2">
                            Importo (€)
                            <span className="text-xs text-gray-400 ml-2">
                                (positivo = acquisto, negativo = vendita)
                            </span>
                        </label>
                        <input
                            type="number"
                            value={amount}
                            onChange={(e) => setAmount(e.target.value)}
                            placeholder="es. 500 o -500"
                            step="0.01"
                            className="w-full px-4 py-3 bg-white/10 border border-white/20 rounded-lg text-white text-lg placeholder-gray-400 focus:outline-none focus:ring-2 focus:ring-blue-500"
                        />
                    </div>
                </div>

                <div className="flex gap-2">
                    <button
                        onClick={handleSimulate}
                        disabled={loading || !selectedCategory || !amount}
                        className="px-6 py-3 bg-blue-600 hover:bg-blue-700 text-white rounded-lg transition-colors font-medium disabled:opacity-50 disabled:cursor-not-allowed"
                    >
                        {loading ? 'Simulazione...' : '🔮 Simula'}
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

                {error && (
                    <div className="mt-4 bg-red-500/10 border border-red-500/50 rounded-lg p-4 text-red-400">
                        {error}
                    </div>
                )}
            </div>

            {result && (
                <div className="space-y-6">
                    <div className="bg-blue-500/10 border border-blue-500/50 rounded-lg p-6">
                        <h4 className="text-lg font-semibold text-blue-400 mb-4">
                            📊 Riepilogo Simulazione
                        </h4>
                        <div className="grid grid-cols-1 md:grid-cols-3 gap-4">
                            <div>
                                <div className="text-sm text-gray-400 mb-1">Categoria</div>
                                <div className="text-xl font-bold text-white">{result.category_name}</div>
                            </div>
                            <div>
                                <div className="text-sm text-gray-400 mb-1">Importo Transazione</div>
                                <div className={`text-xl font-bold ${result.transaction_amount > 0 ? 'text-green-400' : 'text-red-400'
                                    }`}>
                                    {result.transaction_amount > 0 ? '+' : ''}€{result.transaction_amount.toLocaleString('it-IT', { minimumFractionDigits: 2 })}
                                </div>
                            </div>
                            <div>
                                <div className="text-sm text-gray-400 mb-1">Nuovo Valore Totale</div>
                                <div className="text-xl font-bold text-white">
                                    €{result.new_total_value.toLocaleString('it-IT', { minimumFractionDigits: 2 })}
                                </div>
                            </div>
                        </div>
                    </div>

                    <div className="bg-white/5 border border-white/10 rounded-lg p-6">
                        <h4 className="text-lg font-semibold text-white mb-4">
                            🔄 Confronto: Prima vs Dopo
                        </h4>
                        <div className="overflow-x-auto">
                            <table className="w-full">
                                <thead>
                                    <tr className="border-b border-white/20">
                                        <th className="text-left py-3 px-2 text-sm font-medium text-gray-300">Categoria</th>
                                        <th className="text-right py-3 px-2 text-sm font-medium text-gray-300">Target %</th>
                                        <th className="text-right py-3 px-2 text-sm font-medium text-gray-300">Attuale %</th>
                                        <th className="text-right py-3 px-2 text-sm font-medium text-gray-300">Nuova %</th>
                                        <th className="text-right py-3 px-2 text-sm font-medium text-gray-300">Variazione</th>
                                        <th className="text-right py-3 px-2 text-sm font-medium text-gray-300">Nuovo Drift</th>
                                    </tr>
                                </thead>
                                <tbody>
                                    {result.projected_allocations.map((allocation) => {
                                        const isTarget = allocation.category_name === result.category_name;
                                        return (
                                            <tr
                                                key={allocation.category_id}
                                                className={`border-b border-white/10 ${isTarget ? 'bg-blue-500/10' : ''}`}
                                            >
                                                <td className="py-3 px-2">
                                                    <div className="flex items-center space-x-2">
                                                        <div
                                                            className="w-3 h-3 rounded-full"
                                                            style={{ backgroundColor: allocation.color_hex }}
                                                        />
                                                        <span className={`${isTarget ? 'font-bold text-blue-400' : 'text-white'}`}>
                                                            {allocation.category_name}
                                                            {isTarget && ' ⭐'}
                                                        </span>
                                                    </div>
                                                </td>
                                                <td className="text-right py-3 px-2 text-blue-400">
                                                    {Number(allocation.target_percent).toFixed(2)}%
                                                </td>
                                                <td className="text-right py-3 px-2 text-gray-300">
                                                    {Number(allocation.current_percent).toFixed(2)}%
                                                </td>
                                                <td className="text-right py-3 px-2 text-white font-bold">
                                                    {Number(allocation.new_percent).toFixed(2)}%
                                                </td>
                                                <td className={`text-right py-3 px-2 font-medium ${Number(allocation.change_percent) > 0 ? 'text-green-400' :
                                                    Number(allocation.change_percent) < 0 ? 'text-red-400' :
                                                        'text-gray-400'
                                                    }`}>
                                                    {Number(allocation.change_percent) > 0 ? '+' : ''}{Number(allocation.change_percent).toFixed(2)}%
                                                </td>
                                                <td className={`text-right py-3 px-2 font-bold ${Math.abs(Number(allocation.new_drift_percent)) < 0.5 ? 'text-green-400' :
                                                    Math.abs(Number(allocation.new_drift_percent)) < 2 ? 'text-yellow-400' :
                                                        'text-red-400'
                                                    }`}>
                                                    {Number(allocation.new_drift_percent) > 0 ? '+' : ''}{Number(allocation.new_drift_percent).toFixed(2)}%
                                                </td>
                                            </tr>
                                        );
                                    })}
                                </tbody>
                            </table>
                        </div>
                    </div>

                    <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
                        <div className="bg-white/5 border border-white/10 rounded-lg p-4">
                            <h5 className="text-sm font-medium text-gray-300 mb-3">Valore Portafoglio</h5>
                            <div className="flex items-center justify-between">
                                <div>
                                    <div className="text-xs text-gray-400">Attuale</div>
                                    <div className="text-lg font-bold text-white">
                                        €{result.current_total_value.toLocaleString('it-IT', { minimumFractionDigits: 2 })}
                                    </div>
                                </div>
                                <div className="text-2xl text-gray-400">→</div>
                                <div>
                                    <div className="text-xs text-gray-400">Nuovo</div>
                                    <div className="text-lg font-bold text-blue-400">
                                        €{result.new_total_value.toLocaleString('it-IT', { minimumFractionDigits: 2 })}
                                    </div>
                                </div>
                            </div>
                        </div>

                        <div className="bg-white/5 border border-white/10 rounded-lg p-4">
                            <h5 className="text-sm font-medium text-gray-300 mb-3">Impatto</h5>
                            <div className="text-center">
                                <div className={`text-3xl font-bold ${result.transaction_amount > 0 ? 'text-green-400' : 'text-red-400'
                                    }`}>
                                    {result.transaction_amount > 0 ? '+' : ''}
                                    {((result.transaction_amount / result.current_total_value) * 100).toFixed(2)}%
                                </div>
                                <div className="text-xs text-gray-400 mt-1">
                                    {result.transaction_amount > 0 ? 'Incremento' : 'Decremento'} portafoglio
                                </div>
                            </div>
                        </div>
                    </div>

                    <div className="bg-white/5 border border-white/10 rounded-lg p-4 text-sm text-gray-400">
                        <p className="font-medium text-white mb-2">ℹ️ Nota:</p>
                        <p>
                            Questa è una simulazione pura. Nessuna transazione viene eseguita.
                            Usa questi dati per capire come una potenziale operazione influenzerebbe il bilanciamento del tuo portafoglio
                            prima di procedere con l'acquisto o la vendita reale.
                        </p>
                    </div>
                </div>
            )}
        </div>
    );
};
