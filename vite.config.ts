import { fileURLToPath, URL } from 'node:url'
import vue from '@vitejs/plugin-vue'
import inertia from '@inertiajs/vite'
import tailwindcss from '@tailwindcss/vite'
import { defineConfig } from 'vite'
import RubyPlugin from 'vite-plugin-ruby'

export default defineConfig({
  resolve: {
    alias: {
      '@': fileURLToPath(new URL('./app/frontend', import.meta.url)),
      '~': fileURLToPath(new URL('./app/frontend', import.meta.url)),
    },
  },
  plugins: [
    tailwindcss(),
    RubyPlugin(),
    inertia(),
    vue(),
  ],
})
