# Balance Fetcher

This repository contains two main contracts for efficient blockchain data fetching:

1. **BalanceFetcher**: Fetches ERC20 token balances and native ETH balances for multiple addresses
2. **LenderFetcher**: Checks lending protocol positions across multiple DeFi protocols

## BalanceFetcher Contract

### Input Format

The BalanceFetcher contract expects a tightly packed input with the following structure:

```
[2 bytes: numTokens][2 bytes: numAddresses][20 bytes: address1][20 bytes: address2]...[20 bytes: token1][20 bytes: token2]...
```

#### Example Input

```solidity
// Example addresses and tokens
address[] users = [
    0x91ae002a960e63Ccb0E5bDE83A8C13E51e1cB91A,
    0xdFF70A71618739f4b8C81B11254BcE855D02496B
];

address[] tokens = [
    0xFd086bC7CD5C481DCC9C85ebE478A1C0b69FCbb9, // USDT
    0xaf88d065e77c8cC2239327C5EDb3A432268e5831, // USDC
    address(0)  // Native ETH (use address(0) for native balance)
];

// Create packed input
bytes memory input = abi.encodePacked(
    uint16(tokens.length),     // 2 bytes: number of tokens
    uint16(users.length),      // 2 bytes: number of addresses
    abi.encodePacked(users),   // 20 * N bytes: user addresses
    abi.encodePacked(tokens)   // 20 * M bytes: token addresses
);
```

### Output Format

The BalanceFetcher contract returns a packed output with block number:

```
[8 bytes: block number][4 bytes: user index + count][16 bytes: token index + balance][16 bytes: token index + balance]...
[4 bytes: user index + count][16 bytes: token index + balance][16 bytes: token index + balance]...
```

Each entry uses exact byte allocation:

- **Block number (8 bytes)**: Current block number when the call was executed
- **User prefix (4 bytes)**: `[2 bytes: user index][2 bytes: count of non-zero balances]`
- **Balance entries (16 bytes each)**: `[2 bytes: token index][14 bytes: balance (uint112)]`

**Note**: Use `address(0)` in the token list to query native ETH balances.

#### Data Layout

The data is laid out sequentially with no padding:

```
Block Number: [8 bytes: current block number]
User 1:  [userIdx: 2b][count: 2b]
Token 1: [tokenIdx: 2b][balance: 14b]  // ERC20 or native ETH balance
Token 2: [tokenIdx: 2b][balance: 14b]
...
User 2:  [userIdx: 2b][count: 2b]
Token 1: [tokenIdx: 2b][balance: 14b]
...
```

## LenderFetcher Contract

The LenderFetcher contract efficiently checks if a user has positions (collateral, supply, or debt) across multiple DeFi lending protocols in a single transaction.

### Supported Protocols

- **Aave V2** (lenderId: 0)
- **Aave V3** (lenderId: 1)
- **Compound V2** (lenderId: 2)
- **Compound V3** (lenderId: 3)

### Input Format

The LenderFetcher expects a tightly packed input:

```
[2 bytes: total input length][20 bytes: user address][protocols...]
```

Each protocol entry contains:

```
[1 byte: lenderId][1 byte: forkId][20 bytes: protocol address]
```

#### Example Input

```solidity
address user = 0x1234567890123456789012345678901234567890;

// Check multiple protocols for the user
bytes memory input = abi.encodePacked(
    uint16(66),  // total input length (22 user + 22*2 protocols)
    user,        // user address (20 bytes)

    // Aave V3 on Arbitrum
    uint8(1),    // Aave V3 lenderId
    uint8(0),    // forkId
    address(0x794a61358D6845594F94dc1DB02A252b5b4814aD), // Aave V3 Pool

    // Compound V2 on Ethereum
    uint8(2),    // Compound V2 lenderId
    uint8(0),    // forkId
    address(0x3d9819210A31b4961b30EF54bE2aeD79B9c9Cd3B)  // Comptroller
);
```

### Output Format

The contract returns:

```
[8 bytes: block number][32 bytes: result1][32 bytes: result2]...
```

Each 32-byte result contains:

```
[1 byte: lenderId][1 byte: forkId][15 bytes: position flags][15 bytes: debt flags]
```

#### Position Flag Meanings

- **Aave V2/V3**: `totalCollateralBase` | `totalDebtBase` (actual amounts)
- **Compound V2**: `hasCollateral` (1/0) | `hasDebt` (1/0) (boolean flags)
- **Compound V3**: `hasPosition` (1/0) | `hasDebt` (1/0) (boolean flags)

**Note**: Only protocols where the user has positions (non-zero collateral or debt) are included in the response.

#### Example Usage

```solidity
// Call the LenderFetcher
(bool success, bytes memory data) = lenderFetcher.call(
    abi.encodeWithSignature("bal(bytes)", input)
);

// Parse results
if (success && data.length > 72) { // 32 offset + 32 length + 8 block number
    // User has positions in one or more protocols
    // Decode each 32-byte result to check specific protocols
}
```
