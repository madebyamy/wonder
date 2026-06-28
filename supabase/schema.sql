-- Wander App — Supabase Schema
-- Run this in the Supabase SQL Editor (Database → SQL Editor → New query)

-- ── PROFILES (extends auth.users) ──────────────────────────────────────────
create table if not exists profiles (
  id uuid references auth.users on delete cascade primary key,
  name text not null,
  avatar_color text default 'blue',
  phone text,
  created_at timestamptz default now()
);
alter table profiles enable row level security;
create policy "Anyone can view profiles" on profiles for select using (true);
create policy "Users can insert own profile" on profiles for insert with check (auth.uid() = id);
create policy "Users can update own profile" on profiles for update using (auth.uid() = id);

-- Auto-create profile on signup
create or replace function handle_new_user()
returns trigger as $$
begin
  insert into profiles (id, name)
  values (
    new.id,
    coalesce(new.raw_user_meta_data->>'name', split_part(new.email, '@', 1))
  );
  return new;
end;
$$ language plpgsql security definer;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute procedure handle_new_user();

-- ── TRIPS ───────────────────────────────────────────────────────────────────
create table if not exists trips (
  id uuid default gen_random_uuid() primary key,
  name text not null,
  destinations text[] default '{}',
  start_date date,
  end_date date,
  color text default '#b8a4ed',
  cover_emoji text default '✈️',
  created_by uuid references auth.users on delete cascade not null,
  created_at timestamptz default now()
);
alter table trips enable row level security;
create policy "Trip members can view trips" on trips for select using (
  auth.uid() = created_by or
  exists (select 1 from trip_members where trip_id = trips.id and user_id = auth.uid())
);
create policy "Users can create trips" on trips for insert with check (auth.uid() = created_by);
create policy "Trip owners can update" on trips for update using (auth.uid() = created_by);
create policy "Trip owners can delete" on trips for delete using (auth.uid() = created_by);

-- ── TRIP MEMBERS ────────────────────────────────────────────────────────────
create table if not exists trip_members (
  id uuid default gen_random_uuid() primary key,
  trip_id uuid references trips on delete cascade not null,
  user_id uuid references auth.users on delete cascade,
  email text,
  name text,
  role text default 'member',
  status text default 'invited',
  invited_at timestamptz default now(),
  joined_at timestamptz
);
alter table trip_members enable row level security;
create policy "Trip members can view members" on trip_members for select using (
  exists (select 1 from trips where id = trip_id and created_by = auth.uid()) or
  user_id = auth.uid()
);
create policy "Trip owners can manage members" on trip_members for all using (
  exists (select 1 from trips where id = trip_id and created_by = auth.uid())
);

-- ── EXPENSES ────────────────────────────────────────────────────────────────
create table if not exists expenses (
  id uuid default gen_random_uuid() primary key,
  trip_id uuid references trips on delete cascade not null,
  title text not null,
  amount decimal(10,2) not null,
  currency text default 'USD',
  category text,
  paid_by uuid references auth.users,
  split_type text default 'even',
  status text default 'owe',
  notes text,
  created_by uuid references auth.users on delete cascade not null,
  created_at timestamptz default now()
);
alter table expenses enable row level security;
create policy "Trip members can view expenses" on expenses for select using (
  exists (
    select 1 from trips t left join trip_members tm on tm.trip_id = t.id
    where t.id = expenses.trip_id and (t.created_by = auth.uid() or tm.user_id = auth.uid())
  )
);
create policy "Members can insert expenses" on expenses for insert with check (auth.uid() = created_by);
create policy "Creators can update expenses" on expenses for update using (auth.uid() = created_by);
create policy "Creators can delete expenses" on expenses for delete using (auth.uid() = created_by);

-- ── TASKS ───────────────────────────────────────────────────────────────────
create table if not exists tasks (
  id uuid default gen_random_uuid() primary key,
  trip_id uuid references trips on delete cascade not null,
  title text not null,
  due_date date,
  done boolean default false,
  auto_generated boolean default false,
  category text default 'general',
  created_by uuid references auth.users on delete cascade not null,
  created_at timestamptz default now()
);
alter table tasks enable row level security;
create policy "Trip members can view tasks" on tasks for select using (
  exists (
    select 1 from trips t left join trip_members tm on tm.trip_id = t.id
    where t.id = tasks.trip_id and (t.created_by = auth.uid() or tm.user_id = auth.uid())
  )
);
create policy "Members can insert tasks" on tasks for insert with check (auth.uid() = created_by);
create policy "Creators can update tasks" on tasks for update using (auth.uid() = created_by);
create policy "Creators can delete tasks" on tasks for delete using (auth.uid() = created_by);

-- ── LOG ENTRIES ─────────────────────────────────────────────────────────────
create table if not exists log_entries (
  id uuid default gen_random_uuid() primary key,
  trip_id uuid references trips on delete cascade not null,
  entry_date date not null,
  title text,
  body text,
  mood text,
  created_by uuid references auth.users on delete cascade not null,
  created_at timestamptz default now(),
  updated_at timestamptz default now()
);
alter table log_entries enable row level security;
create policy "Trip members can view log entries" on log_entries for select using (
  exists (
    select 1 from trips t left join trip_members tm on tm.trip_id = t.id
    where t.id = log_entries.trip_id and (t.created_by = auth.uid() or tm.user_id = auth.uid())
  )
);
create policy "Users can insert own entries" on log_entries for insert with check (auth.uid() = created_by);
create policy "Users can update own entries" on log_entries for update using (auth.uid() = created_by);

