// ============================================
// COLOR CONSTANTS
// ============================================

export const CHART_COLORS = [
  '#3b82f6', // blue
  '#10b981', // green
  '#f59e0b', // amber
  '#8b5cf6', // purple
  '#ef4444', // red
  '#06b6d4', // cyan
  '#f97316', // orange
  '#ec4899', // pink
];

export const getColorByIndex = (index: number): string => {
  return CHART_COLORS[index % CHART_COLORS.length];
};
