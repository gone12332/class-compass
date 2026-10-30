-- Class Compass: anonymous stats, online count and bans.
-- Run once in Supabase: SQL Editor > New query > paste all of this > Run.
-- Safe to run again; it only adds what is missing and replaces the functions.
--
-- Privacy: each phone sends a random ID it made up itself. No names, no GPS, no class names.
-- Phones can only call cc_track(). They cannot read or change any table.
-- Only the admin login can call the cc_admin_* functions.

create table if not exists public.cc_devices (
  id         text primary key check (id ~ '^[a-f0-9]{16,64}$'),
  first_seen timestamptz not null default now(),
  last_seen  timestamptz not null default now(),
  platform   text check (platform is null or char_length(platform) <= 20),
  visits     integer not null default 0,
  last_src   text,
  banned     boolean not null default false,
  ban_note   text check (ban_note is null or char_length(ban_note) <= 120)
);

create table if not exists public.cc_events (
  id         bigint generated always as identity primary key,
  device_id  text not null references public.cc_devices(id) on delete cascade,
  kind       text not null check (kind in ('open', 'scan', 'trip', 'arrive')),
  src        text check (src is null or src ~ '^[a-z0-9-]{1,40}$'),
  created_at timestamptz not null default now()
);

create index if not exists cc_events_created_idx on public.cc_events (created_at);
create index if not exists cc_events_kind_idx on public.cc_events (kind, created_at);
create index if not exists cc_events_device_idx on public.cc_events (device_id, created_at);
create index if not exists cc_devices_seen_idx on public.cc_devices (last_seen);

-- Lock the tables. Everything goes through the functions below.
alter table public.cc_devices enable row level security;
alter table public.cc_events enable row level security;
revoke all on public.cc_devices, public.cc_events from anon, authenticated;

-- Who counts as the admin: the Supabase user whose email is below.
-- The /admin page turns the username "root" into root@example.com.
create or replace function public.cc_is_admin() returns boolean
language sql stable as $$
  select coalesce(auth.jwt() ->> 'email', '') = 'root@example.com'
$$;

-- Called by the app. kind: 'ping' (still here), 'open', 'scan' (opened from a poster), 'trip', 'arrive'.
-- Returns whether this phone is banned.
create or replace function public.cc_track(p_device text, p_kind text, p_src text default null, p_platform text default null)
returns json
language plpgsql security definer set search_path = public as $$
declare
  d public.cc_devices;
  src text := nullif(lower(regexp_replace(coalesce(p_src, ''), '[^a-zA-Z0-9-]', '', 'g')), '');
begin
  if p_device !~ '^[a-f0-9]{16,64}$' or p_kind not in ('ping', 'open', 'scan', 'trip', 'arrive') then
    return json_build_object('ok', false);
  end if;
  src := left(src, 40);

  insert into public.cc_devices as t (id, platform, visits, last_src)
  values (p_device, left(p_platform, 20), case when p_kind in ('open', 'scan') then 1 else 0 end, case when p_kind = 'scan' then src end)
  on conflict (id) do update set
    last_seen = now(),
    platform  = coalesce(left(excluded.platform, 20), t.platform),
    visits    = t.visits + case when p_kind in ('open', 'scan') then 1 else 0 end,
    last_src  = coalesce(excluded.last_src, t.last_src)
  returning * into d;

  -- Store real events, but at most one of each kind per phone every 10 seconds.
  if p_kind <> 'ping' and not exists (
    select 1 from public.cc_events e
    where e.device_id = p_device and e.kind = p_kind and e.created_at > now() - interval '10 seconds'
  ) then
    insert into public.cc_events (device_id, kind, src)
    values (p_device, p_kind, case when p_kind = 'scan' then src end);
  end if;

  return json_build_object('ok', true, 'banned', d.banned, 'note', case when d.banned then d.ban_note end);
end $$;

-- Admin: all the numbers for the dashboard. p_tz is the admin's time zone, like 'America/New_York'.
create or replace function public.cc_admin_stats(p_tz text default 'UTC')
returns json
language plpgsql security definer set search_path = public as $$
declare
  tz text := case when exists (select 1 from pg_timezone_names where name = p_tz) then p_tz else 'UTC' end;
  today timestamptz := date_trunc('day', now() at time zone tz) at time zone tz;
  result json;
