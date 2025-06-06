// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import {CampaignRewardsClaim} from "../src/rewards/cross-chain/CampaignRewardsClaim.sol";

contract DeployCampaignRewardsClaim is Script {
    function run() public {
        vm.startBroadcast();
        CampaignRewardsClaim c = new CampaignRewardsClaim();
        console.log("CampaignRewardsClaim impl contract deployed at ", address(c));
        vm.stopBroadcast();
    }
}
