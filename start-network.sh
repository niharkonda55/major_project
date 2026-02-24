#!/usr/bin/env bash
# Quick start - Land Registry Blockchain Network
# Run from major/ directory

set -e
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"
NETWORK_DIR="land-registry/network/land-registry-network"
CHAINCODE_PATH="../../chaincode/land-token"

cd "$NETWORK_DIR"
echo "Starting network with CA and CouchDB..."
./network.sh up -ca -s couchdb

echo "Creating landregistrychannel..."
./network.sh createChannel -c landregistrychannel

echo "Deploying land-token chaincode..."
./network.sh deployCC -ccn land-token -ccp "$CHAINCODE_PATH" -ccl javascript -ccep "AND('RevenueDeptMSP.peer','RegionalOfficeMSP.peer')"

echo "Network ready. Run backend: cd land-registry/backend && npm start"
