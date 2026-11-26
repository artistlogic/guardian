// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import { Test } from "forge-std/Test.sol";
import { IPayable } from "../src/reactive/interfaces/IPayable.sol";
import { GuardianCallback } from "../src/GuardianCallback.sol";

/// @notice Tests for GuardianCallback authorization and accounting.
contract GuardianCallbackTest is Test {
    address constant PROXY = address(0xA11CE);
    address constant REACTIVE = address(0xB0B);
    address constant ATTACKER = address(0xBAD);

    GuardianCallback callback;

    function setUp() public {
        callback = new GuardianCallback(IPayable(payable(PROXY)), REACTIVE);
    }

    /// Happy path: the proxy delivers an alert from the authorized reactive contract.
    function test_OnAlertHappyPath() public {
        vm.prank(PROXY);
        callback.onAlert(REACTIVE, 11155111, 0x1234, 10e18, 1);
        assertEq(callback.count(), 1);
        assertEq(callback.lastValue(), 10e18);
    }

    /// Protection: anyone other than the callback proxy is rejected.
    function test_OnAlertRejectsNonProxy() public {
        vm.prank(ATTACKER);
        vm.expectRevert();
        callback.onAlert(REACTIVE, 11155111, 0x1234, 10e18, 1);
    }

    /// Protection: the proxy cannot deliver an alert on behalf of another reactive contract.
    function test_OnAlertRejectsWrongSender() public {
        vm.prank(PROXY);
        vm.expectRevert();
        callback.onAlert(ATTACKER, 11155111, 0x1234, 10e18, 1);
    }

    /// Accounting: multiple alerts accumulate.
    function test_OnAlertAccumulates() public {
        vm.startPrank(PROXY);
        callback.onAlert(REACTIVE, 11155111, 0x1, 10e18, 1);
        callback.onAlert(REACTIVE, 11155111, 0x2, 20e18, 2);
        vm.stopPrank();
        assertEq(callback.count(), 2);
        assertEq(callback.lastValue(), 20e18);
    }
}
