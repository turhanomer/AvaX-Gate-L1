// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title ITeleporterReceiver
 * @author Avalanche / AvaLoom
 * @notice Interface for receiving cross-chain messages from Teleporter.
 * @dev Only the TeleporterMessenger contract may call receiveTeleporterMessage.
 */
interface ITeleporterReceiver {
    /**
     * @dev Called by the TeleporterMessenger when a cross-chain message is delivered.
     * @param originChainId The blockchain ID of the chain that sent the message.
     * @param originSenderAddress The address of the sender on the origin chain.
     * @param message ABI-encoded message payload.
     */
    function receiveTeleporterMessage(
        bytes32 originChainId,
        address originSenderAddress,
        bytes calldata message
    ) external;
}
