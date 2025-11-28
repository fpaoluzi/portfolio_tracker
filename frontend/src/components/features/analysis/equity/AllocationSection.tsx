import React from 'react';
import { ResponsiveContainer, PieChart, Pie, Cell, Tooltip, Legend } from 'recharts';
import { AggregatedAllocation } from '../utils/types';
import { COLORS } from '../utils/chartHelpers';
import { isAltriVariation, filterAndSumAltri } from '../utils/altriNormalization';
import { ChartContainer } from '../shared/ChartContainer';
import { TableContainer } from '../shared/TableContainer';

interface AllocationSectionProps {
    allocation: AggregatedAllocation[];
    onAllocationClick?: (allocation: AggregatedAllocation) => void;
}

export const AllocationSection: React.FC<AllocationSectionProps> = ({ allocation, onAllocationClick }) => {
    const filteredAllocation = allocation.filter(a => !isAltriVariation(a.allocation_type));

    const chartData = filteredAllocation.map(a => ({
        name: a.allocation_type,
        value: a.weighted_percent,
    }));

    const { altriSum } = filterAndSumAltri(allocation.map(a => ({ name: a.allocation_type, value: a.weighted_percent })));
    const totalShown = filteredAllocation.reduce((sum, a) => sum + a.weighted_percent, 0);
    const othersPercent = 100 - totalShown - altriSum;

    return (
        <div className="grid grid-cols-1 lg:grid-cols-2 gap-6">
            <ChartContainer title="Asset Allocation">
                <ResponsiveContainer width="100%" height={400}>
                    <PieChart>
                        <Pie
                            data={chartData}
                            cx="50%"
                            cy="50%"
                            labelLine={false}
                            label={(props: any) => `${props.name}: ${Number(props.value).toFixed(2)}%`}
                            outerRadius={120}
                            fill="#8884d8"
                            dataKey="value"
                            onClick={(data: any) => onAllocationClick?.(data)}
                            style={{ cursor: onAllocationClick ? 'pointer' : 'default' }}
                        >
                            {chartData.map((entry, index) => (
                                <Cell key={`cell-${index}`} fill={COLORS[index % COLORS.length]} />
                            ))}
                        </Pie>
                        <Tooltip
                            contentStyle={{
                                backgroundColor: 'rgba(0, 0, 0, 0.9)',
                                border: '1px solid rgba(255, 255, 255, 0.2)',
                                borderRadius: '8px',
                                color: 'white',
                            }}
                        />
                        <Legend />
                    </PieChart>
                </ResponsiveContainer>
            </ChartContainer>

            <TableContainer title="Dettaglio">
                <table className="w-full">
                    <thead>
                        <tr className="border-b border-white/20">
                            <th className="text-left py-3 px-2 text-sm font-medium text-gray-300">Asset Class</th>
                            <th className="text-right py-3 px-2 text-sm font-medium text-gray-300">Peso %</th>
                        </tr>
                    </thead>
                    <tbody>
                        {filteredAllocation.map((alloc, index) => (
                            <tr key={index} className="border-b border-white/10">
                                <td className="py-3 px-2 text-sm text-white">{alloc.allocation_type}</td>
                                <td className="py-3 px-2 text-sm text-right font-medium text-blue-400">
                                    {alloc.weighted_percent.toFixed(2)}%
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
