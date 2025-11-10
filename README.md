# KipuBankV3

## Overview

`KipuBankV3` is an evolution of the `KipuBankV2` contract, designed to function as an advanced DeFi application integrated with Uniswap V2.  
It allows deposits in multiple tokens, automatically converts them to **USDC**, and maintains the main banking logic, including the global maximum limit (`bankCap`).  
The project was developed using **Foundry**, focusing on security, modularity, and achieving over 50% test coverage.

---

## Implemented Improvements

1. **Uniswap V2 Integration**  
   Added compatibility with the Uniswap V2 router (`IUniswapV2Router02`), enabling automatic swaps of any ERC-20 token into USDC.

2. **Generalized Deposits**  
   Deposits can be made in:
   - ETH (native token)
   - USDC (direct deposit)
   - Any other ERC-20 token paired with USDC.

3. **Automatic Conversion to USDC**  
   Tokens other than USDC are converted via the router and credited to the user's balance.

4. **Security and Access Control Logic**  
   - Uses `AccessControl` instead of `Ownable`.
   - Reentrancy protection with `ReentrancyGuard`.
   - Secure token handling with `SafeERC20`.

5. **External Wrapper**  
   A helper `Wrapper` contract was implemented to encapsulate swap logic, improving code readability and maintainability.

6. **Bank Cap**  
   A maximum USDC cap is maintained for the total balance the bank can hold.  
   If a deposit exceeds this limit, the transaction reverts with `DepositWouldExceedCap`.

7. **Test Coverage**  
   Unit tests were performed using Foundry (`forge test`), achieving total coverage above 50%.

---

## Deployment Instructions

### 1. Create `.env` file

```bash
PRIVATE_KEY=0xYOUR_PRIVATE_KEY_WITH_FUNDS_ON_SEPOLIA
ADMIN=0xADMIN_ADDRESS
SEPOLIA_UNI_V2_ROUTER=0xeE567Fe1712Faf6149d80dA1E6934E354124CfE3
SEPOLIA_USDC=0x1c7D4B196Cb0C7B01d743Fbc6116a902379C7238
INITIAL_BANK_CAP_USDC=100000000000
```

### 2. Build

```bash
forge build
```

### 3. Deploy to Local Network (Anvil)

```bash
anvil
```

In another terminal:

```bash
forge script script/KipuBankV3.s.sol:DeployKipuBankV3Script --rpc-url http://127.0.0.1:8545 --broadcast
```

### 4. Deploy to Sepolia

```bash
forge script script/KipuBankV3.s.sol:DeployKipuBankV3Script --rpc-url https://rpc.sepolia.ethpandaops.io --broadcast --verify
```

---

## Contract Interaction

### Deposit USDC Directly

```solidity
deposit(USDC_ADDRESS, amount, 0);
```

### Deposit Another ERC-20 Token

```solidity
deposit(TOKEN_ADDRESS, amount, minOutUSDC);
```

### Deposit ETH

```solidity
deposit(address(0), msg.value, minOutUSDC);
```

### Withdraw USDC

```solidity
withdrawUSDC(amountUSDC);
```

---

## Design Decisions and Trade-offs

- The swap logic is delegated to the `Wrapper` contract to simplify the main contract.  
- Security was prioritized through OpenZeppelin libraries.  
- `immutable` variables were used to optimize gas.  
- Modular design allows the `Wrapper` to be replaced without redeploying `KipuBankV3`.

---

## Threat Analysis

| Risk | Description | Mitigation |
|------|--------------|-------------|
| Reentrancy | Risk in withdrawals or swaps | `ReentrancyGuard` |
| Price Manipulation | Sudden changes in USDC/WETH pairs | Use of `amountOutMin` |
| Excessive Deposits | Exceeding bankCap | Validation before updating balances |
| Insecure Roles | Unauthorized access | `AccessControl` |
| Non-standard Tokens | Tokens not following ERC20 behavior | Interface validation |

---

## Test Coverage

- **Total coverage:** above 50%
- **Framework:** Foundry 

```bash
forge coverage --report summary
```

---

## Testing Methods

- **Mocks:**  
  `MockRouter` and `MockERC20` simulate Uniswap and token behavior.
- **Tested Scenarios:**  
  - Deposits in USDC, ETH, and other tokens.  
  - Valid and invalid withdrawals.  
  - Role control.  
  - Deposit limits.  
- **Revert Tests:**  
  Custom errors such as `ZeroAmount`, `DepositWouldExceedCap`, and `SwapFailed` were validated.

---

## Links

**Verified Contract (Sepolia):**  
[https://sepolia.etherscan.io/address/0x8728130f647a9764877fd4E5fC712e2C43483213#code](https://sepolia.etherscan.io/address/0x8728130f647a9764877fd4E5fC712e2C43483213#code)
