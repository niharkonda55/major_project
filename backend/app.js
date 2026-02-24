/**
 * Land Registry Backend
 * Express API - Fabric transactions, Supabase sync
 * Blockchain is source of truth for ownership
 */

require('dotenv').config();
const express = require('express');
const landRoutes = require('./routes/land');
const identityRoutes = require('./routes/identity');

const app = express();
app.use(express.json());

app.use('/api/land', landRoutes);
app.use('/api/identity', identityRoutes);

app.get('/health', (req, res) => {
  res.json({ status: 'ok', service: 'land-registry-backend' });
});

const PORT = process.env.PORT || 3000;
app.listen(PORT, () => {
  console.log(`Land Registry Backend listening on port ${PORT}`);
});
