#!/usr/bin/env bash
set -euo pipefail

# -----------------------------------------------------------------------------
# Bootstrap script to recreate a DApp-setup workspace in the CURRENT folder.
#
# How to use (from an EMPTY folder where you want to create the project):
# 1) Save this file as DApp-setup.sh in that empty folder.
# 2) Open a terminal and cd into that folder.
# 3) Run one of the following:
#      bash DApp-setup.sh
#    OR
#      chmod +x DApp-setup.sh && ./DApp-setup.sh
# 4) After it finishes (no new subfolder is created):
#      pnpm contracts:compile
#      pnpm web:dev
#
# Required parameters (edit apps/dao-dapp/.env.local after script runs):
# - VITE_WALLETCONNECT_ID: Your WalletConnect Cloud Project ID
# - VITE_MAINNET_RPC: HTTPS RPC URL for Ethereum mainnet (no websockets)
# - VITE_POLYGON_RPC: HTTPS RPC URL for Polygon
# - VITE_OPTIMISM_RPC: HTTPS RPC URL for Optimism
# - VITE_ARBITRUM_RPC: HTTPS RPC URL for Arbitrum
# - VITE_SEPOLIA_RPC: HTTPS RPC URL for Sepolia testnet
#
# Additional contract deployment parameters (edit packages/contracts/.env.hardhat.local):
# - PRIVATE_KEY or MNEMONIC: Credentials for contract deployment
# - MAINNET_RPC / POLYGON_RPC / OPTIMISM_RPC / ARBITRUM_RPC / SEPOLIA_RPC
# - ETHERSCAN_API_KEY (or per-explorer keys via verify config)
#
# Notes:
# - Only HTTP endpoints are configured (no WebSockets) to avoid WS errors.
# - You can replace public endpoints with Infura/Alchemy/QuickNode URLs for reliability.
#
# Prerequisites:
# - Node.js 22 LTS recommended
# - Corepack available (the script checks and enables it)
# - Internet access
# -----------------------------------------------------------------------------

# --- Corepack & pnpm ----------------------------------------------------------------
command -v corepack >/dev/null 2>&1 || {
  echo "Corepack not found. Please install Node.js >= 22 (22 LTS recommended) and retry." >&2
  exit 1
}
corepack enable
export COREPACK_ENABLE_DOWNLOAD_PROMPT=0
corepack prepare pnpm@10.16.1 --activate

# Pin Node LTS for dev shells
printf "v22\n" > .nvmrc

