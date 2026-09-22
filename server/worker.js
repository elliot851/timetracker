// TimeTracker API — a single Cloudflare Worker.
//
// Bindings (wrangler.toml):
//   DB           → D1 database (run schema.sql once)
//   SHOTS        → R2 bucket (screenshots)
//   ADMIN_EMAILS → comma-separated list; these accounts are always admins, everyone else a member
//   BREVO_API_KEY (secret), MAIL_FROM_EMAIL, MAIL_FROM_NAME → transactional email
//
// Auth: email + password. Passwords hashed with PBKDF2-SHA256. A login returns a
// bearer token stored in `sessions`; clients send it as `Authorization: Bearer <token>`.
//
// Roles: the desktop app is for everyone (tracking). The website is monitoring-only
// and meant for admins; members can log in but only see their own data.

const CORS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Methods": "GET,POST,DELETE,OPTIONS",
  "Access-Control-Allow-Headers": "Content-Type, Authorization",
};

const json = (data, status = 200) =>
  new Response(JSON.stringify(data), {
    status,
    headers: { "Content-Type": "application/json", ...CORS },
  });

const err = (message, status = 400) => json({ error: message }, status);

// ---- password hashing (Web Crypto, available in Workers) ----

const enc = new TextEncoder();
const b64 = (buf) => btoa(String.fromCharCode(...new Uint8Array(buf)));
const fromB64 = (s) => Uint8Array.from(atob(s), (c) => c.charCodeAt(0));

async function hashPassword(password, saltBytes, iterations = 100000) {
  const salt = saltBytes || crypto.getRandomValues(new Uint8Array(16));
  const key = await crypto.subtle.importKey(
    "raw", enc.encode(password), "PBKDF2", false, ["deriveBits"]);
  const bits = await crypto.subtle.deriveBits(
    { name: "PBKDF2", salt, iterations, hash: "SHA-256" }, key, 256);
  return `pbkdf2$${iterations}$${b64(salt)}$${b64(bits)}`;
}

async function verifyPassword(password, stored) {
  const [, iterStr, saltB64, hashB64] = stored.split("$");
  const candidate = await hashPassword(password, fromB64(saltB64), Number(iterStr));
  // constant-time-ish compare
  const a = candidate.split("$")[3], b = hashB64;
  if (a.length !== b.length) return false;
  let diff = 0;
  for (let i = 0; i < a.length; i++) diff |= a.charCodeAt(i) ^ b.charCodeAt(i);
  return diff === 0;
}

const uuid = () => crypto.randomUUID();
const token = () => b64(crypto.getRandomValues(new Uint8Array(32)))
  .replace(/[^a-zA-Z0-9]/g, "").slice(0, 40);

// ---- roles ----

const adminEmails = (env) =>
  (env.ADMIN_EMAILS || "").split(",").map((e) => e.trim().toLowerCase()).filter(Boolean);

const roleFor = (env, email) => adminEmails(env).includes(email.toLowerCase()) ? "admin" : "user";

/// Keeps the stored role in line with ADMIN_EMAILS so editing the list is enough.
async function syncRole(env, row) {
  if (!adminEmails(env).length) return row;   // not configured → keep stored roles
  const role = roleFor(env, row.email);
  if (row.role !== role) {
    await env.DB.prepare("UPDATE users SET role = ? WHERE id = ?").bind(role, row.id).run();
    row.role = role;
  }
  return row;
}

// ---- auth helpers ----

async function currentUser(request, env) {
  const auth = request.headers.get("Authorization") || "";
  const t = auth.replace(/^Bearer\s+/i, "");
  if (!t) return null;
  const row = await env.DB.prepare(
    `SELECT u.id, u.email, u.name, u.role FROM sessions s
     JOIN users u ON u.id = s.user_id
     WHERE s.token = ? AND s.expires_at > ?`)
    .bind(t, new Date().toISOString()).first();
  return row ? syncRole(env, row) : null;
}

// ---- routes ----

