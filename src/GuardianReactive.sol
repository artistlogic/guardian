// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import { AbstractReactive } from "./reactive/base/AbstractReactive.sol";
import { IReactive } from "./reactive/interfaces/IReactive.sol";
import { ISystemContract } from "./reactive/interfaces/ISystemContract.sol";

/// @title GuardianReactive
/// @notice 监听源链上"被守护地址"转出代币的事件；单笔金额超过阈值时，
///         跨链回调到目标链的记录合约，留下可查的 Alert。
/// @dev    订阅时就把 `from`（topic1）锁死为被守护地址，网络侧先过滤噪音；
///         金额阈值在 react() 内判断，用 return 静默退出（回滚也收费）。
contract GuardianReactive is AbstractReactive {
    /// @notice ERC-20 Transfer(address indexed from, address indexed to, uint256 value)
    uint256 private constant TRANSFER_TOPIC_0 =
        0xddf252ad1be2c89b69c2b068fc378daa952ba7f163c4a11628f55a4df523b3ef;

    address public immutable owner;
    uint256 public immutable originChainId;
    address public immutable token;
    address public immutable watch;
    uint256 public immutable threshold;
    uint256 public immutable maxAlerts;
    uint256 public immutable destChainId;
    uint64 public immutable gasLimit;

    address public recipient;
    uint256 public alerts;
    uint256 public lastValue;
    uint256 public lastOriginTx;
    bool public paused;

    event RecipientSet(address indexed recipient);
    event Alerted(uint256 value, uint256 originTxHash, uint256 alertIndex);
    event Unsubscribed(uint256 alerts);

    constructor(
        uint256 originChainId_,
        address token_,
        address watch_,
        uint256 threshold_,
        uint256 maxAlerts_,
        uint256 destChainId_,
        uint64 gasLimit_
    ) payable {
        owner = msg.sender;
        originChainId = originChainId_;
        token = token_;
        watch = watch_;
        threshold = threshold_;
        maxAlerts = maxAlerts_;
        destChainId = destChainId_;
        gasLimit = gasLimit_;

        // 订阅：只关心「被守护地址作为 from」的 Transfer
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
        if (log_.contractAddress != token) return;
        if (log_.opCode != 3) return; // Transfer 有 3 个 topic
        if (paused) return;
        if (alerts >= maxAlerts) return;
        if (recipient == address(0)) return;

        // Transfer 的 data 只有一笔金额
        uint256 value = abi.decode(log_.data, (uint256));
        if (value < threshold) return;

        alerts += 1;
        lastValue = value;
        lastOriginTx = log_.txHash;

        // 第一个参数留给代理注入「发起回调的 reactive 地址」
        bytes memory payload =
            abi.encode(address(0), log_.chainId, log_.txHash, value, alerts);

        SYSTEM.requestCallbackV_1_0(
            ISystemContract.CallbackConfiguration_V_1_0({
                chainId: destChainId,
                recipient: recipient,
                gasLimit: gasLimit,
                payload: payload
            })
        );

        emit Alerted(value, log_.txHash, alerts);

        if (alerts >= maxAlerts) {
            _unsubscribe();
        }
    }

    /// @notice 绑定目标链回调合约（只能由 owner 设置一次）
    function setRecipient(address recipient_) external {
        require(msg.sender == owner, "not owner");
        recipient = recipient_;
        emit RecipientSet(recipient_);
    }

    /// @notice 紧急暂停：主动退订，之后不再处理事件
    function pause() external {
        require(msg.sender == owner, "not owner");
        paused = true;
        _unsubscribe();
        emit Unsubscribed(alerts);
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
