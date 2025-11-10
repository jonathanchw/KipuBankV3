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
 * @notice Banco DeFi que acepta ETH, USDC y cualquier ERC20 con par en Uniswap V2,
 *         swappea todo a USDC y mantiene la contabilidad interna en USDC.
 *
 * @dev
 * - Integra Uniswap V2 vía router y Wrapper (para preview).
 * - Aplica un bankCap global en unidades de USDC (6 decimales).
 * - Preserva la idea de depósitos, retiros y control de roles de KipuBankV2.
 */
contract KipuBankV3 is AccessControl, ReentrancyGuard {
    using SafeERC20 for IERC20;

    /*////////////////////////////////////////////////////////////
                          ROLES & CONSTANTES
    ////////////////////////////////////////////////////////////*/

    bytes32 public constant OPERATOR_ROLE = keccak256("OPERATOR_ROLE");

    /// @notice Decimales de USDC (se asume 6)
    uint8 public constant USDC_DECIMALS = 6;

    /*////////////////////////////////////////////////////////////
                             INMUTABLES
    ////////////////////////////////////////////////////////////*/

    IUniswapV2Router02 public immutable i_router;
    address public immutable i_usdc;
    address public immutable i_weth;

    /*////////////////////////////////////////////////////////////
                               STATE
    ////////////////////////////////////////////////////////////*/

    /// @notice bankCap global en unidades de USDC (6 decimales)
    uint256 public s_bankCapUSDC;

    /// @notice total depositado en el banco, expresado en USDC (6 decimales)
    uint256 public s_totalDepositedUSDC;

    /// @notice balance interno de los usuarios en USDC
    /// usamos mapping anidado para mantener compat con el diseño anterior
    mapping(address => mapping(address => uint256)) private s_balances;

    /// @notice límite de retiro por transacción (por token). Usamos i_usdc como clave.
    mapping(address => uint256) public s_withdrawalLimitUSDC;

    /// @notice contrato externo Wrapper para preview (y potencialmente swaps)
    IWrapper public wrapper;

    uint256 public s_totalDepositsCount;
    uint256 public s_totalWithdrawalsCount;

    /*////////////////////////////////////////////////////////////
                               EVENTS
    ////////////////////////////////////////////////////////////*/

    event DepositUSDC(address indexed user, uint256 usdcAmount);
    event DepositConvertedToUSDC(
        address indexed user,
        address indexed fromToken,
        uint256 fromAmount,
        uint256 usdcAmount
    );
    event WithdrawUSDC(address indexed user, uint256 usdcAmount);
    event BankCapUpdated(uint256 newCapUSDC);
    event WrapperUpdated(address newWrapper);

    /*////////////////////////////////////////////////////////////
                               ERRORS
    ////////////////////////////////////////////////////////////*/

    error ZeroAmount();
    error DepositWouldExceedCap(uint256 amountUSDC, uint256 remainingUSDC);
    error InsufficientBalance(uint256 have, uint256 want);
    error WithdrawalLimitExceeded(uint256 amountUSDC, uint256 limitUSDC);
    error InvalidAddress();
    error NoPathOrZeroOut();
    error SwapFailed();

    /*////////////////////////////////////////////////////////////
                             CONSTRUCTOR
    ////////////////////////////////////////////////////////////*/

    /**
     * @param _router Dirección del router de Uniswap V2
     * @param _usdc Dirección del token USDC (6 decimales)
     * @param _initialCapUSDC bankCap inicial en unidades USDC (6 decimales)
     * @param _admin Dirección admin que recibe DEFAULT_ADMIN_ROLE y OPERATOR_ROLE
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
     * @notice Actualiza el bankCap (en USDC, 6 decimales)
     */
    function setBankCapUSDC(uint256 _newCap) external onlyRole(DEFAULT_ADMIN_ROLE) {
        s_bankCapUSDC = _newCap;
        emit BankCapUpdated(_newCap);
    }

    /**
     * @notice Setea el límite de retiro por transacción en USDC
     * @dev Usamos i_usdc como clave de s_withdrawalLimitUSDC
     */
    function setWithdrawalLimitUSDC(uint256 _limit) external onlyRole(OPERATOR_ROLE) {
        s_withdrawalLimitUSDC[i_usdc] = _limit;
    }

    /**
     * @notice Actualiza la dirección del Wrapper externo
     */
    function setWrapper(address _wrapper) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (_wrapper == address(0)) revert InvalidAddress();
        wrapper = IWrapper(_wrapper);
        emit WrapperUpdated(_wrapper);
    }

    /*////////////////////////////////////////////////////////////
                               DEPOSITS
    ////////////////////////////////////////////////////////////*/

    /**
     * @notice Depositar tokens en el banco (ETH, USDC o cualquier ERC20 con par a USDC).
     * @param _token Dirección del token a depositar:
     *        - address(0) para ETH
     *        - i_usdc para USDC
     *        - otro ERC20 soportado por Uniswap V2
     * @param _amount Cantidad en unidades nativas del token
     * @param _minOutUSDC Mínimo USDC aceptado (para proteger contra slippage)
     */
    function deposit(
    address _token,
    uint256 _amount,
    uint256 _minOutUSDC
    ) external payable nonReentrant {
    if (_amount == 0) revert ZeroAmount();

    // 1) Depósito directo de USDC (sin swap)
    if (_token == i_usdc) {
        IERC20(i_usdc).safeTransferFrom(msg.sender, address(this), _amount);

        if (s_totalDepositedUSDC + _amount > s_bankCapUSDC) {
            revert DepositWouldExceedCap(_amount, s_bankCapUSDC - s_totalDepositedUSDC);
        }

        s_balances[msg.sender][i_usdc] += _amount;
        s_totalDepositedUSDC += _amount;
        ++s_totalDepositsCount;

        emit DepositUSDC(msg.sender, _amount);
        return;
    }

    // 2) Depósito de ETH (token == address(0))
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

        s_balances[msg.sender][i_usdc] += usdcReceived;
        s_totalDepositedUSDC += usdcReceived;
        ++s_totalDepositsCount;

        emit DepositConvertedToUSDC(msg.sender, address(0), _amount, usdcReceived);
        return;
    }

    // 3) Depósito de un ERC20 arbitrario con par a USDC
    uint256 expectedUSDCOut;

    if (address(wrapper) != address(0)) {
        // Usamos el Wrapper para hacer el preview del swap token -> USDC
        expectedUSDCOut = wrapper.previewSwapToUsdc(_token, _amount);
    } else {
        // Fallback: calculamos ruta token -> WETH -> USDC directo en el router
        address[] memory pathPreview;
        pathPreview = new address[](3);
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

    // Transferimos los tokens al banco
    IERC20(_token).safeTransferFrom(msg.sender, address(this), _amount);

    // Swappeamos token -> USDC vía router (token -> WETH -> USDC o WETH -> USDC)
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

    s_balances[msg.sender][i_usdc] += usdcGot;
    s_totalDepositedUSDC += usdcGot;
    ++s_totalDepositsCount;

    emit DepositConvertedToUSDC(msg.sender, _token, _amount, usdcGot);
}


    /*////////////////////////////////////////////////////////////
                               WITHDRAWALS
    ////////////////////////////////////////////////////////////*/

    /**
     * @notice Retirar USDC del banco.
     * @param _amountUSDC Cantidad en USDC a retirar (6 decimales).
     */
    function withdrawUSDC(uint256 _amountUSDC) external nonReentrant {
        if (_amountUSDC == 0) revert ZeroAmount();

        uint256 bal = s_balances[msg.sender][i_usdc];
        if (_amountUSDC > bal) revert InsufficientBalance(bal, _amountUSDC);

        uint256 limit = s_withdrawalLimitUSDC[i_usdc];
        if (limit != 0 && _amountUSDC > limit) {
            revert WithdrawalLimitExceeded(_amountUSDC, limit);
        }

        unchecked {
            s_balances[msg.sender][i_usdc] = bal - _amountUSDC;
        }
        s_totalDepositedUSDC -= _amountUSDC;
        ++s_totalWithdrawalsCount;

        IERC20(i_usdc).safeTransfer(msg.sender, _amountUSDC);
        emit WithdrawUSDC(msg.sender, _amountUSDC);
    }

    /*////////////////////////////////////////////////////////////
                               VIEWS
    ////////////////////////////////////////////////////////////*/

    /// @notice Devuelve el balance interno del usuario en USDC
    function getUSDCBalance(address _user) external view returns (uint256) {
        return s_balances[_user][i_usdc];
    }

    /*////////////////////////////////////////////////////////////
                               FALLBACKS
    ////////////////////////////////////////////////////////////*/

    receive() external payable {
        revert("Use deposit for ETH");
    }

    fallback() external payable {
        revert("Use deposit for ETH");
    }
}
