#!/usr/bin/env node
/**
 * Copy Admin MSP to Fabric wallet for backend
 * Run from backend dir: node scripts/copyAdminToWallet.js
 */

require('dotenv').config({ path: require('path').join(__dirname, '../.env') });
const { Wallets } = require('fabric-network');
const fs = require('fs');
const path = require('path');

async function main() {
  const base = path.resolve(__dirname, '../..');
  const walletPath = path.resolve(process.env.WALLET_PATH || path.join(base, 'backend/wallet'));
  const wallet = await Wallets.newFileSystemWallet(walletPath);

  const networkRoot = path.join(base, 'network/land-registry-network');
  const adminPath = path.join(networkRoot, 'organizations/peerOrganizations/org1.example.com/users/Admin@org1.example.com/msp');

  if (!fs.existsSync(adminPath)) {
    console.error('Admin MSP not found. Run network.sh up -ca first.');
    process.exit(1);
  }

  const certPath = path.join(adminPath, 'signcerts');
  const keyPath = path.join(adminPath, 'keystore');
  const certFiles = fs.readdirSync(certPath).filter(f => f.endsWith('.pem') || f.endsWith('.crt'));
  const keyFiles = fs.readdirSync(keyPath);

  if (!certFiles.length || !keyFiles.length) {
    throw new Error('Admin cert or key not found in MSP');
  }
  const certificate = fs.readFileSync(path.join(certPath, certFiles[0])).toString();
  const privateKey = fs.readFileSync(path.join(keyPath, keyFiles[0])).toString();

  const identity = {
    credentials: { certificate, privateKey },
    mspId: 'Org1MSP',
    type: 'X.509'
  };

  await wallet.put('Admin@revenuedept', identity);
  console.log('Admin@revenuedept added to wallet');
}

main().catch(err => {
  console.error(err);
  process.exit(1);
});
