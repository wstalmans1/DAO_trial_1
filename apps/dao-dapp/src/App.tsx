import { ConnectButton } from '@rainbow-me/rainbowkit'

export default function App() {
  return (
    <div className="min-h-screen bg-gray-900 text-white">
      <div className="container mx-auto px-6 py-8">
        <header className="flex items-center justify-between mb-8">
          <h1 className="text-3xl font-bold text-white">DAO dApp</h1>
          <div className="relative">
            <ConnectButton 
              chainStatus="full"
              showBalance={true}
              accountStatus={{
                smallScreen: 'avatar',
                largeScreen: 'full',
              }}
            />
          </div>
        </header>
        
        <main className="space-y-8">
          <div className="bg-gray-800 rounded-lg p-6 shadow-lg">
            <h2 className="text-xl font-semibold mb-4 text-white">Welcome to the DAO</h2>
            <p className="text-gray-300">
              Connect your wallet to start participating in decentralized governance.
            </p>
          </div>
          
          <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-6">
            <div className="bg-gray-800 rounded-lg p-6 shadow-lg hover:bg-gray-700 transition-colors">
              <h3 className="text-lg font-semibold mb-2 text-white">Proposals</h3>
              <p className="text-gray-300 text-sm">View and vote on governance proposals</p>
            </div>
            
            <div className="bg-gray-800 rounded-lg p-6 shadow-lg hover:bg-gray-700 transition-colors">
              <h3 className="text-lg font-semibold mb-2 text-white">Treasury</h3>
              <p className="text-gray-300 text-sm">Manage DAO treasury and funds</p>
            </div>
            
            <div className="bg-gray-800 rounded-lg p-6 shadow-lg hover:bg-gray-700 transition-colors">
              <h3 className="text-lg font-semibold mb-2 text-white">Members</h3>
              <p className="text-gray-300 text-sm">View DAO membership and roles</p>
            </div>
          </div>
        </main>
      </div>
    </div>
  )
}
