import { exec, spawn } from "child_process"
import { promisify } from "util"
const execAsync = promisify(exec)

export const ANVIL_PORT = 8545
export const ANVIL_URL = `http://127.0.0.1:${ANVIL_PORT}`
export const FORK_URL = 'https://arbitrum.drpc.org'
export const CHAIN_ID = '42161'
export class AnvilManager {
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