export default {
  async fetch(request, env) {
    if (request.method === "OPTIONS") return new Response(null, { headers: CORS });
    const url = new URL(request.url);
    const path = url.pathname;

    try {
      if (path === "/api/register" && request.method === "POST") return register(request, env);
      if (path === "/api/login" && request.method === "POST") return login(request, env);
      if (path === "/api/verify" && request.method === "POST") return verifyCode(request, env);
      if (path === "/api/resend-code" && request.method === "POST") return resendCode(request, env);
      if (path === "/api/request-reset" && request.method === "POST") return requestReset(request, env);
      if (path === "/api/reset" && request.method === "POST") return resetPassword(request, env);

      const user = await currentUser(request, env);
      if (!user) return err("Not signed in", 401);

      if (path === "/api/me") return json({ user });
      if (path === "/api/logout" && request.method === "POST") return logout(request, env);
      if (path === "/api/shifts" && request.method === "POST") return saveShifts(request, env, user);
      if (path === "/api/minutes" && request.method === "POST") return saveMinutes(request, env, user);
      if (path === "/api/warnings" && request.method === "POST") return saveWarning(request, env, user);
      if (path === "/api/upload" && request.method === "POST") return upload(request, env, user);

      // Reads. A member may read only their own; an admin may pass ?user=<id> (or user=all).
      if (path === "/api/users") return listUsers(env, user);
      if (path === "/api/minutes") return readMinutes(url, env, user);
      if (path === "/api/shifts") return readShifts(url, env, user);
      if (path === "/api/warnings") return readWarnings(url, env, user);
      if (path === "/api/range") return readRange(url, env, user);
      if (path === "/api/shot") return readShot(url, env, user);

      return err("Not found", 404);
    } catch (e) {
      return err(String(e && e.message || e), 500);
    }
  },
};

async function register(request, env) {
  const { email, password, name } = await request.json();
  if (!email || !password) return err("Email and password are required");
  if (password.length < 8) return err("Password must be at least 8 characters");
  const lower = email.toLowerCase();
  const exists = await env.DB.prepare("SELECT id FROM users WHERE email = ?").bind(lower).first();
  if (exists) return err("That email is already registered", 409);

  const id = uuid();
  const displayName = name || email.split("@")[0];
  const hash = await hashPassword(password);
  const code = code6();
  await env.DB.prepare(
    "INSERT INTO users (id,email,name,password,role,created_at,verified,verify_code,code_expires) " +
    "VALUES (?,?,?,?,?,?,0,?,?)")
    .bind(id, lower, displayName, hash, roleFor(env, lower),
          new Date().toISOString(), code, codeExpiry()).run();

  await sendEmail(env, lower, "Your TimeTracker verification code",
    `Welcome to TimeTracker!\n\nYour verification code is: ${code}\n\nIt expires in 15 minutes.`,
    codeEmailHTML("Verify your email",
      "Welcome to TimeTracker! Enter the code below to activate your account.", code));
  return json({ pending: true, email: lower });
}

async function login(request, env) {
  const { email, password } = await request.json();
  const row = await env.DB.prepare("SELECT * FROM users WHERE email = ?")
    .bind((email || "").toLowerCase()).first();
  if (!row || !(await verifyPassword(password || "", row.password)))
    return err("Wrong email or password", 401);
  if (!row.verified)
    return json({ error: "Email not verified yet", needsVerification: true }, 403);
  return issueSession(env, await syncRole(env, row));
}

// ---- email verification & password reset ----

const code6 = () => String(Math.floor(100000 + Math.random() * 900000));
const codeExpiry = () => new Date(Date.now() + 15 * 60000).toISOString(); // 15 min

/// Sends via Brevo when BREVO_API_KEY is set; otherwise logs so the flow is
/// testable before email delivery is wired up. Uses a single verified sender
/// (MAIL_FROM_EMAIL) so no domain DNS is required.
async function sendEmail(env, to, subject, text, html) {
  if (!env.BREVO_API_KEY) {
    console.log(`[EMAIL to ${to}] ${subject}\n${text}`);
    return;
  }
  const body = {
    sender: { email: env.MAIL_FROM_EMAIL, name: env.MAIL_FROM_NAME || "TimeTracker" },
    to: [{ email: to }],
    subject,
    textContent: text,
  };
  if (html) body.htmlContent = html;
  const res = await fetch("https://api.brevo.com/v3/smtp/email", {
    method: "POST",
    headers: { "api-key": env.BREVO_API_KEY, "Content-Type": "application/json", "accept": "application/json" },
    body: JSON.stringify(body),
  });
  if (!res.ok) console.log(`[EMAIL FAIL ${res.status}] ${await res.text()}`);
}

