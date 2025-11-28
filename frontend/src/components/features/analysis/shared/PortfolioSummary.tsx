import React from 'react';
import { RiskStats } from '../utils/types';

interface PortfolioSummaryProps {
    riskStats: RiskStats | null;
    selectedPortfolioId: string | null;
}

/**
 * Portfolio Summary Component
 * Shows total value of selected assets and their weights in the portfolio
 */
export const PortfolioSummary: React.FC<PortfolioSummaryProps> = ({
    riskStats,
    selectedPortfolioId,
}) => {
    // Debug logging
    console.log('PortfolioSummary render:', {
        selectedPortfolioId,
        hasRiskStats: !!riskStats,
        riskStats,
        detailsLength: riskStats?.details?.length
    });

    if (!selectedPortfolioId || !riskStats || !riskStats.details || riskStats.details.length === 0) {
        console.log('PortfolioSummary: Not rendering because:', {
            noPortfolio: !selectedPortfolioId,
            noRiskStats: !riskStats,
            noDetails: !riskStats?.details,
            emptyDetails: riskStats?.details?.length === 0
        });
        return null;
    }

    return (
        <div className="bg-gradient-to-br from-blue-500/20 to-purple-500/20 backdrop-blur-lg rounded-2xl border border-blue-400/30 p-6 mb-6">
            <h3 className="text-xl font-bold text-white mb-4">📊 Riepilogo Selezione</h3>
            <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
                <div className="bg-white/5 rounded-lg p-4">
                    <div className="text-sm text-gray-300 mb-1">Valore Totale Asset Selezionati</div>
                    <div className="text-2xl font-bold text-blue-300">
                        {new Intl.NumberFormat('it-IT', { style: 'currency', currency: 'EUR' }).format(riskStats.total_value)}
                    </div>
                </div>
                <div className="bg-white/5 rounded-lg p-4">
                    <div className="text-sm text-gray-300 mb-2">Peso nel Portafoglio</div>
                    <div className="space-y-2">
                        {riskStats.details.map((detail, idx) => (
                            <div key={idx} className="flex justify-between items-center">
                                <span className="text-white text-sm">{detail.asset_name}</span>
                                <span className="text-blue-300 font-bold">{detail.weight_percent.toFixed(2)}%</span>
                            </div>
                        ))}
                    </div>
                </div>
            </div>
        </div>
    );
};
