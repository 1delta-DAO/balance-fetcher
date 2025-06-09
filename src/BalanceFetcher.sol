// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

contract BalanceFetcher {
    bytes32 private constant ERC20_BALANCE_OF = 0x70a0823100000000000000000000000000000000000000000000000000000000;
    bytes32 private constant UINT96_MASK = 0x0000000000000000000000000000000000000000ffffffffffffffffffffffff;
    bytes32 private constant ERR_INVALID_INPUT_LENGTH =
        0x7db491eb00000000000000000000000000000000000000000000000000000000;

    error InvalidInputLength();

    fallback() external payable {
        assembly {
            // revert function
            function revertInvalidInputLength() {
                mstore(0, ERR_INVALID_INPUT_LENGTH) // InvalidInputLength
                revert(0, 4)
            }

            // read balance function
            function readBalance(token, user) -> bal {
                mstore(0x0, ERC20_BALANCE_OF)
                mstore(0x4, user)
                pop(staticcall(gas(), token, 0x0, 0x24, 0x0, 0x20))
                bal := mload(0x0)
            }

            // encode address and balance function
            function encodeAddressAndBalance(addr, bal) -> enc {
                enc := or(shl(96, addr), and(bal, UINT96_MASK))
            }
            /*
            Expected input:
            numAddresses: 2bytes
            numTokens: 2bytes
            data:
                address1, address2, ...
                token1, token2, ...
            */
            let firstWrd := calldataload(0)
            let numTokens := shr(240, firstWrd)
            let numAddresses := and(0x0000ffff, shr(224, firstWrd))

            // revert if number of tokens or addresses is zero
            if or(iszero(numTokens), iszero(numAddresses)) { revertInvalidInputLength() }

            // revert if the address length is incorrect
            if xor(calldatasize(), add(4, add(mul(numTokens, 20), mul(numAddresses, 20)))) {
                revertInvalidInputLength()
            }

            /*
            Data structure:
            prefix : userAddress, numberOfNoneZeroBalanceTokens (20bytes, 12bytes) : 32 bytes
            data: tokenAddress, balance (20bytes, 12bytes) : 32 bytes per each non-zero balance
             */
            let ptr := mload(0x40)
            // reserve memory (max possible size - all users have none-zero balances for all tokens)
            mstore(0x40, add(ptr, mul(32, add(numAddresses, mul(numAddresses, numTokens)))))
            let tokenAddressesOffset := add(4, mul(numAddresses, 20)) // 4 is the offset for number of addresses and numTokens
            let totalNoneZeroCount := 0

            for { let i := 0 } lt(i, numAddresses) { i := add(i, 1) } {
                let user := shr(96, calldataload(add(4, mul(i, 20))))
                let noneZeroCurrentUser := 0
                for { let j := 0 } lt(j, numTokens) { j := add(j, 1) } {
                    let token := shr(96, calldataload(add(tokenAddressesOffset, mul(j, 20))))
                    let bal := readBalance(token, user)
                    if iszero(bal) { continue }
                    mstore(
                        add(
                            add(ptr, mul(add(i, 1), 32)), // offset for prefix part
                            mul(add(totalNoneZeroCount, noneZeroCurrentUser), 32) // offset for all previous non-zero balances
                        ),
                        encodeAddressAndBalance(token, bal)
                    )
                    noneZeroCurrentUser := add(noneZeroCurrentUser, 1)
                }
                // update the prefix for this user
                switch iszero(i)
                case 0 {
                    mstore(
                        add(
                            ptr,
                            mul(add(i, totalNoneZeroCount), 32) // offset for previous prefixes and none-zero balances for all users before this user
                        ),
                        encodeAddressAndBalance(user, noneZeroCurrentUser)
                    )
                }
                default {
                    // the first address
                    mstore(ptr, encodeAddressAndBalance(user, noneZeroCurrentUser))
                }

                // update the total number of non-zero balances
                totalNoneZeroCount := add(totalNoneZeroCount, noneZeroCurrentUser)
            }
            // length of the data
            mstore(0, mul(32, add(totalNoneZeroCount, numAddresses)))

            mstore(0x40, add(ptr, mload(0)))

            // return the data
            return(ptr, mload(0))
        }
    }
}