/// A clean, light, branded HTML email with the code as big bold digits in boxes.
function codeEmailHTML(heading, message, code) {
  const boxes = code.split("").map((d) =>
    `<td style="padding:0 5px;">
       <div style="width:46px;height:58px;line-height:58px;background:#eef1f7;border:1px solid #d8deea;
         border-radius:10px;color:#0b0f1b;font-size:30px;font-weight:800;text-align:center;
         font-family:'SF Mono',Menlo,Consolas,monospace;">${d}</div>
     </td>`).join("");
  return `<!doctype html><html><body style="margin:0;background:#f4f6fb;padding:40px 0;
    font-family:-apple-system,Segoe UI,Roboto,Helvetica,Arial,sans-serif;">
    <table role="presentation" width="100%" cellpadding="0" cellspacing="0"><tr><td align="center">
      <table role="presentation" width="440" cellpadding="0" cellspacing="0"
        style="background:#ffffff;border:1px solid #e6e9f0;border-radius:18px;overflow:hidden;">
        <tr><td style="padding:36px 40px 8px;" align="center">
          <img src="https://timetracker-a2o.pages.dev/logo.png" width="60" height="60" alt="TimeTracker"
            style="border-radius:15px;display:block;" />
          <div style="color:#8a94ad;font-size:13px;font-weight:600;margin-top:10px;
            letter-spacing:.5px;">TIMETRACKER</div>
        </td></tr>
        <tr><td style="padding:20px 40px 6px;" align="center">
          <div style="color:#0b0f1b;font-size:22px;font-weight:700;">${heading}</div>
        </td></tr>
        <tr><td style="padding:6px 40px 24px;" align="center">
          <div style="color:#616a80;font-size:14px;line-height:1.5;">${message}</div>
        </td></tr>
        <tr><td style="padding:0 30px 14px;" align="center">
          <table role="presentation" cellpadding="0" cellspacing="0"><tr>${boxes}</tr></table>
        </td></tr>
        <tr><td style="padding:0 40px 24px;" align="center">
          <div style="color:#616a80;font-size:13px;">Or copy the code:
            <span style="font-family:'SF Mono',Menlo,Consolas,monospace;font-weight:700;
              color:#0b0f1b;letter-spacing:2px;">${code}</span></div>
        </td></tr>
        <tr><td style="padding:0 40px 34px;" align="center">
          <div style="color:#9aa2b4;font-size:12px;line-height:1.5;">
            This code expires in 15 minutes. If this wasn't you, you can safely ignore this email.</div>
        </td></tr>
      </table>
    </td></tr></table></body></html>`;
}

async function verifyCode(request, env) {
  const { email, code } = await request.json();
  const row = await env.DB.prepare("SELECT * FROM users WHERE email = ?")
    .bind((email || "").toLowerCase()).first();
  if (!row) return err("Unknown account", 404);
  if (row.verified) return issueSession(env, await syncRole(env, row));
  if (!row.verify_code || row.verify_code !== String(code))
    return err("Wrong code", 400);
  if (!row.code_expires || row.code_expires < new Date().toISOString())
    return err("That code has expired", 400);
  await env.DB.prepare(
    "UPDATE users SET verified = 1, verify_code = NULL, code_expires = NULL WHERE id = ?")
    .bind(row.id).run();
  return issueSession(env, await syncRole(env, row));
}

async function resendCode(request, env) {
  const { email } = await request.json();
  const row = await env.DB.prepare("SELECT * FROM users WHERE email = ?")
    .bind((email || "").toLowerCase()).first();
  if (!row) return err("Unknown account", 404);
  const code = code6();
  await env.DB.prepare("UPDATE users SET verify_code = ?, code_expires = ? WHERE id = ?")
    .bind(code, codeExpiry(), row.id).run();
  await sendEmail(env, row.email, "Your TimeTracker verification code",
    `Your new verification code is: ${code}\n\nIt expires in 15 minutes.`,
    codeEmailHTML("Your new code", "Here is your new TimeTracker verification code.", code));
  return json({ ok: true });
}

async function requestReset(request, env) {
  const { email } = await request.json();
  const row = await env.DB.prepare("SELECT * FROM users WHERE email = ?")
    .bind((email || "").toLowerCase()).first();
  // Always report ok so we don't reveal which emails exist.
  if (row) {
    const code = code6();
    await env.DB.prepare("UPDATE users SET verify_code = ?, code_expires = ? WHERE id = ?")
      .bind(code, codeExpiry(), row.id).run();
    await sendEmail(env, row.email, "Reset your TimeTracker password",
      `Your reset code is: ${code}\n\nIt expires in 15 minutes. Ignore this if it wasn't you.`,
      codeEmailHTML("Reset your password",
        "Enter the code below to choose a new password.", code));
  }
  return json({ ok: true });
}

