import hre from 'hardhat'

async function main() {
  const { viem } = await hre.network.connect()
  const [deployer] = await viem.getWalletClients()
  const networkName = hre.network.name
  const shouldVerify = process.env.VERIFY === 'true' && networkName !== 'hardhat'

  const verify = async (label: string, address: string, constructorArguments: unknown[] = []) => {
    if (!shouldVerify) return
    console.log(`🔍 Verifying ${label}...`)
    try {
      if (typeof hre.run === 'function') {
        await hre.run('verify:verify', {
          address,
          constructorArguments
        })
      } else {
        throw new Error('Verification task unavailable in this environment')
      }
      console.log(`✅ Verified ${label}`)
    } catch (error: any) {
      const message = (error?.message ?? '').toLowerCase()
      if (message.includes('already verified')) {
        console.log(`ℹ️  ${label} already verified`)
      } else {
        console.warn(`⚠️  Verification skipped for ${label}:`, error?.message ?? error)
      }
    }
  }

  console.log(`Using deployer: ${deployer.account.address}`)

  const timelockImpl = await viem.deployContract('TimelockControllerImpl', [], { account: deployer.account })
  console.log(`✅ TimelockControllerImpl implementation deployed at ${timelockImpl.address}`)
  await verify('TimelockControllerImpl implementation', timelockImpl.address)

  const governorImpl = await viem.deployContract('DAOGovernorImpl', [], { account: deployer.account })
  console.log(`✅ DAOGovernorImpl implementation deployed at ${governorImpl.address}`)
  await verify('DAOGovernorImpl implementation', governorImpl.address)

  const membershipImpl = await viem.deployContract('MembershipNFTUpgradeable', [], { account: deployer.account })
  console.log(`✅ MembershipNFTUpgradeable implementation deployed at ${membershipImpl.address}`)
  await verify('MembershipNFTUpgradeable implementation', membershipImpl.address)

  const treasuryImpl = await viem.deployContract('SimpleTreasuryUpgradeable', [], { account: deployer.account })
  console.log(`✅ SimpleTreasuryUpgradeable implementation deployed at ${treasuryImpl.address}`)
  await verify('SimpleTreasuryUpgradeable implementation', treasuryImpl.address)

  const kernelImpl = await viem.deployContract('KernelUpgradeable', [], { account: deployer.account })
  console.log(`✅ KernelUpgradeable implementation deployed at ${kernelImpl.address}`)
  await verify('KernelUpgradeable implementation', kernelImpl.address)

  const factory = await viem.deployContract(
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
  console.log(`✅ DAOFactoryUUPS deployed at ${factory.address}`)
  await verify('DAOFactoryUUPS', factory.address, [
    timelockImpl.address,
    governorImpl.address,
    membershipImpl.address,
    treasuryImpl.address,
    kernelImpl.address
  ])

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
