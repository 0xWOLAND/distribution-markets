// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Script, console} from "forge-std/Script.sol";
import {DistributionAMM} from "../src/DistributionAMM.sol";

contract DistributionAMMScript is Script {
    DistributionAMM public distributionAMM;

    function setUp() public {}

    function run() public {
        vm.startBroadcast();

        distributionAMM = new DistributionAMM();

        vm.stopBroadcast();
    }
}
