# Sentry · 链上钱包哨兵

![Tests](https://img.shields.io/badge/tests-13%20passing-3ddc97)
![Reactive Omni](https://img.shields.io/badge/Reactive%20Omni-Lasna-54c8ff)
![Solidity](https://img.shields.io/badge/solidity-0.8.29-363636?logo=solidity&logoColor=white)
![License](https://img.shields.io/badge/license-MIT-blue)

监听一个被守护钱包的 ERC-20 转出。超过阈值时，由 Reactive 合约在目标链记录告警并推送通知。
不需要服务器，不需要托管私钥。

链上有记录、能送到你手上、每一跳都可核验——不只是链上 emit 一个事件。

**赛道 2 · Set It and Forget It** —— 个人自动化：不用托管服务器，不用托管私钥。

**看板** https://artistlogic.github.io/guardian/ · **接入** [docs/INTEGRATION.md](docs/INTEGRATION.md) · **安全** [docs/SECURITY.md](docs/SECURITY.md)

<img src="docs/architecture.svg" alt="Sepolia 转账、Lasna Reactive 合约、Sepolia 回调" width="100%">

## 场景

自托管钱包可能因为一笔意外的转出而损失代币。现有的"提前知道"方案，都要你托管或订阅什么：

| 方案 | 规则运行在 | 你的代价 |
|---|---|---|
| 自己盯区块浏览器 | 人 | 不可持续 |
| 自建 bot | 你的服务器 | 7×24 运维 + 私钥在机器上 |
| Tenderly / Alchemy | 厂商 + 你的监听器 | 自己维护基础设施 |
| Defender Sentinels | 厂商 | 企业级、偏重 |
| **Sentry** | **Reactive 网络** | **一条订阅 + 一个合约** |

## 证据

| 环节 | 交易 |
|---|---|
| 源链转出 10 D3RT | `0x4fe9d51f…326ee` · [Sepolia](https://eth-sepolia.blockscout.com/tx/0x4fe9d51fb6c57e86852e61fac842e98901788b7949bafb918019cd1f3cb326ee) |
| `react()` | `0x01960122…500c5` · [Lasna](https://lasna.reactscan.net/tx/0x01960122654318f025145e87230d469243b9eb387cc3076f6c55a742720500c5) |
| 回调 `Alert` | `0xe439ee83…715371` · [Sepolia](https://eth-sepolia.blockscout.com/tx/0xe439ee83286ecc1222173317aadd28e6c104f4a5e9606106e8112e8ae3715371) |
| 负例 1 D3RT | `0x99713085…7931f4` · 不触发 |

Reactive `0xd9cda08b…7034`（Lasna）· Callback `0xa070a801…abe0`（Sepolia）· 代币 `0x259d2fb6…4ed9`

## 工作原理

1. 订阅在网络层收窄：`chainId + 代币 + topic0 + topic1(钱包)`
2. `react()` 判断来源、日志类型、暂停、额度、`txHash` 去重、阈值与上限
3. 命中后请求回调；代理把 reactive 地址注入第一个参数
4. 回调双锁：`onlyServiceProvider` 与 `onlyCallbackSender`

## 运行

```bash
forge build && forge test -vv          # 13 passed
cp .env.example .env                   # 填 PRIVATE_KEY、WATCH、TOKEN
bash script/deploy.sh                  # 部署两个合约

source .env && cast send "$TOKEN" "transfer(address,uint256)" \
  0x000000000000000000000000000000000000dEaD 10000000000000000000 \
  --rpc-url "$SEPOLIA_RPC_URL" --private-key "$PRIVATE_KEY"
```

## 工程

13 个 Foundry 测试覆盖正常与失败路径；每次 push 自动跑 build 与 test。

| 失败 | 影响 | 恢复 |
|---|---|---|
| 余额用尽 | `debt > 0`，静默停止 | `depositTo()` |
| 回调失败 | 照常收费、`CallbackFailure`、`count` 不变 | 修复后重试 |
| 重复 / 伪造 | 被拒绝 | 无需处理 |

## 范围

只记录告警：不拦截、不转移资金、不持有私钥。下一步均为可选：白名单感知、每日摘要、
预授权额度下的响应动作。

## 安全

合约没有提款路径；owner 私钥最多只能改阈值、接收方或暂停。仅测试网；
密钥在 `.env`，从不进 git。细节：[docs/SECURITY.md](docs/SECURITY.md)。
