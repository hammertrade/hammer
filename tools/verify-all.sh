#!/usr/bin/env bash
# Verifies every deployed contract on Etherscan, from the records forge kept of the deploy (broadcast/).
# tools/deploy-mainnet.sh starts it in the background after a deploy; run it again by hand any time
# (contracts already verified are skipped). Sends no transactions.
#
#   ETH_RPC_URL=... ETHERSCAN_API_KEY=... OWNER=0x... bash tools/verify-all.sh
set -uo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"
export PATH="$HOME/.foundry/bin:$PATH"
KEYS=${KEYS:-$HOME/keys/hammer-eth}
: "${ETH_RPC_URL:?set ETH_RPC_URL}"
: "${ETHERSCAN_API_KEY:?set ETHERSCAN_API_KEY}"
: "${OWNER:?set OWNER}"
key() { cat "$KEYS/$1.key"; }
addr() { cast wallet address --private-key "$(key "$1")"; }
export PRICE_SIGNER=$(addr price-signer) OPERATOR=$(addr operator) BACKUP_OPERATOR=$(addr backup-operator) GUARDIAN=$(addr guardian)
export DEV_RECIPIENT=${DEV_RECIPIENT:-$OWNER}
[ -n "${WITH_COIN:-}" ] && unset OWNER || export OWNER
EXCHANGE=$(node -p 'require("./deployments/1.json").exchange')
export EXCHANGE
V=(--rpc-url "$ETH_RPC_URL" --private-key "$(key deployer)" --broadcast --resume --verify --etherscan-api-key "$ETHERSCAN_API_KEY" --retries 10 --delay 10)
status=0
echo "== $(date '+%H:%M:%S') exchange"
forge script script/Deploy.s.sol "${V[@]}" 2>&1 | grep -E 'verif|Verif|Submit|Pass|Fail|URL|Error|error' | grep -v 'help:' || status=1
echo "== $(date '+%H:%M:%S') deposits"
forge script script/DeployDeposits.s.sol "${V[@]}" 2>&1 | grep -E 'verif|Verif|Submit|Pass|Fail|URL|Error|error' | grep -v 'help:' || status=1
if [ -s deployments/1-coin.json ]; then
  echo "== $(date '+%H:%M:%S') coin"
  LAUNCH_COIN=true COIN_NAME="${COIN_NAME:-Hammer}" COIN_SYMBOL="${COIN_SYMBOL:-HAMMER}" HOOK_RECIPIENT="${HOOK_RECIPIENT:-$DEV_RECIPIENT}" \
    forge script script/AttachCoin.s.sol "${V[@]}" 2>&1 | grep -E 'verif|Verif|Submit|Pass|Fail|URL|Error|error' | grep -v 'help:' || status=1
fi
echo "== $(date '+%H:%M:%S') done. Check the contracts on etherscan.io (a green tick on the Contract tab)."
exit $status
