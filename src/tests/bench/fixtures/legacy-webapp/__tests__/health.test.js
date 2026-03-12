const request = require('supertest');
const app = require('../src/app');

test('health endpoint returns ok', async () => {
  const res = await request(app).get('/api/health');
  expect(res.statusCode).toBe(200);
});
