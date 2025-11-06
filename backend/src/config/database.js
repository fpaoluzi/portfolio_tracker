// ============================================
// DATABASE CONFIGURATION
// PostgreSQL Connection Pool
// ============================================

const { Pool } = require('pg');

// Configurazione Database PostgreSQL
const pool = new Pool({
  host: process.env.DB_HOST || 'localhost',
  port: process.env.DB_PORT || 5432,
  database: process.env.DB_NAME || 'finance',
  user: process.env.DB_USER || 'postgres',
  password: process.env.DB_PASSWORD || 'postgres',
  max: 20,
  idleTimeoutMillis: 30000,
  connectionTimeoutMillis: 2000,
});

// Event handlers
pool.on('connect', () => {
  console.log('✅ Connesso a PostgreSQL');
});

pool.on('error', (err) => {
  console.error('❌ Errore PostgreSQL:', err);
});

module.exports = pool;
