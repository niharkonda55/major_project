#!/usr/bin/env bash
#
# Copyright IBM Corp All Rights Reserved
#
# SPDX-License-Identifier: Apache-2.0
#

# This script brings up a Hyperledger Fabric network for testing smart contracts
# and applications. The test network consists of two organizations with one
# peer each, and a single node Raft ordering service. Users can also use this
# script to create a channel deploy a chaincode on the channel
#
# prepending $PWD/../bin to PATH to ensure we are picking up the correct binaries
# this may be commented out to resolve installed version of tools if desired
#
# Use absolute paths only. SCRIPT_DIR = directory containing this script.
ROOTDIR=$(cd "$(dirname "$0")" && pwd)
export ROOTDIR

# Fabric binaries: prefer FABRIC_BIN_PATH env, then $HOME/fabric-samples/bin, then fabric-projects/fabric-samples/bin
if [ -n "${FABRIC_BIN_PATH:-}" ] && [ -d "${FABRIC_BIN_PATH}" ]; then
  :
elif [ -d "${HOME}/fabric-samples/bin" ]; then
  FABRIC_BIN_PATH="${HOME}/fabric-samples/bin"
elif [ -d "${ROOTDIR}/../../fabric-samples/bin" ]; then
  FABRIC_BIN_PATH="$(cd "${ROOTDIR}/../../fabric-samples/bin" && pwd)"
else
  FABRIC_BIN_PATH="${ROOTDIR}/../bin"
fi
export PATH="${FABRIC_BIN_PATH}:${PATH}"
export FABRIC_CFG_PATH=${PWD}/../config
export FABRIC_BIN_PATH
export VERBOSE=false

# push to the required directory & set a trap to go back if needed
pushd "${ROOTDIR}" > /dev/null
trap "popd > /dev/null" EXIT

. "${ROOTDIR}/scripts/utils.sh"

: ${CONTAINER_CLI:="docker"}
if command -v ${CONTAINER_CLI}-compose > /dev/null 2>&1; then
    : ${CONTAINER_CLI_COMPOSE:="${CONTAINER_CLI}-compose"}
else
    : ${CONTAINER_CLI_COMPOSE:="${CONTAINER_CLI} compose"}
fi
infoln "Using ${CONTAINER_CLI} and ${CONTAINER_CLI_COMPOSE}"

# Obtain CONTAINER_IDS and remove them
# This function is called when you bring a network down
function clearContainers() {
  infoln "Removing remaining containers"
  ${CONTAINER_CLI} rm -f $(${CONTAINER_CLI} ps -aq --filter label=service=hyperledger-fabric) 2>/dev/null || true
  ${CONTAINER_CLI} rm -f $(${CONTAINER_CLI} ps -aq --filter name='dev-peer*') 2>/dev/null || true
  ${CONTAINER_CLI} kill "$(${CONTAINER_CLI} ps -q --filter name=ccaas)" 2>/dev/null || true
}

# Delete any images that were generated as a part of this setup
# specifically the following images are often left behind:
# This function is called when you bring the network down
function removeUnwantedImages() {
  infoln "Removing generated chaincode docker images"
  ${CONTAINER_CLI} image rm -f $(${CONTAINER_CLI} images -aq --filter reference='dev-peer*') 2>/dev/null || true
}

# Versions of fabric known not to work with the test network
NONWORKING_VERSIONS="^1\.0\. ^1\.1\. ^1\.2\. ^1\.3\. ^1\.4\."

# Compare major.minor only; allow patch-level mismatch (e.g. 2.5.4 and 2.5.14)
version_major_minor() {
  echo "$1" | sed -n 's/^\([0-9]*\.[0-9]*\).*/\1/p'
}

