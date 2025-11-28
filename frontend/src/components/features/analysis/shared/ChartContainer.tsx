import React from 'react';

interface ChartContainerProps {
    title: string;
    children: React.ReactNode;
    className?: string;
}

/**
 * Chart Container Component
 * Reusable wrapper for charts with consistent styling
 */
export const ChartContainer: React.FC<ChartContainerProps> = ({
    title,
    children,
    className = '',
}) => {
    return (
        <div className={`bg-white/10 backdrop-blur-lg rounded-2xl border border-white/20 p-6 ${className}`}>
            <h3 className="text-xl font-bold text-white mb-4">{title}</h3>
            {children}
        </div>
    );
};
