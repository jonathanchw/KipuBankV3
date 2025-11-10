// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {Wrapper} from "../src/Wrapper.sol";
import {MockERC20} from "../src/mocks/MockERC20.sol";
import {MockRouter} from "../src/mocks/MockRouter.sol";

contract WrapperTest is Test {
    Wrapper public wrapper;
    MockRouter public router;
    MockERC20 public usdc;
    MockERC20 public weth;
    MockERC20 public tokenA;

    address public user = address(0xBEEF);
    address public recipient = address(0xCAFE);

    function setUp() public {
        usdc = new MockERC20("USD Coin", "USDC");
        weth = new MockERC20("Wrapped Ether", "WETH");
        tokenA = new MockERC20("TokenA", "TKA");

        router = new MockRouter(address(weth), address(usdc));
        wrapper = new Wrapper(address(router), address(usdc));

        tokenA.mint(user, 1_000 ether);
        usdc.mint(user, 1_000 ether);

        vm.startPrank(user);
        tokenA.approve(address(wrapper), type(uint256).max);
        usdc.approve(address(wrapper), type(uint256).max);
        vm.stopPrank();
    }

    function testPreviewSwapUSDCReturnsSameAmount() public {
        uint256 quote = wrapper.previewSwapToUsdc(address(usdc), 123e18);
        assertEq(quote, 123e18);
    }

    function testPreviewSwapOtherTokenUsesRouter() public {
        uint256 amountIn = 10 ether;
        uint256 quote = wrapper.previewSwapToUsdc(address(tokenA), amountIn);
        // MockRouter getAmountsOut returns 1:1
        assertEq(quote, amountIn);
    }

    function testSwapToUsdcWhenInputIsUSDCJustTransfers() public {
        uint256 amountIn = 50 ether;

        vm.startPrank(user);
        wrapper.swapToUsdc(address(usdc), amountIn, 0, recipient);
        vm.stopPrank();

        assertEq(usdc.balanceOf(recipient), amountIn);
    }

    function testSwapToUsdcFromOtherTokenMintsUSDC() public {
        uint256 amountIn = 25 ether;

        vm.startPrank(user);
        wrapper.swapToUsdc(address(tokenA), amountIn, 1, recipient);
        vm.stopPrank();

        // MockRouter mints USDC 1:1
        assertEq(usdc.balanceOf(recipient), amountIn);
    }
}
