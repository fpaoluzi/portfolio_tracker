import React, { useState } from 'react';
import { PortfolioComposition, RiskStats } from '../utils/types';
import { BondSectorsSection } from './BondSectorsSection';
import { BondGeographySection } from './BondGeographySection';
import { BondAllocationSection } from './BondAllocationSection';
import { BondRatingsSection } from './BondRatingsSection';
import { BondMaturitySection } from './BondMaturitySection';
import { BondRiskStatsSection } from './BondRiskStatsSection';

type BondTab = 'sectors' | 'regions' | 'allocation' | 'bondRatings' | 'bondMaturity' | 'riskStats';

interface BondAnalysisProps {
    composition: PortfolioComposition | null;
    riskStats: RiskStats | null;
}

export const BondAnalysis: React.FC<BondAnalysisProps> = ({ composition, riskStats }) => {
    const [activeTab, setActiveTab] = useState<BondTab>('sectors');

    if (!composition) {
        return (
            <div className="text-center text-gray-400 py-8">
                Seleziona uno o più asset per visualizzare l'analisi
            </div>
        );
    }

    const tabs: { id: BondTab; label: string; count?: number }[] = [
        { id: 'sectors', label: 'Settori', count: composition.sectors?.length },
        { id: 'regions', label: 'Geografia', count: composition.regions?.length },
        { id: 'allocation', label: 'Asset Allocation', count: composition.allocation?.length },
        { id: 'bondRatings', label: 'Rating', count: composition.bondRatings?.length },
        { id: 'bondMaturity', label: 'Maturity', count: composition.bondMaturity?.length },
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
                {activeTab === 'sectors' && <BondSectorsSection sectors={composition.sectors} />}
                {activeTab === 'regions' && <BondGeographySection regions={composition.regions} />}
                {activeTab === 'allocation' && <BondAllocationSection allocation={composition.allocation} />}
                {activeTab === 'bondRatings' && <BondRatingsSection bondRatings={composition.bondRatings} />}
                {activeTab === 'bondMaturity' && <BondMaturitySection bondMaturity={composition.bondMaturity} />}
                {activeTab === 'riskStats' && <BondRiskStatsSection riskStats={riskStats} />}
            </div>
        </div>
    );
};
