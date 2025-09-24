import hre from 'hardhat'

async function main() {
  const { viem } = await hre.network.connect()
  const [deployer] = await viem.getWalletClients()
  const publicClient = await viem.getPublicClient()

  console.log(`Using deployer: ${deployer.account.address}`)

  const waitForDeployment = async <T extends { address: string; deploymentTransaction: { hash: `0x${string}` } }>(
    label: string,
    deployment: Promise<T>
  ) => {
    const contract = await deployment
    console.log(`⏳ Deploying ${label}...`)
    await publicClient.waitForTransactionReceipt({ hash: contract.deploymentTransaction.hash })
    console.log(`✅ ${label} deployed at ${contract.address}`)
    return contract
  }

  const timelockImpl = await waitForDeployment(
    'TimelockControllerImpl implementation',
    viem.deployContract('TimelockControllerImpl', [], { account: deployer.account })
  )

  const governorImpl = await waitForDeployment(
    'DAOGovernorImpl implementation',
    viem.deployContract('DAOGovernorImpl', [], { account: deployer.account })
  )

  const membershipImpl = await waitForDeployment(
    'MembershipNFTUpgradeable implementation',
    viem.deployContract('MembershipNFTUpgradeable', [], { account: deployer.account })
  )

  const treasuryImpl = await waitForDeployment(
    'SimpleTreasuryUpgradeable implementation',
    viem.deployContract('SimpleTreasuryUpgradeable', [], { account: deployer.account })
  )

  const kernelImpl = await waitForDeployment(
    'KernelUpgradeable implementation',
    viem.deployContract('KernelUpgradeable', [], { account: deployer.account })
  )

  const factory = await waitForDeployment(
    'DAOFactoryUUPS',
    viem.deployContract(
      'DAOFactoryUUPS',
      [
        timelockImpl.address,
        governorImpl.address,
        membershipImpl.address,
        treasuryImpl.address,
        kernelImpl.address
      ],
      { account: deployer.account }
    )
  )

  console.log('\nDeployment summary:')
  console.log(`  TimelockControllerImpl: ${timelockImpl.address}`)
  console.log(`  DAOGovernorImpl      : ${governorImpl.address}`)
  console.log(`  MembershipNFTImpl    : ${membershipImpl.address}`)
  console.log(`  SimpleTreasuryImpl   : ${treasuryImpl.address}`)
  console.log(`  KernelImpl           : ${kernelImpl.address}`)
  console.log(`  DAOFactoryUUPS       : ${factory.address}`)

  console.log('\nNext steps:')
  console.log('  • Use the factory to deploy a DAO instance when needed (e.g., via script or frontend).')
}

main().catch((error) => {
  console.error(error)
  process.exitCode = 1
})
