-- =============================================================================
-- RedLink by Codered: ONE-FILE DATABASE SETUP
-- =============================================================================
-- HOW TO USE
--   1. Scroll to "PART 4" near the bottom and edit the 3 values (who can create links).
--   2. Copy this WHOLE file into Supabase > SQL Editor and click Run.
--   3. The last result table shows the mode and approved accounts so you can check it.
--
-- Safe to run again at any time (for example to change the mode). If something in
-- PART 4 is wrong the script stops with a plain-English error and changes nothing.
-- =============================================================================


-- =============================================================================
-- PART 1 of 4: tables, settings and lock-down
-- =============================================================================
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


-- =============================================================================
-- PART 2 of 4: the only doors the website can use
-- =============================================================================
-- RedLink 0002: the only doors the website can use. Safe to run more than once.

-- ---- internal gates (never callable from the website) ----
create or replace function public._redlink_admin_gate()
returns text language plpgsql security definer set search_path to 'public' as $function$
declare
  v_mode   text;
  v_claims jsonb := coalesce(nullif(current_setting('request.jwt.claims', true), ''), '{}')::jsonb;
  v_email  text  := lower(coalesce(v_claims ->> 'email', ''));
begin
  select mode into v_mode from public.redlink_settings where id = 1;
  if v_mode is distinct from 'auth' then return 'off'; end if;
  if v_claims ->> 'role' is distinct from 'authenticated' or v_email = '' then return 'login'; end if;
  if exists (select 1 from public.redlink_users where lower(email) = v_email) then return 'ok'; end if;
  return 'denied';
end;
$function$;

create or replace function public._redlink_pin_ok(p_pin text)
returns text language plpgsql security definer set search_path to 'public' as $function$
declare
  c_ip_max  constant int      := 5;
  c_all_max constant int      := 40;
  c_window  constant interval := interval '15 minutes';
  h         jsonb := coalesce(nullif(current_setting('request.headers', true), ''), '{}')::jsonb;
  v_ip      text  := coalesce(
                       nullif(h ->> 'cf-connecting-ip', ''),
                       nullif(h ->> 'x-real-ip', ''),
                       nullif(btrim(split_part(coalesce(h ->> 'x-forwarded-for', ''), ',', 1)), ''),
                       'unknown');
  v_ip_fails  int;
  v_all_fails int;
  v_hash      text;
begin
  if p_pin is null or char_length(p_pin) > 100 then
    return 'wrong';
  end if;

  select coalesce(max(fails) filter (where ip = v_ip), 0),
         coalesce(max(fails) filter (where ip = '*'), 0)
    into v_ip_fails, v_all_fails
    from public.redlink_pin_fails
   where ip in (v_ip, '*') and since > now() - c_window;

  if v_ip_fails >= c_ip_max or v_all_fails >= c_all_max then
    return 'locked';
  end if;

  select pin_hash into v_hash from public.redlink_settings where id = 1;

  if v_hash is not null
     and v_hash = encode(sha256(convert_to('redlink-pin:' || btrim(p_pin), 'UTF8')), 'hex') then
    delete from public.redlink_pin_fails where ip = v_ip;
    return 'ok';
  end if;

  insert into public.redlink_pin_fails (ip, fails, since)
  select k, 1, now() from unnest(array[v_ip, '*']) as k
  on conflict (ip) do update set
    fails = case when public.redlink_pin_fails.since <= now() - c_window
                 then 1 else public.redlink_pin_fails.fails + 1 end,
    since = case when public.redlink_pin_fails.since <= now() - c_window
                 then now() else public.redlink_pin_fails.since end;

  if v_ip_fails + 1 >= c_ip_max or v_all_fails + 1 >= c_all_max then
    return 'locked';
  end if;
  return 'wrong';
end;
$function$;

create or replace function public._redlink_gate(p_pin text)
returns text language plpgsql security definer set search_path to 'public' as $function$
declare
  v_mode   text;
  v_claims jsonb := coalesce(nullif(current_setting('request.jwt.claims', true), ''), '{}')::jsonb;
  v_email  text  := lower(coalesce(v_claims ->> 'email', ''));
