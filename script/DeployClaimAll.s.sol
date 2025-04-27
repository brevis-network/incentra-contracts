// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import {ClaimAll} from "../src/rewards/ClaimAll.sol";

contract DeployClaimAll is Script {
    function run() public {
        vm.startBroadcast();
        ClaimAll c = new ClaimAll();
        console.log("BrevisProofRelay contract deployed at ", address(c));
        vm.stopBroadcast();
    }
}
