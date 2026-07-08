import { useMemo, useState } from 'react';
import type { BasketLine, Product } from './types';

export function useBasket() {
  const [lines, setLines] = useState<BasketLine[]>([]);

  const add = (product: Product) => {
    setLines((current) => {
      const existing = current.find((l) => l.product.id === product.id);
      if (existing) {
        return current.map((l) =>
          l.product.id === product.id ? { ...l, quantity: l.quantity + 1 } : l,
        );
      }
      return [...current, { product, quantity: 1 }];
    });
  };

  const clear = () => setLines([]);

  const totalCents = useMemo(
    () => lines.reduce((sum, l) => sum + l.product.priceCents * l.quantity, 0),
    [lines],
  );

  return { lines, add, clear, totalCents };
}