begin
  select mode into v_mode from public.redlink_settings where id = 1;
  if v_mode is null then return 'denied'; end if;
  if v_mode = 'open' then return 'ok'; end if;
  if v_mode = 'pin'  then return public._redlink_pin_ok(p_pin); end if;
  if v_claims ->> 'role' is distinct from 'authenticated' or v_email = '' then
    return 'login';
  end if;
  if exists (select 1 from public.redlink_users where lower(email) = v_email) then
    return 'ok';
  end if;
  return 'denied';
end;
$function$;

-- Deletes expired links. Called by the cron job, and by create_redlink as a fallback.
create or replace function public.redlink_purge_expired()
returns void language sql security definer set search_path to 'public' as $$
  delete from public.redlinks where created_at < now() - public.redlink_ttl();
$$;

-- ---- website functions ----
create or replace function public.get_redlink_mode()
returns text language sql stable security definer set search_path to 'public' as $function$
  select coalesce((select mode from public.redlink_settings where id = 1), 'auth');
$function$;

create or replace function public.check_redlink_access(p_pin text default null)
returns jsonb language plpgsql security definer set search_path to 'public' as $function$
begin
  return jsonb_build_object('status', public._redlink_gate(p_pin));
end;
$function$;

create or replace function public.check_redlink_name(p_id text, p_pin text default null)
returns jsonb language plpgsql security definer set search_path to 'public' as $function$
declare
  v_gate text := public._redlink_gate(p_pin);
begin
  if v_gate <> 'ok' then
    return jsonb_build_object('status', v_gate);
  end if;
  if p_id is null or p_id !~ '^[a-z0-9_-]{3,64}$' then
    return jsonb_build_object('status', 'ok', 'free', false, 'reason', 'invalid');
  end if;
  if lower(p_id) = 'admin' then
    return jsonb_build_object('status', 'ok', 'free', false, 'reason', 'reserved');
  end if;
  return jsonb_build_object('status', 'ok', 'free', not exists (
    select 1 from public.redlinks where id = p_id and created_at > now() - public.redlink_ttl()
  ));
end;
$function$;

create or replace function public.create_redlink(
  p_id text, p_encrypted_text text, p_encrypted_checksum text, p_verifier text, p_pin text default null)
returns jsonb language plpgsql security definer set search_path to 'public' as $function$
declare
  v_created timestamptz;
  v_gate    text;
begin
  v_gate := public._redlink_gate(p_pin);
  if v_gate <> 'ok' then
    return jsonb_build_object('status', v_gate);
  end if;

  if p_verifier is null or p_verifier !~ '^[0-9a-f]{64}$' then
    raise exception 'invalid verifier' using errcode = '23514';
  end if;

  -- expired rows must never block a name (also the cleanup fallback when pg_cron is unavailable)
  perform public.redlink_purge_expired();

  if lower(p_id) = 'admin' then
    raise exception 'that link name is reserved' using errcode = '23514';
  end if;

  insert into public.redlinks (id, encrypted_text, encrypted_checksum, verifier)
  values (p_id, p_encrypted_text, p_encrypted_checksum, p_verifier)
  returning created_at into v_created;

  return jsonb_build_object('status', 'ok', 'created_at', v_created);
end;
$function$;

create or replace function public.get_redlink_meta(p_id text)
returns text language sql stable security definer set search_path to 'public' as $function$
  select encrypted_checksum from public.redlinks
   where id = p_id and verifier is not null and created_at > now() - public.redlink_ttl();
$function$;

create or replace function public.claim_redlink(p_id text, p_proof text)
returns jsonb language plpgsql security definer set search_path to 'public' as $function$
declare
  c_max constant int := public.redlink_max_tries();
  r public.redlinks%rowtype;
begin
  select * into r from public.redlinks
   where id = p_id and verifier is not null and created_at > now() - public.redlink_ttl()
   for update;

  if not found then
    return jsonb_build_object('status', 'gone');
  end if;

  if p_proof is not null and length(p_proof) <= 200
     and r.verifier = encode(sha256(convert_to(p_proof, 'UTF8')), 'hex') then
    delete from public.redlinks where id = p_id;
    return jsonb_build_object('status', 'ok',
      'encrypted_text', r.encrypted_text, 'encrypted_checksum', r.encrypted_checksum);
  end if;

  if r.attempts + 1 >= c_max then
    delete from public.redlinks where id = p_id;
    return jsonb_build_object('status', 'locked');
  end if;

  update public.redlinks set attempts = attempts + 1 where id = p_id;
  return jsonb_build_object('status', 'wrong', 'left', c_max - (r.attempts + 1));
