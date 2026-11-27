# Sentry · 链上钱包哨兵

![Solidity](https://img.shields.io/badge/solidity-0.8.29-363636?logo=solidity&logoColor=white)
![Tests](https://img.shields.io/badge/tests-13%20passing-3ddc97)
![Reactive Omni](https://img.shields.io/badge/Reactive%20Omni-Lasna-54c8ff)
![License](https://img.shields.io/badge/license-MIT-blue)

监听一个被守护钱包的 ERC-20 转出。超过阈值时，由 Reactive 合约在目标链记录告警并推送通知。
不需要服务器，也不需要托管私钥。

**看板：** https://artistlogic.github.io/guardian/ · **接入：** [docs/INTEGRATION.md](docs/INTEGRATION.md)

<img src="docs/architecture.svg" alt="Sepolia 转账、Lasna Reactive 合约、Sepolia 回调" width="100%">

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
2. `react()` 依次判断来源、日志类型、暂停、额度、`txHash` 去重、阈值与上限
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

13 个 Foundry 测试（阈值、去重、上限、暂停、owner 权限、回调双锁），每次 push 跑 CI。

| 失败 | 影响 | 恢复 |
|---|---|---|
| reactive 余额用尽 | `debt > 0`，静默停止 | `depositTo()` |
| 回调失败 | 照常收费、发出 `CallbackFailure`、`count` 不变 | 修复后重试 |
| 重复 / 伪造 | 被拒绝 | 无需处理 |

## 范围

只记录告警，不转移资金。下一步均为可选：白名单感知、每日摘要、预授权额度下的响应动作。

Tenderly、Defender Sentinels、Forta、Hypernative 等都假设监听器跑在用户自己的基础设施里。
Sentry 把规则、订阅与告警都放在链上。范围刻意很小：一个钱包、一个代币、一个阈值。

## 说明

部署密钥在 `.env`（已被 git 忽略），`.env.example` 只有占位符；仅测试网。
合约与测试起草使用了 AI 辅助；本文件中的命令与交易均已实际运行验证。
威胁模型与容量行为：[docs/SECURITY.md](docs/SECURITY.md)。
