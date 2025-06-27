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

// Compound V3 Interfaces
interface IComet {
    function supply(address asset, uint256 amount) external;
    function withdraw(address asset, uint256 amount) external;
    function balanceOf(address account) external view returns (uint256);
    function borrowBalanceOf(address account) external view returns (uint256);
    function collateralBalanceOf(address account, address asset) external view returns (uint128);
    function baseToken() external view returns (address);
    function numAssets() external view returns (uint8);
    function getAssetInfo(uint8 i) external view returns (AssetInfo memory);
}

struct AssetInfo {
    uint8 offset;
    address asset;
    address priceFeed;
    uint64 scale;
    uint64 borrowCollateralFactor;
    uint64 liquidateCollateralFactor;
    uint64 liquidationFactor;
    uint128 supplyCap;
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
    address public constant ETH_WBTC = 0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599;

    // Compound V2 contracts
    address public constant COMPOUND_COMPTROLLER = 0x3d9819210A31b4961b30EF54bE2aeD79B9c9Cd3B;
    address public constant CUSDC = 0x39AA39c021dfbaE8faC545936693aC917d5E7563;
    address public constant CUSDT = 0xf650C3d88D12dB855b8bf7D11Be6C55A4e07dCC9;
    address public constant CDAI = 0x5d3a536E4D6DbD6114cc1Ead35777bAB948E3643;
    address public constant CETH = 0x4Ddc2D193948926D02f9B1fE9e1daa0718270ED5;

    // Compound V3 Eth mainnet
    address public constant COMET_USDC = 0xc3d688B66703497DAA19211EEdff47f25384cdc3;
    address public constant COMET_WETH = 0xA17581A9E3356d9A858b789D68B4d866e593aE94;

    // Fork IDs
    uint8 public constant AAVE_V2_FORK = 0;
    uint8 public constant AAVE_V3_FORK = 0;
    uint8 public constant AVALON_FORK = 1;
    uint8 public constant COMP_V2_FORK = 0;
    uint8 public constant COMP_V3_FORK = 0;

    uint8 public constant COMP_V2_LENDER = 2;
    uint8 public constant COMP_V3_LENDER = 3;

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

    function depositToAave() internal {
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
        deal(ETH_USDC, user, 100000e6);
        deal(ETH_USDT, user, 100000e6);
        deal(ETH_DAI, user, 100000e18);
        deal(ETH_WBTC, user, 100e8);
        vm.deal(user, 100 ether);
    }

    function testSingleLenderAaveV3() public {
        depositToAave();
        bytes memory input = abi.encodePacked(user, uint8(1), uint8(AAVE_V3_FORK), AAVE_V3_POOL);
        input = abi.encodePacked(uint16(input.length), input);

        console.log("Input");
        console.logBytes(input);

        uint256 gas = gasleft();
        (bool success, bytes memory data) = address(fetcher).call(abi.encodeWithSignature("bal(bytes)", input));
        console.log("Gas used:", gas - gasleft());

        assertTrue(success, "Call should succeed");
        console.log("Response length:", data.length);
        console.log("Response");
        console.logBytes(data);

        _verifyResponse(data, true, false);
    }

    function testAaveV3WithBorrow() public {
        depositToAave();

        vm.startPrank(user);
        IAavePool(AAVE_V3_POOL).borrow(USDC, 100e6, 2, 0, user);
        vm.stopPrank();

        bytes memory input = abi.encodePacked(user, uint8(1), uint8(AAVE_V3_FORK), AAVE_V3_POOL);
        input = abi.encodePacked(uint16(input.length), input);

        console.log("Input");
        console.logBytes(input);

        uint256 gas = gasleft();
        (bool success, bytes memory data) = address(fetcher).call(abi.encodeWithSignature("bal(bytes)", input));
        console.log("Gas used:", gas - gasleft());

        console.log("Response length:", data.length);
        console.log("Response");
        console.logBytes(data);

        _verifyResponse(data, true, true);
    }

