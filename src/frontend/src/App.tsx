import { useEffect, useState } from 'react';
import type { Product } from './types';
import { getProducts, checkout } from './api';
import { useBasket } from './useBasket';
import './App.css';

type PayState = { status: 'idle' | 'paying' } | { status: 'error'; message: string };

export default function App() {
  const [products, setProducts] = useState<Product[]>([]);
  const [loadError, setLoadError] = useState<string | null>(null);
  const [pay, setPay] = useState<PayState>({ status: 'idle' });
  const basket = useBasket();

  useEffect(() => {
    getProducts().then(setProducts).catch((e) => setLoadError(String(e.message ?? e)));
  }, []);

  const onPay = async () => {
    setPay({ status: 'paying' });
    try {
      await checkout(basket.lines.map((l) => ({ id: l.product.id, quantity: l.quantity })));
      setPay({ status: 'idle' });
    } catch (e) {
      setPay({ status: 'error', message: e instanceof Error ? e.message : String(e) });
    }
  };

  const formatPrice = (cents: number) => `$${(cents / 100).toFixed(2)}`;

  return (
    <div className="app">
      <header>
        <h1>🛒 Sample Shop</h1>
      </header>

      <main>
        <section className="catalog">
          {loadError && <p className="error">Could not load products: {loadError}</p>}
          <div className="grid">
            {products.map((p) => (
              <article key={p.id} className="card">
                <div className="emoji">{p.emoji}</div>
                <h3>{p.name}</h3>
                <p className="desc">{p.description}</p>
                <p className="price">{formatPrice(p.priceCents)}</p>
                <button onClick={() => basket.add(p)}>Add to basket</button>
              </article>
            ))}
          </div>
        </section>

        <aside className="basket">
          <h2>Basket ({basket.lines.reduce((n, l) => n + l.quantity, 0)})</h2>
          <ul>
            {basket.lines.map((l) => (
              <li key={l.product.id}>
                {l.product.name} × {l.quantity} — {formatPrice(l.product.priceCents * l.quantity)}
              </li>
            ))}
          </ul>
          <p className="total">Total: {formatPrice(basket.totalCents)}</p>
          <button className="pay" disabled={basket.lines.length === 0 || pay.status === 'paying'} onClick={onPay}>
            {pay.status === 'paying' ? 'Processing…' : 'Pay'}
          </button>
          {pay.status === 'error' && <p className="error">{pay.message} — something went wrong on the server.</p>}
        </aside>
      </main>
    </div>
  );
}
