# TimeTracker — överlämning till Creative Loop

Allt som behövs för att köra systemet på egna konton ligger i det här paketet. Ge hela zip-filen till din AI (Claude Code) tillsammans med `PROMPT-TILL-CLAUDE.md` — den innehåller steg-för-steg-instruktionen för att ladda upp allt på egna Cloudflare-, GitHub- och Brevo-konton och sedan bygga in det i Creative Loop.

**Innehåll**

| Mapp/fil | Vad |
|---|---|
| `src/web/` | Hemsidan + admin-dashboarden (en fil: `index.html` + `logo.png`). Cloudflare Pages. |
| `src/server/` | API:t (`worker.js`), Cloudflare Worker + D1 (SQLite) + R2. `wrangler.toml`, `schema.sql`. |
| `src/mac-app/` | Native macOS-appen (Swift/AppKit) som de anställda kör. `build.sh` bygger. |
| `src/desktop-client/` | Windows/Linux/macOS-klienten (Electron) + GitHub Actions-workflow som bygger installers. |
| `schema.sql` | Databasschemat: original (SQLite/D1) + översättning till Postgres/Supabase med RLS. |
| `exempel/` | 6 påhittade skärmbilder + exempeldata (JSON/CSV) för alla tabeller. Inga riktiga personer. |
| `env.example` | Alla miljövariabler/hemligheter med förklaring (inga riktiga värden). |
| `seed-admins.sql` | Skapar de tre admin-kontona med befintliga inloggningar (lösenordshash, inte klartext). |
| `PROMPT-TILL-CLAUDE.md` | Instruktionen till AI:n som ska deploya och integrera. |
| `CHECKLISTA.md` | Vad som är OK / SAKNAS i den här exporten. |

---

## Vad systemet gör

Hubstaff-liknande tidsspårning för ett team. Den anställda stämplar in i en app på sin dator; appen mäter aktivitet (tangentbord/mus) varje minut, tar en lågupplöst skärmbild var 10:e minut, loggar vilket program som är i förgrunden och varnar (och pausar timern) när aktiviteten är noll. Allt synkas till ett API i Cloudflare, och chefer (admin) ser hela teamet live i en webbdashboard: timmar, aktivitet, skärmbilder, varningar, analytics och tidrapporter.

## Delarna

| Del | Vad den gör | Språk/ramverk | Pratar med |
|---|---|---|---|
| **Agent, macOS** (`src/mac-app`) | Instämpling, aktivitet/min, skärmbild/10 min, app-spårning, idle-varning, lokal lagring + synk | Swift 5, AppKit, ScreenCaptureKit. Byggs med `swiftc` (inget Xcode-projekt) | HTTPS → API, `Authorization: Bearer <token>` |
| **Agent, Windows/Linux/macOS** (`src/desktop-client`) | Samma funktioner som Mac-appen | Electron 33 (Node), `electron-builder` | HTTPS → API, samma bearer-token |
| **API/server** (`src/server`) | Konton, e-postverifiering, lösenordsåterställning, roller, lagring av pass/minuter/varningar, uppladdning och utlämning av skärmbilder | Cloudflare Worker (JavaScript, inga beroenden) | D1 (SQLite) via binding `DB`, R2 via binding `SHOTS`, Brevo REST för e-post |
| **Databas** | Tabellerna `users, sessions, shifts, minutes, warnings` | Cloudflare D1 (SQLite) | — |
| **Bildlagring** | Skärmbilderna som JPEG-objekt | Cloudflare R2, bucket `timetracker-shots` | — |
| **Webbvy** (`src/web`) | Landningssida + inloggning + admin-dashboard (Dashboard, Activity, Analytics, Timesheets, Warnings, Members, Download) | En statisk HTML-fil, vanilla JS, ingen byggprocess | HTTPS → API |
| **Bakgrundsjobb** | Inga cron-jobb i dag. Klienterna har en lokal återförsökskö (`queue.json` i Electron) för misslyckade synkar. | — | — |

