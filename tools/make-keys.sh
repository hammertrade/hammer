#!/usr/bin/env bash
# Makes the exchange's working keys, one file each, in a folder only you can read.
#
#   bash tools/make-keys.sh            keys go to ~/keys/hammer-eth
#   KEYS=/some/folder bash tools/make-keys.sh
#
# Makes:  deployer.key  operator.key  backup-operator.key  price-signer.key  guardian.key
# and addresses.txt with the public address of each (safe to share, the .key files are not).
#
# It never overwrites a key that exists: run it again and it only fills in what is missing.
# Back the folder up somewhere offline (an encrypted USB stick). Lose price-signer.key or
# operator.key and you can replace them from the owner wallet; lose the owner wallet and you can't.
# The OWNER is NOT made here: use your own wallet (MetaMask, hardware wallet or a Safe).
set -euo pipefail
command -v cast > /dev/null || { echo "cast is missing: install Foundry first (curl -L https://foundry.paradigm.xyz | bash; foundryup)" >&2; exit 1; }
KEYS=${KEYS:-$HOME/keys/hammer-eth}
umask 077
mkdir -p "$KEYS"
chmod 700 "$KEYS"

for role in deployer operator backup-operator price-signer guardian; do
  file="$KEYS/$role.key"
  if [ -s "$file" ]; then echo "  $role.key exists, kept"; continue; fi
  # cast prints the key; it goes straight into the file and is never shown.
  cast wallet new --json | node -e 'let s="";process.stdin.on("data",d=>s+=d).on("end",()=>{const j=JSON.parse(s);const w=Array.isArray(j)?j[0]:(j.data?j.data[0]:j);process.stdout.write(w.private_key||w.privateKey)})' > "$file"
  echo "  $role.key made"
done

{
  for role in deployer operator backup-operator price-signer guardian; do
    printf '%-16s %s\n' "$role" "$(cast wallet address --private-key "$(cat "$KEYS/$role.key")")"
  done
} > "$KEYS/addresses.txt"

echo
echo "Keys are in $KEYS (readable by you alone). Addresses:"
cat "$KEYS/addresses.txt"
echo
echo "Send ETH to the deployer only. tools/deploy-mainnet.sh tops up the operators from it."
