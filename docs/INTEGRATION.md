# Integrating Sentry

Sentry has three integration surfaces. All of them share the same contracts; only the delivery
of the notification differs.

## 1. Config file (self-hosted)

The smallest integration is a config file and one script.

```json
{
  "originChainId": 11155111,
  "token": "0x259d2fb64231d85e639d1074fa724bcdf29a4ed9",
  "guardedWallet": "0x...",
  "threshold": "5000000000000000000",
  "maxAlerts": 5,
  "maxPerAlert": "100000000000000000000",
  "maxTotal": "200000000000000000000",
  "destChainId": 11155111,
  "callbackProxy": "0xAa14d9Cd0f788Ca23d11805986C1d8bd035D23b4"
}
```

```bash
source .env && bash script/deploy.sh   # deploys reactive + callback, binds recipient
```

The host application only needs to set the config and keep both contracts funded.
It never holds a key that can move user funds; the callback contract can only record alerts.

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
