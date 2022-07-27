# hvb-onboarding

Repository for onboarding [HVB](https://forum.makerdao.com/t/mip6-huntingdon-valley-bank-loan-syndication-collateral-onboarding-application/14219) to MCD. Forked and adapted from [MIP21-RWA-Example](https://github.com/makerdao/MIP21-RWA-Example) template repo.

## Dev

### Clone the repo

(Optional) You can run `nix-env -f https://github.com/dapphub/dapptools/archive/master.tar.gz -iA solc-static-versions.solc_0_6_12` for a lasting installation of the solidity version used.

### Install lib dependencies

```bash
make update
```

### Create a local `.env` file and change the placeholder values

```bash
cp .env.exaples .env
```

### Deploy contracts

```bash
make deploy-ces-goerli # to deploy contracts for the CES Fork of Goerli MCD
make deploy-goerli # to deploy contracts for the official Goerli MCD
make deploy-mainnet # to deploy contracts for the official Mainnet MCD
```

This script outputs a JSON file like this one:

```json
{
  "RWA009_TOKEN": "<address>",
  "MIP21_LIQUIDATION_ORACLE": "<address>",
  "ILK": "RWA009-A",
  "RWA009": "<address>",
  "MCD_JOIN_RWA009_A": "<address>",
  "RWA009_A_URN": "<address>",
  "RWA009_A_OUTPUT_CONDUIT": "<address>",
  "RWA009_A_OPERATOR": "<address>",
  "RWA009_A_MATE": "<address>"
}
```

You can save it using `stdout` redirection:

```bash
make deploy-ces-goerli > out/ces-goerli-addresses.json
```

### Verify source code

If you saved the deployed addresses like suggested above, in order to verify the contracts you need to extract the contents of the JSON file into environment variables. There is a convenience script named `json-to-env` for that in [CES Shell Utils](https://github.com/clio-finance/shell-utils).

If you properly initialized this repo, it should be already installed at `lib/shell-utils` and can be referenced as:

```bash
 # sets the proper env vars
source <(lib/shell-utils/bin/json-to-env -x out/ces-goerli-addresses.json)
make verify-ces-goerli
```

### Replace spell addresses

Spell actions cannot have state, so any parameter they take must be hard-coded into their source code.

Every time a new deployment is made, you need to update the addresses used in the spell, which can be tedious.

We created a quality of life script powered by dark `sed` sorcery to help with this task in `scripts/replace-spell-addresses.sh`:

```bash
scripts/replace-spell-addresses.sh <deployments_json_file> <spell_file> <spell_addresses_helper_file>
```

Example:

```
scripts/replace-spell-addresses.sh out/ces-goerli-addresses.json src/spells/CESFork_GoerliRwaSpell.sol src/spells/helpers/CESFork_GoerliAddresses.sol
```

### More...

You can also refer to the Makefile (`make <command>`) for full list of commands.

## License

AGPL-3.0 LICENSE