begin
  if not public.cc_is_admin() then raise exception 'not allowed' using errcode = '42501'; end if;
  select json_build_object(
    'online_now',     (select count(*) from cc_devices where last_seen > now() - interval '2 minutes'),
    'phones_total',   (select count(*) from cc_devices),
    'phones_new_today', (select count(*) from cc_devices where first_seen >= today),
    'phones_today',   (select count(*) from cc_devices where last_seen >= today),
    'banned_total',   (select count(*) from cc_devices where banned),
    'scans_total',    (select count(*) from cc_events where kind = 'scan'),
    'scans_today',    (select count(*) from cc_events where kind = 'scan' and created_at >= today),
    'opens_total',    (select count(*) from cc_events where kind in ('open', 'scan')),
    'opens_today',    (select count(*) from cc_events where kind in ('open', 'scan') and created_at >= today),
    'trips_total',    (select count(*) from cc_events where kind = 'trip'),
    'trips_today',    (select count(*) from cc_events where kind = 'trip' and created_at >= today),
    'arrivals_total', (select count(*) from cc_events where kind = 'arrive'),
    'arrivals_today', (select count(*) from cc_events where kind = 'arrive' and created_at >= today),
    'posters', coalesce((
      select json_agg(p order by p.scans desc) from (
        select src, count(*) as scans, count(distinct device_id) as phones, max(created_at) as last_scan
        from cc_events where kind = 'scan' and src is not null group by src
      ) p), '[]'::json),
    'days', (
      select json_agg(x order by x.day) from (
        select g.day::date as day,
          (select count(*) from cc_events e where e.kind = 'scan' and e.created_at >= g.day at time zone tz and e.created_at < (g.day + interval '1 day') at time zone tz) as scans,
          (select count(*) from cc_events e where e.kind in ('open', 'scan') and e.created_at >= g.day at time zone tz and e.created_at < (g.day + interval '1 day') at time zone tz) as opens,
          (select count(*) from cc_events e where e.kind = 'arrive' and e.created_at >= g.day at time zone tz and e.created_at < (g.day + interval '1 day') at time zone tz) as arrivals
        from generate_series((now() at time zone tz)::date - 13, (now() at time zone tz)::date, interval '1 day') as g(day)
      ) x),
    'server_time', now()
  ) into result;
  return result;
end $$;

-- Admin: list phones. p_filter: 'all', 'online' or 'banned'.
create or replace function public.cc_admin_devices(p_filter text default 'all', p_limit integer default 300)
returns json
language plpgsql security definer set search_path = public as $$
begin
  if not public.cc_is_admin() then raise exception 'not allowed' using errcode = '42501'; end if;
  return coalesce((
    select json_agg(r) from (
      select d.id, d.first_seen, d.last_seen, d.platform, d.visits, d.last_src, d.banned, d.ban_note,
             d.last_seen > now() - interval '2 minutes' as online,
             (select count(*) from cc_events e where e.device_id = d.id and e.kind = 'arrive') as arrivals
      from cc_devices d
      where p_filter = 'all'
         or (p_filter = 'online' and d.last_seen > now() - interval '2 minutes')
         or (p_filter = 'banned' and d.banned)
      order by d.last_seen desc
      limit least(greatest(p_limit, 1), 1000)
    ) r), '[]'::json);
end $$;

-- Admin: ban or unban one phone.
create or replace function public.cc_admin_ban(p_device text, p_banned boolean, p_note text default null)
returns json
language plpgsql security definer set search_path = public as $$
declare n integer;
begin
  if not public.cc_is_admin() then raise exception 'not allowed' using errcode = '42501'; end if;
  update cc_devices set banned = p_banned, ban_note = case when p_banned then left(nullif(p_note, ''), 120) end
  where id = p_device;
  get diagnostics n = row_count;
  return json_build_object('ok', n = 1);
end $$;

revoke all on function public.cc_track(text, text, text, text) from public;
revoke all on function public.cc_admin_stats(text) from public;
revoke all on function public.cc_admin_devices(text, integer) from public;
revoke all on function public.cc_admin_ban(text, boolean, text) from public;
-- Supabase gives anon access to new functions by default, so take it back from the admin ones.
revoke all on function public.cc_admin_stats(text) from anon;
revoke all on function public.cc_admin_devices(text, integer) from anon;
revoke all on function public.cc_admin_ban(text, boolean, text) from anon;
grant execute on function public.cc_track(text, text, text, text) to anon, authenticated;
grant execute on function public.cc_admin_stats(text) to authenticated;
grant execute on function public.cc_admin_devices(text, integer) to authenticated;
grant execute on function public.cc_admin_ban(text, boolean, text) to authenticated;
