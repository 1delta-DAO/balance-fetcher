// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

library Lenders {
    uint256 internal constant AAVE_V2 = 0;
    uint256 internal constant AAVE_V3 = 1;
    uint256 internal constant COMP_V2 = 2;
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
    bytes32 private constant COMP_GET_ALL_MARKETS = 0xb0772d0b00000000000000000000000000000000000000000000000000000000;
    bytes32 private constant COMP_IS_DEPRECATED = 0x94543c1500000000000000000000000000000000000000000000000000000000;
    bytes32 private constant COMP_BALANCE_OF_UNDERLYING =
        0x70a0823100000000000000000000000000000000000000000000000000000000;
    bytes32 private constant COMP_BORROW_BALANCE_CURRENT =
        0x95dd919300000000000000000000000000000000000000000000000000000000;
    bytes32 private constant ERR_NO_VALUE = 0xf2365b5b00000000000000000000000000000000000000000000000000000000;

    error InvalidInputLength();
    error UnsupportedLender();
    error CallFailed();
    error NoValue();

    fallback() external payable {
        assembly {
            // revert if value is sent
            if callvalue() {
                mstore(0, ERR_NO_VALUE)
                revert(0, 4)
            }

            /* *************
             * Functions
             *************** */
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
                // lenderId (1byte) | forkId (1byte) | totalCollateralBase (15bytes) | totalDebtBase (15bytes)
                result := or(shl(248, and(lender, 0xff)), shl(240, and(fork, 0xff)))
                result := or(result, or(shl(120, col), deb))
            }

            function getCommV2Balance(currentOffset, user, lender) -> result, offset {
                let oneword := calldataload(currentOffset)
                let fork := shr(248, oneword)
                let comptroller := shr(96, shl(8, oneword))
                offset := add(currentOffset, 21) // update offset

                let ptr := mload(0x40) // we can use the free memory pointer because it is updated to a safe memory location
                // get all markets from comptroller
                mstore(0x00, COMP_GET_ALL_MARKETS)
                if iszero(staticcall(gas(), comptroller, 0, 0x04, 0, 0)) {
                    mstore(0x00, ERR_CALL_FAILED)
                    revert(0x00, 0x04)
                }
                // we don't know the return data length beforehand, so we use returndatacopy to copy the output data
                if gt(returndatasize(), 0) { returndatacopy(add(ptr, 0x20), 0, returndatasize()) }

                let marketsLength := mload(add(ptr, 0x40))
                let marketsData := add(ptr, 0x60)

                let hasCollateral := 0
                let hasDebt := 0

                // loop all markets
                for { let i := 0 } lt(i, marketsLength) { i := add(i, 1) } {
                    let cToken := mload(add(marketsData, mul(i, 0x20)))

                    // check if market is deprecated
                    mstore(0x00, COMP_IS_DEPRECATED)
                    mstore(0x04, cToken)
                    let isDeprecated := 0
                    if staticcall(gas(), comptroller, 0x00, 0x24, 0x00, 0x20) { isDeprecated := mload(0x00) }

                    // skip if deprecated
                    if isDeprecated { continue }

                    // check supply balance
                    if iszero(hasCollateral) {
                        mstore(0x00, COMP_BALANCE_OF_UNDERLYING)
                        mstore(0x04, user)
                        if staticcall(gas(), cToken, 0x00, 0x24, 0x00, 0x20) {
                            let supplyBalance := mload(0x00)
                            if gt(supplyBalance, 0) { hasCollateral := 1 }
                        }
                    }

                    // check borrow balance
                    if iszero(hasDebt) {
                        mstore(0x00, COMP_BORROW_BALANCE_CURRENT)
                        mstore(0x04, user)
                        if staticcall(gas(), cToken, 0x00, 0x24, 0x00, 0x20) {
                            let borrowBalance := mload(0x00)
                            if gt(borrowBalance, 0) { hasDebt := 1 }
                        }
                    }

                    // if both are none-zero, exit loop
                    if and(hasCollateral, hasDebt) { break }
                }

                // if no positions found, return 0
                if and(iszero(hasCollateral), iszero(hasDebt)) {
                    result := 0
                    leave
                }

                // encode result: lenderId (1byte) | forkId (1byte) | hasCollateral (15bytes) | hasDebt (15bytes)
                result := or(shl(248, and(lender, 0xff)), shl(240, and(fork, 0xff)))
                result := or(result, or(shl(120, hasCollateral), hasDebt))
            }

            /* *************
             * Logic
             *************** */
            if lt(calldatasize(), 0x44) {
                mstore(0x00, ERR_INVALID_INPUT_LENGTH)
                revert(0x00, 0x04)
            }

            // skip function selector, abi encoding of bytes
            let offset := 0x44
            let resultsPtr := mload(0x40)

            /*
            input:
            - 16 bytes: input length
            - 20 bytes: user address
            - 1 byte: lenderId
            - 1 byte: forkId
            - 20 bytes: pool/comptroller address

            output:
            - 16 bytes: block number
            - 32 bytes: result0
            - 32 bytes: result1
            - ...

            result encoding:
            - 1 byte: lenderId
            - 1 byte: forkId
            - For AAVE: 15 bytes totalCollateralBase | 15 bytes totalDebtBase
            - For COMP_V2: 15 bytes hasCollateral (1/0) | 15 bytes hasDebt (1/0)
            */

            let firstWord := calldataload(offset)
            // the first 16 bytes is the input length (can't use mload(0x24) here because of possible zero padding for alignment)
            let inputLength := shr(240, firstWord)
            // reserve 0xff bytes
            mstore(
                0x40,
                add(
                    0x50, // offset, length (abi encoding) and block number
                    add(
                        resultsPtr,
                        mul(
                            div(
                                sub(inputLength, 36), // subtract the user address and input length
                                22 // divide by 22 which is the required data length for each fork
                            ),
                            32 // each result length
                        )
                    )
                )
            )
            mstore(resultsPtr, 0x20) // offset
            mstore(add(resultsPtr, 0x40), shl(192, number())) // block number
            let currentPtr := add(resultsPtr, 0x48) // skip bytes length, offset and block number

            let user := shr(96, shl(16, firstWord))
            offset := add(offset, 22) // skip user address and input length

            for {} lt(offset, add(inputLength, 0x44)) {} {
                // the first byte is the lenderId, this id is used to determine which function to use
                let lender := byte(0, calldataload(offset)) // 3 gas
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
                case 2 {
                    // COMPOUND_V2
                    result, offset := getCommV2Balance(offset, user, lender)
                }
                default {
                    mstore(0x00, ERR_UNSUPPORTED_LENDER)
                    revert(0x00, 0x04)
                }

                if iszero(result) { continue } // save only none-zero results

                mstore(currentPtr, result)
                currentPtr := add(currentPtr, 0x20) // skip result
            }

            // Update free memory pointer (align to 32 bytes)
            mstore(0x40, and(add(currentPtr, 0x1f), not(0x1f)))

            // return the data
            mstore(add(resultsPtr, 0x20), sub(sub(currentPtr, resultsPtr), 0x40)) // data length and offset
            return(resultsPtr, sub(currentPtr, resultsPtr))
        }
    }
}