    function _verifyResponse(bytes memory data, bool expectedCollateral, bool expectedDebt) internal pure {
        // Decode the response
        // Format: offset(32) + length(32) + blockNumber(8) + results(4*n)

        require(data.length >= 72, "Response too short - missing header");

        uint256 offset;
        uint256 length;
        uint64 blockNumber;

        assembly {
            offset := mload(add(data, 0x20))
            length := mload(add(data, 0x40))
            blockNumber := shr(192, mload(add(data, 0x60)))
        }

        require(offset == 0x20, "Invalid offset in response");

        uint256 expectedMinLength = 8;
        if (expectedCollateral || expectedDebt) {
            expectedMinLength += 4;
        }

        require(length >= expectedMinLength, "Response length doesn't match expectations");

        if (!expectedCollateral && !expectedDebt) {
            require(length == 8, "Expected no positions but got some");
            return;
        }

        require(length >= 12, "Expected positions but response too short");
        require((length - 8) % 4 == 0, "Invalid result data length - not multiple of 4");

        uint32 result;
        assembly {
            result := shr(224, mload(add(data, 0x68))) // First result starts after blockNumber
        }

        // Decode result: lenderId (1byte) | forkId (1byte) | hasCollateral/hasPosition (1byte) | hasDebt (1byte)
        uint8 lenderId = uint8(result >> 24);
        uint8 forkId = uint8((result >> 16) & 0xFF);
        bool hasCollateral = ((result >> 8) & 0xFF) != 0;
        bool hasDebt = (result & 0xFF) != 0;

        require(hasCollateral == expectedCollateral, "Collateral flag mismatch");
        require(hasDebt == expectedDebt, "Debt flag mismatch");

        require(lenderId <= 3, "Invalid lender ID");
        require(forkId <= 1, "Invalid fork ID");
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

        _verifyResponse(data, false, false);
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
        _verifyResponse(data, true, false);
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
        _verifyResponse(data, true, true); // hasCollateral=true, hasDebt=true
    }

    function testCompoundV3NoPositions() public {
        prepareEthFork();

        bytes memory input = abi.encodePacked(user, uint8(COMP_V3_LENDER), uint8(COMP_V3_FORK), COMET_USDC);
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

        // Verify the response - no positions expected
        _verifyResponse(data, false, false);
    }

    function testCompoundV3WithBaseSupplyOnly() public {
        prepareEthFork();

        vm.startPrank(user);

        // Supply USDC to Compound V3 (base asset)
        IERC20(ETH_USDC).approve(COMET_USDC, type(uint256).max);
        IComet(COMET_USDC).supply(ETH_USDC, 5000e6);

        vm.stopPrank();

        // Test the fetcher
        bytes memory input = abi.encodePacked(user, uint8(COMP_V3_LENDER), uint8(COMP_V3_FORK), COMET_USDC);
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

        // Decode and verify the response - should have position but no debt
        _verifyResponse(data, true, false);
    }

    function testCompoundV3WithCollateralOnly() public {
        prepareEthFork();

        vm.startPrank(user);

        // Supply WBTC as collateral to USDC market
        IERC20(ETH_WBTC).approve(COMET_USDC, type(uint256).max);
        IComet(COMET_USDC).supply(ETH_WBTC, 1e8);

        vm.stopPrank();

        // Test the fetcher
        bytes memory input = abi.encodePacked(user, uint8(COMP_V3_LENDER), uint8(COMP_V3_FORK), COMET_USDC);
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

        // Decode and verify the response - should have collateral but no debt
        _verifyResponse(data, true, false);
    }

    function testCompoundV3WithCollateralAndDebt() public {
        prepareEthFork();

        vm.startPrank(user);

        // Supply WBTC as collateral
        IERC20(ETH_WBTC).approve(COMET_USDC, type(uint256).max);
        IComet(COMET_USDC).supply(ETH_WBTC, 1e8);

        // Borrow USDC (base asset) against WBTC collateral
        IComet(COMET_USDC).withdraw(ETH_USDC, 2000e6);

        vm.stopPrank();

        // Test the fetcher
        bytes memory input = abi.encodePacked(user, uint8(COMP_V3_LENDER), uint8(COMP_V3_FORK), COMET_USDC);
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

        // Decode and verify the response - should have both collateral and debt
        _verifyResponse(data, true, true);
    }