-- ── SUITCASE ITEMS ──────────────────────────────────────────────────────────
create table if not exists suitcase_items (
  id uuid default gen_random_uuid() primary key,
  trip_id uuid references trips on delete cascade not null,
  name text not null,
  category text default 'outfit',
  time_of_day text default 'day',
  assigned_days int[] default '{}',
  shared boolean default false,
  photo_url text,
  notes text,
  created_by uuid references auth.users on delete cascade not null,
  created_at timestamptz default now()
);
alter table suitcase_items enable row level security;
create policy "Users can view own or shared items" on suitcase_items for select using (
  auth.uid() = created_by or shared = true
);
create policy "Users can manage own items" on suitcase_items for all using (auth.uid() = created_by);

-- ── PHOTOS ──────────────────────────────────────────────────────────────────
create table if not exists photos (
  id uuid default gen_random_uuid() primary key,
  trip_id uuid references trips on delete cascade not null,
  storage_path text not null,
  uploaded_by uuid references auth.users on delete cascade not null,
  day_date date,
  caption text,
  created_at timestamptz default now()
);
alter table photos enable row level security;
create policy "Trip members can view photos" on photos for select using (
  exists (
    select 1 from trips t left join trip_members tm on tm.trip_id = t.id
    where t.id = photos.trip_id and (t.created_by = auth.uid() or tm.user_id = auth.uid())
  )
);
create policy "Members can upload photos" on photos for insert with check (auth.uid() = uploaded_by);
create policy "Owners can delete photos" on photos for delete using (auth.uid() = uploaded_by);

-- ── FLIGHTS ─────────────────────────────────────────────────────────────────
create table if not exists flights (
  id uuid default gen_random_uuid() primary key,
  trip_id uuid references trips on delete cascade not null,
  flight_date date not null,
  airline text,
  flight_number text,
  departure_airport text,
  arrival_airport text,
  departure_time time,
  arrival_time time,
  arrival_date date,
  notes text,
  created_by uuid references auth.users on delete cascade not null,
  created_at timestamptz default now()
);
alter table flights enable row level security;
create policy "Trip members can view flights" on flights for select using (
  exists (select 1 from trips t left join trip_members tm on tm.trip_id = t.id
    where t.id = flights.trip_id and (t.created_by = auth.uid() or tm.user_id = auth.uid()))
);
create policy "Members can insert flights" on flights for insert with check (auth.uid() = created_by);
create policy "Creators can update flights" on flights for update using (auth.uid() = created_by);
create policy "Creators can delete flights" on flights for delete using (auth.uid() = created_by);

-- ── HOTELS ───────────────────────────────────────────────────────────────────
create table if not exists hotels (
  id uuid default gen_random_uuid() primary key,
  trip_id uuid references trips on delete cascade not null,
  hotel_name text not null,
  address text,
  checkin_date date not null,
  checkout_date date not null,
  confirmation text,
  notes text,
  created_by uuid references auth.users on delete cascade not null,
  created_at timestamptz default now()
);
alter table hotels enable row level security;
create policy "Trip members can view hotels" on hotels for select using (
  exists (select 1 from trips t left join trip_members tm on tm.trip_id = t.id
    where t.id = hotels.trip_id and (t.created_by = auth.uid() or tm.user_id = auth.uid()))
);
create policy "Members can insert hotels" on hotels for insert with check (auth.uid() = created_by);
create policy "Creators can update hotels" on hotels for update using (auth.uid() = created_by);
create policy "Creators can delete hotels" on hotels for delete using (auth.uid() = created_by);

-- ── EXCURSIONS ───────────────────────────────────────────────────────────────
create table if not exists excursions (
  id uuid default gen_random_uuid() primary key,
  trip_id uuid references trips on delete cascade not null,
  excursion_date date not null,
  title text not null,
  start_time time,
  description text,
  cost decimal(10,2),
  currency text default 'USD',
  booking_ref text,
  created_by uuid references auth.users on delete cascade not null,
  created_at timestamptz default now()
);
alter table excursions enable row level security;
create policy "Trip members can view excursions" on excursions for select using (
  exists (select 1 from trips t left join trip_members tm on tm.trip_id = t.id
    where t.id = excursions.trip_id and (t.created_by = auth.uid() or tm.user_id = auth.uid()))
);
create policy "Members can insert excursions" on excursions for insert with check (auth.uid() = created_by);
create policy "Creators can update excursions" on excursions for update using (auth.uid() = created_by);
create policy "Creators can delete excursions" on excursions for delete using (auth.uid() = created_by);

-- ── STORAGE BUCKET ──────────────────────────────────────────────────────────
-- Run this separately in Storage section, or via SQL:
insert into storage.buckets (id, name, public) values ('trip-photos', 'trip-photos', false)
on conflict do nothing;

create policy "Trip members can upload photos" on storage.objects for insert
  with check (bucket_id = 'trip-photos' and auth.role() = 'authenticated');

create policy "Trip members can view photos" on storage.objects for select
  using (bucket_id = 'trip-photos' and auth.role() = 'authenticated');

create policy "Photo owners can delete" on storage.objects for delete
  using (bucket_id = 'trip-photos' and auth.uid()::text = (storage.foldername(name))[1]);
