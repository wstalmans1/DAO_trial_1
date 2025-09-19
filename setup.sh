#!/usr/bin/env bash
set -euo pipefail

# -----------------------------------------------------------------------------
# setup.sh — Node 22 + React 18 + wagmi/RainbowKit + Tailwind v4 + Hardhat 3 (ESM-safe)
#
# Usage (from an EMPTY folder, or rerun safely to repair an existing setup):
#   bash setup.sh
#
# What you get:
# - apps/dao-dapp : Vite + React 18 + RainbowKit v2 + wagmi v2 + TanStack Query v5 + Tailwind v4
# - packages/contracts : Hardhat v3 (ESM) + @nomicfoundation/hardhat-toolbox-viem
#
# After it finishes:
#   1) Edit apps/dao-dapp/.env.local  (VITE_WALLETCONNECT_ID + RPCs)
#   2) Edit packages/contracts/.env.hardhat.local  (PRIVATE_KEY/MNEMONIC + RPCs + ETHERSCAN key)
#   3) (Optional) Approve native builds for speed: pnpm approve-builds
#      -> select: bufferutil, utf-8-validate, keccak, secp256k1
#   4) Compile contracts: pnpm contracts:compile
#   5) Start web app:     pnpm web:dev
# -----------------------------------------------------------------------------

# --- Corepack & pnpm ---------------------------------------------------------------
command -v corepack >/dev/null 2>&1 || {
  echo "Corepack not found. Install Node.js >= 22 and retry." >&2
  exit 1
}
corepack enable
export COREPACK_ENABLE_DOWNLOAD_PROMPT=0
corepack prepare pnpm@10.16.1 --activate

# Pin Node 22 for dev shells
printf "v22\n" > .nvmrc

# --- Root files --------------------------------------------------------------------
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

cat > package.json <<'EOF'
{
  "name": "dapp_setup",
  "private": true,
  "packageManager": "pnpm@10.16.1",
  "engines": { "node": ">=22 <23" },
  "scripts": {
    "web:dev": "pnpm --dir apps/dao-dapp dev",
    "web:build": "pnpm --dir apps/dao-dapp build",
    "web:preview": "pnpm --dir apps/dao-dapp preview",

    "contracts:compile": "pnpm --filter contracts run compile",
    "contracts:test": "pnpm --filter contracts run test",
    "contracts:deploy": "pnpm --filter contracts run deploy",
    "contracts:verify": "pnpm --filter contracts exec hardhat verify"
  }
}
EOF

cat > pnpm-workspace.yaml <<'EOF'
packages:
  - "apps/*"
  - "packages/*"
EOF

# --- App scaffold (Vite + React + TS) ----------------------------------------------
mkdir -p apps
if [ -d "apps/dao-dapp" ]; then
  echo "apps/dao-dapp already exists; keeping it and ensuring deps/configs are correct."
else
  pnpm create vite@6 apps/dao-dapp -- --template react-ts --no-git --package-manager pnpm
fi

# Force React 18 (web3 peers target <=18)
pnpm --dir apps/dao-dapp add react@18.3.1 react-dom@18.3.1
pnpm --dir apps/dao-dapp add -D @types/react@18.3.12 @types/react-dom@18.3.1

# Web3 + data
pnpm --dir apps/dao-dapp add @rainbow-me/rainbowkit@~2.2.8 wagmi@~2.16.9 viem@~2.37.6 @tanstack/react-query@~5.89.0

# Tailwind v4 (PostCSS plugin)
pnpm --dir apps/dao-dapp add -D tailwindcss@~4.0.0 @tailwindcss/postcss@~4.0.0 postcss@~8.4.47

# postcss.config (ESM)
cat > apps/dao-dapp/postcss.config.mjs <<'EOF'
export default { plugins: { '@tailwindcss/postcss': {} } }
EOF

# Tailwind entry
mkdir -p apps/dao-dapp/src
cat > apps/dao-dapp/src/index.css <<'EOF'
@import "tailwindcss";
EOF

# Contracts artifacts bucket (consumed by the app)
mkdir -p apps/dao-dapp/src/contracts
cat > apps/dao-dapp/src/contracts/.gitkeep <<'EOF'
# Generated contract artifacts are ignored by git but kept for tooling.
EOF

# Wagmi/RainbowKit config (HTTP only)
mkdir -p apps/dao-dapp/src/config
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

# main.tsx providers (overwrite to ensure stable setup)
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

# Minimal App (overwrite harmlessly)
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

