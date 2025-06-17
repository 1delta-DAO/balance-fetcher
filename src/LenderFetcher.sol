// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

library Lenders {
    uint256 internal constant AAVE_V2 = 0;
    uint256 internal constant AAVE_V3 = 1;
}

library AaveForks {}

contract LenderFetcher {
    uint256 private constant UINT128_MAX = 0xffffffffffffffffffffffffffffffff;
    uint256 private constant UINT120_MAX = 0xffffffffffffffffffffffffffffff;

    bytes32 private constant ERR_CALL_FAILED = 0x3204506f00000000000000000000000000000000000000000000000000000000;
    bytes32 private constant ERR_INVALID_INPUT_LENGTH =
        0x7db491eb00000000000000000000000000000000000000000000000000000000;
    bytes32 private constant ERR_UNSUPPORTED_LENDER = 0x8c379a0000000000000000000000000000000000000000000000000000000000;
    bytes32 private constant AAVE_GET_ACCOUNT_DATA = 0xbf92857c00000000000000000000000000000000000000000000000000000000;

    error InvalidInputLength();
    error UnsupportedLender();
    error CallFailed();

    fallback() external payable {
        assembly {
            /* *************
             * Functions
             ************* */
            function getAaveBalance(currentOffset, user, lender) -> result, offset {
                let oneword := calldataload(currentOffset)
                let fork := shr(248, oneword)
                let pool := shr(96, shl(8, oneword))
                offset := add(currentOffset, 21) // update offset

                // get balance and set result
                mstore(0x00, AAVE_GET_ACCOUNT_DATA)
                mstore(0x04, user)
                if iszero(staticcall(gas(), pool, 0, 0x24, 0x100, 0xc0)) {
                    mstore(0x00, ERR_CALL_FAILED)
                    revert(0x00, 0x04)
                }
                let col := and(UINT120_MAX, mload(0x100))
                let deb := and(UINT120_MAX, mload(0x120))
                if and(iszero(col), iszero(deb)) { result := 0 }
                // lenderId (1byte) | forkId (1byte) |totalCollateralBase (15bytes) | totalDebtBase (15bytes)
                result := or(shl(248, and(lender, 0xff)), shl(240, and(fork, 0xff)))
                result := or(result, or(shl(120, col), deb))
            }

            /* *************
             * Logic
             ************* */
            if lt(calldatasize(), 0x44) {
                mstore(0x00, ERR_INVALID_INPUT_LENGTH)
                revert(0x00, 0x04)
            }

            // skip function selector, abi encoding of bytes
            let offset := 0x44
            let resultsPtr := mload(0x40)
            // save block number uint64
            mstore(resultsPtr, shl(192, and(number(), 0xffffffffffffffff)))
            let memOffset := add(resultsPtr, 8)
            // reserve 0xff bytes
            mstore(0x40, add(resultsPtr, 0xff))

            let firstWord := calldataload(offset)
            let inputLength := shr(240, firstWord) // I cannot use the mload(0x24) because of zero padding
            let user := shr(96, shl(16, firstWord))
            offset := add(offset, 22) // skip user address and input length

            for {} lt(offset, add(inputLength, 0x44)) {} {
                // the first byte us the lenderId, this id is used to determine which function to use
                let lender := byte(0, calldataload(offset))
                offset := add(offset, 1)

                let result := 0

                switch lender
                case 0 {
                    // AAVE_V2
                    result, offset := getAaveBalance(offset, user, lender)
                }
                case 1 {
                    // AAVE_V3
                    result, offset := getAaveBalance(offset, user, lender)
                }
                default {
                    mstore(0x00, ERR_UNSUPPORTED_LENDER)
                    revert(0x00, 0x04)
                }

                if iszero(result) { continue } // save only none-zero results

                mstore(memOffset, result)
                memOffset := add(memOffset, 0x20) // skip result
            }

            mstore(0x40, add(memOffset, 0x20)) // set the fmp to a word after the results
            return(resultsPtr, sub(memOffset, resultsPtr))
        }
    }
}
