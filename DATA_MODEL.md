# Nexvoka — Data Model & Workspace Spec

*For Charles. This describes the Projects / Chats / Knowledge layer added in v0.2 of the prototype, and how to build it for real.*

---

## 1. The concepts

| Concept | What it is | Analogy |
|---|---|---|
| **Global source** | Org-wide context every project and every session can see | "Company handbook" |
| **Project** | A container for related work, with its own knowledge and sessions | Claude/ChatGPT "Projects" |
| **Session (chat)** | One council conversation inside a project | A single chat thread |
| **Round** | One deliberation pass within a session (R1 → R2 → R3) | — |
| **Knowledge item** | A titled block of context attached to global or a project | An uploaded doc / instruction |

A session belongs to exactly one project. A project belongs to one workspace (org). Knowledge attaches at **global** or **project** level — never at session level (session-specific context is just the conversation).

---

## 2. Schema (Postgres)

```sql
create table workspaces (
  id            uuid primary key default gen_random_uuid(),
  name          text not null,
  created_at    timestamptz default now()
);

create table users (
  id            uuid primary key default gen_random_uuid(),
  workspace_id  uuid references workspaces(id) on delete cascade,
  email         text unique not null,
  role          text not null default 'member',   -- owner | admin | member
  created_at    timestamptz default now()
);

create table projects (
  id            uuid primary key default gen_random_uuid(),
  workspace_id  uuid references workspaces(id) on delete cascade,
  name          text not null,
  description   text,
  archived      boolean default false,
  created_at    timestamptz default now()
);

-- Knowledge items: scope is either global (project_id null) or project-level
create table knowledge_items (
  id            uuid primary key default gen_random_uuid(),
  workspace_id  uuid references workspaces(id) on delete cascade,
  project_id    uuid references projects(id) on delete cascade,  -- NULL = global
  title         text not null,
  body          text not null,
  source_type   text default 'text',   -- text | file | url
  source_ref    text,                  -- storage key or URL when not inline text
  tokens_est    int,
  created_by    uuid references users(id),
  created_at    timestamptz default now()
);
create index on knowledge_items (workspace_id, project_id);

create table sessions (
  id            uuid primary key default gen_random_uuid(),
  project_id    uuid references projects(id) on delete cascade,
  title         text not null default 'New session',
  scope         text not null default 'both',   -- both | project | none
  created_by    uuid references users(id),
  created_at    timestamptz default now(),
  updated_at    timestamptz default now()
);

create table rounds (
  id            uuid primary key default gen_random_uuid(),
  session_id    uuid references sessions(id) on delete cascade,
  topic_index   int not null,        -- which user question this belongs to
  round_number  int not null,        -- 1 | 2 | 3
  mode          text not null,       -- parallel | debate | synthesize | critique
  created_at    timestamptz default now()
);

create table messages (
  id            uuid primary key default gen_random_uuid(),
  session_id    uuid references sessions(id) on delete cascade,
  round_id      uuid references rounds(id) on delete set null,
  author        text not null,       -- user | claude | gpt | gemini | cowork | notebook | veo | synthesis | verdict | document
  body          text not null,       -- HTML or markdown
  created_at    timestamptz default now()
);
create index on messages (session_id, created_at);

-- Council-written briefs for action agents, produced at synthesis
create table agent_briefs (
  id            uuid primary key default gen_random_uuid(),
  session_id    uuid references sessions(id) on delete cascade,
  round_id      uuid references rounds(id) on delete cascade,
  agent         text not null,       -- cowork | notebook | veo
  brief         text not null,
  status        text default 'pending',  -- pending | running | done | failed
  result        text,
  created_at    timestamptz default now()
);
```

**Row-level security:** scope everything by `workspace_id`. A user can only read rows whose workspace matches their own — same pattern VyBeos already uses for multi-tenant isolation.

---

## 3. Context assembly — the important part

Before every model call, the orchestrator builds a context preamble from the knowledge layer. This is the function that makes projects worth having.

```js
async function buildContext(sessionId) {
  const session = await getSession(sessionId);
  if (session.scope === 'none') return '';

  const project = await getProject(session.project_id);
  const blocks = [];

  if (session.scope === 'both') {
    const global = await getKnowledge({ workspaceId: project.workspace_id, projectId: null });
    if (global.length) {
      blocks.push(
        'SHARED ORGANISATION CONTEXT (applies everywhere):\n' +
        global.map(k => `• ${k.title}: ${k.body}`).join('\n')
      );
    }
  }

  const projectKb = await getKnowledge({ projectId: project.id });
  if (projectKb.length) {
    blocks.push(
      `PROJECT CONTEXT — ${project.name}:\n` +
      projectKb.map(k => `• ${k.title}: ${k.body}`).join('\n')
    );
  }

  return blocks.length ? blocks.join('\n\n') + '\n\n' : '';
}
```

