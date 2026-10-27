#!/usr/bin/env bash
# Opens the coin's Uniswap v4 pool and locks its liquidity: the launch transaction.
# Run it once, after tools/deploy-mainnet.sh WITH_COIN=1, when you are ready for people to buy.
#
#   OWNER=0xYourWallet ETH_RPC_URL=https://... bash tools/launch-coin.sh
#
# What it does, with the numbers the fork tests launch with (test/LaunchCoinFork.t.sol):
#   - 80% of the supply goes into the pool, single-sided: no ETH needed besides the locker's fee.
#   - Opening price: one ETH buys about 505M coin, a market cap near 2 ETH for the whole supply.
#   - Pool fee 1% of every trade for the liquidity, plus the fee hook's 1% of the ETH side to HOOK_RECIPIENT.
#   - The liquidity is locked for LOCK_DAYS (365) in UNCX's locker; the lock belongs to OWNER.
#   - The 2% wallet limit stays on. Later: removeLimits(), then renounceOwnership() on the coin.
#
# Settings: OWNER (lock owner, required), ETH_RPC_URL (required), LOCK_DAYS (365), KEYS (~/keys/hammer-eth), YES=1,
#   BUY_ETH  the first buy, sent right behind the launch from the deployer, the coin straight to OWNER
#            (0 = none; at most 0.04: at the opening price 0.04 ETH buys 1.93% of the supply, just under
#            the 2% wallet limit)
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"
KEYS=${KEYS:-$HOME/keys/hammer-eth}
: "${OWNER:?set OWNER to your own wallet: the liquidity lock is made over to it}"
: "${ETH_RPC_URL:?set ETH_RPC_URL}"
LOCK_DAYS=${LOCK_DAYS:-365}
BUY_ETH=${BUY_ETH:-0}
node -e "const v=Number(process.argv[1]); if(!(v>=0 && v<=0.04)) { console.error('BUY_ETH is 0 to 0.04 (more than 0.04 ETH would go over the 2% wallet limit and fail)'); process.exit(1) }" "$BUY_ETH"
[ -s deployments/1-coin.json ] || { echo "deployments/1-coin.json is missing: run tools/deploy-mainnet.sh with WITH_COIN=1 first" >&2; exit 1; }
DEPLOYER_KEY=$(cat "$KEYS/deployer.key")
COIN=$(node -p 'require("./deployments/1-coin.json").coin')
HOOK=$(node -p 'require("./deployments/1-coin.json").hook ?? "0x0000000000000000000000000000000000000000"')
LOCKER=$(cast call "$COIN" 'LOCKER()(address)' --rpc-url "$ETH_RPC_URL")
FLAT=$(cast call "$LOCKER" 'flatFee()(uint256)' --rpc-url "$ETH_RPC_URL" | awk '{print $1}')
LPFEE=$(cast call "$LOCKER" 'lpFee()(uint256)' --rpc-url "$ETH_RPC_URL" | awk '{print $1}')
LAUNCHED=
[ "$(cast call "$COIN" 'lpTokenId()(uint256)' --rpc-url "$ETH_RPC_URL" | awk '{print $1}')" = "0" ] || LAUNCHED=1
mined_ok() { case "$(cast receipt "$1" status --rpc-url "$ETH_RPC_URL")" in true|1*) return 0 ;; *) return 1 ;; esac; }

# The tested launch curve (test/LaunchCoinFork.t.sol), scaled to the pool's share of the supply.
SQRT_START=1779478419032188924193855251423147
TICK_LOWER=-887200
TICK_UPPER=200400
SUPPLY=$(cast call "$COIN" 'totalSupply()(uint256)' --rpc-url "$ETH_RPC_URL" | awk '{print $1}')
POOL=$(cast call "$COIN" 'poolSupply()(uint256)' --rpc-url "$ETH_RPC_URL" | awk '{print $1}')
LIQUIDITY=$(node -e "console.log((44523249996678482940644n * BigInt('$POOL') / BigInt('$SUPPLY')).toString())")
DEADLINE=$(( $(cast block --rpc-url "$ETH_RPC_URL" -f timestamp) + 1800 ))
LOCK_FOR=$(( LOCK_DAYS * 86400 ))

if [ -n "$LAUNCHED" ]; then
  echo "  the pool is already open: going on with what comes after"
else
printf '  coin       %s (%s)\n  pool supply %s\n  hook       %s\n  locker fee %s ETH, takes %s/10000 of the liquidity\n  lock       %s days, owner %s\n' \
  "$COIN" "$(cast call "$COIN" 'symbol()(string)' --rpc-url "$ETH_RPC_URL")" "$(cast from-wei "$POOL")" "$HOOK" "$(cast from-wei "$FLAT")" "$LPFEE" "$LOCK_DAYS" "$OWNER"
[ "$BUY_ETH" = "0" ] || printf '  first buy  %s ETH, right behind the launch, coin to %s\n' "$BUY_ETH" "$OWNER"
[ "$LPFEE" -le 100 ] || { echo "The locker now takes more than 1% of the liquidity ($LPFEE/10000). Stopping." >&2; exit 1; }
if [ -z "${YES:-}" ]; then
  printf '\nType LAUNCH to open the pool on Ethereum mainnet: '
  read -r answer
  [ "$answer" = "LAUNCH" ] || { echo "Stopped. Nothing was sent."; exit 1; }
