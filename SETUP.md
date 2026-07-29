# Nexvoka — Setup & GitHub Instructions

Everything you need to get Nexvoka into a Git repo and running.

## 1. What's in this folder

```
nexvoka/
├── prototype/index.html      ← the working prototype (open in a Claude artifact)
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
