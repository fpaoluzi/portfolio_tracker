import React from 'react';
import { ResponsiveContainer, PieChart, Pie, Cell, Tooltip, Legend } from 'recharts';
import { AggregatedBondRating } from '../utils/types';
import { COLORS } from '../utils/chartHelpers';
import { isAltriVariation, filterAndSumAltri } from '../utils/altriNormalization';
import { ChartContainer } from '../shared/ChartContainer';
import { TableContainer } from '../shared/TableContainer';

interface BondRatingsSectionProps {
    bondRatings: AggregatedBondRating[];
}

export const BondRatingsSection: React.FC<BondRatingsSectionProps> = ({ bondRatings }) => {
    const filteredRatings = bondRatings.filter(br => !isAltriVariation(br.rating_category));

    const chartData = filteredRatings.map(br => ({
        name: br.rating_category,
        value: br.weighted_percent,
    }));

    const { altriSum } = filterAndSumAltri(bondRatings.map(br => ({ name: br.rating_category, value: br.weighted_percent })));
    const totalShown = filteredRatings.reduce((sum, br) => sum + br.weighted_percent, 0);
    const othersPercent = 100 - totalShown - altriSum;

    return (
        <div className="grid grid-cols-1 lg:grid-cols-2 gap-6">
            <ChartContainer title="Distribuzione Rating">
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
                            <th className="text-left py-3 px-2 text-sm font-medium text-gray-300">Categoria Rating</th>
                            <th className="text-right py-3 px-2 text-sm font-medium text-gray-300">Peso %</th>
                        </tr>
                    </thead>
                    <tbody>
                        {filteredRatings.map((rating, index) => (
                            <tr key={index} className="border-b border-white/10">
                                <td className="py-3 px-2 text-sm text-white">{rating.rating_category}</td>
                                <td className="py-3 px-2 text-sm text-right font-medium text-blue-400">
                                    {rating.weighted_percent.toFixed(2)}%
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
