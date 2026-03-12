import { Router } from 'express';
import { ProductService } from '../services/product-service';

export const productsRouter = Router();
const productService = new ProductService();

productsRouter.get('/products', async (_req, res, next) => {
  try {
    const products = await productService.findAll();
    res.json(products);
  } catch (err) { next(err); }
});

productsRouter.get('/products/:id', async (req, res, next) => {
  try {
    const product = await productService.findById(req.params.id);
    if (!product) { res.status(404).json({ error: 'Not found' }); return; }
    res.json(product);
  } catch (err) { next(err); }
});
