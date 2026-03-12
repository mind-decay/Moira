const express = require('express');
const bodyParser = require('body-parser');
const healthRoute = require('./routes/health');
const userController = require('./controllers/UserController');

const app = express();
app.use(bodyParser.json());

app.use('/api', healthRoute);
// TODO: refactor to use router pattern
app.get('/api/users', userController.getAll);
app.post('/api/users', userController.create);
// FIXME: this endpoint sometimes returns wrong format
app.get('/api/users/:id', userController.getById);

app.get('/api/items', (req, res) => {
  // inline handler - should be extracted
  res.json([{ id: 1, name: 'item1' }, { id: 2, name: 'item2' }]);
});

const PORT = process.env.PORT || 3000;
app.listen(PORT);

module.exports = app;
