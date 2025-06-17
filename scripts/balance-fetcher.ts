import {
  createPublicClient,
  createWalletClient,
  http,
  encodePacked,
  hexToBytes,
} from 'viem'
import { privateKeyToAccount } from 'viem/accounts'
import { arbitrum } from 'viem/chains'
import { ANVIL_URL, AnvilManager } from './AnvilManager'
import { getContractBytecode, parseBalanceData, PRIVATE_KEY, TOKENS, USERS } from './Utils'

async function main() {
  const anvil = new AnvilManager()
  
  try {
    await anvil.start()
    await new Promise(resolve => setTimeout(resolve, 2000))
    
    const account = privateKeyToAccount(PRIVATE_KEY)
    
    const publicClient = createPublicClient({
      chain: arbitrum,
      transport: http(ANVIL_URL)
    })
    
    const walletClient = createWalletClient({
      account,
      chain: arbitrum,
      transport: http(ANVIL_URL)
    })
    
    const bytecode = await getContractBytecode()
    
    const deployHash = await walletClient.deployContract({
      abi: [], // No constructor
      bytecode: bytecode as `0x${string}`,
    })
    
    const receipt = await publicClient.waitForTransactionReceipt({ hash: deployHash })
    const contractAddress = receipt.contractAddress!
    
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
    
    const gasEstimate = await publicClient.estimateGas({
      account: account.address,
      to: contractAddress,
      data: input as `0x${string}`,
    })
    
    console.log(`Estimated gas: ${gasEstimate}`)
    
    const result = await publicClient.call({
      account: account.address,
      to: contractAddress,
      data: input as `0x${string}`,
    })
    
    if (!result.data) {
      throw new Error('No data returned from contract call')
    }
    
    console.log(`Response data (${result.data.length / 2 - 1} bytes):`)
    console.log(`Response: ${result.data}`)
    
    const responseBytes = hexToBytes(result.data)
    parseBalanceData(responseBytes)
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