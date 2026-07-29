# Nexvoka

**Many voices. One answer.**

Nexvoka is a multi-AI deliberation platform. One question convenes a council — Claude, ChatGPT, and Gemini — who answer, challenge each other across structured rounds, and converge on a single synthesis, verdict, and document. Action agents (NotebookLM, Cowork, VEO) stay dormant until the council writes them a brief.

> The name comes from *nexus* (a point of connection) + *voca* (Latin, "to call together"). nexvoka.com is secured. File a trademark in the software/SaaS class before public launch.

## Why this beats "ask three chatbots separately"

- **Shared context** — every AI sees every other AI's answer and responds to it by name.
- **Structured deliberation** — Round 1 (positions) → Round 2 (cross-examination) → Synthesis → Round 3 (final positions) → Verdict.
- **Modes** — Parallel, Debate, Synthesize, Critique change the deliberation style mid-session.
- **One output** — the session compiles into a single document: positions, agreements, disagreements, verdict, next steps.
- **Action agents on-demand** — the council writes the brief; the user activates NotebookLM (research), Cowork (delivery), or VEO (video) with one tap.

## Repo layout

```
nexvoka/
├── prototype/        # Single-file HTML prototype (Claude plays all voices)
│   └── index.html
├── server/           # Node.js/Express orchestrator (real multi-API backend)
│   ├── src/index.js
│   └── migrations/001_init.sql   # Postgres schema + row-level security
├── docs/
│   ├── ARCHITECTURE.md
│   ├── DATA_MODEL.md     # Projects / Chats / Knowledge spec
│   └── PRODUCT.md
└── README.md
```

## Running the prototype

Open `prototype/index.html` in a Claude.ai artifact context (it uses the proxied Anthropic API). For local testing outside Claude, point `callClaude()` at your own server proxy — never put API keys in the frontend.

## Running the server (real APIs)

```bash
cd server
npm install
cp .env.example .env   # add ANTHROPIC_API_KEY, OPENAI_API_KEY, GOOGLE_API_KEY
npm run dev
```

Deploy target: **Railway** (persistent Express server + PostgreSQL add-on).

## Roadmap

- [x] Prototype: council rounds, modes, synthesis, verdict, document compile
- [x] Prototype: Projects sidebar, sessions per project, two-tier knowledge layer
- [ ] Server: real Anthropic + OpenAI + Google API fan-out with streaming
- [x] Database schema + RLS migration (`server/migrations/001_init.sql`)
- [ ] Auth + saved sessions wired to the schema
- [ ] VEO integration (available now via Gemini API / Vertex AI)
- [ ] NotebookLM integration (waiting on public API — enterprise-only today)
- [ ] Cowork delivery hooks
- [ ] Billing (Stripe) + team workspaces
