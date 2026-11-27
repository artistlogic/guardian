# Sentry · On-chain Wallet Alerting

![Solidity](https://img.shields.io/badge/solidity-0.8.29-363636?logo=solidity&logoColor=white)
![Tests](https://img.shields.io/badge/tests-13%20passing-3ddc97)
![Reactive Omni](https://img.shields.io/badge/Reactive%20Omni-Lasna-54c8ff)
![Dashboard](https://img.shields.io/badge/dashboard-live-8b7bff)
![License](https://img.shields.io/badge/license-MIT-blue)

Watches ERC-20 outflows from a guarded wallet. Above a threshold, a reactive contract records an
alert on the destination chain and a notifier pushes it. No server, no hosted private key.

**Live dashboard:** https://artistlogic.github.io/guardian/ ·
**Integration guide:** [docs/INTEGRATION.md](docs/INTEGRATION.md)

<img src="docs/architecture.svg" alt="Transfer on Sepolia, reactive contract on Lasna, callback on Sepolia" width="100%">

## Proof

| Step | Transaction |
|---|---|
| origin transfer (10 D3RT) | https://eth-sepolia.blockscout.com/tx/0x4fe9d51fb6c57e86852e61fac842e98901788b7949bafb918019cd1f3cb326ee |
| `react()` on Lasna | https://lasna.reactscan.net/tx/0x01960122654318f025145e87230d469243b9eb387cc3076f6c55a742720500c5 |
| callback `Alert` | https://eth-sepolia.blockscout.com/tx/0xe439ee83286ecc1222173317aadd28e6c104f4a5e9606106e8112e8ae3715371 |
| below-threshold control (1 D3RT, no alert) | https://eth-sepolia.blockscout.com/tx/0x99713085eab4f09c6e65980e0e8c97fb13125fa0e0ab52d3feb94f13f27931f4 |

| Contract | Chain | Address |
|---|---|---|
| GuardianReactive | Lasna 5318007 | `0xd9cda08baac9de9cbe658e553a8fd7112c7f7034` |
| GuardianCallback | Sepolia 11155111 | `0xa070a801f8cd3f844e41e672d9e42380485cabe0` |
| D3RT test token | Sepolia | `0x259d2fb64231d85e639d1074fa724bcdf29a4ed9` |

After the runs: `alerts = 1`, `totalValue = 10e18`, `count = 1`.

## How it works

- Subscription is narrowed at the network level: `chainId + token + topic0 + topic1(guarded wallet)`.
- `react()` checks source contract, log type, pause, quota, duplicate `txHash`, then threshold and caps.
  Failing conditions return silently (a revert would still be billed).
- A qualifying transfer requests a callback; the payload carries the callback selector, and the proxy
  injects the reactive address as the first argument.
- The callback is guarded twice: `onlyServiceProvider` (proxy only) and `onlyCallbackSender` (authorized
  reactive only).
- Limits: per-alert cap, total cap, alert count cap (both caps unsubscribe), owner `pause()`,
  owner `setThreshold()`.

## Quickstart

```bash
forge build && forge test -vv          # 13 passing

cp .env.example .env                   # fill PRIVATE_KEY, WATCH, TOKEN
bash script/deploy.sh                  # deploys both contracts, prints addresses

source .env                            # makes the variables below available
cast send "$TOKEN" "transfer(address,uint256)" 0x000000000000000000000000000000000000dEaD \
  10000000000000000000 --rpc-url "$SEPOLIA_RPC_URL" --private-key "$PRIVATE_KEY"
```

The script reads `.env` itself. `--private-key` on a command line is acceptable for a funded test
wallet only; for anything else use `cast wallet import` plus `--account`.

## Verify

```bash
cast call <REACTIVE> "alerts()(uint256)"     --rpc-url https://lasna-rpc.rnk.dev/
cast call <REACTIVE> "totalValue()(uint256)" --rpc-url https://lasna-rpc.rnk.dev/
cast call <CALLBACK> "count()(uint256)"      --rpc-url https://ethereum-sepolia-rpc.publicnode.com
```

## Tests

`forge test -vv` → 13 passing: counts once, ignores below-threshold, rejects non-system callers,
dedupes by tx hash, enforces per-alert and total caps, stops after pause, allows owner threshold
change (and rejects non-owner), callback happy path, rejects non-proxy, rejects wrong sender,
accumulates alerts.

## Failure modes

| Failure | Effect | Recovery |
|---|---|---|
| reactive out of funds | `debt > 0`, execution stops silently | `depositTo()` clears debt |
| callback fails | attempt is charged, `CallbackFailure` emitted, `count` unchanged | check gasLimit/target/funding, trigger again |
| duplicate events | rejected by `seen[txHash]` | none |
| forged callback | rejected by both guards | none |

## Scope and roadmap

This version records alerts; it does not move funds.

1. Response action behind a user-approved allowance and a higher action threshold.
2. Allowlist rules: the notifier decodes the `Transfer` recipient and marks unknown recipients as
   higher severity (off-chain, no contract change).
3. Human-in-the-loop above a hard cap.

These need a second contract holding an allowance — a different trust decision from alerting, which is
why alerting ships first.

## Related work

Tenderly Alerts, OpenZeppelin Defender Sentinels, Forta, Hypernative and Hexagate all assume a listener
running in infrastructure the user controls. Sentry executes the subscription and the callback on-chain,
so there is no listener to host and every alert is verifiable on an explorer. Scope is deliberately
smaller: one wallet, one token, one threshold.

## AI assistance

| Part | AI involvement | Verification |
|---|---|---|
| contract skeleton and comments | drafted, reviewed line by line | `forge build`, `forge test` (13), on-chain runs |
| tests | drafted | `forge test -vv` passes |
| README and docs | drafted | every command run manually on testnets |
| §Proof evidence | produced by real transactions | read back with `cast` and explorers |

## Security notes

- `.env` is git-ignored and never committed; `.env.example` contains placeholders only.
- Testnets only (Sepolia, Lasna). No real funds.
- Prefer `cast wallet import` over plaintext keys for any non-test use.
