// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {ERC721} from "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title AvaLoomVNFT
 * @author AvaLoom (Retro9000)
 * @notice Virtual NFT (V-NFT) representing a locked NFT on a source L1. Only the Hub can mint and burn.
 * @dev ERC721 with mint/burn restricted to the Hub (minter role).
 */
contract AvaLoomVNFT is ERC721, Ownable {
    /// @notice Only the Hub can mint and burn.
    address public minter;
    /// @notice Next token ID to mint.
    uint256 private _nextTokenId;

    event MinterUpdated(address indexed previousMinter, address indexed newMinter);

    constructor() ERC721("AvaLoom Virtual NFT", "AVNFT") Ownable(msg.sender) {}

    /**
     * @notice Set the minter (Hub) address. Only owner.
     * @param _minter Address of the AvaLoomHub.
     */
    function setMinter(address _minter) external onlyOwner {
        address old = minter;
        minter = _minter;
        emit MinterUpdated(old, _minter);
    }

    /**
     * @notice Mint a new V-NFT to the given address. Only minter (Hub).
     * @param to Recipient (seller on the Hub).
     * @return tokenId The minted token ID.
     */
    function mint(address to) external returns (uint256 tokenId) {
        require(msg.sender == minter, "AvaLoomVNFT: only minter");
        tokenId = _nextTokenId++;
        _safeMint(to, tokenId);
        return tokenId;
    }

    /**
     * @notice Burn a V-NFT. Only minter (Hub).
     * @param tokenId The V-NFT token ID to burn.
     */
    function burn(uint256 tokenId) external {
        require(msg.sender == minter, "AvaLoomVNFT: only minter");
        _burn(tokenId);
    }
}
