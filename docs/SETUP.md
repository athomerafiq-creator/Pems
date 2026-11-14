# PEMS — Setup guide (about 20 minutes)

You need: the GitHub account that owns this repo, a free **Supabase** account and a free
**Cloudflare** account. Nothing here costs money. Never paste passwords or the
`service_role` key into chat, email or code.

---

## Step 1 — Create the database (Supabase)

1. Go to **supabase.com** → *Sign in with GitHub* (use the athomerafiq-creator account).
2. **New project** → Name `pems` → set a strong database password (keep it yourself) →
   Region **Southeast Asia (Singapore)** → Plan **Free** → *Create*. Wait ~2 minutes.
3. Left menu → **SQL Editor** → *New query*.
4. Open `supabase/schema.sql` in this repo → **Raw** → select all → copy →
   paste into the SQL editor → **Run**. You should see *Success. No rows returned*.

## Step 2 — Lock down sign-ups

Supabase → **Authentication** → **Sign In / Providers** (or *Providers*) → **Email**:

* **Allow new users to sign up** → **OFF** (only invited people can get in)
* **Confirm email** → ON
* Save.

## Step 3 — Put the app online (Cloudflare Pages)

1. **dash.cloudflare.com** → **Workers & Pages** → **Create** → **Pages** →
   **Connect to Git** → connect GitHub → choose the **Pems** repository.
2. Build settings: Framework preset **None**, Build command **(empty)**,
   Build output directory **/** → **Save and Deploy**.
3. You get an address like `https://pems-xxx.pages.dev`. Copy it.

## Step 4 — Connect the app to the database

1. Supabase → **Project Settings** → **API** (or *Data API*). Copy:
   * **Project URL** (e.g. `https://abcd1234.supabase.co`)
   * **anon public** key (long text starting `eyJ...`)
     — *not* the `service_role` key.
2. Send those two values to the developer, **or** edit `config.js` in GitHub
   (pencil icon) and paste them between the quotes → *Commit changes*.
   Cloudflare redeploys automatically in about a minute.
3. Supabase → **Authentication** → **URL Configuration**:
   * **Site URL** = your Cloudflare address from Step 3
   * **Redirect URLs** → *Add URL* → the same address → Save.

## Step 5 — Invite the three users

Supabase → **Authentication** → **Users** → **Invite user**, one at a time:

1. `athomerafiq@gmail.com` (becomes **Principal** automatically)
2. `pstocoo.ishc@gmail.com` (Md Sumon Reza — PA)
3. `support@revenuehelper.org` (PA02)

Each person gets an email → clicks the link → sets their own password (10+ characters)
→ is inside PEMS. Their access is pre-set; the Principal can change it any time in
**Settings → Assistant access**.

Anyone else you invite later starts **switched off**; turn them on in Settings.

## Step 6 — Keep the free database awake (2 minutes)

Free Supabase projects pause after 7 days with no use. To be safe:
GitHub → this repo → **Settings** → **Secrets and variables** → **Actions** →
**New repository secret**:

* `SUPABASE_URL` = the Project URL
* `SUPABASE_ANON_KEY` = the anon key

The included workflow pings the database once a day.

---

## Backups (do this every week or month)

The free plan has no automatic backups. Two easy ways:

* **Quick:** Supabase → **Table Editor** → open each table → **Export → CSV**.
* **Full:** Supabase → Project Settings → **Database** → copy the connection string, then on
  any computer with PostgreSQL tools: `pg_dump "<connection string>" > pems-backup.sql`.
  Files: Supabase → **Storage** → `pems-files` → download.

Keep backups on an encrypted drive. Test a restore once into a new free project.

## Good to know

* **Exchange rate:** Principal sets it in Settings (1 USD = ? BDT).
* **Workspaces:** Settings → Workspaces → *Add workspace*; then tick it for each assistant.
* **Revoke an assistant:** Settings → Assistant access → *Revoke access* (immediate).
* **Email notifications & automatic Google Calendar sync** are queued inside PEMS now;
  sending them for real is phase 2 (needs one Google sign-in by the Principal).
  Until then every meeting has an *Open in Google Calendar* link.
* **Limits of the free plan:** 500 MB database, 1 GB files. Keep scans compressed.
