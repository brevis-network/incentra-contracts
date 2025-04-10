// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import {CampaignCL} from "../src/concentrated-liquidity/CampaignCL.sol";

contract DeployCampaignCL is Script {
    function run() public {
        vm.startBroadcast();
        CampaignCL c = new CampaignCL();
        console.log("CampaignCL impl contract deployed at ", address(c));
        vm.stopBroadcast();
    }
}
