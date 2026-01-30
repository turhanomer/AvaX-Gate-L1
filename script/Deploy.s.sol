// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title Deploy
 * @notice Deployment order and steps (see README for full instructions).
 * @dev To run with Foundry: forge install foundry-rs/forge-std, then use a script that calls the deploy functions.
 * Deployment order: 1) AvaLoomSource on Source L1. 2) AvaLoomVNFT on AvaLoom L1. 3) AvaLoomHub on AvaLoom L1.
 * 4) AvaLoomVNFT.setMinter(hubAddress). 5) AvaLoomHub.setSourceContract(sourceChainID, sourceContractAddress).
 */
contract Deploy {
    // Placeholder so this file documents deploy order. Use forge create or a full script with forge-std for actual deploys.
}
