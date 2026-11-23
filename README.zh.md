# Guardian · 链上钱包守护

> **监听指定钱包的 ERC-20 转出事件。单笔金额超过阈值时，由 Reactive 在目标链上自动执行告警——
> 不需要自建服务器，也不需要托管私钥。**
>
> [English README](README.md)

## 1. 它是什么

```text
 Sepolia（源链）                  Lasna（Reactive）                  Sepolia（目标链）
 ────────────────                ─────────────────                  ──────────────────
 ERC-20 Transfer                 GuardianReactive.react()            GuardianCallback.onAlert()
 from = 被守护钱包      ──▶      value ≥ 阈值 ?                      emit Alert(value, originTxHash)
 value ≥ 阈值                    requestCallbackV_1_0   ─────────▶
```

核心价值：**告警由网络在链上完成，而不是你托管的机器人。**

## 2. 演示证据

| 步骤 | 交易 |
|---|---|
| ① 源链事件（D3RT `Transfer`，Sepolia） | https://eth-sepolia.blockscout.com/tx/0x1ba40219983167c32c3b8deb9017c57fcb1f38fa6bbd5b582f0429d495f1b407 |
| ② Reactive `react()`（Lasna） | https://lasna.reactscan.net/tx/0x74c7cb0e973156073c683486d13a57bf72346d2bff4e9199a37d33a1a3c1b342 |
| ③ 目标链回调（`Alert`，Sepolia） | https://eth-sepolia.blockscout.com/tx/0x53dcc37d4f98662ba1672d34b958af6b126245038fa15953de3d517bece8e4cd |

**已部署合约**

| 合约 | 链 | 地址 |
|---|---|---|
| GuardianReactive | Lasna (5318007) | `0x292b87c5df8d322de30e1402801f78f2e8563405` |
| GuardianCallback | Sepolia (11155111) | `0x8068fbf573fb522748f7786b485595b531666ec3` |
| 被监控代币（D3RT） | Sepolia | `0x259d2fb64231d85e639d1074fa724bcdf29a4ed9` |

**运行后读数**：`alerts = 1`、`count = 1`。

## 3. 工作原理

- **订阅收窄**：`chainId + 代币地址 + topic0 + topic1(被守护钱包)`，只有"从该钱包转出"的转账会进入 `react()`。
- **阈值判断**：`react()` 内判断，低于阈值直接 `return`（不 revert，回滚也要收费）。
- **回调内容**：`(reactive, originChainId, originTxHash, value, alertIndex)`，第一个参数由代理注入。
- **两道门锁**：`onlyServiceProvider`（只认回调代理）+ `onlyCallbackSender`（只认我们的 reactive 合约）。
- **防失控**：
  - 订阅过滤 + 合约内校验，只在该触发时触发；
  - `seen[txHash]` 去重，同一笔源交易只处理一次；
  - 单笔金额封顶 + 累计封顶；`maxAlerts` 到顶自动退订；owner 可 `pause()`。

## 4. 怎么跑

```bash
forge build
forge test -vv
```

## 5. 边界（不解决什么）

- 只能**发现并记录**，已经转出的资产无法撤销；
- 本版本不自动转移资产（需要预授权额度，属于另一层设计）；
- 企业级控制（多签、白名单、审批流、合规筛查）不在范围内，见第 6 节组合方式。

## 5b. 出问题怎么办

| 出问题 | 会发生什么 | 怎么处理 |
|---|---|---|
| **Reactive 合约余额用完** | `debt > 0` → 系统**静默停服**（不报错，只是不动了） | `depositTo(合约)` 充值清零 debt，并持续监控 |
| **目标链回调失败** | 代理照常收费并发 `CallbackFailure`，`count` 不增加 | 查目标合约 / `gasLimit` / 回调合约余额，处理后重新触发 |
| **重复事件** | `seen[txHash]` 拦下 | 无需处理 |
| **误触发** | 订阅过滤 + 阈值拦截 | 调整阈值 |
| **金额过大** | 单笔封顶、累计到顶停止并退订 | 重新部署调整上限 |
| **伪造回调** | 两道门锁拒绝 | 无需处理 |

```bash
# 欠费恢复三步
cast call 0x8888888888888888888888888888888888888888 "debt(address)(uint256)" <合约>
cast send 0x8888888888888888888888888888888888888888 "depositTo(address)" <合约> --value 1ether
cast call <合约> "alerts()(uint256)"
```

## 6. 测试

```bash
forge test -vv   # 7 passed
```

| 测试 | 验证 |
|---|---|
| `test_CountsOnce` | 正常路径，执行一次 |
| `test_DuplicateIgnored` | 同一 txHash 只处理一次 |
| `test_BelowThresholdIgnored` | 低于阈值忽略 |
| `test_OnlySystem` | 非系统调用 revert |
| `test_PerAlertCap` | 单笔封顶 |
| `test_TotalCapStops` | 累计到顶停止 |
| `test_PauseStops` | 暂停后不再处理 |

## 7. 安全说明

仅使用测试网（Sepolia / Lasna）。永远不要提交 `.env`。演示钱包是一次性测试钱包。
