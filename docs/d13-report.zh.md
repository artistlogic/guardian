# D13 报告 · 提交包

> 任务：整理一份别人照着就能复现的提交包（仓库 / 合约 / 交易 / 视频 / AI 说明）。

## 仓库

https://github.com/artistlogic/guardian

- `README.md`：英文主版（黑客松用）
- `README.zh.md`：中文总览
- `script/deploy.sh` + `.env.example`：可复现部署
- `.github/workflows/test.yml`：CI 自动跑测试

## 最终合约（受保护版）

| 合约 | 链 | 地址 |
|---|---|---|
| GuardianReactive | Lasna (5318007) | `0xd9cda08baac9de9cbe658e553a8fd7112c7f7034` |
| GuardianCallback | Sepolia (11155111) | `0xa070a801f8cd3f844e41e672d9e42380485cabe0` |
| 被监控代币 D3RT | Sepolia | `0x259d2fb64231d85e639d1074fa724bcdf29a4ed9` |

## 交易（正例三笔 + 负例一笔）

| 环节 | 链接 |
|---|---|
| ① 源链 Transfer（10 D3RT） | https://eth-sepolia.blockscout.com/tx/0x4fe9d51fb6c57e86852e61fac842e98901788b7949bafb918019cd1f3cb326ee |
| ② Reactive `react()` | https://lasna.reactscan.net/tx/0x01960122654318f025145e87230d469243b9eb387cc3076f6c55a742720500c5 |
| ③ 目标链回调 `Alert` | https://eth-sepolia.blockscout.com/tx/0xe439ee83286ecc1222173317aadd28e6c104f4a5e9606106e8112e8ae3715371 |
| 负例（1 D3RT，低于阈值不触发） | https://eth-sepolia.blockscout.com/tx/0x99713085eab4f09c6e65980e0e8c97fb13125fa0e0ab52d3feb94f13f27931f4 |

读数：`alerts = 1`、`totalValue = 10e18`、`count = 1`；负例后 `alerts` 保持 0。

## 验证方式

```bash
cast call 0xd9cda08baac9de9cbe658e553a8fd7112c7f7034 "alerts()(uint256)" --rpc-url https://lasna-rpc.rnk.dev/
cast call 0xa070a801f8cd3f844e41e672d9e42380485cabe0 "count()(uint256)"  --rpc-url https://ethereum-sepolia-rpc.publicnode.com
```

## 复现步骤

```bash
git clone git@github.com:artistlogic/guardian.git && cd guardian
cp .env.example .env      # 填 PRIVATE_KEY 等
source .env && bash script/deploy.sh
forge test -vv            # 7 passed
```

## 演示视频

- 时长 <3 分钟，录屏 + 讲解：痛点 → 架构 → 链上演示（三笔交易）→ 保护与测试
- 视频链接：<待填>

## AI 使用说明

D13 任务要求：如使用 AI 编程工具，说明哪些部分由 AI 生成、如何验证。

- AI 参与：合约骨架与注释、Foundry 测试、README 结构由 AI 起草
- 人工验证：逐行审阅后 `forge build` + `forge test`（7 项全绿）；所有命令在测试网手工执行
- 链上验证：第 2 节地址与交易哈希均来自真实部署，可用 `cast` 独立核对，无模拟数据
