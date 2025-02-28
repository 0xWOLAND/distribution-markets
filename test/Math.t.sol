// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Test, console} from "forge-std/Test.sol";
import {Math} from "../src/Math.sol";

contract MathTest is Test {
    using Math for *;
    uint256 constant PRECISION = 1e18;

    function test_EvaluateAtMean() public pure {
        int256 x = 0;
        int256 mu = 0;
        uint256 sigma = 1e18;
        uint256 lambda = 1e18;
        uint256 result = Math.evaluate(x, mu, sigma, lambda);
        uint256 expected = 398942280401432677; // ≈ 0.3989e18
        assertApproxEqAbs(result, expected, 1e17, "Evaluate at mean incorrect");
    }

    function test_EvaluateZeroSigmaOrLambda() public pure {
        assertEq(Math.evaluate(0, 0, 0, 1e18), 0, "Zero sigma should return 0");
        assertEq(Math.evaluate(0, 0, 1e18, 0), 0, "Zero lambda should return 0");
    }

    function test_DifferenceIdenticalGaussians() public pure {
        int256 x = 0;
        int256 mu1 = 0; uint256 sigma1 = 1e18; uint256 lambda1 = 1e18;
        int256 mu2 = 0; uint256 sigma2 = 1e18; uint256 lambda2 = 1e18;
        int256 diff = Math.difference(x, mu1, sigma1, lambda1, mu2, sigma2, lambda2);
        assertEq(diff, 0, "Identical Gaussians should have zero difference");
    }

    function test_DifferenceDifferentMeans() public pure {
        int256 x = 0;
        int256 mu1 = 0; uint256 sigma1 = 1e18; uint256 lambda1 = 1e18;
        int256 mu2 = 1e18; uint256 sigma2 = 1e18; uint256 lambda2 = 1e18;
        int256 diff = Math.difference(x, mu1, sigma1, lambda1, mu2, sigma2, lambda2);
        assertGt(diff, 0, "Difference should be positive when x is at mu1");
    }

    function test_KLDivergenceZeroInputs() public pure {
        assertEq(Math.klDivergence(0, 0, 1e18, 0, 1e18, 1e18), 0, "Zero sigma1 should return 0");
        assertEq(Math.klDivergence(0, 1e18, 0, 0, 1e18, 1e18), 0, "Zero lambda1 should return 0");
        assertEq(Math.klDivergence(0, 1e18, 1e18, 0, 0, 1e18), 0, "Zero sigma2 should return 0");
        assertEq(Math.klDivergence(0, 1e18, 1e18, 0, 1e18, 0), 0, "Zero lambda2 should return 0");
    }

    function test_KLDivergenceIdenticalGaussians() public pure {
        int256 mu1 = 0; uint256 sigma1 = 1e18; uint256 lambda1 = 1e18;
        int256 mu2 = 0; uint256 sigma2 = 1e18; uint256 lambda2 = 1e18;
        uint256 kl = Math.klDivergence(mu1, sigma1, lambda1, mu2, sigma2, lambda2);
        assertEq(kl, 0, "KL divergence of identical Gaussians should be 0");
    }

    function test_KLDivergenceDifferentMeans() public pure {
        int256 mu1 = 0; uint256 sigma1 = 1e18; uint256 lambda1 = 1e18;
        int256 mu2 = 1e18; uint256 sigma2 = 1e18; uint256 lambda2 = 1e18;
        uint256 kl = Math.klDivergence(mu1, sigma1, lambda1, mu2, sigma2, lambda2);
        assertApproxEqAbs(kl, 0.5e18, 1e15, "KL divergence for mean shift incorrect");
    }

    function test_WassersteinDistanceZeroInputs() public pure {
        assertEq(Math.wassersteinDistance(0, 0, 1e18, 0, 1e18, 1e18), 0, "Zero sigma1 should return 0");
        assertEq(Math.wassersteinDistance(0, 1e18, 0, 0, 1e18, 1e18), 0, "Zero lambda1 should return 0");
        assertEq(Math.wassersteinDistance(0, 1e18, 1e18, 0, 0, 1e18), 0, "Zero sigma2 should return 0");
        assertEq(Math.wassersteinDistance(0, 1e18, 1e18, 0, 1e18, 0), 0, "Zero lambda2 should return 0");
    }

    function test_WassersteinDistanceIdenticalGaussians() public pure {
        int256 mu1 = 0; uint256 sigma1 = 1e18; uint256 lambda1 = 1e18;
        int256 mu2 = 0; uint256 sigma2 = 1e18; uint256 lambda2 = 1e18;
        uint256 distance = Math.wassersteinDistance(mu1, sigma1, lambda1, mu2, sigma2, lambda2);
        assertEq(distance, 0, "Wasserstein distance of identical Gaussians should be 0");
    }

    function test_WassersteinDistanceDifferentLambdas() public pure {
        int256 mu1 = 0; uint256 sigma1 = 1e18; uint256 lambda1 = 1e18;
        int256 mu2 = 0; uint256 sigma2 = 1e18; uint256 lambda2 = 2e18;
        uint256 distance = Math.wassersteinDistance(mu1, sigma1, lambda1, mu2, sigma2, lambda2);
        assertApproxEqAbs(distance, 1e18, 1e15, "Wasserstein distance for lambda difference incorrect");
    }

    function test_WassersteinDistanceDifferentMeans() public pure {
        int256 mu1 = 0; uint256 sigma1 = 1e18; uint256 lambda1 = 1e18;
        int256 mu2 = 1e18; uint256 sigma2 = 1e18; uint256 lambda2 = 1e18;
        uint256 distance = Math.wassersteinDistance(mu1, sigma1, lambda1, mu2, sigma2, lambda2);
        assertApproxEqAbs(distance, 0, 1e15, "Wasserstein distance for mean difference incorrect");
    }

    function testFuzz_Evaluate(int256 x, int256 mu, uint256 sigma, uint256 lambda) public pure {
        sigma = bound(sigma, 1e16, 10e18); // Avoid overflow and tiny sigma
        lambda = bound(lambda, 1e16, 10e18);
        x = bound(x, -10e18, 10e18);
        mu = bound(mu, -10e18, 10e18);
        uint256 result = Math.evaluate(x, mu, sigma, lambda);
        assertGe(result, 0, "Gaussian evaluation should be non-negative");
    }
}