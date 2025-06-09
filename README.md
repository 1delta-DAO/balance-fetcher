# Balance Fetcher

A solidity contract for fetching ERC20 token balances for multiple addresses in a single transaction.

## Input Format

The contract expects a tightly packed input with the following structure:

```
[2 bytes: numTokens][2 bytes: numAddresses][20 bytes: address1][20 bytes: address2]...[20 bytes: token1][20 bytes: token2]...
```

### Example Input

For 2 addresses and 2 tokens, the input would be structured as follows:

```solidity
// Example addresses and tokens
address[] users = [
    0x91ae002a960e63Ccb0E5bDE83A8C13E51e1cB91A,
    0xdFF70A71618739f4b8C81B11254BcE855D02496B
];

address[] tokens = [
    0xFd086bC7CD5C481DCC9C85ebE478A1C0b69FCbb9, // USDT
    0xaf88d065e77c8cC2239327C5EDb3A432268e5831  // USDC
];

// Packed input would be:
// 0x00020002 (2 tokens, 2 addresses)
// 91ae002a960e63Ccb0E5bDE83A8C13E51e1cB91A (address1)
// dFF70A71618739f4b8C81B11254BcE855D02496B (address2)
// Fd086bC7CD5C481DCC9C85ebE478A1C0b69FCbb9 (token1)
// af88d065e77c8cC2239327C5EDb3A432268e5831 (token2)
```

## Output Format

The contract returns a tightly packed output with the following structure:

```
[32 bytes: user1 address + count][32 bytes: token1 + balance1][32 bytes: token2 + balance2]...
[32 bytes: user2 address + count][32 bytes: token1 + balance1][32 bytes: token2 + balance2]...
```

Each 32-byte word contains:
- For user entries: `[20 bytes: address][12 bytes: count of non-zero balances]`
- For balance entries: `[20 bytes: token address][12 bytes: balance]`

### Example Output

```solidity
// Example output for 2 users with non-zero balances:
// First user (0x91ae...)
// 0x91ae002a960e63Ccb0E5bDE83A8C13E51e1cB91A000000000000000000000002 (address + 2 balances)
// 0xFd086bC7CD5C481DCC9C85ebE478A1C0b69FCbb9000000000000000000000001 (USDT + 1e6)
// 0xaf88d065e77c8cC2239327C5EDb3A432268e5831000000000000000000000002 (USDC + 2e6)

// Second user (0xdFF7...)
// 0xdFF70A71618739f4b8C81B11254BcE855D02496B000000000000000000000001 (address + 1 balance)
// 0xaf88d065e77c8cC2239327C5EDb3A432268e5831000000000000000000000003 (USDC + 3e6)
```
