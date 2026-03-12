import express from 'express';
import { healthRouter } from './routes/health';

const app = express();
app.use(express.json());
app.use('/api', healthRouter);

const PORT = process.env.PORT || 3000;
app.listen(PORT, () => console.log(`Server running on port ${PORT}`));

export default app;
