/**
 * Land Registry API Routes
 */

const express = require('express');
const router = express.Router();
const fabricService = require('../services/fabricService');
const supabaseService = require('../services/supabaseService');

router.get('/:propertyId', async (req, res) => {
  try {
    const { propertyId } = req.params;
    const identityLabel = req.query.identity || 'Admin@revenuedept';
    const org = identityLabel.includes('regionaloffice') ? 'regionaloffice' : 'revenuedept';

    const contract = await fabricService.getContract(identityLabel, org);
    const result = await contract.evaluateTransaction('getLandByPropertyID', propertyId);
    const landRecord = JSON.parse(result.toString());
    res.json(landRecord);
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

router.get('/survey/:surveyNumber/:subdivision?', async (req, res) => {
  try {
    const { surveyNumber, subdivision } = req.params;
    const identityLabel = req.query.identity || 'Admin@revenuedept';
    const org = identityLabel.includes('regionaloffice') ? 'regionaloffice' : 'revenuedept';

    const contract = await fabricService.getContract(identityLabel, org);
    const args = subdivision ? ['getLandBySurveyNumber', surveyNumber, subdivision] : ['getLandBySurveyNumber', surveyNumber, ''];
    const result = await contract.evaluateTransaction(...args);
    res.json(JSON.parse(result.toString()));
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

router.get('/:propertyId/history', async (req, res) => {
  try {
    const { propertyId } = req.params;
    const identityLabel = req.query.identity || 'Admin@revenuedept';
    const org = identityLabel.includes('regionaloffice') ? 'regionaloffice' : 'revenuedept';

    const contract = await fabricService.getContract(identityLabel, org);
    const result = await contract.evaluateTransaction('getFullTransferHistory', propertyId);
    res.json(JSON.parse(result.toString()));
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

router.post('/create', async (req, res) => {
  try {
    const { surveyNumber, subdivisionNumber, area, ownerId, documentHash, officerApproval } = req.body;
    const identityLabel = req.body.identity || 'vro1@revenuedept';

    const contract = await fabricService.getContract(identityLabel, 'revenuedept');
    const result = await contract.submitTransaction('createLandRecord',
      surveyNumber, subdivisionNumber, String(area), ownerId, documentHash, officerApproval);
    const landRecord = JSON.parse(result.toString());

    try {
      await supabaseService.upsertLandMetadata(landRecord);
    } catch (e) {
      console.warn('Supabase sync skipped:', e.message);
    }
    res.json(landRecord);
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

router.post('/transfer', async (req, res) => {
  try {
    const { propertyId, newOwnerId } = req.body;
    const identityLabel = req.body.identity || 'mro1@revenuedept';

    const contract = await fabricService.getContract(identityLabel, 'revenuedept');
    const result = await contract.submitTransaction('transferLand', propertyId, newOwnerId);
    const transferResult = JSON.parse(result.toString());

    try {
      const landContract = await fabricService.getContract(identityLabel, 'revenuedept');
      const landResult = await landContract.evaluateTransaction('getLandByPropertyID', propertyId);
      const landRecord = JSON.parse(landResult.toString());
      await supabaseService.upsertLandMetadata(landRecord);
    } catch (e) {
      console.warn('Supabase sync skipped:', e.message);
    }
    res.json(transferResult);
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

module.exports = router;
