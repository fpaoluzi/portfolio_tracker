import React from 'react';
import { ResponsiveContainer, BarChart, CartesianGrid, XAxis, YAxis, Tooltip, Bar, Cell, LabelList } from 'recharts';
import { AggregatedHolding } from '../utils/types';
import { COLORS, CustomLabel } from '../utils/chartHelpers';
import { isAltriVariation, filterAndSumAltri } from '../utils/altriNormalization';
import { ChartContainer } from '../shared/ChartContainer';
import { TableContainer } from '../shared/TableContainer';

interface HoldingsSectionProps {
    holdings: AggregatedHolding[];
    onHoldingClick?: (holding: AggregatedHolding) => void;
}

export const HoldingsSection: React.FC<HoldingsSectionProps> = ({ holdings, onHoldingClick }) => {
    // Filter out "Altri" variations from backend
    const filteredHoldings = holdings.filter(h => !isAltriVariation(h.holding_name));

    const chartData = filteredHoldings.map(h => ({
        name: h.holding_name,
        value: h.weighted_percent,
        symbol: h.holding_symbol,
    }));

    // Calculate "Altri" percentage
    const { altriSum } = filterAndSumAltri(holdings.map(h => ({ name: h.holding_name, value: h.weighted_percent })));
    const totalShown = filteredHoldings.reduce((sum, h) => sum + h.weighted_percent, 0);
    const othersPercent = 100 - totalShown - altriSum;

    return (
        <div className="grid grid-cols-1 lg:grid-cols-2 gap-6">
            {/* Chart */}
            <ChartContainer title="Top Holdings">
                <ResponsiveContainer width="100%" height={400}>
                    <BarChart data={chartData} layout="vertical" margin={{ left: 100 }}>
                        <CartesianGrid strokeDasharray="3 3" stroke="rgba(255,255,255,0.1)" />
                        <XAxis type="number" stroke="rgba(255,255,255,0.5)" />
                        <YAxis
                            type="category"
                            dataKey="name"
                            stroke="rgba(255,255,255,0.5)"
                            width={90}
                            style={{ fontSize: '11px' }}
                        />
                        <Tooltip
                            contentStyle={{
                                backgroundColor: 'rgba(0, 0, 0, 0.9)',
                                border: '1px solid rgba(255, 255, 255, 0.2)',
                                borderRadius: '8px',
                                color: 'white',
                            }}
                            formatter={(value: number) => `${value.toFixed(2)}%`}
                        />
                        <Bar
                            dataKey="value"
                            radius={[0, 4, 4, 0]}
                            onClick={(data: any) => onHoldingClick?.(data)}
                            style={{ cursor: onHoldingClick ? 'pointer' : 'default' }}
                        >
                            {chartData.map((entry, index) => (
                                <Cell key={`cell-${index}`} fill={COLORS[index % COLORS.length]} />
                            ))}
                            <LabelList content={<CustomLabel />} />
                        </Bar>
                    </BarChart>
                </ResponsiveContainer>
            </ChartContainer>

            {/* Table */}
            <TableContainer title="Dettaglio">
                <table className="w-full">
                    <thead>
                        <tr className="border-b border-white/20">
                            <th className="text-left py-3 px-2 text-sm font-medium text-gray-300">Azienda</th>
                            <th className="text-left py-3 px-2 text-sm font-medium text-gray-300">Ticker</th>
                            <th className="text-right py-3 px-2 text-sm font-medium text-gray-300">Peso %</th>
                        </tr>
                    </thead>
                    <tbody>
                        {filteredHoldings.map((holding, index) => (
                            <tr key={index} className="border-b border-white/10">
                                <td className="py-3 px-2 text-sm text-white">{holding.holding_name}</td>
                                <td className="py-3 px-2 text-sm text-gray-400">{holding.holding_symbol || 'N/A'}</td>
                                <td className="py-3 px-2 text-sm text-right font-medium text-blue-400">
                                    {holding.weighted_percent.toFixed(2)}%
                                </td>
                            </tr>
                        ))}
                        {/* Altri row */}
                        {(othersPercent > 0.01 || altriSum > 0) && (
                            <tr className="border-b border-white/10 bg-gray-500/10">
                                <td className="py-3 px-2 text-sm text-gray-300 italic">Altri</td>
                                <td className="py-3 px-2 text-sm text-gray-400">-</td>
                                <td className="py-3 px-2 text-sm text-right font-medium text-gray-400">
                                    {(othersPercent + altriSum).toFixed(2)}%
                                </td>
                            </tr>
                        )}
                    </tbody>
                </table>
            </TableContainer>
        </div>
    );
};
