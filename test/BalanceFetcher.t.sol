// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import "forge-std/Test.sol";
import "../src/BalanceFetcher.sol";
import "forge-std/console.sol";

contract BalanceFetcherTest is Test {
    BalanceFetcher public fetcher;

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
        vm.createSelectFork("https://1rpc.io/arb");
        fetcher = new BalanceFetcher();
    }

    function testBalanceFetching() public {
        bytes memory input = abi.encodePacked(
            uint16(4), // numTokens
            uint16(4), // numAddresses
            abi.encodePacked(users[0], users[1], users[2], users[3]),
            abi.encodePacked(tokens[0], tokens[1], tokens[2], tokens[3])
        );

        console.log("input");
        console.logBytes(input);

        uint256 gas = gasleft();

        (bool success, bytes memory data) = address(fetcher).call(input);
        console.log("Gas used:", gas - gasleft());

        require(success, "Call failed");

        console.log("Response length:", data.length);

        uint256 offset = 0;
        while (offset < data.length) {
            console.log("Current offset:", offset);

            // Read user address and count
            bytes32 userData;
            assembly {
                userData := mload(add(data, add(32, offset)))
            }
            address user = address(uint160(uint256(userData) >> 96));
            uint96 count = uint96(uint256(userData) & 0xffffffffffffffffffffffff);

            console.log("User:", user);
            console.log("Number of non-zero balances:", count);

            // Read balances
            for (uint256 i = 0; i < count; i++) {
                offset += 32;
                console.log("Balance offset:", offset);

                bytes32 balanceData;
                assembly {
                    balanceData := mload(add(data, add(32, offset)))
                }
                address token = address(uint160(uint256(balanceData) >> 96));
                uint96 balance = uint96(uint256(balanceData) & 0xffffffffffffffffffffffff);

                console.log("  Token:", token);
                console.log("  Balance:", balance);

                // Verify balance
                (bool success, bytes memory data) =
                    address(token).call(abi.encodeWithSignature("balanceOf(address)", user));
                require(success, "Call failed");
                uint256 actualBalance = abi.decode(data, (uint256));
                assertEq(balance, actualBalance, "Balance mismatch");
            }
            offset += 32;
            console.log("Next user offset:", offset);
        }
    }
}
