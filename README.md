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
| ① Origin event (D3RT `Transfer`, Sepolia) | https://eth-sepolia.blockscout.com/tx/0x1ba40219983167c32c3b8deb9017c57fcb1f38fa6bbd5b582f0429d495f1b407 |
| ② Reactive `react()` (Lasna) | https://lasna.reactscan.net/tx/0x74c7cb0e973156073c683486d13a57bf72346d2bff4e9199a37d33a1a3c1b342 |
| ③ Destination callback (`Alert`, Sepolia) | https://eth-sepolia.blockscout.com/tx/0x53dcc37d4f98662ba1672d34b958af6b126245038fa15953de3d517bece8e4cd |

**Deployed contracts**

| Contract | Chain | Address |
|---|---|---|
| GuardianReactive | Lasna (5318007) | `0x292b87c5df8d322de30e1402801f78f2e8563405` |
| GuardianCallback | Sepolia (11155111) | `0x8068fbf573fb522748f7786b485595b531666ec3` |
| Watched token (D3RT) | Sepolia | `0x259d2fb64231d85e639d1074fa724bcdf29a4ed9` |

**Readings after the run:** `GuardianReactive.alerts = 1`, `GuardianCallback.count = 1`.

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

## 5b. Failure modes / 出问题怎么办

| 出问题 | 会发生什么 | 怎么处理 |
|---|---|---|
| **Reactive 合约余额用完** | `reserves` 扣完 → `debt > 0` → 系统**静默停服**，`react()` 不再被调用（链上不会报错，只是"没反应"） | 立刻 `depositTo(合约地址)` 充值把 debt 清零；建议持续监控 `debt()` 与 `balance`，留余量 |
| **目标链回调失败** | 代理仍**照常收费**并发 `CallbackFailure` 事件；目标链 `count` 不增加 | 查原因：目标合约 revert / `gasLimit` 太小 / 回调合约欠费；处理后重新触发一次源事件 |
| **同一个事件被重复推送** | 有 `seen[txHash]` 去重，第二次直接 `return`，不会重复执行 | 无需处理 |
| **误触发（噪音事件）** | 订阅锁定 `from = 被守护地址`，`react()` 内再判断阈值；不满足直接 `return`（不 revert，回滚也收费） | 调整阈值或换过滤条件 |
| **单笔/累计金额过大** | 单笔按 `maxValuePerAlert` 封顶；累计到 `maxTotalValue` 后停止并退订 | 重新部署并调整上限 |
| **有人伪造回调** | 代理注入地址被 `onlyCallbackSender` 校验；非代理调用被 `onlyServiceProvider` 拒绝 | 无需处理 |

```text
恢复流程（余额耗尽）:
  ① cast call 0x8888…8888 "debt(address)(uint256)" <合约>     → 看欠了多少
  ② cast send 0x8888…8888 "depositTo(address)" <合约> --value 1ether   → 充值
  ③ cast call <合约> "alerts()(uint256)"                      → 确认恢复处理
```

## Tests

```bash
forge test -vv
```

| Test | 验证 |
|---|---|
| `test_CountsOnce` | 正常路径：超阈值事件执行一次 |
| `test_DuplicateIgnored` | 保护②：同一 txHash 重复推送只算一次 |
| `test_BelowThresholdIgnored` | 保护①：低于阈值不触发 |
| `test_OnlySystem` | 保护①：非系统合约调用 revert |
| `test_PerAlertCap` | 保护③：单笔金额封顶 |
| `test_TotalCapStops` | 保护③：累计到上限后停止 |
| `test_PauseStops` | 紧急暂停后不再处理 |

## 6. Next steps

```text
D10  Protection action: pre-approved allowance -> transfer remaining funds to a cold wallet
D11  Foundry tests: below threshold / wrong sender / after pause
D12  One-command reproducible deploy + README polish
```

## 7. Safety

Test networks only (Sepolia / Lasna). Never commit `.env`. The demo wallet is a throwaway test wallet.
