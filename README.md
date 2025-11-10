# KipuBankV3

## Descripción General

`KipuBankV3` es una evolución del contrato `KipuBankV2`, diseñada para funcionar como una aplicación DeFi avanzada e integrada con Uniswap V2.  
Permite depósitos en múltiples tokens, los convierte automáticamente a **USDC**, y mantiene la lógica principal del banco, incluyendo el límite máximo global (`bankCap`).  
El proyecto fue desarrollado en **Foundry**, con enfoque en seguridad, modularidad y cobertura de pruebas superior al 50%.

---

## Mejoras Implementadas

1. **Integración con Uniswap V2**  
   Se agregó compatibilidad con el router de Uniswap V2 (`IUniswapV2Router02`), permitiendo realizar swaps automáticos de cualquier token ERC-20 hacia USDC.

2. **Depósitos Generalizados**  
   Se pueden realizar depósitos en:
   - ETH (token nativo)
   - USDC (depósito directo)
   - Cualquier otro token ERC-20 con par a USDC.

3. **Conversión Automática a USDC**  
   Tokens distintos a USDC se convierten mediante el router y se acreditan al balance del usuario.

4. **Lógica de Seguridad y Control de Acceso**  
   - Uso de `AccessControl` en lugar de `Ownable`.
   - Protección contra reentradas con `ReentrancyGuard`.
   - Manejo seguro de tokens con `SafeERC20`.

5. **Wrapper Externo**  
   Se implementó un contrato `Wrapper` auxiliar que encapsula la lógica de swap, mejorando la legibilidad y el mantenimiento del código.

6. **Bank Cap**  
   Se mantiene un límite máximo de USDC total que el banco puede almacenar.  
   Si un depósito supera ese límite, la transacción revierte con `DepositWouldExceedCap`.

7. **Cobertura de Pruebas**  
   Se realizaron pruebas unitarias con Foundry (`forge test`), alcanzando una cobertura total superior al 50%.

---

## Instrucciones de Despliegue

### 1. Crear archivo `.env`

```bash
PRIVATE_KEY=0xTU_CLAVE_PRIVADA_CON_FONDOS_EN_SEPOLIA
ADMIN=0xDIRECCION_DEL_ADMIN
SEPOLIA_UNI_V2_ROUTER=0xeE567Fe1712Faf6149d80dA1E6934E354124CfE3
SEPOLIA_USDC=0x1c7D4B196Cb0C7B01d743Fbc6116a902379C7238
INITIAL_BANK_CAP_USDC=100000000000
```

### 2. Compilar

```bash
forge build
```

### 3. Desplegar en red local (Anvil)

```bash
anvil
```

En otra terminal:

```bash
forge script script/KipuBankV3.s.sol:DeployKipuBankV3Script --rpc-url http://127.0.0.1:8545 --broadcast
```

### 4. Desplegar en Sepolia

```bash
forge script script/KipuBankV3.s.sol:DeployKipuBankV3Script --rpc-url https://rpc.sepolia.ethpandaops.io --broadcast --verify
```

---

## Interacción con el Contrato

### Depositar USDC directamente

```solidity
deposit(USDC_ADDRESS, amount, 0);
```

### Depositar otro token ERC-20

```solidity
deposit(TOKEN_ADDRESS, amount, minOutUSDC);
```

### Depositar ETH

```solidity
deposit(address(0), msg.value, minOutUSDC);
```

### Retirar USDC

```solidity
withdrawUSDC(amountUSDC);
```

---

## Decisiones de Diseño y Trade-offs

- La lógica de swap se delega al contrato `Wrapper` para simplificar el contrato principal.  
- Se priorizó la seguridad mediante librerías de OpenZeppelin.  
- Se usaron variables `immutable` para optimizar gas.  
- Diseño modular que permite sustituir el `Wrapper` sin redeployar `KipuBankV3`.

---

## Análisis de Amenazas

| Riesgo | Descripción | Mitigación |
|--------|--------------|------------|
| Reentrancy | Riesgo en retiros o swaps | `ReentrancyGuard` |
| Manipulación de precios | Cambios bruscos en pares USDC/WETH | Uso de `amountOutMin` |
| Exceso de depósitos | Superar bankCap | Validación antes de actualizar balances |
| Roles inseguros | Acceso no autorizado | `AccessControl` |
| Tokens no estándar | Tokens sin comportamiento ERC20 | Validación de interfaz |

---

## Cobertura de Pruebas

- **Cobertura total:** superior al 50%
- **Framework:** Foundry  
- **Comando:**

```bash
forge coverage --report summary
```

---

## Métodos de Prueba

- **Mocks:**  
  `MockRouter` y `MockERC20` simulan Uniswap y tokens.
- **Escenarios probados:**  
  - Depósitos en USDC, ETH y otros tokens.  
  - Retiros válidos e inválidos.  
  - Control de roles.  
  - Límites de depósito.  
- **Pruebas de revert:**  
  Se validaron errores personalizados como `ZeroAmount`, `DepositWouldExceedCap` y `SwapFailed`.

---

## Enlaces

**Contrato verificado (Sepolia):**  
[https://sepolia.etherscan.io/address/0x8728130f647a9764877fd4E5fC712e2C43483213#code](https://sepolia.etherscan.io/address/0x8728130f647a9764877fd4E5fC712e2C43483213#code)