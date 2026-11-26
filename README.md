# Sentry · On-chain Wallet Alerting

> **Watch a wallet's outgoing token transfers. When one exceeds the threshold,
> Reactive executes an on-chain alert on the destination chain — no server, no key hosting.**
>
> **Positioning**: a lightweight cross-chain alerting middleware built on Reactive Omni —
> detects, records and notifies; it never blocks or moves funds.
>
> [中文说明 / Chinese docs](README.zh.md)

## 1. What it is

```text
 Sepolia (origin)                 Lasna (Reactive)                 Sepolia (destination)
 ─────────────────                ─────────────────                ──────────────────────
 ERC-20 Transfer                  GuardianReactive.react()          GuardianCallback.onAlert()
 from = watched wallet    ──▶     value >= threshold ?              emit Alert(value, originTxHash)
 value >= threshold               requestCallbackV_1_0  ─────────▶
```

The whole point: **alerting is done on-chain, by the network, not by a bot you must host.**

### The problem it solves

Self-custody wallets keep growing, but anomalous outflows usually happen when nobody is
looking (night time, travel, meetings). Existing options all have a catch:

| Option | Catch |
|---|---|
| Watch the explorer by hand | unsustainable |
| Self-hosted keeper bot on a server | server to maintain, private key to host |
| Paid monitoring services | opaque pricing, poor retention |
| Wallet built-in risk controls | vendor rules, not customizable |

Reactive moves the heavy part (listening, reliable execution) into the network: the user only
defines *what counts as abnormal* and *what to do about it*.

## 2. The demo (evidence)

| Step | Transaction |
|---|---|
| ① Origin event (D3RT `Transfer` 10, Sepolia) | https://eth-sepolia.blockscout.com/tx/0x4fe9d51fb6c57e86852e61fac842e98901788b7949bafb918019cd1f3cb326ee |
| ② Reactive `react()` (Lasna) | https://lasna.reactscan.net/tx/0x01960122654318f025145e87230d469243b9eb387cc3076f6c55a742720500c5 |
| ③ Destination callback (`Alert`, Sepolia) | https://eth-sepolia.blockscout.com/tx/0xe439ee83286ecc1222173317aadd28e6c104f4a5e9606106e8112e8ae3715371 |
| Negative check (1 D3RT, below threshold) | https://eth-sepolia.blockscout.com/tx/0x99713085eab4f09c6e65980e0e8c97fb13125fa0e0ab52d3feb94f13f27931f4 |

**Deployed contracts**

| Contract | Chain | Address |
|---|---|---|
| GuardianReactive | Lasna (5318007) | `0xd9cda08baac9de9cbe658e553a8fd7112c7f7034` |
| GuardianCallback | Sepolia (11155111) | `0xa070a801f8cd3f844e41e672d9e42380485cabe0` |
| Watched token (D3RT) | Sepolia | `0x259d2fb64231d85e639d1074fa724bcdf29a4ed9` |

**Readings after the runs:** `alerts = 1`, `totalValue = 10e18`, `count = 1`;
the below-threshold transfer left `alerts` unchanged at 0 before the positive run.

```text
time ──────────────────────────────────────────────────────────────▶

watched wallet            Sepolia        Lasna                    Sepolia
     │  transfer 10 D3RT     │              │                        │
     ├──────────────────────▶│ Transfer     │                        │
     │                       │  ──event──▶  │ react(): value ≥ 5 D3RT│
     │                       │              │  requestCallbackV_1_0  │
     │                       │              ├───────callback───────▶│ onAlert()
     │                       │              │                        │ emit Alert
     │                       │              │                        │ count = 1
```

## 3. How it works

- **Subscription** is narrowed at the network level: `chainId + token + topic0 + topic1(watched wallet)`.
  Only transfers **out of** the watched wallet ever reach `react()`.
- **Threshold** is checked inside `react()`; below-threshold transfers `return` silently (reverts are charged too).
- **Callback** carries `(reactive, originChainId, originTxHash, value, alertIndex)`; the first field is injected by the proxy.
- **Two locks** on the callback: `onlyServiceProvider` (only the callback proxy) and `onlyCallbackSender` (only the authorized reactive contract).
- **Runaway protection**:
  - only transfers from the watched wallet trigger (subscription filter + in-contract checks),
  - each source txHash is processed once (`seen` mapping),
  - per-alert value cap and total value cap; `maxAlerts` auto-unsubscribes; owner can `pause()`.

## 4. Try it

### Build & test

```bash
forge build
forge test -vv
```

### Deploy (testnet)

```bash
cp .env.example .env      # fill PRIVATE_KEY, token, watched wallet, proxy
source .env && bash script/deploy.sh
```

