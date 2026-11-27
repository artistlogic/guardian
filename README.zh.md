# Sentry · 链上钱包哨兵

![Solidity](https://img.shields.io/badge/solidity-0.8.29-363636?logo=solidity&logoColor=white)
![Tests](https://img.shields.io/badge/tests-13%20passing-3ddc97)
![Reactive Omni](https://img.shields.io/badge/Reactive%20Omni-Lasna-54c8ff)
![License](https://img.shields.io/badge/license-MIT-blue)

监听一个被守护钱包的 ERC-20 转出。超过阈值时，由 Reactive 合约在目标链记录告警，并推送通知。

不需要服务器，不需要托管私钥。每条告警都是一笔链上交易。

**看板：** https://artistlogic.github.io/guardian/ · **接入文档：** [docs/INTEGRATION.md](docs/INTEGRATION.md)

<img src="docs/architecture.svg" alt="Sepolia 转账、Lasna Reactive 合约、Sepolia 回调" width="100%">

## 使用场景

自托管钱包里放着代币。真正危险的时刻，是一笔"主人没有预期到"的转出：被攻破的浏览器、
恶意的授权、泄露的助记词。等主人从区块浏览器发现时，往往已经过了几个小时，或者永远没发现。

现有的"提前知道"方案，各有代价：

| 方案 | 规则运行在 | 你要付出的代价 |
|---|---|---|
| 自己盯区块浏览器 | 人 | 不可持续 |
| 自建 bot | 你的服务器 | 7×24 运维 + 私钥在机器上 |
| Tenderly Alerts / Alchemy Notify | 厂商 + 你的监听器 | 基础设施仍归你维护 |
| OpenZeppelin Defender Sentinels | 厂商 | 企业级，偏重 |
| **Sentry** | **Reactive 网络** | **一条订阅 + 一个合约** |

Sentry 把规则留在链上：网络负责监听，合约负责判断，回调负责记录。
你收到的是通知，而不是一台要维护的机器。

## 证据

| 环节 | 交易 |
|---|---|
| 源链转出 10 D3RT | `0x4fe9d51f…326ee` · [Sepolia](https://eth-sepolia.blockscout.com/tx/0x4fe9d51fb6c57e86852e61fac842e98901788b7949bafb918019cd1f3cb326ee) |
| Lasna 上的 `react()` | `0x01960122…500c5` · [Lasna](https://lasna.reactscan.net/tx/0x01960122654318f025145e87230d469243b9eb387cc3076f6c55a742720500c5) |
| 回调发出 `Alert` | `0xe439ee83…715371` · [Sepolia](https://eth-sepolia.blockscout.com/tx/0xe439ee83286ecc1222173317aadd28e6c104f4a5e9606106e8112e8ae3715371) |
| 负例：1 D3RT | `0x99713085…7931f4` · 不触发 |

Reactive `0xd9cda08b…7034`（Lasna）· Callback `0xa070a801…abe0`（Sepolia）· 代币 `0x259d2fb6…4ed9`
首次运行后：`alerts = 1`、`totalValue = 10e18`、`count = 1`。

## 工作原理

1. 订阅在网络层收窄：`chainId + 代币 + topic0 + topic1(钱包)`
2. `react()` 依次判断：来源、日志类型、暂停、额度、`txHash` 去重、阈值与上限
3. 命中后请求回调；代理把 reactive 地址注入第一个参数
4. 回调双锁：`onlyServiceProvider`（只认代理）与 `onlyCallbackSender`（只认授权合约）

额度：单笔上限、累计上限、次数上限（到限自动退订）；owner 可 `pause()`、可 `setThreshold()`。

## 运行

```bash
forge build && forge test -vv          # 13 passed

cp .env.example .env                   # 填 PRIVATE_KEY、WATCH、TOKEN
bash script/deploy.sh                  # 部署 reactive 与 callback

source .env && cast send "$TOKEN" "transfer(address,uint256)" \
  0x000000000000000000000000000000000000dEaD 10000000000000000000 \
  --rpc-url "$SEPOLIA_RPC_URL" --private-key "$PRIVATE_KEY"
```

验证：

```bash
cast call <REACTIVE> "alerts()(uint256)" --rpc-url https://lasna-rpc.rnk.dev/
cast call <CALLBACK> "count()(uint256)"  --rpc-url https://ethereum-sepolia-rpc.publicnode.com
```

## 工程

13 个 Foundry 测试覆盖正常路径与失败路径（阈值、去重、上限、暂停、owner 权限、回调双锁）。
每次 push 都会跑 `forge build` 与 `forge test`。

| 失败 | 影响 | 恢复 |
|---|---|---|
| reactive 余额用尽 | `debt > 0`，静默停止 | `depositTo()` |
| 回调失败 | 照常收费、发出 `CallbackFailure`、`count` 不变 | 修复后重试 |
| 重复 / 伪造 | 被拒绝 | 无需处理 |

## 范围

本版本只记录告警：不拦截交易、不转移资金、不持有私钥。

下一步均为可选：白名单感知（解码接收方）、每日摘要（减少打扰）、预授权额度下的响应动作。
最后一项需要第二个合约持有额度——那是另一种信任前提，所以先交付"只告警"。

## 说明

安全模型与容量行为：[docs/SECURITY.md](docs/SECURITY.md)。
密钥在 `.env`（已被 git 忽略），`.env.example` 只有占位符；仅测试网。
起草使用了 AI 辅助；本文件中的命令与交易均已实际执行验证。
