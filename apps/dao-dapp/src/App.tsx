import { ConnectButton } from '@rainbow-me/rainbowkit'
import type { FormEvent } from 'react'
import { useMemo, useState } from 'react'
import { decodeEventLog } from 'viem'
import { useAccount, useChainId, usePublicClient, useWriteContract } from 'wagmi'

import daoFactoryArtifact from './contracts/contracts/factory/DAOFactoryUUPS.sol/DAOFactoryUUPS.json'

const factoryAbi = daoFactoryArtifact.abi
const factoryAddress = import.meta.env.VITE_FACTORY_ADDRESS
const factoryChainId = Number.parseInt(import.meta.env.VITE_FACTORY_CHAIN_ID ?? '11155111', 10)
const factoryChainLabel = import.meta.env.VITE_FACTORY_CHAIN_NAME ?? 'Sepolia'
const explorerBaseUrl = import.meta.env.VITE_BLOCK_EXPLORER_URL ?? 'https://eth-sepolia.blockscout.com'

const implementationAddresses = {
  timelock: import.meta.env.VITE_TIMELOCK_IMPL_ADDRESS as `0x${string}` | undefined,
  governor: import.meta.env.VITE_GOVERNOR_IMPL_ADDRESS as `0x${string}` | undefined,
  membership: import.meta.env.VITE_MEMBERSHIP_IMPL_ADDRESS as `0x${string}` | undefined,
  treasury: import.meta.env.VITE_TREASURY_IMPL_ADDRESS as `0x${string}` | undefined,
  kernel: import.meta.env.VITE_KERNEL_IMPL_ADDRESS as `0x${string}` | undefined
}

type DeploymentSummary = {
  timelock: string
  membershipNFT: string
  governor: string
  treasury: string
  kernel: string
}

