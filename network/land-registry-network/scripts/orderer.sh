#!/usr/bin/env bash

channel_name=$1

# Use ROOTDIR/TEST_NETWORK_HOME from parent or derive; prefer existing PATH (FABRIC_BIN_PATH set by network.sh)
NETWORK_ROOT="${ROOTDIR:-${TEST_NETWORK_HOME:-$(cd "$(dirname "$0")/.." && pwd)}}"
export PATH="${NETWORK_ROOT}/../bin:${FABRIC_BIN_PATH:-}:${PATH}"
export ORDERER_ADMIN_TLS_SIGN_CERT="${NETWORK_ROOT}/organizations/ordererOrganizations/example.com/orderers/orderer.example.com/tls/server.crt"
export ORDERER_ADMIN_TLS_PRIVATE_KEY="${NETWORK_ROOT}/organizations/ordererOrganizations/example.com/orderers/orderer.example.com/tls/server.key"

osnadmin channel join --channelID ${channel_name} --config-block "${NETWORK_ROOT}/channel-artifacts/${channel_name}.block" -o localhost:7053 --ca-file "$ORDERER_CA" --client-cert "$ORDERER_ADMIN_TLS_SIGN_CERT" --client-key "$ORDERER_ADMIN_TLS_PRIVATE_KEY" >> log.txt 2>&1