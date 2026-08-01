import { defineConfig, loadEnv } from 'vite'
import react from '@vitejs/plugin-react'

// bundle へ焼き込まれる環境変数。欠けると localhost 向けの本番サイトを publish してしまう
const REQUIRED_PROD_ENV = ['VITE_API_URL', 'VITE_API_SECRET', 'VITE_TODO_APP_API_URL']

// https://vite.dev/config/
export default defineConfig(({ command, mode }) => {
  // 本番ビルドの成果物はそのまま Cloudflare Pages へ deploy される（Git 連携なしの手動デプロイ）。
  // Pages ダッシュボードの環境変数は手元の vite build には注入されないため、
  // .env.production を移し忘れたまま「成功する」ビルドを作らせない。
  if (command === 'build' && mode === 'production') {
    const env = loadEnv(mode, process.cwd(), 'VITE_')
    const invalid = REQUIRED_PROD_ENV.filter((key) => {
      const value = env[key]
      return !value || value.includes('localhost') || value.includes('127.0.0.1')
    })
    if (invalid.length > 0) {
      throw new Error(
        `本番ビルドに必要な環境変数が未設定、または localhost を指しています: ${invalid.join(', ')}\n` +
          `apps/shelf/web/.env.production を用意してください（.env.example をコピーして値を埋める）。`,
      )
    }
  }

  return { plugins: [react()] }
})
