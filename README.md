# PEMS — Personal Executive Management System

Private digital office for **M Rafiq Hoque** and his assistants: calendar, tasks, contacts,
document vault, personal finance (USD + BDT), payroll, meetings, team chat, attendance,
official warnings, travel, weekly reports (PDF/Excel) — one secure web app.

| Part | Where it runs | Cost |
|---|---|---|
| Web app (`public/`) | Cloudflare Workers (static assets) | Free |
| Database, logins, files, live chat (`supabase/schema.sql`) | Supabase | Free tier |
| Source code & daily keep-alive | GitHub (this repo) | Free |

**Setup:** follow [`docs/SETUP.md`](docs/SETUP.md) — about 20 minutes, no coding.

## Security in one paragraph
Every rule is enforced inside the database (PostgreSQL row-level security), not just by hiding
buttons. Assistants only see the modules and workspaces the Principal grants; PERSONAL records
are never visible to them; their finance entries are always *Pending* until the Principal
approves; they cannot archive, delete, approve their own work or change permissions; attendance
times are stamped by the server clock; switching an account off blocks it immediately.
Files live in a private bucket and open only through 2-minute signed links.
`tests/rls_test.py` checks all of this (56 checks) against a real PostgreSQL.

## Layout
```
public/index.html     the whole app (no build step)
public/config.js      Supabase URL + anon key (public by design)
wrangler.jsonc        Cloudflare Workers config (serves ./public)
supabase/schema.sql   database, security rules, storage, realtime
docs/SETUP.md         step-by-step setup and backup guide
tests/                security tests + browser smoke test
.github/workflows/    daily keep-alive ping
```
