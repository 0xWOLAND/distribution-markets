// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;
import { UD60x18, ud } from "@prb-math-4.1.0/src/UD60x18.sol";
import { SD59x18, sd } from "@prb-math-4.1.0/src/SD59x18.sol";

library Math {
    /**
     * @notice Evaluate the Gaussian distribution at a given point
     * @param x The point to evaluate the Gaussian at
     * @param mu The mean of the Gaussian
     * @param sigma The standard deviation of the Gaussian
     * @param lambda The lambda of the Gaussian
     */
    function evaluate(int256 x, int256 mu, uint256 sigma, uint256 lambda) internal pure returns (uint256) {
        if (sigma == 0 || lambda == 0) return 0;

        SD59x18 xFixed = sd(x);
        SD59x18 muFixed = sd(mu);
        UD60x18 sigmaFixed = ud(sigma);
        UD60x18 lambdaFixed = ud(lambda);
        
        UD60x18 result = _evaluate(xFixed, muFixed, sigmaFixed, lambdaFixed);
        return result.unwrap();
    }
    
    function _evaluate(SD59x18 x, SD59x18 mu, UD60x18 sigma, UD60x18 lambda) internal pure returns (UD60x18) {
        SD59x18 xDiff = x.sub(mu);
        UD60x18 deltaSquared = xDiff.mul(xDiff).intoUD60x18();
        UD60x18 sigmaSquared = sigma.mul(sigma);
        UD60x18 denominator = sigmaSquared.mul(ud(2e18));

        // If exponent would be too large, return 0 (Gaussian tail is negligible)
        if (deltaSquared.div(denominator) > ud(133e18)) {
            return ud(0);
        }

        UD60x18 exponent = deltaSquared.div(denominator); // (x - mu)^2 / (2 * sigma^2)
        UD60x18 gaussian = ud(1e18).div(exponent.exp()); // e^(-exponent)
        UD60x18 normalization = lambda.mul(ud(398942280401432677)).div(sigma); // (λ * (1 / sqrt(2π))) / σ
        return normalization.mul(gaussian);
    }
    
    function difference(
        int256 x, int256 mu1, uint256 sigma1, uint256 lambda1,
        int256 mu2, uint256 sigma2, uint256 lambda2
    ) internal pure returns (int256) {
        SD59x18 xFixed = sd(x);
        SD59x18 mu1Fixed = sd(mu1);
        UD60x18 sigma1Fixed = ud(sigma1);
        UD60x18 lambda1Fixed = ud(lambda1);
        SD59x18 mu2Fixed = sd(mu2);
        UD60x18 sigma2Fixed = ud(sigma2);
        UD60x18 lambda2Fixed = ud(lambda2);
        
        UD60x18 f = _evaluate(xFixed, mu1Fixed, sigma1Fixed, lambda1Fixed);
        UD60x18 g = _evaluate(xFixed, mu2Fixed, sigma2Fixed, lambda2Fixed);
        
        if (f.gte(g)) {
            return int256(f.sub(g).unwrap());
        } else {
            return -int256(g.sub(f).unwrap());
        }
    }

    function klDivergence(
        int256 mu1, uint256 sigma1, uint256 lambda1,
        int256 mu2, uint256 sigma2, uint256 lambda2
    ) internal pure returns (uint256) {
        if (sigma1 == 0 || sigma2 == 0 || lambda1 == 0 || lambda2 == 0) return 0;

        SD59x18 mu1Fixed = sd(mu1);
        UD60x18 sigma1Fixed = ud(sigma1);
        SD59x18 mu2Fixed = sd(mu2);
        UD60x18 sigma2Fixed = ud(sigma2);

        UD60x18 kl = _klDivergence(mu1Fixed, sigma1Fixed, mu2Fixed, sigma2Fixed);
        return kl.unwrap();
    }

    function _klDivergence(
        SD59x18 mu1, UD60x18 sigma1,
        SD59x18 mu2, UD60x18 sigma2
    ) internal pure returns (UD60x18 dkl) {
        UD60x18 term1 = sigma2.div(sigma1).ln();
        UD60x18 sigma1Squared = sigma1.mul(sigma1);
        UD60x18 sigma2Squared = sigma2.mul(sigma2);
        SD59x18 muDiff = mu1.sub(mu2);
        UD60x18 muDiffSquared = muDiff.mul(muDiff).intoUD60x18();
        UD60x18 numerator = sigma1Squared.add(muDiffSquared);
        UD60x18 term2 = numerator.div(sigma2Squared.mul(ud(2e18)));
        UD60x18 term3 = ud(0.5e18);
        dkl = term1.add(term2).sub(term3);
        if (dkl.lt(ud(0))) dkl = ud(0); // Clamp negative values
    }

    function wassersteinDistance(
        int256 mu1, uint256 sigma1, uint256 lambda1,
        int256 mu2, uint256 sigma2, uint256 lambda2
    ) internal pure returns (uint256) {
        if (sigma1 == 0 || sigma2 == 0 || lambda1 == 0 || lambda2 == 0) return 0;
        
        SD59x18 mu1Fixed = sd(mu1);
        UD60x18 sigma1Fixed = ud(sigma1);
        UD60x18 lambda1Fixed = ud(lambda1);
        SD59x18 mu2Fixed = sd(mu2);
        UD60x18 sigma2Fixed = ud(sigma2);
        UD60x18 lambda2Fixed = ud(lambda2);

        UD60x18 distance = _wassersteinDistance(mu1Fixed, sigma1Fixed, lambda1Fixed, mu2Fixed, sigma2Fixed, lambda2Fixed);
        return distance.unwrap();
    }

    function _wassersteinDistance(
        SD59x18 mu1, UD60x18 sigma1, UD60x18 lambda1,
        SD59x18 mu2, UD60x18 sigma2, UD60x18 lambda2
    ) internal pure returns (UD60x18) {
        UD60x18 kld1 = _klDivergence(mu1, sigma1, mu2, sigma2);
        UD60x18 kld2 = _klDivergence(mu2, sigma2, mu1, sigma1);
        UD60x18 lambdaDiff = lambda1.gt(lambda2) ? lambda1.sub(lambda2) : lambda2.sub(lambda1);
        UD60x18 lambdaDiffSquared = lambdaDiff.mul(lambdaDiff);
        UD60x18 kldDiff = kld1.gt(kld2) ? kld1.sub(kld2) : kld2.sub(kld1);
        UD60x18 kldDiffSquared = kldDiff.mul(kldDiff);
        UD60x18 sumSquared = lambdaDiffSquared.add(kldDiffSquared);
        return sumSquared.sqrt();
    }
}