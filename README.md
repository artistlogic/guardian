# Guardian · On-chain Wallet Guardian

> **Watch a wallet's outgoing token transfers. When one exceeds the threshold,
> Reactive executes an on-chain alert on the destination chain — no server, no key hosting.**
>
> **中文摘要**：监听 Sepolia 上指定钱包的 ERC-20 转出事件，单笔金额超过阈值时，
> Reactive 自动跨链回调到目标链并记录一条 Alert；无需自建服务器，无需托管私钥。

## 1. What it is

```text
 Sepolia (origin)                 Lasna (Reactive)                 Sepolia (destination)
 ─────────────────                ─────────────────                ──────────────────────
 ERC-20 Transfer                  GuardianReactive.react()          GuardianCallback.onAlert()
 from = watched wallet    ──▶     value >= threshold ?              emit Alert(value, originTxHash)
 value >= threshold               requestCallbackV_1_0  ─────────▶
```

The whole point: **alerting is done on-chain, by the network, not by a bot you must host.**

## 2. The demo (evidence)

| Step | Transaction |
|---|---|
| ① Origin event (Transfer) | `<PENDING>` |
| ② Reactive `react()` (Lasna) | `<PENDING>` |
| ③ Destination callback (`Alert`) | `<PENDING>` |

## 3. How it works

- **Subscription** is narrowed at the network level: `chainId + token + topic0 + topic1(watched wallet)`.
  Only transfers **out of** the watched wallet ever reach `react()`.
- **Threshold** is checked inside `react()`; below-threshold transfers `return` silently (reverts are charged too).
- **Callback** carries `(reactive, originChainId, originTxHash, value, alertIndex)`; the first field is injected by the proxy.
- **Two locks** on the callback: `onlyServiceProvider` (only the callback proxy) and `onlyCallbackSender` (only our reactive contract).
- **Runaway protection**: `maxAlerts` auto-unsubscribes; owner can `pause()`; contract keeps a balance so it never goes into debt.

## 4. Try it

```bash
# 1) build
forge build

# 2) deploy + fund + trigger + collect evidence (see script/deploy.sh in the repo)
bash script/deploy.sh
```

## 5. What we don't solve

- We can only **detect and record**; an already-sent transfer cannot be reverted.
- We do not move funds automatically in this version (that needs a pre-approved allowance and is a separate design).
- Enterprise-grade controls (multisig, whitelists, approval workflows, compliance screening) are **out of scope**; see §6 for how they would compose.

## 6. Next steps

```text
D10  Protection action: pre-approved allowance -> transfer remaining funds to a cold wallet
D11  Foundry tests: below threshold / wrong sender / after pause
D12  One-command reproducible deploy + README polish
```

## 7. Safety

Test networks only (Sepolia / Lasna). Never commit `.env`. The demo wallet is a throwaway test wallet.
