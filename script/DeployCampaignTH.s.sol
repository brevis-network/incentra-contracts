// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import {CampaignTH} from "../src/token-holding/CampaignTH.sol";

contract DeployCampaignTH is Script {
    function run() public {
        vm.startBroadcast();
        CampaignTH c = new CampaignTH();
        console.log("CampaignTH impl contract deployed at ", address(c));
        vm.stopBroadcast();
    }
}
