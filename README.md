# Sentry · On-chain Wallet Alerting

![Solidity](https://img.shields.io/badge/solidity-0.8.29-363636?logo=solidity&logoColor=white)
![Tests](https://img.shields.io/badge/tests-13%20passing-3ddc97)
![Reactive Omni](https://img.shields.io/badge/Reactive%20Omni-Lasna-54c8ff)
![License](https://img.shields.io/badge/license-MIT-blue)

Watches ERC-20 outflows from one guarded wallet. Above the threshold, a reactive contract records an
alert on the destination chain and a notifier pushes it. No server, no hosted key.

**Live:** https://artistlogic.github.io/guardian/ · **Guide:** [docs/INTEGRATION.md](docs/INTEGRATION.md)

<img src="docs/architecture.svg" alt="Transfer on Sepolia, reactive contract on Lasna, callback on Sepolia" width="100%">

## Proof

| Step | Transaction |
|---|---|
| origin 10 D3RT | `0x4fe9d51f…326ee` · [Sepolia](https://eth-sepolia.blockscout.com/tx/0x4fe9d51fb6c57e86852e61fac842e98901788b7949bafb918019cd1f3cb326ee) |
| `react()` | `0x01960122…500c5` · [Lasna](https://lasna.reactscan.net/tx/0x01960122654318f025145e87230d469243b9eb387cc3076f6c55a742720500c5) |
| callback `Alert` | `0xe439ee83…715371` · [Sepolia](https://eth-sepolia.blockscout.com/tx/0xe439ee83286ecc1222173317aadd28e6c104f4a5e9606106e8112e8ae3715371) |
| control 1 D3RT | `0x99713085…7931f4` · no alert |

Reactive `0xd9cda08b…7034` (Lasna) · Callback `0xa070a801…abe0` (Sepolia) · Token `0x259d2fb6…4ed9`

## How it works

1. The subscription narrows at the network layer: `chainId + token + topic0 + topic1(wallet)`.
2. `react()` checks source, log type, pause, quota, `txHash` duplicate, then threshold and caps.
3. A qualifying transfer requests a callback; the proxy injects the reactive address as first argument.
4. The callback is guarded twice: `onlyServiceProvider` and `onlyCallbackSender`.

## Run

```bash
forge build && forge test -vv          # 13 passing
cp .env.example .env                   # PRIVATE_KEY, WATCH, TOKEN
bash script/deploy.sh                  # deploys both contracts
source .env && cast send "$TOKEN" "transfer(address,uint256)" \
  0x000000000000000000000000000000000000dEaD 10000000000000000000 \
  --rpc-url "$SEPOLIA_RPC_URL" --private-key "$PRIVATE_KEY"
```

## Engineering

13 Foundry tests (threshold, dedupe, caps, pause, owner-only, callback guards), CI on every push.

| Failure | Effect | Recovery |
|---|---|---|
| reactive out of funds | `debt > 0`, silently stops | `depositTo()` |
| callback fails | charged, `CallbackFailure`, `count` unchanged | fix and retrigger |
| duplicate / forged | rejected | none |

## Scope

Records alerts; never moves funds. Next, opt-in only: allowlist-aware severity, daily digest,
response action behind a user-approved allowance.

Agents and SaaS tools (Tenderly, Defender Sentinels, Forta, Hypernative) assume a listener you host.
Sentry puts the rule, the subscription and the alert on-chain. Scope is deliberately small:
one wallet, one token, one threshold.

## Notes

Deployment keys live in `.env` (git-ignored); `.env.example` has placeholders only. Testnets only.
Contract and test drafts used AI assistance; every command and transaction here was run and verified.
Threat model and load behaviour: [docs/SECURITY.md](docs/SECURITY.md).
