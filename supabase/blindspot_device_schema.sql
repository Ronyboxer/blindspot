-- Blind Spot Raspberry Pi capture schema for Supabase.
-- Run this in Ronak's Supabase SQL editor or via an authenticated Supabase CLI session.

create extension if not exists pgcrypto;

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('photos', 'photos', true, 10485760, array['image/jpeg', 'image/png'])
on conflict (id) do update
set public = excluded.public,
    file_size_limit = excluded.file_size_limit,
    allowed_mime_types = excluded.allowed_mime_types;

create table if not exists public.rides (
  id uuid primary key default gen_random_uuid(),
  user_id text not null,
  device_id text not null,
  started_at timestamptz not null default now(),
  ended_at timestamptz,
  created_at timestamptz not null default now()
);

alter table public.rides
  add column if not exists user_id text,
  add column if not exists device_id text,
  add column if not exists started_at timestamptz not null default now(),
  add column if not exists ended_at timestamptz,
  add column if not exists distance_m double precision,
  add column if not exists duration_s double precision,
  add column if not exists photo_count integer,
  add column if not exists accessibility_score integer,
  add column if not exists accessibility_rating text,
  add column if not exists accessibility_summary text,
  add column if not exists accessibility_labels jsonb,
  add column if not exists accessibility_observations jsonb,
  add column if not exists accessibility_map_tags jsonb,
  add column if not exists accessibility_model text,
  add column if not exists potholes_detected boolean,
  add column if not exists pothole_count integer,
  add column if not exists road_hazards jsonb,
  add column if not exists qwen_summary jsonb,
  add column if not exists summarized_at timestamptz,
  add column if not exists created_at timestamptz not null default now();

update public.rides
set device_id = 'legacy-device'
where device_id is null or device_id = '';

update public.rides
set user_id = 'legacy-user'
where user_id is null or user_id = '';

alter table public.rides
  alter column user_id set not null,
  alter column device_id set not null;

update public.rides
set photo_count = 0
where photo_count is null;

create table if not exists public.photos (
  id uuid primary key default gen_random_uuid(),
  ride_id uuid references public.rides(id) on delete set null,
  event_id uuid,
  event_type text not null default 'manual_flag',
  storage_url text not null,
  lat double precision,
  lng double precision,
  captured_at timestamptz not null default now(),
  is_blurred boolean not null default false,
  is_processed boolean not null default false,
  created_at timestamptz not null default now()
);

alter table public.photos
  add column if not exists ride_id uuid references public.rides(id) on delete set null,
  add column if not exists event_id uuid,
  add column if not exists event_type text not null default 'manual_flag',
  add column if not exists storage_url text,
  add column if not exists lat double precision,
  add column if not exists lng double precision,
  add column if not exists captured_at timestamptz not null default now(),
  add column if not exists is_blurred boolean not null default false,
  add column if not exists is_processed boolean not null default false,
  add column if not exists created_at timestamptz not null default now();

update public.photos
set storage_url = ''
where storage_url is null;

update public.photos
set event_type = 'manual_flag'
where event_type is null or event_type = '';

alter table public.photos
  alter column event_type set not null,
  alter column storage_url set not null,
  alter column captured_at set not null,
  alter column is_blurred set not null,
  alter column is_processed set not null,
  alter column created_at set not null;

do $$
begin
  if not exists (
    select 1 from pg_constraint
    where conname = 'photos_require_ride_id'
      and conrelid = 'public.photos'::regclass
  ) then
    alter table public.photos
    add constraint photos_require_ride_id
    check (ride_id is not null)
    not valid;
  end if;
end $$;

do $$
begin
  if not exists (
    select 1 from pg_constraint
    where conname = 'photos_manual_flag_only'
      and conrelid = 'public.photos'::regclass
  ) then
    alter table public.photos
    add constraint photos_manual_flag_only
    check (event_type = 'manual_flag')
    not valid;
  end if;
end $$;

create table if not exists public.ai_summary (
  id uuid primary key default gen_random_uuid(),
  ride_id uuid not null references public.rides(id) on delete cascade,
  user_id text,
  device_id text,
  model text not null,
  summary_type text not null default 'ride',
  summary text not null,
  accessibility_score integer,
  accessibility_rating text,
  potholes_detected boolean not null default false,
  pothole_count integer,
  labels jsonb not null default '[]'::jsonb,
  observations jsonb not null default '[]'::jsonb,
  road_hazards jsonb not null default '[]'::jsonb,
  recommended_map_tags jsonb not null default '[]'::jsonb,
  distance_m double precision,
  duration_s double precision,
  photo_count integer,
  metrics jsonb not null default '{}'::jsonb,
  raw_response jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);

alter table public.ai_summary
  add column if not exists ride_id uuid references public.rides(id) on delete cascade,
  add column if not exists user_id text,
  add column if not exists device_id text,
  add column if not exists model text,
  add column if not exists summary_type text not null default 'ride',
  add column if not exists summary text,
  add column if not exists accessibility_score integer,
  add column if not exists accessibility_rating text,
  add column if not exists potholes_detected boolean not null default false,
  add column if not exists pothole_count integer,
  add column if not exists labels jsonb not null default '[]'::jsonb,
  add column if not exists observations jsonb not null default '[]'::jsonb,
  add column if not exists road_hazards jsonb not null default '[]'::jsonb,
  add column if not exists recommended_map_tags jsonb not null default '[]'::jsonb,
  add column if not exists distance_m double precision,
  add column if not exists duration_s double precision,
  add column if not exists photo_count integer,
  add column if not exists metrics jsonb not null default '{}'::jsonb,
  add column if not exists raw_response jsonb not null default '{}'::jsonb,
  add column if not exists created_at timestamptz not null default now();

