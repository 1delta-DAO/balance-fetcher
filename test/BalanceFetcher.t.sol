// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import "forge-std/Test.sol";
import "../src/BalanceFetcher.sol";
import "forge-std/console.sol";

interface IBal {
    function bal(bytes calldata data) external view returns (bytes memory);
}

contract BalanceFetcherTest is Test {
    IBal public fetcher;

    // Test addresses
    address[] public users = [
        0x91ae002a960e63Ccb0E5bDE83A8C13E51e1cB91A,
        0xdFF70A71618739f4b8C81B11254BcE855D02496B,
        0x0eb2d44F6717D8146B6Bd6B229A15F0803e5B244,
        0xB1026b8e7276e7AC75410F1fcbbe21796e8f7526
    ];

    address[] public tokens = [
        0xFd086bC7CD5C481DCC9C85ebE478A1C0b69FCbb9, // USDT
        0xaf88d065e77c8cC2239327C5EDb3A432268e5831, // USDC
        0x2f2a2543B76A4166549F7aaB2e75Bef0aefC5B0f, // WBTC
        0x82aF49447D8a07e3bd95BD0d56f35241523fBab1 // WETH
    ];

    function setUp() public {
        vm.createSelectFork("wss://arbitrum-one-rpc.publicnode.com");
        fetcher = IBal(address(new BalanceFetcher()));
    }

    function testBalanceFetching_multiple_users() public {
        bytes memory input = abi.encodePacked(
            uint16(4), // numTokens
            uint16(4), // numAddresses
            abi.encodePacked(users[0], users[1], users[2], users[3]),
            abi.encodePacked(tokens[0], tokens[1], tokens[2], tokens[3])
        );

        console.log("input");
        console.logBytes(input);

        uint256 gas = gasleft();

        bytes memory data = fetcher.bal(input);

        console.log("Gas used:", gas - gasleft());
        console.log("Response length:", data.length);

        uint256 offset = 8; //skip block number
        while (offset < data.length) {
            console.log("Current offset:", offset);

            uint16 userIndex;
            uint16 count;
            assembly {
                let userData := mload(add(data, add(32, offset)))
                userIndex := shr(240, userData) // Extract top 2 bytes
                count := and(shr(224, userData), 0xffff) // Extract next 2 bytes
            }

            console.log("User index:", userIndex);
            console.log("User address:", users[userIndex]);
            console.log("Number of non-zero balances:", count);

            // Move to balance data
            offset += 4;

            // Read balances
            for (uint256 i = 0; i < count; i++) {
                console.log("Balance offset:", offset);

                uint16 tokenIndex;
                uint112 tokenBalance;
                assembly {
                    let balanceData := mload(add(data, add(32, offset)))
                    tokenIndex := shr(240, balanceData) // Extract top 2 bytes
                    tokenBalance := and(shr(128, balanceData), 0xffffffffffffffffffffffffffff) // Extract next 14 bytes
                }

                console.log("Token index:", tokenIndex);
                console.log("Token address:", tokens[tokenIndex]);
                console.log("Balance:", tokenBalance);

                // Verify balance
                (bool balanceCallSuccess, bytes memory balanceData) =
                    address(tokens[tokenIndex]).call(abi.encodeWithSignature("balanceOf(address)", users[userIndex]));
                require(balanceCallSuccess, "Balance call failed");
                uint256 actualBalance = abi.decode(balanceData, (uint256));
                console.log("Actual balance:", actualBalance);
                assertEq(tokenBalance, actualBalance, "Balance mismatch");

                offset += 16;
            }

            console.log("Next user offset:", offset);
        }
    }

    function test_revertOnValue() public {
        vm.expectRevert(BalanceFetcher.NoValue.selector);
        (bool s, bytes memory data) = address(fetcher).call(abi.encodeWithSelector(fetcher.bal.selector, new bytes(0)));
    }

    function testBalanceFetching_single_user() public {
        bytes memory input = abi.encodePacked(
            uint16(4), // numTokens
            uint16(1), // numAddresses
            abi.encodePacked(users[0]),
            abi.encodePacked(tokens[0], tokens[1], tokens[2], tokens[3])
        );

        console.log("input");
        console.logBytes(input);

        uint256 gas = gasleft();

        (bool s, bytes memory data) = address(fetcher).call(abi.encodeWithSelector(fetcher.bal.selector, input));
        // bytes memory data = fetcher.bal(input);
        console.log("data");
        console.logBytes(data);

        console.log("Gas used:", gas - gasleft());
        console.log("Response length:", data.length);

        uint256 offset = 8; // skip block number
        while (offset < data.length) {
            console.log("Current offset:", offset);

            uint16 userIndex;
            uint16 count;
            assembly {
                let userData := mload(add(data, add(32, offset)))
                userIndex := shr(240, userData) // Extract top 2 bytes
                count := and(shr(224, userData), 0xffff) // Extract next 2 bytes
            }

            console.log("User index:", userIndex);
            console.log("User address:", users[userIndex]);
            console.log("Number of non-zero balances:", count);

            offset += 4;

            // Read balances
            for (uint256 i = 0; i < count; i++) {
                console.log("Balance offset:", offset);

                uint16 tokenIndex;
                uint112 tokenBalance;
                assembly {
                    let balanceData := mload(add(data, add(32, offset)))
                    tokenIndex := shr(240, balanceData) // Extract top 2 bytes
                    tokenBalance := and(shr(128, balanceData), 0xffffffffffffffffffffffffffff) // Extract next 14 bytes
                }

                console.log("  Token index:", tokenIndex);
                console.log("  Token address:", tokens[tokenIndex]);
                console.log("  Balance:", tokenBalance);

                // Verify balance
                (bool balanceCallSuccess, bytes memory balanceData) =
                    address(tokens[tokenIndex]).call(abi.encodeWithSignature("balanceOf(address)", users[userIndex]));
                require(balanceCallSuccess, "Balance call failed");
                uint256 actualBalance = abi.decode(balanceData, (uint256));
                assertEq(tokenBalance, actualBalance, "Balance mismatch");

                offset += 16;
            }
            console.log("Next user offset:", offset);
        }
    }

    function testNativeBalanceFetching() public {
        uint256 ethAmount = 5 ether;
        vm.deal(users[0], ethAmount);

        bytes memory input = abi.encodePacked(
            uint16(1),
            uint16(1),
            abi.encodePacked(users[0]),
            abi.encodePacked(address(0)) // native
        );

        console.log("Expected ETH balance:", ethAmount);

        uint256 gas = gasleft();
        bytes memory data = fetcher.bal(input);

        console.log("Gas used:", gas - gasleft());
        console.log("Response length:", data.length);

        uint256 offset = 8; // skip block number

        // Should have at least one user entry
        require(offset < data.length, "No data returned");

        // Read user prefix (4 bytes)
        uint16 userIndex;
        uint16 count;
        assembly {
            let userData := mload(add(data, add(32, offset)))
            userIndex := shr(240, userData) // Extract top 2 bytes
            count := and(shr(224, userData), 0xffff) // Extract next 2 bytes
        }

        console.log("User index:", userIndex);
        assertEq(userIndex, 0, "User index should be 0");
        console.log("Number of non-zero balances:", count);
        assertEq(count, 1, "Should have 1 non-zero balance (native ETH)");

        offset += 4;

        // Read the native balance (16 bytes)
        uint16 tokenIndex;
        uint112 tokenBalance;
        assembly {
            let balanceData := mload(add(data, add(32, offset)))
            tokenIndex := shr(240, balanceData) // Extract top 2 bytes
            tokenBalance := and(shr(128, balanceData), 0xffffffffffffffffffffffffffff) // Extract next 14 bytes
        }

        console.log("Token index:", tokenIndex);
        assertEq(tokenIndex, 0, "Token index should be 0 (native ETH)");
        console.log("Returned ETH balance:", tokenBalance);

        // The contract should return the contract's ETH balance (which should be ethAmount after the call)
        assertEq(tokenBalance, ethAmount, "Native balance mismatch");
    }

    function testBlockNumberReturned() public {
        bytes memory input = abi.encodePacked(
            uint16(1), // numTokens
            uint16(1), // numAddresses
            abi.encodePacked(users[0]),
            abi.encodePacked(tokens[0])
        );

        bytes memory data = fetcher.bal(input);

        // Extract block number from the first 8 bytes of response
        uint256 returnedBlockNumber;
        assembly {
            returnedBlockNumber := mload(add(data, 32))
            returnedBlockNumber := shr(192, returnedBlockNumber) // Extract first 8 bytes (64 bits)
        }

        console.log("Returned block number:", returnedBlockNumber);
        assertEq(returnedBlockNumber, block.number, "Block number should match current block");
        console.log("Block number test passed");
    }

    function testRevertZeroTokens() public {
        bytes memory input = abi.encodePacked(
            uint16(0), // numTokens
            uint16(4), // numAddresses
            abi.encodePacked(users[0], users[1], users[2], users[3]),
            abi.encodePacked(tokens[0], tokens[1], tokens[2], tokens[3])
        );

        vm.expectRevert(BalanceFetcher.InvalidInputLength.selector);
        fetcher.bal(input);
    }

    function testRevertZeroAddresses() public {
        bytes memory input = abi.encodePacked(
            uint16(4), // numTokens
            uint16(0), // numAddresses
            abi.encodePacked(users[0], users[1], users[2], users[3]),
            abi.encodePacked(tokens[0], tokens[1], tokens[2], tokens[3])
        );

        vm.expectRevert(BalanceFetcher.InvalidInputLength.selector);
        fetcher.bal(input);
    }

    function testRevertIncorrectInputLength() public {
        // Missing one token address
        bytes memory input = abi.encodePacked(
            uint16(4), // numTokens
            uint16(4), // numAddresses
            abi.encodePacked(users[0], users[1], users[2], users[3]),
            abi.encodePacked(tokens[0], tokens[1], tokens[2]) // Only 3 tokens instead of 4
        );

        vm.expectRevert(BalanceFetcher.InvalidInputLength.selector);
        fetcher.bal(input);
    }

    function testRevertIncorrectInputLength2() public {
        bytes memory input = abi.encodePacked(
            uint16(4), // numTokens
            uint16(4), // numAddresses
            abi.encodePacked(users[0], users[1], users[2]), // Only 3 users instead of 4
            abi.encodePacked(tokens[0], tokens[1], tokens[2], tokens[3])
        );

        vm.expectRevert(BalanceFetcher.InvalidInputLength.selector);
        fetcher.bal(input);
    }

    function testRevertEmptyInput() public {
        bytes memory input = "";
        vm.expectRevert(BalanceFetcher.InvalidInputLength.selector);
        fetcher.bal(input);
    }

    function testRevertTooShortInput() public {
        // Only sending the first 2 bytes (numTokens)
        bytes memory input = abi.encodePacked(uint16(4));
        vm.expectRevert(BalanceFetcher.InvalidInputLength.selector);
        fetcher.bal(input);
    }
}
