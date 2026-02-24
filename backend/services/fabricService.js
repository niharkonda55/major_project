/**
 * Fabric Network Service
 * Gateway, contract, wallet management
 */

const { Gateway, Wallets } = require('fabric-network');
const path = require('path');
const fs = require('fs');

let gateway;

async function getContract(identityLabel, org = 'revenuedept') {
  const base = path.resolve(__dirname, '../..');
  const ccpPath = org === 'revenuedept'
    ? path.resolve(process.env.CONNECTION_PROFILE_REVENUEDEPT || path.join(base, 'network/land-registry-network/organizations/peerOrganizations/revenuedept.landregistry.com/connection-revenuedept.json'))
    : path.resolve(process.env.CONNECTION_PROFILE_REGIONALOFFICE || path.join(base, 'network/land-registry-network/organizations/peerOrganizations/regionaloffice.landregistry.com/connection-regionaloffice.json'));

  const ccp = JSON.parse(fs.readFileSync(ccpPath, 'utf8'));
  const walletPath = path.resolve(process.env.WALLET_PATH || path.join(base, 'backend/wallet'));
  const wallet = await Wallets.newFileSystemWallet(walletPath);

  const identity = await wallet.get(identityLabel);
  if (!identity) {
    throw new Error(`Identity ${identityLabel} not found in wallet. Enroll first.`);
  }

  gateway = new Gateway();
  await gateway.connect(ccp, {
    wallet,
    identity: identityLabel,
    discovery: { enabled: true, asLocalhost: true }
  });

  const network = await gateway.getNetwork(process.env.CHANNEL_NAME || 'landregistrychannel');
  return network.getContract(process.env.CHAINCODE_NAME || 'land-token');
}

async function disconnect() {
  if (gateway) {
    gateway.disconnect();
    gateway = null;
  }
}

module.exports = { getContract, disconnect };
