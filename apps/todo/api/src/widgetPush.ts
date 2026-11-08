import { Hono } from "hono";

// iOS ウィジェットへの WidgetKit push。
// ウィジェットは iOS が決める間隔（予算次第で 1 時間以上空く）でしか自分では読み直さないので、
// Mac や shelf でタスクを変えたときに「中身が変わった」を APNs で送って読み直させる。
// push も iOS の予算の内なので即時の保証は無い。届かなくても今までどおりの定期更新が残る。
type Bindings = {
  DB: D1Database;
  // APNs の認証キー（.p8 の中身そのまま）・キー ID・Team ID。どれかが無ければ送らない
  APNS_KEY?: string;
  APNS_KEY_ID?: string;
  APNS_TEAM_ID?: string;
  // 実機には Development 署名で入れている（todo:device・todo:ota とも）ので sandbox が既定
  APNS_HOST?: string;
};

// topic はアプリ本体の bundle ID + ".push-type.widgets"
const TOPIC = "com.d0ne1s.todoapp.push-type.widgets";
const tokenPattern = /^[0-9a-f]{32,400}$/;

const widgetPushTokens = new Hono<{ Bindings: Bindings }>();

// PUT /widget-push-tokens/:token（ウィジェットがトークンを受け取るたびに送ってくる。何度来てもよい）
widgetPushTokens.put("/:token", async (c) => {
  const token = c.req.param("token").toLowerCase();
  if (!tokenPattern.test(token)) return c.json({ error: "invalid token" }, 400);
  await c.env.DB
    .prepare(
      "INSERT INTO widget_push_tokens (token) VALUES (?) ON CONFLICT(token) DO UPDATE SET updated_at = datetime('now')"
    )
    .bind(token)
    .run();
  return c.json({ ok: true });
});

// DELETE /widget-push-tokens/:token（ウィジェットをホーム画面から外したとき）
widgetPushTokens.delete("/:token", async (c) => {
  const token = c.req.param("token").toLowerCase();
  await c.env.DB.prepare("DELETE FROM widget_push_tokens WHERE token = ?").bind(token).run();
  return c.json({ ok: true });
});

function base64url(input: ArrayBuffer | string): string {
  const bytes =
    typeof input === "string" ? new TextEncoder().encode(input) : new Uint8Array(input);
  let binary = "";
  for (const b of bytes) binary += String.fromCharCode(b);
  return btoa(binary).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}

let cachedJwt: { iat: number; keyId: string; jwt: string } | null = null;

// APNs の provider token（ES256 の JWT）。Apple は「20 分より頻繁に作り直さない・60 分以内に作り直す」を求める。
// isolate ごとに好きな時刻で作るとこれを破り得るので、iat を 30 分刻みにそろえる
async function providerToken(env: Required<Pick<Bindings, "APNS_KEY" | "APNS_KEY_ID" | "APNS_TEAM_ID">>) {
  const iat = Math.floor(Date.now() / 1000 / 1800) * 1800;
  if (cachedJwt && cachedJwt.iat === iat && cachedJwt.keyId === env.APNS_KEY_ID) {
    return cachedJwt.jwt;
  }
  const pem = env.APNS_KEY.replace(/-----[^-]+-----/g, "").replace(/\s+/g, "");
  const der = Uint8Array.from(atob(pem), (ch) => ch.charCodeAt(0));
  const key = await crypto.subtle.importKey(
    "pkcs8",
    der,
    { name: "ECDSA", namedCurve: "P-256" },
    false,
    ["sign"]
  );
  const signingInput = `${base64url(JSON.stringify({ alg: "ES256", kid: env.APNS_KEY_ID }))}.${base64url(
    JSON.stringify({ iss: env.APNS_TEAM_ID, iat })
  )}`;
  // WebCrypto の ECDSA 署名は r||s の生の形で、JWT の ES256 がそのまま求める形
  const signature = await crypto.subtle.sign(
    { name: "ECDSA", hash: "SHA-256" },
    key,
    new TextEncoder().encode(signingInput)
  );
  const jwt = `${signingInput}.${base64url(signature)}`;
  cachedJwt = { iat, keyId: env.APNS_KEY_ID, jwt };
  return jwt;
}

// 登録済みの全トークンへ「中身が変わった」を送る。失敗してもタスクの書き込みには影響させない
async function notifyWidgets(env: Bindings): Promise<void> {
  const { APNS_KEY, APNS_KEY_ID, APNS_TEAM_ID } = env;
  if (!APNS_KEY || !APNS_KEY_ID || !APNS_TEAM_ID) return;

  const { results } = await env.DB
    .prepare("SELECT token FROM widget_push_tokens")
    .all<{ token: string }>();
  if (results.length === 0) return;

  const jwt = await providerToken({ APNS_KEY, APNS_KEY_ID, APNS_TEAM_ID });
  const host = env.APNS_HOST || "api.sandbox.push.apple.com";

  await Promise.all(
    results.map(async ({ token }) => {
      const res = await fetch(`https://${host}/3/device/${token}`, {
        method: "POST",
        headers: {
          authorization: `bearer ${jwt}`,
          "apns-topic": TOPIC,
          "apns-push-type": "widgets",
        },
        body: JSON.stringify({ aps: { "content-changed": true } }),
      });
      if (res.ok) {
        console.log(JSON.stringify({ widgetPush: "sent", token: token.slice(0, 8) }));
        return;
      }
      const body = await res.text();
      const reason = (() => {
        try {
          return (JSON.parse(body) as { reason?: string }).reason ?? body;
        } catch {
          return body;
        }
      })();
      console.log(
        JSON.stringify({ widgetPush: "failed", token: token.slice(0, 8), status: res.status, reason })
      );
      // もう届かないトークンは消す（ウィジェットが次にトークンを受け取ったときに登録し直される）
      if (res.status === 410 || reason === "BadDeviceToken") {
        await env.DB.prepare("DELETE FROM widget_push_tokens WHERE token = ?").bind(token).run();
      }
    })
  );
}

export { widgetPushTokens, notifyWidgets };
