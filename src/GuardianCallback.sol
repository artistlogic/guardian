// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import { IPayable } from "./reactive/interfaces/IPayable.sol";
import { AbstractCallback } from "./reactive/base/AbstractCallback.sol";

/// @title GuardianCallback
/// @notice 部署在目标链，接收 GuardianReactive 的回调，把"异常转出"记录到链上。
/// @dev    两道门锁：
///         - onlyServiceProvider：只认目标链的 Callback Proxy
///         - onlyCallbackSender：payload 里注入的 reactive 地址必须是登记的那个
contract GuardianCallback is AbstractCallback {
    event Alert(
        address indexed reactive,
        uint256 originChainId,
        uint256 originTxHash,
        uint256 value,
        uint256 alertIndex
    );

    uint256 public count;
    uint256 public lastValue;
    uint256 public lastOriginTx;

    /// @param proxy_   目标链的 Callback Proxy
    /// @param reactive_ 授权的 GuardianReactive 地址
    constructor(IPayable proxy_, address reactive_)
        payable
        AbstractCallback(proxy_, reactive_)
    {}

    /// @notice 第一个参数由代理注入（reactive 地址），不能由调用者伪造
    function onAlert(
        address reactive_,
        uint256 originChainId_,
        uint256 originTxHash_,
        uint256 value_,
        uint256 alertIndex_
    ) external onlyServiceProvider onlyCallbackSender(reactive_) {
        count += 1;
        lastValue = value_;
        lastOriginTx = originTxHash_;
        emit Alert(reactive_, originChainId_, originTxHash_, value_, alertIndex_);
    }

    /// @notice 让任何人/合约都能清欠款（余额不足时把本合约的钱付给代理）
    function coverDebt() external {
        _coverDebt();
    }
}
