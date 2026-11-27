# Integrating Sentry

Sentry has three integration surfaces. All of them share the same contracts; only the delivery
of the notification differs.

## 1. Config file (self-hosted)

Sentry is configured through one `.env` file, read by the deploy script:

```ini
PRIVATE_KEY=0x...                                  # funded test wallet
SEPOLIA_RPC_URL=https://ethereum-sepolia-rpc.publicnode.com
LASNA_RPC_URL=https://lasna-rpc.rnk.dev/
TOKEN=0x259d2fb64231d85e639d1074fa724bcdf29a4ed9   # ERC-20 on Sepolia
WATCH=0x...                                        # guarded wallet
CALLBACK_PROXY=0xAa14d9Cd0f788Ca23d11805986C1d8bd035D23b4

# optional (defaults in script)
THRESHOLD=5000000000000000000
MAX_ALERTS=5
MAX_PER=100000000000000000000
MAX_TOTAL=200000000000000000000
```

```bash
cp .env.example .env      # fill in the values above
bash script/deploy.sh     # deploys reactive + callback, prints both addresses
```

The host application only sets the config and keeps both contracts funded. It never holds a key that
can move user funds; the callback contract can only record alerts.

A future SDK would read the same fields from `config.json`; the current release reads `.env` only.

## 2. Webhook output

The notifier is a standalone script. In production it can be replaced by any listener that receives
the `Alert` event and posts JSON to an existing system.

```json
{
  "type": "sentry.alert",
  "chainId": 11155111,
  "originTx": "0x632f…494c",
  "callbackTx": "0x3d67…e926",
  "value": "10000000000000000000",
  "token": "0x259d…4ed9",
  "alertIndex": 4
}
```

Targets already used in the demo: ntfy topic. Any HTTP endpoint works the same way
(Telegram bot, Feishu/Lark webhook, internal alerting system).

## 3. SDK (roadmap)

A thin client wrapper would expose three calls:

```js
const sentry = new Sentry({ rpc, reactiveAddress, callbackAddress });

await sentry.configure({ token, guardedWallet, threshold });  // writes config, deploys if needed
sentry.onAlert((alert) => { /* originTx, callbackTx, value, timestamp */ });
await sentry.fund({ reactive: "0.5", callback: "0.02" });
```

The contracts are the stable interface; the SDK only wraps deployment and event reading.

## What the host does not need

| Requirement | Needed? |
|---|---|
| A server running 24/7 | no — the reactive network does the watching |
| A hosted private key | no — the contracts are pre-funded and permissionless to trigger |
| A database | no — alerts are on-chain events |
| Custom indexing | optional — any log reader works |

## Boundaries

Sentry is an alerting layer. It does not block transfers, does not move funds, and does not hold
user keys. Response actions and allowlists are separate, opt-in modules (see README §8).
