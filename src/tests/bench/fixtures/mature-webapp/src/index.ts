import express from 'express';
import { healthRouter } from './routes/health';
import { usersRouter } from './routes/users';
import { productsRouter } from './routes/products';
import { errorHandler } from './middleware/error-handler';

const app = express();
app.use(express.json());

app.use('/api', healthRouter);
app.use('/api', usersRouter);
app.use('/api', productsRouter);
app.use(errorHandler);

const PORT = process.env.PORT || 3000;
app.listen(PORT, () => console.log(`Server running on port ${PORT}`));

export default app;
