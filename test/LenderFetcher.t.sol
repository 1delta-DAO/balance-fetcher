// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";
import {LenderFetcher} from "../src/LenderFetcher.sol";
import {console} from "forge-std/console.sol";

interface IERC20 {
    function transfer(address to, uint256 amount) external returns (bool);
    function transferFrom(address from, address to, uint256 amount) external returns (bool);
    function approve(address spender, uint256 amount) external returns (bool);
    function balanceOf(address account) external view returns (uint256);
    function decimals() external view returns (uint8);
}

interface IAavePool {
    function supply(address asset, uint256 amount, address onBehalfOf, uint16 referralCode) external;
    function borrow(address asset, uint256 amount, uint256 interestRateMode, uint16 referralCode, address onBehalfOf)
        external;
    function getUserAccountData(address user)
        external
        view
        returns (
            uint256 totalCollateralBase,
            uint256 totalDebtBase,
            uint256 availableBorrowsBase,
            uint256 currentLiquidationThreshold,
            uint256 ltv,
            uint256 healthFactor
        );
}

contract LenderFetcherTest is Test {
    LenderFetcher public fetcher;

    // Test user
    address public testUser = 0x1De17A0000000000000000000000000000000000;

    address public constant USDC = 0xaf88d065e77c8cC2239327C5EDb3A432268e5831;
    address public constant USDT = 0xFd086bC7CD5C481DCC9C85ebE478A1C0b69FCbb9;
    address public constant WETH = 0x82aF49447D8a07e3bd95BD0d56f35241523fBab1;

    address public constant AAVE_V3_POOL = 0x794a61358D6845594F94dc1DB02A252b5b4814aD;
    address public constant AVALON_POOL = 0xe1ee45DB12ac98d16F1342a03c93673d74527b55;

    uint8 public constant AAVE_V2_FORK = 0;
    uint8 public constant AAVE_V3_FORK = 0;
    uint8 public constant AVALON_FORK = 1;

    function setUp() public {
        vm.createSelectFork("https://1rpc.io/arb");

        fetcher = new LenderFetcher();
    }

    function depositToProtocols() internal {
        deal(USDC, testUser, 2000e6);
        deal(USDT, testUser, 2000e6);
        deal(WETH, testUser, 2e18);
        vm.startPrank(testUser);
        IERC20(USDC).approve(AAVE_V3_POOL, type(uint256).max);
        IERC20(USDT).approve(AAVE_V3_POOL, type(uint256).max);
        IERC20(WETH).approve(AAVE_V3_POOL, type(uint256).max);
        IERC20(USDC).approve(AVALON_POOL, type(uint256).max);
        IERC20(USDT).approve(AVALON_POOL, type(uint256).max);
        IERC20(WETH).approve(AVALON_POOL, type(uint256).max);

        IAavePool(AAVE_V3_POOL).supply(USDC, 1000e6, testUser, 0);
        IAavePool(AAVE_V3_POOL).supply(USDT, 1000e6, testUser, 0);
        IAavePool(AAVE_V3_POOL).supply(WETH, 1e18, testUser, 0);
        IAavePool(AVALON_POOL).supply(USDC, 1000e6, testUser, 0);
        IAavePool(AVALON_POOL).supply(USDT, 1000e6, testUser, 0);
        IAavePool(AVALON_POOL).supply(WETH, 1e18, testUser, 0);
        vm.stopPrank();
    }

    function testSingleLenderAaveV3() public {
        depositToProtocols();
        bytes memory input = abi.encodePacked(testUser, uint8(AAVE_V3_FORK), uint8(0), AAVE_V3_POOL);
        input = abi.encodePacked(uint16(input.length), input);

        console.log("Input");
        console.logBytes(input);

        uint256 gas = gasleft();
        (bool success, bytes memory data) = address(fetcher).call(abi.encodeWithSignature("bal(bytes)", input));
        console.log("Gas used:", gas - gasleft());

        console.log("Response length:", data.length);
        console.log("Response");
        console.logBytes(data);
    }
}
