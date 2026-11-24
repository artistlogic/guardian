# D9 报告 · 跑通第一条完整链路

> 任务：用自己项目的合约，在测试网跑通「源链事件 → react() → 目标链动作」。

## 一句话

监听指定钱包的 ERC-20 转出，单笔超过阈值时，由 Reactive 跨链回调到目标链记录一条 Alert。

## 仓库

https://github.com/artistlogic/guardian

（本报告对应提交时版本：commit `9e912f2`）

## 三笔交易

| 环节 | 链接 |
|---|---|
| ① 源链事件（Sepolia，D3RT Transfer 10 枚） | https://eth-sepolia.blockscout.com/tx/0x1ba40219983167c32c3b8deb9017c57fcb1f38fa6bbd5b582f0429d495f1b407 |
| ② Reactive `react()`（Lasna） | https://lasna.reactscan.net/tx/0x74c7cb0e973156073c683486d13a57bf72346d2bff4e9199a37d33a1a3c1b342 |
| ③ 目标链回调（`Alert`，Sepolia） | https://eth-sepolia.blockscout.com/tx/0x53dcc37d4f98662ba1672d34b958af6b126245038fa15953de3d517bece8e4cd |

## 时序图

```text
被守护钱包            Sepolia              Lasna                  Sepolia
    │ 转出 10 D3RT      │                    │                      │
    ├──────────────────▶│ Transfer 事件      │                      │
    │                   │ ──订阅匹配────────▶│ react()              │
    │                   │                    │ value ≥ 阈值 ?       │
    │                   │                    │ requestCallbackV_1_0 │
    │                   │                    ├── 回调代理派送 ─────▶│ onAlert()
    │                   │                    │                      │ emit Alert
```

## 合约（本报告对应版本）

| 合约 | 链 | 地址 |
|---|---|---|
| GuardianReactive | Lasna (5318007) | `0x292b87c5df8d322de30e1402801f78f2e8563405` |
| GuardianCallback | Sepolia (11155111) | `0x8068fbf573fb522748f7786b485595b531666ec3` |

链上读数：`alerts = 1`，`callback_count = 1`。

## 迭代说明

测试网迭代中部署过多个版本：v1（修复前 bug 版）、**v2（本报告版本）**、v3（后续加保护版）。
v1/v2 已 `pause()` 退订，链上可见；本报告三笔交易对应 v2。
