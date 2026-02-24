/*
 * Land Registry & Tokenization Chaincode
 * ABAC: createLandRecord (VRO), transferLand (MRO)
 * No delete functions - immutable ledger
 */

'use strict';

const LandTokenContract = require('./lib/landTokenContract');

module.exports.contracts = [LandTokenContract];
