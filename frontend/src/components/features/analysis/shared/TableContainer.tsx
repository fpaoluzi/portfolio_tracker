import React from 'react';

interface TableContainerProps {
    title: string;
    children: React.ReactNode;
    className?: string;
}

/**
 * Table Container Component
 * Reusable wrapper for tables with consistent styling
 */
export const TableContainer: React.FC<TableContainerProps> = ({
    title,
    children,
    className = '',
}) => {
    return (
        <div className={`bg-white/10 backdrop-blur-lg rounded-2xl border border-white/20 p-6 ${className}`}>
            <h3 className="text-xl font-bold text-white mb-4">{title}</h3>
            <div className="overflow-x-auto">
                {children}
            </div>
        </div>
    );
};
