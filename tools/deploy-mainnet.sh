#!/usr/bin/env bash
# Deploys the whole exchange to Ethereum in one go, from the keys tools/make-keys.sh made.
#
#   OWNER=0xYourWallet ETH_RPC_URL=https://eth-mainnet.g.alchemy.com/v2/KEY bash tools/deploy-mainnet.sh
#
# Settings (environment):
#   OWNER              your own wallet or Safe: it can change limits, markets and the price signer   required
#   ETH_RPC_URL        an Ethereum RPC (Alchemy, QuickNode)                                          required
#   DEV_RECIPIENT      receives the team's half of the fees                                          OWNER
#   ETHERSCAN_API_KEY  set it and every contract is verified on Etherscan                            none
#   OPERATOR_ETH       ETH sent from the deployer to the operator and to the backup operator, each   0.02
#   CAP_BTC, CAP_ETH, LISTINGS, MIN_MARGIN, MIN_NOTIONAL, ...  passed on to script/Deploy.s.sol (see its header)
#   WITH_COIN=1        also create the coin (LaunchCoin): Uniswap v4 pool + fee hook, loss mining,     off
#                      staking and jackpot. Its pool opens later, with tools/launch-coin.sh.
#   COIN_NAME, COIN_SYMBOL  the coin's name and ticker                                               Hammer, HAMMER
#   HOOK_RECIPIENT     gets the fee hook's 1% of every coin trade; must be a plain wallet (not a Safe     OWNER
#                      or smart account)
#   KEYS               the keys folder                                                               ~/keys/hammer-eth
#   YES=1              do not stop to ask before sending (for scripts; leave it off by hand)
#   KEEP_OWNER=1       with WITH_COIN: the deployer stays owner (tools/launch-coin.sh hands it over after
#                      opening the pool and trading; tools/launch.sh go does that)
#   SLOW=1             wait for each transaction before sending the next (slower; the default sends them
#                      all at once, in order, and forge still checks every one before it sends any)
#
# Steps: check the exact bytecode, ask, deploy the exchange, Deposits and the coin (forge simulates all of it
# before it sends anything, and stops if any of it would fail), fund the operators. Etherscan verification
# runs afterwards in the background (tools/verify-all.sh, log in verify.log), so it never holds the launch up.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"
KEYS=${KEYS:-$HOME/keys/hammer-eth}
: "${OWNER:?set OWNER to your own wallet address (MetaMask, hardware wallet or Safe)}"
: "${ETH_RPC_URL:?set ETH_RPC_URL to your Ethereum RPC URL}"
DEV_RECIPIENT=${DEV_RECIPIENT:-$OWNER}
OPERATOR_ETH=${OPERATOR_ETH:-0.02}
say() { printf '\n== %s\n' "$*"; }
key() { [ -s "$KEYS/$1.key" ] || { echo "$KEYS/$1.key is missing: run tools/make-keys.sh first" >&2; exit 1; }; cat "$KEYS/$1.key"; }
addr() { cast wallet address --private-key "$(key "$1")"; }

command -v forge > /dev/null || { echo "forge is missing: install Foundry first" >&2; exit 1; }
[[ "$OWNER" =~ ^0x[0-9a-fA-F]{40}$ ]] || { echo "OWNER is not an address" >&2; exit 1; }
CHAIN=$(cast chain-id --rpc-url "$ETH_RPC_URL")
[ "$CHAIN" = "1" ] || { echo "ETH_RPC_URL is chain $CHAIN, not Ethereum mainnet (1)" >&2; exit 1; }
if [ -s deployments/1.json ] && [ -z "${REDEPLOY:-}" ]; then
  echo "deployments/1.json exists: the exchange is already deployed. Move that file away (or REDEPLOY=1) to deploy a new one." >&2; exit 1
fi

