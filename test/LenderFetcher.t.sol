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

// Compound V2 Interfaces
interface IComptroller {
    function getAllMarkets() external view returns (address[] memory);
    function isDeprecated(address cToken) external view returns (bool);
    function enterMarkets(address[] calldata cTokens) external returns (uint256[] memory);
    function getAccountLiquidity(address account) external view returns (uint256, uint256, uint256);
}

interface ICToken {
    function mint(uint256 mintAmount) external returns (uint256);
    function redeem(uint256 redeemTokens) external returns (uint256);
    function borrow(uint256 borrowAmount) external returns (uint256);
    function repayBorrow(uint256 repayAmount) external returns (uint256);
    function balanceOfUnderlying(address owner) external returns (uint256);
    function borrowBalanceCurrent(address account) external returns (uint256);
    function underlying() external view returns (address);
    function balanceOf(address owner) external view returns (uint256);
    function exchangeRateStored() external view returns (uint256);
}

interface ICEther {
    function mint() external payable;
    function redeem(uint256 redeemTokens) external returns (uint256);
    function borrow(uint256 borrowAmount) external returns (uint256);
    function repayBorrow() external payable;
    function balanceOfUnderlying(address owner) external returns (uint256);
    function borrowBalanceCurrent(address account) external returns (uint256);
    function balanceOf(address owner) external view returns (uint256);
    function exchangeRateStored() external view returns (uint256);
}

