#!/usr/bin/env bash
# The launch, step by step, with your settings remembered between steps.
#
#   bash tools/launch.sh            where you are and the next command to run
#   bash tools/launch.sh config     answer a few questions (domain, X, wallet, keys); saved in launch.env
#   bash tools/launch.sh keys       make the exchange's service keys (~/keys/hammer-eth)
#   bash tools/launch.sh prep       everything that can be done ahead: bytecode, server packages, api, practice site
#   bash tools/launch.sh go         THE LAUNCH, in one go (about 5 minutes): contracts, server, live site, coin
#                                   pool, trading open. Asks once. Then you call acceptOwnership() on Etherscan.
#   bash tools/launch.sh deploy     deploy the contracts to Ethereum (simulates first, asks before sending)
#   bash tools/launch.sh server     put the relayer on your server
#   bash tools/launch.sh api        give it the address api.<your domain>
#   bash tools/launch.sh site       publish the site (practice mode until the exchange is live, then live)
#   bash tools/launch.sh coin       open the coin's pool (asks before sending)
#   bash tools/launch.sh ca         the $HAMMER contract address: known as soon as the keys exist, before any deploy
#   bash tools/launch.sh limits-off remove the coin's 2% wallet limit, for good (asks first)
#   bash tools/launch.sh lock       the liquidity lock: id, unlock date, what to do with it
#   bash tools/launch.sh status     check everything: keys, balances, contracts, server, site
#
# launch.env stays on this computer (it is in .gitignore). It holds your RPC and Etherscan keys, never a
# wallet key: those live in ~/keys/hammer-eth.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"
export PATH="$HOME/.foundry/bin:$PATH"
CONF="$ROOT/launch.env"
KEYS=${KEYS:-$HOME/keys/hammer-eth}
export KEYS
say() { printf '\n== %s\n' "$*"; }
ok() { printf '  \033[32m✓\033[0m %s\n' "$*"; }
todo() { printf '  \033[33m•\033[0m %s\n' "$*"; }
bad() { printf '  \033[31m✗\033[0m %s\n' "$*"; }

[ -f "$CONF" ] && . "$CONF"
DOMAIN=${DOMAIN:-}; X_HANDLE=${X_HANDLE:-}; OWNER=${OWNER:-}; ETH_RPC_URL=${ETH_RPC_URL:-}
ETHERSCAN_API_KEY=${ETHERSCAN_API_KEY:-}; SERVER_IP=${SERVER_IP:-}; PAGES_PROJECT=${PAGES_PROJECT:-}; WITH_COIN=${WITH_COIN:-1}; BUY_ETH=${BUY_ETH:-0.04}

save() {
  umask 077
  cat > "$CONF" <<EOF
# Hammer launch settings (tools/launch.sh). Not committed. No wallet keys in here.
DOMAIN=$DOMAIN
X_HANDLE=$X_HANDLE
OWNER=$OWNER
ETH_RPC_URL=$ETH_RPC_URL
ETHERSCAN_API_KEY=$ETHERSCAN_API_KEY
SERVER_IP=$SERVER_IP
PAGES_PROJECT=$PAGES_PROJECT
WITH_COIN=$WITH_COIN
BUY_ETH=$BUY_ETH
EOF
}
ask() { # ask VAR "question" [default]
  local cur=${!1:-${3:-}} answer
  printf '%s%s: ' "$2" "${cur:+ [$cur]}"
  read -r answer
  printf -v "$1" '%s' "${answer:-$cur}"
}
need() { for v in "$@"; do [ -n "${!v:-}" ] || { echo "Missing $v: run  bash tools/launch.sh config  first." >&2; exit 1; }; done; }
# wrangler whoami answers 0 even when nobody is logged in, so look at what it says.
cf_login() { npx --yes wrangler@4 whoami 2>&1 | grep -qiE "not authenticated|not logged in" && npx --yes wrangler@4 login || true; }
dashed() { printf '%s' "$1" | tr '.' '-'; }
api_up() { [ -n "$DOMAIN" ] && curl -fsS -m 8 "https://api.$DOMAIN/health" 2> /dev/null | grep -q '"ok":true'; }

