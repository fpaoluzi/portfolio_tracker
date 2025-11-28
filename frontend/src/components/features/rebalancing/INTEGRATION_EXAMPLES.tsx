/**
 * ESEMPIO DI INTEGRAZIONE - RebalancingDashboard
 * 
 * Questo file mostra come integrare il modulo di Asset Allocation
 * nell'applicazione esistente.
 */

import React, { useState } from 'react';
import { RebalancingDashboard } from './components/features/rebalancing';

/**
 * Esempio 1: Integrazione in una pagina dedicata
 */
export const RebalancingPage: React.FC = () => {
    const [selectedPortfolioId, setSelectedPortfolioId] = useState<string>('');
    const [portfolios, setPortfolios] = useState<any[]>([]);

    // Carica portfolios all'avvio
    React.useEffect(() => {
        fetch('/api/portfolios')
            .then(res => res.json())
            .then(data => {
                setPortfolios(data);
                if (data.length > 0) {
                    setSelectedPortfolioId(data[0].portfolio_id);
                }
            });
    }, []);

    return (
        <div className="min-h-screen bg-gray-900 p-6">
            <div className="max-w-7xl mx-auto">
                {/* Selettore Portfolio */}
                <div className="mb-6">
                    <label className="block text-sm font-medium text-gray-300 mb-2">
                        Seleziona Portafoglio
                    </label>
                    <select
                        value={selectedPortfolioId}
                        onChange={(e) => setSelectedPortfolioId(e.target.value)}
                        className="px-4 py-2 bg-white/10 border border-white/20 rounded-lg text-white"
                    >
                        {portfolios.map((p) => (
                            <option key={p.portfolio_id} value={p.portfolio_id}>
                                {p.name}
                            </option>
                        ))}
                    </select>
                </div>

                {/* Dashboard Ribilanciamento */}
                {selectedPortfolioId && (
                    <RebalancingDashboard portfolioId={selectedPortfolioId} />
                )}
            </div>
        </div>
    );
};

/**
 * Esempio 2: Integrazione come tab in PortfolioAnalysis esistente
 */
export const PortfolioAnalysisWithRebalancing: React.FC<{ portfolioId: string }> = ({
    portfolioId
}) => {
    const [activeTab, setActiveTab] = useState<'analysis' | 'rebalancing'>('analysis');

    return (
        <div>
            {/* Tabs */}
            <div className="flex border-b border-white/10 mb-6">
                <button
                    onClick={() => setActiveTab('analysis')}
                    className={`px-6 py-3 ${activeTab === 'analysis'
                            ? 'border-b-2 border-blue-500 text-white'
                            : 'text-gray-400'
                        }`}
                >
                    📊 Analisi Composizione
                </button>
                <button
                    onClick={() => setActiveTab('rebalancing')}
                    className={`px-6 py-3 ${activeTab === 'rebalancing'
                            ? 'border-b-2 border-blue-500 text-white'
                            : 'text-gray-400'
                        }`}
                >
                    🎯 Ribilanciamento
                </button>
            </div>

            {/* Content */}
            {activeTab === 'analysis' && (
                <div>{/* Componente PortfolioAnalysis esistente */}</div>
            )}
            {activeTab === 'rebalancing' && (
                <RebalancingDashboard portfolioId={portfolioId} />
            )}
        </div>
    );
};

/**
 * Esempio 3: Utilizzo dei singoli componenti
 */
import {
    AllocationManager,
    DriftAnalysis,
    SmartDeposit,
    ManualSimulation
} from './components/features/rebalancing';

export const CustomRebalancingView: React.FC<{ portfolioId: string }> = ({
    portfolioId
}) => {
    return (
        <div className="space-y-8">
            {/* Solo Health Check */}
            <DriftAnalysis portfolioId={portfolioId} />

            {/* Solo Smart Deposit */}
            <SmartDeposit portfolioId={portfolioId} />

            {/* Oppure tutti separati */}
            <AllocationManager portfolioId={portfolioId} />
            <ManualSimulation portfolioId={portfolioId} />
        </div>
    );
};

/**
 * ROUTE SETUP (se usi React Router)
 */
/*
import { BrowserRouter, Routes, Route } from 'react-router-dom';

<Routes>
  <Route path="/portfolios/:id/rebalancing" element={<RebalancingPage />} />
</Routes>
*/
