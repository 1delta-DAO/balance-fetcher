// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

library Lenders {
    uint256 internal constant AAVE_V2 = 0;
    uint256 internal constant AAVE_V3 = 1;
    uint256 internal constant COMP_V2 = 2;
    uint256 internal constant COMP_V3 = 3;
}

library AaveForks {}

contract LenderFetcher {
    bytes32 private constant ERR_CALL_FAILED = 0x3204506f00000000000000000000000000000000000000000000000000000000;
    bytes32 private constant ERR_INVALID_INPUT_LENGTH =
        0x7db491eb00000000000000000000000000000000000000000000000000000000;
    bytes32 private constant ERR_UNSUPPORTED_LENDER = 0x8c379a0000000000000000000000000000000000000000000000000000000000;
    bytes32 private constant AAVE_GET_ACCOUNT_DATA = 0xbf92857c00000000000000000000000000000000000000000000000000000000;
    bytes32 private constant COMP_GET_ALL_MARKETS = 0xb0772d0b00000000000000000000000000000000000000000000000000000000;
    bytes32 private constant COMP_IS_DEPRECATED = 0x94543c1500000000000000000000000000000000000000000000000000000000;
    bytes32 private constant BALANCE_OF = 0x70a0823100000000000000000000000000000000000000000000000000000000;
    bytes32 private constant COMP_BORROW_BALANCE_CURRENT =
        0x95dd919300000000000000000000000000000000000000000000000000000000;
    bytes32 private constant COMP_V3_BORROW_BALANCE_OF =
        0x374c49b400000000000000000000000000000000000000000000000000000000;
    bytes32 private constant COMP_V3_NUM_ASSETS = 0xa46fe83b00000000000000000000000000000000000000000000000000000000;
    bytes32 private constant COMP_V3_GET_ASSET_INFO = 0xc8c7fe6b00000000000000000000000000000000000000000000000000000000;
    bytes32 private constant COMP_V3_COLLATERAL_BALANCE_OF =
        0x2b92a07d00000000000000000000000000000000000000000000000000000000;
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
                let col := mload(0x100)
                let deb := mload(0x120)

                let hasCollateral := gt(col, 0)
                let hasDebt := gt(deb, 0)

                if iszero(or(hasCollateral, hasDebt)) {
                    result := 0
                    leave
                }

                // lenderId (1byte) | forkId (1byte) | hasCollateral (1byte) | hasDebt (1byte)
                result := or(shl(24, and(lender, 0xff)), shl(16, and(fork, 0xff)))
                result := or(result, or(shl(8, hasCollateral), hasDebt))
            }

            function getCompV2Balance(currentOffset, user, lender) -> result, offset {
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
                        mstore(0x00, BALANCE_OF)
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
                if iszero(or(hasCollateral, hasDebt)) {
                    result := 0
                    leave
                }

                // encode result: lenderId (1byte) | forkId (1byte) | hasCollateral (1byte) | hasDebt (1byte)
                result := or(shl(24, and(lender, 0xff)), shl(16, and(fork, 0xff)))
                result := or(result, or(shl(8, hasCollateral), hasDebt))
            }

            function getCompV3Balance(currentOffset, user, lender) -> result, offset {
                let oneword := calldataload(currentOffset)
                let fork := shr(248, oneword)
                let comet := shr(96, shl(8, oneword))
                offset := add(currentOffset, 21) // update offset

                let hasCollateral := 0
                let hasDebt := 0
                let hasBaseSupply := 0

                // check base asset supply balance
                mstore(0x00, BALANCE_OF)
                mstore(0x04, user)
                if staticcall(gas(), comet, 0x00, 0x24, 0x00, 0x20) {
                    let baseSupplyBalance := mload(0x00)
                    if gt(baseSupplyBalance, 0) { hasBaseSupply := 1 }
                }

                // check base asset borrow balance
                mstore(0x00, COMP_V3_BORROW_BALANCE_OF)
                mstore(0x04, user)
                if staticcall(gas(), comet, 0x00, 0x24, 0x00, 0x20) {
                    let baseBorrowBalance := mload(0x00)
                    if gt(baseBorrowBalance, 0) { hasDebt := 1 }
                }

                // get number of collateral assets
                mstore(0x00, COMP_V3_NUM_ASSETS)
                let numAssets := 0
                if staticcall(gas(), comet, 0x00, 0x04, 0x00, 0x20) { numAssets := mload(0x00) }

                // check collateral balances
                if gt(numAssets, 0) {
                    for { let i := 0 } lt(i, numAssets) { i := add(i, 1) } {
                        // get asset info for index i
                        mstore(0x00, COMP_V3_GET_ASSET_INFO)
                        mstore(0x04, i)
                        if staticcall(gas(), comet, 0x00, 0x24, 0x00, 0x40) {
                            // asset address is at offset 0x20 in AssetInfo struct
                            let assetAddress := mload(0x20)

                            let ptr := mload(0x40)
                            // check collateral balance for this asset
                            mstore(ptr, COMP_V3_COLLATERAL_BALANCE_OF)
                            mstore(add(ptr, 0x04), user)
                            mstore(add(ptr, 0x24), assetAddress)
                            if staticcall(gas(), comet, ptr, 0x44, 0x00, 0x20) {
                                let collateralBalance := mload(0x00)
                                if gt(collateralBalance, 0) {
                                    hasCollateral := 1
                                    break
                                }
                            }
                        }
                    }
                }

                if iszero(or(or(hasCollateral, hasBaseSupply), hasDebt)) {
                    result := 0
                    leave
                }

                // encode result: lenderId (1byte) | forkId (1byte) | hasPosition (1byte) | hasDebt (1byte)
                let hasPosition := or(hasCollateral, hasBaseSupply)
                result := or(shl(24, and(lender, 0xff)), shl(16, and(fork, 0xff)))
                result := or(result, or(shl(8, hasPosition), hasDebt))
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
            - 8 bytes: block number
            - 4 bytes: result0
            - 4 bytes: result1
            - ...

            result encoding:
            - 1 byte: lenderId
            - 1 byte: forkId
            - 1 byte: hasCollateral/hasPosition flag (1/0)
            - 1 byte: hasDebt flag (1/0)
            */

            let firstWord := calldataload(offset)
            // the first 16 bytes is the input length (can't use mload(0x24) here because of possible zero padding for alignment)
            let inputLength := shr(240, firstWord)
            // reserve memory for max results length
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
                            4 // each result length
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
                    result, offset := getCompV2Balance(offset, user, lender)
                }
                case 3 {
                    // COMPOUND_V3
                    result, offset := getCompV3Balance(offset, user, lender)
                }
                default {
                    mstore(0x00, ERR_UNSUPPORTED_LENDER)
                    revert(0x00, 0x04)
                }

                if iszero(result) { continue } // save only none-zero results

                mstore(currentPtr, shl(224, result))
                currentPtr := add(currentPtr, 4)
            }

            // Update free memory pointer (align to 32 bytes)
            mstore(0x40, and(add(currentPtr, 0x1f), not(0x1f)))

            // return the data
            mstore(add(resultsPtr, 0x20), sub(sub(currentPtr, resultsPtr), 0x40)) // data length and offset
            return(resultsPtr, sub(currentPtr, resultsPtr))
        }
    }
}