DEPLOYER=$(addr deployer)
export PRICE_SIGNER=$(addr price-signer) OPERATOR=$(addr operator) BACKUP_OPERATOR=$(addr backup-operator) GUARDIAN=$(addr guardian)
export DEV_RECIPIENT
FINAL_OWNER=$OWNER
# The coin is attached by the Exchange's owner. With WITH_COIN the deployer stays owner until the coin
# is in place, then hands the role to OWNER in the same run.
if [ -n "${WITH_COIN:-}" ]; then unset OWNER; else export OWNER; fi
lc() { printf '%s' "$1" | tr 'A-F' 'a-f'; }
[ "$(lc "$FINAL_OWNER")" != "$(lc "$DEPLOYER")" ] || { echo "OWNER must be your own wallet, not the deployer key" >&2; exit 1; }

say "who is who"
printf '  %-16s %s\n' deployer "$DEPLOYER" owner "$FINAL_OWNER" "dev recipient" "$DEV_RECIPIENT" operator "$OPERATOR" "backup operator" "$BACKUP_OPERATOR" "price signer" "$PRICE_SIGNER" guardian "$GUARDIAN"
BAL=$(cast balance "$DEPLOYER" --rpc-url "$ETH_RPC_URL" --ether)
GAS=$(cast gas-price --rpc-url "$ETH_RPC_URL")
printf '  deployer balance %s ETH, gas price %s gwei\n' "$BAL" "$(cast from-wei "$GAS" gwei)"

say "the exact bytecode that will be deployed"
# Built once ahead (tools/launch.sh prep); rebuilt here only if a source changed since (a few minutes).
if node tools/deployable.mjs --check > /tmp/hammer-deployable.log 2>&1; then echo "  ready"; else
  echo "  building it (a few minutes; tools/launch.sh prep does this ahead of time)"
  node tools/deployable.mjs --forge > /tmp/hammer-deployable.log 2>&1 || { tail -20 /tmp/hammer-deployable.log; exit 1; }
fi
# About 20M gas for everything (measured on a mainnet fork), on top: the operators' ETH and the locker's fee.
printf '  cost: about %s ETH of gas at the current price, plus %s ETH to each operator\n' \
  "$(node -e "console.log((20e6*Number('$GAS')/1e18).toFixed(4))")" "$OPERATOR_ETH"

if [ -z "${YES:-}" ]; then
  printf '\nType DEPLOY to send these transactions to Ethereum mainnet: '
  read -r answer
  [ "$answer" = "DEPLOY" ] || { echo "Stopped. Nothing was sent."; exit 1; }
fi

# Verification runs afterwards (tools/verify-all.sh). VERIFY stays empty here; SLOW=1 brings --slow back.
VERIFY=()
[ -z "${SLOW:-}" ] || VERIFY=(--slow)

say "deploying the exchange"
forge script script/Deploy.s.sol --rpc-url "$ETH_RPC_URL" --private-key "$(key deployer)" --broadcast ${VERIFY[@]+"${VERIFY[@]}"} 2>&1 \
  | grep -vE 'warning|│|╭|╰|help:' | grep -E 'Exchange|Oracle|Sessions|Lens|Gateway|Batcher|Pricing|ONCHAIN|Error|error' | sed 's/^/  /'
[ -s deployments/1.json ] || { echo "No deployments/1.json: the deploy did not complete." >&2; exit 1; }
EXCHANGE=$(node -p 'require("./deployments/1.json").exchange')

say "deploying Deposits (a deposit address per wallet)"
EXCHANGE=$EXCHANGE forge script script/DeployDeposits.s.sol --rpc-url "$ETH_RPC_URL" --private-key "$(key deployer)" --broadcast ${VERIFY[@]+"${VERIFY[@]}"} 2>&1 \
  | grep -E 'Deposits|ONCHAIN|Error|error' | grep -vE 'warning|help:' | sed 's/^/  /'

