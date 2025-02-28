// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;
import { UD60x18, ud } from "@prb-math-4.1.0/src/UD60x18.sol";
import { SD59x18, sd } from "@prb-math-4.1.0/src/SD59x18.sol";
import { console } from "forge-std/console.sol";

/**
 * @title Math
 * @dev Library for math calculations using PRB Math fixed-point types
 */
library Math {
    /**
     * @notice Calculate the value of a Gaussian function at a given point
     * @param x The point to evaluate the Gaussian at (int256)
     * @param mu The mean of the Gaussian (int256)
     * @param sigma The standard deviation of the Gaussian (uint256)
     * @param lambda The scale factor of the Gaussian (uint256)
     * @return The value of the Gaussian at point x (uint256)
     */
    function evaluate(
        int256 x, 
        int256 mu, 
        uint256 sigma, 
        uint256 lambda
    ) internal pure returns (uint256) {
        if (sigma == 0|| lambda == 0) {
            return 0;
        }

        // Convert to PRB Math types
        SD59x18 xFixed = sd(x);
        SD59x18 muFixed = sd(mu);
        UD60x18 sigmaFixed = ud(sigma);
        UD60x18 lambdaFixed = ud(lambda);
        
        // Call the internal function
        UD60x18 result = _evaluate(xFixed, muFixed, sigmaFixed, lambdaFixed);
        
        // Convert back to uint256
        return result.unwrap();
    }
    
    /**
     * @notice Internal function to calculate the value of a Gaussian using fixed-point types
     */
    function _evaluate(
        SD59x18 x, 
        SD59x18 mu, 
        UD60x18 sigma, 
        UD60x18 lambda
    ) internal pure returns (UD60x18) {
        UD60x18 result;
        {
            SD59x18 xDiff = x.sub(mu);
            SD59x18 diffSquared = xDiff.mul(xDiff);
            UD60x18 deltaSquared = diffSquared.abs().intoUD60x18();
            UD60x18 sigmaSquared = sigma.mul(sigma);
            UD60x18 exponent = deltaSquared.div(sigmaSquared.add(sigmaSquared));
            result = lambda.mul(exponent.exp().inv());
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
     * @return The signed difference [f(x) - g(x)] as int256
     */
    function difference(
        int256 x,
        int256 mu1,
        uint256 sigma1,
        uint256 lambda1,
        int256 mu2,
        uint256 sigma2,
        uint256 lambda2
    ) internal pure returns (int256) {
        // Convert to PRB Math types
        SD59x18 xFixed = sd(x);
        SD59x18 mu1Fixed = sd(mu1);
        UD60x18 sigma1Fixed = ud(sigma1);
        UD60x18 lambda1Fixed = ud(lambda1);
        SD59x18 mu2Fixed = sd(mu2);
        UD60x18 sigma2Fixed = ud(sigma2);
        UD60x18 lambda2Fixed = ud(lambda2);
        
        // Calculate using fixed point
        UD60x18 f = _evaluate(xFixed, mu1Fixed, sigma1Fixed, lambda1Fixed);
        UD60x18 g = _evaluate(xFixed, mu2Fixed, sigma2Fixed, lambda2Fixed);
        
        // Calculate signed difference (may be negative)
        if (f.gte(g)) {
            return int256(f.sub(g).unwrap());
        } else {
            return -int256(g.sub(f).unwrap());
        }
    }

    /**
     * @notice Calculate L2 norm between two Gaussians
     * @return L2 norm value as uint256
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
        // Convert to PRB Math types
        SD59x18 mu1Fixed = sd(mu1);
        UD60x18 sigma1Fixed = ud(sigma1);
        UD60x18 lambda1Fixed = ud(lambda1);
        SD59x18 mu2Fixed = sd(mu2);
        UD60x18 sigma2Fixed = ud(sigma2);
        UD60x18 lambda2Fixed = ud(lambda2);
        UD60x18 precisionFixed = ud(precision);
        UD60x18 sqrtPiFixed = ud(sqrtPi);
        
        // Calculate L2 norm using fixed point
        UD60x18 result = _l2Norm(
            mu1Fixed, sigma1Fixed, lambda1Fixed,
            mu2Fixed, sigma2Fixed, lambda2Fixed,
            precisionFixed, sqrtPiFixed
        );
        
        // Convert back to uint256
        return result.unwrap();
    }
    
    /**
     * @notice Internal function to calculate L2 norm using fixed-point types
     */
    function _l2Norm(
        SD59x18 mu1,
        UD60x18 sigma1,
        UD60x18 lambda1,
        SD59x18 mu2,
        UD60x18 sigma2,
        UD60x18 lambda2,
        UD60x18 precision,
        UD60x18 sqrtPi
    ) internal pure returns (UD60x18) {
        // Calculate first term in its own scope
        UD60x18 two = ud(2e18);
        UD60x18 t1;
        {
            UD60x18 lambdaSq = lambda1.mul(lambda1);
            t1 = lambdaSq.div(two.mul(sigma1).mul(sqrtPi));
        }
        
        // Calculate second term in its own scope
        UD60x18 t2;
        {
            UD60x18 lambdaSq = lambda2.mul(lambda2);
            t2 = lambdaSq.div(two.mul(sigma2).mul(sqrtPi));
        }
        
        // Calculate cross term
        UD60x18 ct = _crossTerm(mu1, sigma1, lambda1, mu2, sigma2, lambda2, precision, sqrtPi);
        
        // L2 norm squared = t1 + t2 > ct ? (t1 + t2 - ct) : 0;
        UD60x18 normSq;
        {
            UD60x18 t1t2 = t1.add(t2);
            normSq = t1t2.gt(ct) ? t1t2.sub(ct) : ud(0);
        }
        
        // L2 norm = sqrt(normSq)
        return normSq.sqrt();
    }
    
    /**
     * @notice Calculate cross term for L2 norm between two Gaussians
     * @return Cross term value as uint256
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
        // Convert to PRB Math types
        SD59x18 mu1Fixed = sd(mu1);
        UD60x18 sigma1Fixed = ud(sigma1);
        UD60x18 lambda1Fixed = ud(lambda1);
        SD59x18 mu2Fixed = sd(mu2);
        UD60x18 sigma2Fixed = ud(sigma2);
        UD60x18 lambda2Fixed = ud(lambda2);
        UD60x18 precisionFixed = ud(precision);
        UD60x18 sqrtPiFixed = ud(sqrtPi);
        
        // Calculate cross term using fixed point
        UD60x18 result = _crossTerm(
            mu1Fixed, sigma1Fixed, lambda1Fixed,
            mu2Fixed, sigma2Fixed, lambda2Fixed,
            precisionFixed, sqrtPiFixed
        );
        
        // Convert back to uint256
        return result.unwrap();
    }
    
    /**
     * @notice Internal function to calculate cross term using fixed-point types
     */
    function _crossTerm(
        SD59x18 mu1,
        UD60x18 sigma1,
        UD60x18 lambda1,
        SD59x18 mu2,
        UD60x18 sigma2,
        UD60x18 lambda2,
        UD60x18 precision,
        UD60x18 sqrtPi
    ) internal pure returns (UD60x18) {
        // Calculate mu diff and squared in their own scope
        UD60x18 two = ud(2e18);
        UD60x18 dMuSq;
        {
            SD59x18 muDiff = mu1.sub(mu2);
            dMuSq = muDiff.mul(muDiff).intoUD60x18();
        }
        
        // Calculate variance sum in its own scope
        UD60x18 varSum;
        {
            UD60x18 sigma1Sq = sigma1.mul(sigma1);
            UD60x18 sigma2Sq = sigma2.mul(sigma2);
            varSum = sigma1Sq.add(sigma2Sq);
        }
        
        // Calculate exp value in its own scope
        UD60x18 expVal;
        {
            UD60x18 expArg = dMuSq.div(two.mul(varSum));
            expVal = expArg.exp().inv();
        }
        
        // Calculate sqrt variance sum in its own scope
        UD60x18 sqrtVarSum = varSum.mul(precision).sqrt();
        
        // Calculate lambda term in its own scope
        UD60x18 lambdaTerm;
        {
            UD60x18 lambdaProduct = lambda1.mul(lambda2);
            lambdaTerm = two.mul(lambdaProduct).mul(precision);
        }
        
        // Final calculation
        UD60x18 numerator = lambdaTerm.mul(expVal).div(sqrtPi);
        return numerator.div(sqrtVarSum.div(precision));
    }
}