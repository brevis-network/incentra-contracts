// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import {BatchExecutor} from "../src/lib/BatchExecutor.sol";

contract DeployBatchExecutor is Script {
    function run() public {
        vm.startBroadcast();
        BatchExecutor c = new BatchExecutor();
        console.log("BatchExecutor contract deployed at ", address(c));
        vm.stopBroadcast();
    }
}