    function testCompoundV3WithMixedPositions() public {
        prepareEthFork();

        vm.startPrank(user);

        // Supply base asset (USDC) - this counts as position but not collateral
        IERC20(ETH_USDC).approve(COMET_USDC, type(uint256).max);
        IComet(COMET_USDC).supply(ETH_USDC, 3000e6);

        // Supply WBTC as collateral
        IERC20(ETH_WBTC).approve(COMET_USDC, type(uint256).max);
        IComet(COMET_USDC).supply(ETH_WBTC, 1e8);

        // Borrow some USDC against WBTC collateral
        IComet(COMET_USDC).withdraw(ETH_USDC, 5000e6);

        vm.stopPrank();

        // Test the fetcher
        bytes memory input = abi.encodePacked(user, uint8(COMP_V3_LENDER), uint8(COMP_V3_FORK), COMET_USDC);
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

        // Should have position (from both base supply and collateral) and debt
        _verifyResponse(data, true, true);
    }

    function testMultipleProtocolsInOneCall() public {
        prepareEthFork();

        vm.startPrank(user);

        IERC20(ETH_USDC).approve(CUSDC, type(uint256).max);
        IERC20(ETH_DAI).approve(CDAI, type(uint256).max);

        ICToken(CUSDC).mint(3000e6);
        ICToken(CDAI).mint(2000e18);
        ICEther(CETH).mint{value: 2 ether}();

        address[] memory markets = new address[](3);
        markets[0] = CUSDC;
        markets[1] = CDAI;
        markets[2] = CETH;
        IComptroller(COMPOUND_COMPTROLLER).enterMarkets(markets);

        ICToken(CUSDC).borrow(500e6);

        IERC20(ETH_WBTC).approve(COMET_USDC, type(uint256).max);
        IComet(COMET_USDC).supply(ETH_WBTC, 0.5e8);
        IComet(COMET_USDC).withdraw(ETH_USDC, 1000e6);

        vm.stopPrank();

        bytes memory input = abi.encodePacked(
            user, //
            uint8(COMP_V2_LENDER),
            uint8(COMP_V2_FORK),
            COMPOUND_COMPTROLLER,
            uint8(COMP_V3_LENDER),
            uint8(COMP_V3_FORK),
            COMET_USDC
        );
        input = abi.encodePacked(uint16(input.length), input);

        console.log("Input for multiple protocols");
        console.logBytes(input);

        uint256 gas = gasleft();
        (bool success, bytes memory data) = address(fetcher).call(abi.encodeWithSignature("bal(bytes)", input));
        uint256 gasUsed = gas - gasleft();

        assertTrue(success, "Call should succeed");
        console.log("Gas used:", gasUsed);
        console.log("Response length:", data.length);
        console.log("Response");
        console.logBytes(data);

        _verifyMultiResponse(data);
    }

    function _verifyMultiResponse(bytes memory data) internal pure {
        // For multiple protocols, we expect both to have positions (collateral and debt)
        // since the test sets up positions in both Compound V2 and V3

        require(data.length >= 72, "Response too short - missing header");

        uint256 offset;
        uint256 length;
        uint64 blockNumber;

        assembly {
            offset := mload(add(data, 0x20))
            length := mload(add(data, 0x40))
            blockNumber := shr(192, mload(add(data, 0x60)))
        }

        require(offset == 0x20, "Invalid offset in response");
        require(length >= 16, "Expected at least 2 protocol results");
        require((length - 8) % 4 == 0, "Invalid result data length - not multiple of 4");

        uint256 numResults = (length - 8) / 4;
        require(numResults >= 2, "Expected results from multiple protocols");

        bool[4] memory seenLenders;

        for (uint256 i = 0; i < numResults; i++) {
            uint32 result;
            assembly {
                result := shr(224, mload(add(data, add(0x68, mul(i, 4)))))
            }

            // Decode result: lenderId (1byte) | forkId (1byte) | hasCollateral/hasPosition (1byte) | hasDebt (1byte)
            uint8 lenderId = uint8(result >> 24);
            uint8 forkId = uint8((result >> 16) & 0xFF);
            bool hasCollateral = ((result >> 8) & 0xFF) != 0;
            bool hasDebt = (result & 0xFF) != 0;

            require(lenderId <= 3, "Invalid lender ID");
            require(forkId <= 1, "Invalid fork ID");
            require(!seenLenders[lenderId], "Duplicate lender in results");
            seenLenders[lenderId] = true;

            require(hasCollateral || hasDebt, "Expected positions for each protocol");
        }

        require(seenLenders[COMP_V2_LENDER], "Missing Compound V2 result");
        require(seenLenders[COMP_V3_LENDER], "Missing Compound V3 result");
    }
}
