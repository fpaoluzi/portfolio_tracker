'use client';

import { useState, useEffect } from 'react';
import { portfoliosApi, analyticsApi, transactionsApi } from '@/lib/api';
import type { Portfolio, Position, Transaction, Performance, Allocation, Snapshot, TargetAllocation, GeoAllocation } from '@/types';

export const usePortfolio = (portfolioId: string | null) => {
  const [loading, setLoading] = useState(false);
  const [positions, setPositions] = useState<Position[]>([]);
  const [transactions, setTransactions] = useState<Transaction[]>([]);
  const [performance, setPerformance] = useState<Performance | null>(null);
  const [allocation, setAllocation] = useState<Allocation[]>([]);
  const [snapshots, setSnapshots] = useState<Snapshot[]>([]);
  const [geoAllocation, setGeoAllocation] = useState<GeoAllocation[]>([]);
  const [targetAllocation, setTargetAllocation] = useState<TargetAllocation | null>(null);

  const calculateGeoAllocation = (positionsData: Position[]) => {
    const geoMap: Record<string, number> = {};

    positionsData.forEach(pos => {
      const country = pos.country || 'Non specificato';
      if (!geoMap[country]) {
        geoMap[country] = 0;
      }
      geoMap[country] += parseFloat(String(pos.current_value || 0));
    });

    const geoArray = Object.entries(geoMap)
      .map(([name, value]) => ({ name, value }))
      .sort((a, b) => b.value - a.value);

    setGeoAllocation(geoArray);
  };

  const loadPortfolioData = async (id: string) => {
    setLoading(true);
    try {
      const [posData, transData, perfData, allocData, snapData] = await Promise.all([
        analyticsApi.getPositions(id),
        transactionsApi.getByPortfolio(id, 100, 0),
        analyticsApi.getPerformance(id),
        analyticsApi.getAllocation(id),
        analyticsApi.getSnapshots(id, 365),
      ]);

      setPositions(posData);
      setTransactions(transData);
      setPerformance(perfData);
      setAllocation(allocData);
      setSnapshots(snapData);
      calculateGeoAllocation(posData);

      // Load target allocation
      try {
        const targetData = await analyticsApi.getTargetAllocation(id);
        setTargetAllocation(targetData);
      } catch (error) {
        // Target allocation might not exist
        setTargetAllocation(null);
      }
    } catch (error) {
      console.error('Error loading portfolio data:', error);
    } finally {
      setLoading(false);
    }
  };

  const updatePrices = async () => {
    if (!portfolioId) return;
    setLoading(true);
    try {
      await portfoliosApi.updatePrices(portfolioId);
      await loadPortfolioData(portfolioId);
    } catch (error) {
      console.error('Error updating prices:', error);
    } finally {
      setLoading(false);
    }
  };

  const refreshData = () => {
    if (portfolioId) {
      loadPortfolioData(portfolioId);
    }
  };

  useEffect(() => {
    if (portfolioId) {
      loadPortfolioData(portfolioId);
    }
  }, [portfolioId]);

  return {
    loading,
    positions,
    transactions,
    performance,
    allocation,
    snapshots,
    geoAllocation,
    targetAllocation,
    updatePrices,
    refreshData,
  };
};
