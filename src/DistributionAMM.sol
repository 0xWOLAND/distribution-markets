// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "@prb-math-4.1.0/src/Common.sol";
import "./Math.sol";

contract DistributionAMM {
    using Math for *;

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

    address public owner;
    bool public isResolved;
    int256 public outcome;

    function initialize(
        uint256 _k,
        uint256 _b,
        uint256 _kToBRatio,
        uint256 _sigma,
        uint256 _lambda,
        int256 _mu,
        uint256 _minSigma
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

        owner = msg.sender;
        isResolved = false;
        outcome = 0;
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
        
        if (totalShares == 0) {
            shares = amount;
        } else {
            shares = y * totalShares;
        }

        b = _b;
        k = _k;

        lpShares[msg.sender] += shares;
        totalShares += shares;

        positionId = positionNFT.mintLPPosition(msg.sender, amount, mu, sigma, y * lambda);
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
        uint256 oldLambda,
        int256 newMu,
        uint256 newSigma,
        uint256 newLambda,
        int256 criticalPoint
    ) public pure returns (uint256 amount) {
        // Calculate old Gaussian at critical point
        uint256 f = Math.evaluate(criticalPoint, oldMu, oldSigma, oldLambda);
        
        // Calculate new Gaussian at critical point
        uint256 g = Math.evaluate(criticalPoint, newMu, newSigma, newLambda);
        
        // Return the maximum possible loss
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
    function trade(uint256 amount, int256 newMu, uint256 newSigma, uint256 newLambda, int256 criticalPoint) external returns (uint256 positionId) {
        uint256 l2 = newLambda * sqrt(1/(2 * newSigma * SQRT_2PI));
        require(l2 == k, "L2 norm does not match k");

        uint256 backing = k / (newSigma * SQRT_PI);
        require(backing <= b, "backing is greater than b");

        uint256 requiredCollateral = getRequiredCollateral(mu, sigma, lambda, newMu, newSigma, newLambda, criticalPoint);
        require(amount >= requiredCollateral, "amount must be greater than required collateral");

        uint256 fee = calculateFee(mu, sigma, lambda, newMu, newSigma, newLambda);
        amount -= fee;

        b += amount;
        k = kToBRatio * b;

        positionId = positionNFT.mint(msg.sender, amount, mu, sigma, lambda, newMu, newSigma, newLambda);
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
        uint256 newLambda
    ) public pure returns (uint256 feeAmount) {
        // Use the l2Norm function from Math library
        uint256 l2Norm = Math.l2Norm(
            oldMu, 
            oldSigma, 
            oldLambda, 
            newMu, 
            newSigma, 
            newLambda,
            PRECISION,
            SQRT_PI
        );
        
        // Fee = l2Norm * FEE_RATE
        feeAmount = (l2Norm * FEE_RATE) / (PRECISION * PRECISION);
    }

    /**
     * @notice Resolve market with final outcome
     * @param _outcome Final value of measured variable
     *
     * Should have timelocked dispute period
     */
    function resolve(int256 _outcome) external {
        require(msg.sender == owner, "only owner can resolve");
        require(!isResolved, "market already resolved");

        isResolved = true;
        outcome = _outcome;
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
        require(isResolved, "market not resolved");

        int256 _amount = int256(amount);
        int256 payout = positionNFT.calculatePayout(positionId, outcome);
        int256 capped_payout = payout > int256(b) ? int256(b) : payout;
        assert(capped_payout > _amount);

        positionNFT.withdraw(positionId, _amount);
        b -= uint256(capped_payout);
    }
}

contract PositionNFT {
    using Math for *;
    
    struct Position {
        address owner;
        uint256 collateral;
        int256 initialMu;
        uint256 initialSigma;
        uint256 initialLambda;
        int256 targetMu;
        uint256 targetSigma;
        uint256 targetLambda;
    }

    uint256 private nextTokenId;

    mapping(uint256 => Position) public positions;
    mapping(uint256 => address) private _owners;

    event Transfer(address indexed from, address indexed to, uint256 indexed tokenId);
    event Mint(address indexed to, uint256 indexed tokenId, uint256 collateral, int256 initialMu, uint256 initialSigma, uint256 initialLambda, int256 targetMu, uint256 targetSigma, uint256 targetLambda);

    // mint function unchanged
    function mint(address to, uint256 collateral, int256 initialMu, uint256 initialSigma, uint256 initialLambda, int256 targetMu, uint256 targetSigma, uint256 targetLambda) external returns (uint256 tokenId) {
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

        emit Mint(to, tokenId, collateral, initialMu, initialSigma, initialLambda, targetMu, targetSigma, targetLambda);
        emit Transfer(address(0), to, tokenId);
    }

    // mintLPPosition function unchanged
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
            targetMu: 0,
            targetSigma: 0,
            targetLambda: 0
        });
        _owners[tokenId] = to;

        emit Mint(to, tokenId, collateral, mu, sigma, lambda, 0, 0, 0);
        emit Transfer(address(0), to, tokenId);
    }


    
    
    
    /**
     * @notice Calculate position payout for given outcome
     */
    function calculatePayout(
        uint256 tokenId, 
        int256 outcome
    ) external view returns (int256 amount) {
        Position storage position = positions[tokenId];
        
        // Check if this is an LP position (targetLambda == 0)
        if (position.targetLambda == 0) {
            // For LP positions, we only need to compute the negative of initialGaussian
            return -int256(Math.evaluate(
                outcome,
                position.initialMu,
                position.initialSigma,
                position.initialLambda
            ));
        }
        
        // For regular positions, use the diff function
        return Math.difference(
            outcome,
            position.initialMu,
            position.initialSigma,
            position.initialLambda,
            position.targetMu,
            position.targetSigma,
            position.targetLambda
        );
    }

    /**
     * @notice Set collateral for a position
     * @param tokenId ID of the position
     * @param amount Amount of collateral to set
     */
    function withdraw(uint256 tokenId, int256 amount) external {
        uint256 collateral = amount > 0 ? uint256(amount) : uint256(-amount);
        require(positions[tokenId].collateral >= collateral, "insufficient collateral");
        positions[tokenId].collateral -= collateral;
    }
}