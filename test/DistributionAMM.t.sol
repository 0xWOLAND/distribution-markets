// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

// import {Test, console} from "forge-std/Test.sol";
// import {Counter} from "../src/Counter.sol";

// contract CounterTest is Test {
//     Counter public counter;

//     function setUp() public {
//         counter = new Counter();
//         counter.setNumber(0);
//     }

//     function test_Increment() public {
//         counter.increment();
//         assertEq(counter.number(), 1);
//     }

//     function testFuzz_SetNumber(uint256 x) public {
//         counter.setNumber(x);
//         assertEq(counter.number(), x);
//     }
// }

import {Test, console} from "forge-std/Test.sol";
import {DistributionAMM} from "../src/DistributionAMM.sol";

contract DistributionAMMTest is Test {
    // Constants from DistributionAMM
    uint256 constant PRECISION = 1e18;
    uint256 constant SQRT_2 = 14142135623730950488; // sqrt(2) * 1e18
    uint256 constant SQRT_PI = 17724538509055160272; // sqrt(pi) * 1e18
    uint256 constant SQRT_2PI = 2506628274631000896; // sqrt(2pi) * 1e18


    DistributionAMM public amm;

    function setUp() public {
        amm = new DistributionAMM();
    }

    function test_Initialize() public {
        // Test parameters
        uint256 _k = 446701179693725312; // L2 norm constraint
        uint256 _b = 10e18; // Backing collateral
        uint256 _kToBRatio = _k * PRECISION / _b; // k/b ratio, scaled by PRECISION
        uint256 _sigma = 1e18; // Standard deviation
        uint256 _lambda = 1e18;
        int256 _mu = 0; // Mean
        uint256 _minSigma = 1e17; // Minimum sigma

        // Initialize the contract
        amm.initialize(_k, _b, _kToBRatio, _sigma, _lambda, _mu, _minSigma);

        // Verify state
        assertEq(amm.k(), _k, "k should match input");
        assertEq(amm.b(), _b, "b should match input");
        assertEq(amm.kToBRatio(), _kToBRatio, "kToBRatio should match input");
        assertEq(amm.sigma(), _sigma, "sigma should match input");
        assertEq(amm.lambda(), _lambda, "lambda should match input");
        assertEq(amm.mu(), _mu, "mu should match input");
        assertEq(amm.minSigma(), _minSigma, "minSigma should match input");
        assertEq(amm.totalShares(), 1e18, "totalShares should be 1e18");
        assertEq(amm.lpShares(address(this)), 1e18, "caller should have 1e18 LP shares");
        assertEq(amm.owner(), address(this), "owner should be caller");
        assertEq(amm.isResolved(), false, "isResolved should be false");
        assertEq(amm.outcome(), 0, "outcome should be 0");
    }
}