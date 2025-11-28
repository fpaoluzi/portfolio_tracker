import React from 'react';
import { ResponsiveContainer, BarChart, CartesianGrid, XAxis, YAxis, Tooltip, Bar, Cell, LabelList } from 'recharts';
import { AggregatedSector } from '../utils/types';
import { COLORS, CustomLabel } from '../utils/chartHelpers';
import { isAltriVariation, filterAndSumAltri } from '../utils/altriNormalization';
import { ChartContainer } from '../shared/ChartContainer';
import { TableContainer } from '../shared/TableContainer';

interface SectorsSectionProps {
    sectors: AggregatedSector[];
    onSectorClick?: (sector: AggregatedSector) => void;
}

export const SectorsSection: React.FC<SectorsSectionProps> = ({ sectors, onSectorClick }) => {
    const filteredSectors = sectors.filter(s => !isAltriVariation(s.sector_name));

    const chartData = filteredSectors.map(s => ({
        name: s.sector_name,
        value: s.weighted_percent,
    }));

    const { altriSum } = filterAndSumAltri(sectors.map(s => ({ name: s.sector_name, value: s.weighted_percent })));
    const totalShown = filteredSectors.reduce((sum, s) => sum + s.weighted_percent, 0);
    const othersPercent = 100 - totalShown - altriSum;

    return (
        <div className="grid grid-cols-1 lg:grid-cols-2 gap-6">
            <ChartContainer title="Distribuzione Settoriale">
                <ResponsiveContainer width="100%" height={400}>
                    <BarChart data={chartData} layout="vertical" margin={{ left: 140 }}>
                        <CartesianGrid strokeDasharray="3 3" stroke="rgba(255,255,255,0.1)" />
                        <XAxis type="number" stroke="rgba(255,255,255,0.5)" />
                        <YAxis
                            type="category"
                            dataKey="name"
                            stroke="rgba(255,255,255,0.5)"
                            width={130}
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
                            onClick={(data: any) => onSectorClick?.(data)}
                            style={{ cursor: onSectorClick ? 'pointer' : 'default' }}
                        >
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
                            <th className="text-left py-3 px-2 text-sm font-medium text-gray-300">Settore</th>
                            <th className="text-right py-3 px-2 text-sm font-medium text-gray-300">Peso %</th>
                        </tr>
                    </thead>
                    <tbody>
                        {filteredSectors.map((sector, index) => (
                            <tr key={index} className="border-b border-white/10">
                                <td className="py-3 px-2 text-sm text-white">{sector.sector_name}</td>
                                <td className="py-3 px-2 text-sm text-right font-medium text-blue-400">
                                    {sector.weighted_percent.toFixed(2)}%
                                </td>
                            </tr>
                        ))}
                        {(othersPercent > 0.01 || altriSum > 0) && (
                            <tr className="border-b border-white/10 bg-gray-500/10">
                                <td className="py-3 px-2 text-sm text-gray-300 italic">Altri</td>
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
