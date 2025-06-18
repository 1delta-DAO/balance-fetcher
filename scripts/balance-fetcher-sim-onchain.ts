import {
  createPublicClient,
  encodePacked,
  hexToBytes,
  http,
  parseAbi,
} from "viem";
import { parseBalanceData, PRIVATE_KEY } from "./Utils";
import { privateKeyToAccount } from "viem/accounts";
import { base } from "viem/chains";

const CONTRACT_ADDRESS = "0x474041E305c269f6973FCF2A6eDdb2fB717a23E0";

const USERS = [
  "0x20FE51A9229EEf2cF8Ad9E89d91CAb9312cF3b7A",
  "0xC882b111A75C0c657fC507C04FbFcD2cC984F071",
  "0x97b9D2102A9a65A26E1EE82D59e42d1B73B68689",
  "0xBaeD383EDE0e5d9d72430661f3285DAa77E9439F",
] as const;

const TOKENS = [
  "0x0555E30da8f98308EdB960aa94C0Db47230d2B9c",
  "0x833589fcd6edb6e08f4c7c32d4f71b54bda02913",
  "0x4200000000000000000000000000000000000006",
  "0x820c137fa70c8691f0e44dc420a5e53c168921dc",
] as const;

async function main() {
  try {
    const account = privateKeyToAccount(PRIVATE_KEY);
    const publicClient = createPublicClient({
      chain: base,
      transport: http("https://base.llamarpc.com"),
    });
    console.log(`BalanceFetcher deployed at: ${CONTRACT_ADDRESS}`);

    const input =
      encodePacked(
        ["uint16", "uint16"],
        [4, 4] // numTokens, numAddresses
      ) +
      encodePacked(["address", "address", "address", "address"], USERS).slice(
        2
      ) +
      encodePacked(["address", "address", "address", "address"], TOKENS).slice(
        2
      );

    console.log(`\nInput data (${input.length / 2 - 1} bytes):`);
    console.log(`Input: ${input}`);

    const BALANCE_FETCHER_ABI = parseAbi([
      "function bal(bytes) returns (bytes)",
      "error InvalidInputLength()",
    ]);

    const simulation = await publicClient.simulateContract({
      account: account.address,
      address: CONTRACT_ADDRESS,
      abi: BALANCE_FETCHER_ABI,
      functionName: "bal",
      args: [input as `0x${string}`],
    });

    console.log("Simulation successful!");

    if (!simulation) {
      throw new Error("No data returned from simulation");
    }

    console.log(`Response: ${simulation}`);

    const responseBytes = hexToBytes(simulation.result);
    parseBalanceData(responseBytes);

    console.log("simulateContract test completed successfully!");
  } catch (error) {
    console.error("Error:", error);
    process.exit(1);
  }
}

main().catch(console.error);
