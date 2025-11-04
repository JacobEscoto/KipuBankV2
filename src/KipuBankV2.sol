// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/// @title KipuBank
/// @author JacobEscoto

import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";

contract KipuBank is AccessControl, ReentrancyGuard {
    using SafeERC20 for IERC20;

    /// @notice Rol administrativo del contrato inteligente
    /// @dev Permite gestionar roles, price feeds y agregar tokens
    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");

    /// @notice Rol de auditoría
    /// @dev Puede consultar balances y bankCap total del banco
    bytes32 public constant AUDITOR_ROLE = keccak256("AUDITOR_ROLE");

    /// @notice Dirección para ETH nativo
    address public constant ETH_ADDRESS = address(0);

    uint8 public constant USDC_DECIMALS = 6;

    /// @notice Límite de saldo en depositos en el banco
    uint256 public immutable bankCapUSDC;

    /// @notice Líde saldo por retiro
    uint256 public immutable limitWithdrawalUSDC;

    struct TokenInfo {
        bool supported;
        uint8 decimal;
        address priceFeed;
    }

    mapping(address => mapping(address => uint256)) private balances;
    mapping(address => uint256) public totalBalances;
    mapping(address => TokenInfo) public tokenInfo;
    mapping(address => bool) public esTokenCompatible;

    /// @notice Contadores globales
    uint256 public depositosTotales;
    uint256 public retirosTotales;

    event Deposit(address indexed token, address indexed user, uint256 amount, uint256 valueUSDC);
    event Withdraw(address indexed token, address indexed user, uint256 amount, uint256 valueUSDC);
    event TokenAgregado(address indexed token, uint8 decimal, address feed);
    event TokenEliminado(address indexed token);
    event PriceFeedSet(address indexed token, address feed);

    error ValorCero();
    error TokenNoSoportado(address token);
    error NoHayFeedDePrecio(address token);
    error LimiteDepositoExcedido(uint256 attemptedUSDC, uint256 bankCap);
    error LimiteRetiroExcedido(uint256 attemptedUSDC, uint256 limitWithdrawal);
    error FondosInsuficientes(address user, address token, uint256 disponible);
    error TransferenciaFallida();
    error DireccionCero();

    /**
     * @notice Constructor del Contrato Inteligente
     * @param _bankCapUSDC Capacidad total del banco
     * @param _limitWithdrawalUSDC Límite por retiro
     */
    constructor(uint256 _bankCapUSDC, uint256 _limitWithdrawalUSDC) {
        if (_bankCapUSDC == 0 || _limitWithdrawalUSDC == 0) revert ValorCero();
        bankCapUSDC = _bankCapUSDC;
        limitWithdrawalUSDC = _limitWithdrawalUSDC;

        // Asignar roles iniciales al deployer
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(ADMIN_ROLE, msg.sender);
        _grantRole(AUDITOR_ROLE, msg.sender);
    }

     /// @notice Agrega un token soportado
     /// @dev Funcion solo permitida para rol de Admin
    function agregarToken(address token, uint8 decimal, address feed) external onlyRole(ADMIN_ROLE) {
        if (token == address(0)) token = ETH_ADDRESS;
        if (decimal == 0) revert DireccionCero();
        if (feed == address(0)) revert DireccionCero();

        tokenInfo[token] = TokenInfo({
            supported: true,
            decimal: decimal,
            priceFeed: feed
        });
        esTokenCompatible[token] = true;
        emit TokenAgregado(token, decimal, feed);
    }

    /// @notice Actualiza el feed de precio de un token
    /// @dev Solo lo puede utilizar el rol de ADMIN
    function setPriceFeed(address token, address feed) external onlyRole(ADMIN_ROLE) {
        if (!esTokenCompatible[token]) revert TokenNoSoportado(token);
        if (feed == address(0)) revert DireccionCero();
        tokenInfo[token].priceFeed = feed;
        emit PriceFeedSet(token, feed);
    }

    /// @notice Depositar ETH
    function depositETH() external payable nonReentrant {
        if (msg.value == 0) revert ValorCero();
        address token = ETH_ADDRESS;
        if (!esTokenCompatible[token]) revert TokenNoSoportado(token);
        address feedAddr = tokenInfo[token].priceFeed;
        if (feedAddr == address(0)) revert NoHayFeedDePrecio(token);

        uint256 valueUSDC = _montoDeTokenToUSDC(token, msg.value);
        uint256 tokenTotalUSDC = 0;
        uint256 tokenTotal = totalBalances[token];
        if (tokenTotal > 0) tokenTotalUSDC = _montoDeTokenToUSDC(token, tokenTotal);
        if (valueUSDC + tokenTotalUSDC > bankCapUSDC) revert LimiteDepositoExcedido(valueUSDC + tokenTotalUSDC, bankCapUSDC);

        balances[token][msg.sender] += msg.value;
        totalBalances[token] += msg.value;
        depositosTotales++;
        emit Deposit(token, msg.sender, msg.value, valueUSDC);
    }

    /// @notice Depositar ERC20
    function depositERC20(address token, uint256 monto) external nonReentrant {
        if (monto == 0) revert ValorCero();
        if (!esTokenCompatible[token]) revert TokenNoSoportado(token);
        address feedAddr = tokenInfo[token].priceFeed;
        if (feedAddr == address(0)) revert NoHayFeedDePrecio(token);

        uint256 valueUSDC = _montoDeTokenToUSDC(token, monto);

        uint256 tokenTotalUSDC = 0;
        uint256 tokenTotal = totalBalances[token];
        if (tokenTotal > 0) tokenTotalUSDC = _montoDeTokenToUSDC(token, tokenTotal);

        if (valueUSDC + tokenTotalUSDC > bankCapUSDC) revert LimiteDepositoExcedido(valueUSDC + tokenTotalUSDC, bankCapUSDC);

        IERC20(token).safeTransferFrom(msg.sender, address(this), monto);

        balances[token][msg.sender] += monto;
        totalBalances[token] += monto;
        depositosTotales++;
        emit Deposit(token, msg.sender, monto, valueUSDC);
    }

    /// @notice Retirar ETH
    function withdraw(address token, uint256 monto) external nonReentrant {
        if (monto == 0) revert ValorCero();
        if (token == address(0)) token = ETH_ADDRESS;
        if (!esTokenCompatible[token]) revert TokenNoSoportado(token);

        uint256 disponible = balances[token][msg.sender];
        if (disponible < monto)
            revert FondosInsuficientes(msg.sender, token, disponible);

        if (tokenInfo[token].priceFeed == address(0))
            revert NoHayFeedDePrecio(token);
        uint256 valueUSDC = _montoDeTokenToUSDC(token, monto);
        if (valueUSDC > limitWithdrawalUSDC)
            revert LimiteRetiroExcedido(valueUSDC, limitWithdrawalUSDC);

        balances[token][msg.sender] = disponible - monto;
        totalBalances[token] -= monto;
        retirosTotales++;

        emit Withdraw(token, msg.sender, monto, valueUSDC);
        if (token == ETH_ADDRESS) {
            (bool ok, ) = payable(msg.sender).call{value: monto}("");
            if (!ok) revert TransferenciaFallida();
        } else {
            IERC20(token).safeTransfer(msg.sender, monto);
        }
    }

    /// @notice Devuelve el balance del usuario para un token
    function getBalance(address token, address user) external view returns (uint256) {
        if (token == address(0)) token = ETH_ADDRESS;
        return balances[token][user];
    }

    /// @notice Convierte el monto a USDC
    function _montoDeTokenToUSDC( address token, uint256 monto) internal view returns (uint256 valueUSDC) {
        AggregatorV3Interface feed = AggregatorV3Interface(tokenInfo[token].priceFeed);
        if (address(feed) == address(0)) revert NoHayFeedDePrecio(token);

        (, int256 precio, , , ) = feed.latestRoundData();
        require(precio > 0, "price <= 0");
        uint256 precioFinal = uint256(precio);
        uint8 feedDecimals = feed.decimals();

        uint8 tokenDecimals = token == ETH_ADDRESS ? 18 : IERC20Metadata(token).decimals();

        uint256 numerador = monto * precioFinal * (10 ** uint256(USDC_DECIMALS));
        uint256 denominador = (10 ** uint256(tokenDecimals)) *
            (10 ** uint256(feedDecimals));
        valueUSDC = numerador / denominador;
    }
    
    // RECEIVE Y FALLBACK
    receive() external payable {
        revert ValorCero();
    }

    fallback() external payable {
        revert ValorCero();
    }
}
