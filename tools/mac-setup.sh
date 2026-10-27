#!/usr/bin/env bash
# One-time setup of a Mac for Hammer: Node 22, Foundry, the project's packages, a first build.
# Safe to run again: whatever is already installed is kept.
#
#   cd ~/hammer && bash tools/mac-setup.sh
#
# Takes 5-15 minutes the first time. At the end it prints what is installed.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"
say() { printf '\n== %s\n' "$*"; }

say "Apple's command line tools (git, ssh, make)"
if ! xcode-select -p > /dev/null 2>&1; then
  xcode-select --install || true
  echo "A window asked to install the command line tools. Click Install, wait for it to finish, then run this script again."
  exit 1
fi
echo "  installed"

say "Node.js 22"
export NVM_DIR="$HOME/.nvm"
touch "$HOME/.zshrc"   # nvm adds itself to this file, and a fresh Mac does not have one
if [ ! -s "$NVM_DIR/nvm.sh" ]; then
  curl -fsSL https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.3/install.sh | bash
fi
# shellcheck disable=SC1091
. "$NVM_DIR/nvm.sh"
nvm install 22 > /dev/null
nvm alias default 22 > /dev/null
echo "  node $(node -v), npm $(npm -v)"

say "Foundry (forge, cast)"
if ! command -v forge > /dev/null 2>&1 && [ ! -x "$HOME/.foundry/bin/forge" ]; then
  curl -fsSL https://foundry.paradigm.xyz | bash
fi
export PATH="$HOME/.foundry/bin:$PATH"
foundryup > /dev/null 2>&1 || foundryup
echo "  $(forge --version | head -1)"

say "the project's packages"
npm --prefix relayer ci --no-audit --no-fund > /dev/null
npm --prefix web ci --no-audit --no-fund > /dev/null
echo "  relayer and site packages installed"

say "first build of the contracts (downloads the Solidity compiler once)"
forge build > /tmp/hammer-forge-build.log 2>&1 || { tail -20 /tmp/hammer-forge-build.log; exit 1; }
echo "  contracts compiled"

say "done"
cat <<NEXT
Everything is installed. Close this Terminal window and open a new one, so it picks up node and forge,
then go on with:

  cd ~/hammer
  bash tools/launch.sh
NEXT
