# D10 报告 · 加保护（防误触发 / 防重复 / 设上限）

> 任务：给自动化加三条保护，并用 Foundry 测试证明有效，README 写清"出问题怎么办"。

## 三条保护

| 保护 | 实现 |
|---|---|
| ① 只在该触发时触发 | 订阅 `topic1 = 被守护钱包`；`react()` 内校验来源合约、opCode、暂停状态、阈值 |
| ② 同一事件不重复 | `seen[txHash]` 去重，重复推送直接 `return` |
| ③ 金额上限 | 单笔 `maxValuePerAlert` 封顶；累计 `maxTotalValue` 到顶即停并退订 |

## 测试代码

https://github.com/artistlogic/guardian/blob/4c7ef59/test/GuardianReactive.t.sol

## forge test 输出

```text
Ran 7 tests for test/GuardianReactive.t.sol:GuardianReactiveTest
[PASS] test_BelowThresholdIgnored()
[PASS] test_CountsOnce()
[PASS] test_DuplicateIgnored()
[PASS] test_OnlySystem()
[PASS] test_PauseStops()
[PASS] test_PerAlertCap()
[PASS] test_TotalCapStops()
Suite result: ok. 7 passed; 0 failed
```

## README「出问题怎么办」

https://github.com/artistlogic/guardian/blob/4c7ef59/README.md
（第 5b 节「Failure modes / 出问题怎么办」）

覆盖：余额耗尽静默停服 + `depositTo` 恢复、回调失败 `CallbackFailure`、重复事件、误触发、
金额超额、伪造回调。

## 说明

本任务为本地测试验证（保护逻辑），无需链上部署；
对应受保护版合约在 D13 阶段部署（`0xd9cda08b…`）。
