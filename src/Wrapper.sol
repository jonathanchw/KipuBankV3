// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC20} from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import {IUniswapV2Router02} from "v2-periphery/contracts/interfaces/IUniswapV2Router02.sol";

/**
 * @title Wrapper
 * @notice Contract that swaps any ERC20 token to USDC using Uniswap V2.
 * @dev Designed to be used externally by other contracts (e.g., KipuBankV3).
 */
contract Wrapper {
    using SafeERC20 for IERC20;

    /// @notice Thrown when an address parameter is zero.
    error ZeroAddress();

    /// @notice Thrown when an amount is zero.
    error ZeroAmount();

    /// @notice Uniswap V2 Router instance.
    IUniswapV2Router02 public immutable ROUTER;

    /// @notice USDC token address.
    address public immutable USDC;

    /// @notice Wrapped Ether (WETH) address from Uniswap router.
    address public immutable WETH;

    /**
     * @param _router The address of the Uniswap V2 router.
     * @param _usdc The address of the USDC token.
     */
    constructor(address _router, address _usdc) {
        if (_router == address(0) || _usdc == address(0)) revert ZeroAddress();
        ROUTER = IUniswapV2Router02(_router);
        USDC = _usdc;
        WETH = ROUTER.WETH();
    }

    /**
     * @notice Swaps an ERC20 token to USDC using Uniswap V2.
     * @param tokenIn The token to be swapped.
     * @param amountIn The amount of tokenIn to swap.
     * @param amountOutMin The minimum expected USDC amount.
     * @param recipient The address to receive the resulting USDC.
     * @return amountOut The amount of USDC received after swap.
     */
    function swapToUsdc(
        address tokenIn,
        uint256 amountIn,
        uint256 amountOutMin,
        address recipient
    ) external returns (uint256 amountOut) {
        if (tokenIn == address(0) || recipient == address(0)) revert ZeroAddress();
        if (amountIn == 0) revert ZeroAmount();

        // Pull tokens from the user
        IERC20(tokenIn).safeTransferFrom(msg.sender, address(this), amountIn);

        // If input token is already USDC, skip the swap
        if (tokenIn == USDC) {
            IERC20(USDC).safeTransfer(recipient, amountIn);
            return amountIn;
        }

        // Ensure allowance for Uniswap router
        if (IERC20(tokenIn).allowance(address(this), address(ROUTER)) < amountIn) {
            IERC20(tokenIn).safeIncreaseAllowance(address(ROUTER), type(uint256).max); // See this, I think Cris said something about type(uint256).max. 
        }

        // Build swap path
        address[] memory path;
        if (tokenIn == WETH) {
            path = new address[](2);
            path[0] = WETH;
            path[1] = USDC;
        } else {
            path = new address[](3);
            path[0] = tokenIn;
            path[1] = WETH;
            path[2] = USDC;
        }

        // Execute swap
        uint256[] memory amounts =
            ROUTER.swapExactTokensForTokens(amountIn, amountOutMin, path, recipient, block.timestamp);

        amountOut = amounts[amounts.length - 1];
    }

    /**
     * @notice Returns a quote for how much USDC would be received in a swap.
     * @param tokenIn The token to swap.
     * @param amountIn The amount of tokenIn to swap.
     * @return amountOut The expected USDC output.
     */
    function previewSwapToUsdc(address tokenIn, uint256 amountIn) external view returns (uint256 amountOut) {
        if (tokenIn == address(0)) revert ZeroAddress();
        if (amountIn == 0) revert ZeroAmount();

        if (tokenIn == USDC) {
            return amountIn;
        }

        address[] memory path;
        if (tokenIn == WETH) {
            path = new address[](2) ;
            path[0] = WETH;
            path[1] = USDC;
        } else {
            path = new address[](3) ;
            path[0] = tokenIn;
            path[1] = WETH;
            path[2] = USDC;
        }

        uint256[] memory amounts = ROUTER.getAmountsOut(amountIn, path);
        amountOut = amounts[amounts.length - 1];
    }
}
