import {
  encodePacked,
  hexToBytes,
  parseAbi,
} from 'viem'
import { AnvilManager } from './AnvilManager'
import { deployContract, parseBalanceData, TOKENS, USERS } from './Utils'



async function main() {
    const anvil = new AnvilManager()
    await anvil.start()
    await new Promise(resolve => setTimeout(resolve, 2000))

  try {
    const { contractAddress, publicClient, account } = await deployContract(anvil);
    console.log(`BalanceFetcher deployed at: ${contractAddress}`)
    
    const input = encodePacked(
      ['uint16', 'uint16'],
      [4, 4] // numTokens, numAddresses
    ) + 
    encodePacked(
      ['address', 'address', 'address', 'address'],
      USERS
    ).slice(2) + 
    encodePacked(
      ['address', 'address', 'address', 'address'],
      TOKENS
    ).slice(2)
    
    console.log(`\nInput data (${input.length / 2 - 1} bytes):`)
    console.log(`Input: ${input}`)

    const BALANCE_FETCHER_ABI = parseAbi(['function bal(bytes) returns (bytes)','error InvalidInputLength()'])

    const simulation = await publicClient.simulateContract({
      account: account.address,
      address: contractAddress,
      abi: BALANCE_FETCHER_ABI,
      functionName: 'bal',
      args: [input as `0x${string}`],
    })
    
    console.log('Simulation successful!')
    
    if (!simulation) {
      throw new Error('No data returned from simulation')
    }
    
    console.log(`Response: ${simulation}`)
    
    const responseBytes = hexToBytes(simulation.result)
    parseBalanceData(responseBytes)
    
    console.log('simulateContract test completed successfully!')
    
  } catch (error) {
    console.error('Error:', error)
    process.exit(1)
  } finally {
    await anvil.stop()
  }
}

process.on('SIGINT', () => {
  console.log('\nShutting down...')
  process.exit(0)
})

process.on('SIGTERM', () => {
  console.log('\nShutting down...')
  process.exit(0)
})

main().catch(console.error)
