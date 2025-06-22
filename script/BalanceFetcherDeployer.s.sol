// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Script} from "forge-std/Script.sol";
import {BalanceFetcher} from "../src/BalanceFetcher.sol";
import {console} from "forge-std/console.sol";
import {StdStyle} from "forge-std/StdStyle.sol";

/**
 * @dev How to deploy
 *
 * Key management:
 * 1. Import key:
 *    cast wallet import deployer --interactive
 *
 * 2. Deploy:
 *    forge script script/BalanceFetcherDeployer.s.sol --rpc-url $RPC_URL --account deployer --broadcast --verify
 * @Note: etherscan (or others) api key should be added to the toml file or passed as an argument to forge script
 */
contract BalanceFetcherDeployer is Script {
    address internal constant FACTORY = 0x16c4Dc0f662E2bEceC91fC5E7aeeC6a25684698A;
    bytes32 public constant DEFAULT_SALT = keccak256("BalanceFetcher_v1.0.0");
    bytes public constant creationCode = type(BalanceFetcher).creationCode;

    struct NetworkConfig {
        string name;
        uint256 chainId;
    }

    struct DeploymentConfig {
        address deployer;
        BalanceFetcher balanceFetcher;
        address predictedBalanceFetcherAddress;
        uint256 deploymentBlock;
        bytes32 deploymentTx;
    }

    function run() public returns (DeploymentConfig memory config) {
        console.log(StdStyle.bold(StdStyle.green("BALANCE FETCHER DEPLOYER")));

        NetworkConfig memory networkConfig = getNetworkConfig();

        console.log(StdStyle.blue("BalanceFetcher Deployment"));
        console.log(StdStyle.blue("Network:"), networkConfig.name);
        console.log(StdStyle.blue("Chain ID:"), networkConfig.chainId);
        console.log(StdStyle.blue("Deployer:"), msg.sender);
        console.log(StdStyle.blue("Deployer Balance:"), msg.sender.balance / 1e18, "ETH");
        console.log(StdStyle.blue("Salt:"), vm.toString(DEFAULT_SALT));

        require(msg.sender != address(0), "Invalid deployer address");
        require(msg.sender.balance > 0, "Insufficient balance for deployment");
        IF factory = IF(FACTORY);

        vm.startBroadcast();

        address predictedAddress = factory.computeAddress(DEFAULT_SALT, keccak256(creationCode));
        console.log(StdStyle.blue("Predicted address:"), predictedAddress);

        // Check if already deployed
        if (predictedAddress.code.length > 0) {
            console.log(StdStyle.yellow("BalanceFetcher already deployed"));
            vm.stopBroadcast();

            config = DeploymentConfig({
                deployer: msg.sender,
                balanceFetcher: BalanceFetcher(payable(predictedAddress)),
                predictedBalanceFetcherAddress: predictedAddress,
                deploymentBlock: block.number,
                deploymentTx: bytes32(0)
            });

            return config;
        }
        console.log(StdStyle.yellow("Deploying BalanceFetcher"));
        address balanceFetcherAddress = factory.deploy(DEFAULT_SALT, creationCode);

        vm.stopBroadcast();

        require(balanceFetcherAddress == predictedAddress, "Address mismatch: deployment failed");

        config = DeploymentConfig({
            deployer: msg.sender,
            balanceFetcher: BalanceFetcher(payable(balanceFetcherAddress)),
            predictedBalanceFetcherAddress: predictedAddress,
            deploymentBlock: block.number,
            deploymentTx: bytes32(0)
        });

        console.log(StdStyle.green("Deployment Successful"));
        console.log(StdStyle.blue("BalanceFetcher Address:"), balanceFetcherAddress);
        console.log(StdStyle.blue("Deployment Block:"), block.number);

        verifyDeployment(BalanceFetcher(payable(balanceFetcherAddress)));

        return config;
    }

    function getNetworkConfig() internal view returns (NetworkConfig memory) {
        uint256 chainId = block.chainid;

        if (chainId == 10) {
            return NetworkConfig("Optimism", 10);
        } else if (chainId == 56) {
            return NetworkConfig("BSC", 56);
        } else if (chainId == 137) {
            return NetworkConfig("Polygon", 137);
        } else if (chainId == 42161) {
            return NetworkConfig("Arbitrum One", 42161);
        } else if (chainId == 43114) {
            return NetworkConfig("Avalanche", 43114);
        } else if (chainId == 8453) {
            return NetworkConfig("Base", 8453);
        } else {
            return NetworkConfig("Unknown Network", chainId);
        }
    }

    function verifyDeployment(BalanceFetcher balanceFetcher) internal view {
        console.log(StdStyle.blue("Verifying deployment"));
        uint256 codeSize;
        address contractAddress = address(balanceFetcher);
        assembly {
            codeSize := extcodesize(contractAddress)
        }

        require(codeSize > 0, "Deployment failed");
        console.log(StdStyle.green("Contract code deployed successfully"));
        console.log(StdStyle.blue("Contract address verified:"), contractAddress);
    }
}

interface IF {
    function deploy(bytes32 salt, bytes memory bytecode) external returns (address);
    function computeAddress(bytes32 salt, bytes32 bytecodeHash) external view returns (address);
}