export default function App() {
  const { isConnected, address } = useAccount()
  const chainId = useChainId()
  const publicClient = usePublicClient()
  const { writeContractAsync, isPending } = useWriteContract()

  const [minDelay, setMinDelay] = useState('180')
  const [membersInput, setMembersInput] = useState('')
  const [txHash, setTxHash] = useState<`0x${string}` | null>(null)
  const [deployment, setDeployment] = useState<DeploymentSummary | null>(null)
  const [error, setError] = useState<string | null>(null)
  const [successMessage, setSuccessMessage] = useState<string | null>(null)

  const formattedFactoryAddress = useMemo(() => {
    if (!factoryAddress) return undefined
    return factoryAddress as `0x${string}`
  }, [factoryAddress])

  const hasKnownImpls = useMemo(() => {
    return (
      !!formattedFactoryAddress ||
      Object.values(implementationAddresses).some((addr) => !!addr)
    )
  }, [formattedFactoryAddress])

  const needsNetworkSwitch = useMemo(() => {
    if (!factoryChainId || !chainId) return false
    return chainId !== factoryChainId
  }, [chainId, factoryChainId])

  const parseMemberAddresses = (raw: string) => {
    const tokens = raw
      .split(/[\s,;]+/)
      .map((token) => token.trim())
      .filter(Boolean)
      .map((token) => token.toLowerCase())

    const unique = Array.from(new Set(tokens))

    for (const addr of unique) {
      if (!/^0x[a-f0-9]{40}$/.test(addr)) {
        throw new Error(`Invalid member address: ${addr}`)
      }
    }

    return unique as `0x${string}`[]
  }

  const handleDeploy = async (event: FormEvent<HTMLFormElement>) => {
    event.preventDefault()
    setError(null)
    setSuccessMessage(null)
    setDeployment(null)
    setTxHash(null)

    if (!isConnected || !address) {
      setError('Connect your wallet before deploying a DAO.')
      return
    }

    if (!formattedFactoryAddress) {
      setError('Factory address is not configured. Set VITE_FACTORY_ADDRESS in your environment.')
      return
    }

    if (needsNetworkSwitch) {
      setError(`Please switch your wallet to the ${factoryChainLabel} network before deploying.`)
      return
    }

    let minDelayValue: bigint
    try {
      minDelayValue = BigInt(minDelay)
    } catch (err) {
      setError('Minimum delay must be a positive integer (in seconds).')
      return
    }

    if (minDelayValue < 0n) {
      setError('Minimum delay must be zero or greater.')
      return
    }

    let memberAddresses: `0x${string}`[]
    try {
      memberAddresses = parseMemberAddresses(membersInput)
    } catch (err) {
      setError((err as Error).message)
      return
    }

    if (!publicClient) {
      setError('No public client available. Ensure wagmi is configured correctly.')
      return
    }

    try {
      const hash = await writeContractAsync({
        address: formattedFactoryAddress,
        abi: factoryAbi,
        functionName: 'deployDao',
        args: [minDelayValue, memberAddresses],
        account: address
      })

      setTxHash(hash)
      const receipt = await publicClient.waitForTransactionReceipt({ hash })

      const daoEventLog = receipt.logs
        .map((log) => {
          try {
            const decoded = decodeEventLog({ abi: factoryAbi, data: log.data, topics: log.topics })
            return decoded
          } catch {
            return null
          }
        })
        .find((decoded) => decoded?.eventName === 'DaoGenesis')

      if (daoEventLog?.args && typeof daoEventLog.args === 'object') {
        const { timelock, membershipNFT, governor, treasury, kernel } = daoEventLog.args as unknown as Record<string, string>
        setDeployment({ timelock, membershipNFT, governor, treasury, kernel })
        setSuccessMessage('DAO deployed successfully!')
      } else {
        setSuccessMessage('DAO deployed. Event decoding failed; check the explorer for details.')
      }

      setMembersInput('')
    } catch (err) {
      console.error(err)
      setError((err as Error).message ?? 'Deployment failed. Check the console for details.')
    }
  }

  return (
    <div className="min-h-screen bg-slate-950 text-slate-100">
      <div className="mx-auto w-full max-w-5xl px-6 py-10 space-y-8">
        <header className="flex flex-col gap-4 sm:flex-row sm:items-center sm:justify-between sm:gap-6">
          <div className="flex-1">
            <h1 className="text-3xl font-bold">Launch Your DAO</h1>
            <p className="text-slate-400 text-sm">
              Deploy a fresh governance stack in one transaction using the DAOFactory.
            </p>
          </div>
          <div className="flex justify-end sm:w-auto">
            <ConnectButton chainStatus="full" showBalance={true} />
          </div>
        </header>

        <section className="bg-slate-900 border border-slate-800 rounded-2xl p-6 space-y-4 shadow-lg">
          <h2 className="text-xl font-semibold">Deployment Parameters</h2>
          <p className="text-sm text-slate-400">
            The factory deploys a timelock, membership NFT (soulbound, one vote per member), treasury, governor, and kernel.
            The deployer automatically becomes a member and relinquishes setup privileges to the timelock.
          </p>

          {hasKnownImpls && (
            <div className="rounded-lg border border-slate-800 bg-slate-950 p-4 text-xs text-slate-400">
              <p className="mb-2 text-sm font-semibold text-slate-200">Current Implementation Addresses</p>
              <ul className="space-y-1">
                {formattedFactoryAddress && (
                  <li>
                    Factory:{' '}
                    <a
                      className="text-emerald-300 hover:underline"
                      href={`${explorerBaseUrl}/address/${formattedFactoryAddress}`}
                      target="_blank"
                      rel="noreferrer"
                    >
                      {formattedFactoryAddress}
                    </a>
                  </li>
                )}
                {implementationAddresses.timelock && (
                  <li>
                    Timelock Impl:{' '}
                    <a
                      className="text-emerald-300 hover:underline"
                      href={`${explorerBaseUrl}/address/${implementationAddresses.timelock}`}
                      target="_blank"
                      rel="noreferrer"
                    >
                      {implementationAddresses.timelock}
                    </a>
                  </li>
                )}
                {implementationAddresses.membership && (
                  <li>
                    Membership NFT Impl:{' '}
                    <a
                      className="text-emerald-300 hover:underline"
                      href={`${explorerBaseUrl}/address/${implementationAddresses.membership}`}
                      target="_blank"
                      rel="noreferrer"
                    >
                      {implementationAddresses.membership}
                    </a>
                  </li>
                )}
                {implementationAddresses.governor && (
                  <li>
                    Governor Impl:{' '}
                    <a
                      className="text-emerald-300 hover:underline"
                      href={`${explorerBaseUrl}/address/${implementationAddresses.governor}`}
                      target="_blank"
                      rel="noreferrer"
                    >
                      {implementationAddresses.governor}
                    </a>
                  </li>
                )}
                {implementationAddresses.treasury && (
                  <li>
                    Treasury Impl:{' '}
                    <a
                      className="text-emerald-300 hover:underline"
                      href={`${explorerBaseUrl}/address/${implementationAddresses.treasury}`}
                      target="_blank"
                      rel="noreferrer"
                    >
                      {implementationAddresses.treasury}
                    </a>
                  </li>
                )}
                {implementationAddresses.kernel && (
                  <li>
                    Kernel Impl:{' '}
                    <a
                      className="text-emerald-300 hover:underline"
                      href={`${explorerBaseUrl}/address/${implementationAddresses.kernel}`}
                      target="_blank"
                      rel="noreferrer"
                    >
                      {implementationAddresses.kernel}
                    </a>
                  </li>
                )}
              </ul>
            </div>
          )}

          {!formattedFactoryAddress && (
            <div className="rounded-lg border border-amber-500/40 bg-amber-500/10 p-4 text-sm text-amber-200">
              <strong>Configuration required:</strong> set <code>VITE_FACTORY_ADDRESS</code> in your environment before using the launcher.
            </div>
          )}

          {needsNetworkSwitch && (
            <div className="rounded-lg border border-amber-500/40 bg-amber-500/10 p-4 text-sm text-amber-200">
              Please switch your wallet to <strong>{factoryChainLabel}</strong> (chain ID {factoryChainId}).
            </div>
          )}

          {error && (
            <div className="rounded-lg border border-rose-500/40 bg-rose-500/10 p-4 text-sm text-rose-200">
              {error}
            </div>
          )}

          {successMessage && (
            <div className="rounded-lg border border-emerald-500/40 bg-emerald-500/10 p-4 text-sm text-emerald-200">
              {successMessage}
            </div>
          )}

          <form className="space-y-6" onSubmit={handleDeploy}>
            <div className="grid gap-4">
              <label className="flex flex-col gap-2 text-sm">
                <span className="text-slate-200 font-medium">Timelock Min Delay (seconds)</span>
                <input
                  type="number"
                  min="0"
                  className="rounded-md border border-slate-700 bg-slate-950 px-3 py-2 text-sm focus:border-emerald-500 focus:outline-none"
                  value={minDelay}
                  onChange={(event) => setMinDelay(event.target.value)}
                  placeholder="86400"
                  required
                />
              </label>

              <label className="flex flex-col gap-2 text-sm">
                <span className="text-slate-200 font-medium">Member Addresses (one per line or comma separated)</span>
                <textarea
                  className="min-h-[120px] rounded-md border border-slate-700 bg-slate-950 px-3 py-2 text-sm focus:border-emerald-500 focus:outline-none"
                  value={membersInput}
                  onChange={(event) => setMembersInput(event.target.value)}
                  placeholder={`0xabc...123\n0xdef...456`}
                />
                <span className="text-xs text-slate-500">
                  Members you list here each receive one soulbound vote token. The deployer is added automatically.
                </span>
              </label>
            </div>

            <button
              type="submit"
              disabled={!formattedFactoryAddress || isPending || needsNetworkSwitch}
              className="inline-flex items-center justify-center rounded-md bg-emerald-500 px-4 py-2 text-sm font-medium text-emerald-950 hover:bg-emerald-400 disabled:cursor-not-allowed disabled:opacity-60"
            >
              {isPending ? 'Deploying…' : 'Deploy DAO'}
            </button>
          </form>

          {txHash && (
            <p className="text-xs text-slate-400">
              Transaction:{' '}
              <a
                className="text-emerald-300 hover:underline"
                href={`${explorerBaseUrl}/tx/${txHash}`}
                target="_blank"
                rel="noreferrer"
              >
                {txHash}
              </a>
            </p>
          )}

          {deployment && (
            <div className="mt-4 space-y-2 rounded-lg border border-slate-800 bg-slate-950 p-4 text-sm">
              <h3 className="text-base font-semibold text-slate-200">Deployed Module Addresses</h3>
              <ul className="space-y-1 text-xs text-slate-400">
                <li>
                  <span className="font-medium text-slate-300">Timelock:</span>{' '}
                  <a className="text-emerald-300 hover:underline" href={`${explorerBaseUrl}/address/${deployment.timelock}`} target="_blank" rel="noreferrer">
                    {deployment.timelock}
                  </a>
                </li>
                <li>
                  <span className="font-medium text-slate-300">Membership NFT:</span>{' '}
                  <a className="text-emerald-300 hover:underline" href={`${explorerBaseUrl}/address/${deployment.membershipNFT}`} target="_blank" rel="noreferrer">
                    {deployment.membershipNFT}
                  </a>
                </li>
                <li>
                  <span className="font-medium text-slate-300">Governor:</span>{' '}
                  <a className="text-emerald-300 hover:underline" href={`${explorerBaseUrl}/address/${deployment.governor}`} target="_blank" rel="noreferrer">
                    {deployment.governor}
                  </a>
                </li>
                <li>
                  <span className="font-medium text-slate-300">Treasury:</span>{' '}
                  <a className="text-emerald-300 hover:underline" href={`${explorerBaseUrl}/address/${deployment.treasury}`} target="_blank" rel="noreferrer">
                    {deployment.treasury}
                  </a>
                </li>
                <li>
                  <span className="font-medium text-slate-300">Kernel:</span>{' '}
                  <a className="text-emerald-300 hover:underline" href={`${explorerBaseUrl}/address/${deployment.kernel}`} target="_blank" rel="noreferrer">
                    {deployment.kernel}
                  </a>
                </li>
              </ul>
            </div>
          )}
        </section>
      </div>
    </div>
  )
}
