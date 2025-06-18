import {
  encodePacked,
  hexToBytes,
  parseAbi,
  createPublicClient,
  http,
  type Address,
} from "viem";
import { base } from "viem/chains";
import * as fs from "fs";
import * as path from "path";

const CONTRACT_ADDRESS = "0x474041E305c269f6973FCF2A6eDdb2fB717a23E0" as const;

// load 50 first tokens
// todo: can be ooptimized to return better tokens
const loadTokens = () => {
  const tokenListPath = path.join(__dirname, "8453.json");
  const tokenList = JSON.parse(fs.readFileSync(tokenListPath, "utf8"));
  return Object.keys(tokenList.list).slice(0, 50); // Use first 50 tokens for testing
};

// some whales on base, repeated
const TEST_USERS: Address[] = [
  "0x20FE51A9229EEf2cF8Ad9E89d91CAb9312cF3b7A",
  "0xC882b111A75C0c657fC507C04FbFcD2cC984F071",
  "0x97b9D2102A9a65A26E1EE82D59e42d1B73B68689",
  "0xBaeD383EDE0e5d9d72430661f3285DAa77E9439F",
  "0x3304E22DDaa22bCdC5fCa2269b418046aE7b566A",
  "0xB604f2d512EaA32E06F1ac40362bC9157cE5Da96",
  "0x4e3ae00E8323558fA5Cac04b152238924AA31B60",
  "0x63DFE4e34A3bFC00eB0220786238a7C6cEF8Ffc4",
  "0x0D0707963952f2fBA59dD06f2b425ace40b492Fe",
  "0xeF4fB24aD0916217251F553c0596F8Edc630EB66",
  "0x6dcBCe46a8B494c885D0e7b6817d2b519dF64467",
  "0x7777777F279eba3d3Ad8F4E708545291A6fDBA8B",
  "0x8B9B689D0c44dCab4472ea0F3788c71Ef2d0ee49",
  "0x1A714D76F14B9e7C894B5580cE92316021863341",
  "0x66a503a1060AB3f2B1AAaBeD613fe30BAbbC1bDE",
  "0x5638484ba2d2F1D1D35020572B0Aa439a9869192",
  "0xCc4ADB618253ED0d4d8A188fB901d70C54735e03",
  "0x3D8FC1CFfAa110F7A7F9f8BC237B73d54C4aBf61",
  "0xB604f2d512EaA32E06F1ac40362bC9157cE5Da96",
  "0xBaD36f8edD1E2109baa37197c05074151a70Cc05",
  "0xD89E6B7687f862dd6D24B3B2D4D0dec6A89A6fdd",
  "0x39591E7c099A379FD7b349EbFeCaeEF439c40454",
  "0x242E2d70d3AdC00a9eF23CeD6E88811fCefCA788",
  "0x91Dca37856240E5e1906222ec79278b16420Dc92",
  "0x3563015e9f5694AFE5D8cD86233f77557DA704cc",
  "0x1A714D76F14B9e7C894B5580cE92316021863341",
  "0x8B9B689D0c44dCab4472ea0F3788c71Ef2d0ee49",
  "0xaEA5Bf79F1E3F2069a99A99928927988EC642e0B",
  "0x20FE51A9229EEf2cF8Ad9E89d91CAb9312cF3b7A",
  "0xC882b111A75C0c657fC507C04FbFcD2cC984F071",
  "0x97b9D2102A9a65A26E1EE82D59e42d1B73B68689",
  "0xBaeD383EDE0e5d9d72430661f3285DAa77E9439F",
  "0x3304E22DDaa22bCdC5fCa2269b418046aE7b566A",
  "0xB604f2d512EaA32E06F1ac40362bC9157cE5Da96",
  "0x4e3ae00E8323558fA5Cac04b152238924AA31B60",
  "0x63DFE4e34A3bFC00eB0220786238a7C6cEF8Ffc4",
  "0x0D0707963952f2fBA59dD06f2b425ace40b492Fe",
  "0xeF4fB24aD0916217251F553c0596F8Edc630EB66",
  "0x6dcBCe46a8B494c885D0e7b6817d2b519dF64467",
  "0x7777777F279eba3d3Ad8F4E708545291A6fDBA8B",
  "0x8B9B689D0c44dCab4472ea0F3788c71Ef2d0ee49",
  "0x1A714D76F14B9e7C894B5580cE92316021863341",
  "0x66a503a1060AB3f2B1AAaBeD613fe30BAbbC1bDE",
  "0x5638484ba2d2F1D1D35020572B0Aa439a9869192",
  "0xCc4ADB618253ED0d4d8A188fB901d70C54735e03",
  "0x3D8FC1CFfAa110F7A7F9f8BC237B73d54C4aBf61",
  "0xB604f2d512EaA32E06F1ac40362bC9157cE5Da96",
  "0xBaD36f8edD1E2109baa37197c05074151a70Cc05",
  "0xD89E6B7687f862dd6D24B3B2D4D0dec6A89A6fdd",
  "0x39591E7c099A379FD7b349EbFeCaeEF439c40454",
  "0x242E2d70d3AdC00a9eF23CeD6E88811fCefCA788",
  "0x91Dca37856240E5e1906222ec79278b16420Dc92",
  "0x3563015e9f5694AFE5D8cD86233f77557DA704cc",
  "0x1A714D76F14B9e7C894B5580cE92316021863341",
];