async function resetPassword(request, env) {
  const { email, code, password } = await request.json();
  if (!password || password.length < 8) return err("Password must be at least 8 characters");
  const row = await env.DB.prepare("SELECT * FROM users WHERE email = ?")
    .bind((email || "").toLowerCase()).first();
  if (!row || !row.verify_code || row.verify_code !== String(code))
    return err("Wrong code", 400);
  if (!row.code_expires || row.code_expires < new Date().toISOString())
    return err("That code has expired", 400);
  const hash = await hashPassword(password);
  await env.DB.prepare(
    "UPDATE users SET password = ?, verified = 1, verify_code = NULL, code_expires = NULL WHERE id = ?")
    .bind(hash, row.id).run();
  return issueSession(env, await syncRole(env, row));
}

async function issueSession(env, user) {
  const t = token();
  const expires = new Date(Date.now() + 90 * 864e5).toISOString(); // 90 days
  await env.DB.prepare("INSERT INTO sessions (token,user_id,expires_at) VALUES (?,?,?)")
    .bind(t, user.id, expires).run();
  return json({
    token: t,
    user: { id: user.id, email: user.email, name: user.name, role: user.role },
  });
}

async function logout(request, env) {
  const t = (request.headers.get("Authorization") || "").replace(/^Bearer\s+/i, "");
  await env.DB.prepare("DELETE FROM sessions WHERE token = ?").bind(t).run();
  return json({ ok: true });
}

// ---- writes (from the desktop app) ----

/// Screenshot objects live under "<userId>/<day>/<file>.jpg" in R2. The app sends the
/// key without the user prefix; store the full object key so reads are unambiguous.
const withOwner = (userId, key) =>
  !key ? key : key.startsWith(userId + "/") ? key : `${userId}/${key}`;

async function saveShifts(request, env, user) {
  const shifts = await request.json(); // [{id,start,end}]
  const stmt = env.DB.prepare(
    "INSERT INTO shifts (id,user_id,start_at,end_at) VALUES (?,?,?,?) " +
    "ON CONFLICT(id) DO UPDATE SET end_at = excluded.end_at");
  await env.DB.batch(shifts.map((s) => stmt.bind(s.id, user.id, s.start, s.end || null)));
  return json({ ok: true, count: shifts.length });
}

async function saveMinutes(request, env, user) {
  const rows = await request.json(); // [{ts,keyboard,mouse,overall,apps,screenshots}]
  const stmt = env.DB.prepare(
    "INSERT OR REPLACE INTO minutes (id,user_id,ts,keyboard,mouse,overall,apps,screenshots) " +
    "VALUES (?,?,?,?,?,?,?,?)");
  await env.DB.batch(rows.map((m) => stmt.bind(
    `${user.id}:${m.ts}`, user.id, m.ts, m.keyboard, m.mouse, m.overall,
    JSON.stringify(m.apps || []),
    JSON.stringify((m.screenshots || []).map((k) => withOwner(user.id, k))))));
  return json({ ok: true, count: rows.length });
}

async function saveWarning(request, env, user) {
  const w = await request.json();
  await env.DB.prepare(
    "INSERT OR REPLACE INTO warnings " +
    "(id,user_id,user_name,started_at,resolved_at,outcome,screenshot,activity,app) " +
    "VALUES (?,?,?,?,?,?,?,?,?)")
    .bind(w.id, user.id, user.name, w.startedAt, w.resolvedAt || null,
          w.outcome || null, withOwner(user.id, w.screenshot) || null, w.activity || 0, w.app || null).run();
  return json({ ok: true });
}

async function upload(request, env, user) {
  // Body is the raw JPEG; key comes from ?key=2026-09-15/2026-09-15_14-02-11.jpg
  const key = new URL(request.url).searchParams.get("key");
  if (!key) return err("Missing key");
  const objectKey = withOwner(user.id, key);
  await env.SHOTS.put(objectKey, request.body, {
    httpMetadata: { contentType: "image/jpeg" },
  });
  return json({ ok: true, key: objectKey });
}

// ---- reads (own data, or any data for admins) ----