end;
$function$;

create or replace function public.admin_list_redlinks()
returns jsonb language plpgsql security definer set search_path to 'public' as $function$
declare
  v_gate text := public._redlink_admin_gate();
begin
  if v_gate <> 'ok' then
    return jsonb_build_object('status', v_gate);
  end if;
  return jsonb_build_object(
    'status', 'ok',
    'max_attempts', public.redlink_max_tries(),
    'links', coalesce((
      select jsonb_agg(jsonb_build_object(
               'id', id,
               'created_at', created_at,
               'expires_at', created_at + public.redlink_ttl(),
               'attempts', attempts
             ) order by created_at desc)
        from public.redlinks
       where created_at > now() - public.redlink_ttl()
    ), '[]'::jsonb));
end;
$function$;

create or replace function public.admin_burn_redlink(p_id text)
returns jsonb language plpgsql security definer set search_path to 'public' as $function$
declare
  v_gate text := public._redlink_admin_gate();
  v_n    int;
begin
  if v_gate <> 'ok' then
    return jsonb_build_object('status', v_gate);
  end if;
  delete from public.redlinks where id = p_id;
  get diagnostics v_n = row_count;
  return jsonb_build_object('status', case when v_n > 0 then 'ok' else 'gone' end);
end;
$function$;

-- ---- OWNER TOOL: set the create mode (SQL editor / installer only) ----
create or replace function public.redlink_mode(p_mode text, p_pin text default null)
returns text language plpgsql security definer set search_path to 'public' as $function$
declare
  v_mode  text := lower(btrim(coalesce(p_mode, '')));
  v_users int;
begin
  if v_mode not in ('open', 'pin', 'auth') then
    raise exception 'mode must be open, pin or auth';
  end if;

  if v_mode = 'pin' then
    if p_pin is null or char_length(btrim(p_pin)) < 4 then
      raise exception 'pin mode needs a PIN of at least 4 characters';
    end if;
    update public.redlink_settings
       set mode = 'pin',
           pin_hash = encode(sha256(convert_to('redlink-pin:' || btrim(p_pin), 'UTF8')), 'hex')
     where id = 1;
  else
    update public.redlink_settings set mode = v_mode, pin_hash = null where id = 1;
  end if;

  delete from public.redlink_pin_fails;

  if v_mode = 'auth' then
    select count(*) into v_users from public.redlink_users;
    if v_users = 0 then
      return 'Create mode is now: auth. WARNING: redlink_users is empty, so nobody can create yet.';
    end if;
  end if;
  return 'Create mode is now: ' || v_mode;
end;
$function$;

-- ---- who may call what ----
-- Supabase grants new functions to anon/authenticated by default, so revoke explicitly first.
revoke all on function
  public._redlink_admin_gate(), public._redlink_pin_ok(text), public._redlink_gate(text),
  public.redlink_purge_expired(), public.redlink_mode(text, text),
  public.get_redlink_mode(), public.check_redlink_access(text), public.check_redlink_name(text, text),
  public.create_redlink(text, text, text, text, text), public.get_redlink_meta(text),
  public.claim_redlink(text, text), public.admin_list_redlinks(), public.admin_burn_redlink(text)
  from public, anon, authenticated;

grant execute on function public.get_redlink_mode()                                  to anon, authenticated;
grant execute on function public.check_redlink_access(text)                          to anon, authenticated;
grant execute on function public.check_redlink_name(text, text)                      to anon, authenticated;
grant execute on function public.create_redlink(text, text, text, text, text)        to anon, authenticated;
grant execute on function public.get_redlink_meta(text)                              to anon, authenticated;
grant execute on function public.claim_redlink(text, text)                           to anon, authenticated;
grant execute on function public.admin_list_redlinks()                               to authenticated;
grant execute on function public.admin_burn_redlink(text)                            to authenticated;