cmd_config() {
  say "settings (Enter keeps the value in brackets)"
  ask DOMAIN "Your domain, e.g. hammertrade.xyz"
  ask X_HANDLE "Your X handle without @, e.g. HammerTradeXYZ"
  ask OWNER "Your own wallet address (MetaMask): owns the exchange, receives the fees"
  ask ETH_RPC_URL "Alchemy Ethereum Mainnet URL (https://eth-mainnet.g.alchemy.com/v2/...)"
  ask ETHERSCAN_API_KEY "Etherscan API key"
  ask SERVER_IP "Server IP (leave empty if you have no server yet)"
  ask WITH_COIN "Launch the \$HAMMER coin too? 1 = yes, 0 = no" 1
  ask BUY_ETH "Your first buy of \$HAMMER at launch, in ETH (0 to 0.04; 0.04 = 1.93% of the supply)" 0.04
  [[ "$OWNER" =~ ^0x[0-9a-fA-F]{40}$ ]] || { bad "OWNER is not an address"; exit 1; }
  save
  ok "saved to launch.env"
  local cur_domain cur_x
  cur_domain=$(node -p 'require("./brand.json").domain'); cur_x=$(node -p 'require("./brand.json").x')
  if [ "$DOMAIN" != "$cur_domain" ] || [ "$X_HANDLE" != "$cur_x" ]; then
    say "putting $DOMAIN and @$X_HANDLE into the site, contracts' scripts and server config"
    node tools/rebrand.mjs --domain "$DOMAIN" --x "$X_HANDLE" | tail -1
  fi
  echo; echo "Next:  bash tools/launch.sh keys"
}

cmd_keys() { bash tools/make-keys.sh; cmd_ca; echo; echo "Send 0.22 ETH to the deployer address above, then:  bash tools/launch.sh prep"; }

# The coin is the deployer's 25th transaction (nonce 24: 22 for the exchange, 1 for Deposits, 1 for the
# fee hook), a plain CREATE, so its address follows from the deployer's address alone. It holds while the
# deployer sends nothing else before the launch and the markets are the default ones.
COIN_NONCE=24
predict_coin() { cast compute-address "$(cast wallet address --private-key "$(cat "$KEYS/deployer.key")")" --nonce "$COIN_NONCE" | awk '{print $NF}'; }
cmd_ca() {
  if [ -s deployments/1-coin.json ]; then
    say "\$HAMMER contract (deployed)"; printf '\n    \033[1;33m%s\033[0m\n' "$(node -p 'require("./deployments/1-coin.json").coin')"; return
  fi
  [ -s "$KEYS/deployer.key" ] || { bad "no keys yet: bash tools/launch.sh keys"; exit 1; }
  say "\$HAMMER contract address (it will be this one)"
  printf '\n    \033[1;33m%s\033[0m\n\n' "$(predict_coin)"
  echo "  It stays this address as long as the deployer key sends nothing before  bash tools/launch.sh go."
  if [ -n "$ETH_RPC_URL" ]; then
    local n; n=$(cast nonce "$(cast wallet address --private-key "$(cat "$KEYS/deployer.key")")" --rpc-url "$ETH_RPC_URL" 2> /dev/null || echo "?")
    [ "$n" = "0" ] && ok "deployer has sent nothing yet: the address holds" || [ "$n" = "?" ] || bad "the deployer has already sent $n transaction(s): this prediction no longer holds"
  fi
}

cmd_deploy() {
  need OWNER ETH_RPC_URL
  local coin=(); [ "$WITH_COIN" = "1" ] && coin=(WITH_COIN=1)
  env OWNER="$OWNER" ETH_RPC_URL="$ETH_RPC_URL" ETHERSCAN_API_KEY="$ETHERSCAN_API_KEY" ${coin[@]+"${coin[@]}"} bash tools/deploy-mainnet.sh
  echo; echo "Then accept ownership on Etherscan (the step 1 printed above), and:  bash tools/launch.sh server"
}

