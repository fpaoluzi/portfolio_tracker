/**
 * Chart helper functions and constants
 */

/**
 * Color palette for charts
 */
export const COLORS = [
    '#3b82f6', // blue-500
    '#10b981', // green-500
    '#f59e0b', // amber-500
    '#ef4444', // red-500
    '#8b5cf6', // violet-500
    '#ec4899', // pink-500
    '#06b6d4', // cyan-500
    '#f97316', // orange-500
    '#14b8a6', // teal-500
    '#a855f7', // purple-500
    '#84cc16', // lime-500
    '#f43f5e', // rose-500
];

/**
 * Custom label component for bar charts
 */
export const CustomLabel = (props: any) => {
    const { x, y, width, value } = props;
    if (width < 30) return null; // Don't show label if bar is too small
    return (
        <text
            x={x + width + 5}
            y={y + 15}
            fill="white"
            fontSize={12}
            fontWeight="bold"
        >
            {value.toFixed(2)}%
        </text>
    );
};
