import type { Metadata } from 'next';
import '../index.css';

export const metadata: Metadata = {
  title: 'Portfolio Tracker Pro',
  description: 'Gestione completa del portafoglio con PostgreSQL',
};

export default function RootLayout({
  children,
}: {
  children: React.ReactNode;
}) {
  return (
    <html lang="it">
      <body>{children}</body>
    </html>
  );
}