cmd_server() {
  need DOMAIN ETH_RPC_URL OWNER
  [ -n "$SERVER_IP" ] || { ask SERVER_IP "Server IP"; save; }
  [ -s deployments/1.json ] || { bad "deploy the contracts first (bash tools/launch.sh deploy)"; exit 1; }
  RPC_URL="$ETH_RPC_URL" CORS_ORIGIN="https://$DOMAIN,https://www.$DOMAIN${PAGES_PROJECT:+,https://$PAGES_PROJECT.pages.dev}" SUPPORT_ADMINS="$OWNER" \
    bash tools/server-install.sh "$SERVER_IP"
  echo; echo "Next:  bash tools/launch.sh api"
}

cmd_api() {
  need DOMAIN SERVER_IP ETH_RPC_URL OWNER
  printf 'https://%s-api.%s.sslip.io' "$(node -p 'require("./brand.json").name.toLowerCase()')" "$(dashed "$SERVER_IP")" > "$KEYS/upstream.txt"
  cf_login
  bash tools/deploy-edge.sh
  say "giving the server the key the Worker uses"
  cmd_server > /dev/null
  sleep 5
  if api_up; then ok "https://api.$DOMAIN/health answers"; else todo "api.$DOMAIN does not answer yet; DNS can take a few minutes. Check: bash tools/launch.sh status"; fi
  echo; echo "Next:  bash tools/launch.sh site"
}

cmd_site() {
  need DOMAIN
  cf_login
  if [ -s deployments/1.json ] && api_up; then
    say "publishing the LIVE site: real USDC, your contracts"
    VITE_SITE_URL="https://$DOMAIN" VITE_API_URL="https://api.$DOMAIN" VITE_PREVIEW=0 PAGES_PROJECT="$PAGES_PROJECT" bash tools/deploy-site.sh
  else
    say "publishing the PRACTICE site (play money): the exchange is not live yet"
    VITE_SITE_URL="https://$DOMAIN" VITE_API_URL= VITE_PREVIEW=1 PAGES_PROJECT="$PAGES_PROJECT" bash tools/deploy-site.sh
  fi
  local code=""
  for _ in $(seq 1 30); do code=$(curl -s -o /dev/null -w '%{http_code}' -m 8 "https://$DOMAIN" || true); [ "$code" = 200 ] && break; sleep 4; done
  if [ "$code" = 200 ]; then ok "https://$DOMAIN is up (hard refresh: Cmd+Shift+R)"; else bad "https://$DOMAIN does not answer yet (got ${code:-nothing}); give it a few minutes, then: bash tools/launch.sh status"; fi
}

cmd_coin() {
  need OWNER ETH_RPC_URL
  OWNER="$OWNER" ETH_RPC_URL="$ETH_RPC_URL" bash tools/launch-coin.sh
}

cmd_prep() {
  need DOMAIN ETH_RPC_URL OWNER
  [ -s "$KEYS/deployer.key" ] || cmd_keys
  [ -n "$SERVER_IP" ] || { ask SERVER_IP "Server IP"; save; }
  say "1/4 the exact bytecode that will be deployed (a few minutes, once)"
  if node tools/deployable.mjs --check > /tmp/hammer-deployable.log 2>&1; then ok "already built"; else
    node tools/deployable.mjs --forge > /tmp/hammer-deployable.log 2>&1 || { tail -20 /tmp/hammer-deployable.log; exit 1; }
    ok "built"
  fi
  say "2/4 the server: Node 22 and Caddy"
  ssh -o BatchMode=yes -o ConnectTimeout=20 -o StrictHostKeyChecking=accept-new "root@$SERVER_IP" 'bash -s' <<'REMOTE' || { bad "could not log in as root@$SERVER_IP with your SSH key"; exit 1; }
set -e
export DEBIAN_FRONTEND=noninteractive
if ! node -v 2> /dev/null | grep -qE '^v(2[2-9]|[3-9][0-9])\.'; then
  curl -fsSL https://deb.nodesource.com/setup_22.x | bash - > /dev/null
  apt-get install -y -qq nodejs > /dev/null
fi
command -v caddy > /dev/null || { apt-get update -qq && apt-get install -y -qq caddy > /dev/null; }
timedatectl set-ntp true 2> /dev/null || true
echo "  node $(node -v), $(caddy version | cut -d' ' -f1)"
REMOTE
  say "3/4 api.$DOMAIN (Cloudflare Worker in front of the server)"
  cf_login
  printf 'https://%s-api.%s.sslip.io' "$(node -p 'require("./brand.json").name.toLowerCase()')" "$(dashed "$SERVER_IP")" > "$KEYS/upstream.txt"
  bash tools/deploy-edge.sh > /tmp/hammer-edge.log 2>&1 || { tail -20 /tmp/hammer-edge.log; exit 1; }
  ok "Worker published"
  say "4/4 the practice site on $DOMAIN"
  cmd_site
  say "ready"
  local dep; dep=$(cast wallet address --private-key "$(cat "$KEYS/deployer.key")")
  echo "  deployer $dep holds $(cast balance "$dep" --ether --rpc-url "$ETH_RPC_URL") ETH (needs about 0.22)"
  echo; echo "Launch:  bash tools/launch.sh go"
}

