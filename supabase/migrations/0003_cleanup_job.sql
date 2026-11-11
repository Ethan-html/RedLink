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
