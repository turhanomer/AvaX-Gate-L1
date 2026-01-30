// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {ERC721Holder} from "@openzeppelin/contracts/token/ERC721/utils/ERC721Holder.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ITeleporterMessenger} from "./teleporter/ITeleporterMessenger.sol";
import {ITeleporterReceiver} from "./teleporter/ITeleporterReceiver.sol";

/**
 * @title AvaLoomSource
 * @author AvaLoom (Retro9000)
 * @notice Locks NFTs on a source L1 and notifies the AvaLoom Hub via Teleporter. Releases NFTs to buyers when instructed by the Hub.
 * @dev Deploy on each source L1 (e.g. C-Chain, gaming L1). Follows Checks-Effects-Interactions and uses ReentrancyGuard.
 */
contract AvaLoomSource is ITeleporterReceiver, ReentrancyGuard, ERC721Holder {
    using SafeERC20 for IERC20;

    /// @notice Teleporter messenger used for cross-chain messages.
    ITeleporterMessenger public immutable TELEPORTER_MESSENGER;
    /// @notice AvaLoom L1 blockchain ID (destination for lock messages).
    bytes32 public immutable AVA_LOOM_BLOCKCHAIN_ID;
    /// @notice AvaLoom Hub contract address on AvaLoom L1.
    address public immutable AVA_LOOM_HUB_ADDRESS;

    /// @notice Gas limit for delivering the lock message on the Hub (recommended 300k–500k).
    uint256 public constant LOCK_MESSAGE_REQUIRED_GAS = 400_000;

    struct LockedNft {
        address nftContract;
        uint256 tokenId;
        address owner;
        bool exists;
    }

    /// @notice Escrow key = keccak256(abi.encodePacked(nftContract, tokenId))
    mapping(bytes32 => LockedNft) public lockedNfTs;

    event NFTLocked(
        address indexed nftContract,
        uint256 indexed tokenId,
        address indexed owner,
        bytes32 lockKey,
        bytes32 messageId
    );
    event NFTReleased(
        address indexed nftContract,
        uint256 indexed tokenId,
        address indexed newOwner
    );

    /**
     * @notice Only the Teleporter messenger may call the receiver function.
     */
    modifier onlyTeleporter() {
        _onlyTeleporter();
        _;
    }

    function _onlyTeleporter() internal view {
        require(
            msg.sender == address(TELEPORTER_MESSENGER),
            "AvaLoomSource: only Teleporter"
        );
    }

    /**
     * @param _teleporterMessenger Address of the TeleporterMessenger on this chain.
     * @param _avaLoomBlockchainId Blockchain ID of the AvaLoom L1.
     * @param _avaLoomHubAddress Address of the AvaLoomHub on the AvaLoom L1.
     */
    constructor(
        address _teleporterMessenger,
        bytes32 _avaLoomBlockchainId,
        address _avaLoomHubAddress
    ) {
        require(_teleporterMessenger != address(0), "AvaLoomSource: zero messenger");
        require(_avaLoomHubAddress != address(0), "AvaLoomSource: zero hub");
        TELEPORTER_MESSENGER = ITeleporterMessenger(_teleporterMessenger);
        AVA_LOOM_BLOCKCHAIN_ID = _avaLoomBlockchainId;
        AVA_LOOM_HUB_ADDRESS = _avaLoomHubAddress;
    }

    /**
     * @notice Locks an NFT in this contract and sends a cross-chain message to the AvaLoom Hub to mint a V-NFT.
     * @dev Checks: NFT exists, not already locked, caller owns and has approved. Effects: update escrow. Interactions: transferFrom, (optional) fee transfer/approve, sendCrossChainMessage.
     * @param nftContract The ERC721 contract address.
     * @param tokenId The token ID to lock.
     * @param feeTokenAddress ERC20 address for relayer fee (use address(0) and 0 amount for no fee).
     * @param feeAmount Amount of fee tokens for the relayer.
     * @return messageId The Teleporter message ID.
     * @custom:security CEI + ReentrancyGuard
     */
    function lockNft(
        IERC721 nftContract,
        uint256 tokenId,
        address feeTokenAddress,
        uint256 feeAmount
    ) external nonReentrant returns (bytes32 messageId) {
        // --- Checks ---
        bytes32 lockKey = keccak256(abi.encodePacked(address(nftContract), tokenId));
        require(!lockedNfTs[lockKey].exists, "AvaLoomSource: already locked");
        require(nftContract.ownerOf(tokenId) == msg.sender, "AvaLoomSource: not owner");

        // --- Effects ---
        lockedNfTs[lockKey] = LockedNft({
            nftContract: address(nftContract),
            tokenId: tokenId,
            owner: msg.sender,
            exists: true
        });

        // --- Interactions ---
        nftContract.transferFrom(msg.sender, address(this), tokenId);

        uint256 adjustedFeeAmount = 0;
        if (feeAmount > 0 && feeTokenAddress != address(0)) {
            IERC20(feeTokenAddress).safeTransferFrom(msg.sender, address(this), feeAmount);
            adjustedFeeAmount = feeAmount;
            IERC20(feeTokenAddress).safeIncreaseAllowance(address(TELEPORTER_MESSENGER), adjustedFeeAmount);
        }

        bytes memory message = abi.encode(tokenId, msg.sender, address(nftContract));
        messageId = TELEPORTER_MESSENGER.sendCrossChainMessage(
            ITeleporterMessenger.TeleporterMessageInput({
                destinationBlockchainId: AVA_LOOM_BLOCKCHAIN_ID,
                destinationAddress: AVA_LOOM_HUB_ADDRESS,
                feeInfo: ITeleporterMessenger.TeleporterFeeInfo({
                    feeTokenAddress: feeTokenAddress,
                    amount: adjustedFeeAmount
                }),
                requiredGasLimit: LOCK_MESSAGE_REQUIRED_GAS,
                allowedRelayerAddresses: new address[](0),
                message: message
            })
        );

        emit NFTLocked(address(nftContract), tokenId, msg.sender, lockKey, messageId);
        return messageId;
    }

    /**
     * @notice Receives a cross-chain message from the Hub to release an NFT to the buyer.
     * @dev Only callable by Teleporter. Checks: sender, decode. Effects: clear escrow. Interactions: safeTransferFrom.
     * @param message ABI-encoded (tokenId, originalContractAddress, newOwner).
     * @custom:security CEI; onlyTeleporter
     */
    function receiveTeleporterMessage(
        bytes32, /* originChainID */
        address, /* originSenderAddress */
        bytes calldata message
    ) external override onlyTeleporter {
        (uint256 tokenId, address originalContractAddress, address newOwner) =
            abi.decode(message, (uint256, address, address));

        bytes32 lockKey = keccak256(abi.encodePacked(originalContractAddress, tokenId));
        LockedNft storage locked = lockedNfTs[lockKey];

        // --- Checks ---
        require(locked.exists, "AvaLoomSource: not locked");

        // --- Effects ---
        locked.exists = false;
        delete lockedNfTs[lockKey];

        // --- Interactions ---
        IERC721(originalContractAddress).safeTransferFrom(address(this), newOwner, tokenId);

        emit NFTReleased(originalContractAddress, tokenId, newOwner);
    }

    /**
     * @notice Returns whether an NFT is currently locked.
     * @param nftContract The NFT contract address.
     * @param tokenId The token ID.
     */
    function isLocked(address nftContract, uint256 tokenId) external view returns (bool) {
        bytes32 lockKey = keccak256(abi.encodePacked(nftContract, tokenId));
        return lockedNfTs[lockKey].exists;
    }
}
