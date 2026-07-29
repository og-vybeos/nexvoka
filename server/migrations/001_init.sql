-- ============================================================
-- Nexvoka — 001_init.sql
-- Projects / Sessions / Knowledge / Rounds schema + RLS
-- Run against Supabase (or any Postgres 14+) via SQL editor or psql.
-- ============================================================

-- Supabase has pgcrypto + vector available; enable what we need.
create extension if not exists "pgcrypto";
create extension if not exists "vector";      -- for future knowledge retrieval

-- ─────────────────────────────────────────────
-- Tenancy
-- ─────────────────────────────────────────────
create table if not exists workspaces (
  id            uuid primary key default gen_random_uuid(),
  name          text not null,
  created_at    timestamptz not null default now()
);

-- Mirrors auth.users; app-level profile + workspace membership.
create table if not exists members (
  id            uuid primary key references auth.users(id) on delete cascade,
  workspace_id  uuid not null references workspaces(id) on delete cascade,
  email         text not null,
  role          text not null default 'member'
                  check (role in ('owner','admin','member')),
  created_at    timestamptz not null default now()
);
create index if not exists members_workspace_idx on members (workspace_id);

-- Helper: current user's workspace. Used by every RLS policy below.
create or replace function current_workspace_id()
returns uuid
language sql stable security definer
set search_path = public
as $$
  select workspace_id from members where id = auth.uid()
$$;

-- ─────────────────────────────────────────────
-- Projects
-- ─────────────────────────────────────────────
create table if not exists projects (
  id            uuid primary key default gen_random_uuid(),
  workspace_id  uuid not null references workspaces(id) on delete cascade,
  name          text not null,
  description   text,
  archived      boolean not null default false,
  created_by    uuid references members(id) on delete set null,
  created_at    timestamptz not null default now()
);
create index if not exists projects_workspace_idx on projects (workspace_id, archived);

-- ─────────────────────────────────────────────
-- Knowledge layer
--   project_id IS NULL  → global source (whole workspace)
--   project_id NOT NULL → project-scoped source
-- ─────────────────────────────────────────────
create table if not exists knowledge_items (
  id            uuid primary key default gen_random_uuid(),
  workspace_id  uuid not null references workspaces(id) on delete cascade,
  project_id    uuid references projects(id) on delete cascade,
  title         text not null,
  body          text not null,
  source_type   text not null default 'text'
                  check (source_type in ('text','file','url')),
  source_ref    text,
  tokens_est    int,
  embedding     vector(1536),          -- null until retrieval path is built
  created_by    uuid references members(id) on delete set null,
  created_at    timestamptz not null default now()
);
create index if not exists knowledge_scope_idx on knowledge_items (workspace_id, project_id);

-- ─────────────────────────────────────────────
-- Sessions (chats) + rounds + messages
-- ─────────────────────────────────────────────
create table if not exists sessions (
  id            uuid primary key default gen_random_uuid(),
  workspace_id  uuid not null references workspaces(id) on delete cascade,
  project_id    uuid not null references projects(id) on delete cascade,
  title         text not null default 'New session',
  scope         text not null default 'both'
                  check (scope in ('both','project','none')),
  created_by    uuid references members(id) on delete set null,
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now()
);
create index if not exists sessions_project_idx on sessions (project_id, updated_at desc);

create table if not exists rounds (
  id            uuid primary key default gen_random_uuid(),
  workspace_id  uuid not null references workspaces(id) on delete cascade,
  session_id    uuid not null references sessions(id) on delete cascade,
  topic_index   int not null,
  round_number  int not null check (round_number between 1 and 9),
  mode          text not null
                  check (mode in ('parallel','debate','synthesize','critique')),
  created_at    timestamptz not null default now(),
  unique (session_id, topic_index, round_number)
);
create index if not exists rounds_session_idx on rounds (session_id);

create table if not exists messages (
  id            uuid primary key default gen_random_uuid(),
  workspace_id  uuid not null references workspaces(id) on delete cascade,
  session_id    uuid not null references sessions(id) on delete cascade,
  round_id      uuid references rounds(id) on delete set null,
  author        text not null
                  check (author in (
                    'user','claude','gpt','gemini',
                    'cowork','notebook','veo',
                    'synthesis','verdict','document'
                  )),
  body          text not null,
  created_at    timestamptz not null default now()
);
create index if not exists messages_session_idx on messages (session_id, created_at);

-- ─────────────────────────────────────────────
-- Council-written briefs for action agents
-- ─────────────────────────────────────────────
create table if not exists agent_briefs (
  id            uuid primary key default gen_random_uuid(),
  workspace_id  uuid not null references workspaces(id) on delete cascade,
  session_id    uuid not null references sessions(id) on delete cascade,
  round_id      uuid references rounds(id) on delete set null,
  agent         text not null check (agent in ('cowork','notebook','veo')),
  brief         text not null,
  status        text not null default 'pending'
                  check (status in ('pending','running','done','failed')),
  result        text,
  created_at    timestamptz not null default now()
);
create index if not exists briefs_session_idx on agent_briefs (session_id, status);

-- ─────────────────────────────────────────────
-- Compiled council documents
-- ─────────────────────────────────────────────
create table if not exists documents (
  id            uuid primary key default gen_random_uuid(),
  workspace_id  uuid not null references workspaces(id) on delete cascade,
  session_id    uuid not null references sessions(id) on delete cascade,
  title         text not null,
  markdown      text not null,
  created_at    timestamptz not null default now()
);
create index if not exists documents_session_idx on documents (session_id);

-- ─────────────────────────────────────────────
-- keep sessions.updated_at fresh
-- ─────────────────────────────────────────────
create or replace function touch_session()
returns trigger language plpgsql as $$
begin
  update sessions set updated_at = now() where id = new.session_id;
  return new;
end $$;

drop trigger if exists messages_touch_session on messages;
create trigger messages_touch_session
  after insert on messages
  for each row execute function touch_session();

-- ============================================================
-- Row-Level Security — every table scoped to the caller's workspace
-- ============================================================
alter table workspaces      enable row level security;
alter table members         enable row level security;
alter table projects        enable row level security;
alter table knowledge_items enable row level security;
alter table sessions        enable row level security;
alter table rounds          enable row level security;
alter table messages        enable row level security;
alter table agent_briefs    enable row level security;
alter table documents       enable row level security;

-- Workspaces: you can see your own.
drop policy if exists ws_self on workspaces;
create policy ws_self on workspaces
  for select using (id = current_workspace_id());

-- Members: you can see people in your workspace.
drop policy if exists members_same_ws on members;
create policy members_same_ws on members
  for select using (workspace_id = current_workspace_id());

-- Everything else: full access within your own workspace.
do $$
declare
  t    text;
  pol  text;
begin
  foreach t in array array[
    'projects','knowledge_items','sessions','rounds',
    'messages','agent_briefs','documents'
  ]
  loop
    pol := t || '_tenant';
    execute format('drop policy if exists %I on %I;', pol, t);
    execute format($f$
      create policy %I on %I
        for all
        using      (workspace_id = current_workspace_id())
        with check (workspace_id = current_workspace_id());
    $f$, pol, t);
  end loop;
end $$;

-- ============================================================
-- Done. Next: 002_seed.sql for a demo workspace (optional, dev only).
-- ============================================================
