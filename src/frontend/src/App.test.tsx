import { render, screen, waitFor } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { describe, it, expect, vi, beforeEach } from 'vitest';
import App from './App';

const products = [
  { id: 'coffee-mug', name: 'Ceramic Coffee Mug', description: 'A mug', priceCents: 1299, emoji: '☕' },
];

beforeEach(() => {
  vi.restoreAllMocks();
});

describe('App', () => {
  it('lists products, adds to basket, and shows a 500 error on Pay', async () => {
    const fetchMock = vi.fn()
      // getProducts
      .mockResolvedValueOnce({ ok: true, status: 200, json: async () => products } as Response)
      // checkout -> 500
      .mockResolvedValueOnce({ ok: false, status: 500, json: async () => ({ error: 'x' }) } as Response);
    vi.stubGlobal('fetch', fetchMock);

    render(<App />);

    // product renders
    expect(await screen.findByText('Ceramic Coffee Mug')).toBeInTheDocument();

    // add to basket
    await userEvent.click(screen.getByRole('button', { name: /add to basket/i }));
    expect(screen.getByText(/basket \(1\)/i)).toBeInTheDocument();

    // pay -> error surfaces
    await userEvent.click(screen.getByRole('button', { name: /pay/i }));
    await waitFor(() =>
      expect(screen.getByText(/payment failed \(500\)/i)).toBeInTheDocument(),
    );
  });
});
