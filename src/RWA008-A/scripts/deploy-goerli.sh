#!/bin/bash

set -eo pipefail

source "${BASH_SOURCE%/*}/../../../scripts/_common.sh"
# shellcheck disable=SC1091
source "${BASH_SOURCE%/*}/../../../scripts/build-env-addresses.sh" goerli >/dev/null 2>&1

[[ "$ETH_RPC_URL" && "$(seth chain)" == "goerli" ]] || die "Please set a goerli ETH_RPC_URL"
[[ -z "$MIP21_LIQUIDATION_ORACLE" ]] && die 'Please set the MIP21_LIQUIDATION_ORACLE env var'

export ETH_GAS=6000000

# TODO: confirm if name/symbol is going to follow the RWA convention
# TODO: confirm with DAO at the time of mainnet deployment if OFH will indeed be 007
[[ -z "$NAME" ]] && NAME="RWA-008"
[[ -z "$SYMBOL" ]] && SYMBOL="RWA008"
#
# WARNING (2021-09-08): The system cannot currently accomodate any LETTER beyond
# "A".  To add more letters, we will need to update the PIP naming convention
# to include the letter.  Unfortunately, while fixing this on-chain and in our
# code would be easy, RWA001 integrations may already be using the old PIP
# naming convention.  So, before we can have new letters we must:
# 1. Change the existing PIP naming convention
# 2. Change all the places that depend on that convention (this script included)
# 3. Make sure all integrations are ready to accomodate that new PIP name.
# ! TODO: check with team/PE if this is still the case
#
[[ -z "$LETTER" ]] && LETTER="A"

# [[ -z "$MIP21_LIQUIDATION_ORACLE" ]] && MIP21_LIQUIDATION_ORACLE="0xDEADBEEFDEADBEEFDEADBEEFDEADBEEFDEADBEEF"
# TODO: confirm liquidations handling - no liquidations for the time being

ILK="${SYMBOL}-${LETTER}"
debug "ILK: ${ILK}"
ILK_ENCODED=$(cast --to-bytes32 "$(cast --from-ascii "$ILK")")

# build it
make build

FORGE_DEPLOY="${BASH_SOURCE%/*}/../../../scripts/forge-deploy.sh"
FORGE_VERIFY="${BASH_SOURCE%/*}/../../../scripts/forge-verify.sh"
CAST_SEND="${BASH_SOURCE%/*}/../../../scripts/cast-send.sh"

# Contracts
Token='RwaToken'
Urn='RwaUrn2'
UrnCloseHelper='RwaUrnCloseHelper'
InputConduit='RwaInputConduit2'
OutputConduit='RwaOutputConduit2'
LiquidationOracle='RwaLiquidationOracle'

[[ -z "$OPERATOR" ]] && OPERATOR=$($FORGE_DEPLOY --verify ForwardProxy) # using generic forward proxy for goerli
debug "${SYMBOL}_${LETTER}_OPERATOR: ${OPERATOR}"

[[ -z "$MATE" ]] && MATE=$($FORGE_DEPLOY --verify ForwardProxy) # using generic forward proxy for goerli
debug "${SYMBOL}_${LETTER}_MATE: ${MATE}"

# tokenize it
[[ -z "$RWA_TOKEN" ]] && {
	debug 'WARNING: `$RWA_TOKEN` not set. Deploying it...'
	TX=$($CAST_SEND "${RWA_TOKEN_FAB}" 'createRwaToken(string,string,address)' "$NAME" "$SYMBOL" "$OPERATOR")
	debug "TX: $TX"

	RECEIPT="$(cast receipt --json $TX)"
	TX_STATUS="$(jq -r '.status' <<<"$RECEIPT")"
	[[ "$TX_STATUS" != "0x1" ]] && die "Failed to create ${SYMBOL} token in tx ${TX}."

	RWA_TOKEN=$(cast --to-checksum-address "$(jq -r ".logs[0].address" <<<"$RECEIPT")")
	debug "${SYMBOL}: ${RWA_TOKEN}"
}

debug "${SYMBOL}: ${RWA_TOKEN}"

# route it
[[ -z "$RWA_OUTPUT_CONDUIT" ]] && {
	RWA_OUTPUT_CONDUIT=$($FORGE_DEPLOY ${OutputConduit} --constructor-args "$MCD_DAI")
	debug "${SYMBOL}_${LETTER}_OUTPUT_CONDUIT: ${RWA_OUTPUT_CONDUIT}"

	# trust addresses for goerli
	$CAST_SEND "$RWA_OUTPUT_CONDUIT" 'rely(address)' "$MCD_PAUSE_PROXY" &&
		$CAST_SEND "$RWA_OUTPUT_CONDUIT" 'deny(address)' "$ETH_FROM"
}

