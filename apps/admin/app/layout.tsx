import './globals.css';
import type { ReactNode } from 'react';
export const metadata = {
  title: 'RuralConnect · Operations',
  description: 'Kerala transport operations',
};
export default function Layout({ children }: { children: ReactNode }) {
  return (
    <html lang="en">
      <body>{children}</body>
    </html>
  );
}
