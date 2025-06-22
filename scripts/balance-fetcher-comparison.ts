import {
  encodePacked,
  hexToBytes,
  parseAbi,
  createPublicClient,
  http,
  type Address,
  type Hex,
} from "viem";
import { base } from "viem/chains";
import * as fs from "fs";

const CONTRACT_ADDRESS = "0x474041E305c269f6973FCF2A6eDdb2fB717a23E0" as const;

const BASE_TOKENS: Address[] = [
  "0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913",
  "0x4200000000000000000000000000000000000006",
  "0x0555E30da8f98308EdB960aa94C0Db47230d2B9c",
  "0xc1CBa3fCea344f92D9239c08C0568f6F2F0ee452",
  "0x820C137fa70C8691f0e44Dc420a5e53c168921Dc",
  "0x04C0599Ae5A44757c0af6F9eC3b93da8976c150A",
  "0x6985884C4392D348587B19cb9eAAf157F13271cd",
  "0x5d3a1Ff2b6BAb83b63cd9AD0787074081a52ef34",
  "0xcbB7C0000aB88B473b1f5aFd9ef808440eed33Bf",
  "0x63706e401c06ac8513145b7687A14804d17f814b",
];

const TEST_USERS: Address[] = [
  "0x3304E22DDaa22bCdC5fCa2269b418046aE7b566A", // Binance 76
  "0x3304E22DDaa22bCdC5fCa2269b418046aE7b566A",
];

// RPC URLs for testing (working endpoints)
const RPC_URLS = [
  "https://base.publicnode.com",
  "https://1rpc.io/base",
  "https://base.drpc.org",
];

interface TestResult {
  approach: "multicall" | "balanceFetcher";
  numTokens: number;
  numAddresses: number;
  rpcUrl: string;
  executionTime: number;
  success: boolean;
  errorMessage?: string;
  gasUsed?: bigint;
}

interface ComparisonResult {
  numTokens: number;
  multicall: TestResult | null;
  balanceFetcher: TestResult | null;
  winner?: "multicall" | "balanceFetcher" | "tie";
  timesDifference?: number;
}

// Standard ERC20 ABI for balanceOf
const ERC20_ABI = parseAbi([
  "function balanceOf(address owner) view returns (uint256)",
]);

// BalanceFetcher ABI
const BALANCE_FETCHER_ABI = parseAbi([
  "function bal(bytes) returns (bytes)",
  "error InvalidInputLength()",
]);

async function testMulticallApproach(
  numTokens: number,
  rpcUrl: string,
  tokens: Address[],
  users: Address[]
): Promise<TestResult> {
  const publicClient = createPublicClient({
    chain: base,
    transport: http(rpcUrl, {
      timeout: 120000, // 2 minute
      retryCount: 2,
    }),
  });

  const selectedTokens = tokens.slice(0, numTokens);
  const numAddresses = users.length;

  const contracts = [];
  for (const user of users) {
    for (const token of selectedTokens) {
      contracts.push({
        address: token,
        abi: ERC20_ABI,
        functionName: "balanceOf" as const,
        args: [user],
      });
    }
  }

  const startTime = Date.now();
  try {
    const results = await publicClient.multicall({
      contracts,
      allowFailure: true,
    });

    const endTime = Date.now();
    const executionTime = endTime - startTime;

    // Count successful calls
    const successfulCalls = results.filter(
      (result) => result.status === "success"
    ).length;
    const totalCalls = results.length;

    if (successfulCalls < totalCalls * 0.95) {
      // If less than 95% succeed, consider it a failure
      throw new Error(
        `Only ${successfulCalls}/${totalCalls} multicall queries succeeded`
      );
    }

    return {
      approach: "multicall",
      numTokens,
      numAddresses,
      rpcUrl,
      executionTime,
      success: true,
    };
  } catch (error) {
    const endTime = Date.now();
    const executionTime = endTime - startTime;
    const errorMessage = error instanceof Error ? error.message : String(error);

    return {
      approach: "multicall",
      numTokens,
      numAddresses,
      rpcUrl,
      executionTime,
      success: false,
      errorMessage,
    };
  }
}