# Do some basic sanity checking to make sure that the appropriate versions of fabric
# binaries/images are available.
function checkPrereqs() {
  ## Check peer binary (use absolute path when possible)
  local PEER_CMD="${FABRIC_BIN_PATH}/peer"
  [ -x "${PEER_CMD}" ] || PEER_CMD="peer"
  if ! ${PEER_CMD} version > /dev/null 2>&1; then
    errorln "Peer binary not found or not runnable. Set FABRIC_BIN_PATH or install Fabric binaries (e.g. FABRIC_BIN_PATH=$HOME/fabric-samples/bin)."
    exit 1
  fi
  LOCAL_VERSION=$(${PEER_CMD} version 2>/dev/null | sed -ne 's/^ Version: //p' | head -1)
  [ -n "$LOCAL_VERSION" ] || { errorln "Could not get peer version."; exit 1; }

  local FABRIC_IMAGE="hyperledger/fabric-peer:${IMAGETAG:-2.5}"
  DOCKER_IMAGE_VERSION=$(${CONTAINER_CLI} run --rm "${FABRIC_IMAGE}" peer version 2>/dev/null | sed -ne 's/^ Version: //p' | head -1) || DOCKER_IMAGE_VERSION=""
  if [ -z "$DOCKER_IMAGE_VERSION" ]; then
    fatalln "Docker image ${FABRIC_IMAGE} not found. Pull it or set IMAGETAG in network.config."
  fi

  infoln "LOCAL_VERSION=$LOCAL_VERSION | DOCKER_IMAGE_VERSION=$DOCKER_IMAGE_VERSION"

  # Only stop if major.minor differs; allow patch-level mismatch within 2.5.x
  local LOCAL_MM=$(version_major_minor "$LOCAL_VERSION")
  local DOCKER_MM=$(version_major_minor "$DOCKER_IMAGE_VERSION")
  if [ "$LOCAL_MM" != "$DOCKER_MM" ]; then
    fatalln "Version mismatch: local major.minor=$LOCAL_MM, docker major.minor=$DOCKER_MM. Align Fabric binaries and Docker images (e.g. 2.5.14)."
  fi

  for UNSUPPORTED_VERSION in $NONWORKING_VERSIONS; do
    if echo "$LOCAL_VERSION" | grep -q $UNSUPPORTED_VERSION; then
      fatalln "Local Fabric binary version $LOCAL_VERSION is not supported by the test network."
    fi
    if echo "$DOCKER_IMAGE_VERSION" | grep -q $UNSUPPORTED_VERSION; then
      fatalln "Fabric Docker image version $DOCKER_IMAGE_VERSION is not supported by the test network."
    fi
  done

  ## check for cfssl binaries
  if [ "$CRYPTO" == "cfssl" ]; then
  
    cfssl version > /dev/null 2>&1
    if [[ $? -ne 0 ]]; then
      errorln "cfssl binary not found.."
      errorln
      errorln "Follow the instructions to install the cfssl and cfssljson binaries:"
      errorln "https://github.com/cloudflare/cfssl#installation"
      exit 1
    fi
  fi

  ## Check for fabric-ca when using CA
  if [ "$CRYPTO" == "Certificate Authorities" ]; then
    local CA_CMD="${FABRIC_BIN_PATH}/fabric-ca-client"
    [ -x "${CA_CMD}" ] || CA_CMD="fabric-ca-client"
    if ! ${CA_CMD} version > /dev/null 2>&1; then
      errorln "fabric-ca-client binary not found. Set FABRIC_BIN_PATH (e.g. FABRIC_BIN_PATH=$HOME/fabric-samples/bin)."
      exit 1
    fi
    CA_LOCAL_VERSION=$(${CA_CMD} version 2>/dev/null | sed -ne 's/ Version: //p' | head -1)
    local CA_IMAGE="hyperledger/fabric-ca:${CA_IMAGETAG:-1.5}"
    CA_DOCKER_IMAGE_VERSION=$(${CONTAINER_CLI} run --rm "${CA_IMAGE}" fabric-ca-client version 2>/dev/null | sed -ne 's/ Version: //p' | head -1) || CA_DOCKER_IMAGE_VERSION=""
    infoln "CA_LOCAL_VERSION=$CA_LOCAL_VERSION | CA_DOCKER_IMAGE_VERSION=$CA_DOCKER_IMAGE_VERSION"
    if [ -z "$CA_DOCKER_IMAGE_VERSION" ]; then
      fatalln "Docker image ${CA_IMAGE} not found. Pull it or set CA_IMAGETAG in network.config."
    fi
    local CA_LOCAL_MM=$(version_major_minor "$CA_LOCAL_VERSION")
    local CA_DOCKER_MM=$(version_major_minor "$CA_DOCKER_IMAGE_VERSION")
    if [ "$CA_LOCAL_MM" != "$CA_DOCKER_MM" ]; then
      fatalln "CA version mismatch: local major.minor=$CA_LOCAL_MM, docker major.minor=$CA_DOCKER_MM."
    fi
  fi
}

