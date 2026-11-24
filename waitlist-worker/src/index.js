// Aurora waitlist signup endpoint (Cloudflare Worker).
// Accepts one email address from https://aurora.nmapaye.com, checks a
// Cloudflare Turnstile token, and stores the address in a D1 database that
// only the account owner can read (Cloudflare dashboard > D1 > aurora-waitlist).
// There is no endpoint that lists or returns signups.

const ALLOWED_ORIGIN = "https://aurora.nmapaye.com";
const ALLOWED_HOSTNAME = "aurora.nmapaye.com";
const EMAIL_RE = /^[^\s@]{1,64}@[^\s@.]+(\.[^\s@.]+)+$/;
const MAX_BODY_BYTES = 4096;

const corsHeaders = {
  "Access-Control-Allow-Origin": ALLOWED_ORIGIN,
  "Access-Control-Allow-Methods": "POST, OPTIONS",
  "Access-Control-Allow-Headers": "Content-Type",
  "Access-Control-Max-Age": "86400",
  Vary: "Origin",
};

function reply(status, body) {
  return new Response(JSON.stringify(body), {
    status,
    headers: {
      ...corsHeaders,
      "Content-Type": "application/json",
      "Cache-Control": "no-store",
      "X-Content-Type-Options": "nosniff",
    },
  });
}

async function verifyTurnstile(token, secret, ip) {
  const form = new FormData();
  form.append("secret", secret);
  form.append("response", token);
  if (ip) form.append("remoteip", ip);
  try {
    const res = await fetch("https://challenges.cloudflare.com/turnstile/v0/siteverify", {
      method: "POST",
      body: form,
    });
    const data = await res.json();
    return data.success === true && (!data.hostname || data.hostname === ALLOWED_HOSTNAME);
  } catch {
    return false;
  }
}

export default {
  async fetch(request, env) {
    if (request.method === "OPTIONS") {
      return new Response(null, { status: 204, headers: corsHeaders });
    }

    const url = new URL(request.url);
    if (request.method !== "POST" || url.pathname !== "/signup") {
      return reply(404, { ok: false, error: "not_found" });
    }
    if (request.headers.get("Origin") !== ALLOWED_ORIGIN) {
      return reply(403, { ok: false, error: "forbidden" });
    }
    const type = (request.headers.get("Content-Type") || "").split(";")[0].trim();
    if (type !== "application/json") {
      return reply(415, { ok: false, error: "unsupported_type" });
    }

    const raw = await request.text();
    if (raw.length > MAX_BODY_BYTES) {
      return reply(413, { ok: false, error: "too_large" });
    }
    let body;
    try {
      body = JSON.parse(raw);
    } catch {
      return reply(400, { ok: false, error: "bad_json" });
    }

    const email = String(body?.email ?? "").trim().toLowerCase();
    const token = String(body?.token ?? "");
    if (email.length > 254 || !EMAIL_RE.test(email)) {
      return reply(400, { ok: false, error: "invalid_email" });
    }
    if (!token || token.length > 2048) {
      return reply(400, { ok: false, error: "missing_check" });
    }
    if (!env.TURNSTILE_SECRET || !env.DB) {
      return reply(503, { ok: false, error: "not_configured" });
    }

    const human = await verifyTurnstile(token, env.TURNSTILE_SECRET, request.headers.get("CF-Connecting-IP"));
    if (!human) {
      return reply(403, { ok: false, error: "check_failed" });
    }

    await env.DB.prepare(
      "INSERT INTO signups (email, created_at) VALUES (?1, ?2) ON CONFLICT(email) DO NOTHING",
    )
      .bind(email, new Date().toISOString())
      .run();

    return reply(200, { ok: true });
  },
};
