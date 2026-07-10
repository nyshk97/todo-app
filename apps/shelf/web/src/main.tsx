import { StrictMode } from "react";
import { createRoot } from "react-dom/client";
import { QueryClient, focusManager } from "@tanstack/react-query";
import { PersistQueryClientProvider } from "@tanstack/react-query-persist-client";
import { createSyncStoragePersister } from "@tanstack/query-sync-storage-persister";
import "./index.css";
import App from "./App";

// キャッシュ戦略: 前回のデータを localStorage から即描画し、裏で再取得して差し替える
const CACHE_MAX_AGE = 7 * 24 * 60 * 60 * 1000;

const queryClient = new QueryClient({
  defaultOptions: {
    queries: {
      staleTime: 30_000,
      gcTime: CACHE_MAX_AGE,
      // タブが visible な間は定期再取得（hidden 中はデフォルトで停止）
      refetchInterval: 60_000,
    },
  },
});

// v5 の focusManager は visibilitychange しか監視せず、ウィンドウが見えたまま
// 別アプリから戻るケースを拾えないため、focus イベントも追加で監視する。
// handleFocus は引数なしで呼ぶ（boolean を渡すと値が変化した時しか発火しない）
focusManager.setEventListener((handleFocus) => {
  const onFocus = () => handleFocus();
  window.addEventListener("visibilitychange", onFocus, false);
  window.addEventListener("focus", onFocus, false);
  return () => {
    window.removeEventListener("visibilitychange", onFocus);
    window.removeEventListener("focus", onFocus);
  };
});

const persister = createSyncStoragePersister({
  storage: window.localStorage,
  key: "todo-shelf-query-cache",
});

createRoot(document.getElementById("root")!).render(
  <StrictMode>
    <PersistQueryClientProvider
      client={queryClient}
      persistOptions={{ persister, maxAge: CACHE_MAX_AGE }}
    >
      <App />
    </PersistQueryClientProvider>
  </StrictMode>
);
