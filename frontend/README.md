# Portfolio Tracker Pro - Next.js Frontend

Applicazione Next.js 14 con App Router per la gestione del portafoglio investimenti.

## 🚀 Struttura del Progetto

```
src/
├── app/                      # Next.js App Router
│   ├── layout.tsx           # Layout principale
│   └── page.tsx             # Pagina principale
├── components/
│   ├── ui/                  # Componenti UI riutilizzabili
│   │   ├── Modal.tsx        # Componente modale
│   │   ├── Button.tsx       # Bottoni
│   │   ├── Input.tsx        # Input con stili corretti
│   │   ├── Select.tsx       # Select/Dropdown con sfondo scuro (FIX)
│   │   └── Textarea.tsx     # Textarea
│   └── features/            # Componenti specifici per feature
│       ├── portfolio/       # Gestione portafogli
│       ├── asset/           # Gestione asset
│       ├── transaction/     # Gestione transazioni
│       └── allocation/      # Allocazione e ribilanciamento
├── lib/
│   ├── api/                 # Client API e servizi
│   │   ├── client.ts        # Client HTTP base
│   │   ├── portfolios.ts    # API portafogli
│   │   ├── assets.ts        # API asset
│   │   ├── transactions.ts  # API transazioni
│   │   └── analytics.ts     # API analytics
│   ├── hooks/               # Custom React hooks
│   │   └── usePortfolio.ts  # Hook per gestione portfolio
│   └── utils/               # Utility functions
│       ├── format.ts        # Formattazione valute/date
│       └── colors.ts        # Costanti colori
└── types/
    └── index.ts             # TypeScript type definitions
```

## ✨ Miglioramenti rispetto alla versione precedente

### 1. **Architettura Modulare**
- Codice diviso in moduli logici e riutilizzabili
- Separazione delle responsabilità (UI, logica, API)
- Facile manutenzione e testing

### 2. **TypeScript**
- Type safety completo
- Autocompletamento nell'IDE
- Riduzione degli errori runtime

### 3. **Componenti UI Riutilizzabili**
- Design system consistente
- Facile aggiornamento degli stili
- Componenti accessibili

### 4. **Fix Dropdown Bianche** ✅
- **Problema risolto**: Le dropdown ora hanno sfondo scuro (`bg-slate-700/50`) con testo bianco
- Bordi e focus chiari
- Freccia dropdown personalizzata visibile

### 5. **API Layer Centralizzato**
- Gestione errori centralizzata
- Facile aggiornamento endpoint
- Type-safe API calls

### 6. **Custom Hooks**
- Logica di stato riutilizzabile
- Codice più pulito e leggibile
- Facilita il testing

## 🛠 Setup e Avvio

### Installazione dipendenze
```bash
npm install
```

### Avvio in modalità development
```bash
npm run dev
```

L'applicazione sarà disponibile su `http://localhost:3000`

### Build per produzione
```bash
npm run build
npm start
```

## 🔧 Configurazione

Crea un file `.env.local` nella root del progetto:

```env
NEXT_PUBLIC_API_URL=http://localhost:3001/api
```

## 📦 Tecnologie Utilizzate

- **Next.js 14** - Framework React con App Router
- **React 19** - Libreria UI
- **TypeScript** - Type safety
- **Tailwind CSS** - Styling utility-first
- **Recharts** - Grafici e visualizzazioni
- **Lucide React** - Icone moderne

## 🎨 Tema e Stili

L'applicazione utilizza un tema scuro con:
- Gradient background (slate-900 → blue-900)
- Componenti con backdrop blur
- Colori coerenti per stati (success, danger, warning)
- **Dropdown con sfondo scuro** (risolto il problema del testo bianco su sfondo bianco)

## 📝 Note per lo Sviluppo

### Aggiungere un nuovo componente UI
```tsx
// src/components/ui/NuovoComponente.tsx
export const NuovoComponente = () => {
  return (
    <div className="bg-slate-700/50 border border-white/20 rounded-lg">
      {/* ... */}
    </div>
  );
};
```

### Aggiungere una nuova API
```typescript
// src/lib/api/nuova-api.ts
import { apiClient } from './client';

export const nuovaApi = {
  getData: () => apiClient.get('/endpoint'),
};
```

### Creare un nuovo hook
```typescript
// src/lib/hooks/useNuovoHook.ts
'use client';
import { useState, useEffect } from 'react';

export const useNuovoHook = () => {
  // logica...
  return { /* valori */ };
};
```

## 🔄 Migrazione dalla versione precedente

La nuova struttura è completamente compatibile con il backend esistente. Non sono necessarie modifiche al database o alle API.

### Versione Legacy
Se vuoi eseguire la vecchia versione React:
```bash
npm run legacy:start
```

## 📋 TODO Future

- [ ] Aggiungere test unitari
- [ ] Implementare SSR per performance
- [ ] Aggiungere autenticazione utente
- [ ] Supporto multi-lingua
- [ ] PWA support
- [ ] Dark/Light mode toggle

## 🤝 Contribuire

Per contribuire al progetto:
1. Segui la struttura modulare esistente
2. Usa TypeScript per tutti i nuovi file
3. Mantieni i componenti piccoli e focalizzati
4. Testa le modifiche con il backend

## 📄 Licenza

MIT
