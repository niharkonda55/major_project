# Land Registry Blockchain

Blockchain-based Land Registration & Tokenization System.

## Structure

```
land-registry/
├── network/land-registry-network/   # Fabric network (RAFT, CouchDB, Fabric CA)
├── chaincode/land-token/            # Node.js chaincode (ABAC: VRO, MRO)
├── backend/                         # Express API + Fabric + Supabase
└── supabase/schema.sql
```

## Quick Start

```bash
# Start network
cd network/land-registry-network
./network.sh up -ca -s couchdb
./network.sh createChannel -c landregistrychannel
./network.sh deployCC -ccn land-token -ccp ../../chaincode/land-token -ccl javascript -ccep "AND('RevenueDeptMSP.peer','RegionalOfficeMSP.peer')"

# Start backend
cd ../backend
npm install && cp .env.example .env
node scripts/copyAdminToWallet.js
node scripts/enrollUser.js revenuedept vro1 vro1pw
node scripts/enrollUser.js revenuedept mro1 mro1pw
npm start
```
