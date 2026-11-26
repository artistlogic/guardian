# Sentry · 链上钱包哨兵

Sentry 监听被守护钱包的 ERC-20 转出。单笔金额超过配置的阈值时，由 Reactive 合约发起跨链回调，
在目标链上记录一条告警，并由链下通知器推送给使用者。

它不需要自建服务器，也不需要托管私钥。

<img src="docs/architecture.svg" alt="Sepolia 上的转账、Lasna 上的 Reactive 合约、Sepolia 上的回调" width="100%">

- 实时看板：https://artistlogic.github.io/guardian/
- 代码仓库：https://github.com/artistlogic/guardian
- 回调合约（Sepolia）：[`0xa070a801…abe0`](https://eth-sepolia.blockscout.com/address/0xa070a801f8cd3f844e41e672d9e42380485cabe0)

## 1. 做什么

钱包发出一笔代币转账后，Sentry 判断它是否来自被守护地址、金额是否超过阈值。
两者都满足时，在目标链写入一条告警并推送通知。整个过程在链上可查。

| Sentry 会做 | Sentry 不做 |
|---|---|
| 发现超过阈值的外流 | 拦截或回滚交易 |
| 在目标链记录告警 | 转移或托管资金 |
| 向使用者推送通知 | 替代多签与审批流程 |

之所以做这个工具，是因为现有方式各有缺口：人工盯区块浏览器不可持续；
自建 keeper 需要服务器和托管私钥；付费监控定价不透明；钱包内置风控遵循厂商规则。

## 2. 链上证据

| 环节 | 交易 |
|---|---|
| 源链转出（10 D3RT，Sepolia） | https://eth-sepolia.blockscout.com/tx/0x632fb41ed499697eef05a0b5638984dd8161dc4f1a3cf1422c6fe1fad2d8494c |
| Lasna 上的 `react()` | https://lasna.reactscan.net/tx/0x01960122654318f025145e87230d469243b9eb387cc3076f6c55a742720500c5 |
| Sepolia 上的回调 `Alert` | https://eth-sepolia.blockscout.com/tx/0x3d673287f16d7a4e63526053c4061905360fe904ec615fca1d07fa343b7ce926 |
| 低于阈值的转账（1 D3RT） | https://eth-sepolia.blockscout.com/tx/0x99713085eab4f09c6e65980e0e8c97fb13125fa0e0ab52d3feb94f13f27931f4 |

低于阈值的那笔没有产生告警：正例运行前 `alerts` 保持为 0。

| 合约 | 链 | 地址 |
|---|---|---|
| GuardianReactive | Lasna (5318007) | `0xd9cda08baac9de9cbe658e553a8fd7112c7f7034` |
| GuardianCallback | Sepolia (11155111) | `0xa070a801f8cd3f844e41e672d9e42380485cabe0` |
| 被监控代币（D3RT） | Sepolia | `0x259d2fb64231d85e639d1074fa724bcdf29a4ed9` |

运行后读数：`alerts = 1`、`totalValue = 10e18`、`count = 1`。

```text
被守护钱包            Sepolia              Lasna                 Sepolia
     │ 转出 10 D3RT      │                    │                     │
     ├──────────────────▶│ Transfer           │                     │
     │                   │ ──事件───────────▶ │ react()             │
     │                   │                    │ 阈值与额度判断       │
     │                   │                    ├──回调──────────────▶│ onAlert()
     │                   │                    │                     │ emit Alert
```

## 3. 工作原理

订阅在网络层就做了收窄：`chainId + 代币 + topic0 + topic1(被守护钱包)`。
只有从被守护钱包转出的转账会进入 `react()`。

`react()` 按顺序判断：来源合约、日志类型、暂停状态、剩余告警额度、源交易是否已处理，
最后是金额阈值与额度上限。不满足条件的直接返回——回滚同样要付费。

命中后向系统合约请求回调。payload 带回调函数选择器与告警数据；
第一个参数由回调代理注入为发起请求的 reactive 合约地址，接收方据此校验来源。

回调函数有两道校验：`onlyServiceProvider` 只接受回调代理；
`onlyCallbackSender` 只接受授权的 reactive 合约。

额度控制：

- 单笔金额上限；累计金额上限，达到后自动退订
- 告警次数上限，达到后自动退订
- owner 可调用 `pause()`
- owner 可调用 `setThreshold()`，无需重新部署即可调整阈值

## 4. 运行

```bash
forge build
forge test -vv
```

测试网部署：

```bash
cp .env.example .env      # 填入 PRIVATE_KEY 与地址
source .env && bash script/deploy.sh
```

脚本会在 Lasna 部署 reactive 合约（预充值）、在目标链部署回调合约（预充值），并绑定接收地址，
最后打印两个合约地址。

触发一次：

```bash
cast send "$TOKEN" "transfer(address,uint256)" 0x000000000000000000000000000000000000dEaD 10000000000000000000 \
  --rpc-url "$SEPOLIA_RPC_URL" --private-key "$PRIVATE_KEY"
```

## 5. 验证

```bash
# Reactive 侧
cast call <REACTIVE> "alerts()(uint256)"     --rpc-url https://lasna-rpc.rnk.dev/
cast call <REACTIVE> "totalValue()(uint256)" --rpc-url https://lasna-rpc.rnk.dev/

# 目标链侧
cast call <CALLBACK> "count()(uint256)" --rpc-url https://ethereum-sepolia-rpc.publicnode.com

# 事件
cast logs --rpc-url https://lasna-rpc.rnk.dev/ --address <REACTIVE> "Alerted(uint256,uint256,uint256)"
cast logs --rpc-url https://ethereum-sepolia-rpc.publicnode.com --address <CALLBACK> "Alert(address,uint256,uint256,uint256,uint256)"
```

## 6. 测试

```bash
forge test -vv
# 13 passed
```

| 测试 | 验证内容 |
|---|---|
| `test_CountsOnce` | 超阈值转账被处理一次 |
| `test_BelowThresholdIgnored` | 低于阈值不处理 |
| `test_OnlySystem` | 非系统合约调用回滚 |
| `test_DuplicateIgnored` | 同一源交易只处理一次 |
| `test_PerAlertCap` | 单笔金额封顶 |
| `test_TotalCapStops` | 累计到上限停止 |
| `test_PauseStops` | 暂停后不处理 |
| `test_ThresholdConfigurable` | owner 可修改阈值 |
| `test_SetThresholdOnlyOwner` | 非 owner 不可修改 |
| `test_OnAlertHappyPath` | 代理可正常投递告警 |
| `test_OnAlertRejectsNonProxy` | 直接调用被拒 |
| `test_OnAlertRejectsWrongSender` | 只接受授权合约 |
| `test_OnAlertAccumulates` | 多次告警累计 |

## 7. 失败模式

| 情况 | 会发生什么 | 处理方式 |
|---|---|---|
| Reactive 合约余额用尽 | `debt > 0`，执行停止且不报错 | `depositTo()` 清零欠款 |
| 回调失败 | 代理照常收取本次费用并发出 `CallbackFailure`，`count` 不变 | 检查 `gasLimit`、目标合约与余额后重新触发 |
| 重复事件 | 被 `seen[txHash]` 拒绝 | 无需处理 |
| 噪音事件 | 被订阅与阈值过滤 | 调整阈值 |
| 金额超过上限 | 封顶或停止并退订 | 重新部署并调整上限 |
| 伪造回调 | 两道校验拒绝 | 无需处理 |

欠费恢复：

```bash
cast call 0x8888888888888888888888888888888888888888 "debt(address)(uint256)" <合约>
cast send 0x8888888888888888888888888888888888888888 "depositTo(address)" <合约> --value 1ether
cast call <合约> "alerts()(uint256)"
```

## 8. 范围与路线图

当前版本负责告警记录，不转移资金。

后续功能彼此独立、默认关闭：

1. 响应动作：用户授权一笔有限额度，超过更高的行动阈值时触发转账。
2. 白名单规则：转出到白名单之外的地址时提升风险等级。
3. 人工兜底：超过硬上限时通知人，而不是动钱。

这些功能需要第二个合约持有额度，与"只做告警"是不同的信任前提。
告警本身没有这项要求，因此先上线。

接入方式（配置文件 / Webhook / SDK）：[docs/INTEGRATION.md](docs/INTEGRATION.md)。

## 9. AI 辅助说明

以下部分由 AI 辅助起草，并在使用前完成审阅与测试：

| 部分 | AI 参与 | 验证方式 |
|---|---|---|
| 合约骨架与注释 | 起草，逐行审阅 | `forge build`、`forge test`（13 项）、链上运行 |
| 测试 | 起草 | `forge test -vv` 通过，逐条对照合约行为 |
| README | 起草 | 所有命令在测试网手工执行 |
| 第 2 节证据 | 真实交易产生 | 用 `cast` 与区块浏览器回读 |

第 2 节的地址与哈希均来自实际部署与转账。

## 10. 说明

- 仅使用测试网：源链与目标链为 Sepolia，Reactive 侧为 Lasna。
- 仓库不包含 `.env`。
- 通知器是链下脚本，不属于合约部分。
