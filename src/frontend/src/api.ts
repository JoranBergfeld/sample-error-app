import type { Product } from './types';

const BASE_URL = (import.meta.env.VITE_API_BASE_URL ?? '').replace(/\/$/, '');

export async function getProducts(): Promise<Product[]> {
  const res = await fetch(`${BASE_URL}/api/products`);
  if (!res.ok) throw new Error(`Failed to load products (${res.status})`);
  return res.json();
}

export interface CheckoutItem {
  id: string;
  quantity: number;
}

export async function checkout(items: CheckoutItem[]): Promise<void> {
  const res = await fetch(`${BASE_URL}/api/checkout`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ items }),
  });
  if (!res.ok) {
    throw new Error(`Payment failed (${res.status})`);
  }
}
