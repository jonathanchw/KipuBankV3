// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {MockERC20} from "./MockERC20.sol";

/// @dev Minimal mock router for testing KipuBankV3 and Wrapper.
/// - WETH() returns the stored WETH address.
/// - getAmountsOut() returns 1:1 for all hops.
/// - swapExactTokensForTokens() mints USDC 1:1 to the recipient.
/// - swapExactETHForTokens() mints USDC 1:1 to the recipient.
contract MockRouter {
    address public immutable weth;
    address public immutable usdc;

    constructor(address _weth, address _usdc) {
        weth = _weth;
        usdc = _usdc;
    }

    /// @notice Mimics UniswapV2Router02.WETH()
    function WETH() external view returns (address) {
        return weth;
    }

    /// @notice Returns a 1:1 amounts array for any path.
    function getAmountsOut(uint256 amountIn, address[] calldata path)
        external
        pure
        returns (uint256[] memory amounts)
    {
        uint256 len = path.length;
        amounts = new uint256[](len);
        for (uint256 i = 0; i < len; i++) {
            amounts[i] = amountIn;
        }
    }


}
