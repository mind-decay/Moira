import { Router } from 'express';
import { UserService } from '../services/user-service';
import { CreateUserSchema } from '../types/user';

export const usersRouter = Router();
const userService = new UserService();

usersRouter.get('/users', async (_req, res, next) => {
  try {
    const users = await userService.findAll();
    res.json(users);
  } catch (err) { next(err); }
});

usersRouter.post('/users', async (req, res, next) => {
  try {
    const data = CreateUserSchema.parse(req.body);
    const user = await userService.create(data);
    res.status(201).json(user);
  } catch (err) { next(err); }
});
