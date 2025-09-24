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

  const timelockImpl = await viem.deployContract('TimelockControllerImplementation', [], { account: deployer.account })
  console.log(`✅ TimelockControllerImplementation deployed at ${timelockImpl.address}`)
  await verify('TimelockControllerImplementation', timelockImpl.address)

  const governorImpl = await viem.deployContract('DAOGovernorImplementation', [], { account: deployer.account })
  console.log(`✅ DAOGovernorImplementation deployed at ${governorImpl.address}`)
  await verify('DAOGovernorImplementation', governorImpl.address)

  const membershipImpl = await viem.deployContract('MembershipNFTImplementation', [], { account: deployer.account })
  console.log(`✅ MembershipNFTImplementation deployed at ${membershipImpl.address}`)
  await verify('MembershipNFTImplementation', membershipImpl.address)

  const treasuryImpl = await viem.deployContract('SimpleTreasuryImplementation', [], { account: deployer.account })
  console.log(`✅ SimpleTreasuryImplementation deployed at ${treasuryImpl.address}`)
  await verify('SimpleTreasuryImplementation', treasuryImpl.address)

  const kernelImpl = await viem.deployContract('KernelImplementation', [], { account: deployer.account })
  console.log(`✅ KernelImplementation deployed at ${kernelImpl.address}`)
  await verify('KernelImplementation', kernelImpl.address)

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
  console.log(`  TimelockControllerImplementation: ${timelockImpl.address}`)
  console.log(`  DAOGovernorImplementation      : ${governorImpl.address}`)
  console.log(`  MembershipNFTImplementation    : ${membershipImpl.address}`)
  console.log(`  SimpleTreasuryImplementation   : ${treasuryImpl.address}`)
  console.log(`  KernelImplementation           : ${kernelImpl.address}`)
  console.log(`  DAOFactoryUUPS       : ${factory.address}`)

  console.log('\nNext steps:')
  console.log('  • Use the factory to deploy a DAO instance when needed (e.g., via script or frontend).')
}

main().catch((error) => {
  console.error(error)
  process.exitCode = 1
})
