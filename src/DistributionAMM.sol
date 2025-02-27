// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "dependencies/@prb-math-4.1.0/src/Common.sol";

contract DistributionAMM {
    uint256 public k;
    uint256 public b;
    uint256 public kToBRatio;
    uint256 public sigma;
    uint256 public lambda;
    int256 public mu;
    uint256 public minSigma;

    uint256 constant PRECISION = 1e18;
    uint256 constant SQRT_2 = 14142135623730950488;
    uint256 constant SQRT_PI = 17724538509055160272;
    uint256 constant SQRT_2PI = 2506628274631000896;
    uint256 constant FEE_RATE = 1e16;

    uint256 public totalShares;
    mapping(address => uint256) public lpShares;

    PositionNFT public positionNFT;

    function initialize(
        uint256 _k,
        uint256 _b,
        uint256 _kToBRatio,
        uint256 _sigma,
        uint256 _lambda,
        int256 _mu,
        uint256 _minSigma,
    ) external {

        uint256 sqrt_factor = sqrt(1/(_sigma * SQRT_2PI));
        uint256 l2 = sqrt_factor / SQRT_2;
        uint256 max_f = _k * sqrt_factor;

        require(l2 == _k, "L2 norm does not match k");
        require(max_f <= _b, "max_f is greater than b");

        k = _k;
        b = _b;
        kToBRatio = _kToBRatio;
        sigma = _sigma;
        lambda = _lambda;
        mu = _mu;
        minSigma = _minSigma;

        lpShares[msg.sender] = 1e18;
        totalShares = 1e18;
    }

      /**
     * @notice Adds liquidity to the pool
     * @param amount Amount of collateral to add (y * b)
     * @return shares LP tokens minted
     * @return positionId NFT representing market position component
     * 
     * **Mathematical Explanation:**
     * 
     * - **Initial State:**
     *   - The pool is initially backed by `b` collateral.
     *   - The pool holds a market position defined by `h = b - λf`, where:
     *     - `λ` (lambda) is the scale factor.
     *     - `f` is the Gaussian function representing the market position.
     * 
     * - **Liquidity Addition:**
     *   1. **Collateral Contribution:**
     *      - The Liquidity Provider (LP) adds `amount = y * b` collateral, where:
     *        - `y = amount / b` represents the proportion of the **existing** pool's collateral being added.
     *        - `b` is the current total collateral in the pool **before** the addition.
     * 
     *   2. **LP Receives:**
     *      - **LP Shares:** Representing a proportion of the pool based on the added collateral.
     *      - **Position NFT:** Representing `y * (λf)`, the scaled current market position.
     *      Note: these should add up to a flat payout of yb at the time of return.
     * 
     * - **Resulting State:**
     *   - **New Collateral (`b_new`):**
     *     - `b_new = b + y * b = b * (1 + y)`
     * 
     *   - **LP Ownership Proportion (`p`):**
     *     - The LP's ownership proportion of the pool after addition is:
     *       ```
     *       p = (y * b) / (b * (1 + y)) = y / (1 + y)
     *       ```
     *     - **Note:** `y` is the proportion of the existing pool's collateral being added, not the final ownership proportion.
     * 
     *   - **Components Received:**
     *     - **LP Shares:** Equivalent to `p` proportion of the new pool.
     *     - **Position NFT:** Represents `y * (λf)`, maintaining the scaled market position.
     * 
     * - **Impact:**
     *   - **Collateral (`b`):** Increases to `b_new = b * (1 + y)`
     *   - **L2 Norm Constraint (`k`):** Increases proportionally according to `kToBRatio`.
     *   - **Market Position (`h`):**
     *     - Maintains proportionality with the new collateral.
     *     - Adjusted based on the added liquidity and existing market dynamics.
     */
    function addLiquidity(uint256 amount) external returns (uint256 shares, uint256 positionId) {
        require(amount % b == 0, "amount must be a multiple of b");

        uint256 y = amount / b;
        uint256 _b = b * (1 + y);
        uint256 _k = kToBRatio * _b;
        
        // p = y / (1 + y)
        // shares = (p * totalShares) / (1 - p)
        // ==> shares = ((y / (1 + y)) * totalShares) / (1 - (y / (1 + y)))
        // ==> shares = (y * totalShares) / ((1 + y) - y)
        // ==> shares = (y * totalShares) / (1)
        // ==> shares = y * totalShares

        if (totalShares == 0) {
            shares = amount;
        } else {
            shares = y * totalShares;
        }

        k = _k;
        b = _b;

        // sender gets p shares of the new pool
        lpShares[msg.sender] += shares;
        totalShares += shares;

        positionNFT.mintLPPosition(msg.sender, amount, mu, sigma, lambda);
    }

    /**
     * @notice Removes liquidity from the pool
     * @param shares Amount of LP shares to burn
     * @return amount Collateral returned
     * 
     * **Mathematical Explanation:**
     * - LP must burn both their LP shares
     * - Amount returned is proportional to shares burned relative to total supply.
     * - The position NFT ensures the LP exits with their proportion of both the
     *   collateral and market position components, maintaining market pricing.
     */
    function removeLiquidity(uint256 shares) external returns (uint256 amount) {
        require(shares > 0, "shares must be greater than 0");
        require(shares <= lpShares[msg.sender], "shares must be less than or equal to LP shares");
        require(totalShares > shares, "shares must be less than total shares");

        amount = (shares * b) / totalShares;

        lpShares[msg.sender] -= shares;
        totalShares -= shares;
        b -= amount;
        k = kToBRatio * b;

        // transfer `amount` collateral to msg.sender
    }


     /**
     * @notice Calculate required collateral for a trade
     * @param oldMu Current market mean
     * @param oldSigma Current market std dev
     * @param oldLambda Current market scale
     * @param newMu Desired new mean
     * @param newSigma Desired new std dev
     * @param newLambda Desired new scale
     * @param criticalPoint The x-value of the local minimum to check for max loss
     * @return amount Required collateral including fees
     *
     * Helper function to compute required collateral for trade.
     * Calculates the maximum possible loss at the provided critical point,
     * which represents the local minimum where maximum loss occurs.
     * Includes fee calculation in returned amount.
     */
    function getRequiredCollateral(
        int256 oldMu,
        uint256 oldSigma,
        uint256 oldLam,
        int256 newMu,
        uint256 newSigma,
        uint256 newLam,
        int256 crit
    ) external pure returns (uint256 amount) {
        // Distance squared: (x - μ)^2
        uint256 dOld2 = uint256((crit - oldMu) * (crit - oldMu));
        uint256 dNew2 = uint256((crit - newMu) * (crit - newMu));

        // Compute σ^2 once, use for denom and norm
        uint256 sOld2 = oldSigma * oldSigma / PRECISION;
        uint256 sNew2 = newSigma * newSigma / PRECISION;

        // Exponent: -((x - μ)^2 / (2 * σ^2)), unscaled
        uint256 expOld = dOld2 / (2 * sOld2);
        uint256 expNew = dNew2 / (2 * sNew2);

        // Approximate exp(-x) as 1 - x, cap at 0, scaled later
        uint256 eOld = expOld < PRECISION ? PRECISION - expOld : 0;
        uint256 eNew = expNew < PRECISION ? PRECISION - expNew : 0;

        // Combined coefficient: λ / (σ * sqrt(2π))
        uint256 cOld = oldLam * PRECISION / (oldSigma * SQRT_2PI);
        uint256 cNew = newLam * PRECISION / (newSigma * SQRT_2PI);

        // f(x) and g(x) in one step
        uint256 f = cOld * eOld / PRECISION;
        uint256 g = cNew * eNew / PRECISION;

        amount = g < f ? f - g : 0;
    }

  /**
     * @notice Execute a trade to move the market gaussian
     * @param amount Collateral provided (includes required fees in cash)
     * @param newMu New mean to move market to
     * @param newSigma New standard deviation
     * @param newLambda New scale factor
     * @param criticalPoint The x-value of the local minimum on the opposite side
     *                     of the negative distribution's mean from the positive
     *                     distribution's mean (e.g., for ap - bq where p is centered
     *                     at 0 and q at 1, this would be the local min above 1)
     * @return positionId ID of minted position NFT
     *
     * Core trading function. Verifies:
     * 1. L2 norm constraint maintained (using closed form for gaussians)
     * 2. Provided collateral covers maximum possible loss (found at criticalPoint)
     * 3. Fees are paid in cash and added to b, with k updated proportionally
     *
     * Position NFT represents: new_gaussian - old_gaussian
     * The position must be collateralized by the maximum possible loss,
     * which occurs at the critical point. Frontend should aggregate positions
     * across all NFTs in user's wallet for clear position display.
     */
    function trade(uint256 amount, int256 _mu, uint256 _sigma, uint256 _lambda, int256 criticalPoint) external returns (uint256 positionId) {
        uint256 l2 = _lambda * sqrt(1/(2 * _sigma * SQRT_2PI));
        require(l2 == k, "L2 norm does not match k");

        uint256 backing = k / (_sigma * SQRT_PI);
        require(backing <= b, "backing is greater than b");

        uint256 requiredCollateral = getRequiredCollateral(mu, sigma, lambda, _mu, _sigma, _lambda, criticalPoint);
        require(amount >= requiredCollateral, "amount must be greater than required collateral");

        uint256 fee = calculateFee(mu, sigma, lambda, _mu, _sigma, _lambda);
        amount -= fee;

        b += amount;
        k = kToBRatio * b;

        positionNFT.mint(msg.sender, amount, mu, sigma, lambda, _mu, _sigma, _lambda);
    }

       /**
     * @notice Calculate fee for a proposed trade
     * @param oldMu Current market mean
     * @param oldSigma Current market std dev
     * @param oldLambda Current market scale
     * @param newMu Desired new mean
     * @param newSigma Desired new std dev
     * @param newLambda Desired new scale
     * @return feeAmount The fee required for the trade
     *
     * Helper function to compute the fee for a trade based on the
     * market parameters. Uses the stored fee rate (in basis points)
     * and the size of the position change.
     */
    function calculateFee(
        int256 oldMu,
        uint256 oldSigma,
        uint256 oldLambda,
        int256 newMu,
        uint256 newSigma,
        uint256 newLambda,
    ) external view returns (uint256 feeAmount) {
        uint256 term1 = (oldLambda * oldLambda * PRECISION) / (2 * oldSigma * SQRT_PI);
        uint256 term2 = (newLambda * newLambda * PRECISION) / (2 * newSigma * SQRT_PI);

        // Cross term: -2 * lambda_f * lambda_g * exp(-deltaMu^2 / (2 * (sigma_f^2 + sigma_g^2))) / sqrt(sigma_f^2 + sigma_g^2)
        int256 deltaMu = newMu - oldMu;
        uint256 deltaMuSquared = uint256(deltaMu * deltaMu);
        uint256 varianceSum = (oldSigma * oldSigma) + (newSigma * newSigma);
        uint256 expArg = (deltaMuSquared * PRECISION) / (2 * varianceSum);
        uint256 expResult = exp(expArg); // Assuming exp returns 1e18 scaled result

        uint256 sqrtVarianceSum = sqrt(varianceSum * PRECISION); // Scale up for precision
        uint256 crossTermNumerator = (2 * oldLambda * newLambda * expResult * PRECISION) / SQRT_PI;
        uint256 crossTerm = crossTermNumerator / (sqrtVarianceSum / PRECISION);

        // l2 norm squared = term1 + term2 - crossTerm
        uint256 l2Squared = term1 + term2 > crossTerm ? (term1 + term2 - crossTerm) : 0;

        // l2 norm = sqrt(l2Squared)
        uint256 l2Norm = sqrt(l2Squared * PRECISION); // Scale up for precision

        // Fee = l2Norm * FEE_RATE
        feeAmount = (l2Norm * FEE_RATE) / (PRECISION * PRECISION);
    }

    /**
     * @notice Withdraw winnings from position
     * @param positionId NFT token ID
     * @param amount Amount to withdraw
     *
     * Calculates payout based on stored parameters:
     * payout = constant_line - old_gaussian + new_gaussian
     * evaluated at outcome point. Tracks partial withdrawals.
     */
    function withdraw(uint256 positionId, uint256 amount) external {
        Position position = positionNFT.positions(positionId);
        require(position.owner == msg.sender, "only owner can withdraw");

        uint256 payout = amount * (PRECISION * PRECISION) / (position.collateral * FEE_RATE);
    }
}

