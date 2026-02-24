# Land Registry Blockchain - Setup & Deployment Guide

Production-grade Blockchain-Based Land Registration & Tokenization System using Hyperledger Fabric.

## Architecture Overview

- **Blockchain**: Hyperledger Fabric (RAFT, CouchDB, Fabric CA, TLS)
- **Organizations**: RevenueDeptMSP, RegionalOfficeMSP
- **Channel**: landregistrychannel
- **Endorsement**: AND(RevenueDeptMSP.peer, RegionalOfficeMSP.peer)
- **Chaincode**: land-token (Node.js, ABAC enforced)
- **Backend**: Node.js + Express + Supabase (read cache)

## Prerequisites

- Docker & Docker Compose
- Node.js 18+
- Hyperledger Fabric binaries (`peer`, `configtxgen`, `configtxlator`, `osnadmin`, `fabric-ca-client`, `jq`)
- Git

## Directory Structure

```
major/
├── land-registry/
│   ├── network/land-registry-network/   # Fabric network (modified test-network)
│   ├── chaincode/land-token/            # Node.js chaincode
│   ├── backend/                         # Express API
│   └── supabase/schema.sql
└── fabric-samples/                      # Source of bin/ and config/
```

## Step 1: Install Fabric Binaries

If not already installed:

```bash
# Download Fabric (adjust version as needed)
curl -sSL https://raw.githubusercontent.com/hyperledger/fabric/main/scripts/bootstrap.sh | bash -s -- 2.5.4 1.5.6 -d

# Add bin and config to path - copy/symlink to network folder
# From fabric-samples:
cp -r fabric-samples/bin land-registry/network/
cp -r fabric-samples/config land-registry/network/
```

Or set PATH to your existing Fabric installation:

```bash
export PATH=$PATH:/path/to/fabric-samples/bin
export FABRIC_CFG_PATH=/path/to/fabric-samples/config
```

The `network.sh` expects `../bin` and `../config` relative to `land-registry-network`. Ensure:

- `land-registry/network/bin/` exists (peer, configtxgen, etc.)
- `land-registry/network/config/` exists (core.yaml)

## Step 2: Start Blockchain Network (Docker)

```bash
cd land-registry/network/land-registry-network

# Start network with Fabric CA and CouchDB
./network.sh up -ca -s couchdb

# Create channel
./network.sh createChannel -c landregistrychannel

# Deploy chaincode (path relative to land-registry-network)
./network.sh deployCC -ccn land-token -ccp ../../chaincode/land-token -ccl javascript -ccep "AND('RevenueDeptMSP.peer','RegionalOfficeMSP.peer')"
```

**Expected output**: Peers, orderer, CAs, CouchDB running. Channel created. Chaincode installed and committed.

## Step 3: Setup Backend

```bash
cd land-registry/backend

# Install dependencies
npm install

# Copy env template
cp .env.example .env

# Edit .env - set SUPABASE_URL, SUPABASE_SERVICE_KEY
# Paths are relative to backend/ - adjust if needed
```

**Copy Admin identity to wallet** (for queries):

```bash
node scripts/copyAdminToWallet.js
```

**Enroll VRO/MRO users** (for create/transfer):

```bash
# Enroll VRO (createLandRecord)
node scripts/enrollUser.js revenuedept vro1 vro1pw

# Enroll MRO (transferLand)
node scripts/enrollUser.js revenuedept mro1 mro1pw
```

## Step 4: Setup Supabase

1. Create project at [supabase.com](https://supabase.com)
2. Run `supabase/schema.sql` in SQL Editor
3. Add `SUPABASE_URL` and `SUPABASE_SERVICE_KEY` to backend `.env`

## Step 5: Run Backend

```bash
cd land-registry-project/backend
npm start
```

API available at `http://localhost:3000`

## Step 6: Run Frontend (if applicable)

If you have a frontend:

```bash
cd land-registry/frontend
npm install
npm start
```

(Add frontend setup if/when frontend is created.)

---

# Full Deployment Commands (Quick Reference)

## Start Everything

```bash
# Terminal 1 - Blockchain
cd land-registry/network/land-registry-network
./network.sh up -ca -s couchdb
./network.sh createChannel -c landregistrychannel
./network.sh deployCC -ccn land-token -ccp ../../../land-registry-project/chaincode/land-token -ccl javascript -ccep "AND('RevenueDeptMSP.peer','RegionalOfficeMSP.peer')"

# Terminal 2 - Backend
cd land-registry/backend
npm install && cp .env.example .env
node scripts/copyAdminToWallet.js
node scripts/enrollUser.js revenuedept vro1 vro1pw
node scripts/enrollUser.js revenuedept mro1 mro1pw
npm start
```

## Shutdown

```bash
cd land-registry/network/land-registry-network
./network.sh down
```

## Clean Restart (removes crypto, channel artifacts)

```bash
./network.sh down
# Then run Step 2 again
```

---

# API Examples

```bash
# Create land record (VRO identity)
curl -X POST http://localhost:3000/api/land/create \
  -H "Content-Type: application/json" \
  -d '{"surveyNumber":"SURV001","subdivisionNumber":"1","area":"100.5","ownerId":"OWN001","documentHash":"hash123","officerApproval":"Approved","identity":"vro1@revenuedept"}'

# Get land by property ID
curl "http://localhost:3000/api/land/<propertyId>"

# Transfer land (MRO identity)
curl -X POST http://localhost:3000/api/land/transfer \
  -H "Content-Type: application/json" \
  -d '{"propertyId":"LAND-xxx","newOwnerId":"OWN002","identity":"mro1@revenuedept"}'

# Get transfer history
curl "http://localhost:3000/api/land/<propertyId>/history"
```

---

# Troubleshooting

| Issue | Fix |
|-------|-----|
| `peer version` not found | Add Fabric bin to PATH; ensure `../bin` exists from network dir |
| Channel creation fails | Wait 10s after `up`; check orderer logs |
| Chaincode install fails | Verify chaincode path; run `npm install` in chaincode dir |
| Backend "Identity not found" | Run `copyAdminToWallet.js` and `enrollUser.js` |
| Supabase sync errors | Optional - backend works without Supabase; set env vars if using |