// rpcs
const RPC_URLS = [
  "wss://base-rpc.publicnode.com",
  "https://base.gateway.tenderly.co",
  "https://1rpc.io/base",
  "https://base.drpc.org",
  "https://endpoints.omniatech.io/v1/base/mainnet/public",
];

interface TestResult {
  numTokens: number;
  numAddresses: number;
  rpcUrl: string;
  executionTime: number;
  success: boolean;
  errorMessage?: string;
  gasUsed?: bigint;
  blockNumber?: bigint;
}

interface PerformanceStats {
  min: number;
  max: number;
  avg: number;
  median: number;
  p95: number;
}

const BALANCE_FETCHER_ABI = parseAbi([
  "function bal(bytes) returns (bytes)",
  "error InvalidInputLength()",
]);

async function runSingleTest(
  numTokens: number,
  numAddresses: number,
  rpcUrl: string,
  tokens: Address[],
  users: Address[]
): Promise<TestResult> {
  const publicClient = createPublicClient({
    chain: base,
    transport: http(rpcUrl, {
      timeout: 30000,
      retryCount: 3,
    }),
  });

  const selectedTokens = tokens.slice(0, numTokens);
  const selectedUsers = users.slice(0, numAddresses);

  const input =
    encodePacked(["uint16", "uint16"], [numTokens, numAddresses]) +
    encodePacked(new Array(numAddresses).fill("address"), selectedUsers).slice(
      2
    ) +
    encodePacked(new Array(numTokens).fill("address"), selectedTokens).slice(2);

  const startTime = Date.now();
  try {
    const simulation = await publicClient.simulateContract({
      address: CONTRACT_ADDRESS,
      abi: BALANCE_FETCHER_ABI,
      functionName: "bal",
      args: [input as `0x${string}`],
    });

    const endTime = Date.now();
    const executionTime = endTime - startTime;

    return {
      numTokens,
      numAddresses,
      rpcUrl,
      executionTime,
      success: true,
      gasUsed: simulation.request.gas,
      blockNumber: BigInt(await publicClient.getBlockNumber()),
    };
  } catch (error) {
    const endTime = Date.now();
    const executionTime = endTime - startTime;

    return {
      numTokens,
      numAddresses,
      rpcUrl,
      executionTime,
      success: false,
      errorMessage: error instanceof Error ? error.message : String(error),
    };
  }
}

