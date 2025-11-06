// ============================================
// PORTFOLIO TRACKER - BACKEND API SERVER
// Node.js + Express + PostgreSQL (REFACTORED)
// ============================================

const express = require('express');
const cors = require('cors');
const pool = require('./src/config/database');
const { PORT } = require('./src/config/server');
const apiRoutes = require('./src/routes');

const app = express();

// ============================================
// MIDDLEWARE
// ============================================

app.use(cors());
app.use(express.json());

// ============================================
// API ROUTES
// ============================================

app.use('/api', apiRoutes);

// ============================================
// START SERVER
// ============================================

app.listen(PORT, () => {
  console.log(`
╔═══════════════════════════════════════════╗
║   Portfolio Tracker API Server           ║
║   http://localhost:${PORT}                  ║
║                                           ║
║   Database: PostgreSQL                    ║
║   Host: localhost:5432                    ║
║   Database: finance                       ║
║   Status: Refactored & Modular ✅         ║
╚═══════════════════════════════════════════╝
  `);
});

// ============================================
// GRACEFUL SHUTDOWN
// ============================================

process.on('SIGTERM', () => {
  console.log('SIGTERM ricevuto. Chiusura server...');
  pool.end(() => {
    console.log('Pool database chiuso');
    process.exit(0);
  });
});

module.exports = app;
