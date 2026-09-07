import { defineConfig } from 'vite';
import react from '@vitejs/plugin-react';
import tailwindcss from '@tailwindcss/vite';

export default defineConfig({
  plugins: [react(), tailwindcss()],
  server: {
    proxy: {
      // In dev the BFF runs on 8080; in the cluster nginx does this instead.
      '/graphql': { target: 'http://localhost:8080', changeOrigin: true },
    },
  },
});