-- =============================================================================
-- PART 3 of 4: expiry cleanup every 15 minutes
-- =============================================================================
-- RedLink 0003: expiry cleanup every 15 minutes.
-- If pg_cron is unavailable this does NOT fail: expired links are already invisible to every
-- function, and create_redlink purges them each time someone creates a link.
do $$
begin
  begin
    create extension if not exists pg_cron with schema pg_catalog;
  exception when others then
    raise notice 'pg_cron unavailable (%). Using purge-on-create fallback.', sqlerrm;
    return;
  end;

  if exists (select 1 from cron.job where jobname = 'redlink-purge') then
    perform cron.unschedule('redlink-purge');
  end if;
  if exists (select 1 from cron.job where jobname = 'redlink-purge-7d') then
    perform cron.unschedule('redlink-purge-7d');
  end if;
  perform cron.schedule('redlink-purge', '*/15 * * * *', 'select public.redlink_purge_expired()');
end $$;


-- =============================================================================
-- PART 4 of 4: CHOOSE WHO CAN CREATE LINKS   <<< EDIT THE 3 VALUES BELOW >>>
-- =============================================================================
-- Opening a link is always possible with its passkey. This only controls who can CREATE.
--
--   v_mode = 'open'   Anyone can create. Leave v_pin and v_admins empty.
--   v_mode = 'pin'    People must enter a PIN first. Fill in v_pin (4+ characters).
--   v_mode = 'auth'   Only approved accounts can sign in and create (best for private use).
--                     Fill in v_admins with your email. Several emails: separate with commas.
--
-- Auth mode also needs the account itself in Supabase (the README shows the 4 clicks):
--   Authentication > Users > Add user > Create new user (email + password, Auto Confirm ON).
--   Use the SAME email you put in v_admins. Accounts listed here can also use /admin.
--
-- Note: a PIN typed here is kept in your SQL Editor history. Prefer a PIN you won't reuse.
-- Re-running only ADDS emails. To remove one later:
--   delete from public.redlink_users where email = 'someone@example.com';
do $setup$
declare
  v_mode   text := 'auth';     -- <<< 'open', 'pin' or 'auth'
  v_pin    text := '';         -- <<< only for 'pin'
  v_admins text := '';         -- <<< only for 'auth', e.g. 'you@example.com'
  v_email  text;
  v_list   text[];
begin
  v_mode := lower(btrim(coalesce(v_mode, '')));
  if v_mode not in ('open', 'pin', 'auth') then
    raise exception 'v_mode must be exactly open, pin or auth (you wrote: %)', v_mode;
  end if;

  if v_mode = 'pin' and char_length(btrim(coalesce(v_pin, ''))) < 4 then
    raise exception 'PIN mode: put a PIN of at least 4 characters in v_pin.';
  end if;

  if v_mode = 'auth' then
    v_list := array(select lower(btrim(e)) from unnest(string_to_array(coalesce(v_admins, ''), ',')) e
                    where btrim(e) <> '');
    if coalesce(array_length(v_list, 1), 0) = 0 then
      raise exception 'AUTH mode: put your email in v_admins (for example ''you@example.com'').';
    end if;
    foreach v_email in array v_list loop
      if v_email !~ '^[^@\s]+@[^@\s]+\.[^@\s]+$' then
        raise exception 'AUTH mode: "%" does not look like an email address.', v_email;
      end if;
      insert into public.redlink_users (email) values (v_email) on conflict do nothing;
    end loop;
  end if;

  perform public.redlink_mode(v_mode, nullif(btrim(v_pin), ''));
end
$setup$;

-- Check: this is what you should see when it worked.
select public.get_redlink_mode()                                         as create_mode,
       (select count(*) from public.redlink_users)                       as approved_accounts,
       coalesce((select string_agg(email, ', ' order by email)
                   from public.redlink_users), '(none)')                 as approved_emails,
       case public.get_redlink_mode()
         when 'open' then 'Anyone can create links.'
         when 'pin'  then 'Creating links needs the PIN.'
         else 'Only approved accounts can create. Now create the same user in Authentication > Users.'
       end                                                               as what_this_means;


-- =============================================================================
-- OPTIONAL: only for an OLD database that still has the unused "sites" model.
-- New projects can ignore this. To use it, remove the /* and */ lines, then run again.
-- It does NOT touch redlinks, redlink_settings, redlink_users or auth.users.
-- =============================================================================
/*
drop function if exists public.create_redlink(text, text, text, text, text, text);
drop function if exists public.set_redlink_site(text, text, text);
drop function if exists public.get_redlink_site(text);
drop function if exists public.redlink_is_admin();
drop table    if exists public.redlink_sites;
drop table    if exists public.redlink_admins;
alter table public.redlinks drop column if exists site;
*/
