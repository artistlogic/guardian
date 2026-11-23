// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import { Test } from "forge-std/Test.sol";
import { GuardianReactive } from "../src/GuardianReactive.sol";
import { IReactive } from "../src/reactive/interfaces/IReactive.sol";
import { ISystemContract } from "../src/reactive/interfaces/ISystemContract.sol";
import { ISubscriptionService } from "../src/reactive/interfaces/ISubscriptionService.sol";

/// @notice GuardianReactive 的保护逻辑测试
/// - 用 vm.mockCall 模拟系统合约（subscribe / unsubscribe / requestCallbackV_1_0）
/// - 用 vm.prank(SYSTEM) 模拟系统合约调用 react()
contract GuardianReactiveTest is Test {
    address constant SYSTEM = 0x8888888888888888888888888888888888888888;
    uint256 constant SEPOLIA = 11155111;

    address constant TOKEN = address(0x1000);
    address constant WATCH = address(0x2000);
    address constant CALLBACK = address(0x3000);

    uint256 constant THRESHOLD = 5e18;
    uint256 constant MAX_ALERTS = 3;
    uint256 constant MAX_PER = 100e18;
    uint256 constant MAX_TOTAL = 200e18;

    GuardianReactive guardian;

    function setUp() public {
        // 系统合约在测试环境里没有代码，先把要调用的三个方法 mock 掉
        vm.mockCall(SYSTEM, abi.encodeWithSelector(ISubscriptionService.subscribe.selector), "");
        vm.mockCall(SYSTEM, abi.encodeWithSelector(ISubscriptionService.unsubscribe.selector), "");
        vm.mockCall(
            SYSTEM,
            abi.encodeWithSelector(ISystemContract.requestCallbackV_1_0.selector),
            ""
        );

        guardian = new GuardianReactive(
            SEPOLIA,
            TOKEN,
            WATCH,
            THRESHOLD,
            MAX_ALERTS,
            MAX_PER,
            MAX_TOTAL,
            SEPOLIA,
            uint64(1_000_000)
        );
        guardian.setRecipient(CALLBACK);
    }

    function _log(uint256 txHash_, uint256 value_)
        internal
        pure
        returns (IReactive.LogRecord memory l)
    {
        l.chainId = SEPOLIA;
        l.contractAddress = TOKEN;
        l.opCode = 3;
        l.txHash = txHash_;
        l.data = abi.encode(value_);
    }

    function _react(uint256 txHash_, uint256 value_) internal {
        vm.prank(SYSTEM);
        guardian.react(_log(txHash_, value_));
    }

    /// 正常情况：超阈值事件被执行一次
    function test_CountsOnce() public {
        _react(1, 10e18);
        assertEq(guardian.alerts(), 1);
        assertEq(guardian.totalValue(), 10e18);
        assertTrue(guardian.seen(1));
    }

    /// 保护 ②：同一笔交易重复推送，只算一次
    function test_DuplicateIgnored() public {
        _react(2, 10e18);
        _react(2, 10e18);
        _react(2, 10e18);
        assertEq(guardian.alerts(), 1);
    }

    /// 保护 ①：低于阈值不触发
    function test_BelowThresholdIgnored() public {
        _react(3, 4e18);
        assertEq(guardian.alerts(), 0);
    }

    /// 保护 ①：非系统合约调用直接 revert
    function test_OnlySystem() public {
        vm.expectRevert();
        guardian.react(_log(4, 10e18));
    }

    /// 保护 ③：单笔金额被封顶
    function test_PerAlertCap() public {
        _react(5, 150e18);
        assertEq(guardian.alerts(), 1);
        assertEq(guardian.totalValue(), MAX_PER); // 记录封顶后的值
        assertEq(guardian.lastValue(), MAX_PER);
    }

    /// 保护 ③：累计金额到上限后不再处理
    function test_TotalCapStops() public {
        _react(6, 100e18);
        _react(7, 100e18); // 累计 200 = 上限，处理
        _react(8, 100e18); // 超上限，忽略
        assertEq(guardian.alerts(), 2);
        assertEq(guardian.totalValue(), MAX_TOTAL);
    }

    /// 暂停后不再处理
    function test_PauseStops() public {
        guardian.pause();
        _react(9, 10e18);
        assertEq(guardian.alerts(), 0);
    }
}
