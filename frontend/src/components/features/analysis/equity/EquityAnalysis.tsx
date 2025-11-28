import React, { useState } from 'react';
import { PortfolioComposition, RiskStats } from '../utils/types';
import { HoldingsSection } from './HoldingsSection';
import { SectorsSection } from './SectorsSection';
import { GeographySection } from './GeographySection';
import { AllocationSection } from './AllocationSection';
import { RiskStatsSection } from './RiskStatsSection';

type EquityTab = 'holdings' | 'sectors' | 'regions' | 'allocation' | 'riskStats';

interface EquityAnalysisProps {
    composition: PortfolioComposition | null;
    riskStats: RiskStats | null;
}

export const EquityAnalysis: React.FC<EquityAnalysisProps> = ({ composition, riskStats }) => {
    const [activeTab, setActiveTab] = useState<EquityTab>('holdings');

    if (!composition) {
        return (
            <div className="text-center text-gray-400 py-8">
                Seleziona uno o più asset per visualizzare l'analisi
            </div>
        );
    }

    const tabs: { id: EquityTab; label: string; count?: number }[] = [
        { id: 'holdings', label: 'Top Holdings', count: composition.holdings?.length },
        { id: 'sectors', label: 'Settori', count: composition.sectors?.length },
        { id: 'regions', label: 'Geografia', count: composition.regions?.length },
        { id: 'allocation', label: 'Asset Allocation', count: composition.allocation?.length },
        { id: 'riskStats', label: 'Statistiche Rischio' },
    ];

    return (
        <div className="space-y-6">
            {/* Tab Navigation */}
            <div className="flex flex-wrap gap-2 bg-white/5 p-2 rounded-xl">
                {tabs.map((tab) => (
                    <button
                        key={tab.id}
                        onClick={() => setActiveTab(tab.id)}
                        className={`px-4 py-2 font-medium transition-colors ${activeTab === tab.id
                                ? 'bg-blue-500 text-white'
                                : 'bg-white/10 text-gray-300 hover:bg-white/20'
                            } rounded-lg`}
                    >
                        {tab.label}
                        {tab.count !== undefined && ` (${tab.count})`}
                    </button>
                ))}
            </div>

            {/* Tab Content */}
            <div>
                {activeTab === 'holdings' && <HoldingsSection holdings={composition.holdings} />}
                {activeTab === 'sectors' && <SectorsSection sectors={composition.sectors} />}
                {activeTab === 'regions' && <GeographySection regions={composition.regions} />}
                {activeTab === 'allocation' && <AllocationSection allocation={composition.allocation} />}
                {activeTab === 'riskStats' && <RiskStatsSection riskStats={riskStats} />}
            </div>
        </div>
    );
};