# join it
[[ -z "$RWA_JOIN" ]] && {
	TX=$($CAST_SEND "${JOIN_FAB}" 'newAuthGemJoin(address,bytes32,address)' "$MCD_PAUSE_PROXY" "$ILK_ENCODED" "$RWA_TOKEN")
    debug "TX: $TX"

    RECEIPT="$(cast receipt --json $TX)"
    TX_STATUS="$(jq -r '.status' <<<"$RECEIPT")"
    [[ "$TX_STATUS" != "0x1" ]] && die "Failed to create ${SYMBOL} token in tx ${TX}."

	RWA_JOIN=$(cast --to-checksum-address "$(jq -r ".logs[0].address" <<<"$RECEIPT")")
	debug "MCD_JOIN_${SYMBOL}_${LETTER}: ${RWA_JOIN}"
}

# urn it
[[ -z "$RWA_URN" ]] && {
    RWA_URN=$($FORGE_DEPLOY ${Urn} --constructor-args "$MCD_VAT" "$MCD_JUG" "$RWA_JOIN" "$MCD_JOIN_DAI" "$RWA_OUTPUT_CONDUIT")
    debug "${SYMBOL}_${LETTER}_URN: ${RWA_URN}"

    $CAST_SEND "$RWA_URN" 'rely(address)' "$MCD_PAUSE_PROXY" &&
	    $CAST_SEND "$RWA_URN" 'deny(address)' "$ETH_FROM"
}

[[ -z "$RWA_URN_CLOSE_HELPER" ]] && {
	RWA_URN_CLOSE_HELPER=$($FORGE_DEPLOY ${UrnCloseHelper})
	debug "RWA_URN_CLOSE_HELPER: ${RWA_URN_CLOSE_HELPER}"
}

# connect it
[[ -z "$RWA_INPUT_CONDUIT" ]] && {
	RWA_INPUT_CONDUIT=$($FORGE_DEPLOY ${InputConduit} --constructor-args "$MCD_DAI" "$RWA_URN")
	debug "${SYMBOL}_${LETTER}_INPUT_CONDUIT: ${RWA_INPUT_CONDUIT}"

	$CAST_SEND "$RWA_INPUT_CONDUIT" 'rely(address)' "$MCD_PAUSE_PROXY" &&
		$CAST_SEND "$RWA_INPUT_CONDUIT" 'deny(address)' "$ETH_FROM"
}

# price it
[[ -z "$MIP21_LIQUIDATION_ORACLE" ]] && {
	MIP21_LIQUIDATION_ORACLE=$($FORGE_DEPLOY ${LiquidationOracle} --constructor-args "$MCD_VAT" "$MCD_VOW")
	debug "MIP21_LIQUIDATION_ORACLE: ${MIP21_LIQUIDATION_ORACLE}"

	$CAST_SEND "$MIP21_LIQUIDATION_ORACLE" 'rely(address)' "$MCD_PAUSE_PROXY" &&
		$CAST_SEND "$MIP21_LIQUIDATION_ORACLE" 'deny(address)' "$ETH_FROM"
}

# Verify the contracts
# Verification is a no-op if the contracts are already verified
$FORGE_VERIFY $RWA_TOKEN ${Ttoken} --constructor-args \
	$(cast abi-encode 'x(string,string)' "$NAME" "$SYMBOL") >&2

$FORGE_VERIFY $RWA_URN ${Urn} --constructor-args \
	$(cast abi-encode 'x(address,address,address,address,address)'\
		"$MCD_VAT" "$MCD_JUG" "$RWA_JOIN" "$MCD_JOIN_DAI" "$RWA_OUTPUT_CONDUIT") >&2

$FORGE_VERIFY $RWA_URN_CLOSE_HELPER ${UrnCloseHelper} >&2

$FORGE_VERIFY $RWA_OUTPUT_CONDUIT ${OutputConduit} --constructor-args \
	$(cast abi-encode 'x(address)' "$MCD_DAI") >&2

$FORGE_VERIFY $RWA_INPUT_CONDUIT ${InputConduit} --constructor-args \
	$(cast abi-encode 'x(address,address)' "$MCD_DAI" "$RWA_URN") >&2

$FORGE_VERIFY $MIP21_LIQUIDATION_ORACLE ${LiquidationOracle} --constructor-args \
	$(cast abi-encode 'x(address,address)' "$MCD_VAT" "$MCD_VOW") >&2

cat <<JSON
{
    "MIP21_LIQUIDATION_ORACLE": "${MIP21_LIQUIDATION_ORACLE}",
    "RWA_TOKEN_FAB": "${RWA_TOKEN_FAB}",
    "RWA008_A_URN_CLOSE_HELPER": "${RWA_URN_CLOSE_HELPER}",
    "SYMBOL": "${SYMBOL}",
    "NAME": "${NAME}",
    "ILK": "${ILK}",
    "${SYMBOL}": "${RWA_TOKEN}",
    "MCD_JOIN_${SYMBOL}_${LETTER}": "${RWA_JOIN}",
    "${SYMBOL}_${LETTER}_URN": "${RWA_URN}",
    "${SYMBOL}_${LETTER}_INPUT_CONDUIT": "${RWA_INPUT_CONDUIT}",
    "${SYMBOL}_${LETTER}_OUTPUT_CONDUIT": "${RWA_OUTPUT_CONDUIT}",
    "${SYMBOL}_${LETTER}_OPERATOR": "${OPERATOR}",
    "${SYMBOL}_${LETTER}_MATE": "${MATE}"
}
JSON