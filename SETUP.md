# Nexvoka — Setup & GitHub Instructions

Everything you need to get Nexvoka into a Git repo and running.

## 1. What's in this folder

```
nexvoka/
├── prototype/index.html      ← the working prototype (open in a Claude artifact)
│   └── index-v01-backup.html  ← previous version, kept for reference
├── server/                   ← real multi-API orchestrator (Node/Express)
│   ├── src/index.js
│   ├── package.json
│   └── .env.example
├── docs/
│   ├── ARCHITECTURE.md
│   └── PRODUCT.md
├── README.md
├── SETUP.md                  ← this file
└── .gitignore
```

## 2. Create the GitHub repo

**Option A — GitHub website (easiest):**
1. Go to github.com → New repository
2. Name it `nexvoka`, leave it empty (no README, no .gitignore — you already have them)
3. Copy the repo URL it gives you (e.g. `https://github.com/YOURNAME/nexvoka.git`)

**Then from your terminal**, inside the unzipped `nexvoka` folder:

```bash
cd nexvoka
git init
git add -A
git commit -m "Nexvoka v0.1 — prototype, docs, orchestrator skeleton"
git branch -M main
git remote add origin https://github.com/YOURNAME/nexvoka.git
git push -u origin main
```

Done — your code is on GitHub.

## 3. Run the prototype

The prototype (`prototype/index.html`) calls the Anthropic API through Claude's proxy, so it runs as-is inside a Claude.ai artifact. To run it on your own site, replace the `callClaude()` fetch with a call to your own backend proxy (never put an API key in the HTML).

## 4. Run the real server (when ready)

```bash
cd server
npm install
cp .env.example .env
# open .env and paste your keys:
#   ANTHROPIC_API_KEY=...
#   OPENAI_API_KEY=...
#   GOOGLE_API_KEY=...
npm run dev
```

Server starts on `http://localhost:3001`. Health check: `curl http://localhost:3001/health`.

The `/api/round` endpoint streams each AI's response back over SSE (Server-Sent Events), so the frontend can show each council member as it finishes.

## 4b. Database setup

The schema lives in the repo as a migration — not hand-built in a dashboard. That way any environment can be recreated from scratch.

**Ozzie (once):** create the Supabase project under your own account, then invite Charles as a member. The account stays yours; access is granted.

**Charles (dev):** create your own separate free Supabase project as a sandbox. You'll be dropping and recreating tables while building — don't do that in the shared one.

Run the migration:

```bash
# Option A — psql
psql "$DATABASE_URL" -f server/migrations/001_init.sql

# Option B — paste server/migrations/001_init.sql into the Supabase SQL editor
```

What it creates: `workspaces`, `members`, `projects`, `knowledge_items`, `sessions`, `rounds`, `messages`, `agent_briefs`, `documents` — plus row-level security scoping every table to the caller's workspace. See `docs/DATA_MODEL.md` for the reasoning and the API surface that sits on top.

Schema changes go in **new** files (`002_*.sql`, `003_*.sql`), never by editing `001_init.sql` after it's been run somewhere.

## 4c. API keys — who holds what

**Never commit a key.** `.env` is gitignored; keep it that way.

| Key | Who | Where it lives |
|---|---|---|
| Anthropic / OpenAI / Google (dev) | Charles's own keys | his local `.env` |
| Anthropic / OpenAI / Google (prod) | Ozzie's keys | Railway env vars only |
| Database connection string | shared | password manager, not chat/email |

Charles using his own dev keys matters for two reasons: your production quota doesn't get burned by debugging loops, and per-key usage tells you what's actually costing money. Dev spend on these APIs is small.

If a key ever gets pasted into a chat, email, or commit — rotate it. Don't reason about whether it was exposed; just rotate.


## 4b. Set up the database (Charles does this)

The schema lives in the repo as a migration — never hand-built in a dashboard.

**Ozzie creates the Supabase project** (so the account and data stay with the business), then invites Charles as a member.

**Charles then:**
1. Creates his own free Supabase project as a dev sandbox
2. Opens Supabase → SQL Editor → pastes `server/migrations/001_init.sql` → Run
3. Adds `SUPABASE_URL` and `SUPABASE_SERVICE_KEY` to his local `.env`

The migration creates workspaces, members, projects, knowledge_items, sessions, rounds, messages, agent_briefs, documents — plus row-level security scoped by workspace, so no tenant can ever read another's data.

Schema changes after this go in new files (`002_*.sql`, `003_*.sql`), never by editing 001.

## 5. Deploy (when ready)

Use **Railway** (not Vercel — Nexvoka needs a persistent server for streaming):
1. railway.app → New Project → Deploy from GitHub repo
2. Point it at the `server/` folder
3. Add the three API keys as environment variables in Railway's dashboard
4. Optional: add the Railway PostgreSQL plugin to store sessions

## 6. Daily workflow (you + a collaborator)

```bash
git pull            # get latest before you start
# ... make changes ...
git add -A
git commit -m "what you changed"
git push            # share it
```

Each person keeps their own `.env` with their own keys — `.env` is gitignored, so keys never get committed.

## 7. Before launch — brand checklist

- [x] Register **nexvoka.com** ✓ secured
- [ ] Trademark search + filing in the software/SaaS class
- [ ] Grab @nexvoka on the socials you care about
- [ ] Confirm no GitHub org named `nexvoka` conflicts
- [ ] (Optional, deferred) nexvoka.ai — buy later if traction warrants; trademark protects the brand regardless

---

Renaming later is trivial — the brand name lives in a handful of strings in `prototype/index.html` and the docs. A find-and-replace does it.