**Adresser i drift i dag** (Artushs konton; ersätts med egna vid flytt): API `https://timetracker-api.artush22.workers.dev`, webb `https://timetracker-a2o.pages.dev`, GitHub `https://github.com/artush22-eng/timetracker` (publikt; releaser med installers). API-adressen är hårdkodad i `src/mac-app/Sources/Session.swift` (`defaultAPIBaseURL`), `src/desktop-client/main.js` (`API`, `WEBSITE`) och `src/web/index.html` (`API`, `GITHUB_REPO`).

**Autentisering:** e-post + lösenord. Lösenord hashas med PBKDF2-SHA256 (100 000 iterationer, slumpat salt). Inloggning ger en 40-teckens slumpad bearer-token som lagras i `sessions` med 90 dagars giltighet. Nya konton måste verifiera en 6-siffrig kod som mejlas (giltig 15 min). Rollen `admin` sätts av listan `ADMIN_EMAILS` (hemlig miljövariabel) och synkas vid varje anrop; alla andra är `user`.

## Skärmbildsflödet, steg för steg

1. **Start:** när den anställda trycker *Clock in* skapas ett pass (`shifts`) och trackern startar. Första minuten tas alltid en skärmbild.
2. **Intervall:** aktiviteten stängs av varje **60 s**; en skärmbild tas var **10:e minut** (`SCREENSHOT_EVERY_MIN` i Electron, `screenshotEvery` i `Tracker.swift`, överstyrbart via `defaults write com.artush.timetracker screenshotEveryMinutes N` på Mac). *Take screenshot now* i menyn tar en direkt.
3. **Vilken skärm:** den skärm där muspekaren är. Mac: ScreenCaptureKit (`SCScreenshotManager`). Electron: `desktopCapturer`.
4. **Upplösning/format:** nedskalad till **1280 px bredd**, **JPEG kvalitet 40** (~30–100 KB per bild).
5. **Lokal kopia:** Mac: `~/Documents/TimeTracker/users/<userId>/screenshots/<yyyy-MM-dd>/<yyyy-MM-dd_HH-mm-ss>.jpg`. Electron: `<userData>/screenshots/<yyyy-MM-dd>/<samma namn>.jpg` (`%APPDATA%\TimeTracker` på Windows, `~/.config/TimeTracker` på Linux, `~/Library/Application Support/TimeTracker` på Mac).
6. **Sändning:** `POST /api/upload?key=<dag>/<fil>.jpg` med rå JPEG i body + bearer-token. Servern sparar i R2 som **`<userId>/<yyyy-MM-dd>/<yyyy-MM-dd_HH-mm-ss>.jpg`** och skriver nyckeln i `minutes.screenshots` (JSON-lista) för den minuten.
7. **Lagringstid/radering:** **ingen automatisk gallring finns** — bilderna ligger kvar tills någon raderar dem i R2. Lokala kopior raderas inte heller automatiskt. (Se "Kända brister".)
8. **Visning för chefen:** webbens *Activity*-vy hämtar `GET /api/minutes?user=<id>&date=<dag>` och laddar varje bild via `GET /api/shot?key=<nyckel>&user=<id>` (kräver admin-token eller att man är ägaren; servern kontrollerar att nyckelns prefix är ägarens id). Bilderna visas per timme med aktivitetsprocent och app-namn, och öppnas i en lightbox med pilar/tangentbord. Dashboard-kortet visar senaste bilden per person. Vid idle-varning tas en extra bevisbild som visas i *Warnings*.
9. **Stopp:** *Clock out* sätter `end_at` på passet och stoppar trackern. Electron stämplar även ut automatiskt vid sleep/låst skärm.

## Tidsspårningen

