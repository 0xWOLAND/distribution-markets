// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Test, console} from "forge-std/Test.sol";
import {DistributionAMM, PositionNFT} from "../src/DistributionAMM.sol";

contract DistributionAMMTest is Test {
    // Constants from DistributionAMM
    uint256 constant PRECISION = 1e18;
    uint256 constant SQRT_2 = 14142135623730950488; // sqrt(2) * 1e18
    uint256 constant SQRT_PI = 17724538509055160272; // sqrt(pi) * 1e18
    uint256 constant SQRT_2PI = 2506628274631000896; // sqrt(2pi) * 1e18

    address public owner = address(0x1);
    address public user1 = address(0x2);

    DistributionAMM public amm;
    function setUp() public {
        vm.startPrank(owner);
        amm = new DistributionAMM();
        amm.initialize(
            446701179693725312,    // _k
            1000000000000000000,   // _b (10 scaled)
            44670117969372531,     // _kToBRatio
            1e18,                  // _sigma
            1e18,                  // _lambda
            0,                     // _mu
            1e16                   // _minSigma
        );
        vm.stopPrank();
    }

    function printPosition(uint256 positionId) public {
        PositionNFT positionNFT = PositionNFT(address(amm.positionNFT()));
        PositionNFT.Position memory position = positionNFT.getPosition(positionId);
        console.log("[POSITION NFT] positionId: ", positionId);
        console.log("position.owner: ", position.owner);
        console.log("position.collateral: ", position.collateral);
        console.log("position.initialMu: ", position.initialMu);
        console.log("position.initialSigma: ", position.initialSigma);
        console.log("position.initialLambda: ", position.initialLambda);
        console.log("position.targetMu: ", position.targetMu);
        console.log("position.targetSigma: ", position.targetSigma);
        console.log("position.targetLambda: ", position.targetLambda);
    }


    function test_AddLiquidity() public {
        vm.startPrank(user1);
        uint256 amount = 2e18;
        (uint256 shares, uint256 positionId) = amm.addLiquidity(amount);
        console.log("shares: ", shares);
        console.log("positionId: ", positionId);
        console.log("lpShares[user1]: ", amm.lpShares(user1));
        PositionNFT positionNFT = PositionNFT(address(amm.positionNFT()));
        printPosition(positionId);
        
        console.log("--------------------------------");

        uint256 removedAmount = amm.removeLiquidity(shares, positionId);
        console.log("removedAmount: ", removedAmount);
        printPosition(positionId);
        vm.stopPrank();
    }
}