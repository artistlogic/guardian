// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import { Test } from "forge-std/Test.sol";
import { GuardianReactive } from "../src/GuardianReactive.sol";
import { IReactive } from "../src/reactive/interfaces/IReactive.sol";
import { ISystemContract } from "../src/reactive/interfaces/ISystemContract.sol";
import { ISubscriptionService } from "../src/reactive/interfaces/ISubscriptionService.sol";

/// @notice Tests for GuardianReactive protections.
/// @dev The system contract has no code in the test environment, so its
///      subscribe / unsubscribe / requestCallbackV_1_0 methods are mocked.
///      react() is then called as if it came from the system contract.
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

    /// Happy path: a transfer above the threshold is processed once.
    function test_CountsOnce() public {
        _react(1, 10e18);
        assertEq(guardian.alerts(), 1);
        assertEq(guardian.totalValue(), 10e18);
        assertTrue(guardian.seen(1));
    }

    /// Protection 2: the same source transaction is processed only once.
    function test_DuplicateIgnored() public {
        _react(2, 10e18);
        _react(2, 10e18);
        _react(2, 10e18);
        assertEq(guardian.alerts(), 1);
    }

    /// Protection 1: transfers below the threshold are ignored.
    function test_BelowThresholdIgnored() public {
        _react(3, 4e18);
        assertEq(guardian.alerts(), 0);
    }

    /// Protection 1: calls from anyone but the system contract revert.
    function test_OnlySystem() public {
        vm.expectRevert();
        guardian.react(_log(4, 10e18));
    }

    /// Protection 3: a single alert is capped at maxValuePerAlert.
    function test_PerAlertCap() public {
        _react(5, 150e18);
        assertEq(guardian.alerts(), 1);
        assertEq(guardian.totalValue(), MAX_PER);
        assertEq(guardian.lastValue(), MAX_PER);
    }

    /// Protection 3: processing stops once the total cap is reached.
    function test_TotalCapStops() public {
        _react(6, 100e18);
        _react(7, 100e18); // total reaches the cap
        _react(8, 100e18); // over the cap: ignored
        assertEq(guardian.alerts(), 2);
        assertEq(guardian.totalValue(), MAX_TOTAL);
    }

    /// Emergency pause stops all further processing.
    function test_PauseStops() public {
        guardian.pause();
        _react(9, 10e18);
        assertEq(guardian.alerts(), 0);
    }
}
