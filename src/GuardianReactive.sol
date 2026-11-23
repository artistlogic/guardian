// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import { AbstractReactive } from "./reactive/base/AbstractReactive.sol";
import { IReactive } from "./reactive/interfaces/IReactive.sol";
import { ISystemContract } from "./reactive/interfaces/ISystemContract.sol";
import { GuardianCallback } from "./GuardianCallback.sol";

/// @title GuardianReactive
/// @notice Watches ERC-20 transfers out of a guarded wallet. When a single
///         transfer reaches the threshold, it requests a cross-chain callback
///         that records an on-chain alert on the destination chain.
/// @dev    Three layers of protection:
///         1) Trigger only when it should: subscription is narrowed to
///            `from == watch`, and `react()` re-checks source, opCode,
///            pause flag and threshold.
///         2) Idempotency: a source txHash is processed at most once.
///         3) Spend caps: per-alert cap and total cap.
contract GuardianReactive is AbstractReactive {
    /// @notice keccak256("Transfer(address,address,uint256)")
    uint256 private constant TRANSFER_TOPIC_0 =
        0xddf252ad1be2c89b69c2b068fc378daa952ba7f163c4a11628f55a4df523b3ef;

    address public immutable owner;
    uint256 public immutable originChainId;
    address public immutable token;
    address public immutable watch;
    uint256 public immutable threshold;
    uint256 public immutable maxAlerts;
    uint256 public immutable maxValuePerAlert;
    uint256 public immutable maxTotalValue;
    uint256 public immutable destChainId;
    uint64 public immutable gasLimit;

    address public recipient;
    uint256 public alerts;
    uint256 public totalValue;
    uint256 public lastValue;
    uint256 public lastOriginTx;
    bool public paused;

    /// @notice Source transaction hashes already processed (idempotency).
    mapping(uint256 => bool) public seen;

    event RecipientSet(address indexed recipient);
    event Alerted(uint256 value, uint256 originTxHash, uint256 alertIndex);
    event ValueCapped(uint256 rawValue, uint256 cappedValue);
    event Unsubscribed(uint256 alerts, uint256 totalValue);

    constructor(
        uint256 originChainId_,
        address token_,
        address watch_,
        uint256 threshold_,
        uint256 maxAlerts_,
        uint256 maxValuePerAlert_,
        uint256 maxTotalValue_,
        uint256 destChainId_,
        uint64 gasLimit_
    ) payable {
        owner = msg.sender;
        originChainId = originChainId_;
        token = token_;
        watch = watch_;
        threshold = threshold_;
        maxAlerts = maxAlerts_;
        maxValuePerAlert = maxValuePerAlert_;
        maxTotalValue = maxTotalValue_;
        destChainId = destChainId_;
        gasLimit = gasLimit_;

        // Protection 1: only transfers where `from` is the guarded wallet.
        SYSTEM.subscribe(
            originChainId_,
            token_,
            TRANSFER_TOPIC_0,
            uint256(uint160(watch_)),
            REACTIVE_IGNORE,
            REACTIVE_IGNORE
        );
    }

    /// @inheritdoc IReactive
    function react(LogRecord calldata log_) external onlySystem {
        // Protection 1: source and event type checks.
        if (log_.contractAddress != token) return;
        if (log_.opCode != 3) return;
        if (paused) return;
        if (alerts >= maxAlerts) return;
        if (recipient == address(0)) return;

        // Protection 2: process each source transaction once.
        if (seen[log_.txHash]) return;

        uint256 value = abi.decode(log_.data, (uint256));
        if (value < threshold) return;

        // Protection 3: per-alert and total value caps.
        uint256 effective = value;
        if (value > maxValuePerAlert) {
            effective = maxValuePerAlert;
            emit ValueCapped(value, effective);
        }
        if (totalValue + effective > maxTotalValue) return;

        seen[log_.txHash] = true;
        alerts += 1;
        totalValue += effective;
        lastValue = effective;
        lastOriginTx = log_.txHash;

        // First argument is a placeholder overwritten by the proxy with the
        // address of the reactive contract that requested the callback.
        bytes memory payload = abi.encodeWithSelector(
            GuardianCallback.onAlert.selector,
            address(0),
            log_.chainId,
            log_.txHash,
            effective,
            alerts
        );

        SYSTEM.requestCallbackV_1_0(
            ISystemContract.CallbackConfiguration_V_1_0({
                chainId: destChainId,
                recipient: recipient,
                gasLimit: gasLimit,
                payload: payload
            })
        );

        emit Alerted(effective, log_.txHash, alerts);

        if (alerts >= maxAlerts || totalValue >= maxTotalValue) {
            _unsubscribe();
        }
    }

    /// @notice Binds the destination callback contract (owner only).
    function setRecipient(address recipient_) external {
        require(msg.sender == owner, "not owner");
        recipient = recipient_;
        emit RecipientSet(recipient_);
    }

    /// @notice Emergency stop: unsubscribe and ignore further events.
    function pause() external {
        require(msg.sender == owner, "not owner");
        paused = true;
        _unsubscribe();
        emit Unsubscribed(alerts, totalValue);
    }

    function _unsubscribe() internal {
        try
            SYSTEM.unsubscribe(
                originChainId,
                token,
                TRANSFER_TOPIC_0,
                uint256(uint160(watch)),
                REACTIVE_IGNORE,
                REACTIVE_IGNORE
            )
        {} catch {}
    }
}
