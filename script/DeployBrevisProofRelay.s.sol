// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import {BrevisProofRelay} from "../src/brevis/BrevisProofRelay.sol";
import {IBrevisProof} from "../src/brevis/IBrevisProof.sol";

contract DeployBrevisProofRelay is Script {
    function run() public {
        vm.startBroadcast();
        BrevisProofRelay c = new BrevisProofRelay(IBrevisProof(address(0)));
        console.log("BrevisProofRelay contract deployed at ", address(c));
        vm.stopBroadcast();
    }
}
