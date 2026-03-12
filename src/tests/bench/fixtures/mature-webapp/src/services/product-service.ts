import { Product } from '../types/product';

export class ProductService {
  private products: Product[] = [
    { id: '1', name: 'Widget', price: 9.99, createdAt: new Date() },
    { id: '2', name: 'Gadget', price: 19.99, createdAt: new Date() },
  ];

  async findAll(): Promise<Product[]> { return this.products; }
  async findById(id: string): Promise<Product | undefined> { return this.products.find(p => p.id === id); }
}