This preamble prepends the user message for **every** council member, in **every** round, and for action-agent activations too. The prototype does exactly this in `knowledgeContext()` — mirror that behaviour.

### Token budgeting (do this before launch)

Knowledge grows and context windows don't. Two things needed:

1. **`tokens_est` per item**, summed at assembly time. If the total exceeds a budget (suggest ~25% of the smallest participating model's window), fall back to retrieval instead of stuffing.
2. **Retrieval path**: embed knowledge items (pgvector — already in the VyBeos stack), and at assembly time select only the top-k items relevant to the user's question. Stuff-everything is correct for small projects; retrieval is correct at scale. Build the interface so the switch is invisible to the caller.

---

## 4. The scope decision (still open — prototype shows both)

The prototype exposes three settings so the product decision can be made from experience rather than theory:

| Scope | Behaviour | Best when |
|---|---|---|
| `both` | Global + project context | One org, many related projects — most business use |
| `project` | Project context only | Client work needing hard separation; consultancy/agency mode |
| `none` | No shared context | Clean-room reasoning, testing, sensitive one-offs |

**Recommendation:** ship `both` as the default, keep all three as a per-session setting. The reason is practical rather than philosophical — `both` is what makes the product feel like it knows you, and it's the tier that creates lock-in. But `project`-only is not optional for anyone doing client work, where leaking Client A's context into Client B's session is a real liability. Since the difference is one field on `sessions`, supporting all three costs almost nothing.

Note the setting lives on the **session**, not the project, so a user can run one clean-room session inside an otherwise context-rich project.

---

## 5. API surface

```
GET    /api/projects                       list projects (+ session counts)
POST   /api/projects                       { name, description }
PATCH  /api/projects/:id                   rename / archive
DELETE /api/projects/:id

GET    /api/knowledge?projectId=           list (omit projectId for global)
POST   /api/knowledge                      { projectId|null, title, body }
DELETE /api/knowledge/:id

GET    /api/sessions?projectId=            list sessions in a project
POST   /api/sessions                       { projectId, scope }
PATCH  /api/sessions/:id                   { title, scope }
GET    /api/sessions/:id                   full session: messages + rounds + briefs

POST   /api/rounds                         { sessionId, message?, roundNumber, mode }  → SSE
POST   /api/synthesis                      { sessionId, topicIndex } → synthesis + briefs
POST   /api/briefs/:id/activate            run an action agent from its brief
POST   /api/sessions/:id/compile           → markdown document
```

`/api/rounds` is the hot path and streams over SSE — one event per council member as it completes, so the UI fills in progressively rather than waiting for the slowest model.

---

## 6. Build order (suggested)

1. **Schema + auth + workspace scoping.** Everything else assumes tenant isolation exists.
2. **Projects & sessions CRUD** with the sidebar wired to real data (the prototype's sidebar is the target UX).
3. **Knowledge CRUD + `buildContext()`.** Verify by asking a council question that can only be answered from project knowledge.
4. **Rounds over SSE**, replacing the prototype's simulated personas with real Anthropic / OpenAI / Google calls. The context protocol is unchanged — only the caller differs.
5. **Synthesis → briefs → activation.**
6. **Compile document**, persisted so it can be retrieved later.
7. **Token budgeting + pgvector retrieval** once real projects get large.

---

## 7. Known gaps / open questions

- **Prototype persistence is in-memory.** Reloading resets projects and sessions. Real persistence is step 1 above; nothing in the UI needs to change.
- **Concurrency:** two users in one session simultaneously is undefined. Simplest v1 answer is a soft lock while a round is running.
- **Cost per session:** a full R1→R2→synthesis→R3→verdict→document run is 12+ model calls. Worth testing cheaper models for R1 and reserving frontier models for synthesis/verdict.
- **Action agents:** VEO is callable today via the Gemini API; NotebookLM has no public API yet (enterprise only); Cowork's integration surface still needs a decision. All three are simulated in the prototype behind a clean interface, so each can be swapped independently.