The script deploys `GuardianReactive` on Lasna (pre-funded), `GuardianCallback` on the
destination chain (pre-funded), and binds the recipient. It prints both addresses.

### Trigger a run

Send a test-token transfer **from the watched wallet** that exceeds the threshold:

```bash
cast send "$TOKEN" "transfer(address,uint256)" 0x000000000000000000000000000000000000dEaD 10000000000000000000 \
  --rpc-url "$SEPOLIA_RPC_URL" --private-key "$PRIVATE_KEY"
```

Within ~30–120 s, `react()` fires and the callback lands on the destination chain.

## 5. What we don't solve

- We can only **detect and record**; an already-sent transfer cannot be reverted.
- We do not move funds automatically in this version (that needs a pre-approved allowance and is a separate design).
- Enterprise-grade controls (multisig, whitelists, approval workflows, compliance screening) are **out of scope**; see §6 for how they would compose.

## 5b. Failure modes

| Failure | What happens | How to recover |
|---|---|---|
| **Reactive contract runs out of funds** | `reserves` drained → `debt > 0` → the system **silently stops** calling `react()` (no error, it just goes quiet) | Top up with `depositTo(contract)` to clear debt; monitor `debt()` and balance |
| **Destination callback fails** | Proxy still charges and emits `CallbackFailure`; `count` does not increase | Check target revert / `gasLimit` / callback funding, then trigger again |
| **Duplicate event pushed** | `seen[txHash]` rejects it; no double execution | Nothing to do |
| **Noise events** | Subscription filter + threshold; ignored events `return` (no revert) | Adjust threshold |
| **Value too large** | Per-alert cap, total cap, then stop and unsubscribe | Redeploy with new limits |
| **Forged callback** | `onlyServiceProvider` + `onlyCallbackSender` reject | Nothing to do |

```bash
# Recover a contract that stopped due to debt
cast call 0x8888888888888888888888888888888888888888 "debt(address)(uint256)" <contract>
cast send 0x8888888888888888888888888888888888888888 "depositTo(address)" <contract> --value 1ether
cast call <contract> "alerts()(uint256)"
```

## 6. Tests

```bash
forge test -vv
# 7 passed
```

| Test | Verifies |
|---|---|
| `test_CountsOnce` | happy path, one alert per transfer |
| `test_DuplicateIgnored` | same txHash processed once |
| `test_BelowThresholdIgnored` | below threshold ignored |
| `test_OnlySystem` | non-system caller reverts |
| `test_PerAlertCap` | per-alert cap |
| `test_TotalCapStops` | total cap stops processing |
| `test_PauseStops` | pause stops processing |

## 7. Verify on-chain

```bash
# Reactive side: did react() run?
cast call <GUARDIAN_REACTIVE> "alerts()(uint256)"   --rpc-url https://lasna-rpc.rnk.dev/
cast call <GUARDIAN_REACTIVE> "totalValue()(uint256)" --rpc-url https://lasna-rpc.rnk.dev/
cast call <GUARDIAN_REACTIVE> "seen(uint256)(bool)" <SOURCE_TX_AS_UINT256> --rpc-url https://lasna-rpc.rnk.dev/

# Destination side: did the callback land?
cast call <GUARDIAN_CALLBACK> "count()(uint256)" --rpc-url https://ethereum-sepolia-rpc.publicnode.com

# Both transactions
cast logs --rpc-url https://lasna-rpc.rnk.dev/ --address <GUARDIAN_REACTIVE> "Alerted(uint256,uint256,uint256)"
cast logs --rpc-url https://ethereum-sepolia-rpc.publicnode.com --address <GUARDIAN_CALLBACK> "Alert(address,uint256,uint256,uint256,uint256)"
```

The three reference transactions in §2 are the expected end state:
origin transfer → `react()` on Lasna → `Alert` on the destination chain.

## 8. AI usage disclosure

Parts drafted with AI assistance (Claude/DeepSeek) and how they were verified:

| Part | AI involvement | Verification |
|---|---|---|
| Contract skeleton and comments | drafted with AI, reviewed line by line | `forge build` + `forge test` (7 tests) + on-chain runs |
| Tests | drafted with AI | `forge test -vv` green locally; logic re-checked against contract behavior |
| README structure | drafted with AI | every command executed by hand on testnets |
| On-chain evidence (§2) | produced by real transactions | independent reads via `cast` + explorers |

All on-chain addresses and transaction hashes were produced by actually deploying and running
the contracts; nothing in §2 is simulated.

## 9. Safety

Test networks only (Sepolia / Lasna). Never commit `.env`.
