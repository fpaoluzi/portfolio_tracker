import React from 'react';
import { RiskStats } from '../utils/types';
import { TrendingUp, Activity, Target } from 'lucide-react';

interface RiskStatsSectionProps {
    riskStats: RiskStats | null;
}

export const RiskStatsSection: React.FC<RiskStatsSectionProps> = ({ riskStats }) => {
    if (!riskStats) {
        return (
            <div className="text-center text-gray-400 py-8">
                Nessun dato disponibile per le statistiche di rischio
            </div>
        );
    }

    return (
        <div className="space-y-6">
            {/* Summary Cards */}
            <div className="grid grid-cols-1 md:grid-cols-3 gap-4">
                <div className="bg-gradient-to-br from-blue-500/20 to-cyan-500/20 backdrop-blur-lg rounded-xl border border-blue-400/30 p-6">
                    <div className="flex items-center gap-3 mb-2">
                        <TrendingUp className="w-6 h-6 text-blue-400" />
                        <h4 className="text-sm font-medium text-gray-300">ISR Medio</h4>
                    </div>
                    <div className="text-3xl font-bold text-white">
                        {riskStats.isr !== null ? riskStats.isr.toFixed(2) : 'N/A'}
                    </div>
                </div>

                <div className="bg-gradient-to-br from-purple-500/20 to-pink-500/20 backdrop-blur-lg rounded-xl border border-purple-400/30 p-6">
                    <div className="flex items-center gap-3 mb-2">
                        <Activity className="w-6 h-6 text-purple-400" />
                        <h4 className="text-sm font-medium text-gray-300">Deviazione Standard</h4>
                    </div>
                    <div className="text-3xl font-bold text-white">
                        {riskStats.standard_deviation !== null ? `${riskStats.standard_deviation.toFixed(2)}%` : 'N/A'}
                    </div>
                </div>

                <div className="bg-gradient-to-br from-green-500/20 to-emerald-500/20 backdrop-blur-lg rounded-xl border border-green-400/30 p-6">
                    <div className="flex items-center gap-3 mb-2">
                        <Target className="w-6 h-6 text-green-400" />
                        <h4 className="text-sm font-medium text-gray-300">Sharpe Ratio</h4>
                    </div>
                    <div className="text-3xl font-bold text-white">
                        {riskStats.sharpe_ratio !== null ? riskStats.sharpe_ratio.toFixed(2) : 'N/A'}
                    </div>
                </div>
            </div>

            {/* Details Table */}
            <div className="bg-white/10 backdrop-blur-lg rounded-2xl border border-white/20 p-6">
                <h3 className="text-xl font-bold text-white mb-4">Dettaglio per Asset</h3>
                <div className="overflow-x-auto">
                    <table className="w-full">
                        <thead>
                            <tr className="border-b border-white/20">
                                <th className="text-left py-3 px-2 text-sm font-medium text-gray-300">Asset</th>
                                <th className="text-left py-3 px-2 text-sm font-medium text-gray-300">Ticker</th>
                                <th className="text-right py-3 px-2 text-sm font-medium text-gray-300">ISR</th>
                                <th className="text-right py-3 px-2 text-sm font-medium text-gray-300">Std Dev</th>
                                <th className="text-right py-3 px-2 text-sm font-medium text-gray-300">Sharpe</th>
                                <th className="text-right py-3 px-2 text-sm font-medium text-gray-300">Peso %</th>
                            </tr>
                        </thead>
                        <tbody>
                            {riskStats.details.map((detail, index) => (
                                <tr key={index} className="border-b border-white/10">
                                    <td className="py-3 px-2 text-sm text-white">{detail.asset_name}</td>
                                    <td className="py-3 px-2 text-sm text-gray-400">{detail.ticker || 'N/A'}</td>
                                    <td className="py-3 px-2 text-sm text-right text-white">
                                        {detail.isr !== null ? detail.isr.toFixed(2) : 'N/A'}
                                    </td>
                                    <td className="py-3 px-2 text-sm text-right text-white">
                                        {detail.standard_deviation !== null ? `${detail.standard_deviation.toFixed(2)}%` : 'N/A'}
                                    </td>
                                    <td className="py-3 px-2 text-sm text-right text-white">
                                        {detail.sharpe_ratio !== null ? detail.sharpe_ratio.toFixed(2) : 'N/A'}
                                    </td>
                                    <td className="py-3 px-2 text-sm text-right font-medium text-blue-400">
                                        {detail.weight_percent.toFixed(2)}%
                                    </td>
                                </tr>
                            ))}
                            {riskStats.details.length > 0 && (
                                <tr className="border-t-2 border-blue-500 bg-blue-500/10">
                                    <td className="py-3 px-2 text-sm font-bold text-white" colSpan={2}>Media Ponderata</td>
                                    <td className="py-3 px-2 text-sm text-right font-bold text-blue-300">
                                        {riskStats.isr !== null ? riskStats.isr.toFixed(2) : 'N/A'}
                                    </td>
                                    <td className="py-3 px-2 text-sm text-right font-bold text-blue-300">
                                        {riskStats.standard_deviation !== null ? `${riskStats.standard_deviation.toFixed(2)}%` : 'N/A'}
                                    </td>
                                    <td className="py-3 px-2 text-sm text-right font-bold text-blue-300">
                                        {riskStats.sharpe_ratio !== null ? riskStats.sharpe_ratio.toFixed(2) : 'N/A'}
                                    </td>
                                    <td className="py-3 px-2 text-sm text-right font-bold text-blue-300">100.00%</td>
                                </tr>
                            )}
                        </tbody>
                    </table>
                </div>
            </div>
        </div>
    );
};
