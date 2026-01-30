// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title ITeleporterMessenger
 * @author Avalanche / AvaLoom
 * @notice Interface for Avalanche Teleporter (ICM) cross-chain messaging.
 * @dev See https://github.com/ava-labs/teleporter
 */
interface ITeleporterMessenger {
    struct TeleporterFeeInfo {
        address feeTokenAddress;
        uint256 amount;
    }

    struct TeleporterMessageInput {
        bytes32 destinationBlockchainId;
        address destinationAddress;
        TeleporterFeeInfo feeInfo;
        uint256 requiredGasLimit;
        address[] allowedRelayerAddresses;
        bytes message;
    }

    /**
     * @dev Sends a cross-chain message to the destination chain.
     * @param messageInput The message input struct.
     * @return messageId Unique identifier for the message.
     */
    function sendCrossChainMessage(
        TeleporterMessageInput calldata messageInput
    ) external returns (bytes32 messageId);
}