# Before you can bring up a network, each organization needs to generate the crypto
# material that will define that organization on the network. Because Hyperledger
# Fabric is a permissioned blockchain, each node and user on the network needs to
# use certificates and keys to sign and verify its actions. In addition, each user
# needs to belong to an organization that is recognized as a member of the network.
# You can use the Cryptogen tool or Fabric CAs to generate the organization crypto
# material.

# By default, the sample network uses cryptogen. Cryptogen is a tool that is
# meant for development and testing that can quickly create the certificates and keys
# that can be consumed by a Fabric network. The cryptogen tool consumes a series
# of configuration files for each organization in the "organizations/cryptogen"
# directory. Cryptogen uses the files to generate the crypto  material for each
# org in the "organizations" directory.

# You can also use Fabric CAs to generate the crypto material. CAs sign the certificates
# and keys that they generate to create a valid root of trust for each organization.
# The script uses Docker Compose to bring up three CAs, one for each peer organization
# and the ordering organization. The configuration file for creating the Fabric CA
# servers are in the "organizations/fabric-ca" directory. Within the same directory,
# the "registerEnroll.sh" script uses the Fabric CA client to create the identities,
# certificates, and MSP folders that are needed to create the test network in the
# "organizations/ordererOrganizations" directory.

# Create Organization crypto material using cryptogen or CAs
function createOrgs() {
  if [ -d "organizations/peerOrganizations" ]; then
    rm -Rf organizations/peerOrganizations && rm -Rf organizations/ordererOrganizations
  fi

  # Create crypto material using cryptogen
  if [ "$CRYPTO" == "cryptogen" ]; then
    which cryptogen
    if [ "$?" -ne 0 ]; then
      fatalln "cryptogen tool not found. exiting"
    fi
    infoln "Generating certificates using cryptogen tool"

    infoln "Creating Org1 Identities"

    set -x
    cryptogen generate --config=./organizations/cryptogen/crypto-config-org1.yaml --output="organizations"
    res=$?
    { set +x; } 2>/dev/null
    if [ $res -ne 0 ]; then
      fatalln "Failed to generate certificates..."
    fi

    infoln "Creating Org2 Identities"

    set -x
    cryptogen generate --config=./organizations/cryptogen/crypto-config-org2.yaml --output="organizations"
    res=$?
    { set +x; } 2>/dev/null
    if [ $res -ne 0 ]; then
      fatalln "Failed to generate certificates..."
    fi

    infoln "Creating Orderer Org Identities"

    set -x
    cryptogen generate --config=./organizations/cryptogen/crypto-config-orderer.yaml --output="organizations"
    res=$?
    { set +x; } 2>/dev/null
    if [ $res -ne 0 ]; then
      fatalln "Failed to generate certificates..."
    fi

  fi

  # Create crypto material using cfssl
  if [ "$CRYPTO" == "cfssl" ]; then

    . organizations/cfssl/registerEnroll.sh
    #function_name cert-type   CN   org
    peer_cert peer peer0.org1.example.com org1
    peer_cert admin Admin@org1.example.com org1

    infoln "Creating Org2 Identities"
    #function_name cert-type   CN   org
    peer_cert peer peer0.org2.example.com org2
    peer_cert admin Admin@org2.example.com org2

    infoln "Creating Orderer Org Identities"
    #function_name cert-type   CN   
    orderer_cert orderer orderer.example.com
    orderer_cert admin Admin@example.com

  fi 

  # Create crypto material using Fabric CA
  if [ "$CRYPTO" == "Certificate Authorities" ]; then
    infoln "Generating certificates using Fabric CA"
    ${CONTAINER_CLI_COMPOSE} -f "${ROOTDIR}/compose/${COMPOSE_FILE_CA}" up -d 2>&1

    . "${ROOTDIR}/organizations/fabric-ca/registerEnroll.sh"

    # Make sure CA files have been created
    while :
    do
      if [ ! -f "organizations/fabric-ca/org1/tls-cert.pem" ]; then
        sleep 1
      else
        break
      fi
    done

    # Make sure CA service is initialized and can accept requests before making register and enroll calls
    export FABRIC_CA_CLIENT_HOME="${ROOTDIR}/organizations/peerOrganizations/org1.example.com"
    COUNTER=0
    rc=1
    while [[ $rc -ne 0 && $COUNTER -lt $MAX_RETRY ]]; do
      sleep 1
      set -x
      fabric-ca-client getcainfo -u https://admin:adminpw@localhost:7054 --caname ca-org1 --tls.certfiles "${ROOTDIR}/organizations/fabric-ca/org1/ca-cert.pem"
      res=$?
    { set +x; } 2>/dev/null
    rc=$res  # Update rc
    COUNTER=$((COUNTER + 1))
    done

    infoln "Creating Org1 Identities"

    createOrg1

    infoln "Creating Org2 Identities"

    createOrg2

    infoln "Creating Orderer Org Identities"

    createOrderer

  fi

  infoln "Generating CCP files for Org1 and Org2"
  [ -x "${ROOTDIR}/organizations/ccp-generate.sh" ] && chmod +x "${ROOTDIR}/organizations/ccp-generate.sh"
  "${ROOTDIR}/organizations/ccp-generate.sh"
}

