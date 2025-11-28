import React, { useState } from 'react';
import { AllocationManager } from './AllocationManager';
import { DriftAnalysis } from './DriftAnalysis';
import { SmartDeposit } from './SmartDeposit';
import { ManualSimulation } from './ManualSimulation';

interface RebalancingDashboardProps {
    portfolioId: string;
}

type TabType = 'categories' | 'drift' | 'smart-deposit' | 'simulation';

export const RebalancingDashboard: React.FC<RebalancingDashboardProps> = ({ portfolioId }) => {
    const [activeTab, setActiveTab] = useState<TabType>('categories');
    const [refreshTrigger, setRefreshTrigger] = useState(0);

    const handleCategoriesChange = () => {
        setRefreshTrigger((prev) => prev + 1);
    };

    const tabs = [
        { id: 'categories' as TabType, label: '⚙️ Categorie', icon: '⚙️' },
        { id: 'drift' as TabType, label: '📈 Verifica rispetto allocazione attuale', icon: '📈' },
        { id: 'smart-deposit' as TabType, label: '💰 Smart Deposit', icon: '💰' },
        { id: 'simulation' as TabType, label: '🎯 Simulazione', icon: '🎯' },
    ];

    return (
        <div className="space-y-6">
            <div className="bg-gradient-to-r from-blue-600/20 to-purple-600/20 border border-blue-500/30 rounded-lg p-6">
                <h2 className="text-2xl font-bold text-white mb-2">
                    🎯 Asset Allocation & Ribilanciamento
                </h2>
                <p className="text-gray-300">
                    Sistema di simulazione per gestire l'allocazione del portafoglio e pianificare il ribilanciamento.
                    Tutte le funzionalità sono puramente informative e non modificano i dati reali del portafoglio.
                </p>
            </div>

            <div className="bg-white/5 border border-white/10 rounded-lg overflow-hidden">
                <div className="flex border-b border-white/10 overflow-x-auto">
                    {tabs.map((tab) => (
                        <button
                            key={tab.id}
                            onClick={() => setActiveTab(tab.id)}
                            className={`flex-1 min-w-[150px] px-6 py-4 text-sm font-medium transition-colors ${activeTab === tab.id
                                ? 'bg-blue-600 text-white border-b-2 border-blue-400'
                                : 'text-gray-400 hover:text-white hover:bg-white/5'
                                }`}
                        >
                            <span className="mr-2">{tab.icon}</span>
                            {tab.label}
                        </button>
                    ))}
                </div>

                <div className="p-6">
                    {activeTab === 'categories' && (
                        <AllocationManager
                            portfolioId={portfolioId}
                            onCategoriesChange={handleCategoriesChange}
                        />
                    )}
                    {activeTab === 'drift' && (
                        <DriftAnalysis
                            portfolioId={portfolioId}
                            refreshTrigger={refreshTrigger}
                            onFixAllocation={() => setActiveTab('categories')}
                        />
                    )}
                    {activeTab === 'smart-deposit' && (
                        <SmartDeposit portfolioId={portfolioId} />
                    )}
                    {activeTab === 'simulation' && (
                        <ManualSimulation portfolioId={portfolioId} />
                    )}
                </div>
            </div>

            <div className="bg-yellow-500/10 border border-yellow-500/50 rounded-lg p-4">
                <div className="flex items-start space-x-3">
                    <span className="text-2xl">⚠️</span>
                    <div className="flex-1">
                        <h4 className="text-yellow-400 font-semibold mb-2">Sistema di Simulazione</h4>
                        <p className="text-sm text-gray-300">
                            Questo modulo è completamente simulativo. Nessuna delle funzionalità modifica le tue posizioni reali,
                            esegue transazioni o altera i dati del portafoglio. Usa queste informazioni per prendere decisioni
                            informate sui tuoi investimenti, ma ricorda che dovrai eseguire manualmente le operazioni tramite il tuo broker.
                        </p>
                    </div>
                </div>
            </div>
        </div>
    );
};
