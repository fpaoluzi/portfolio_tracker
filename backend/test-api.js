// ============================================
// TEST API - Portfolio Tracker
// Testa tutti gli endpoint principali
// ============================================

const API_URL = 'http://localhost:3001/api';

async function testAPI() {
  console.log('🧪 Test API Portfolio Tracker\n');
  
  try {
    // 1. Health Check
    console.log('1️⃣  Test Health Check...');
    const health = await fetch(`${API_URL}/health`);
    const healthData = await health.json();
    console.log('✅ Server attivo:', healthData.status);
    console.log('✅ Database:', healthData.database);
    console.log('');
    
    // 2. Lista Portafogli
    console.log('2️⃣  Test Lista Portafogli...');
    const portfolios = await fetch(`${API_URL}/portfolios`);
    const portfoliosData = await portfolios.json();
    console.log(`✅ Trovati ${portfoliosData.length} portafogli`);
    portfoliosData.forEach(p => console.log(`   - ${p.name} (${p.broker})`));
    console.log('');
    
    if (portfoliosData.length === 0) {
      console.log('❌ Nessun portafoglio trovato. Esegui prima l\'import!');
      return;
    }
    
    const portfolioId = portfoliosData[0].portfolio_id;
    console.log(`📊 Uso portafoglio: ${portfoliosData[0].name}\n`);
    
    // 3. Performance
    console.log('3️⃣  Test Performance...');
    const performance = await fetch(`${API_URL}/portfolios/${portfolioId}/performance`);
    const perfData = await performance.json();
    console.log(`✅ Valore totale: €${perfData.current_value?.toFixed(2) || 0}`);
    console.log(`✅ Investito: €${perfData.total_invested?.toFixed(2) || 0}`);
    console.log(`✅ Gain/Loss: €${perfData.total_gain_loss?.toFixed(2) || 0} (${perfData.total_gain_loss_pct?.toFixed(2) || 0}%)`);
    console.log('');
    
    // 4. Posizioni
    console.log('4️⃣  Test Posizioni Correnti...');
    const positions = await fetch(`${API_URL}/portfolios/${portfolioId}/positions`);
    const posData = await positions.json();
    console.log(`✅ Trovate ${posData.length} posizioni`);
    posData.slice(0, 3).forEach(pos => {
      console.log(`   - ${pos.asset_name}: ${pos.quantity} @ €${pos.current_price} = €${pos.current_value?.toFixed(2)}`);
    });
    console.log('');
    
    // 5. Allocazione
    console.log('5️⃣  Test Allocazione Asset...');
    const allocation = await fetch(`${API_URL}/portfolios/${portfolioId}/allocation`);
    const allocData = await allocation.json();
    console.log(`✅ Allocazione per ${allocData.length} tipi di asset`);
    allocData.forEach(alloc => {
      console.log(`   - ${alloc.asset_type}: ${alloc.percentage?.toFixed(1)}% (€${alloc.total_value?.toFixed(2)})`);
    });
    console.log('');
    
    // 6. Transazioni
    console.log('6️⃣  Test Transazioni...');
    const transactions = await fetch(`${API_URL}/portfolios/${portfolioId}/transactions?limit=5`);
    const txData = await transactions.json();
    console.log(`✅ Ultime ${txData.length} transazioni`);
    txData.forEach(tx => {
      console.log(`   - ${tx.transaction_date}: ${tx.transaction_type} ${tx.quantity} ${tx.asset_name}`);
    });
    console.log('');
    
    // 7. Snapshot
    console.log('7️⃣  Test Snapshot Storici...');
    const snapshots = await fetch(`${API_URL}/portfolios/${portfolioId}/snapshots?days=7`);
    const snapData = await snapshots.json();
    console.log(`✅ Trovati ${snapData.length} snapshot ultimi 7 giorni`);
    if (snapData.length > 0) {
      console.log(`   - Ultimo: ${snapData[0].snapshot_date} - Valore: €${snapData[0].total_value}`);
    }
    console.log('');
    
    // 8. Lista Assets
    console.log('8️⃣  Test Lista Assets...');
    const assets = await fetch(`${API_URL}/assets`);
    const assetsData = await assets.json();
    console.log(`✅ Trovati ${assetsData.length} asset nel database`);
    assetsData.slice(0, 3).forEach(asset => {
      console.log(`   - ${asset.name} (${asset.isin})`);
    });
    console.log('');
    
    console.log('🎉 TUTTI I TEST COMPLETATI CON SUCCESSO!\n');
    console.log('✅ Server API funzionante');
    console.log('✅ Database connesso');
    console.log('✅ Dati importati correttamente');
    console.log('\n🚀 Il sistema è pronto per l\'uso!');
    
  } catch (error) {
    console.error('❌ ERRORE NEL TEST:', error.message);
    console.log('\n⚠️  Verifica che:');
    console.log('   1. Il server sia avviato (npm start)');
    console.log('   2. PostgreSQL sia attivo');
    console.log('   3. I dati siano stati importati (npm run import)');
  }
}

// Esegui test
if (typeof window === 'undefined') {
  // Node.js
  const fetch = require('node-fetch');
  testAPI();
} else {
  // Browser
  testAPI();
}

module.exports = { testAPI };
