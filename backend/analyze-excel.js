const XLSX = require('xlsx');
const path = require('path');

// Leggi il file Excel
const filePath = path.join(__dirname, '..', 'StoricoOrdini.xlsx');
const workbook = XLSX.readFile(filePath);

// Ottieni il primo foglio
const sheetName = workbook.SheetNames[0];
const worksheet = workbook.Sheets[sheetName];

console.log('=== FOGLIO ===');
console.log('Nome foglio:', sheetName);
console.log('Range:', worksheet['!ref']);

// Converti in JSON senza header per vedere tutto
const dataNoHeader = XLSX.utils.sheet_to_json(worksheet, { header: 1 });

console.log('\n=== PRIME 15 RIGHE (formato array) ===\n');
dataNoHeader.slice(0, 15).forEach((row, i) => {
  console.log(`Riga ${i}:`, row);
});

// Trova la riga con gli header (cerca "Data", "Titolo", "ISIN", etc.)
let headerRow = -1;
for (let i = 0; i < Math.min(20, dataNoHeader.length); i++) {
  const row = dataNoHeader[i];
  if (row && row.some(cell =>
    cell && typeof cell === 'string' &&
    (cell.includes('Data') || cell.includes('Titolo') || cell.includes('ISIN'))
  )) {
    headerRow = i;
    console.log(`\n=== HEADER TROVATO ALLA RIGA ${i} ===`);
    console.log(row);
    break;
  }
}

if (headerRow >= 0) {
  // Converti usando la riga corretta come header
  const dataWithHeader = XLSX.utils.sheet_to_json(worksheet, {
    range: headerRow,
    defval: ''
  });

  console.log(`\n=== DATI CON HEADER (${dataWithHeader.length} righe) ===\n`);
  console.log('Prime 3 transazioni:\n');
  console.log(JSON.stringify(dataWithHeader.slice(0, 3), null, 2));

  if (dataWithHeader.length > 0) {
    console.log('\n=== COLONNE ===');
    console.log(Object.keys(dataWithHeader[0]));
  }
}
