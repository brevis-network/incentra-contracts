// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import {RewardsSubmissionTH} from "../src/token-holding/RewardsSubmissionTH.sol";

contract DeployRewardsSubmissionTH is Script {
    function run() public {
        vm.startBroadcast();
        RewardsSubmissionTH c = new RewardsSubmissionTH();
        console.log("RewardsSubmissionTH impl contract deployed at ", address(c));
        vm.stopBroadcast();
    }
}
