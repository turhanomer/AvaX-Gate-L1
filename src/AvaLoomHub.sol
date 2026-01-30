// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ITeleporterMessenger} from "./teleporter/ITeleporterMessenger.sol";
import {ITeleporterReceiver} from "./teleporter/ITeleporterReceiver.sol";
import {AvaLoomVNFT} from "./AvaLoomVNFT.sol";

/**
 * @title AvaLoomHub
 * @author AvaLoom (Retro9000)
 * @notice Central marketplace on AvaLoom L1. Receives lock notifications, mints V-NFTs, manages listings, executes buys (90% seller / 10% burn), and sends release messages back to source.
 * @dev Implements ITeleporterReceiver. Follows Checks-Effects-Interactions and uses ReentrancyGuard.
 */
contract AvaLoomHub is ITeleporterReceiver, ReentrancyGuard {
    using SafeERC20 for IERC20;

    /// @notice Teleporter messenger on AvaLoom L1.
    ITeleporterMessenger public immutable TELEPORTER_MESSENGER;
    /// @notice V-NFT contract (virtual NFTs representing locked originals).
    AvaLoomVNFT public immutable V_NFT;

    /// @notice 10% of sale price is sent to burn address (Retro9000 / AVAX burn alignment).
    uint256 public constant BURN_BPS = 1000;
    /// @notice Basis points denominator.
    uint256 public constant BPS_DENOMINATOR = 10_000;
    /// @notice Burn address for 10% commission (signals support for network economy).
    address public constant BURN_ADDRESS = 0x000000000000000000000000000000000000dEaD;

    /// @notice Gas limit for delivering the release message on the Source L1.
    uint256 public constant RELEASE_MESSAGE_REQUIRED_GAS = 400_000;

    struct Listing {
        uint256 originalTokenId;
        address originalContract;
        bytes32 sourceBlockchainId;
        address sourceSenderAddress;
        address seller;
        uint256 price;
        bool listed;
        bool sold;
    }

    /// @notice Listing by V-NFT token ID.
    mapping(uint256 => Listing) public listings;
    /// @notice Source L1 blockchain ID => Source contract address (for sending release messages).
    mapping(bytes32 => address) public sourceContractsByChainId;
    /// @notice Pending release: vNftId => released (so we can support retry without double-release).
    mapping(uint256 => bool) public releaseSent;

    event VNFTCreated(
        uint256 indexed vNftId,
        uint256 originalTokenId,
        address originalContract,
        bytes32 sourceBlockchainId,
        address seller
    );
    event Listed(uint256 indexed vNftId, uint256 price);
    event Sold(
        uint256 indexed vNftId,
        address indexed buyer,
        address indexed seller,
        uint256 price,
        uint256 burnAmount,
        bytes32 messageId
    );
    event ReleaseMessageSent(
        uint256 indexed vNftId,
        bytes32 sourceBlockchainId,
        address sourceContract,
        address buyer
    );
    event SourceContractSet(bytes32 indexed chainId, address sourceContract);

    modifier onlyTeleporter() {
        _onlyTeleporter();
        _;
    }

    function _onlyTeleporter() internal view {
        require(
            msg.sender == address(TELEPORTER_MESSENGER),
            "AvaLoomHub: only Teleporter"
        );
    }

    /**
     * @param _teleporterMessenger Address of the TeleporterMessenger on AvaLoom L1.
     * @param _vNft Address of the AvaLoomVNFT contract.
     */
    constructor(address _teleporterMessenger, address _vNft) {
        require(_teleporterMessenger != address(0), "AvaLoomHub: zero messenger");
        require(_vNft != address(0), "AvaLoomHub: zero vNFT");
        TELEPORTER_MESSENGER = ITeleporterMessenger(_teleporterMessenger);
        V_NFT = AvaLoomVNFT(payable(_vNft));
    }

    /**
     * @notice Register a source contract for a given source chain (so we know where to send release messages).
     * @param chainId Source L1 blockchain ID.
     * @param sourceContract Address of AvaLoomSource on that chain.
     */
    function setSourceContract(bytes32 chainId, address sourceContract) external {
        require(sourceContract != address(0), "AvaLoomHub: zero address");
        sourceContractsByChainId[chainId] = sourceContract;
        emit SourceContractSet(chainId, sourceContract);
    }

    /**
     * @notice Receive lock notification from a source L1; mint V-NFT and create listing.
     * @dev Only callable by Teleporter. Checks: sender. Effects: mint, create listing. No external token transfer before state updates (CEI).
     * @param originChainId The source chain blockchain ID.
     * @param originSenderAddress The AvaLoomSource contract address on the source chain.
     * @param message ABI-encoded (tokenId, owner, originalContractAddress).
     * @custom:security CEI; onlyTeleporter
     */
    function receiveTeleporterMessage(
        bytes32 originChainId,
        address originSenderAddress,
        bytes calldata message
    ) external override onlyTeleporter {
        (uint256 tokenId, address owner, address originalContractAddress) =
            abi.decode(message, (uint256, address, address));

        // --- Effects ---
        uint256 vNftId = V_NFT.mint(owner);
        listings[vNftId] = Listing({
            originalTokenId: tokenId,
            originalContract: originalContractAddress,
            sourceBlockchainId: originChainId,
            sourceSenderAddress: originSenderAddress,
            seller: owner,
            price: 0,
            listed: false,
            sold: false
        });

        emit VNFTCreated(vNftId, tokenId, originalContractAddress, originChainId, owner);
    }

    /**
     * @notice List a V-NFT for sale at the given price in wei (native token).
     * @param vNftId The V-NFT token ID.
     * @param priceInWei Price in wei (native token, e.g. AVAX/LOOM).
     * @custom:security CEI
     */
    function listForSale(uint256 vNftId, uint256 priceInWei) external {
        Listing storage listing = listings[vNftId];
        require(listing.seller != address(0), "AvaLoomHub: no listing");
        require(!listing.sold, "AvaLoomHub: already sold");
        require(msg.sender == listing.seller, "AvaLoomHub: not seller");

        listing.price = priceInWei;
        listing.listed = true;

        emit Listed(vNftId, priceInWei);
    }

    /**
     * @notice Buy a listed V-NFT. Sends 90% to seller, 10% to burn address; burns V-NFT; sends release message to source L1.
     * @dev Relayer fee for the release message: buyer must approve and send feeToken to this contract; we approve Teleporter. If feeAmount is 0, no relayer fee is attached.
     * @param vNftId The V-NFT token ID to buy.
     * @param relayerFeeToken ERC20 address for relayer incentive (use address(0) and 0 amount for no fee).
     * @param relayerFeeAmount Amount of fee tokens for the relayer.
     * @custom:security CEI + ReentrancyGuard
     */
    function buy(
        uint256 vNftId,
        address relayerFeeToken,
        uint256 relayerFeeAmount
    ) external payable nonReentrant {
        Listing storage listing = listings[vNftId];

        // --- Checks ---
        require(listing.seller != address(0), "AvaLoomHub: no listing");
        require(listing.listed, "AvaLoomHub: not listed");
        require(!listing.sold, "AvaLoomHub: already sold");
        require(msg.value >= listing.price, "AvaLoomHub: insufficient value");
        require(msg.sender != listing.seller, "AvaLoomHub: cannot buy own");

        address seller = listing.seller;
        uint256 price = listing.price;
        uint256 burnAmount = (price * BURN_BPS) / BPS_DENOMINATOR;
        uint256 sellerAmount = price - burnAmount;

        address sourceContract = sourceContractsByChainId[listing.sourceBlockchainId];
        require(sourceContract != address(0), "AvaLoomHub: source not set");

        // --- Effects ---
        listing.sold = true;
        listing.listed = false;
        releaseSent[vNftId] = true;

        V_NFT.burn(vNftId);

        // --- Interactions ---
        (bool sentSeller,) = seller.call{value: sellerAmount}("");
        require(sentSeller, "AvaLoomHub: send seller failed");

        (bool sentBurn,) = BURN_ADDRESS.call{value: burnAmount}("");
        require(sentBurn, "AvaLoomHub: send burn failed");

        uint256 adjustedFeeAmount = 0;
        if (relayerFeeAmount > 0 && relayerFeeToken != address(0)) {
            IERC20(relayerFeeToken).safeTransferFrom(msg.sender, address(this), relayerFeeAmount);
            adjustedFeeAmount = relayerFeeAmount;
            IERC20(relayerFeeToken).safeIncreaseAllowance(address(TELEPORTER_MESSENGER), adjustedFeeAmount);
        }

        bytes memory releaseMessage = abi.encode(
            listing.originalTokenId,
            listing.originalContract,
            msg.sender
        );

        bytes32 messageId = TELEPORTER_MESSENGER.sendCrossChainMessage(
            ITeleporterMessenger.TeleporterMessageInput({
                destinationBlockchainId: listing.sourceBlockchainId,
                destinationAddress: sourceContract,
                feeInfo: ITeleporterMessenger.TeleporterFeeInfo({
                    feeTokenAddress: relayerFeeToken,
                    amount: adjustedFeeAmount
                }),
                requiredGasLimit: RELEASE_MESSAGE_REQUIRED_GAS,
                allowedRelayerAddresses: new address[](0),
                message: releaseMessage
            })
        );

        emit Sold(vNftId, msg.sender, seller, price, burnAmount, messageId);
        emit ReleaseMessageSent(vNftId, listing.sourceBlockchainId, sourceContract, msg.sender);
    }

    /**
     * @notice Retry sending the release message for a sold V-NFT if delivery failed. Only usable once per vNftId (releaseSent already set); callable by anyone to incentivize relayers.
     * @dev V-NFT must already be burned and listing marked sold. Re-sends same payload (tokenId, originalContract, buyer). Does not clear listing to avoid double-release; Source contract will reject if already released.
     * @param vNftId The V-NFT token ID that was sold.
     * @param buyer The buyer address (must match the listing at time of buy).
     * @param relayerFeeToken Fee token for relayer.
     * @param relayerFeeAmount Fee amount.
     * @return messageId The new Teleporter message ID.
     */
    function retryRelease(
        uint256 vNftId,
        address buyer,
        address relayerFeeToken,
        uint256 relayerFeeAmount
    ) external nonReentrant returns (bytes32 messageId) {
        Listing storage listing = listings[vNftId];
        require(listing.sold, "AvaLoomHub: not sold");
        require(releaseSent[vNftId], "AvaLoomHub: release already sent");
        require(listing.originalContract != address(0), "AvaLoomHub: no listing");

        address sourceContract = sourceContractsByChainId[listing.sourceBlockchainId];
        require(sourceContract != address(0), "AvaLoomHub: source not set");

        uint256 adjustedFeeAmount = 0;
        if (relayerFeeAmount > 0 && relayerFeeToken != address(0)) {
            IERC20(relayerFeeToken).safeTransferFrom(msg.sender, address(this), relayerFeeAmount);
            adjustedFeeAmount = relayerFeeAmount;
            IERC20(relayerFeeToken).safeIncreaseAllowance(address(TELEPORTER_MESSENGER), adjustedFeeAmount);
        }

        bytes memory releaseMessage = abi.encode(
            listing.originalTokenId,
            listing.originalContract,
            buyer
        );

        messageId = TELEPORTER_MESSENGER.sendCrossChainMessage(
            ITeleporterMessenger.TeleporterMessageInput({
                destinationBlockchainId: listing.sourceBlockchainId,
                destinationAddress: sourceContract,
                feeInfo: ITeleporterMessenger.TeleporterFeeInfo({
                    feeTokenAddress: relayerFeeToken,
                    amount: adjustedFeeAmount
                }),
                requiredGasLimit: RELEASE_MESSAGE_REQUIRED_GAS,
                allowedRelayerAddresses: new address[](0),
                message: releaseMessage
            })
        );

        emit ReleaseMessageSent(vNftId, listing.sourceBlockchainId, sourceContract, buyer);
        return messageId;
    }

    /**
     * @notice Return listing details for a V-NFT.
     */
    function getListing(uint256 vNftId) external view returns (Listing memory) {
        return listings[vNftId];
    }
}
