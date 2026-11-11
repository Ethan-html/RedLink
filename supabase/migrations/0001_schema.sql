-- RedLink 0001: tables, settings, lock-down. Safe to run more than once.

create or replace function public.redlink_max_tries()
returns int language sql immutable as $$ select 5 $$;

create or replace function public.redlink_ttl()
returns interval language sql immutable as $$ select interval '7 days' $$;

create table if not exists public.redlinks (
  id                 text primary key check (id ~ '^[a-z0-9_-]{3,64}$'),
  encrypted_text     text not null check (char_length(encrypted_text) between 1 and 200000),
  encrypted_checksum text not null check (char_length(encrypted_checksum) between 1 and 200),
  created_at         timestamptz not null default now(),
  verifier           text check (verifier ~ '^[0-9a-f]{64}$'),
  attempts           int  not null default 0
);
create index if not exists redlinks_created_at_idx on public.redlinks (created_at);

-- One row (id = 1): who may CREATE links. Opening a link is always passkey-only.
-- Default is 'auth' (fail closed) until the installer picks a mode.
create table if not exists public.redlink_settings (
  id       int primary key check (id = 1),
  mode     text not null default 'auth' check (mode in ('open', 'pin', 'auth')),
  pin_hash text
);
insert into public.redlink_settings (id, mode) values (1, 'auth') on conflict (id) do nothing;

-- Approved accounts for auth mode and the Manage links page (stored lowercase).
create table if not exists public.redlink_users (
  email text primary key check (email = lower(email))
);

-- PIN brute-force counters: one row per caller IP, plus '*' for all callers.
create table if not exists public.redlink_pin_fails (
  ip    text primary key,
  fails int not null default 0,
  since timestamptz not null default now()
);

alter table public.redlinks         enable row level security;
alter table public.redlink_settings enable row level security;
alter table public.redlink_users    enable row level security;
alter table public.redlink_pin_fails enable row level security;
revoke all on public.redlinks, public.redlink_settings, public.redlink_users, public.redlink_pin_fails
  from anon, authenticated;
