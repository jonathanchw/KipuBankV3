// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC20} from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import {AccessControl} from "openzeppelin-contracts/contracts/access/AccessControl.sol";
import {ReentrancyGuard} from "openzeppelin-contracts/contracts/utils/ReentrancyGuard.sol";

import {IUniswapV2Router02} from "v2-periphery/contracts/interfaces/IUniswapV2Router02.sol";
import {IWrapper} from "./interfaces/IWrapper.sol";

/**
 * @title KipuBankV3
 * @notice DeFi bank that accepts ETH, USDC and any ERC20 token with a pair on Uniswap V2,
 *         swaps everything to USDC and keeps internal accounting in USDC.
 *
 * @dev
 * - Integrates Uniswap V2 via router and Wrapper (for preview).
 * - Applies a global bankCap in USDC units (6 decimals).
 * - Preserves the concept of deposits, withdrawals and role control from KipuBankV2.
 */
contract KipuBankV3 is AccessControl, ReentrancyGuard {
    using SafeERC20 for IERC20;

    /*////////////////////////////////////////////////////////////
                          ROLES & CONSTANTS
    ////////////////////////////////////////////////////////////*/

    bytes32 public constant OPERATOR_ROLE = keccak256("OPERATOR_ROLE");

    /// @notice USDC decimals (assumed 6)
    uint8 public constant USDC_DECIMALS = 6;

    /*////////////////////////////////////////////////////////////
                             IMMUTABLES
    ////////////////////////////////////////////////////////////*/

    /// @notice Uniswap V2 Router contract for token swaps
    IUniswapV2Router02 public immutable i_router;
    
    /// @notice USDC token address (6 decimals)
    address public immutable i_usdc;
    
    /// @notice Wrapped ETH (WETH) token address
    address public immutable i_weth;

    /*////////////////////////////////////////////////////////////
                               STATE
    ////////////////////////////////////////////////////////////*/

    /// @notice Global bankCap in USDC units (6 decimals)
    uint256 public s_bankCapUSDC;

    /// @notice Total deposited in the bank, expressed in USDC (6 decimals)
    uint256 public s_totalDepositedUSDC;

    /// @notice Internal user balances in USDC
    /// uses nested mapping for backward compatibility with previous design
    mapping(address => mapping(address => uint256)) private s_balances;

    /// @notice Withdrawal limit per transaction (per token). Uses i_usdc as key.
    mapping(address => uint256) public s_withdrawalLimitUSDC;

    /// @notice External Wrapper contract for preview (and potentially swaps)
    IWrapper public wrapper;

    /// @notice Total number of successful deposits.
    uint256 public s_totalDepositsCount;

    /// @notice Total number of successful withdrawals.
    uint256 public s_totalWithdrawalsCount;

    /*////////////////////////////////////////////////////////////
                               EVENTS
    ////////////////////////////////////////////////////////////*/

    /// @notice Emitted when a user deposits USDC directly.
    /// @param user The address of the user making the deposit
    /// @param usdcAmount The amount of USDC deposited
    event DepositUSDC(address indexed user, uint256 usdcAmount);
    
    /// @notice Emitted when a user deposits a token that is converted to USDC.
    /// @param user The address of the user making the deposit
    /// @param fromToken The address of the token being deposited (address(0) for ETH)
    /// @param fromAmount The amount of the original token deposited
    /// @param usdcAmount The amount of USDC received after conversion
    event DepositConvertedToUSDC(
        address indexed user,
        address indexed fromToken,
        uint256 fromAmount,
        uint256 usdcAmount
    );
    
    /// @notice Emitted when a user withdraws USDC from the bank.
    /// @param user The address of the user making the withdrawal
    /// @param usdcAmount The amount of USDC withdrawn
    event WithdrawUSDC(address indexed user, uint256 usdcAmount);
    
    /// @notice Emitted when the bank cap is updated.
    /// @param newCapUSDC The new bank cap in USDC units
    event BankCapUpdated(uint256 newCapUSDC);
    
    /// @notice Emitted when the wrapper contract address is updated.
    /// @param newWrapper The new wrapper contract address
    event WrapperUpdated(address newWrapper);

    /*////////////////////////////////////////////////////////////
                               ERRORS
    ////////////////////////////////////////////////////////////*/

    /// @notice Thrown when the provided amount is zero.
    error ZeroAmount();

    /// @notice Thrown when a deposit would exceed the global bank cap.
    /// @param amountUSDC The amount in USDC that was attempted to deposit
    /// @param remainingUSDC The remaining capacity before reaching the bank cap
    error DepositWouldExceedCap(uint256 amountUSDC, uint256 remainingUSDC);

    /// @notice Thrown when user tries to withdraw more than their balance.
    /// @param have The current balance the user has
    /// @param want The amount the user is attempting to withdraw
    error InsufficientBalance(uint256 have, uint256 want);

    /// @notice Thrown when the per-transaction withdrawal limit is exceeded.
    /// @param amountUSDC The amount in USDC that was attempted to withdraw
    /// @param limitUSDC The maximum allowed withdrawal limit per transaction
    error WithdrawalLimitExceeded(uint256 amountUSDC, uint256 limitUSDC);

    /// @notice Thrown when a provided address is the zero address.
    error InvalidAddress();

    /// @notice Thrown when the swap path cannot be determined or would output zero USDC.
    error NoPathOrZeroOut();

    /// @notice Thrown when a swap operation via Uniswap fails.
    error SwapFailed();

    /// @notice Thrown when ETH is sent directly instead of using the deposit function.
    error DirectETHNotAllowed();

    /*////////////////////////////////////////////////////////////
                              MODIFIERS
    ////////////////////////////////////////////////////////////*/

    /// @notice Validates that the provided amount is not zero.
    /// @dev Reverts with ZeroAmount if `amount` is zero.
    /// @param amount The amount to validate
    modifier nonZeroAmount(uint256 amount) {
        if (amount == 0) revert ZeroAmount();
        _;
    }

    /// @notice Validates that the provided address is not the zero address.
    /// @dev Reverts with InvalidAddress if `addr` is the zero address.
    /// @param addr The address to validate
    modifier validAddress(address addr) {
        if (addr == address(0)) revert InvalidAddress();
        _;
    }

    /// @notice Checks that the deposit doesn't exceed bank capacity.
    /// @dev Reverts with DepositWouldExceedCap if adding the amount would exceed the bank cap.
    /// @param amountUSDC The amount in USDC to check against the bank cap
    modifier withinBankCap(uint256 amountUSDC) {
        if (s_totalDepositedUSDC + amountUSDC > s_bankCapUSDC) {
            revert DepositWouldExceedCap(amountUSDC, s_bankCapUSDC - s_totalDepositedUSDC);
        }
        _;
    }

    /*////////////////////////////////////////////////////////////
                             CONSTRUCTOR
    ////////////////////////////////////////////////////////////*/

    /**
     * @param _router Uniswap V2 router address
     * @param _usdc USDC token address (6 decimals)
     * @param _initialCapUSDC Initial bankCap in USDC units (6 decimals)
     * @param _admin Admin address that receives DEFAULT_ADMIN_ROLE and OPERATOR_ROLE
     */
    constructor(
        address _router,
        address _usdc,
        uint256 _initialCapUSDC,
        address _admin
    ) {
        if (_router == address(0) || _usdc == address(0) || _admin == address(0)) {
            revert InvalidAddress();
        }

        i_router = IUniswapV2Router02(_router);
        i_usdc = _usdc;
        i_weth = i_router.WETH();

        s_bankCapUSDC = _initialCapUSDC;

        _grantRole(DEFAULT_ADMIN_ROLE, _admin);
        _grantRole(OPERATOR_ROLE, _admin);
    }

    /*////////////////////////////////////////////////////////////
                         ADMIN / OPERATOR
    ////////////////////////////////////////////////////////////*/

    /**
     * @notice Updates the bankCap (in USDC, 6 decimals)
     * @param _newCap The new bank cap in USDC units (6 decimals)
     */
    function setBankCapUSDC(uint256 _newCap) external onlyRole(DEFAULT_ADMIN_ROLE) {
        s_bankCapUSDC = _newCap;
        emit BankCapUpdated(_newCap);
    }

    /**
     * @notice Sets the per-transaction withdrawal limit in USDC
     * @dev Uses i_usdc as the key of s_withdrawalLimitUSDC
     * @param _limit The withdrawal limit in USDC units (6 decimals)
     */
    function setWithdrawalLimitUSDC(uint256 _limit) external onlyRole(OPERATOR_ROLE) {
        s_withdrawalLimitUSDC[i_usdc] = _limit;
    }

    /**
     * @notice Updates the external Wrapper contract address
     * @param _wrapper The new wrapper contract address
     */
    function setWrapper(address _wrapper) 
        external 
        onlyRole(DEFAULT_ADMIN_ROLE) 
        validAddress(_wrapper) 
    {
        wrapper = IWrapper(_wrapper);
        emit WrapperUpdated(_wrapper);
    }

    /*////////////////////////////////////////////////////////////
                               DEPOSITS
    ////////////////////////////////////////////////////////////*/

    /**
     * @notice Deposit tokens into the bank (ETH, USDC or any ERC20 with a pair to USDC).
     * @param _token Address of the token to deposit:
     *        - address(0) for ETH
     *        - i_usdc for USDC
     *        - another ERC20 supported by Uniswap V2
     * @param _amount Amount in native units of the token
     * @param _minOutUSDC Minimum accepted USDC (to protect against slippage)
     */
    function deposit(
        address _token,
        uint256 _amount,
        uint256 _minOutUSDC
    ) external payable nonReentrant nonZeroAmount(_amount) {
        // 1) Direct deposit of USDC (no swap)
        if (_token == i_usdc) {
            IERC20(i_usdc).safeTransferFrom(msg.sender, address(this), _amount);

            if (s_totalDepositedUSDC + _amount > s_bankCapUSDC) {
                revert DepositWouldExceedCap(_amount, s_bankCapUSDC - s_totalDepositedUSDC);
            }

            unchecked {
                s_balances[msg.sender][i_usdc] += _amount;
                s_totalDepositedUSDC += _amount;
                ++s_totalDepositsCount;
            }

            emit DepositUSDC(msg.sender, _amount);
            return;
        }

        // 2) Deposit of ETH (token == address(0))
        if (_token == address(0)) {
            if (msg.value != _amount) revert ZeroAmount();

            address[] memory path1;
            path1 = new address[](2);
            path1[0] = i_weth;
            path1[1] = i_usdc;

            uint256[] memory amountsOut = i_router.getAmountsOut(_amount, path1);
            uint256 expectedUSDCOutEth = amountsOut[amountsOut.length - 1];
            if (expectedUSDCOutEth == 0) revert NoPathOrZeroOut();

            if (s_totalDepositedUSDC + expectedUSDCOutEth > s_bankCapUSDC) {
                revert DepositWouldExceedCap(
                    expectedUSDCOutEth,
                    s_bankCapUSDC - s_totalDepositedUSDC
                );
            }

            uint256[] memory results = i_router.swapExactETHForTokens{value: _amount}(
                _minOutUSDC,
                path1,
                address(this),
                block.timestamp + 300
            );

            uint256 usdcReceived = results[results.length - 1];
            if (usdcReceived == 0) revert SwapFailed();

            unchecked {
                s_balances[msg.sender][i_usdc] += usdcReceived;
                s_totalDepositedUSDC += usdcReceived;
                ++s_totalDepositsCount;
            }

            emit DepositConvertedToUSDC(msg.sender, address(0), _amount, usdcReceived);
            return;
        }

        // 3) Deposit of an arbitrary ERC20 with a pair to USDC
        uint256 expectedUSDCOut;

        if (address(wrapper) != address(0)) {
            // Use the Wrapper to preview the swap token -> USDC
            expectedUSDCOut = wrapper.previewSwapToUsdc(_token, _amount);
        } else {
            // Fallback: calculate route token -> WETH -> USDC directly in the router
            address[] memory pathPreview;
            pathPreview = new address[](3) ;
            pathPreview[0] = _token;
            pathPreview[1] = i_weth;
            pathPreview[2] = i_usdc;

            uint256[] memory est = i_router.getAmountsOut(_amount, pathPreview);
            expectedUSDCOut = est[est.length - 1];
        }

        if (expectedUSDCOut == 0) revert NoPathOrZeroOut();
        if (s_totalDepositedUSDC + expectedUSDCOut > s_bankCapUSDC) {
            revert DepositWouldExceedCap(
                expectedUSDCOut,
                s_bankCapUSDC - s_totalDepositedUSDC
            );
        }

        // Transfer tokens to the bank
        IERC20(_token).safeTransferFrom(msg.sender, address(this), _amount);

        // Swap token -> USDC via router (token -> WETH -> USDC or WETH -> USDC)
        address[] memory path;
        if (_token == i_weth) {
            path = new address[](2);
            path[0] = i_weth;
            path[1] = i_usdc;
        } else {
            path = new address[](3);
            path[0] = _token;
            path[1] = i_weth;
            path[2] = i_usdc;
        }

        IERC20(_token).approve(address(i_router), 0);
        IERC20(_token).approve(address(i_router), _amount);

        uint256[] memory res = i_router.swapExactTokensForTokens(
            _amount,
            _minOutUSDC,
            path,
            address(this),
            block.timestamp + 300
        );

        uint256 usdcGot = res[res.length - 1];
        if (usdcGot == 0) revert SwapFailed();

        unchecked {
            s_balances[msg.sender][i_usdc] += usdcGot;
            s_totalDepositedUSDC += usdcGot;
            ++s_totalDepositsCount;
        }

        emit DepositConvertedToUSDC(msg.sender, _token, _amount, usdcGot);
    }

    /*////////////////////////////////////////////////////////////
                               WITHDRAWALS
    ////////////////////////////////////////////////////////////*/

    /**
     * @notice Withdraw USDC from the bank.
     * @param _amountUSDC Amount in USDC to withdraw (6 decimals).
     */
    function withdrawUSDC(uint256 _amountUSDC)
        external
        nonReentrant
        nonZeroAmount(_amountUSDC)
    {
        uint256 bal = s_balances[msg.sender][i_usdc];
        if (_amountUSDC > bal) revert InsufficientBalance(bal, _amountUSDC);

        uint256 limit = s_withdrawalLimitUSDC[i_usdc];
        if (limit != 0 && _amountUSDC > limit) {
            revert WithdrawalLimitExceeded(_amountUSDC, limit);
        }

        unchecked {
            s_balances[msg.sender][i_usdc] = bal - _amountUSDC;
            s_totalDepositedUSDC -= _amountUSDC;
            ++s_totalWithdrawalsCount;
        }

        IERC20(i_usdc).safeTransfer(msg.sender, _amountUSDC);
        emit WithdrawUSDC(msg.sender, _amountUSDC);
    }

    /*////////////////////////////////////////////////////////////
                               VIEWS
    ////////////////////////////////////////////////////////////*/

    /// @notice Returns the user's internal balance in USDC
    /// @param _user The address of the user to query
    /// @return The user's balance in USDC units (6 decimals)
    function getUSDCBalance(address _user) external view returns (uint256) {
        return s_balances[_user][i_usdc];
    }

    /*////////////////////////////////////////////////////////////
                               FALLBACKS
    ////////////////////////////////////////////////////////////*/

    function _revertDirectETH() private pure {
        revert DirectETHNotAllowed();
    }

    receive() external payable {
        _revertDirectETH();
    }

    fallback() external payable {
        _revertDirectETH();
    }
}
