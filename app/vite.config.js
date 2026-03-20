import { defineConfig } from 'vite'
import react from '@vitejs/plugin-react'

export default defineConfig({
  plugins: [react()],
  build: {
    outDir: 'dist',
    sourcemap: false, // disable in prod for security
  },
  // Expose only VITE_ prefixed env vars to client
  envPrefix: 'VITE_',
})
