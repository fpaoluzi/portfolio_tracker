/**
 * Helper functions for normalizing "Altri" variations in composition data
 */

/**
 * Check if a name is a variation of "Altri"
 * Matches: altri, altro, ALTRI, ALTRO, other, others (case-insensitive)
 */
export const isAltriVariation = (name: string): boolean => {
    const normalized = name.trim().toLowerCase();
    return normalized === 'altri' || normalized === 'altro' || normalized === 'other' || normalized === 'others';
};

/**
 * Filter out "Altri" variations and sum their percentages
 * @param items Array of items with name and value properties
 * @returns Object with filtered items and sum of Altri variations
 */
export const filterAndSumAltri = (items: Array<{ name: string; value: number }>) => {
    let altriSum = 0;
    const filtered = items.filter(item => {
        if (isAltriVariation(item.name)) {
            altriSum += item.value;
            return false; // Remove from list
        }
        return true; // Keep in list
    });
    return { filtered, altriSum };
};
