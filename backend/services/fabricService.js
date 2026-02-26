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
  const orgDomain = org === 'revenuedept' ? 'org1.example.com' : 'org2.example.com';
  const connFileName = org === 'revenuedept' ? 'connection-org1.json' : 'connection-org2.json';
  const ccpPath = path.resolve(process.env.CONNECTION_PROFILE || path.join(base, `network/land-registry-network/organizations/peerOrganizations/${orgDomain}/${connFileName}`));

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
    discovery: { enabled: false }
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
