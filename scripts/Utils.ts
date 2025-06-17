import { readFileSync } from "fs"
import { join } from "path"
import { ANVIL_URL } from "./AnvilManager"
import { AnvilManager } from "./AnvilManager"
import { privateKeyToAccount } from "viem/accounts"
import { createPublicClient, createWalletClient, http, type Account, type WalletClient, type PublicClient } from "viem"
import { arbitrum } from "viem/chains"

export const USERS = [
    '0x91ae002a960e63Ccb0E5bDE83A8C13E51e1cB91A',
    '0xdFF70A71618739f4b8C81B11254BcE855D02496B',
    '0x0eb2d44F6717D8146B6Bd6B229A15F0803e5B244',
    '0xB1026b8e7276e7AC75410F1fcbbe21796e8f7526'
  ] as const
  
  export const TOKENS = [
    '0xFd086bC7CD5C481DCC9C85ebE478A1C0b69FCbb9', // USDT
    '0xaf88d065e77c8cC2239327C5EDb3A432268e5831', // USDC
    '0x2f2a2543B76A4166549F7aaB2e75Bef0aefC5B0f', // WBTC
    '0x82aF49447D8a07e3bd95BD0d56f35241523fBab1'  // WETH
  ] as const
  
  export const PRIVATE_KEY = '0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80'
  

export async function getContractBytecode(): Promise<string> {
    try {
      // Try to read from forge compilation output
      const artifactPath = join(process.cwd(), 'out/BalanceFetcher.sol/BalanceFetcher.json')
      const artifact = JSON.parse(readFileSync(artifactPath, 'utf8'))
      return artifact.bytecode.object
    } catch (error) {
      console.log('Could not read compiled artifact, compiling with forge...')
      
      // Compile with forge
      const { spawn } = require('child_process')
      await new Promise<void>((resolve, reject) => {
        const forgeProcess = spawn('forge', ['build'], { stdio: 'inherit' })
        forgeProcess.on('close', (code: number) => {
          if (code === 0) {
            resolve()
          } else {
            reject(new Error(`Forge build failed with code ${code}`))
          }
        })
      })
      
      // Try reading again
      const artifactPath = join(process.cwd(), 'out/BalanceFetcher.sol/BalanceFetcher.json')
      const artifact = JSON.parse(readFileSync(artifactPath, 'utf8'))
      return artifact.bytecode.object
    }
  }

  export function parseBalanceData(data: Uint8Array) {
    console.log(`Parsing balance data (${data.length} bytes)...`)
    
    let offset = 8 // skip block number
    const results: Array<{
      userIndex: number
      userAddress: string
      balances: Array<{
        tokenIndex: number
        tokenAddress: string
        balance: bigint
      }>
    }> = []
  
    while (offset < data.length) {
      const userPrefixBytes = data.slice(offset, offset + 4)
      const userPrefix = new DataView(userPrefixBytes.buffer).getUint32(0, false) 
      
      const userIndex = (userPrefix >> 16) & 0xFFFF
      const count = userPrefix & 0xFFFF
      
      console.log(`User ${userIndex} (${USERS[userIndex]}): ${count} non-zero balances`)
      
      offset += 4
      
      const balances = []
      for (let i = 0; i < count; i++) {
        const balanceBytes = data.slice(offset, offset + 16)
        const balanceData = new DataView(balanceBytes.buffer)
        
        const tokenIndex = balanceData.getUint16(0, false)
        const balanceHigh = balanceData.getUint32(2, false)
        const balanceMid = balanceData.getUint32(6, false)
        const balanceLow = balanceData.getUint32(10, false)
        const balanceVeryLow = balanceData.getUint16(14, false)
        
        const balance = (BigInt(balanceHigh) << 80n) + 
                       (BigInt(balanceMid) << 48n) + 
                       (BigInt(balanceLow) << 16n) + 
                       BigInt(balanceVeryLow)
        
        console.log(`Token ${tokenIndex} (${TOKENS[tokenIndex]}): ${balance.toString()}`)
        
        balances.push({
          tokenIndex,
          tokenAddress: TOKENS[tokenIndex],
          balance
        })
        
        offset += 16
      }
      
      results.push({
        userIndex,
        userAddress: USERS[userIndex],
        balances
      })
    }
    
    return results
  }

  export async function deployContract(anvil: AnvilManager): Promise<{
    contractAddress: `0x${string}`
    publicClient: PublicClient
    walletClient: WalletClient
    account: Account
  }> {
    try {
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
          abi: [],
          bytecode: bytecode as `0x${string}`,
        })
        
        const receipt = await publicClient.waitForTransactionReceipt({ hash: deployHash })
        return {
            contractAddress: receipt.contractAddress!,
            publicClient,
            walletClient,
            account
        }
    } catch (error) {
        console.error('Error deploying contract:', error)
        throw error
    }
  }