function scopeUserId(url, user) {
  const requested = url.searchParams.get("user");
  if (!requested || requested === user.id) return user.id;
  return user.role === "admin" ? requested : null; // members can't peek
}

async function listUsers(env, user) {
  if (user.role !== "admin") return json({ users: [user] });
  const { results } = await env.DB.prepare(
    `SELECT u.id, u.email, u.name, u.role, u.created_at, u.verified,
            (SELECT MAX(ts) FROM minutes m WHERE m.user_id = u.id) AS last_seen,
            (SELECT COUNT(*) FROM shifts s WHERE s.user_id = u.id AND s.end_at IS NULL) AS open_shifts
     FROM users u ORDER BY u.role, u.name`).all();
  return json({ users: results });
}

async function readMinutes(url, env, user) {
  const id = scopeUserId(url, user);
  if (!id) return err("Not allowed", 403);
  const day = url.searchParams.get("date"); // yyyy-MM-dd
  const { results } = await env.DB.prepare(
    "SELECT * FROM minutes WHERE user_id = ? AND ts LIKE ? ORDER BY ts")
    .bind(id, `${day}%`).all();
  return json({ minutes: results });
}

async function readShifts(url, env, user) {
  const id = scopeUserId(url, user);
  if (!id) return err("Not allowed", 403);
  const { results } = await env.DB.prepare(
    "SELECT * FROM shifts WHERE user_id = ? ORDER BY start_at DESC").bind(id).all();
  return json({ shifts: results });
}

async function readWarnings(url, env, user) {
  if (user.role === "admin" && !url.searchParams.get("user")) {
    const { results } = await env.DB.prepare(
      "SELECT * FROM warnings ORDER BY started_at DESC").all();
    return json({ warnings: results });
  }
  const id = scopeUserId(url, user);
  if (!id) return err("Not allowed", 403);
  const { results } = await env.DB.prepare(
    "SELECT * FROM warnings WHERE user_id = ? ORDER BY started_at DESC").bind(id).all();
  return json({ warnings: results });
}

/// Everything needed for analytics over a date range, in one call:
/// minutes (without screenshot keys), shifts and warnings. Admins may pass user=all.
async function readRange(url, env, user) {
  const from = url.searchParams.get("from"), to = url.searchParams.get("to"); // yyyy-MM-dd inclusive
  if (!from || !to) return err("from and to are required");
  const requested = url.searchParams.get("user");
  const all = requested === "all" && user.role === "admin";
  const id = all ? null : scopeUserId(url, user);
  if (!all && !id) return err("Not allowed", 403);

  const scope = all ? "" : "AND user_id = ?";
  const bind = (...a) => all ? a : [...a, id];
  const lo = `${from}T00:00:00`, hi = `${to}T23:59:59.999`;

  const [minutes, shifts, warnings] = await Promise.all([
    env.DB.prepare(`SELECT user_id, ts, keyboard, mouse, overall, apps FROM minutes
                    WHERE ts >= ? AND ts <= ? ${scope} ORDER BY ts`).bind(...bind(lo, hi)).all(),
    env.DB.prepare(`SELECT * FROM shifts WHERE start_at <= ? AND (end_at IS NULL OR end_at >= ?) ${scope}
                    ORDER BY start_at`).bind(...bind(hi, lo)).all(),
    env.DB.prepare(`SELECT * FROM warnings WHERE started_at >= ? AND started_at <= ? ${scope}
                    ORDER BY started_at DESC`).bind(...bind(lo, hi)).all(),
  ]);
  return json({ minutes: minutes.results, shifts: shifts.results, warnings: warnings.results });
}

async function readShot(url, env, user) {
  let key = url.searchParams.get("key");
  if (!key) return err("Missing key");
  // Keys are prefixed with the owner's id. Older rows stored "day/file" only — for those,
  // the owner is the scoped user (?user=<id> for admins, else the caller).
  const looksOwned = /^[0-9a-f-]{32,36}\//i.test(key);
  if (!looksOwned) {
    const owner = scopeUserId(url, user);
    if (!owner) return err("Not allowed", 403);
    key = `${owner}/${key}`;
  }
  const owner = key.split("/")[0];
  if (owner !== user.id && user.role !== "admin") return err("Not allowed", 403);
  const object = await env.SHOTS.get(key);
  if (!object) return err("Not found", 404);
  return new Response(object.body, {
    headers: { "Content-Type": "image/jpeg", "Cache-Control": "private, max-age=3600", ...CORS },
  });
}
