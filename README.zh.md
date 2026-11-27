# Sentry · 链上钱包哨兵

![Solidity](https://img.shields.io/badge/solidity-0.8.29-363636?logo=solidity&logoColor=white)
![Tests](https://img.shields.io/badge/tests-13%20passing-3ddc97)
![Reactive Omni](https://img.shields.io/badge/Reactive%20Omni-Lasna-54c8ff)
![Dashboard](https://img.shields.io/badge/dashboard-live-8b7bff)
![License](https://img.shields.io/badge/license-MIT-blue)

监听被守护钱包的 ERC-20 转出。超过阈值时，由 Reactive 合约在目标链记录告警，并由通知器推送。
不需要自建服务器，也不需要托管私钥。

**实时看板：** https://artistlogic.github.io/guardian/ ·
**接入文档：** [docs/INTEGRATION.md](docs/INTEGRATION.md)

<img src="docs/architecture.svg" alt="Sepolia 转账、Lasna Reactive 合约、Sepolia 回调" width="100%">

## 链上证据

| 环节 | 交易 |
|---|---|
| 源链转出（10 D3RT） | https://eth-sepolia.blockscout.com/tx/0x632fb41ed499697eef05a0b5638984dd8161dc4f1a3cf1422c6fe1fad2d8494c |
| Lasna 上的 `react()` | https://lasna.reactscan.net/tx/0x01960122654318f025145e87230d469243b9eb387cc3076f6c55a742720500c5 |
| 目标链回调 `Alert` | https://eth-sepolia.blockscout.com/tx/0x3d673287f16d7a4e63526053c4061905360fe904ec615fca1d07fa343b7ce926 |
| 负例（1 D3RT，不触发） | https://eth-sepolia.blockscout.com/tx/0x99713085eab4f09c6e65980e0e8c97fb13125fa0e0ab52d3feb94f13f27931f4 |

| 合约 | 链 | 地址 |
|---|---|---|
| GuardianReactive | Lasna 5318007 | `0xd9cda08baac9de9cbe658e553a8fd7112c7f7034` |
| GuardianCallback | Sepolia 11155111 | `0xa070a801f8cd3f844e41e672d9e42380485cabe0` |
| D3RT 测试代币 | Sepolia | `0x259d2fb64231d85e639d1074fa724bcdf29a4ed9` |

运行后读数：`alerts = 1`、`totalValue = 10e18`、`count = 1`。

## 工作原理

- 订阅在网络层收窄：`chainId + 代币 + topic0 + topic1(被守护钱包)`。
- `react()` 依次检查：来源合约、日志类型、暂停、额度、重复 `txHash`、阈值与上限。
  不满足条件的直接返回（回滚同样要付费）。
- 命中后请求回调；payload 带选择器，回调代理把 reactive 地址注入为第一个参数。
- 回调两道校验：`onlyServiceProvider`（只认代理）与 `onlyCallbackSender`（只认授权合约）。
- 额度：单笔上限、累计上限、次数上限（到限自动退订）、owner `pause()`、owner `setThreshold()`。

## 快速开始

```bash
forge build && forge test -vv          # 13 passed

cp .env.example .env                   # 填写 PRIVATE_KEY、WATCH、TOKEN
source .env && bash script/deploy.sh   # 部署两个合约并打印地址

cast send "$TOKEN" "transfer(address,uint256)" 0x000000000000000000000000000000000000dEaD \
  10000000000000000000 --rpc-url "$SEPOLIA_RPC_URL" --private-key "$PRIVATE_KEY"
```

## 验证

```bash
cast call <REACTIVE> "alerts()(uint256)"     --rpc-url https://lasna-rpc.rnk.dev/
cast call <REACTIVE> "totalValue()(uint256)" --rpc-url https://lasna-rpc.rnk.dev/
cast call <CALLBACK> "count()(uint256)"      --rpc-url https://ethereum-sepolia-rpc.publicnode.com
```

## 测试

`forge test -vv` → 13 passed：正常计数、低于阈值忽略、非系统调用拒绝、按 `txHash` 去重、
单笔与累计上限、暂停后停止、owner 改阈值（非 owner 拒绝）、回调正常路径、拒绝非代理、
拒绝错误发送方、多次累加。

## 失败模式

| 情况 | 影响 | 处理 |
|---|---|---|
| reactive 余额用尽 | `debt > 0`，静默停止执行 | `depositTo()` 清零 |
| 回调失败 | 照常收费并发出 `CallbackFailure`，`count` 不变 | 检查 gasLimit/目标/余额后重试 |
| 重复事件 | 被 `seen[txHash]` 拒绝 | 无需处理 |
| 伪造回调 | 两道校验拒绝 | 无需处理 |

## 范围与路线图

当前版本只记录告警，不转移资金。

1. 响应动作：用户授权有限额度 + 更高的行动阈值时触发转账。
2. 白名单规则：通知器解码 `Transfer` 接收方，陌生地址标记为更高风险（链下实现，不改合约）。
3. 人工兜底：超过硬上限时通知人，而不是动钱。

这些都需要第二个合约持有额度，与"只做告警"是不同的信任前提，因此告警先上线。

## 相关工作

Tenderly Alerts、OpenZeppelin Defender Sentinels、Forta、Hypernative、Hexagate 都假设监听程序运行在
用户自己的基础设施里。Sentry 把订阅与回调放在链上执行，没有需要托管的监听进程，每条告警都可在
区块浏览器核对。范围刻意更小：单个钱包、单个代币、单个阈值。

## AI 辅助说明

| 部分 | AI 参与 | 验证方式 |
|---|---|---|
| 合约骨架与注释 | 起草，逐行审阅 | `forge build`、`forge test`（13 项）、链上运行 |
| 测试 | 起草 | `forge test -vv` 通过 |
| README 与文档 | 起草 | 所有命令在测试网手工执行 |
| 链上证据 | 真实交易产生 | 用 `cast` 与区块浏览器回读 |

## 安全说明

- `.env` 已被 git 忽略，仓库中只有占位符版本的 `.env.example`。
- 仅使用测试网（Sepolia、Lasna），不涉及真实资金。
- 非测试用途建议使用 `cast wallet import`，不要明文保存私钥。
