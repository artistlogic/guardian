# Security and load notes

This document records the trust assumptions, the attack surface and the load behaviour of Sentry.
It is written to be reviewed, not to advertise.

## 1. Assets and trust model

| Asset | Where | Who can touch it |
|---|---|---|
| guarded wallet funds | user's wallet | the user only — Sentry has no allowance, no key |
| callback contract balance | Sepolia | anyone can top up; only the proxy can make it spend |
| alert records | Sepolia events | append-only; nobody can rewrite them |
| deployer key | `.env` locally / never in git | the operator only; controls threshold, recipient, pause |
| notifier | operator's machine | read-only; holds no key |

Sentry never holds a key that can move user funds. The worst a compromised operator key can do is
change the threshold, pause processing, or point the callback at another recipient — it cannot
withdraw anything, because the contracts have no withdrawal path.

## 2. Threat table

| Threat | Vector | Mitigation | Residual risk |
|---|---|---|---|
| forged callback | direct call to `onAlert()` | `onlyServiceProvider` (proxy) + `onlyCallbackSender` (authorized reactive) | none known |
| replay / duplicate | same log delivered twice | subscription filter + `seen[txHash]` | none |
| event flood / fee griefing | attacker sends many transfers from the watched wallet | per-alert cap, total cap, alert-count cap, auto-unsubscribe | the operator still pays for the alerts they chose to allow |
| below-threshold spam | lots of small transfers | filtered inside `react()` before any callback | reactive gas still paid per inspected event |
| callback failure | wrong gasLimit, empty balance, target revert | `CallbackFailure` event, bounded per-alert cost, documented recovery | alert lost unless retried |
| silent stop | `debt > 0` | documented; `depositTo()` restores | requires monitoring the monitor |
| key compromise | leaked `.env` | git-ignored, single copy, test wallet only, `cast wallet import` for anything real | rotate key; contracts are immutable so redeploy is needed |
| forged notification | someone posts to the ntfy topic | topic is a shared secret channel; move to signed webhooks for production | low for a demo |

## 3. Load behaviour

The design shifts the expensive part off the operator:

- **Watching** happens on the Reactive network. There is no polling loop, no queue and no worker to
  scale — the network delivers matching logs and executes `react()` per event.
- **Cost** is per executed `react()`, plus the callback attempt. Caps bound the worst case:
  with `maxAlerts = 5`, a flood costs at most five callbacks and then the subscription stops.
- **Off-chain** we only read: a notifier polls `Alert` logs. Reads are cheap and cacheable.

For a personal deployment the load is a few events per day. If Sentry were run as a service:

| Concern | Approach |
|---|---|
| many watches | one reactive contract per (wallet, token, threshold); no shared hot path |
| log scanning | incremental blocks + reorg-safe confirmations; batch `eth_getLogs` per range |
| notifier scaling | stateless workers, dedupe by `txHash`, at-least-once delivery |
| burst traffic | bounded queue with backpressure, per-chat rate limit, digest instead of per-event pings |
| RPC limits | several endpoints, exponential backoff, circuit breaker on failures |
| observability | metrics: alerts seen, delivered, failed, backlog age; alert on backlog |

## 4. Bot / plugin shape

The chain is the brain; a bot would only be the mouth.

| Shape | Feasibility | Notes |
|---|---|---|
| notification adapters (ntfy, Telegram, Discord, Feishu, webhook) | high, ~1 day | stateless function from `Alert` → HTTP; secrets in env |
| bot with commands (`/watch`, `/status`, `/journey`) | medium, 2–3 days | needs a small indexer + sqlite/postgres, idempotent delivery, per-chat rate limits |
| multi-tenant SaaS | higher, weeks | auth, quotas, billing, per-tenant isolation, abuse handling |
| on-chain plugin (another protocol consuming alerts) | high | anyone can listen to `Alert`; no permission needed |

A bot does not break the "no server" claim: the watching logic stays on-chain, and the bot is only a
delivery surface. It does introduce a service to operate, which is a product decision, not a
technical limitation.