# Once you create the organization crypto material, you need to create the
# genesis block of the application channel.

# The configtxgen tool is used to create the genesis block. Configtxgen consumes a
# "configtx.yaml" file that contains the definitions for the sample network. The
# genesis block is defined using the "ChannelUsingRaft" profile at the bottom
# of the file. This profile defines an application channel consisting of our two Peer Orgs.
# The peer and ordering organizations are defined in the "Profiles" section at the
# top of the file. As part of each organization profile, the file points to the
# location of the MSP directory for each member. This MSP is used to create the channel
# MSP that defines the root of trust for each organization. In essence, the channel
# MSP allows the nodes and users to be recognized as network members.
#
# If you receive the following warning, it can be safely ignored:
#
# [bccsp] GetDefault -> WARN 001 Before using BCCSP, please call InitFactories(). Falling back to bootBCCSP.
#
# You can ignore the logs regarding intermediate certs, we are not using them in
# this crypto implementation.

# After we create the org crypto material and the application channel genesis block,
# we can now bring up the peers and ordering service. By default, the base
# file for creating the network is "docker-compose-test-net.yaml" in the ``docker``
# folder. This file defines the environment variables and file mounts that
# point the crypto material and genesis block that were created in earlier.

# Pre-flight: binaries, images, configtx, compose files exist. Non-destructive.
function preFlightChecks() {
  infoln "Pre-flight checks..."
  local err=0
  [ -x "${FABRIC_BIN_PATH}/peer" ] || [ -n "$(command -v peer)" ] || { errorln "Fabric peer binary not found. Set FABRIC_BIN_PATH (e.g. \$HOME/fabric-samples/bin)."; err=1; }
  [ -f "${ROOTDIR}/configtx/configtx.yaml" ] || { errorln "configtx.yaml not found at ${ROOTDIR}/configtx/configtx.yaml"; err=1; }
  [ -f "${ROOTDIR}/compose/${COMPOSE_FILE_BASE}" ] || { errorln "Compose file not found: ${ROOTDIR}/compose/${COMPOSE_FILE_BASE}"; err=1; }
  [ -f "${ROOTDIR}/compose/${COMPOSE_FILE_CA}" ] || { errorln "Compose CA file not found: ${ROOTDIR}/compose/${COMPOSE_FILE_CA}"; err=1; }
  if [ "${DATABASE}" = "couchdb" ]; then
    [ -f "${ROOTDIR}/compose/${COMPOSE_FILE_COUCH}" ] || { errorln "Compose couch file not found: ${ROOTDIR}/compose/${COMPOSE_FILE_COUCH}"; err=1; }
  fi
  if [ "$CRYPTO" = "Certificate Authorities" ]; then
    [ -f "${ROOTDIR}/organizations/fabric-ca/registerEnroll.sh" ] || { errorln "Missing ${ROOTDIR}/organizations/fabric-ca/registerEnroll.sh"; err=1; }
    [ -f "${ROOTDIR}/organizations/ccp-generate.sh" ] || { errorln "Missing ${ROOTDIR}/organizations/ccp-generate.sh"; err=1; }
  fi
  ${CONTAINER_CLI} info > /dev/null 2>&1 || { errorln "Docker is not running or not accessible."; err=1; }
  [ $err -eq 0 ] || exit 1
  successln "Pre-flight OK"
}