cmd_go() {
  need DOMAIN ETH_RPC_URL OWNER SERVER_IP
  [ -s "$KEYS/edge.key" ] && [ -s "$KEYS/upstream.txt" ] || { bad "run  bash tools/launch.sh prep  first"; exit 1; }
  local dep bal gas t0=$SECONDS
  dep=$(cast wallet address --private-key "$(cat "$KEYS/deployer.key")")
  bal=$(cast balance "$dep" --ether --rpc-url "$ETH_RPC_URL"); gas=$(cast gas-price --rpc-url "$ETH_RPC_URL")
  say "the launch"
  echo "  deployer $dep: $bal ETH, gas $(cast from-wei "$gas" gwei) gwei"
  echo "  contracts + coin: about $(node -e "console.log((22e6*Number('$gas')/1e18 + 0.14 + Number('$BUY_ETH')).toFixed(3))") ETH in all (gas, 0.04 to the operators, 0.1 to the liquidity locker, $BUY_ETH your first buy)"
  [ "$WITH_COIN" = "1" ] && [ "$BUY_ETH" != "0" ] && echo "  first buy: $BUY_ETH ETH of \$HAMMER, right behind the launch, to $OWNER"
  echo "  then: server, live site on https://$DOMAIN, the \$HAMMER pool (liquidity locked 365 days), trading open"
  local predicted=""
  if [ "$WITH_COIN" = "1" ]; then
    [ "$(cast nonce "$dep" --rpc-url "$ETH_RPC_URL")" = "0" ] && predicted=$(predict_coin)
    [ -n "$predicted" ] && printf '  $HAMMER contract will be: \033[1;33m%s\033[0m\n' "$predicted"
  fi
  printf '\nType GO to launch on Ethereum mainnet: '
  local answer; read -r answer
  [ "$answer" = "GO" ] || { echo "Stopped. Nothing was sent."; exit 1; }

  say "1/4 contracts"
  local coin=(); [ "$WITH_COIN" = "1" ] && coin=(WITH_COIN=1 KEEP_OWNER=1)
  env YES=1 OWNER="$OWNER" ETH_RPC_URL="$ETH_RPC_URL" ETHERSCAN_API_KEY="$ETHERSCAN_API_KEY" ${coin[@]+"${coin[@]}"} bash tools/deploy-mainnet.sh 2>&1 \
    | tee /tmp/hammer-deploy.log | sed '/^Next:/,$d'
  ok "contracts on chain ($((SECONDS - t0)) s)"
  if [ "$WITH_COIN" = "1" ]; then
    local ca; ca=$(node -p 'require("./deployments/1-coin.json").coin')
    printf '\n  $HAMMER CONTRACT: \033[1;33m%s\033[0m   (pool opens in ~2 min, at step 4)\n' "$ca"
    [ -z "$predicted" ] || [ "$(printf '%s' "$ca" | tr 'A-F' 'a-f')" = "$(printf '%s' "$predicted" | tr 'A-F' 'a-f')" ] || bad "differs from the predicted $predicted: use the one above"
  fi

  say "2/4 server"
  cmd_server > /tmp/hammer-server.log 2>&1 || { tail -30 /tmp/hammer-server.log; bad "server install failed (log above). The contracts are deployed. Once fixed, go on one by one: bash tools/launch.sh server, then site, then coin"; exit 1; }
  for _ in $(seq 1 30); do api_up && break; sleep 3; done
  api_up && ok "https://api.$DOMAIN answers ($((SECONDS - t0)) s)" || { bad "api.$DOMAIN does not answer: see /tmp/hammer-server.log, then run  bash tools/launch.sh site  and  coin"; exit 1; }

  say "3/4 live site"
  cmd_site > /tmp/hammer-site.log 2>&1 || { tail -20 /tmp/hammer-site.log; exit 1; }
  ok "https://$DOMAIN is live ($((SECONDS - t0)) s)"

  if [ "$WITH_COIN" = "1" ]; then
    say "4/4 the \$HAMMER pool, trading open"
    YES=1 BUY_ETH="$BUY_ETH" OWNER="$OWNER" ETH_RPC_URL="$ETH_RPC_URL" bash tools/launch-coin.sh
  fi
  say "launched in $(( (SECONDS - t0) / 60 )) min $(( (SECONDS - t0) % 60 )) s"
  [ "$WITH_COIN" = "1" ] && printf '\n  $HAMMER: \033[1;33m%s\033[0m\n  https://app.uniswap.org/swap?outputCurrency=%s&chain=mainnet\n  https://etherscan.io/token/%s\n\n' \
    "$(node -p 'require("./deployments/1-coin.json").coin')" "$(node -p 'require("./deployments/1-coin.json").coin')" "$(node -p 'require("./deployments/1-coin.json").coin')"
  local ex; ex=$(node -p 'require("./deployments/1.json").exchange')
  cat <<DONE
  Two things left, a minute each:
  1. etherscan.io/address/$ex#writeContract: connect $OWNER, call acceptOwnership()
  2. save the addresses:  git add deployments && git commit -m "Mainnet deployment"
  Etherscan verification is running in the background: tail -f verify.log
DONE
}

