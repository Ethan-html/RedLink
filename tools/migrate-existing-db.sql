-- ONE-TIME CLEANUP for a database that has the old mixed schema (like the original
-- Codered test project). Run supabase/migrations/0001, 0002, 0003 FIRST, then this.
-- It removes the unused "sites" model. It does NOT touch redlinks, redlink_settings,
-- redlink_users or auth.users.
drop function if exists public.create_redlink(text, text, text, text, text, text);
drop function if exists public.set_redlink_site(text, text, text);
drop function if exists public.get_redlink_site(text);
drop function if exists public.redlink_is_admin();
drop table    if exists public.redlink_sites;
drop table    if exists public.redlink_admins;
alter table public.redlinks drop column if exists site;
