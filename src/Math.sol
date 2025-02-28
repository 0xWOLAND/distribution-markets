// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;
import "dependencies/@prb-math-4.1.0/src/Common.sol";

/**
 * @title Math
 * @dev Library for math calculations
 */
library Math {
    /**
     * @notice Calculate the value of a Gaussian function at a given point
     * @param x The point to evaluate the Gaussian at
     * @param mu The mean of the Gaussian
     * @param sigma The standard deviation of the Gaussian
     * @param lambda The scale factor of the Gaussian
     * @return The value of the Gaussian at point x
     */
    function evaluate(
        int256 x, 
        int256 mu, 
        uint256 sigma, 
        uint256 lambda
    ) internal pure returns (uint256) {
        if (sigma == 0 || lambda == 0) {
            return 0;
        }
        
        uint256 result;
        {
            uint256 deltaSquared = uint256((x - mu) * (x - mu));
            uint256 sigmaSquared = sigma * sigma;
            uint256 exponent = deltaSquared / (2 * sigmaSquared);
            result = lambda * exp2(exponent);
        }
        return result;
    }
    
    /**
     * @notice Calculate the difference between two Gaussian functions at a point
     * @param x The point to evaluate both Gaussians at
     * @param mu1 The mean of the first Gaussian
     * @param sigma1 The standard deviation of the first Gaussian
     * @param lambda1 The scale factor of the first Gaussian
     * @param mu2 The mean of the second Gaussian
     * @param sigma2 The standard deviation of the second Gaussian
     * @param lambda2 The scale factor of the second Gaussian
     * @return The value of [f(x) - g(x)]
     */
    function diff(
        int256 x,
        int256 mu1,
        uint256 sigma1,
        uint256 lambda1,
        int256 mu2,
        uint256 sigma2,
        uint256 lambda2
    ) internal pure returns (int256) {
        uint256 f = evaluate(x, mu1, sigma1, lambda1);
        uint256 g = evaluate(x, mu2, sigma2, lambda2);
        
        return f >= g ? int256(f - g) : -int256(g - f);
    }
    
    /**
     * @notice Calculate L2 norm between two Gaussians
     * @return L2 norm value
     */
    function l2Norm(
        int256 mu1,
        uint256 sigma1,
        uint256 lambda1,
        int256 mu2,
        uint256 sigma2,
        uint256 lambda2,
        uint256 precision,
        uint256 sqrtPi
    ) internal pure returns (uint256) {
        // Calculate first term in its own scope
        uint256 t1;
        {
            uint256 lambdaSq = lambda1 * lambda1;
            t1 = (lambdaSq * precision) / (2 * sigma1 * sqrtPi);
        }
        
        // Calculate second term in its own scope
        uint256 t2;
        {
            uint256 lambdaSq = lambda2 * lambda2;
            t2 = (lambdaSq * precision) / (2 * sigma2 * sqrtPi);
        }
        
        // Calculate cross term
        uint256 ct = crossTerm(mu1, sigma1, lambda1, mu2, sigma2, lambda2, precision, sqrtPi);
        
        // L2 norm squared = t1 + t2 - ct
        uint256 normSq = t1 + t2 > ct ? (t1 + t2 - ct) : 0;
        
        // L2 norm = sqrt(normSq)
        return sqrt(normSq * precision);
    }
    
    /**
     * @notice Calculate cross term for L2 norm
     * @return Cross term value
     */
    function crossTerm(
        int256 mu1,
        uint256 sigma1,
        uint256 lambda1,
        int256 mu2,
        uint256 sigma2,
        uint256 lambda2,
        uint256 precision,
        uint256 sqrtPi
    ) internal pure returns (uint256) {
        // Calculate mu diff and squared in their own scope
        uint256 dMuSq;
        {
            int256 dMu = mu1 - mu2;
            dMuSq = uint256(dMu * dMu);
        }
        
        // Calculate variance sum in its own scope
        uint256 varSum;
        {
            uint256 sigma1Sq = sigma1 * sigma1;
            uint256 sigma2Sq = sigma2 * sigma2;
            varSum = sigma1Sq + sigma2Sq;
        }
        
        // Calculate exp value in its own scope
        uint256 expVal;
        {
            uint256 expArg = (dMuSq * precision) / (2 * varSum);
            expVal = exp2(expArg);
        }
        
        // Calculate sqrt variance sum in its own scope
        uint256 sqrtVarSum = sqrt(varSum * precision);
        
        // Calculate lambda term in its own scope
        uint256 lambdaTerm;
        {
            uint256 lambdaProduct = lambda1 * lambda2;
            lambdaTerm = 2 * lambdaProduct * precision;
        }
        
        // Final calculation in its own scope
        uint256 numerator = (lambdaTerm * expVal) / sqrtPi;
        return numerator / (sqrtVarSum / precision);
    }
}