- **Arbetstid** = summan av passen (`shifts.start_at` → `end_at`, pågående pass räknas till nu). Ett pass = en instämpling.
- **Aktivitet** per minut: andel sekunder med input. Mac mäter tangentbord och mus separat (`CGEventSource.secondsSinceLastEventType`, ingen Accessibility-rättighet krävs). Electron mäter bara "någon input" via `powerMonitor.getSystemIdleTime()` och sätter keyboard = mouse = overall. Klassificering i vyerna: ≥66 % fokuserad, 33–65 % lätt, <33 % idle.
- **Inaktivitet:** efter **60 s** utan input under ett pass (`IDLE_THRESHOLD_SEC` / `inactivityThreshold`) stämplas passet ut **retroaktivt vid tidpunkten då inputen upphörde**, trackern stoppas, en varning sparas med bevisbild, och en dialog frågar *Back to work* (nytt pass startas) eller *Clock out*. Den inaktiva tiden räknas alltså aldrig.
- **Paus:** finns inte som eget begrepp — man stämplar ut/in.
- **Tidszon:** alla tidsstämplar lagras som ISO-8601 **UTC**. Dagsgränser i webben beräknas i **webbläsarens lokala tidszon** (`fmt.day`); Mac-appen använder `Calendar.current`. Rapporter för team i olika tidszoner blir därför inte helt konsekventa.
- **Summeringar:** per dag = passens överlapp med dygnet (`shiftSecondsOn` i `index.html`); vecka = måndag-baserad kalendervecka (`Shift.swift`) / senaste 7 dagar i webben (`/api/range?user=all&from&to` ger minuter, pass och varningar i ett anrop).

## Anställd-sidan

- **Installation:** ladda ner från hemsidans *Download* (macOS: zip med appen; Windows: `TimeTracker-Setup.exe` eller portable; Linux: AppImage/deb från GitHub Releases). Osignerade byggen → *Högerklicka → Öppna* på Mac, *More info → Run anyway* i SmartScreen på Windows.
- **Inloggning:** e-post + lösenord i appen (samma konto som webben). Skapa konto går i appen eller på webben; koden mejlas. Sessionen ligger i `UserDefaults` (Mac) resp. `session.json` (Electron) tills man loggar ut.
- **OS-stöd:** macOS 14+ (native app, Apple Silicon och Intel), Windows 10/11 64-bit, Linux x86_64 (AppImage/deb; behöver `xdotool` för app-namn).
- **Rättigheter:** macOS kräver **Skärminspelning** (Systeminställningar → Integritet) — utan den blir bilderna svarta. Mac-appen signeras med ett självsignerat cert (`setup-signing.sh`) så rättigheten överlever ombyggen. Electron på Mac frågar samma sak. Windows/Linux kräver inget.
- **Autostart:** inte inbyggt. (Kan läggas till: Login Items på Mac, `app.setLoginItemSettings` i Electron.)
- **Avinstallation:** ta bort appen; data ligger i mapparna under "Lokal kopia" ovan och kan raderas för hand. Windows: Avinstallera via Appar & funktioner (NSIS).

## Chefs-sidan

Webben är **endast för admins** och är monitoring-only (ingen instämpling på webben). Medlemmar som loggar in möts av en sida som hänvisar till appen.

| Vy | Visar |
|---|---|
| **Dashboard** | Team i dag: antal som jobbar nu, timmar, snittaktivitet, varningar; kort per person med status, senast sedd, senaste skärmbild, arbetad tid, aktivitet, minuter. *Inspect day* → Activity. |
| **Activity** | En person, en dag: KPI:er (arbetad tid, aktivitet kb/mus, antal bilder, toppapp), skärmbilder grupperade per timme med aktivitetsstapel och app, lightbox. Dagväljare + personväljare. |
| **Analytics** | Alla/en person, i dag / 7 / 30 dagar: total tid, aktivitet, varningar, jobbar nu; timmar per dag, aktivitet per timme på dygnet, klassificeringsring, toppappar, tabell per person med sparkline. |
| **Timesheets** | Pass per dag: in, ut, längd, aktivitet — per person eller alla. |
| **Warnings** | Alla idle-händelser: person, från-tid, svar (*Went back to work* / *Clocked out* / väntar), bevisbild, app. |
| **Members** | Alla konton: roll, status (working/offline/unverified), senast sedd, skapad. |
| **Download** | Plattformskorten. |

Mac-appen har motsvarande vyer (Timer, Activity, Analytics, Warnings, Team) och en admin kan där titta på andra användares data utan att byta konto (VIEWING-väljare).

## Datamodell

Se `schema.sql` för exakt DDL. Sammanfattning:

- **users** — `id` (uuid text, PK), `email` (unik, gemener), `name`, `password` (`pbkdf2$iter$salt$hash`), `role` (`admin`/`user`), `created_at` (ISO), `verified` (0/1), `verify_code` (6 siffror), `code_expires` (ISO).
- **sessions** — `token` (PK), `user_id` → users, `expires_at`.
- **shifts** — `id` (uuid från klienten, PK), `user_id`, `start_at`, `end_at` (NULL = pågår). Upsert på id.
- **minutes** — `id` = `<user_id>:<ts>` (PK, idempotent), `user_id`, `ts`, `keyboard`, `mouse`, `overall` (0–100), `apps` (JSON `[{name,seconds,title}]`), `screenshots` (JSON `["<user_id>/<dag>/<fil>.jpg"]`).
- **warnings** — `id` (uuid), `user_id`, `user_name`, `started_at`, `resolved_at`, `outcome` (`resumed`/`clockedOut`/NULL), `screenshot` (R2-nyckel), `activity`, `app`.
- **Lokala filer (Mac):** `~/Documents/TimeTracker/users/<id>/activity/<dag>.jsonl` (en minut per rad), `shifts.json`, `warnings.json`, `screenshots/`, `tracker.log`. **Electron:** `session.json`, `shifts.json`, `queue.json`, `screenshots/`, `tracker.log` i userData.
- **R2-objekt:** `<user_id>/<yyyy-MM-dd>/<yyyy-MM-dd_HH-mm-ss>.jpg`, `Content-Type: image/jpeg`.

**API-endpoints** (`worker.js`): `POST /api/register|login|verify|resend-code|request-reset|reset|logout`, `GET /api/me`, `POST /api/shifts|minutes|warnings` (batch-upsert), `POST /api/upload?key=`, `GET /api/users`, `GET /api/minutes?user&date`, `GET /api/shifts?user`, `GET /api/warnings[?user]`, `GET /api/range?user=<id|all>&from&to`, `GET /api/shot?key[&user]`. CORS `*`.

## Säkerhet

- **Känsligt:** skärmbilderna är personuppgifter (kan visa privata meddelanden, lösenord på skärmen, tredje part). Även app-/fönstertitlar och aktivitetsdata är personuppgifter. Informera de anställda skriftligt och ha rättslig grund (GDPR) innan drift.
- **Skyddat i dag:** lösenord hashade; tokens slumpade och tidsbegränsade; en medlem kan bara läsa sin egen data, admin allt; skärmbilder lämnas bara ut via API:t efter ägar-/admin-kontroll (R2-bucketen är inte publik); hemligheter ligger som Cloudflare-secrets; e-postverifiering; lösenordskrav ≥8 tecken med bokstav+siffra.
- **INTE skyddat:** ingen rate limiting (brute force mot `/api/login` är möjlig); CORS är öppet (`*`); ingen kryptering av lokala kopior på datorn; ingen gallring av bilder; ingen 2FA; tokens återkallas inte vid lösenordsbyte; `verify_code` används både för verifiering och återställning; admin-listan styrs av en env-variabel, inte av UI; Electron-klienten är osignerad; API-svaren till admin innehåller allas e-post.

## Kända brister, buggar och vad som inte är klart

- Ingen automatisk gallring av skärmbilder eller minuter (lokalt eller i R2).
- Ingen rate limiting, ingen auditlogg över vem som tittat på vilka bilder.
- Electron: keyboard/mouse särskiljs inte (bara "input"); app-namn via PowerShell/xdotool var 5:e sekund (Linux Wayland ger ingen titel; Wayland-skärmbilder kan kräva PipeWire-dialog).
- Autostart och uppdateringskontroll saknas i båda agenterna.
- Ingen "paus"-funktion, inga projekt/uppgifter, ingen CSV-export, inga scheman.
- Verifieringsmejl från `@outlook.com`-avsändaren hamnar ofta i skräppost — egen domän i Brevo behövs.
- Webben beräknar dygn i webbläsarens tidszon; teams i olika tidszoner blir inkonsekventa.
- Mac-appen är byggd för macOS 14+ och distribueras som zip utan notarisering.
- Test-svit saknas helt; ingen CI utöver bygget av Electron-installers.