LOCKER=0x147AECa171a79466Fe9E2c03f21b45155Ff403F8
coin_addr() { [ -s deployments/1-coin.json ] || { bad "the coin is not deployed yet"; exit 1; }; node -p 'require("./deployments/1-coin.json").coin'; }

cmd_limits_off() {
  need ETH_RPC_URL
  local coin; coin=$(coin_addr)
  [ "$(cast call "$coin" 'limitsInEffect()(bool)' --rpc-url "$ETH_RPC_URL")" = "true" ] || { ok "the limit is already off"; return; }
  say "remove the 2% wallet limit on \$HAMMER ($coin)"
  echo "  Anyone can then hold any amount. This cannot be undone."
  printf '  Type OFF to send it (from the deployer key, the coin'"'"'s owner): '
  local answer; read -r answer; [ "$answer" = "OFF" ] || { echo "Stopped. Nothing was sent."; exit 1; }
  cast send "$coin" 'removeLimits()' --rpc-url "$ETH_RPC_URL" --private-key "$(cat "$KEYS/deployer.key")" > /dev/null
  ok "limit removed"
}

cmd_lock() {
  need ETH_RPC_URL
  local coin id until; coin=$(coin_addr)
  id=$(cast call "$coin" 'lockId()(uint256)' --rpc-url "$ETH_RPC_URL" | awk '{print $1}')
  until=$(cast call "$coin" 'lockedUntil()(uint256)' --rpc-url "$ETH_RPC_URL" | awk '{print $1}')
  [ "$until" != "0" ] || { todo "the pool is not open yet"; return; }
  say "liquidity lock"
  echo "  locker   UNCX $LOCKER"
  echo "  lock id  $id"
  echo "  owner    $OWNER (your wallet)"
  echo "  unlocks  $(node -e "console.log(new Date($until*1000).toISOString().slice(0,10))")"
  cat <<HOW

  All of these are done from your wallet ($OWNER), on etherscan.io/address/$LOCKER#writeContract
  (Connect to Web3 first):
    collect     take the pool's 1% trading fee earned so far (UNCX keeps 2% of it):
                lockId $id, recipient your wallet. Any time, also while locked.
    relock      extend the lock: lockId $id, newUnlockTime a later date as a unix time (epochconverter.com)
    unlockLiquidity  after the unlock date only: lockId $id. The pool's position comes back to your wallet;
                then remove the liquidity on app.uniswap.org (Pool > your position).
HOW
}

