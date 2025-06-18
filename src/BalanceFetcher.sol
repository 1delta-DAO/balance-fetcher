// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

contract BalanceFetcher {
    bytes32 private constant ERC20_BALANCE_OF = 0x70a0823100000000000000000000000000000000000000000000000000000000;
    bytes32 private constant UINT112_MASK = 0x000000000000000000000000000000000000ffffffffffffffffffffffffffff;
    bytes32 private constant UINT16_MASK = 0x000000000000000000000000000000000000000000000000000000000000ffff;
    bytes32 private constant ERR_INVALID_INPUT_LENGTH =
        0x7db491eb00000000000000000000000000000000000000000000000000000000;
    bytes32 private constant ERR_NO_VALUE = 0xf2365b5b00000000000000000000000000000000000000000000000000000000;

    error InvalidInputLength();
    error NoValue();

    fallback() external payable {
        assembly {
            // revert if value is sent
            if callvalue() {
                mstore(0, ERR_NO_VALUE)
                revert(0, 4)
            }
            // revert function
            function revertInvalidInputLength() {
                mstore(0, ERR_INVALID_INPUT_LENGTH) // InvalidInputLength
                revert(0, 4)
            }

            // store the selector once
            mstore(0x0, ERC20_BALANCE_OF)
            // read balance function with the in-place selector
            function readBalance(token, user) -> bal {
                mstore(0x4, user)
                pop(staticcall(gas(), token, 0x0, 0x24, 0x4, 0x20))
                bal := mload(0x4)
            }

            // encode index and balance function (2 bytes index + 14 bytes balance = 16 bytes total)
            function encodeIndexAndBalance(idx, bal) -> enc {
                enc := shl(128, or(shl(112, and(idx, UINT16_MASK)), and(bal, UINT112_MASK)))
            }

            // encode user index and count function (2 bytes each = 4 bytes total)
            function encodeUserIndexAndCount(userIdx, count) -> enc {
                enc := shl(224, or(shl(16, and(userIdx, UINT16_MASK)), and(count, UINT16_MASK)))
            }

            /*
            Expected input:
            numAddresses: uint16
            numTokens: uint16
            data:
                address1, address2, ...
                token1, token2, ...
            */
            let firstWrd := calldataload(0x44)
            let inputLength := calldataload(0x24)
            let numTokens := shr(240, firstWrd)
            let numAddresses := and(0x0000ffff, shr(224, firstWrd))

            // revert if number of tokens or addresses is zero
            if or(iszero(numTokens), iszero(numAddresses)) { revertInvalidInputLength() }

            // revert if input lenfth is incorrect
            if xor(inputLength, add(4, add(mul(numTokens, 20), mul(numAddresses, 20)))) { revertInvalidInputLength() }

            /*
            Data structure:
            prefix : userIndex, numberOfNoneZeroBalanceTokens (2bytes, 2bytes) : 4 bytes
            data: tokenIndex, balance (2bytes, 14bytes) : 16 bytes
             */
            let ptr := mload(0x40)
            // reserve memory (max possible size - all users have none-zero balances for all tokens)
            mstore(
                0x40,
                add(
                    ptr,
                    add(
                        0x48, // reserve for block number, length and offset
                        add(
                            mul(numAddresses, 4), // 4 bytes for each user address
                            mul(mul(numAddresses, numTokens), 16) // 16 bytes per each none-zero balance x all possible occurrences
                        )
                    )
                )
            )
            mstore(ptr, 0x20)
            mstore(add(ptr, 0x40), shl(192, number()))
            let currentPtr := add(ptr, 0x48) // skip bytes length, offset and block number

            let tokenAddressesOffset := add(4, mul(numAddresses, 20)) // 4 is the offset for number of addresses and numTokens

            for { let i := 0 } lt(i, numAddresses) { i := add(i, 1) } {
                let user := shr(96, calldataload(add(0x44, add(4, mul(i, 20)))))
                let noneZeroBalances := 0
                let userDataPtr := currentPtr
                currentPtr := add(currentPtr, 4)

                for { let j := 0 } lt(j, numTokens) { j := add(j, 1) } {
                    let token := shr(96, calldataload(add(0x44, add(tokenAddressesOffset, mul(j, 20)))))
                    let bal := 0
                    switch iszero(token)
                    // ERC20 balance
                    case 0 { bal := readBalance(token, user) }
                    // native balance
                    default { bal := balance(user) }
                    if iszero(bal) { continue }

                    mstore(currentPtr, encodeIndexAndBalance(j, bal))
                    currentPtr := add(currentPtr, 16)
                    noneZeroBalances := add(noneZeroBalances, 1)
                }

                // Store the user prefix (user index and count)
                mstore(
                    userDataPtr,
                    or(
                        encodeUserIndexAndCount(i, noneZeroBalances),
                        and(mload(userDataPtr), 0x00000000ffffffffffffffffffffffffffffffffffffffffffffffffffffffff)
                    )
                )
            }
            // Update free memory pointer (align to 32 bytes)
            mstore(0x40, and(add(currentPtr, 0x1f), not(0x1f)))

            // return the data
            mstore(add(ptr, 0x20), sub(sub(currentPtr, ptr), 0x40)) // data length and offset
            return(ptr, sub(currentPtr, ptr))
        }
    }
}
