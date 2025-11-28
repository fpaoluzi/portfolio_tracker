import React, { useState, useEffect } from 'react';
import { AllocationCategory, CategoriesResponse } from '../../../types/rebalancing';
import { apiClient } from '../../../lib/api/client';

interface AllocationManagerProps {
    portfolioId: string;
    onCategoriesChange?: () => void;
}

export const AllocationManager: React.FC<AllocationManagerProps> = ({
    portfolioId,
    onCategoriesChange
}) => {
    const [categories, setCategories] = useState<AllocationCategory[]>([]);
    const [validation, setValidation] = useState<{ isValid: boolean; total: number; error: string | null }>({
        isValid: true,
        total: 0,
        error: null,
    });
    const [loading, setLoading] = useState(false);
    const [error, setError] = useState<string | null>(null);
    const [isAdding, setIsAdding] = useState(false);
    const [editingId, setEditingId] = useState<string | null>(null);
    const [newCategory, setNewCategory] = useState({
        category_name: '',
        target_percent: '',
        color_hex: '#3B82F6',
    });
    const [editCategory, setEditCategory] = useState({
        category_name: '',
        target_percent: '',
        color_hex: '#3B82F6',
    });

    useEffect(() => {
        fetchCategories();
    }, [portfolioId]);

    const fetchCategories = async () => {
        try {
            setLoading(true);
            const data = await apiClient.get<CategoriesResponse>(`/rebalancing/${portfolioId}/categories`);
            setCategories(data.categories);
            setValidation(data.validation);
            setError(null);
        } catch (err) {
            setError(err instanceof Error ? err.message : 'Errore sconosciuto');
        } finally {
            setLoading(false);
        }
    };

    const handleAddCategory = async () => {
        const percent = parseFloat(newCategory.target_percent);
        if (!newCategory.category_name || isNaN(percent) || percent < 0 || percent > 100) {
            setError('Nome obbligatorio e percentuale deve essere un numero tra 0 e 100');
            return;
        }

        try {
            setLoading(true);
            await apiClient.post(`/rebalancing/${portfolioId}/categories`, {
                category_name: newCategory.category_name,
                target_percent: parseFloat(newCategory.target_percent),
                color_hex: newCategory.color_hex,
            });

            setNewCategory({ category_name: '', target_percent: '', color_hex: '#3B82F6' });
            setIsAdding(false);
            await fetchCategories();
            onCategoriesChange?.();
        } catch (err) {
            setError(err instanceof Error ? err.message : 'Errore sconosciuto');
        } finally {
            setLoading(false);
        }
    };

    const handleDeleteCategory = async (categoryId: string) => {
        if (!confirm('Sei sicuro di voler eliminare questa categoria?')) return;

        try {
            setLoading(true);
            await apiClient.delete(`/rebalancing/${portfolioId}/categories/${categoryId}`);

            await fetchCategories();
            onCategoriesChange?.();
        } catch (err) {
            setError(err instanceof Error ? err.message : 'Errore sconosciuto');
        } finally {
            setLoading(false);
        }
    };

    const handleEditCategory = async (categoryId: string) => {
        const percent = parseFloat(editCategory.target_percent);
        if (!editCategory.category_name || isNaN(percent) || percent < 0 || percent > 100) {
            setError('Nome obbligatorio e percentuale deve essere un numero tra 0 e 100');
            return;
        }

        try {
            setLoading(true);
            await apiClient.put(`/rebalancing/${portfolioId}/categories/${categoryId}`, {
                category_name: editCategory.category_name,
                target_percent: parseFloat(editCategory.target_percent),
                color_hex: editCategory.color_hex,
            });

            setEditingId(null);
            await fetchCategories();
            onCategoriesChange?.();
        } catch (err) {
            setError(err instanceof Error ? err.message : 'Errore sconosciuto');
        } finally {
            setLoading(false);
        }
    };

    const startEditing = (category: AllocationCategory) => {
        setEditingId(category.category_id);
        setEditCategory({
            category_name: category.category_name,
            target_percent: String(category.target_percent),
            color_hex: category.color_hex,
        });
        setIsAdding(false);
    };

    const cancelEditing = () => {
        setEditingId(null);
        setEditCategory({ category_name: '', target_percent: '', color_hex: '#3B82F6' });
    };

    const getRemainingPercent = () => {
        const total = categories.reduce((sum, cat) => sum + Number(cat.target_percent), 0);
        const newPercent = parseFloat(newCategory.target_percent) || 0;
        return 100 - total - newPercent;
    };

    return (
        <div className="space-y-6">
            <div className="flex items-center justify-between">
                <h3 className="text-xl font-semibold text-white">Categorie di Allocazione</h3>
                <button
                    onClick={() => setIsAdding(!isAdding)}
                    className="px-4 py-2 bg-blue-600 hover:bg-blue-700 text-white rounded-lg transition-colors"
                    disabled={loading}
                >
                    {isAdding ? 'Annulla' : '+ Aggiungi Categoria'}
                </button>
            </div>

            {error && (
                <div className="bg-red-500/10 border border-red-500/50 rounded-lg p-4 text-red-400">
                    {error}
                </div>
            )}

            {!validation.isValid && (
                <div className="bg-yellow-500/10 border border-yellow-500/50 rounded-lg p-4 text-yellow-400">
                    ⚠️ {validation.error}
                </div>
            )}

            {isAdding && (
                <div className="bg-white/5 border border-white/10 rounded-lg p-6">
                    <h4 className="text-lg font-medium text-white mb-4">Nuova Categoria</h4>
                    <div className="grid grid-cols-1 md:grid-cols-3 gap-4">
                        <div>
                            <label className="block text-sm font-medium text-gray-300 mb-2">
                                Nome Categoria
                            </label>
                            <input
                                type="text"
                                value={newCategory.category_name}
                                onChange={(e) => setNewCategory({ ...newCategory, category_name: e.target.value })}
                                placeholder="es. Azionario, Bitcoin, Oro"
                                className="w-full px-3 py-2 bg-white/10 border border-white/20 rounded-lg text-white placeholder-gray-400 focus:outline-none focus:ring-2 focus:ring-blue-500"
                            />
                        </div>
                        <div>
                            <label className="block text-sm font-medium text-gray-300 mb-2">
                                Percentuale Target (%)
                            </label>
                            <input
                                type="number"
                                value={newCategory.target_percent}
                                onChange={(e) => setNewCategory({ ...newCategory, target_percent: e.target.value })}
                                placeholder="0-100"
                                min="0"
                                max="100"
                                step="0.01"
                                className="w-full px-3 py-2 bg-white/10 border border-white/20 rounded-lg text-white placeholder-gray-400 focus:outline-none focus:ring-2 focus:ring-blue-500"
                            />
                            <p className="text-xs text-gray-400 mt-1">
                                Rimanente: {getRemainingPercent().toFixed(2)}%
                            </p>
                        </div>
                        <div>
                            <label className="block text-sm font-medium text-gray-300 mb-2">
                                Colore
                            </label>
                            <input
                                type="color"
                                value={newCategory.color_hex}
                                onChange={(e) => setNewCategory({ ...newCategory, color_hex: e.target.value })}
                                className="w-full h-10 bg-white/10 border border-white/20 rounded-lg cursor-pointer"
                            />
                        </div>
                    </div>
                    <div className="mt-4 flex justify-end">
                        <button
                            onClick={handleAddCategory}
                            disabled={loading || !newCategory.category_name || !newCategory.target_percent}
                            className="px-6 py-2 bg-green-600 hover:bg-green-700 text-white rounded-lg transition-colors disabled:opacity-50 disabled:cursor-not-allowed"
                        >
                            Salva Categoria
                        </button>
                    </div>
                </div>
            )}

            <div className="space-y-3">
                {categories.length === 0 ? (
                    <div className="text-center py-12 text-gray-400">
                        <p className="text-lg">Nessuna categoria definita</p>
                        <p className="text-sm mt-2">Aggiungi categorie per iniziare a simulare il ribilanciamento</p>
                    </div>
                ) : (
                    categories.map((category) => (
                        <div
                            key={category.category_id}
                            className="bg-white/5 border border-white/10 rounded-lg p-4 hover:bg-white/10 transition-colors"
                        >
                            {editingId === category.category_id ? (
                                // Edit mode
                                <div className="space-y-4">
                                    <div className="grid grid-cols-1 md:grid-cols-3 gap-4">
                                        <div>
                                            <label className="block text-sm font-medium text-gray-300 mb-2">
                                                Nome Categoria
                                            </label>
                                            <input
                                                type="text"
                                                value={editCategory.category_name}
                                                onChange={(e) => setEditCategory({ ...editCategory, category_name: e.target.value })}
                                                className="w-full px-3 py-2 bg-white/10 border border-white/20 rounded-lg text-white placeholder-gray-400 focus:outline-none focus:ring-2 focus:ring-blue-500"
                                            />
                                        </div>
                                        <div>
                                            <label className="block text-sm font-medium text-gray-300 mb-2">
                                                Percentuale Target (%)
                                            </label>
                                            <input
                                                type="number"
                                                value={editCategory.target_percent}
                                                onChange={(e) => setEditCategory({ ...editCategory, target_percent: e.target.value })}
                                                min="0"
                                                max="100"
                                                step="0.01"
                                                className="w-full px-3 py-2 bg-white/10 border border-white/20 rounded-lg text-white placeholder-gray-400 focus:outline-none focus:ring-2 focus:ring-blue-500"
                                            />
                                        </div>
                                        <div>
                                            <label className="block text-sm font-medium text-gray-300 mb-2">
                                                Colore
                                            </label>
                                            <input
                                                type="color"
                                                value={editCategory.color_hex}
                                                onChange={(e) => setEditCategory({ ...editCategory, color_hex: e.target.value })}
                                                className="w-full h-10 bg-white/10 border border-white/20 rounded-lg cursor-pointer"
                                            />
                                        </div>
                                    </div>
                                    <div className="flex justify-end gap-2">
                                        <button
                                            onClick={cancelEditing}
                                            className="px-4 py-2 bg-gray-600 hover:bg-gray-700 text-white rounded-lg transition-colors"
                                        >
                                            Annulla
                                        </button>
                                        <button
                                            onClick={() => handleEditCategory(category.category_id)}
                                            disabled={loading}
                                            className="px-4 py-2 bg-green-600 hover:bg-green-700 text-white rounded-lg transition-colors disabled:opacity-50 disabled:cursor-not-allowed"
                                        >
                                            Salva
                                        </button>
                                    </div>
                                </div>
                            ) : (
                                // View mode
                                <div className="flex items-center justify-between">
                                    <div className="flex items-center space-x-4 flex-1">
                                        <div
                                            className="w-4 h-4 rounded-full"
                                            style={{ backgroundColor: category.color_hex }}
                                        />
                                        <div className="flex-1">
                                            <h4 className="text-white font-medium">{category.category_name}</h4>
                                        </div>
                                        <div className="text-right">
                                            <p className="text-2xl font-bold text-blue-400">
                                                {Number(category.target_percent).toFixed(2)}%
                                            </p>
                                            <p className="text-xs text-gray-400">Target</p>
                                        </div>
                                    </div>
                                    <div className="flex gap-2 ml-4">
                                        <button
                                            onClick={() => startEditing(category)}
                                            className="px-3 py-1 bg-blue-600/20 hover:bg-blue-600/40 text-blue-400 rounded transition-colors"
                                            disabled={loading}
                                        >
                                            ✏️ Modifica
                                        </button>
                                        <button
                                            onClick={() => handleDeleteCategory(category.category_id)}
                                            className="px-3 py-1 bg-red-600/20 hover:bg-red-600/40 text-red-400 rounded transition-colors"
                                            disabled={loading}
                                        >
                                            🗑️ Elimina
                                        </button>
                                    </div>
                                </div>
                            )}
                            <div className="mt-3">
                                <div className="w-full bg-white/10 rounded-full h-2">
                                    <div
                                        className="h-2 rounded-full transition-all"
                                        style={{
                                            width: `${category.target_percent}%`,
                                            backgroundColor: category.color_hex,
                                        }}
                                    />
                                </div>
                            </div>
                        </div>
                    ))
                )}
            </div>

            {
                categories.length > 0 && (
                    <div className="bg-blue-500/10 border border-blue-500/50 rounded-lg p-4">
                        <div className="flex items-center justify-between">
                            <span className="text-blue-400 font-medium">Totale Allocazione:</span>
                            <span className={`text-2xl font-bold ${validation.isValid ? 'text-green-400' : 'text-red-400'}`}>
                                {validation.total.toFixed(2)}%
                            </span>
                        </div>
                        {validation.isValid && (
                            <p className="text-sm text-green-400 mt-2">✓ Allocazione valida</p>
                        )}
                    </div>
                )
            }

            <div className="bg-white/5 border border-white/10 rounded-lg p-4 text-sm text-gray-400">
                <p className="font-medium text-white mb-2">ℹ️ Nota:</p>
                <p>
                    Le categorie definiscono i tuoi obiettivi di allocazione per la simulazione.
                    La somma delle percentuali deve essere esattamente 100%.
                    Queste impostazioni non modificano il tuo portafoglio reale.
                </p>
            </div>
        </div >
    );
};
