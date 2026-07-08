export interface Product {
  id: string;
  name: string;
  description: string;
  priceCents: number;
  emoji: string;
}

export interface BasketLine {
  product: Product;
  quantity: number;
}
