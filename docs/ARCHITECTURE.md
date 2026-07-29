# Nexvoka — Architecture

## Overview

```
User ──► Frontend (chat UI, session spine, modes)
              │
              ▼
      Orchestrator (Express on Railway)
              │  fan-out, shared context, round sequencing
      ┌───────┼────────┬─────────────┐
      ▼       ▼        ▼             ▼
   Anthropic OpenAI  Google AI   Action agents
   (Claude)  (GPT)   (Gemini)    ├ VEO (Gemini API — live)
      │       │        │         ├ NotebookLM (API pending)
      └───────┴────────┘         └ Cowork (delivery hooks)
              │
              ▼
      Aggregator → shared transcript → next round context
              │
              ▼
      Postgres (sessions, rounds, briefs, documents)
```

## Core loop

1. **Round 1** — user message fans out to all active council members in sequence; each later member receives earlier members' answers in context.
2. **Round 2** — full R1 transcript is injected into each member's context with a mode-specific instruction (debate / synthesize / critique / parallel reassess).
3. **Synthesis** — a neutral call produces: 3-paragraph synthesis + one-sentence briefs for each action agent (JSON).
4. **Round 3** — final positions, no hedging.
5. **Verdict** — single arbiter call distills all rounds.
6. **Document** — full session compiled to one markdown document.

## Key design decisions

- **Action agents are dormant.** NotebookLM / Cowork / VEO never speak in rounds. They activate only from council-written briefs, on user tap. This keeps rounds fast and focused and makes agent activations feel intentional.
- **Sequential fan-out, not parallel.** Within a round, members respond in order so each can react to those before them. (Parallel requests + a second "react" pass is an alternative worth A/B testing for latency.)
- **Mode is per-action.** The active mode at the moment a round is triggered determines the instruction. Users can switch between rounds.
- **The prototype uses one model for all voices.** Claude plays every persona via system prompts. The server swaps each persona for its real API with the same context protocol — the frontend doesn't change.

## Server contract (planned)

```
POST /api/session          → create session
POST /api/round            { sessionId, message?, roundType, mode } → SSE stream of member responses
POST /api/synthesis        { sessionId } → synthesis + briefs JSON
POST /api/activate         { sessionId, agent, brief } → agent deliverable
POST /api/compile          { sessionId } → markdown document
```

SSE streaming lets the UI render each member's tokens as they arrive rather than waiting per-member.

## Provider notes

- **VEO**: available now via Gemini API / Vertex AI (veo video generation endpoints). Async job → poll → video URL.
- **NotebookLM**: enterprise API only as of mid-2026; public API announced as in-progress. The interface slot exists; swap the simulated agent when it ships.
- **Cowork**: desktop agent; integration surface TBD. Near-term: Nexvoka produces the deliverable spec and hands off (file export / webhook).

## Deployment

- **Railway** — Express orchestrator + Postgres (Vercel serverless is incompatible with persistent SSE/Express needs).
- Keys server-side only. Frontend never calls providers directly.
- Per-tenant isolation from day one if this joins the VyBeos multi-tenant pattern.
