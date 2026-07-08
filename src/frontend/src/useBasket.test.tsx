import { renderHook, act } from '@testing-library/react';
import { describe, it, expect } from 'vitest';
import { useBasket } from './useBasket';
import type { Product } from './types';

const mug: Product = { id: 'coffee-mug', name: 'Mug', description: '', priceCents: 1299, emoji: '☕' };

describe('useBasket', () => {
  it('adds items and accumulates quantity and total', () => {
    const { result } = renderHook(() => useBasket());

    act(() => result.current.add(mug));
    act(() => result.current.add(mug));

    expect(result.current.lines).toHaveLength(1);
    expect(result.current.lines[0].quantity).toBe(2);
    expect(result.current.totalCents).toBe(2598);
  });

  it('clears the basket', () => {
    const { result } = renderHook(() => useBasket());
    act(() => result.current.add(mug));
    act(() => result.current.clear());
    expect(result.current.lines).toHaveLength(0);
    expect(result.current.totalCents).toBe(0);
  });
});
