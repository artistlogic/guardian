// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import { IPayable } from "./reactive/interfaces/IPayable.sol";
import { AbstractCallback } from "./reactive/base/AbstractCallback.sol";

/// @title GuardianCallback
/// @notice Destination-chain contract that records alerts delivered by the
///         callback proxy.
/// @dev    Two locks:
///         - onlyServiceProvider: only the chain's callback proxy may call.
///         - onlyCallbackSender: the injected reactive address must match the
///           authorized GuardianReactive contract.
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

    /// @param proxy_    Callback proxy on this chain.
    /// @param reactive_ Authorized GuardianReactive contract.
    constructor(IPayable proxy_, address reactive_)
        payable
        AbstractCallback(proxy_, reactive_)
    {}

    /// @notice First argument is injected by the proxy; callers cannot forge it.
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

    /// @notice Anyone can settle outstanding debt from this contract's balance.
    function coverDebt() external {
        _coverDebt();
    }
}