if [ -n "${WITH_COIN:-}" ]; then
  say "creating the coin: ${COIN_NAME:-Hammer} (\$${COIN_SYMBOL:-HAMMER})"
  EXCHANGE=$EXCHANGE LAUNCH_COIN=true COIN_NAME="${COIN_NAME:-Hammer}" COIN_SYMBOL="${COIN_SYMBOL:-HAMMER}" HOOK_RECIPIENT="${HOOK_RECIPIENT:-$FINAL_OWNER}" \
    forge script script/AttachCoin.s.sol --rpc-url "$ETH_RPC_URL" --private-key "$(key deployer)" --broadcast ${VERIFY[@]+"${VERIFY[@]}"} 2>&1 \
    | grep -vE 'warning|│|╭|╰|help:' | grep -E 'Coin|coin|Staking|Mining|Jackpot|Hook|Sweeper|ONCHAIN|Error|error' | sed 's/^/  /'
  [ -s deployments/1-coin.json ] || { echo "No deployments/1-coin.json: the coin was not attached." >&2; exit 1; }
  if [ -z "${KEEP_OWNER:-}" ]; then
    say "handing the exchange to the owner"
    cast send "$EXCHANGE" 'transferOwnership(address)' "$FINAL_OWNER" --rpc-url "$ETH_RPC_URL" --private-key "$(key deployer)" > /dev/null
    printf '  pending owner: %s (accepts with acceptOwnership)\n' "$(cast call "$EXCHANGE" 'pendingOwner()(address)' --rpc-url "$ETH_RPC_URL")"
  fi
fi

say "gas money for the operators"
# Both sent at once (consecutive nonces), then both waited for.
N=$(cast nonce "$DEPLOYER" --block pending --rpc-url "$ETH_RPC_URL")
HASHES=()
for who in "$OPERATOR" "$BACKUP_OPERATOR"; do
  HASHES+=("$(cast send "$who" --value "${OPERATOR_ETH}ether" --nonce "$N" --async --rpc-url "$ETH_RPC_URL" --private-key "$(key deployer)")")
  N=$((N + 1))
done
for h in "${HASHES[@]}"; do cast receipt "$h" status --rpc-url "$ETH_RPC_URL" > /dev/null; done
for who in "$OPERATOR" "$BACKUP_OPERATOR"; do
  printf '  %s now holds %s ETH\n' "$who" "$(cast balance "$who" --rpc-url "$ETH_RPC_URL" --ether)"
done

if [ -n "${ETHERSCAN_API_KEY:-}" ]; then
  say "Etherscan verification: running in the background (log: verify.log)"
  ( WITH_COIN="${WITH_COIN:-}" COIN_NAME="${COIN_NAME:-Hammer}" COIN_SYMBOL="${COIN_SYMBOL:-HAMMER}" HOOK_RECIPIENT="${HOOK_RECIPIENT:-$FINAL_OWNER}" \
      OWNER="$FINAL_OWNER" ETH_RPC_URL="$ETH_RPC_URL" ETHERSCAN_API_KEY="$ETHERSCAN_API_KEY" KEYS="$KEYS" \
      nohup bash tools/verify-all.sh > verify.log 2>&1 < /dev/null & )
fi

say "done"
node -e 'const fs=require("fs");const d=require("./deployments/1.json");for(const k of ["exchange","deposits","oracle","sessions","lens","gateway","batcher","pricing"])console.log("  "+k.padEnd(10)+d[k]);if(fs.existsSync("./deployments/1-coin.json")){const c=require("./deployments/1-coin.json");for(const k of Object.keys(c))console.log("  "+k.padEnd(10)+c[k])}'
cat <<NEXT

Next:
  1. If OWNER is not the deployer: open the Exchange on etherscan.io/address/$EXCHANGE#writeContract,
     connect the OWNER wallet and call acceptOwnership().
  2. git add deployments/ && git commit -m "Mainnet deployment" && git push
  3. Put the relayer on its server:  RPC_URL=... bash tools/server-install.sh <server ip>
  4. Publish the live site:          npm run deploy:site
NEXT
[ -z "${WITH_COIN:-}" ] || cat <<COIN
  5. New positions stay paused until the coin's pool is open. When you are ready:
       OWNER=$FINAL_OWNER ETH_RPC_URL=... bash tools/launch-coin.sh
     then call unpauseOpens() on the Exchange from the OWNER wallet (Etherscan, Write contract).
COIN
