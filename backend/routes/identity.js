/**
 * Identity / Enrollment routes
 */

const express = require('express');
const router = express.Router();
const enrollService = require('../services/enrollService');

router.post('/enroll', async (req, res) => {
  try {
    const { org, userId, userSecret } = req.body;
    if (!org || !userId || !userSecret) {
      return res.status(400).json({ error: 'org, userId, userSecret required' });
    }
    const result = await enrollService.enrollUser(org, userId, userSecret);
    res.json(result);
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

module.exports = router;