function calculateStats(times: number[]): PerformanceStats {
  const sorted = [...times].sort((a, b) => a - b);
  const len = sorted.length;

  return {
    min: sorted[0],
    max: sorted[len - 1],
    avg: times.reduce((a, b) => a + b, 0) / len,
    median:
      len % 2 === 0
        ? (sorted[len / 2 - 1] + sorted[len / 2]) / 2
        : sorted[Math.floor(len / 2)],
    p95: sorted[Math.floor(len * 0.95)],
  };
}

async function runPerformanceTest() {
  console.log(`Testing ${RPC_URLS.length} RPC URLs`);

  const tokens = loadTokens() as Address[];

  // Test configurations: [numTokens, numAddresses]
  const testConfigs = [
    [5, 5],
    [10, 5],
    [5, 10],
    [10, 10],

    [20, 10],
    [10, 20],
    [20, 20],
    [30, 15],
    [15, 30],

    [50, 10],
    [30, 30],
    [40, 25],
    [25, 40],

    [50, 30],
    [30, 50],
    [50, 50],
  ];

  const allResults: TestResult[] = [];
  const startTime = Date.now();

  for (const [numTokens, numAddresses] of testConfigs) {
    console.log(`\nTesting ${numTokens} tokens × ${numAddresses} addresses`);

    if (numTokens > tokens.length || numAddresses > TEST_USERS.length) {
      console.log(
        `Skipping - not enough tokens (${tokens.length}) or users (${TEST_USERS.length})`
      );
      continue;
    }

    for (const rpcUrl of RPC_URLS) {
      const rpcName = new URL(rpcUrl).hostname;
      process.stdout.write(`${rpcName}...`);

      const result = await runSingleTest(
        numTokens,
        numAddresses,
        rpcUrl,
        tokens,
        TEST_USERS
      );

      allResults.push(result);

      if (result.success) {
        console.log(` ✅ ${result.executionTime}ms`);
      } else {
        console.log(
          ` ❌ ${result.executionTime}ms - ${result.errorMessage?.slice(
            0,
            50
          )}...`
        );
      }

      // Add delay for rpc
      await new Promise((resolve) => setTimeout(resolve, 100));
    }
  }

  const totalTime = Date.now() - startTime;
  console.log(`\nPerformance test completed in ${totalTime}ms`);
  console.log(`Total tests run: ${allResults.length}`);

  // Analyze results
  console.log("\nPerformance Analysis");
  console.log("=".repeat(80));

  // Success rate by RPC
  console.log("\nRPC URL Performance:");
  for (const rpcUrl of RPC_URLS) {
    const rpcResults = allResults.filter((r) => r.rpcUrl === rpcUrl);
    const successRate =
      (rpcResults.filter((r) => r.success).length / rpcResults.length) * 100;
    const successfulTimes = rpcResults
      .filter((r) => r.success)
      .map((r) => r.executionTime);

    if (successfulTimes.length > 0) {
      const stats = calculateStats(successfulTimes);
      console.log(`${new URL(rpcUrl).hostname}:`);
      console.log(
        `     Success: ${successRate.toFixed(1)}% (${
          rpcResults.filter((r) => r.success).length
        }/${rpcResults.length})`
      );
      console.log(
        `     Times: avg=${stats.avg.toFixed(
          0
        )}ms, median=${stats.median.toFixed(0)}ms, p95=${stats.p95.toFixed(
          0
        )}ms`
      );
    } else {
      console.log(`   ${new URL(rpcUrl).hostname}: 0% success rate`);
    }
  }

  console.log("\nBest Performing Configurations:");
  const successfulResults = allResults.filter((r) => r.success);

  if (successfulResults.length === 0) {
    console.log("❌ No successful tests!");
    return;
  }

  // Group by configuration
  const configStats = new Map<string, TestResult[]>();

  for (const result of successfulResults) {
    const key = `${result.numTokens}×${result.numAddresses}`;
    if (!configStats.has(key)) {
      configStats.set(key, []);
    }
    configStats.get(key)!.push(result);
  }

  // Calculate average
  const configPerformance = Array.from(configStats.entries()).map(
    ([config, results]) => {
      const times = results.map((r) => r.executionTime);
      const stats = calculateStats(times);
      const [numTokens, numAddresses] = config.split("×").map(Number);

      return {
        config,
        numTokens,
        numAddresses,
        totalCalls: numTokens * numAddresses,
        ...stats,
        successRate: results.length / RPC_URLS.length,
        results,
      };
    }
  );

  // Sort by performance (lower average time is better)
  configPerformance.sort((a, b) => a.avg - b.avg);

  console.log("\n   Top 10 fastest configurations:");
  configPerformance.slice(0, 10).forEach((config, i) => {
    console.log(
      `   ${i + 1}. ${config.config} (${
        config.totalCalls
      } calls): ${config.avg.toFixed(0)}ms avg, ${
        config.successRate * 100
      }% success`
    );
  });

  // Find sweet spot (good performance with reasonable scale)
  console.log("\nRecommended Configurations:");
  const goodConfigs = configPerformance.filter(
    (c) =>
      c.successRate >= 0.8 && // At least 80% success rate
      c.avg < 5000 && // Under 5 seconds average
      c.totalCalls >= 50 // At least 50 total calls
  );

  if (goodConfigs.length > 0) {
    goodConfigs.slice(0, 5).forEach((config, i) => {
      console.log(
        `   ${i + 1}. ${config.config}: ${config.avg.toFixed(0)}ms avg, ${
          config.totalCalls
        } total calls`
      );
    });
  } else {
    console.log("No configurations meet the recommended criteria");
  }

  // Save detailed results
  const timestamp = new Date().toISOString().replace(/[:.]/g, "-");
  const resultFile = `performance-results-${timestamp}.json`;

  fs.writeFileSync(
    resultFile,
    JSON.stringify(
      {
        timestamp: new Date().toISOString(),
        contractAddress: CONTRACT_ADDRESS,
        rpcUrls: RPC_URLS,
        testConfigs,
        totalExecutionTime: totalTime,
        results: allResults,
        analysis: {
          configPerformance,
          recommendations: goodConfigs.slice(0, 5),
        },
      },
      null,
      2
    )
  );

  console.log(`\nDetailed results saved to: ${resultFile}`);

  // Display final recommendations
  console.log("\nFINAL RECOMMENDATIONS:");
  console.log("=".repeat(80));

  if (goodConfigs.length > 0) {
    const best = goodConfigs[0];
    console.log(
      `Optimal configuration: ${best.numTokens} tokens × ${best.numAddresses} addresses`
    );
    console.log(`      Average execution time: ${best.avg.toFixed(0)}ms`);
    console.log(`      Total balance calls: ${best.totalCalls}`);
    console.log(`      Success rate: ${(best.successRate * 100).toFixed(1)}%`);
  }

  // Best RPC URL
  const rpcPerformance = RPC_URLS.map((rpcUrl) => {
    const rpcResults = allResults.filter(
      (r) => r.rpcUrl === rpcUrl && r.success
    );
    if (rpcResults.length === 0) return null;

    const times = rpcResults.map((r) => r.executionTime);
    const stats = calculateStats(times);

    return {
      rpcUrl,
      hostname: new URL(rpcUrl).hostname,
      ...stats,
      successCount: rpcResults.length,
      totalTests: allResults.filter((r) => r.rpcUrl === rpcUrl).length,
    };
  })
    .filter(Boolean)
    .sort((a, b) => a!.avg - b!.avg);

  if (rpcPerformance.length > 0) {
    const bestRpc = rpcPerformance[0]!;
    console.log(`Best RPC URL: ${bestRpc.hostname}`);
    console.log(`   Average response time: ${bestRpc.avg.toFixed(0)}ms`);
    console.log(
      `   Success rate: ${(
        (bestRpc.successCount / bestRpc.totalTests) *
        100
      ).toFixed(1)}%`
    );
  }
}

// Run the performance test
runPerformanceTest().catch(console.error);