fi

LAUNCH_SIG='launch(uint24,int24,address,uint160,int24,int24,uint128,uint256,uint256,address,uint256)'
if [ "$BUY_ETH" = "0" ]; then
  cast send "$COIN" "$LAUNCH_SIG" 10000 200 "$HOOK" "$SQRT_START" "$TICK_LOWER" "$TICK_UPPER" "$LIQUIDITY" "$DEADLINE" "$LOCK_FOR" "$OWNER" 100 \
    --value "$FLAT" --rpc-url "$ETH_RPC_URL" --private-key "$DEPLOYER_KEY" > /dev/null
else
  # Launch and first buy go out together, with consecutive nonces: the buy can only land after the
  # launch, and its higher tip puts it ahead of anyone else's buy in that block.
  N=$(cast nonce "$(cast wallet address --private-key "$DEPLOYER_KEY")" --block pending --rpc-url "$ETH_RPC_URL")
  MAXFEE=$(( $(cast base-fee --rpc-url "$ETH_RPC_URL") * 3 + 3000000000 ))
  BUY=$(node tools/first-buy.mjs "$COIN" "$HOOK" "$(cast to-wei "$BUY_ETH")" "$OWNER" "$DEADLINE")
  H1=$(cast send "$COIN" "$LAUNCH_SIG" 10000 200 "$HOOK" "$SQRT_START" "$TICK_LOWER" "$TICK_UPPER" "$LIQUIDITY" "$DEADLINE" "$LOCK_FOR" "$OWNER" 100 \
    --value "$FLAT" --nonce "$N" --gas-limit 1500000 --async --rpc-url "$ETH_RPC_URL" --private-key "$DEPLOYER_KEY")
  H2=$(cast send 0x66a9893cC07D91D95644AEDD05D03f95e1dBA8Af "$BUY" --value "${BUY_ETH}ether" --nonce $((N + 1)) --gas-limit 500000 \
    --priority-gas-price 3gwei --gas-price "$MAXFEE" --async --rpc-url "$ETH_RPC_URL" --private-key "$DEPLOYER_KEY")
  mined_ok "$H1" || { echo "The launch failed: https://etherscan.io/tx/$H1" >&2; exit 1; }
  if mined_ok "$H2"; then
    echo "  first buy: $(cast from-wei "$(cast call "$COIN" 'balanceOf(address)(uint256)' "$OWNER" --rpc-url "$ETH_RPC_URL" | awk '{print $1}')") \$$(cast call "$COIN" 'symbol()(string)' --rpc-url "$ETH_RPC_URL" | tr -d '"') in $OWNER"
  else
    echo "  first buy did not go through (https://etherscan.io/tx/$H2); the launch did. Buy on Uniswap by hand if you want."
  fi
fi
echo "  launched: position $(cast call "$COIN" 'lpTokenId()(uint256)' --rpc-url "$ETH_RPC_URL"), locked until $(node -e "console.log(new Date($(cast call "$COIN" 'lockedUntil()(uint256)' --rpc-url "$ETH_RPC_URL" | awk '{print $1}')*1000).toISOString().slice(0,10))")"
echo "  Trade it on app.uniswap.org: paste $COIN"
fi
EXCHANGE=$(node -p 'require("./deployments/1.json").exchange')
DEPLOYER=$(cast wallet address --private-key "$DEPLOYER_KEY")
lc() { printf '%s' "$1" | tr 'A-F' 'a-f'; }
EX_OWNER=$(cast call "$EXCHANGE" 'owner()(address)' --rpc-url "$ETH_RPC_URL")
if [ "$(lc "$EX_OWNER")" = "$(lc "$DEPLOYER")" ]; then
  # The deployer still owns the exchange (tools/launch.sh go): it opens trading itself, then hands over.
  if [ "$(cast call "$EXCHANGE" 'opensPaused()(bool)' --rpc-url "$ETH_RPC_URL")" = "true" ]; then
    cast send "$EXCHANGE" 'unpauseOpens()' --rpc-url "$ETH_RPC_URL" --private-key "$DEPLOYER_KEY" > /dev/null
    echo "  trading open"
  fi
  cast send "$EXCHANGE" 'transferOwnership(address)' "$OWNER" --rpc-url "$ETH_RPC_URL" --private-key "$DEPLOYER_KEY" > /dev/null
  echo "  exchange handed to $OWNER: it becomes yours when you call acceptOwnership()"
  echo "  on etherscan.io/address/$EXCHANGE#writeContract (connect that wallet)"
elif [ "$(cast call "$EXCHANGE" 'opensPaused()(bool)' --rpc-url "$ETH_RPC_URL")" = "true" ]; then
  cat <<NEXT

  New positions are still paused: attaching the coin pauses them until the pool is open.
  Now that it is, open etherscan.io/address/$EXCHANGE#writeContract, connect the OWNER wallet
  and call unpauseOpens(). Trading starts the moment that lands.
NEXT
fi
