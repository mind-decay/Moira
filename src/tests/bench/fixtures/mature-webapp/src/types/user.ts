import { z } from 'zod';

export const CreateUserSchema = z.object({
  name: z.string().min(1),
  email: z.string().email(),
});

export type CreateUser = z.infer<typeof CreateUserSchema>;
export interface User extends CreateUser { id: string; createdAt: Date; }
