// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import {RewardsSubmissionCL} from "../src/concentrated-liquidity/RewardsSubmissionCL.sol";

contract DeployRewardsSubmissionCL is Script {
    function run() public {
        vm.startBroadcast();
        RewardsSubmissionCL c = new RewardsSubmissionCL();
        console.log("RewardsSubmissionCL impl contract deployed at ", address(c));
        vm.stopBroadcast();
    }
}
