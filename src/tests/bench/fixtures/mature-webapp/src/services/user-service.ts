import { CreateUser, User } from '../types/user';

export class UserService {
  private users: User[] = [];

  async findAll(): Promise<User[]> { return this.users; }

  async create(data: CreateUser): Promise<User> {
    const user: User = { id: String(this.users.length + 1), ...data, createdAt: new Date() };
    this.users.push(user);
    return user;
  }
}
