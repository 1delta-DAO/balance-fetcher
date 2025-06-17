import {
  createPublicClient,
  createWalletClient,
  http,
  encodePacked,
  hexToBytes,
} from 'viem'
import { privateKeyToAccount } from 'viem/accounts'
import { arbitrum } from 'viem/chains'
import { spawn, exec } from 'child_process'
import { readFileSync } from 'fs'
import { join } from 'path'
import { promisify } from 'util'

const execAsync = promisify(exec)

const USERS = [
  '0x91ae002a960e63Ccb0E5bDE83A8C13E51e1cB91A',
  '0xdFF70A71618739f4b8C81B11254BcE855D02496B',
  '0x0eb2d44F6717D8146B6Bd6B229A15F0803e5B244',
  '0xB1026b8e7276e7AC75410F1fcbbe21796e8f7526'
] as const

const TOKENS = [
  '0xFd086bC7CD5C481DCC9C85ebE478A1C0b69FCbb9', // USDT
  '0xaf88d065e77c8cC2239327C5EDb3A432268e5831', // USDC
  '0x2f2a2543B76A4166549F7aaB2e75Bef0aefC5B0f', // WBTC
  '0x82aF49447D8a07e3bd95BD0d56f35241523fBab1'  // WETH
] as const

// Default anvil private key
const PRIVATE_KEY = '0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80'
const ANVIL_PORT = 8545
const ANVIL_URL = `http://127.0.0.1:${ANVIL_PORT}`
const FORK_URL = 'https://arbitrum.drpc.org'
const CHAIN_ID = '42161'

class AnvilManager {
  private anvilProcess: any = null

  private async kpop(port: number): Promise<void> {
    try {
      const isWindows = process.platform === 'win32'
      let command: string
      
      if (isWindows) {
        command = `netstat -ano | findstr :${port}`
      } else {
        command = `lsof -ti:${port}`
      }
      
      const { stdout } = await execAsync(command).catch(() => ({ stdout: '' }))
      
      if (stdout.trim()) {
        console.log(`Found processes on port ${port}`)
        
        if (isWindows) {
          const lines = stdout.trim().split('\n')
          for (const line of lines) {
            const parts = line.trim().split(/\s+/)
            const pid = parts[parts.length - 1]
            if (pid && !isNaN(Number(pid))) {
              await execAsync(`taskkill /F /PID ${pid}`).catch(() => {})
            }
          }
        } else {
          await execAsync(`kill -9 ${stdout.trim().split('\n').join(' ')}`).catch(() => {})
        }
        
        await new Promise(resolve => setTimeout(resolve, 1000))
      }
    } catch (error) {
      console.log('No processes found on port or failed to kill:', error instanceof Error ? error.message : String(error))
    }
  }

  async start(): Promise<void> {
    console.log('Starting Anvil...')
    // kill process on port
    await this.kpop(ANVIL_PORT)
    
    return new Promise((resolve, reject) => {
      this.anvilProcess = spawn('anvil', [
        '--fork-url', FORK_URL,
        '--port', ANVIL_PORT.toString(),
        '--chain-id', CHAIN_ID
      ], {
        stdio: ['ignore', 'pipe', 'pipe']
      })

      this.anvilProcess.stdout.on('data', (data: Buffer) => {
        const output = data.toString()
        console.log(`Anvil: ${output}`)
        if (output.includes('Listening on')) {
          console.log('Anvil started')
          resolve()
        }
      })

      this.anvilProcess.stderr.on('data', (data: Buffer) => {
        console.error(`Anvil error: ${data}`)
      })

      this.anvilProcess.on('error', (error: Error) => {
        console.error('Failed to start anvil:', error)
        reject(error)
      })

      setTimeout(() => {
        reject(new Error('Anvil startup timeout'))
      }, 30000)
    })
  }

  async stop(): Promise<void> {
    if (this.anvilProcess) {
      console.log('Stopping Anvil...')
      
      return new Promise<void>((resolve) => {
        const cleanup = () => {
          this.anvilProcess = null
          resolve()
        }
        
        const forceKillTimeout = setTimeout(() => {
          console.log('Force kill anviil...')
          try {
            this.anvilProcess.kill('SIGKILL')
          } catch (error) {
             console.log('Error force killing process:', error instanceof Error ? error.message : String(error))
           }
          cleanup()
        }, 1000)
        
        this.anvilProcess.on('exit', () => {
          clearTimeout(forceKillTimeout)
          console.log('Anvil process exited')
          cleanup()
        })
        
        try {
          this.anvilProcess.kill('SIGTERM')
        } catch (error) {
           console.log('Error sending SIGTERM:', error instanceof Error ? error.message : String(error))
           clearTimeout(forceKillTimeout)
           cleanup()
         }
      })
    }
  }
}

async function getContractBytecode(): Promise<string> {
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

function parseBalanceData(data: Uint8Array) {
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