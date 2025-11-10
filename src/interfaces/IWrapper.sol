// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/// @title Interface for the Wrapper contract
/// @notice Defines the minimal external functions used by KipuBankV3
interface IWrapper {
    /// @notice Simulates a swap from any token to USDC and returns the estimated USDC amount
    /// @param tokenIn The address of the token to be swapped
    /// @param amountIn The amount of tokenIn to swap
    /// @return amountOut The estimated output amount in USDC
    function previewSwapToUsdc(address tokenIn, uint256 amountIn) external view returns (uint256 amountOut);

    /// @notice Executes a swap to USDC
    /// @param tokenIn The token to swap
    /// @param amountIn The amount of tokenIn
    /// @param amountOutMin Minimum USDC amount expected
    /// @param recipient Address that will receive the USDC
    /// @return amountOut The actual USDC amount obtained
    function swapToUsdc(
        address tokenIn,
        uint256 amountIn,
        uint256 amountOutMin,
        address recipient
    ) external returns (uint256 amountOut);
}