# --- Root files ---------------------------------------------------------------------
# .gitignore
cat > .gitignore <<'EOF'
node_modules
dist
.env
.env.*
packages/contracts/cache
packages/contracts/artifacts
packages/contracts/typechain-types
packages/contracts/.env.hardhat.local
apps/dao-dapp/src/contracts/*
!apps/dao-dapp/src/contracts/.gitkeep
EOF

# package.json (root)
cat > package.json <<'EOF'
{
  "name": "dapp_setup",
  "private": true,
  "packageManager": "pnpm@10.16.1",
  "engines": { "node": ">=22 <23" },
  "scripts": {
    "web:dev": "pnpm -C apps/dao-dapp dev",
    "web:build": "pnpm -C apps/dao-dapp build",
    "web:preview": "pnpm -C apps/dao-dapp preview",
    "contracts:compile": "pnpm -C packages/contracts hardhat compile",
    "contracts:test": "pnpm -C packages/contracts hardhat test",
    "contracts:deploy": "pnpm -C packages/contracts hardhat run scripts/deploy.ts",
    "contracts:verify": "pnpm -C packages/contracts hardhat verify"
  }
}
EOF

# pnpm workspace
cat > pnpm-workspace.yaml <<'EOF'
packages:
  - "apps/*"
  - "packages/*"
EOF

# --- App scaffold (Vite + React + TS) -----------------------------------------------
mkdir -p apps
if [ -d "apps/dao-dapp" ]; then
  echo "apps/dao-dapp already exists; skipping Vite scaffold."
else
  # Pin Vite major to reduce template churn
  pnpm create vite@6 apps/dao-dapp -- --template react-ts --no-git --package-manager pnpm
fi
pnpm -C apps/dao-dapp install

# --- App deps (web3 + styling) ------------------------------------------------------
# Pin compatible versions (wagmi v2 + RainbowKit v2 + viem v2 + TanStack Query v5)
pnpm -C apps/dao-dapp add @rainbow-me/rainbowkit@~2.2.8 wagmi@~2.16.9 viem@~2.37.6 @tanstack/react-query@~5.89.0

# Tailwind v4 (PostCSS plugin)
pnpm -C apps/dao-dapp add -D tailwindcss@~4.0.0 @tailwindcss/postcss@~4.0.0 postcss@~8.4.47

# postcss.config (use ESM; v4 plugin)
if [ ! -f apps/dao-dapp/postcss.config.mjs ]; then
  cat > apps/dao-dapp/postcss.config.mjs <<'EOF'
export default { plugins: { '@tailwindcss/postcss': {} } }
EOF
fi

# Tailwind entry (v4 style)
mkdir -p apps/dao-dapp/src
cat > apps/dao-dapp/src/index.css <<'EOF'
@import "tailwindcss";
EOF

# Shared contracts artifacts folder for the web app
mkdir -p apps/dao-dapp/src/contracts
if [ ! -f apps/dao-dapp/src/contracts/.gitkeep ]; then
  cat > apps/dao-dapp/src/contracts/.gitkeep <<'EOF'
# Generated contract artifacts are ignored by git but kept for tooling.
EOF
fi

# Minimal Wagmi/RainbowKit config (HTTP only)
mkdir -p apps/dao-dapp/src/config
if [ ! -f apps/dao-dapp/src/config/wagmi.ts ]; then
  cat > apps/dao-dapp/src/config/wagmi.ts <<'EOF'
import { getDefaultConfig } from '@rainbow-me/rainbowkit'
import { mainnet, polygon, optimism, arbitrum, sepolia } from 'wagmi/chains'
import { http } from 'wagmi'

export const config = getDefaultConfig({
  appName: 'DAO dApp',
  projectId: import.meta.env.VITE_WALLETCONNECT_ID!,
  chains: [mainnet, polygon, optimism, arbitrum, sepolia],
  transports: {
    [mainnet.id]: http(import.meta.env.VITE_MAINNET_RPC!),
    [polygon.id]: http(import.meta.env.VITE_POLYGON_RPC!),
    [optimism.id]: http(import.meta.env.VITE_OPTIMISM_RPC!),
    [arbitrum.id]: http(import.meta.env.VITE_ARBITRUM_RPC!),
    [sepolia.id]: http(import.meta.env.VITE_SEPOLIA_RPC!)
  },
  ssr: false
})
EOF
fi

# main.tsx providers
cat > apps/dao-dapp/src/main.tsx <<'EOF'
import React from 'react'
import ReactDOM from 'react-dom/client'
import { WagmiProvider } from 'wagmi'
import { QueryClient, QueryClientProvider } from '@tanstack/react-query'
import { RainbowKitProvider } from '@rainbow-me/rainbowkit'
import '@rainbow-me/rainbowkit/styles.css'

import { config } from './config/wagmi'
import App from './App'
import './index.css'

const qc = new QueryClient()

ReactDOM.createRoot(document.getElementById('root')!).render(
  <React.StrictMode>
    <WagmiProvider config={config}>
      <QueryClientProvider client={qc}>
        <RainbowKitProvider>
          <App />
        </RainbowKitProvider>
      </QueryClientProvider>
    </WagmiProvider>
  </React.StrictMode>
)
EOF

# Minimal App
cat > apps/dao-dapp/src/App.tsx <<'EOF'
import { ConnectButton } from '@rainbow-me/rainbowkit'

export default function App() {
  return (
    <div className="min-h-screen p-6">
      <header className="flex items-center justify-between">
        <h1 className="text-2xl font-bold">DAO dApp</h1>
        <ConnectButton />
      </header>
    </div>
  )
}
EOF

# Env example
if [ ! -f apps/dao-dapp/.env.example ]; then
  cat > apps/dao-dapp/.env.example <<'EOF'
VITE_WALLETCONNECT_ID=
VITE_MAINNET_RPC=https://cloudflare-eth.com
VITE_POLYGON_RPC=https://polygon-rpc.com
VITE_OPTIMISM_RPC=https://optimism.publicnode.com
VITE_ARBITRUM_RPC=https://arbitrum.publicnode.com
VITE_SEPOLIA_RPC=https://rpc.sepolia.org
EOF
fi
[ -f apps/dao-dapp/.env.local ] || cp apps/dao-dapp/.env.example apps/dao-dapp/.env.local

# --- Contracts workspace (Hardhat 3 + TS) -------------------------------------------
mkdir -p packages/contracts

# package.json (contracts)
cat > packages/contracts/package.json <<'EOF'
{
  "name": "contracts",
  "private": true,
  "scripts": {
    "clean": "hardhat clean",
    "compile": "hardhat compile",
    "test": "hardhat test",
    "deploy": "hardhat run scripts/deploy.ts"
  }
}
EOF

# tsconfig (contracts)
cat > packages/contracts/tsconfig.json <<'EOF'
{
  "extends": "@tsconfig/node22/tsconfig.json",
  "compilerOptions": {
    "target": "ES2022",
    "module": "NodeNext",
    "strict": true,
    "esModuleInterop": true,
    "moduleResolution": "NodeNext",
    "resolveJsonModule": true,
    "outDir": "dist",
    "types": ["node", "hardhat"]
  },
  "include": ["hardhat.config.ts", "scripts", "test", "typechain-types"],
  "exclude": ["dist"]
}
EOF

# Hardhat config (v3-style verify config + HTTP networks)
cat > packages/contracts/hardhat.config.ts <<'EOF'
import { resolve } from 'path'
import { config as loadEnv } from 'dotenv'
import type { HardhatUserConfig } from 'hardhat/config'
import '@nomicfoundation/hardhat-toolbox'

loadEnv({ path: resolve(__dirname, '.env.hardhat.local') })

const privateKey = process.env.PRIVATE_KEY?.trim()
const mnemonic = process.env.MNEMONIC?.trim()

const accounts = (() => {
  if (privateKey) return [privateKey]
  if (mnemonic) return { mnemonic }
  return undefined
})()

const networks: Record<string, any> = {
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
    version: '0.8.28',
    settings: {
      optimizer: { enabled: true, runs: 200 }
    }
  },
  defaultNetwork: 'hardhat',
  networks,
  verify: {
    // Single Etherscan-family key works for Etherscan; for others (Polygonscan, Arbiscan),
    // you can also pass per-network keys here if needed.
    etherscan: {
      apiKey: process.env.ETHERSCAN_API_KEY || ''
    }
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
EOF

# Contracts dirs and placeholders
mkdir -p packages/contracts/contracts
[ -f packages/contracts/contracts/.gitkeep ] || cat > packages/contracts/contracts/.gitkeep <<'EOF'
# Add your Solidity contracts here.
EOF

mkdir -p packages/contracts/scripts
cat > packages/contracts/scripts/deploy.ts <<'EOF'
async function main() {
  console.log('Implement deployments in packages/contracts/scripts/deploy.ts before running this command.')
}

main().catch((error) => {
  console.error(error)
  process.exitCode = 1
})
EOF

mkdir -p packages/contracts/test
[ -f packages/contracts/test/.gitkeep ] || cat > packages/contracts/test/.gitkeep <<'EOF'
# Add your Hardhat tests here.
EOF

# .env examples
cat > packages/contracts/.env.hardhat.example <<'EOF'
# Private key or mnemonic for deployments (set one of the two)
PRIVATE_KEY=
MNEMONIC=

# RPC endpoints (HTTPS)
MAINNET_RPC=
POLYGON_RPC=
OPTIMISM_RPC=
ARBITRUM_RPC=
SEPOLIA_RPC=

# Block explorer API keys (Etherscan family; a single Etherscan key may work for Etherscan networks)
ETHERSCAN_API_KEY=
EOF
[ -f packages/contracts/.env.hardhat.local ] || cp packages/contracts/.env.hardhat.example packages/contracts/.env.hardhat.local

# Dev deps for contracts (Hardhat 3 + toolbox + TS)
pnpm -C packages/contracts add -D hardhat@^3 @nomicfoundation/hardhat-toolbox@^6.1.0 typescript@~5.9.2 ts-node@~10.9.2 @types/node@^22 dotenv@^16 @tsconfig/node22@^22.0.2
pnpm -C packages/contracts install

# Install workspace deps (root lockfile)
pnpm install

# --- Git init (optional, resilient) -------------------------------------------------
if command -v git >/dev/null 2>&1; then
  git init
  git add -A
  git -c user.name="bootstrap" -c user.email="bootstrap@local" commit -m "chore: bootstrap web app and contracts workspace" || true
fi

echo
echo "Done. Next steps:"
echo "1) Edit apps/dao-dapp/.env.local (set VITE_WALLETCONNECT_ID and RPC URLs)"
echo "2) Edit packages/contracts/.env.hardhat.local (set deployer key, RPC URLs, explorer key)"
echo "3) pnpm contracts:compile"
echo "4) pnpm web:dev"
