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

## 演示视频 / PPT

- 视频脚本与 8 页 PPT 大纲：见提交物《提交包-D13.md》
- 视频：<3 分钟，录屏 + 讲解

## AI 使用说明

合约骨架、测试、README 由 AI 辅助起草，逐行人工审阅；
全部命令手工在测试网执行，第 2 节证据为真实链上交易（可用 `cast` 独立核对）。
