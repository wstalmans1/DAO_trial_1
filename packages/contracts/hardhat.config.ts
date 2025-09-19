import { resolve } from 'path'
import { config as loadEnv } from 'dotenv'
import { HardhatUserConfig } from 'hardhat/config'
import { NetworkUserConfig } from 'hardhat/types'
import '@nomicfoundation/hardhat-toolbox'

loadEnv({ path: resolve(__dirname, '.env.hardhat.local') })

const privateKey = process.env.PRIVATE_KEY?.trim()
const mnemonic = process.env.MNEMONIC?.trim()

const accounts = (() => {
  if (privateKey) return [privateKey]
  if (mnemonic) return { mnemonic }
  return undefined
})()

const networks: Record<string, NetworkUserConfig> = {
  hardhat: {}
}

const addNetwork = (name: string, rpcUrl?: string) => {
  const url = rpcUrl?.trim()
  if (!url) return
  networks[name] = {
    url,
    ...(accounts ? { accounts } : {})
  }
}

addNetwork('mainnet', process.env.MAINNET_RPC)
addNetwork('polygon', process.env.POLYGON_RPC)
addNetwork('optimism', process.env.OPTIMISM_RPC)
addNetwork('arbitrum', process.env.ARBITRUM_RPC)
addNetwork('sepolia', process.env.SEPOLIA_RPC)

const config: HardhatUserConfig = {
  solidity: {
    version: '0.8.24',
    settings: {
      optimizer: { enabled: true, runs: 200 }
    }
  },
  defaultNetwork: 'hardhat',
  networks,
  etherscan: {
    apiKey: process.env.ETHERSCAN_API_KEY || ''
  },
  paths: {
    root: resolve(__dirname),
    sources: resolve(__dirname, 'contracts'),
    tests: resolve(__dirname, 'test'),
    cache: resolve(__dirname, 'cache'),
    artifacts: resolve(__dirname, '../../apps/dao-dapp/src/contracts')
  }
}

export default config