# Bring up the peer and orderer nodes using docker compose.
function networkUp() {
  preFlightChecks
  checkPrereqs

  # generate artifacts if they don't exist
  if [ ! -d "organizations/peerOrganizations" ]; then
    createOrgs
  fi

  COMPOSE_FILES="-f ${ROOTDIR}/compose/${COMPOSE_FILE_BASE} -f ${ROOTDIR}/compose/${CONTAINER_CLI}/${CONTAINER_CLI}-${COMPOSE_FILE_BASE}"

  if [ "${DATABASE}" == "couchdb" ]; then
    COMPOSE_FILES="${COMPOSE_FILES} -f ${ROOTDIR}/compose/${COMPOSE_FILE_COUCH}"
  fi

  DOCKER_SOCK="${DOCKER_SOCK}" ${CONTAINER_CLI_COMPOSE} ${COMPOSE_FILES} up -d 2>&1

  $CONTAINER_CLI ps -a
  if [ $? -ne 0 ]; then
    fatalln "Unable to start network"
  fi
}

# call the script to create the channel, join the peers of org1 and org2,
# and then update the anchor peers for each organization
function createChannel() {
  # Bring up the network if it is not already up.
  bringUpNetwork="false"

  local bft_true=$1

  if ! $CONTAINER_CLI info > /dev/null 2>&1 ; then
    fatalln "$CONTAINER_CLI network is required to be running to create a channel"
  fi

  # check if all containers are present
  CONTAINERS=($($CONTAINER_CLI ps | grep hyperledger/ | awk '{print $2}'))
  len=$(echo ${#CONTAINERS[@]})

  if [[ $len -ge 4 ]] && [[ ! -d "organizations/peerOrganizations" ]]; then
    echo "Bringing network down to sync certs with containers"
    networkDown
  fi

  [[ $len -lt 4 ]] || [[ ! -d "organizations/peerOrganizations" ]] && bringUpNetwork="true" || echo "Network Running Already"

  if [ $bringUpNetwork == "true"  ]; then
    infoln "Bringing up network"
    networkUp
  fi

  # now run the script that creates a channel. This script uses configtxgen once
  # to create the channel creation transaction and the anchor peer updates.
  TEST_NETWORK_HOME="${ROOTDIR}" "${ROOTDIR}/scripts/createChannel.sh" "$CHANNEL_NAME" "$CLI_DELAY" "$MAX_RETRY" "$VERBOSE" "$bft_true"
}


## Call the script to deploy a chaincode to the channel
function deployCC() {
  "${ROOTDIR}/scripts/deployCC.sh" "$CHANNEL_NAME" "$CC_NAME" "$CC_SRC_PATH" "$CC_SRC_LANGUAGE" "$CC_VERSION" "$CC_SEQUENCE" "$CC_INIT_FCN" "$CC_END_POLICY" "$CC_COLL_CONFIG" "$CLI_DELAY" "$MAX_RETRY" "$VERBOSE"

  if [ $? -ne 0 ]; then
    fatalln "Deploying chaincode failed"
  fi
}

## Call the script to deploy a chaincode to the channel
function deployCCAAS() {
  "${ROOTDIR}/scripts/deployCCAAS.sh" "$CHANNEL_NAME" "$CC_NAME" "$CC_SRC_PATH" "$CCAAS_DOCKER_RUN" "$CC_VERSION" "$CC_SEQUENCE" "$CC_INIT_FCN" "$CC_END_POLICY" "$CC_COLL_CONFIG" "$CLI_DELAY" "$MAX_RETRY" "$VERBOSE" "$CCAAS_DOCKER_RUN"

  if [ $? -ne 0 ]; then
    fatalln "Deploying chaincode-as-a-service failed"
  fi
}

## Call the script to package the chaincode
function packageChaincode() {

  infoln "Packaging chaincode"

  "${ROOTDIR}/scripts/packageCC.sh" "$CC_NAME" "$CC_SRC_PATH" "$CC_SRC_LANGUAGE" "$CC_VERSION" true

  if [ $? -ne 0 ]; then
    fatalln "Packaging the chaincode failed"
  fi

}

## Call the script to list installed and committed chaincode on a peer
function listChaincode() {

  export FABRIC_CFG_PATH="${ROOTDIR}/configtx"
  export TEST_NETWORK_HOME="${ROOTDIR}"

  . "${ROOTDIR}/scripts/envVar.sh"
  . "${ROOTDIR}/scripts/ccutils.sh"

  setGlobals $ORG

  println
  queryInstalledOnPeer
  println

  listAllCommitted

}

## Call the script to invoke 
function invokeChaincode() {

  export FABRIC_CFG_PATH="${ROOTDIR}/configtx"
  export TEST_NETWORK_HOME="${ROOTDIR}"

  . "${ROOTDIR}/scripts/envVar.sh"
  . "${ROOTDIR}/scripts/ccutils.sh"

  setGlobals $ORG

  chaincodeInvoke $ORG $CHANNEL_NAME $CC_NAME $CC_INVOKE_CONSTRUCTOR

}

## Call the script to query chaincode 
function queryChaincode() {

  export FABRIC_CFG_PATH="${ROOTDIR}/configtx"
  export TEST_NETWORK_HOME="${ROOTDIR}"

  . "${ROOTDIR}/scripts/envVar.sh"
  . "${ROOTDIR}/scripts/ccutils.sh"

  setGlobals $ORG

  chaincodeQuery $ORG $CHANNEL_NAME $CC_NAME $CC_QUERY_CONSTRUCTOR

}


# Tear down running network
function networkDown() {
  local temp_compose=$COMPOSE_FILE_BASE
  COMPOSE_FILE_BASE=compose-bft-test-net.yaml
  COMPOSE_BASE_FILES="-f ${ROOTDIR}/compose/${COMPOSE_FILE_BASE} -f ${ROOTDIR}/compose/${CONTAINER_CLI}/${CONTAINER_CLI}-${COMPOSE_FILE_BASE}"
  COMPOSE_COUCH_FILES="-f ${ROOTDIR}/compose/${COMPOSE_FILE_COUCH}"
  COMPOSE_CA_FILES="-f ${ROOTDIR}/compose/${COMPOSE_FILE_CA}"
  COMPOSE_FILES="${COMPOSE_BASE_FILES} ${COMPOSE_COUCH_FILES} ${COMPOSE_CA_FILES}"

  # stop org3 containers also in addition to org1 and org2, in case we were running sample to add org3
  COMPOSE_ORG3_BASE_FILES="-f ${ROOTDIR}/addOrg3/compose/${COMPOSE_FILE_ORG3_BASE} -f ${ROOTDIR}/addOrg3/compose/${CONTAINER_CLI}/${CONTAINER_CLI}-${COMPOSE_FILE_ORG3_BASE}"
  COMPOSE_ORG3_COUCH_FILES="-f ${ROOTDIR}/addOrg3/compose/${COMPOSE_FILE_ORG3_COUCH} -f ${ROOTDIR}/addOrg3/compose/${CONTAINER_CLI}/${CONTAINER_CLI}-${COMPOSE_FILE_ORG3_COUCH}"
  COMPOSE_ORG3_CA_FILES="-f ${ROOTDIR}/addOrg3/compose/${COMPOSE_FILE_ORG3_CA} -f ${ROOTDIR}/addOrg3/compose/${CONTAINER_CLI}/${CONTAINER_CLI}-${COMPOSE_FILE_ORG3_CA}"
  COMPOSE_ORG3_FILES="${COMPOSE_ORG3_BASE_FILES} ${COMPOSE_ORG3_COUCH_FILES} ${COMPOSE_ORG3_CA_FILES}"

  if [ "${CONTAINER_CLI}" == "docker" ]; then
    DOCKER_SOCK=$DOCKER_SOCK ${CONTAINER_CLI_COMPOSE} ${COMPOSE_FILES} ${COMPOSE_ORG3_FILES} down --volumes --remove-orphans
  elif [ "${CONTAINER_CLI}" == "podman" ]; then
    ${CONTAINER_CLI_COMPOSE} ${COMPOSE_FILES} ${COMPOSE_ORG3_FILES} down --volumes
  else
    fatalln "Container CLI  ${CONTAINER_CLI} not supported"
  fi

  COMPOSE_FILE_BASE=$temp_compose

  # Don't remove the generated artifacts -- note, the ledgers are always removed
  if [ "$MODE" != "restart" ]; then
    # Bring down the network, deleting the volumes
    ${CONTAINER_CLI} volume rm docker_orderer.example.com docker_peer0.org1.example.com docker_peer0.org2.example.com
    #Cleanup the chaincode containers
    clearContainers
    #Cleanup images
    removeUnwantedImages
    # remove orderer block and other channel configuration transactions and certs
    ${CONTAINER_CLI} run --rm -v "$(pwd):/data" busybox sh -c 'cd /data && rm -rf system-genesis-block/*.block organizations/peerOrganizations organizations/ordererOrganizations'
    ## remove fabric ca artifacts
    ${CONTAINER_CLI} run --rm -v "$(pwd):/data" busybox sh -c 'cd /data && rm -rf organizations/fabric-ca/org1/msp organizations/fabric-ca/org1/tls-cert.pem organizations/fabric-ca/org1/ca-cert.pem organizations/fabric-ca/org1/IssuerPublicKey organizations/fabric-ca/org1/IssuerRevocationPublicKey organizations/fabric-ca/org1/fabric-ca-server.db'
    ${CONTAINER_CLI} run --rm -v "$(pwd):/data" busybox sh -c 'cd /data && rm -rf organizations/fabric-ca/org2/msp organizations/fabric-ca/org2/tls-cert.pem organizations/fabric-ca/org2/ca-cert.pem organizations/fabric-ca/org2/IssuerPublicKey organizations/fabric-ca/org2/IssuerRevocationPublicKey organizations/fabric-ca/org2/fabric-ca-server.db'
    ${CONTAINER_CLI} run --rm -v "$(pwd):/data" busybox sh -c 'cd /data && rm -rf organizations/fabric-ca/ordererOrg/msp organizations/fabric-ca/ordererOrg/tls-cert.pem organizations/fabric-ca/ordererOrg/ca-cert.pem organizations/fabric-ca/ordererOrg/IssuerPublicKey organizations/fabric-ca/ordererOrg/IssuerRevocationPublicKey organizations/fabric-ca/ordererOrg/fabric-ca-server.db'
    ${CONTAINER_CLI} run --rm -v "$(pwd):/data" busybox sh -c 'cd /data && rm -rf addOrg3/fabric-ca/org3/msp addOrg3/fabric-ca/org3/tls-cert.pem addOrg3/fabric-ca/org3/ca-cert.pem addOrg3/fabric-ca/org3/IssuerPublicKey addOrg3/fabric-ca/org3/IssuerRevocationPublicKey addOrg3/fabric-ca/org3/fabric-ca-server.db'
    # remove channel and script artifacts
    ${CONTAINER_CLI} run --rm -v "$(pwd):/data" busybox sh -c 'cd /data && rm -rf channel-artifacts log.txt *.tar.gz'
  fi
}

. "${ROOTDIR}/network.config"

# use this as the default docker-compose yaml definition
COMPOSE_FILE_BASE=compose-test-net.yaml
# docker-compose.yaml file if you are using couchdb
COMPOSE_FILE_COUCH=compose-couch.yaml
# certificate authorities compose file
COMPOSE_FILE_CA=compose-ca.yaml
# use this as the default docker-compose yaml definition for org3
COMPOSE_FILE_ORG3_BASE=compose-org3.yaml
# use this as the docker compose couch file for org3
COMPOSE_FILE_ORG3_COUCH=compose-couch-org3.yaml
# certificate authorities compose file
COMPOSE_FILE_ORG3_CA=compose-ca-org3.yaml
#

# Get docker sock path from environment variable
SOCK="${DOCKER_HOST:-/var/run/docker.sock}"
DOCKER_SOCK="${SOCK##unix://}"

# BFT activated flag
BFT=0

# Parse commandline args

## Parse mode
if [[ $# -lt 1 ]] ; then
  printHelp
  exit 0
else
  MODE=$1
  shift
fi

## if no parameters are passed, show the help for cc
if [ "$MODE" == "cc" ] && [[ $# -lt 1 ]]; then
  printHelp $MODE
  exit 0
fi

# parse subcommands if used
if [[ $# -ge 1 ]] ; then
  key="$1"
  # check for the createChannel subcommand
  if [[ "$key" == "createChannel" ]]; then
      export MODE="createChannel"
      shift
  # check for the cc command
  elif [[ "$MODE" == "cc" ]]; then
    if [ "$1" != "-h" ]; then
      export SUBCOMMAND=$key
      shift
    fi
  fi
fi


# parse flags

while [[ $# -ge 1 ]] ; do
  key="$1"
  case $key in
  -h )
    printHelp $MODE
    exit 0
    ;;
  -c )
    CHANNEL_NAME="$2"
    shift
    ;;
  -bft )
    BFT=1
    ;;
  -ca )
    CRYPTO="Certificate Authorities"
    ;;
  -cfssl )
    CRYPTO="cfssl"
    ;;
  -r )
    MAX_RETRY="$2"
    shift
    ;;
  -d )
    CLI_DELAY="$2"
    shift
    ;;
  -s )
    DATABASE="$2"
    shift
    ;;
  -ccl )
    CC_SRC_LANGUAGE="$2"
    shift
    ;;
  -ccn )
    CC_NAME="$2"
    shift
    ;;
  -ccv )
    CC_VERSION="$2"
    shift
    ;;
  -ccs )
    CC_SEQUENCE="$2"
    shift
    ;;
  -ccp )
    CC_SRC_PATH="$2"
    shift
    ;;
  -ccep )
    CC_END_POLICY="$2"
    shift
    ;;
  -cccg )
    CC_COLL_CONFIG="$2"
    shift
    ;;
  -cci )
    CC_INIT_FCN="$2"
    shift
    ;;
  -ccaasdocker )
    CCAAS_DOCKER_RUN="$2"
    shift
    ;;
  -verbose )
    VERBOSE=true
    ;;
  -org )
    ORG="$2"
    shift
    ;;
  -i )
    IMAGETAG="$2"
    shift
    ;;
  -cai )
    CA_IMAGETAG="$2"
    shift
    ;;
  -ccic )
    CC_INVOKE_CONSTRUCTOR="$2"
    shift
    ;;
  -ccqc )
    CC_QUERY_CONSTRUCTOR="$2"
    shift
    ;;    
  * )
    errorln "Unknown flag: $key"
    printHelp
    exit 1
    ;;
  esac
  shift