## Beroenden som mottagaren måste ha

- **Cloudflare-konto** med Workers, **D1**, **R2** (kräver att R2 aktiveras, betalkort) och **Pages**. `wrangler` 4.x (i `src/server/package.json`).
- **Node 22** (för wrangler och Electron-bygget).
- **Brevo-konto** (transaktionsmejl) med verifierad avsändare, helst egen domän — eller byt `sendEmail()` i `worker.js` till valfri leverantör.
- **GitHub-repo** (publikt om nedladdningslänkarna `releases/latest/download/...` ska funka utan inloggning) för Actions-bygget av installers.
- **macOS-dator med Xcode Command Line Tools** för att bygga Mac-appen (`swiftc`).
- Valfritt: Apple Developer-konto (notarisering) och Windows-kodsigneringscertifikat.

## Nycklar som Westros måste sätta

Inga riktiga värden finns i exporten. Sätt egna:

| Nyckel | Var | Hur |
|---|---|---|
| `BREVO_API_KEY` | Cloudflare Worker (secret) | `npx wrangler secret put BREVO_API_KEY` |
| `ADMIN_EMAILS` | Cloudflare Worker (secret) | `printf 'a@x.se,b@x.se' \| npx wrangler secret put ADMIN_EMAILS` |
| `MAIL_FROM_EMAIL`, `MAIL_FROM_NAME` | `wrangler.toml [vars]` | verifierad avsändare i Brevo |
| `database_id`, `bucket_name` | `wrangler.toml` | egna D1/R2-resurser |
| API-URL + webb-URL + `GITHUB_REPO` | de tre klienterna (se ovan) | ersätt de hårdkodade adresserna |
| GitHub-token | endast lokalt för push | inget i koden |
| Admin-konton | databasen | **Följer med:** `seed-admins.sql` skapar de tre admin-kontona (eddie.wdr@gmail.com, artush22@icloud.com, elliot@westrosdigitalretail.se) med samma lösenord som i dag (som hash — själva lösenordet får ni av Artush, det står inte i paketet). Kör filen efter `schema.sql`. Övrig gammal data (pass, minuter, bilder) är inte viktig och följer inte med. |

## Starta lokalt

**API (Cloudflare Worker):**
```bash
cd src/server
npm install
npx wrangler login
npx wrangler d1 create timetracker            # skriv in database_id i wrangler.toml
npx wrangler r2 bucket create timetracker-shots
npx wrangler d1 execute timetracker --remote --file=schema.sql
npx wrangler d1 execute timetracker --remote --file=../../seed-admins.sql   # admin-kontona
printf 'eddie.wdr@gmail.com,artush22@icloud.com,elliot@westrosdigitalretail.se' | npx wrangler secret put ADMIN_EMAILS
npx wrangler secret put BREVO_API_KEY         # klistra in nyckeln
npx wrangler deploy                            # → https://timetracker-api.<konto>.workers.dev
# lokalt: npx wrangler dev  (använder lokal D1/R2-emulering)
```

**Webben (Cloudflare Pages):**
```bash
# byt API-adressen överst i src/web/index.html, sen:
cd src/server && npx wrangler pages project create timetracker
npx wrangler pages deploy ../web --project-name timetracker --branch=main
# lokalt: öppna src/web/index.html direkt i webbläsaren (localStorage funkar från file:// i Chrome)
```

**Electron-klienten (Windows/Linux/macOS):**
```bash
cd src/desktop-client
# byt API/WEBSITE i main.js
npm install
npm start                    # kör lokalt
npm run dist:win             # eller dist:linux / dist:mac → dist/
# CI: lägg github-workflow-build.yml som .github/workflows/build.yml i repot,
#     sätt repository/publish.owner/repo i package.json, git tag v1.0.0 && git push --tags
```

**Mac-appen (native):**
```bash
cd src/mac-app
# byt defaultAPIBaseURL i Sources/Session.swift
./setup-signing.sh           # engångs: självsignerat cert "TimeTracker Dev"
./build.sh                   # bygger, signerar, installerar i /Applications
# första start: ge Skärminspelning i Systeminställningar
```
