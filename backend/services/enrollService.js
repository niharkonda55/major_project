/**
 * Fabric CA Enroll Service
 * Register and enroll users with ABAC attributes
 */

const FabricCAServices = require('fabric-ca-client');
const { Wallets } = require('fabric-network');
const path = require('path');
const fs = require('fs');

async function enrollUser(org, userId, userSecret) {
  const base = path.resolve(__dirname, '../..');
  const caUrl = org === 'revenuedept' ? (process.env.CA_REVENUEDEPT_URL || 'https://localhost:7054') : (process.env.CA_REGIONALOFFICE_URL || 'https://localhost:8054');
  const orgNumber = org === 'revenuedept' ? 'org1' : 'org2';
  const caCertPath = path.resolve(process.env.CA_TLS_CERT || path.join(base, `network/land-registry-network/organizations/fabric-ca/${orgNumber}/ca-cert.pem`));

  const ca = new FabricCAServices(caUrl, { trustedRoots: fs.readFileSync(caCertPath), verify: false });
  const walletPath = path.resolve(process.env.WALLET_PATH || path.join(base, 'backend/wallet'));
  const wallet = await Wallets.newFileSystemWallet(walletPath);

  const mspId = org === 'revenuedept' ? 'Org1MSP' : 'Org2MSP';
  const identityLabel = `${userId}@${org}`;

  const identity = await wallet.get(identityLabel);
  if (identity) {
    return { message: `${identityLabel} already enrolled`, identity: identityLabel };
  }

  const enrollment = await ca.enroll({
    enrollmentID: userId,
    enrollmentSecret: userSecret
  });

  const x509Identity = {
    credentials: {
      certificate: enrollment.certificate,
      privateKey: enrollment.key.toBytes()
    },
    mspId,
    type: 'X.509'
  };

  await wallet.put(identityLabel, x509Identity);
  return { message: `Enrolled ${identityLabel}`, identity: identityLabel };
}

module.exports = { enrollUser };
