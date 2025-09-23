import React from 'react'
import ReactDOM from 'react-dom/client'
import { WagmiProvider } from 'wagmi'
import { QueryClient, QueryClientProvider } from '@tanstack/react-query'
import { RainbowKitProvider, darkTheme } from '@rainbow-me/rainbowkit'
import '@rainbow-me/rainbowkit/styles.css'
import './rainbowkit-overrides.css'

import { config } from './config/wagmi'
import App from './App'
import './index.css'

const qc = new QueryClient()

// Custom dark theme configuration with more distinct styling
const customDarkTheme = darkTheme({
  accentColor: '#3b82f6', // blue-500 - matches our theme
  accentColorForeground: '#ffffff',
  borderRadius: 'large', // More rounded for distinctiveness
  fontStack: 'system', // Use system fonts for consistency
  overlayBlur: 'large', // More blur for better separation
})

// Alternative theme options you can try:
// const customDarkTheme = darkTheme({
//   accentColor: '#10b981', // emerald-500 - green accent
//   accentColorForeground: '#ffffff',
//   borderRadius: 'large', // More rounded
//   fontStack: 'system',
//   overlayBlur: 'large', // More blur
// })

// const customDarkTheme = darkTheme({
//   accentColor: '#8b5cf6', // violet-500 - purple accent
//   accentColorForeground: '#ffffff',
//   borderRadius: 'small', // Less rounded
//   fontStack: 'system',
//   overlayBlur: 'small',
// })

ReactDOM.createRoot(document.getElementById('root')!).render(
  <React.StrictMode>
    <WagmiProvider config={config}>
      <QueryClientProvider client={qc}>
        <RainbowKitProvider theme={customDarkTheme}>
          <App />
        </RainbowKitProvider>
      </QueryClientProvider>
    </WagmiProvider>
  </React.StrictMode>
)