async function testBalanceFetcherApproach(
  numTokens: number,
  rpcUrl: string,
  tokens: Address[],
  users: Address[]
): Promise<TestResult> {
  const publicClient = createPublicClient({
    chain: base,
    transport: http(rpcUrl, {
      timeout: 120000, // 2 minute
      retryCount: 2,
    }),
  });

  const selectedTokens = tokens.slice(0, numTokens);
  const numAddresses = users.length;

  // Encode input for BalanceFetcher
  const input =
    encodePacked(["uint16", "uint16"], [numTokens, numAddresses]) +
    encodePacked(new Array(numAddresses).fill("address"), users).slice(2) +
    encodePacked(new Array(numTokens).fill("address"), selectedTokens).slice(2);

  const startTime = Date.now();
  try {
    const simulation = await publicClient.simulateContract({
      address: CONTRACT_ADDRESS,
      abi: BALANCE_FETCHER_ABI,
      functionName: "bal",
      args: [input as Hex],
    });

    const endTime = Date.now();
    const executionTime = endTime - startTime;

    return {
      approach: "balanceFetcher",
      numTokens,
      numAddresses,
      rpcUrl,
      executionTime,
      success: true,
      gasUsed: simulation.request.gas,
    };
  } catch (error) {
    const endTime = Date.now();
    const executionTime = endTime - startTime;
    const errorMessage = error instanceof Error ? error.message : String(error);

    return {
      approach: "balanceFetcher",
      numTokens,
      numAddresses,
      rpcUrl,
      executionTime,
      success: false,
      errorMessage,
    };
  }
}

async function runComparisonTest(
  numTokens: number,
  tokens: Address[],
  users: Address[]
): Promise<ComparisonResult> {
  console.log(`\nTesting ${numTokens} tokens × ${users.length} addresses`);

  // Test both approaches
  const rpcUrl = RPC_URLS[0];

  const [multicallResult, balanceFetcherResult] = await Promise.all([
    testMulticallApproach(numTokens, rpcUrl, tokens, users),
    testBalanceFetcherApproach(numTokens, rpcUrl, tokens, users),
  ]);

  console.log(
    `  Multicall: ${multicallResult.success ? "✅" : "❌"} ${
      multicallResult.executionTime
    }ms`
  );
  console.log(
    `  BalanceFetcher: ${balanceFetcherResult.success ? "✅" : "❌"} ${
      balanceFetcherResult.executionTime
    }ms`
  );

  let winner: "multicall" | "balanceFetcher" | "tie" | undefined;
  let timesDifference: number | undefined;

  if (multicallResult.success && balanceFetcherResult.success) {
    const multicallTime = multicallResult.executionTime;
    const balanceFetcherTime = balanceFetcherResult.executionTime;

    const timeDifference = Math.abs(multicallTime - balanceFetcherTime);
    const fasterTime = Math.min(multicallTime, balanceFetcherTime);
    const percentageDifference = (timeDifference / fasterTime) * 100;

    if (percentageDifference < 10) {
      // Less than 10% difference is considered a tie
      winner = "tie";
    } else if (multicallTime < balanceFetcherTime) {
      winner = "multicall";
      timesDifference = balanceFetcherTime / multicallTime;
    } else {
      winner = "balanceFetcher";
      timesDifference = multicallTime / balanceFetcherTime;
    }

    console.log(
      `  Winner: ${winner}${
        timesDifference ? ` (${timesDifference.toFixed(1)}x faster)` : ""
      }`
    );
  } else if (multicallResult.success && !balanceFetcherResult.success) {
    winner = "multicall";
    console.log(`  Winner: multicall (BalanceFetcher failed)`);
  } else if (!multicallResult.success && balanceFetcherResult.success) {
    winner = "balanceFetcher";
    console.log(`  Winner: balanceFetcher (Multicall failed)`);
  } else {
    console.log(`  Both approaches failed`);
  }

  return {
    numTokens,
    multicall: multicallResult.success ? multicallResult : null,
    balanceFetcher: balanceFetcherResult.success ? balanceFetcherResult : null,
    winner,
    timesDifference,
  };
}

