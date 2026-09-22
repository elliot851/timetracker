# Checklista — export enligt `export-prompt-hubstaff-artush.md`

| Punkt | Status | Kommentar |
|---|---|---|
| `export/`-mapp i projektroten | **OK** | |
| `README-OVERLAMNING.md` med alla begärda rubriker | **OK** | Vad systemet gör · Delarna · Skärmbildsflödet · Tidsspårningen · Anställd-sidan · Chefs-sidan · Datamodell · Säkerhet · Kända brister · Beroenden · Nycklar som Westros måste sätta · Starta lokalt |
| Källkod för ALLA delar i `src/<del>/` | **OK** | `mac-app` (Swift), `desktop-client` (Electron + Actions-workflow), `server` (Worker), `web` (Pages). Utan node_modules, build, .git, cache, loggar, riktiga bilder/data. |
| `schema.sql` — original + Postgres | **OK** | DEL 1 SQLite (verifierad: laddar i sqlite3, 5 tabeller). DEL 2 Postgres med FK, index, RLS-policies, hjälpfunktioner och gallringsfunktion (balanserad syntax kontrollerad; ej körd mot en Postgres här). |
| 5–10 exempelskärmbilder + exempeldata | **OK** | 6 påhittade JPEG (1280 px, q40, samma namnformat som produktion) + `users/shifts/minutes/warnings.json` och `minutes.csv`. Inga riktiga personer. |
| `env.example` utan riktiga värden | **OK** | |
| Sökning efter nycklar/lösenord/tokens/personuppgifter | **OK** | Inga API-nycklar, tokens, lösenord i klartext eller personnummer. Kvarvarande riktiga adresser är **avsiktliga**: de tre admin-kontona (mottagarens eget team, i `seed-admins.sql`/README) och avsändaren `timelytracker@outlook.com` i `wrangler.toml` (ska bytas till egen Brevo-avsändare, se README). Lösenordshashar (PBKDF2) finns i `seed-admins.sql` på ägarens begäran så att admin-inloggningarna följer med; själva lösenordet står inte i paketet. |
| `screenshots/` med 3–6 bilder av systemet i drift | **SAKNAS** | Skärmdumpar kunde inte tas från den sandlådade miljön (skärminspelning och WebKit-rendering blockerade). Varje vy är i stället beskriven i README under "Chefs-sidan" och "Anställd-sidan", och systemet är live på https://timetracker-a2o.pages.dev för egen titt. |
| `PROMPT-TILL-CLAUDE.md` | **OK** | Del A: deploy på egna konton steg för steg med verifiering. Del B: sidor/roller, Supabase-tabeller med RLS, Storage-bucket + gallring, agent-distribution, bakgrundsjobb, vad som slängs, byggordning. |
| `CHECKLISTA.md` | **OK** | Den här filen. |
| Zip `tidssparning-export-<datum>.zip` | **OK** | Sökvägen står sist i svaret. |

**Utöver prompten, på ägarens begäran:** `seed-admins.sql` — de befintliga admin-kontona följer med; övrig historik (pass, minuter, bilder) gör det inte.
