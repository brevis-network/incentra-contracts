// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import {CampaignGeneric} from "../src/generic/CampaignGeneric.sol";

contract DeployCampaignGeneric is Script {
    function run() public {
        vm.startBroadcast();
        CampaignGeneric c = new CampaignGeneric();
        console.log("CampaignGeneric impl contract deployed at ", address(c));
        vm.stopBroadcast();
    }
}