async function runFullComparison() {
  console.log("Balance Fetching Comparison Test");
  console.log("=".repeat(60));
  console.log(`Contract Address: ${CONTRACT_ADDRESS}`);
  console.log(`Test Users: ${TEST_USERS.length} addresses`);
  console.log(`RPC URL: ${RPC_URLS[0]}`);

  let tokens: Address[];

  tokens = BASE_TOKENS;

  console.log(`Available tokens: ${tokens.length}`);

  const results: ComparisonResult[] = [];
  const startTime = Date.now();

  const testCounts = [
    1, 2, 3, 5, 10, 15, 20, 25, 30, 40, 50, 75, 100, 125, 150, 200,
  ];

  let bothFailed = false;

  for (const tokenCount of testCounts) {
    if (bothFailed) {
      console.log(
        `\nSkipping ${tokenCount} tokens (both approaches already failed)`
      );
      break;
    }

    const expandedTokens: Address[] = [];
    for (let i = 0; i < tokenCount; i++) {
      expandedTokens.push(tokens[i % tokens.length]);
    }

    const result = await runComparisonTest(
      tokenCount,
      expandedTokens,
      TEST_USERS
    );
    results.push(result);

    // Check if both approaches failed
    if (!result.multicall && !result.balanceFetcher) {
      console.log(`\nBoth approaches failed at ${tokenCount} tokens`);
      bothFailed = true;
    }

    // Add delay
    const delay = tokenCount > 50 ? 2000 : tokenCount > 20 ? 1500 : 1000;
    await new Promise((resolve) => setTimeout(resolve, delay));
  }

  const totalTime = Date.now() - startTime;
  console.log(
    `\nFinal comparison completed in ${(totalTime / 1000).toFixed(1)}s`
  );

  console.log("\nANALYSIS");
  console.log("=".repeat(80));

  const successfulMulticall = results.filter((r) => r.multicall).length;
  const successfulBalanceFetcher = results.filter(
    (r) => r.balanceFetcher
  ).length;

  console.log(`\nSuccess Rate:`);
  console.log(
    `  Multicall: ${successfulMulticall}/${results.length} tests (${(
      (successfulMulticall / results.length) *
      100
    ).toFixed(1)}%)`
  );
  console.log(
    `  BalanceFetcher: ${successfulBalanceFetcher}/${results.length} tests (${(
      (successfulBalanceFetcher / results.length) *
      100
    ).toFixed(1)}%)`
  );

  const maxMulticallTokens = Math.max(
    ...results.filter((r) => r.multicall).map((r) => r.numTokens),
    0
  );
  const maxBalanceFetcherTokens = Math.max(
    ...results.filter((r) => r.balanceFetcher).map((r) => r.numTokens),
    0
  );

  console.log(`\nMaximum Tokens Handled:`);
  console.log(`  Multicall: ${maxMulticallTokens} tokens`);
  console.log(`  BalanceFetcher: ${maxBalanceFetcherTokens} tokens`);

  // Performance comparison
  const bothSuccessful = results.filter((r) => r.multicall && r.balanceFetcher);

  if (bothSuccessful.length > 0) {
    console.log(
      `\nPerformance Comparison (${bothSuccessful.length} tests where both succeeded):`
    );

    const multicallWins = bothSuccessful.filter(
      (r) => r.winner === "multicall"
    ).length;
    const balanceFetcherWins = bothSuccessful.filter(
      (r) => r.winner === "balanceFetcher"
    ).length;
    const ties = bothSuccessful.filter((r) => r.winner === "tie").length;

    console.log(`  Multicall wins: ${multicallWins}`);
    console.log(`  BalanceFetcher wins: ${balanceFetcherWins}`);
    console.log(`  Ties: ${ties}`);

    // Average performance
    const avgMulticallTime =
      bothSuccessful.reduce((sum, r) => sum + r.multicall!.executionTime, 0) /
      bothSuccessful.length;
    const avgBalanceFetcherTime =
      bothSuccessful.reduce(
        (sum, r) => sum + r.balanceFetcher!.executionTime,
        0
      ) / bothSuccessful.length;

    console.log(`\nAverage Execution Time:`);
    console.log(`  Multicall: ${avgMulticallTime.toFixed(0)}ms`);
    console.log(`  BalanceFetcher: ${avgBalanceFetcherTime.toFixed(0)}ms`);

    if (avgMulticallTime < avgBalanceFetcherTime) {
      console.log(
        `  → Multicall is ${(avgBalanceFetcherTime / avgMulticallTime).toFixed(
          1
        )}x faster on average`
      );
    } else {
      console.log(
        `  → BalanceFetcher is ${(
          avgMulticallTime / avgBalanceFetcherTime
        ).toFixed(1)}x faster on average`
      );
    }
  }

  // Detailed results table
  console.log(`\nDetailed Results:`);
  console.log("Tokens | Multicall (ms) | BalanceFetcher (ms) | Winner");
  console.log("-".repeat(60));

  results.forEach((result) => {
    const multicallTime = result.multicall?.executionTime || "FAILED";
    const balanceFetcherTime = result.balanceFetcher?.executionTime || "FAILED";
    const winner = result.winner || "BOTH FAILED";

    console.log(
      `${result.numTokens.toString().padStart(6)} | ${multicallTime
        .toString()
        .padStart(13)} | ${balanceFetcherTime
        .toString()
        .padStart(18)} | ${winner}`
    );
  });

  // Save results to file
  const timestamp = new Date().toISOString().replace(/[:.]/g, "-");
  const resultFile = `comparison-results-${timestamp}.json`;

  fs.writeFileSync(
    resultFile,
    JSON.stringify(
      {
        timestamp: new Date().toISOString(),
        contractAddress: CONTRACT_ADDRESS,
        testUsers: TEST_USERS,
        rpcUrl: RPC_URLS[0],
        totalExecutionTime: totalTime,
        tokensUsed: tokens.length,
        results,
        summary: {
          totalTests: results.length,
          successfulMulticall,
          successfulBalanceFetcher,
          maxMulticallTokens,
          maxBalanceFetcherTokens,
          avgMulticallTime:
            bothSuccessful.length > 0
              ? bothSuccessful.reduce(
                  (sum, r) => sum + r.multicall!.executionTime,
                  0
                ) / bothSuccessful.length
              : null,
          avgBalanceFetcherTime:
            bothSuccessful.length > 0
              ? bothSuccessful.reduce(
                  (sum, r) => sum + r.balanceFetcher!.executionTime,
                  0
                ) / bothSuccessful.length
              : null,
        },
      },
      null,
      2
    )
  );

  console.log(`\nDetailed results saved to: ${resultFile}`);

  // Final recommendation
  console.log(`\nFINAL RECOMMENDATIONS:`);
  console.log("=".repeat(80));

  if (maxBalanceFetcherTokens > maxMulticallTokens) {
    console.log(
      `BalanceFetcher is SUPERIOR for scale: handles ${maxBalanceFetcherTokens} tokens vs ${maxMulticallTokens} for multicall`
    );
    console.log(
      `   → Use BalanceFetcher for querying ${maxBalanceFetcherTokens}+ tokens`
    );
  } else if (maxMulticallTokens > maxBalanceFetcherTokens) {
    console.log(
      `Multicall is SUPERIOR for scale: handles ${maxMulticallTokens} tokens vs ${maxBalanceFetcherTokens} for BalanceFetcher`
    );
    console.log(
      `   → Use Multicall for querying ${maxMulticallTokens}+ tokens`
    );
  } else {
    console.log(
      `Both approaches handle the same maximum tokens (${maxBalanceFetcherTokens})`
    );
  }

  if (bothSuccessful.length > 0) {
    const avgMulticallTime =
      bothSuccessful.reduce((sum, r) => sum + r.multicall!.executionTime, 0) /
      bothSuccessful.length;
    const avgBalanceFetcherTime =
      bothSuccessful.reduce(
        (sum, r) => sum + r.balanceFetcher!.executionTime,
        0
      ) / bothSuccessful.length;

    if (avgBalanceFetcherTime < avgMulticallTime) {
      console.log(
        `BalanceFetcher is ${(avgMulticallTime / avgBalanceFetcherTime).toFixed(
          1
        )}x faster on average`
      );
      console.log(`   → Use BalanceFetcher for better performance`);
    } else if (avgMulticallTime < avgBalanceFetcherTime) {
      console.log(
        `Multicall is ${(avgBalanceFetcherTime / avgMulticallTime).toFixed(
          1
        )}x faster on average`
      );
      console.log(`   → Use Multicall for better performance`);
    } else {
      console.log(`Both approaches have similar performance`);
    }
  }

  // Gas usage comparison
  const balanceFetcherWithGas = results.filter(
    (r) => r.balanceFetcher?.gasUsed
  );
  if (balanceFetcherWithGas.length > 0) {
    const avgGasUsed =
      balanceFetcherWithGas.reduce(
        (sum, r) => sum + Number(r.balanceFetcher!.gasUsed!),
        0
      ) / balanceFetcherWithGas.length;
    console.log(
      `\nBalanceFetcher Average Gas Usage: ${Math.round(
        avgGasUsed
      ).toLocaleString()} gas`
    );
  }

  console.log(
    `\nCONCLUSION: ${
      maxBalanceFetcherTokens >= maxMulticallTokens &&
      (bothSuccessful.length === 0 ||
        bothSuccessful.reduce(
          (sum, r) => sum + r.balanceFetcher!.executionTime,
          0
        ) <=
          bothSuccessful.reduce(
            (sum, r) => sum + r.multicall!.executionTime,
            0
          ))
        ? "BalanceFetcher is the optimal solution for batch balance queries!"
        : maxMulticallTokens > maxBalanceFetcherTokens
        ? "Multicall handles more tokens and is the better choice for large-scale queries!"
        : "Both approaches are comparable - choose based on your specific needs!"
    }`
  );
}

// Handle process interruption
process.on("SIGINT", () => {
  console.log("\n\nTest interrupted by user");
  process.exit(0);
});

// Run the comparison
runFullComparison().catch((error) => {
  console.error("\nTest failed:", error);
  process.exit(1);
});
