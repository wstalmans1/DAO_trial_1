import { fileURLToPath } from 'node:url'
import { dirname, resolve } from 'node:path'
import { config as loadEnv } from 'dotenv'
import type { HardhatUserConfig } from 'hardhat/config'
import '@nomicfoundation/hardhat-toolbox-viem'

// ESM-safe __dirname
const __filename = fileURLToPath(import.meta.url)
const __dirname = dirname(__filename)

loadEnv({ path: resolve(__dirname, '.env.hardhat.local') })

const privateKey = process.env.PRIVATE_KEY?.trim()
const mnemonic = process.env.MNEMONIC?.trim()
const accounts = privateKey ? [privateKey] : mnemonic ? { mnemonic } : undefined

// Hardhat v3 requires a "type" discriminator on each network
const networks: any = {
  hardhat: { type: 'edr-simulated' }
}

const addHttp = (name: string, url?: string) => {
  const u = url?.trim()
  if (!u) return
  networks[name] = { type: 'http', url: u, ...(accounts ? { accounts } : {}) }
}

addHttp('mainnet', process.env.MAINNET_RPC)
addHttp('polygon', process.env.POLYGON_RPC)
addHttp('optimism', process.env.OPTIMISM_RPC)
addHttp('arbitrum', process.env.ARBITRUM_RPC)
addHttp('sepolia', process.env.SEPOLIA_RPC)

const config: HardhatUserConfig = {
  solidity: {
    version: '0.8.28',
    settings: {
      optimizer: { enabled: true, runs: 200 },
      viaIR: true
    }
  },
  defaultNetwork: 'hardhat',
  networks,
  verify: { etherscan: { apiKey: process.env.ETHERSCAN_API_KEY || '' } },
  paths: {
    root: resolve(__dirname),
    sources: resolve(__dirname, 'contracts'),
    tests: resolve(__dirname, 'test'),
    cache: resolve(__dirname, 'cache'),
    artifacts: resolve(__dirname, '../../apps/dao-dapp/src/contracts')
  }
}

export default config
