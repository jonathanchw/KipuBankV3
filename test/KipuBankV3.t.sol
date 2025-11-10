// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {KipuBankV3} from "../src/KipuBankV3.sol";
import {Wrapper} from "../src/Wrapper.sol";
import {MockERC20} from "../src/mocks/MockERC20.sol";
import {MockRouter} from "../src/mocks/MockRouter.sol";

contract KipuBankV3Test is Test {
    KipuBankV3 public bank;
    Wrapper public wrapper;
    MockRouter public router;
    MockERC20 public usdc;
    MockERC20 public weth;
    MockERC20 public tokenA;

    address public admin = address(this);
    address public user = address(0x1234);

    uint256 public constant INITIAL_CAP = 1_000_000 ether;

    function setUp() public {
        // Deploy mock tokens
        usdc = new MockERC20("USD Coin", "USDC");
        weth = new MockERC20("Wrapped Ether", "WETH");
        tokenA = new MockERC20("TokenA", "TKA");

        // Deploy mock router
        router = new MockRouter(address(weth), address(usdc));

        // Deploy wrapper
        wrapper = new Wrapper(address(address(router)), address(usdc));

        // Deploy bank with big cap
        bank = new KipuBankV3(
            address(router),
            address(usdc),
            INITIAL_CAP,
            admin
        );

        // Link wrapper
        bank.setWrapper(address(wrapper));

        // Mint tokens to user
        usdc.mint(user, 1_000_000 ether);
        tokenA.mint(user, 1_000_000 ether);

        // Give user ETH
        vm.deal(user, 1_000 ether);

        // User approves bank & wrapper
        vm.startPrank(user);
        usdc.approve(address(bank), type(uint256).max);
        tokenA.approve(address(bank), type(uint256).max);
        tokenA.approve(address(wrapper), type(uint256).max);
        vm.stopPrank();
    }

    function testDepositUSDCIncreasesBalanceAndTotal() public {
        uint256 amount = 100 ether;

        vm.startPrank(user);
        bank.deposit(address(usdc), amount, 0);
        vm.stopPrank();

        uint256 bal = bank.getUSDCBalance(user);
        assertEq(bal, amount);
        assertEq(bank.s_totalDepositedUSDC(), amount);
        assertEq(bank.s_totalDepositsCount(), 1);
    }

    function testDepositERC20SwapsToUSDC() public {
        uint256 amount = 50 ether;

        vm.startPrank(user);
        // _minOutUSDC = 1 to avoid slippage issues in mock
        bank.deposit(address(tokenA), amount, 1);
        vm.stopPrank();

        uint256 bal = bank.getUSDCBalance(user);
        // MockRouter mints 1:1 USDC
        assertEq(bal, amount);
        assertEq(bank.s_totalDepositedUSDC(), amount);
    }

    function testDepositETHSwapsToUSDC() public {
        uint256 amount = 1 ether;

        vm.startPrank(user);
        bank.deposit{value: amount}(address(0), amount, 1);
        vm.stopPrank();

        uint256 bal = bank.getUSDCBalance(user);
        // MockRouter mints 1:1 USDC
        assertEq(bal, amount);
        assertEq(bank.s_totalDepositedUSDC(), amount);
    }

    function testDepositRevertsWhenCapExceeded() public {
        // set small cap via admin
        bank.setBankCapUSDC(10 ether);

        vm.startPrank(user);
        vm.expectRevert(KipuBankV3.DepositWouldExceedCap.selector);
        bank.deposit(address(usdc), 20 ether, 0);
        vm.stopPrank();
    }

    function testWithdrawUSDCWorks() public {
        uint256 amount = 100 ether;

        // deposit first
        vm.startPrank(user);
        bank.deposit(address(usdc), amount, 0);
        vm.stopPrank();

        // set a high withdrawal limit
        bank.setWithdrawalLimitUSDC(type(uint256).max);

        vm.startPrank(user);
        bank.withdrawUSDC(40 ether);
        vm.stopPrank();

        uint256 bal = bank.getUSDCBalance(user);
        assertEq(bal, 60 ether);
        assertEq(bank.s_totalDepositedUSDC(), 60 ether);
        assertEq(bank.s_totalWithdrawalsCount(), 1);
    }

    function testWithdrawRevertsInsufficientBalance() public {
        vm.startPrank(user);
        vm.expectRevert(KipuBankV3.InsufficientBalance.selector);
        bank.withdrawUSDC(1 ether);
        vm.stopPrank();
    }

    function testWithdrawRevertsWhenOverLimit() public {
        uint256 amount = 100 ether;

        vm.startPrank(user);
        bank.deposit(address(usdc), amount, 0);
        vm.stopPrank();

        // set small limit
        bank.setWithdrawalLimitUSDC(10 ether);

        vm.startPrank(user);
        vm.expectRevert(KipuBankV3.WithdrawalLimitExceeded.selector);
        bank.withdrawUSDC(50 ether);
        vm.stopPrank();
    }

    function testOnlyAdminCanSetWrapper() public {
        address attacker = address(0x999);

        vm.prank(attacker);
        vm.expectRevert(); // AccessControl revert
        bank.setWrapper(attacker);
    }

    function testReceiveReverts() public {
        vm.deal(user, 1 ether);
        vm.prank(user);

        (bool ok, ) = address(bank).call{value: 1 ether}("");
        assertFalse(ok);
    }

    function testDepositZeroAmountReverts() public {
        vm.startPrank(user);
        vm.expectRevert(KipuBankV3.ZeroAmount.selector);
        bank.deposit(address(usdc), 0, 0);
        vm.stopPrank();
    }
}