contract PositionNFT {
    struct Position {
        address owner;
        uint256 collateral;
        int256 initialMu;
        uint256 initialSigma;
        uint256 initialLambda;
        uint256 targetMu;
        uint256 targetSigma;
        uint256 targetLambda;
    }

    uint256 private nextTokenId;

    mapping(uint256 => Position) public positions;
    mapping(uint256 => address) private _owners;

    event Transfer(address indexed from, address indexed to, uint256 indexed tokenId);
    event Mint(address indexed to, uint256 indexed tokenId, uint256 collateral, int256 initialMu, uint256 initialSigma, uint256 initialLambda, uint256 targetMu, uint256 targetSigma, uint256 targetLambda);

    function mint(address to, uint256 collateral, int256 initialMu, uint256 initialSigma, uint256 initialLambda, uint256 targetMu, uint256 targetSigma, uint256 targetLambda) external returns (uint256 tokenId) {
        tokenId = nextTokenId++;
        positions[tokenId] = Position({
            owner: to,
            collateral: collateral,
            initialMu: initialMu,
            initialSigma: initialSigma,
            initialLambda: initialLambda,
            targetMu: targetMu,
            targetSigma: targetSigma,
            targetLambda: targetLambda
        });
        _owners[tokenId] = to;

        emit Mint(to, tokenId, collateral);
        emit Transfer(address(0), to, tokenId);
    }

        /**
     * @notice Mint new position NFT for LP position
     * @param to Address to mint to
     * @param collateral Amount of collateral backing the position
     * @param mu Mean of the gaussian to subtract from flat line
     * @param sigma Standard deviation of the gaussian
     * @param lambda Scale factor of the gaussian
     * @return tokenId ID of new NFT
     *
     * Only callable by AMM contract. Creates a position representing:
     * constant_line - lambda * gaussian(mu, sigma)
     */
    function mintLPPosition(
        address to,
        uint256 collateral,
        int256 mu,
        uint256 sigma,
        uint256 lambda
    ) external returns (uint256 tokenId) {
        tokenId = nextTokenId++;
        positions[tokenId] = Position({
            owner: to,
            collateral: collateral,
            initialMu: mu,
            initialSigma: sigma,
            initialLambda: lambda,
            targetMu: 0,         // No target transition for LP position
            targetSigma: 0,
            targetLambda: 0
        });
        _owners[tokenId] = to;

        emit Mint(to, tokenId, collateral, mu, sigma, lambda, 0, 0, 0);
        emit Transfer(address(0), to, tokenId);
    }

}
