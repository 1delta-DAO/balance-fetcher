# Balance Fetcher

A solidity contract for fetching ERC20 token balances for multiple addresses in a single transaction.

## Input Format

The contract expects a tightly packed input with the following structure:

```
[2 bytes: numTokens][2 bytes: numAddresses][20 bytes: address1][20 bytes: address2]...[20 bytes: token1][20 bytes: token2]...
```

### Example Input

```solidity
// Example addresses and tokens
address[] users = [
    0x91ae002a960e63Ccb0E5bDE83A8C13E51e1cB91A,
    0xdFF70A71618739f4b8C81B11254BcE855D02496B
];

address[] tokens = [
    0xFd086bC7CD5C481DCC9C85ebE478A1C0b69FCbb9, 
    0xaf88d065e77c8cC2239327C5EDb3A432268e5831  
];

// Create packed input
bytes memory input = abi.encodePacked(
    uint16(tokens.length),     // 2 bytes: number of tokens
    uint16(users.length),      // 2 bytes: number of addresses
    abi.encodePacked(users),   // 20 * N bytes: user addresses
    abi.encodePacked(tokens)   // 20 * M bytes: token addresses
);
```

## Output Format

The contract returns a packed output:

```
[4 bytes: user index + count][16 bytes: token index + balance][16 bytes: token index + balance]...
[4 bytes: user index + count][16 bytes: token index + balance][16 bytes: token index + balance]...
```

Each entry uses exact byte allocation:
- **User prefix (4 bytes)**: `[2 bytes: user index][2 bytes: count of non-zero balances]`
- **Balance entries (16 bytes each)**: `[2 bytes: token index][14 bytes: balance (uint112)]`

### Data Layout

The data is laid out sequentially with no padding:

```
User 1:  [userIdx: 2b][count: 2b]
Token 1: [tokenIdx: 2b][balance: 14b]
Token 2: [tokenIdx: 2b][balance: 14b]
...
User 2:  [userIdx: 2b][count: 2b]  
Token 1: [tokenIdx: 2b][balance: 14b]
...
```

