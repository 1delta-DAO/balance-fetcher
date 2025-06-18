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
 */
contract BalanceFetcherDeployer is Script {
    struct NetworkConfig {
        string name;
        uint256 chainId;
    }

    struct DeploymentConfig {
        address deployer;
        BalanceFetcher balanceFetcher;
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

        require(msg.sender != address(0), "Invalid deployer address");
        require(msg.sender.balance > 0, "Insufficient balance for deployment");

        vm.startBroadcast();

        console.log(StdStyle.yellow("Deploying BalanceFetcher"));
        BalanceFetcher balanceFetcher = new BalanceFetcher();

        vm.stopBroadcast();

        config = DeploymentConfig({
            deployer: msg.sender,
            balanceFetcher: balanceFetcher,
            deploymentBlock: block.number,
            deploymentTx: bytes32(0)
        });

        console.log(StdStyle.green("Deployment Successful"));
        console.log(StdStyle.blue("BalanceFetcher Address:"), address(balanceFetcher));
        console.log(StdStyle.blue("Deployment Block:"), block.number);
        console.log(StdStyle.blue("Gas Used: Check transaction receipt"));

        verifyDeployment(balanceFetcher);

        return config;
    }

    function getNetworkConfig() internal view returns (NetworkConfig memory) {
        uint256 chainId = block.chainid;

        if (chainId == 8453) {
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
