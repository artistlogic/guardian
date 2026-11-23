// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import { AbstractReactive } from "./reactive/base/AbstractReactive.sol";
import { IReactive } from "./reactive/interfaces/IReactive.sol";
import { ISystemContract } from "./reactive/interfaces/ISystemContract.sol";
import { GuardianCallback } from "./GuardianCallback.sol";

/// @title GuardianReactive
/// @notice 监听源链上"被守护地址"转出代币的事件；单笔金额超过阈值时，
///         跨链回调到目标链的记录合约，留下可查的 Alert。
/// @dev    三层保护：
///         ① 只在该触发时触发：订阅锁定 from = 被守护地址；react 内再判阈值
///         ② 同一事件不重复：按 origin txHash 去重
///         ③ 金额上限：单笔记录上限 + 累计记录上限
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

    /// @notice 已经处理过的源交易哈希（防重复）
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

        // 保护 ①：只订阅「被守护地址作为 from」的 Transfer
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
        // 保护 ①：来源与类型校验
        if (log_.contractAddress != token) return;
        if (log_.opCode != 3) return;
        if (paused) return;
        if (alerts >= maxAlerts) return;
        if (recipient == address(0)) return;

        // 保护 ②：同一笔源交易只处理一次
        if (seen[log_.txHash]) return;

        uint256 value = abi.decode(log_.data, (uint256));
        if (value < threshold) return;

        // 保护 ③：金额封顶 + 累计封顶
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

    /// @notice 绑定目标链回调合约（只能由 owner 设置）
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