done

if [ $BFT -eq 1 ]; then
  export FABRIC_CFG_PATH=$HOME/fabric-projects/fabric-samples/config
  COMPOSE_FILE_BASE=compose-bft-test-net.yaml
fi

# Are we generating crypto material with this command?
if [ ! -d "organizations/peerOrganizations" ]; then
  CRYPTO_MODE="with crypto from '${CRYPTO}'"
else
  CRYPTO_MODE=""
fi

# Determine mode of operation and printing out what we asked for
if [ "$MODE" == "prereq" ]; then
  infoln "Installing binaries and fabric images. Fabric Version: ${IMAGETAG}  Fabric CA Version: ${CA_IMAGETAG}"
  installPrereqs
elif [ "$MODE" == "up" ]; then
  infoln "Starting nodes with CLI timeout of '${MAX_RETRY}' tries and CLI delay of '${CLI_DELAY}' seconds and using database '${DATABASE}' ${CRYPTO_MODE}"
  networkUp
elif [ "$MODE" == "createChannel" ]; then
  infoln "Creating channel '${CHANNEL_NAME}'."
  infoln "If network is not up, starting nodes with CLI timeout of '${MAX_RETRY}' tries and CLI delay of '${CLI_DELAY}' seconds and using database '${DATABASE} ${CRYPTO_MODE}"
  createChannel $BFT
elif [ "$MODE" == "down" ]; then
  infoln "Stopping network"
  networkDown
elif [ "$MODE" == "restart" ]; then
  infoln "Restarting network"
  networkDown
  networkUp
elif [ "$MODE" == "deployCC" ]; then
  infoln "deploying chaincode on channel '${CHANNEL_NAME}'"
  deployCC
elif [ "$MODE" == "deployCCAAS" ]; then
  infoln "deploying chaincode-as-a-service on channel '${CHANNEL_NAME}'"
  deployCCAAS
elif [ "$MODE" == "cc" ] && [ "$SUBCOMMAND" == "package" ]; then
  packageChaincode
elif [ "$MODE" == "cc" ] && [ "$SUBCOMMAND" == "list" ]; then
  listChaincode
elif [ "$MODE" == "cc" ] && [ "$SUBCOMMAND" == "invoke" ]; then
  invokeChaincode
elif [ "$MODE" == "cc" ] && [ "$SUBCOMMAND" == "query" ]; then
  queryChaincode
else
  printHelp
  exit 1
fi
