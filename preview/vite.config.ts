import { defineConfig } from 'vite';
import react from '@vitejs/plugin-react';

const MERIDIAN_API_TARGET = process.env.MERIDIAN_API_TARGET || 'http://localhost:8080';

export default defineConfig({
  plugins: [react()],
  resolve: { dedupe: ['react', 'react-dom'] },
  base: './',
  server: {
    port: 5176,
    proxy: {
      '/api/v1': {
        target: MERIDIAN_API_TARGET,
        changeOrigin: true,
      },
    },
  },
  build: { outDir: 'dist', sourcemap: false, assetsInlineLimit: 0 },
});
