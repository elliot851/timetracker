const $ = (id) => document.getElementById(id);
let mode = "login", pendingEmail = "";
const boxes = [...document.querySelectorAll("#otp input")];
const code = () => boxes.map(b => b.value).join("");
boxes.forEach((b, i) => {
  b.addEventListener("input", () => {
    const d = b.value.replace(/\D/g, "");
    if (d.length > 1) { d.split("").forEach((c, k) => boxes[i + k] && (boxes[i + k].value = c)); boxes[Math.min(i + d.length, 5)].focus(); }
    else { b.value = d; if (d && boxes[i + 1]) boxes[i + 1].focus(); }
    if (code().length === 6) submit();
  });
  b.addEventListener("keydown", e => { if (e.key === "Backspace" && !b.value && boxes[i - 1]) { boxes[i - 1].value = ""; boxes[i - 1].focus(); } });
});

function applyMode() {
  const c = { login: ["Log in", "Sign in with the account you created on the website.", "Log in"],
    register: ["Create your account", "We'll email you a 6-digit code to confirm it.", "Create account"],
    verify: ["Check your email", `We sent a 6-digit code to ${pendingEmail}.`, "Verify"] }[mode];
  $("aTitle").textContent = c[0]; $("aSub").textContent = c[1]; $("aBtn").textContent = c[2];
  $("email").style.display = mode === "verify" ? "none" : ""; $("pwWrap").style.display = mode === "verify" ? "none" : "";
  $("otp").style.display = mode === "verify" ? "flex" : "none"; $("resend").style.display = mode === "verify" ? "" : "none";
  $("toggle").textContent = mode === "login" ? "Don't have an account? Create one" : "Already have an account? Log in";
  $("aErr").textContent = "";
}
$("toggle").onclick = () => { mode = mode === "login" ? "register" : "login"; applyMode(); };
$("forgot").onclick = () => tt.openWebsite();
$("eye").onclick = () => { const p = $("password"); p.type = p.type === "password" ? "text" : "password"; };
$("resend").onclick = async () => { try { await tt.resend(pendingEmail); $("aErr").style.color = "var(--success)"; $("aErr").textContent = "New code sent."; } catch (e) { $("aErr").textContent = e.message; } };
$("aBtn").onclick = submit;
["email", "password"].forEach(id => $(id).addEventListener("keydown", e => { if (e.key === "Enter") submit(); }));

async function submit() {
  const email = $("email").value.trim(), password = $("password").value;
  $("aErr").style.color = "var(--danger)"; $("aErr").textContent = ""; $("aBtn").disabled = true;
  try {
    if (mode === "login") { if (!email.includes("@") || !password) throw new Error("Enter your email and password."); render(await tt.login(email, password)); }
    else if (mode === "register") {
      if (password.length < 8 || !/[a-zA-Z]/.test(password) || !/[0-9]/.test(password)) throw new Error("Password: at least 8 characters with letters and numbers.");
      const r = await tt.register(email, password);
      if (r.pending) { pendingEmail = email; mode = "verify"; applyMode(); boxes[0].focus(); }
    } else if (mode === "verify") { if (code().length < 6) throw new Error("Enter the 6-digit code."); render(await tt.verify(pendingEmail, code())); }
  } catch (e) { $("aErr").textContent = (e.message || "").replace(/^Error invoking remote method '\w+': Error: /, ""); boxes.forEach(b => b.value = ""); }
  finally { $("aBtn").disabled = false; }
}

// ---- timer view ----
let state = null;
function hms(sec) { sec = Math.max(0, Math.floor(sec)); const h = Math.floor(sec / 3600), m = Math.floor(sec % 3600 / 60), s = sec % 60;
  return `${String(h).padStart(2, "0")}:${String(m).padStart(2, "0")}:${String(s).padStart(2, "0")}`; }
function render(s) {
  state = s;
  $("auth").classList.toggle("show", !s.loggedIn); $("main").classList.toggle("show", s.loggedIn);
  if (!s.loggedIn) { mode = "login"; applyMode(); return; }
  $("name").textContent = s.user.name || s.user.email; $("email2").textContent = s.user.email;
  $("av").textContent = (s.user.name || s.user.email).slice(0, 2).toUpperCase();
  $("pill").textContent = s.clockedIn ? "Tracking" : "Clocked out"; $("pill").className = "pill" + (s.clockedIn ? " on" : "");
  $("clockBtn").textContent = s.clockedIn ? "Clock out" : "Clock in"; $("clockBtn").className = "btn" + (s.clockedIn ? " danger" : "");
  $("clockL").textContent = s.clockedIn ? "Today · clocked in since " + new Date(s.since).toLocaleTimeString([], { hour: "2-digit", minute: "2-digit" }) : "Today · not clocked in";
  const a = s.activity; $("act").textContent = a == null ? "–" : a + "%";
  const color = a == null ? "var(--muted2)" : a >= 66 ? "var(--success)" : a >= 33 ? "var(--warn)" : "var(--danger)";
  $("act").style.color = color; $("actBar").style.width = (a || 0) + "%"; $("actBar").style.background = color;
  $("app").textContent = s.app || "–";
  tick();
}
function tick() { if (state && state.loggedIn) $("clock").textContent = hms(state.todaySeconds + (state.clockedIn ? 0 : 0)); }
setInterval(() => { if (state && state.clockedIn) { state.todaySeconds += 1; tick(); } }, 1000);
$("clockBtn").onclick = async () => { $("clockBtn").disabled = true; try { render(await tt.clock(!state.clockedIn)); } finally { $("clockBtn").disabled = false; } };
$("logout").onclick = async () => render(await tt.logout());
$("web").onclick = () => tt.openWebsite();
tt.onState(render);
tt.state().then(render);
applyMode();
