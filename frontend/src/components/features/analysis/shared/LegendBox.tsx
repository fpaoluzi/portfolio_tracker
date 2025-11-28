import React from 'react';
import { COLORS } from '../utils/chartHelpers';

interface LegendItem {
    name: string;
    value: number;
    color?: string;
}

interface LegendBoxProps {
    title: string;
    items: LegendItem[];
    altriPercent?: number;
    className?: string;
}

/**
 * Legend Box Component
 * Reusable legend box for maps and charts
 */
export const LegendBox: React.FC<LegendBoxProps> = ({
    title,
    items,
    altriPercent,
    className = '',
}) => {
    return (
        <div className={`mt-6 bg-white/5 rounded-lg p-4 border border-white/10 ${className}`}>
            <h4 className="text-sm font-semibold text-white mb-3">{title}</h4>
            <div className="flex flex-wrap gap-3">
                {items.map((item, index) => (
                    <div key={index} className="flex items-center gap-2 bg-white/5 px-3 py-2 rounded border border-white/10">
                        <div
                            className="w-4 h-4 rounded"
                            style={{
                                backgroundColor: item.color || COLORS[index % COLORS.length],
                            }}
                        />
                        <span className="text-sm text-white font-medium">
                            {item.name}
                        </span>
                        <span className="text-sm text-blue-300 font-bold">
                            {item.value.toFixed(2)}%
                        </span>
                    </div>
                ))}
                {/* Altri */}
                {altriPercent !== undefined && altriPercent > 0.01 && (
                    <div className="flex items-center gap-2 bg-gray-500/10 px-3 py-2 rounded border border-white/10">
                        <div className="w-4 h-4 rounded bg-gray-400" />
                        <span className="text-sm text-gray-300 font-medium italic">
                            Altri
                        </span>
                        <span className="text-sm text-gray-400 font-bold">
                            {altriPercent.toFixed(2)}%
                        </span>
                    </div>
                )}
            </div>
        </div>
    );
};