cmd_status() {
  say "settings"
  [ -f "$CONF" ] && ok "launch.env: $DOMAIN, @$X_HANDLE, owner ${OWNER:0:10}…" || todo "no settings yet: bash tools/launch.sh config"
  say "keys"
  if [ -s "$KEYS/deployer.key" ]; then
    local dep; dep=$(cast wallet address --private-key "$(cat "$KEYS/deployer.key")")
    ok "keys in $KEYS"
    [ -n "$ETH_RPC_URL" ] && echo "    deployer $dep: $(cast balance "$dep" --ether --rpc-url "$ETH_RPC_URL" 2> /dev/null || echo '?') ETH"
    [ -s deployments/1-coin.json ] || echo "    \$HAMMER will be $(predict_coin)"
  else todo "no keys yet: bash tools/launch.sh keys"; fi
  say "contracts"
  if [ -s deployments/1.json ]; then
    local ex; ex=$(node -p 'require("./deployments/1.json").exchange')
    ok "exchange $ex"
    [ -s deployments/1-coin.json ] && ok "\$HAMMER $(node -p 'require("./deployments/1-coin.json").coin')"
    if [ -n "$ETH_RPC_URL" ]; then
      local own paused; own=$(cast call "$ex" 'owner()(address)' --rpc-url "$ETH_RPC_URL" 2> /dev/null || echo "?")
      paused=$(cast call "$ex" 'opensPaused()(bool)' --rpc-url "$ETH_RPC_URL" 2> /dev/null || echo "?")
      if [ "$(printf '%s' "$own" | tr 'A-F' 'a-f')" = "$(printf '%s' "$OWNER" | tr 'A-F' 'a-f')" ]; then ok "owner is your wallet"; else todo "owner is $own: call acceptOwnership on etherscan.io/address/$ex#writeContract"; fi
      [ "$paused" = "false" ] && ok "trading open" || todo "new positions paused (normal until the coin's pool is open; then unpauseOpens on Etherscan)"
      for k in operator backup-operator; do
        [ -s "$KEYS/$k.key" ] && echo "    $k: $(cast balance "$(cast wallet address --private-key "$(cat "$KEYS/$k.key")")" --ether --rpc-url "$ETH_RPC_URL") ETH"
      done
    fi
  else todo "not deployed yet: bash tools/launch.sh deploy"; fi
  say "server and site"
  if api_up; then ok "https://api.$DOMAIN answers"; else todo "api.$DOMAIN not answering yet (bash tools/launch.sh server, then api)"; fi
  [ -n "$DOMAIN" ] && { curl -fsS -m 8 -o /dev/null "https://$DOMAIN" 2> /dev/null && ok "https://$DOMAIN is up" || todo "https://$DOMAIN not reachable yet"; }
}

cmd_next() {
  cmd_status
  say "next"
  if [ ! -f "$CONF" ]; then echo "  bash tools/launch.sh config"
  elif [ ! -s "$KEYS/deployer.key" ]; then echo "  bash tools/launch.sh keys"
  elif [ ! -s "$KEYS/edge.key" ]; then echo "  bash tools/launch.sh prep"
  elif [ ! -s deployments/1.json ]; then echo "  send 0.22 ETH to the deployer, then:  bash tools/launch.sh go"
  elif ! api_up; then echo "  bash tools/launch.sh server  then  bash tools/launch.sh api"
  else echo "  bash tools/launch.sh site  (live)  then, with the coin:  bash tools/launch.sh coin"; fi
}

case "${1:-next}" in
  config) cmd_config ;; keys) cmd_keys ;; prep) cmd_prep ;; go) cmd_go ;; deploy) cmd_deploy ;; server) cmd_server ;; api) cmd_api ;;
  site) cmd_site ;; coin) cmd_coin ;; ca) cmd_ca ;; limits-off) cmd_limits_off ;; lock) cmd_lock ;; status) cmd_status ;; next) cmd_next ;;
  *) sed -n '2,19p' "$0"; exit 1 ;;
esac
