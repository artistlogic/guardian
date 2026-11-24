#!/bin/bash
# Reproducible deploy for Guardian.
# Usage:
#   cp .env.example .env   # fill PRIVATE_KEY + RPC + addresses
#   source .env && bash script/deploy.sh
set -euo pipefail
cd "$(dirname "$0")/.."

: "${PRIVATE_KEY:?set PRIVATE_KEY}"
: "${SEPOLIA_RPC_URL:?set SEPOLIA_RPC_URL}"
: "${LASNA_RPC_URL:?set LASNA_RPC_URL}"
TOKEN="${TOKEN:?set TOKEN (watched ERC-20 on Sepolia)}"
WATCH="${WATCH:?set WATCH (guarded wallet)}"
CALLBACK_PROXY="${CALLBACK_PROXY:?set CALLBACK_PROXY (destination proxy)}"
THRESHOLD="${THRESHOLD:-5000000000000000000}"        # 5 tokens (18 decimals)
MAX_ALERTS="${MAX_ALERTS:-5}"
MAX_PER="${MAX_PER:-100000000000000000000}"          # 100 tokens
MAX_TOTAL="${MAX_TOTAL:-200000000000000000000}"      # 200 tokens
GAS_LIMIT="${GAS_LIMIT:-1000000}"
REACTIVE_FUND="${REACTIVE_FUND:-0.5ether}"
CALLBACK_FUND="${CALLBACK_FUND:-0.02ether}"

forge build --silent

code_of() {
  local f
  f=$(find out -name "$1.json" | head -1)
  grep -o '"bytecode":{"object":"0x[0-9a-fA-F]*"' "$f" | sed 's/.*"object":"//;s/"$//'
}

deploy() { # artifact, args(no 0x), rpc, value
  local code
  code=$(code_of "$1")
  cast send --rpc-url "$3" --private-key "$PRIVATE_KEY" --json --value "$4" \
    --create "0x${code#0x}$2" | grep -o '"contractAddress":"0x[0-9a-fA-F]*"' | sed 's/.*:"//;s/"$//'
}

echo "== 1/3 deploy GuardianReactive on Lasna"
ARGS_R=$(cast abi-encode "constructor(uint256,address,address,uint256,uint256,uint256,uint256,uint256,uint64)" \
  11155111 "$TOKEN" "$WATCH" "$THRESHOLD" "$MAX_ALERTS" "$MAX_PER" "$MAX_TOTAL" 11155111 "$GAS_LIMIT" | sed 's/^0x//')
REACTIVE=$(deploy GuardianReactive "$ARGS_R" "$LASNA_RPC_URL" "$REACTIVE_FUND")
echo "REACTIVE=$REACTIVE"

echo "== 2/3 deploy GuardianCallback on destination"
ARGS_C=$(cast abi-encode "constructor(address,address)" "$CALLBACK_PROXY" "$REACTIVE" | sed 's/^0x//')
CALLBACK=$(deploy GuardianCallback "$ARGS_C" "$SEPOLIA_RPC_URL" "$CALLBACK_FUND")
echo "CALLBACK=$CALLBACK"

echo "== 3/3 bind recipient"
cast send "$REACTIVE" "setRecipient(address)" "$CALLBACK" \
  --rpc-url "$LASNA_RPC_URL" --private-key "$PRIVATE_KEY" >/dev/null
echo "BOUND"

cat <<EOF

Done:
  GuardianReactive (Lasna)   = $REACTIVE
  GuardianCallback (Sepolia) = $CALLBACK

Trigger a transfer from the guarded wallet, then verify:
  cast call $REACTIVE "alerts()(uint256)" --rpc-url $LASNA_RPC_URL
  cast call $CALLBACK "count()(uint256)"  --rpc-url $SEPOLIA_RPC_URL
EOF
