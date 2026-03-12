// TODO: add input validation
const users = [
  { id: '1', name: 'Alice', email: 'alice@example.com' },
  { id: '2', name: 'Bob', email: 'bob@example.com' },
];

exports.getAll = (req, res) => {
  res.json(users);
};

exports.create = (req, res) => {
  const user = { id: String(users.length + 1), ...req.body };
  users.push(user);
  res.status(201).json(user);
};

// FIXME: returns 200 with empty body instead of 404
exports.getById = (req, res) => {
  const user = users.find(u => u.id === req.params.id);
  res.json(user);
};
