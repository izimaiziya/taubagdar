-- Тревога по контрольному времени. Работает на сервере, даже если телефон туриста сел или без связи.

-- Экстренные контакты, подключённые к Telegram-боту через ссылку t.me/<бот>?start=<token>
create table if not exists public.contact_links (
  token text primary key,
  owner uuid not null references auth.users(id) on delete cascade,
  owner_name text not null default '',
  name text not null default '',
  chat_id bigint,
  linked_at timestamptz
);
alter table public.contact_links enable row level security;
create policy "contact_links_own" on public.contact_links
  for all using (auth.uid() = owner) with check (auth.uid() = owner);

-- Активные походы
create table if not exists public.live_trips (
  id text primary key,
  owner uuid not null references auth.users(id) on delete cascade,
  owner_name text not null default '',
  owner_phone text not null default '',
  route_name text not null,
  control_at timestamptz not null,
  status text not null default 'active' check (status in ('active', 'done', 'alerted')),
  last_lat double precision,
  last_lon double precision,
  last_acc double precision,
  last_battery int,
  last_at timestamptz,
  created_at timestamptz not null default now()
);
alter table public.live_trips enable row level security;
create policy "live_trips_own" on public.live_trips
  for all using (auth.uid() = owner) with check (auth.uid() = owner);

-- Проверка каждые 5 минут. Замените <PROJECT_REF> и <CRON_SECRET> перед запуском.
create extension if not exists pg_cron;
create extension if not exists pg_net;
select cron.schedule(
  'trip-alarm',
  '*/5 * * * *',
  $$
  select net.http_post(
    url := 'https://<PROJECT_REF>.supabase.co/functions/v1/trip-alarm',
    headers := jsonb_build_object('Content-Type', 'application/json', 'x-cron-secret', '<CRON_SECRET>'),
    body := '{}'::jsonb
  );
  $$
);
