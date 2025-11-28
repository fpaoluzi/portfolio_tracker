import React from 'react';
import { ResponsiveContainer, BarChart, CartesianGrid, XAxis, YAxis, Tooltip, Bar, Cell, LabelList } from 'recharts';
import { AggregatedBondMaturity } from '../utils/types';
import { COLORS, CustomLabel } from '../utils/chartHelpers';
import { ChartContainer } from '../shared/ChartContainer';
import { TableContainer } from '../shared/TableContainer';

interface BondMaturitySectionProps {
    bondMaturity: AggregatedBondMaturity[];
}

export const BondMaturitySection: React.FC<BondMaturitySectionProps> = ({ bondMaturity }) => {
    const chartData = bondMaturity.map(bm => ({
        name: bm.maturity_range,
        value: bm.weighted_percent,
        duration: bm.avg_duration_years,
    }));

    return (
        <div className="grid grid-cols-1 lg:grid-cols-2 gap-6">
            <ChartContainer title="Distribuzione Scadenze">
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
                        <Bar dataKey="value" radius={[0, 4, 4, 0]}>
                            {chartData.map((entry, index) => (
                                <Cell key={`cell-${index}`} fill={COLORS[index % COLORS.length]} />
                            ))}
                            <LabelList content={<CustomLabel />} />
                        </Bar>
                    </BarChart>
                </ResponsiveContainer>
            </ChartContainer>

            <TableContainer title="Dettaglio">
                <table className="w-full">
                    <thead>
                        <tr className="border-b border-white/20">
                            <th className="text-left py-3 px-2 text-sm font-medium text-gray-300">Range Scadenza</th>
                            <th className="text-right py-3 px-2 text-sm font-medium text-gray-300">Duration Media</th>
                            <th className="text-right py-3 px-2 text-sm font-medium text-gray-300">Peso %</th>
                        </tr>
                    </thead>
                    <tbody>
                        {bondMaturity.map((maturity, index) => (
                            <tr key={index} className="border-b border-white/10">
                                <td className="py-3 px-2 text-sm text-white">{maturity.maturity_range}</td>
                                <td className="py-3 px-2 text-sm text-right text-gray-400">
                                    {maturity.avg_duration_years !== null ? `${maturity.avg_duration_years.toFixed(2)} anni` : 'N/A'}
                                </td>
                                <td className="py-3 px-2 text-sm text-right font-medium text-blue-400">
                                    {maturity.weighted_percent.toFixed(2)}%
                                </td>
                            </tr>
                        ))}
                    </tbody>
                </table>
            </TableContainer>
        </div>
    );
};
