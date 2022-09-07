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

FORGE_SCRIPT="${BASH_SOURCE%/*}/../../../scripts/forge-script.sh"

# estimate
[ "$ESTIMATE" = "true" ] && {
    RESPONSE=$($FORGE_SCRIPT "${BASH_SOURCE%/*}/RWA007Deployment.s.sol:RWA007Deployment" | tee >(cat 1>&2))
    jq -R 'fromjson? | .logs | .[]' <<<"$RESPONSE" | xargs -I@ cast --to-ascii @ | jq -R 'fromjson?' | jq -s 'map( {(.[0]): .[1]} ) | add'
    exit 0
}

RESPONSE=$($FORGE_SCRIPT "${BASH_SOURCE%/*}/RWA007Deployment.s.sol:RWA007Deployment" --broadcast --slow --verify --retries 10 | tee >(cat 1>&2)) 
jq -R 'fromjson? | .logs | .[]' <<<"$RESPONSE" | xargs -I@ cast --to-ascii @ | jq -R 'fromjson?' | jq -s 'map( {(.[0]): .[1]} ) | add'

# IF we hit block limit we need to parse output from previouse command and set deployed addresses to the ENV (hopefully FOundry will fix vm.setEnv wich we can use for that)
# Then we can simply run another method of Deployment contract and pick up this ENV vars there using `--sig "secondPartOfDeployment()"` flag of `forge script` command
