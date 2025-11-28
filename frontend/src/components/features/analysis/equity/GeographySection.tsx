import React, { useState } from 'react';
import { ComposableMap, Geographies, Geography } from 'react-simple-maps';
import { ResponsiveContainer, BarChart, CartesianGrid, XAxis, YAxis, Tooltip, Bar, Cell, LabelList } from 'recharts';
import { AggregatedRegion } from '../utils/types';
import { COLORS, CustomLabel } from '../utils/chartHelpers';
import { isAltriVariation, filterAndSumAltri } from '../utils/altriNormalization';
import { ChartContainer } from '../shared/ChartContainer';
import { LegendBox } from '../shared/LegendBox';

const GEO_URL = 'https://cdn.jsdelivr.net/npm/world-atlas@2/countries-110m.json';

const REGION_TO_COUNTRIES: Record<string, string[]> = {
    'Italia': ['Italy'],
    'Francia': ['France'],
    'Germania': ['Germany'],
    'Spagna': ['Spain'],
    'Regno Unito': ['United Kingdom'],
    'Paesi Bassi': ['Netherlands'],
    'Belgio': ['Belgium'],
    'Austria': ['Austria'],
    'Portogallo': ['Portugal'],
    'Finlandia': ['Finland'],
    'USA': ['United States of America'],
    'Giappone': ['Japan'],
    'Cina': ['China'],
    'India': ['India'],
    'Canada': ['Canada'],
    'Australia': ['Australia'],
    'Brasile': ['Brazil'],
    'Messico': ['Mexico'],
    'Corea del Sud': ['South Korea'],
    'Taiwan': ['Taiwan'],
};

interface GeographySectionProps {
    regions: AggregatedRegion[];
    onRegionClick?: (region: AggregatedRegion) => void;
}

export const GeographySection: React.FC<GeographySectionProps> = ({ regions, onRegionClick }) => {
    const [mapTooltip, setMapTooltip] = useState<{ name: string; value: number } | null>(null);

    const filteredRegions = regions.filter(r => !isAltriVariation(r.region_name) && r.weighted_percent > 0);

    const chartData = filteredRegions
        .map(r => ({
            name: r.region_name,
            value: r.weighted_percent,
        }))
        .sort((a, b) => b.value - a.value);

    const { altriSum } = filterAndSumAltri(regions.map(r => ({ name: r.region_name, value: r.weighted_percent })));
    const totalShown = filteredRegions.reduce((sum, r) => sum + r.weighted_percent, 0);
    const othersPercent = 100 - totalShown - altriSum;

    return (
        <div className="grid grid-cols-1 lg:grid-cols-2 gap-6">
            <ChartContainer title="Distribuzione Geografica">
                <div className="h-[350px] relative mb-4">
                    <ComposableMap projection="geoMercator" projectionConfig={{ scale: 120 }}>
                        <Geographies geography={GEO_URL}>
                            {({ geographies }) =>
                                geographies.map((geo) => {
                                    let regionData = null;
                                    let regionIndex = -1;

                                    for (let i = 0; i < chartData.length; i++) {
                                        const region = chartData[i];
                                        const countries = REGION_TO_COUNTRIES[region.name] || [];
                                        if (countries.some(c => geo.properties?.name === c)) {
                                            regionData = region;
                                            regionIndex = i;
                                            break;
                                        }
                                    }

                                    const fillColor = regionData
                                        ? COLORS[regionIndex % COLORS.length]
                                        : 'rgba(100, 116, 139, 0.2)';

                                    return (
                                        <Geography
                                            key={geo.rsmKey}
                                            geography={geo}
                                            fill={fillColor}
                                            stroke="rgba(255, 255, 255, 0.3)"
                                            strokeWidth={0.5}
                                            onMouseEnter={() => {
                                                if (regionData) {
                                                    setMapTooltip({ name: regionData.name, value: regionData.value });
                                                }
                                            }}
                                            onMouseLeave={() => setMapTooltip(null)}
                                            style={{
                                                default: { outline: 'none' },
                                                hover: {
                                                    fill: regionData ? COLORS[regionIndex % COLORS.length] : 'rgba(100, 116, 139, 0.4)',
                                                    outline: 'none',
                                                    cursor: 'pointer',
                                                    opacity: 0.8,
                                                },
                                                pressed: { outline: 'none' },
                                            }}
                                        />
                                    );
                                })
                            }
                        </Geographies>
                    </ComposableMap>

                    {mapTooltip && (
                        <div className="absolute top-4 right-4 bg-black/80 text-white px-4 py-2 rounded-lg border border-white/20 shadow-lg">
                            <div className="text-sm font-semibold">{mapTooltip.name}</div>
                            <div className="text-lg font-bold text-blue-400">{mapTooltip.value.toFixed(2)}%</div>
                        </div>
                    )}
                </div>

                <LegendBox
                    title="Legenda Regioni"
                    items={chartData}
                    altriPercent={othersPercent + altriSum}
                />
            </ChartContainer>

            <ChartContainer title="Dettaglio">
                <ResponsiveContainer width="100%" height={400}>
                    <BarChart data={chartData} layout="vertical" margin={{ left: 140, right: 20, top: 5, bottom: 5 }}>
                        <CartesianGrid strokeDasharray="3 3" stroke="rgba(255,255,255,0.1)" />
                        <XAxis type="number" stroke="rgba(255,255,255,0.5)" />
                        <YAxis
                            type="category"
                            dataKey="name"
                            stroke="rgba(255,255,255,0.5)"
                            width={140}
                            tick={{ fill: 'rgba(255,255,255,0.9)', fontSize: 12 }}
                            interval={0}
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
                            onClick={(data: any) => onRegionClick?.(data)}
                            style={{ cursor: onRegionClick ? 'pointer' : 'default' }}
                        >
                            {chartData.map((entry, index) => (
                                <Cell key={`cell-${index}`} fill={COLORS[index % COLORS.length]} />
                            ))}
                            <LabelList content={<CustomLabel />} />
                        </Bar>
                    </BarChart>
                </ResponsiveContainer>
            </ChartContainer>
        </div>
    );
};
