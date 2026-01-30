// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "../src/AvaLoomHub.sol";

contract DeployHub is Script {
    function run() external {
        uint256 deployerPrivateKey = 0x7239c4fabb204db5fc612ad3a2542f405f18117b3dd96034aebfe93fcb365547;
        vm.startBroadcast(deployerPrivateKey);

        address teleporter = 0x253b2784c75e510dD0fF1da844684a1aC0aa5fcf;
        address vNft = 0x0C0DEbA5E0000000000000000000000000000000;

        new AvaLoomHub(teleporter, vNft);

        vm.stopBroadcast();
    }
}