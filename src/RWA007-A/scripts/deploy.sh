#!/bin/bash
set -eo pipefail

[ "$2" = "--estimate" ] && {
    ESTIMATE=true
}

source "${BASH_SOURCE%/*}/../../../scripts/_common.sh"

NETWORK=$1
[[ "$NETWORK" && ("$NETWORK" == "mainnet" || "$NETWORK" == "goerli" || "$NETWORK" == "ces-goerli") ]] || die "Please set NETWORK to one of ('mainnet', 'goelri', 'ces-goerli')"

# shellcheck disable=SC1091
source "${BASH_SOURCE%/*}/../../../scripts/build-env-addresses.sh" $NETWORK >&2

[[ "$ETH_RPC_URL" && "$(seth chain)" == "${NETWORK}" ]] || die "Please set a "${NETWORK}" ETH_RPC_URL"

export ETH_GAS=6000000

[[ -z "$NAME" ]] && export NAME="RWA-007AT2"
[[ -z "$SYMBOL" ]] && export SYMBOL="RWA007AT2"
#
# WARNING (2021-09-08): The system cannot currently accomodate any LETTER beyond
# "A".  To add more letters, we will need to update the PIP naming convention
# naming convention.  So, before we can have new letters we must:
# 1. Change the existing PIP naming convention
# 2. Change all the places that depend on that convention (this script included)
# 3. Make sure all integrations are ready to accomodate that new PIP name.
# ! TODO: check with team/PE if this is still the case
#
[[ -z "$LETTER" ]] && export LETTER="A"

ILK="${SYMBOL}-${LETTER}"
debug "ILK: ${ILK}"
ILK_ENCODED="$(cast --from-ascii "$ILK" | cast --to-bytes32)"


make build

FORGE_SCRIPT="${BASH_SOURCE%/*}/../../../scripts/forge-script.sh"
FORGE_VERIFY="${BASH_SOURCE%/*}/../../../scripts/forge-verify.sh"
FORGE_DEPLOY="${BASH_SOURCE%/*}/../../../scripts/forge-deploy.sh"


# estimate
[ "$ESTIMATE" = "true" ] && {
    $FORGE_SCRIPT "${BASH_SOURCE%/*}/RWA007Deployment.s.sol:RWA007Deployment" "--estimate"
    exit 0
}

# We should remove deploying of RwaToke and RwaJoin and use Foundry script after Foundry fix the bug related to deploying contract with internal transaction

# tokenize it
[[ -z "$RWA_TOKEN" ]] && {
	debug 'WARNING: `$RWA_TOKEN` not set. Deploying it...'
	TX=$($CAST_SEND "${RWA_TOKEN_FAB}" 'createRwaToken(string,string,address)' "$NAME" "$SYMBOL" "$MCD_PAUSE_PROXY")
	debug "TX: $TX"

	RECEIPT="$(cast receipt --json $TX)"
	TX_STATUS="$(jq -r '.status' <<<"$RECEIPT")"
	[[ "$TX_STATUS" != "0x1" ]] && die "Failed to create ${SYMBOL} token in tx ${TX}."

	export RWA_TOKEN=$(cast --to-checksum-address "$(jq -r ".logs[0].address" <<<"$RECEIPT")")
	debug "${SYMBOL}: ${RWA_TOKEN}"
}

# join it
[[ -z "$RWA_JOIN" ]] && {
	TX=$($CAST_SEND "${JOIN_FAB}" 'newAuthGemJoin(address,bytes32,address)' "$MCD_PAUSE_PROXY" "$ILK_ENCODED" "$RWA_TOKEN")
    debug "TX: $TX"

    RECEIPT="$(cast receipt --json $TX)"
    TX_STATUS="$(jq -r '.status' <<<"$RECEIPT")"
    [[ "$TX_STATUS" != "0x1" ]] && die "Failed to create ${SYMBOL} token in tx ${TX}."

	export RWA_JOIN=$(cast --to-checksum-address "$(jq -r ".logs[0].address" <<<"$RECEIPT")")
	debug "MCD_JOIN_${SYMBOL}_${LETTER}: ${RWA_JOIN}"
}

RESULT=($FORGE_SCRIPT "${BASH_SOURCE%/*}/RWA007Deployment.s.sol:RWA007Deployment")
jq -R 'fromjson? | .logs | .[]' <<<"$RESULT" | xargs -I@ cast --to-ascii @ | jq -R 'fromjson?' | jq -s 'map( {(.[0]): .[1]} ) | add'


# # print it
# cat <<JSON
# {
#     "MIP21_LIQUIDATION_ORACLE": "${MIP21_LIQUIDATION_ORACLE}",
#     "RWA_TOKEN_FAB": "${RWA_TOKEN_FAB}",
#     "SYMBOL": "${SYMBOL}",
#     "NAME": "${NAME}",
#     "ILK": "${ILK}",
#     "${SYMBOL}": "${RWA_TOKEN}",
#     "MCD_JOIN_${SYMBOL}_${LETTER}": "${RWA_JOIN}",
#     "${SYMBOL}_${LETTER}_URN": "${RWA_URN}",
#     "${SYMBOL}_${LETTER}_JAR": "${RWA_JAR}",
#     "${SYMBOL}_${LETTER}_OUTPUT_CONDUIT": "${RWA_OUTPUT_CONDUIT}"
#     "${SYMBOL}_${LETTER}_INPUT_CONDUIT_JAR": "${RWA_INPUT_CONDUIT_JAR}"
#     "${SYMBOL}_${LETTER}_INPUT_CONDUIT_URN": "${RWA_INPUT_CONDUIT_URN}"
# }
# JSON