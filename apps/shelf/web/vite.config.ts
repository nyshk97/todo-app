import { defineConfig, loadEnv } from 'vite'
import react from '@vitejs/plugin-react'

// bundle へ焼き込まれる環境変数。欠けると壊れた本番サイトを publish してしまう
const REQUIRED_PROD_ENV = ['VITE_API_URL', 'VITE_API_SECRET', 'VITE_TODO_APP_API_URL']

// 未編集を示す値。localhost だけでなく .env.example の placeholder も弾く
// （雛形をコピーしただけの状態で「成功する」本番ビルドを作らせないため）
const INVALID_VALUE_PATTERNS = [
  'localhost',
  '127.0.0.1',
  'example.com',
  'example.workers.dev',
  'REPLACE_ME',
]

// https://vite.dev/config/
export default defineConfig(({ command, mode }) => {
  // 本番ビルドの成果物はそのまま Cloudflare Pages へ deploy される（Git 連携なしの手動デプロイ）。
  // Pages ダッシュボードの環境変数は手元の vite build には注入されないため、
  // .env.production を移し忘れたまま「成功する」ビルドを作らせない。
  if (command === 'build' && mode === 'production') {
    const env = loadEnv(mode, process.cwd(), 'VITE_')
    const invalid = REQUIRED_PROD_ENV.filter((key) => {
      const value = env[key]
      return !value || INVALID_VALUE_PATTERNS.some((pattern) => value.includes(pattern))
    })
    if (invalid.length > 0) {
      throw new Error(
        `本番ビルドに使えない環境変数があります（未設定 / localhost / 雛形のまま）: ${invalid.join(', ')}\n` +
          `apps/shelf/web/.env.production を用意し、VITE_API_SECRET を実際の値に置き換えてください。`,
      )
    }
  }

  return { plugins: [react()] }
})
