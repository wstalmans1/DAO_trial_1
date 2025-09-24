import { describe, it } from 'node:test'
import assert from 'node:assert/strict'
import hre from 'hardhat'
import { keccak256, toHex } from 'viem'

const MODULE_TIMELOCK = keccak256(toHex('MODULE_TIMELOCK'))
const MODULE_GOVERNOR = keccak256(toHex('MODULE_GOVERNOR'))
const MODULE_TOKEN = keccak256(toHex('MODULE_TOKEN'))
const MODULE_TREASURY = keccak256(toHex('MODULE_TREASURY'))

async function deployFactoryFixture() {
  const { viem } = await hre.network.connect()
  const [deployer, member1, member2] = await viem.getWalletClients()

  const timelockImpl = await viem.deployContract('TimelockControllerImpl')
  const governorImpl = await viem.deployContract('DAOGovernorImpl')
  const membershipImpl = await viem.deployContract('MembershipNFTUpgradeable')
  const treasuryImpl = await viem.deployContract('SimpleTreasuryUpgradeable')
  const kernelImpl = await viem.deployContract('KernelUpgradeable')

  const factory = await viem.deployContract('DAOFactoryUUPS', [
    timelockImpl.address,
    governorImpl.address,
    membershipImpl.address,
    treasuryImpl.address,
    kernelImpl.address
  ])

  const publicClient = await viem.getPublicClient()

  return {
    viem,
    deployer,
    member1,
    member2,
    factory,
    publicClient
  }
}

describe('DAOFactoryUUPS', () => {
  it('deploys full DAO stack and wires kernel modules correctly', async () => {
    const { viem, deployer, member1, factory, publicClient } = await deployFactoryFixture()

    const minDelay = 1n
    const initialMembers = [member1.account.address]

    const { result, request } = await factory.simulate.deployDao([
      minDelay,
      initialMembers
    ], { account: deployer.account })

    const [timelockAddr, nftAddr, governorAddr, treasuryAddr, kernelAddr] = result

    const txHash = await factory.write.deployDao(request)
    await publicClient.waitForTransactionReceipt({ hash: txHash })

    const kernel = await viem.getContractAt('KernelUpgradeable', kernelAddr)

    assert.equal(await kernel.read.module([MODULE_TIMELOCK]), timelockAddr)
    assert.equal(await kernel.read.module([MODULE_GOVERNOR]), governorAddr)
    assert.equal(await kernel.read.module([MODULE_TOKEN]), nftAddr)
    assert.equal(await kernel.read.module([MODULE_TREASURY]), treasuryAddr)

    const timelock = await viem.getContractAt('TimelockControllerImpl', timelockAddr)

    const proposerRole = await timelock.read.PROPOSER_ROLE()
    const executorRole = await timelock.read.EXECUTOR_ROLE()
    const adminRole = await timelock.read.DEFAULT_ADMIN_ROLE()

    assert.ok(await timelock.read.hasRole([proposerRole, governorAddr]))
    assert.ok(await timelock.read.hasRole([executorRole, '0x0000000000000000000000000000000000000000']))
    assert.ok(await timelock.read.hasRole([adminRole, timelockAddr]))
    assert.equal(await timelock.read.hasRole([adminRole, deployer.account.address]), false)

    const treasury = await viem.getContractAt('SimpleTreasuryUpgradeable', treasuryAddr)
    assert.equal(await treasury.read.owner(), timelockAddr)

    const membership = await viem.getContractAt('MembershipNFTUpgradeable', nftAddr)
    const addedDeployer = initialMembers.includes(deployer.account.address)
    const expectedMembers = initialMembers.length + (addedDeployer ? 0 : 1)
    assert.equal(await membership.read.memberCount(), BigInt(expectedMembers))
  })

  it('mints non-transferable one-vote NFTs to members', async () => {
    const { viem, deployer, member1, member2, factory, publicClient } = await deployFactoryFixture()

    const minDelay = 1n
    const initialMembers = [member1.account.address, member2.account.address]

    const { result, request } = await factory.simulate.deployDao([
      minDelay,
      initialMembers
    ], { account: deployer.account })

    const [, nftAddr] = result
    const txHash = await factory.write.deployDao(request)
    await publicClient.waitForTransactionReceipt({ hash: txHash })

    const membership = await viem.getContractAt('MembershipNFTUpgradeable', nftAddr)

    const expectedMembers = initialMembers.includes(deployer.account.address)
      ? initialMembers.length
      : initialMembers.length + 1
    assert.equal(await membership.read.memberCount(), BigInt(expectedMembers))

    const member1Token = await membership.read.tokenIdOf([member1.account.address])
    const member2Token = await membership.read.tokenIdOf([member2.account.address])
    const deployerToken = await membership.read.tokenIdOf([deployer.account.address])

    assert.equal(await membership.read.getVotes([member1.account.address]), 1n)
    assert.equal(await membership.read.getVotes([member2.account.address]), 1n)
    assert.equal(await membership.read.getVotes([deployer.account.address]), 1n)

    await viem.assertions.revert(
      membership.write.transferFrom([
        member1.account.address,
        deployer.account.address,
        member1Token
      ], { account: member1.account })
    )

    await viem.assertions.revert(
      membership.write.transferFrom([
        member2.account.address,
        deployer.account.address,
        member2Token
      ], { account: member2.account })
    )

    await viem.assertions.revert(
      membership.write.transferFrom([
        deployer.account.address,
        member1.account.address,
        deployerToken
      ], { account: deployer.account })
    )
  })
})
