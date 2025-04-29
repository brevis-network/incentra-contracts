// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import {RewardsSubmissionGeneric} from "../src/generic/RewardsSubmissionGeneric.sol";

contract DeployRewardsSubmissionGeneric is Script {
    function run() public {
        vm.startBroadcast();
        RewardsSubmissionGeneric c = new RewardsSubmissionGeneric();
        console.log("RewardsSubmissionGeneric impl contract deployed at ", address(c));
        vm.stopBroadcast();
    }
}