# Env example + local
cat > apps/dao-dapp/.env.example <<'EOF'
VITE_WALLETCONNECT_ID=
VITE_MAINNET_RPC=https://cloudflare-eth.com
VITE_POLYGON_RPC=https://polygon-rpc.com
VITE_OPTIMISM_RPC=https://optimism.publicnode.com
VITE_ARBITRUM_RPC=https://arbitrum.publicnode.com
VITE_SEPOLIA_RPC=https://rpc.sepolia.org
EOF
cp -f apps/dao-dapp/.env.example apps/dao-dapp/.env.local

# Ensure app node_modules present
pnpm --dir apps/dao-dapp install

# --- Contracts workspace (Hardhat 3 + toolbox-viem + TS, ESM) -----------------------
mkdir -p packages/contracts

# contracts/package.json — ESM required by Hardhat 3
cat > packages/contracts/package.json <<'EOF'
{
  "name": "contracts",
  "private": true,
  "type": "module",
  "scripts": {
    "clean": "hardhat clean",
    "compile": "hardhat compile",
    "test": "hardhat test",
    "deploy": "hardhat run scripts/deploy.ts"
  }
}
EOF

# tsconfig — NodeNext/ESM
cat > packages/contracts/tsconfig.json <<'EOF'
{
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

# hardhat.config.ts — ESM-safe __dirname + toolbox-viem + unified verify
cat > packages/contracts/hardhat.config.ts <<'EOF'
import { fileURLToPath } from 'node:url'
import { dirname, resolve } from 'node:path'
import { config as loadEnv } from 'dotenv'
import type { HardhatUserConfig, NetworkUserConfig } from 'hardhat/config'
import '@nomicfoundation/hardhat-toolbox-viem'

// ESM-safe __dirname
const __filename = fileURLToPath(import.meta.url)
const __dirname = dirname(__filename)

loadEnv({ path: resolve(__dirname, '.env.hardhat.local') })

const privateKey = process.env.PRIVATE_KEY?.trim()
const mnemonic = process.env.MNEMONIC?.trim()
const accounts = privateKey ? [privateKey] : mnemonic ? { mnemonic } : undefined

const networks: Record<string, NetworkUserConfig> = { hardhat: {} }
const addNetwork = (name: string, url?: string) => {
  const u = url?.trim()
  if (!u) return
  networks[name] = { url: u, ...(accounts ? { accounts } : {}) }
}

addNetwork('mainnet', process.env.MAINNET_RPC)
addNetwork('polygon', process.env.POLYGON_RPC)
addNetwork('optimism', process.env.OPTIMISM_RPC)
addNetwork('arbitrum', process.env.ARBITRUM_RPC)
addNetwork('sepolia', process.env.SEPOLIA_RPC)

const config: HardhatUserConfig = {
  solidity: { version: '0.8.28', settings: { optimizer: { enabled: true, runs: 200 } } },
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
EOF

# Contracts dirs and placeholders
mkdir -p packages/contracts/contracts
cat > packages/contracts/contracts/.gitkeep <<'EOF'
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
cat > packages/contracts/test/.gitkeep <<'EOF'
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

# Block explorer API key (Etherscan family)
ETHERSCAN_API_KEY=
EOF
cp -f packages/contracts/.env.hardhat.example packages/contracts/.env.hardhat.local

# Dev deps for contracts (HH3 + toolbox-viem + TS)
pnpm --dir packages/contracts add -D hardhat@^3 @nomicfoundation/hardhat-toolbox-viem@^5.0.0 typescript@~5.9.2 ts-node@~10.9.2 @types/node@^22 dotenv@^16
pnpm --dir packages/contracts install

# Install workspace deps (root lockfile)
pnpm install

# --- Git init (optional, resilient) ------------------------------------------------
if command -v git >/dev/null 2>&1; then
  git init
  git add -A
  git -c user.name="bootstrap" -c user.email="bootstrap@local" commit -m "chore: bootstrap web app and contracts workspace" || true
fi

echo
echo "Done. Next steps:"
echo "1) Edit apps/dao-dapp/.env.local  (set VITE_WALLETCONNECT_ID and RPC URLs)"
echo "2) Edit packages/contracts/.env.hardhat.local  (set deployer key, RPC URLs, explorer key)"
echo "3) If you see 'Ignored build scripts' warnings and want native speedups, run:"
echo "     pnpm approve-builds   # select: bufferutil, utf-8-validate, keccak, secp256k1"
echo "4) Compile contracts: pnpm contracts:compile"
echo "5) Start web app:     pnpm web:dev"