contract LenderFetcherTest is Test {
    LenderFetcher public fetcher;

    // Test user
    address public user = 0x1De17A0000000000000000000000000000000000;

    // Arbitrum tokens
    address public constant USDC = 0xaf88d065e77c8cC2239327C5EDb3A432268e5831;
    address public constant USDT = 0xFd086bC7CD5C481DCC9C85ebE478A1C0b69FCbb9;
    address public constant WETH = 0x82aF49447D8a07e3bd95BD0d56f35241523fBab1;

    address public constant AAVE_V3_POOL = 0x794a61358D6845594F94dc1DB02A252b5b4814aD;
    address public constant AVALON_POOL = 0xe1ee45DB12ac98d16F1342a03c93673d74527b55;

    // Ethereum mainnet tokens
    address public constant ETH_USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address public constant ETH_USDT = 0xdAC17F958D2ee523a2206206994597C13D831ec7;
    address public constant ETH_DAI = 0x6B175474E89094C44Da98b954EedeAC495271d0F;
    address public constant ETH_WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;

    // Compound V2 contracts
    address public constant COMPOUND_COMPTROLLER = 0x3d9819210A31b4961b30EF54bE2aeD79B9c9Cd3B;
    address public constant CUSDC = 0x39AA39c021dfbaE8faC545936693aC917d5E7563;
    address public constant CUSDT = 0xf650C3d88D12dB855b8bf7D11Be6C55A4e07dCC9;
    address public constant CDAI = 0x5d3a536E4D6DbD6114cc1Ead35777bAB948E3643;
    address public constant CETH = 0x4Ddc2D193948926D02f9B1fE9e1daa0718270ED5;

    // Fork IDs
    uint8 public constant AAVE_V2_FORK = 0;
    uint8 public constant AAVE_V3_FORK = 0;
    uint8 public constant AVALON_FORK = 1;
    uint8 public constant COMP_V2_FORK = 0;

    uint8 public constant COMP_V2_LENDER = 2;

    uint256 internal arbForkId;
    uint256 internal ethForkId;

    enum Fork {
        Arb,
        Eth
    }

    function setUp() public {
        arbForkId = vm.createFork("https://1rpc.io/arb");
        ethForkId = vm.createFork("https://eth-pokt.nodies.app");
    }

    function selectFork(Fork fork) internal {
        if (fork == Fork.Arb) {
            vm.selectFork(arbForkId);
        } else if (fork == Fork.Eth) {
            vm.selectFork(ethForkId);
        } else {
            revert("Invalid fork");
        }
        fetcher = new LenderFetcher();
    }

    function depositToProtocols() internal {
        // select arbitrum fork
        selectFork(Fork.Arb);

        deal(USDC, user, 2000e6);
        deal(USDT, user, 2000e6);
        deal(WETH, user, 2e18);
        vm.startPrank(user);
        IERC20(USDC).approve(AAVE_V3_POOL, type(uint256).max);
        IERC20(USDT).approve(AAVE_V3_POOL, type(uint256).max);
        IERC20(WETH).approve(AAVE_V3_POOL, type(uint256).max);
        IERC20(USDC).approve(AVALON_POOL, type(uint256).max);
        IERC20(USDT).approve(AVALON_POOL, type(uint256).max);
        IERC20(WETH).approve(AVALON_POOL, type(uint256).max);

        IAavePool(AAVE_V3_POOL).supply(USDC, 1000e6, user, 0);
        IAavePool(AAVE_V3_POOL).supply(USDT, 1000e6, user, 0);
        IAavePool(AAVE_V3_POOL).supply(WETH, 1e18, user, 0);
        IAavePool(AVALON_POOL).supply(USDC, 1000e6, user, 0);
        IAavePool(AVALON_POOL).supply(USDT, 1000e6, user, 0);
        IAavePool(AVALON_POOL).supply(WETH, 1e18, user, 0);
        vm.stopPrank();
    }

    function prepareEthFork() internal {
        selectFork(Fork.Eth);
        // fund test user with tokens
        deal(ETH_USDC, user, 10000e6);
        deal(ETH_USDT, user, 10000e6);
        deal(ETH_DAI, user, 10000e18);
        vm.deal(user, 10 ether);
    }

    function testSingleLenderAaveV3() public {
        depositToProtocols();
        bytes memory input = abi.encodePacked(user, uint8(AAVE_V3_FORK), uint8(0), AAVE_V3_POOL);
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

    function testCompoundV2NoPositions() public {
        prepareEthFork();

        bytes memory input = abi.encodePacked(user, uint8(COMP_V2_LENDER), uint8(COMP_V2_FORK), COMPOUND_COMPTROLLER);
        input = abi.encodePacked(uint16(input.length), input);

        console.log("Input");
        console.logBytes(input);

        uint256 gas = gasleft();
        (bool success, bytes memory data) = address(fetcher).call(abi.encodeWithSignature("bal(bytes)", input));
        uint256 gasUsed = gas - gasleft();

        assertTrue(success, "Call should succeed");
        console.log("Gas used:", gasUsed);
        console.log("Response length:", data.length);
        console.log("Response");
        console.logBytes(data);

        // Verify the response format
        // Expected: offset(32) + length(32) + blockNumber(8) = 72 bytes for no positions
        // Since there are no positions, only block number should be returned
        assertTrue(data.length >= 72, "Response should contain at least the header");
    }

    function testCompoundV2WithCollateralOnly() public {
        prepareEthFork();

        vm.startPrank(user);

        // approve tokens for cTokens
        IERC20(ETH_USDC).approve(CUSDC, type(uint256).max);
        IERC20(ETH_DAI).approve(CDAI, type(uint256).max);

        // supply to different markets
        ICToken(CUSDC).mint(5000e6);
        ICToken(CDAI).mint(5000e18);
        ICEther(CETH).mint{value: 5 ether}();

        // enter markets to use as collateral
        address[] memory markets = new address[](3);
        markets[0] = CUSDC;
        markets[1] = CDAI;
        markets[2] = CETH;
        IComptroller(COMPOUND_COMPTROLLER).enterMarkets(markets);

        vm.stopPrank();

        // Test the fetcher
        bytes memory input = abi.encodePacked(user, uint8(COMP_V2_LENDER), uint8(COMP_V2_FORK), COMPOUND_COMPTROLLER);
        input = abi.encodePacked(uint16(input.length), input);

        console.log("Input");
        console.logBytes(input);

        uint256 gas = gasleft();
        (bool success, bytes memory data) = address(fetcher).call(abi.encodeWithSignature("bal(bytes)", input));
        uint256 gasUsed = gas - gasleft();

        assertTrue(success, "Call should succeed");
        console.log("Gas used:", gasUsed);
        console.log("Response length:", data.length);
        console.log("Response");
        console.logBytes(data);

        // Decode and verify the response
        _verifyCompoundV2Response(data, true, false);
    }

    function testCompoundV2WithCollateralAndDebt() public {
        prepareEthFork();

        vm.startPrank(user);

        // Approve tokens for cTokens
        IERC20(ETH_USDC).approve(CUSDC, type(uint256).max);
        IERC20(ETH_DAI).approve(CDAI, type(uint256).max);

        // Supply to different markets as collateral
        ICToken(CUSDC).mint(5000e6);
        ICToken(CDAI).mint(5000e18);
        ICEther(CETH).mint{value: 5 ether}();

        // Enter markets to use as collateral
        address[] memory markets = new address[](3);
        markets[0] = CUSDC;
        markets[1] = CDAI;
        markets[2] = CETH;
        IComptroller(COMPOUND_COMPTROLLER).enterMarkets(markets);

        // Borrow against collateral
        ICToken(CUSDC).borrow(1000e6); // Borrow 1,000 USDC
        ICToken(CDAI).borrow(500e18); // Borrow 500 DAI

        vm.stopPrank();

        // Test the fetcher
        bytes memory input = abi.encodePacked(user, uint8(COMP_V2_LENDER), uint8(COMP_V2_FORK), COMPOUND_COMPTROLLER);
        input = abi.encodePacked(uint16(input.length), input);

        console.log("Input");
        console.logBytes(input);

        uint256 gas = gasleft();
        (bool success, bytes memory data) = address(fetcher).call(abi.encodeWithSignature("bal(bytes)", input));
        uint256 gasUsed = gas - gasleft();

        assertTrue(success, "Call should succeed");
        console.log("Gas used:", gasUsed);
        console.log("Response length:", data.length);
        console.log("Response");
        console.logBytes(data);

        // Decode and verify the response
        _verifyCompoundV2Response(data, true, true); // hasCollateral=true, hasDebt=true
    }

    function _verifyCompoundV2Response(bytes memory data, bool expectedCollateral, bool expectedDebt) internal view {
        // Decode the response
        // Format: offset(32) + length(32) + blockNumber(8) + results(32*n)

        // Skip to the actual data after ABI encoding
        uint256 offset = abi.decode(data, (uint256));
        bytes memory actualData = abi.decode(data, (bytes));

        console.log("Verifying response...");
        console.log("Expected collateral:", expectedCollateral);
        console.log("Expected debt:", expectedDebt);

        if (!expectedCollateral && !expectedDebt) {
            // Should only contain block number (8 bytes)
            assertEq(actualData.length, 8, "No positions should return only block number");
            return;
        }

        // Should contain: blockNumber(8) + result(32) = 40 bytes
        assertEq(actualData.length, 40, "Response should contain block number and one result");

        // Extract the result (last 32 bytes)
        bytes32 result;
        assembly {
            result := mload(add(actualData, 40)) // 8 bytes block number + 32 bytes result
        }

        // Decode the result
        // Format: lenderId (1byte) | forkId (1byte) | hasCollateral (15bytes) | hasDebt (15bytes)
        uint8 lenderId = uint8(result[0]);
        uint8 forkId = uint8(result[1]);
        uint256 hasCollateral = uint256(result >> 120) & ((1 << 120) - 1);
        uint256 hasDebt = uint256(result) & ((1 << 120) - 1);

        console.log("Decoded lenderId:", lenderId);
        console.log("Decoded forkId:", forkId);
        console.log("Decoded hasCollateral:", hasCollateral);
        console.log("Decoded hasDebt:", hasDebt);

        assertEq(lenderId, COMP_V2_LENDER, "Lender ID should match");
        assertEq(forkId, COMP_V2_FORK, "Fork ID should match");
        assertEq(hasCollateral > 0, expectedCollateral, "Collateral flag should match expectation");
        assertEq(hasDebt > 0, expectedDebt, "Debt flag should match expectation");
    }
}
