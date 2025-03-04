pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import {Campaign} from "../src/Campaign.sol";

contract Deploy is Script {
    function run() public {
        vm.startBroadcast();
        Campaign c = new Campaign();
        console.log("Campaign impl contract deployed at ", address(c));
        vm.stopBroadcast();
    }
}