update public.ai_summary
set model = 'unknown'
where model is null or model = '';

update public.ai_summary
set summary = 'No AI summary available.'
where summary is null or summary = '';

update public.ai_summary
set labels = '[]'::jsonb
where labels is null;

update public.ai_summary
set observations = '[]'::jsonb
where observations is null;

update public.ai_summary
set road_hazards = '[]'::jsonb
where road_hazards is null;

update public.ai_summary
set recommended_map_tags = '[]'::jsonb
where recommended_map_tags is null;

update public.ai_summary
set metrics = '{}'::jsonb
where metrics is null;

update public.ai_summary
set raw_response = '{}'::jsonb
where raw_response is null;

alter table public.ai_summary
  alter column ride_id set not null,
  alter column model set not null,
  alter column summary_type set not null,
  alter column summary set not null,
  alter column potholes_detected set not null,
  alter column labels set not null,
  alter column observations set not null,
  alter column road_hazards set not null,
  alter column recommended_map_tags set not null,
  alter column metrics set not null,
  alter column raw_response set not null,
  alter column created_at set not null;

do $$
begin
  if not exists (
    select 1 from pg_constraint
    where conname = 'ai_summary_accessibility_score_range'
      and conrelid = 'public.ai_summary'::regclass
  ) then
    alter table public.ai_summary
    add constraint ai_summary_accessibility_score_range
    check (accessibility_score is null or accessibility_score between 0 and 100);
  end if;
end $$;

do $$
begin
  if not exists (
    select 1 from pg_constraint
    where conname = 'ai_summary_accessibility_rating_check'
      and conrelid = 'public.ai_summary'::regclass
  ) then
    alter table public.ai_summary
    add constraint ai_summary_accessibility_rating_check
    check (accessibility_rating is null or accessibility_rating in ('good', 'fair', 'poor'));
  end if;
end $$;

do $$
begin
  if not exists (
    select 1 from pg_constraint
    where conname = 'ai_summary_pothole_count_nonnegative'
      and conrelid = 'public.ai_summary'::regclass
  ) then
    alter table public.ai_summary
    add constraint ai_summary_pothole_count_nonnegative
    check (pothole_count is null or pothole_count >= 0);
  end if;
end $$;

create index if not exists rides_device_started_idx
on public.rides (device_id, started_at desc);

create index if not exists photos_ride_captured_idx
on public.photos (ride_id, captured_at desc);

create index if not exists ai_summary_ride_created_idx
on public.ai_summary (ride_id, created_at desc);

create index if not exists ai_summary_user_created_idx
on public.ai_summary (user_id, created_at desc)
where user_id is not null;

alter table public.rides enable row level security;
alter table public.photos enable row level security;
alter table public.ai_summary enable row level security;

grant usage on schema public to anon, authenticated;
grant select, insert, update on public.rides to anon, authenticated;
grant select, insert on public.photos to anon, authenticated;
grant select, insert on public.ai_summary to anon, authenticated;

drop policy if exists "blindspot rides insert" on public.rides;
create policy "blindspot rides insert"
on public.rides for insert
to anon, authenticated
with check (
  device_id is not null and device_id <> ''
  and user_id is not null and user_id <> ''
);

drop policy if exists "blindspot rides select" on public.rides;
create policy "blindspot rides select"
on public.rides for select
to anon, authenticated
using (true);

drop policy if exists "blindspot rides update" on public.rides;
create policy "blindspot rides update"
on public.rides for update
to anon, authenticated
using (
  device_id is not null and device_id <> ''
  and user_id is not null and user_id <> ''
)
with check (
  device_id is not null and device_id <> ''
  and user_id is not null and user_id <> ''
);

drop policy if exists "blindspot photos insert" on public.photos;
create policy "blindspot photos insert"
on public.photos for insert
to anon, authenticated
with check (
  ride_id is not null
  and event_type = 'manual_flag'
  and storage_url is not null and storage_url <> ''
);

drop policy if exists "blindspot photos select" on public.photos;
create policy "blindspot photos select"
on public.photos for select
to anon, authenticated
using (true);

drop policy if exists "blindspot ai summary insert" on public.ai_summary;
create policy "blindspot ai summary insert"
on public.ai_summary for insert
to anon, authenticated
with check (
  ride_id is not null
  and model is not null and model <> ''
  and summary is not null and summary <> ''
);

drop policy if exists "blindspot ai summary select" on public.ai_summary;
create policy "blindspot ai summary select"
on public.ai_summary for select
to anon, authenticated
using (true);

drop policy if exists "blindspot storage photo upload" on storage.objects;
create policy "blindspot storage photo upload"
on storage.objects for insert
to anon, authenticated
with check (bucket_id = 'photos');

drop policy if exists "blindspot storage photo read" on storage.objects;
create policy "blindspot storage photo read"
on storage.objects for select
to anon, authenticated
using (bucket_id = 'photos');

-- Hackathon device note:
-- These permissive policies let the Pi use a publishable key for the live demo.
-- For production, route device writes through an authenticated backend or Edge
-- Function and replace these policies with per-device authorization.
