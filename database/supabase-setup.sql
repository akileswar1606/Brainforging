-- BrainForging: accounts, progress and waiting-list sign-ups. Run the WHOLE file once in Supabase -> SQL Editor. Safe to run again.

-- 1. Learner profiles (created automatically at sign-up)
create table if not exists public.bf_profiles (id uuid primary key references auth.users(id) on delete cascade);
alter table public.bf_profiles
  add column if not exists full_name text, add column if not exists email text,
  add column if not exists phone text, add column if not exists country text,
  add column if not exists xp int not null default 0, add column if not exists streak int not null default 0,
  add column if not exists last_active date, add column if not exists created_at timestamptz not null default now();

-- 2. Lesson progress
create table if not exists public.bf_progress (
  id bigint generated always as identity primary key,
  user_id uuid not null default auth.uid() references auth.users(id) on delete cascade,
  course text not null, lesson text not null, score int,
  passed boolean not null default false, updated_at timestamptz not null default now(),
  unique (user_id, course, lesson)
);

alter table public.bf_profiles enable row level security;
alter table public.bf_progress enable row level security;
drop policy if exists "read own profile" on public.bf_profiles;
drop policy if exists "update own profile" on public.bf_profiles;
drop policy if exists "read own progress" on public.bf_progress;
drop policy if exists "insert own progress" on public.bf_progress;
drop policy if exists "update own progress" on public.bf_progress;
create policy "read own profile" on public.bf_profiles for select to authenticated using (auth.uid() = id);
create policy "update own profile" on public.bf_profiles for update to authenticated using (auth.uid() = id) with check (auth.uid() = id);
create policy "read own progress" on public.bf_progress for select to authenticated using (auth.uid() = user_id);
create policy "insert own progress" on public.bf_progress for insert to authenticated with check (auth.uid() = user_id);
create policy "update own progress" on public.bf_progress for update to authenticated using (auth.uid() = user_id) with check (auth.uid() = user_id);
grant select, update on public.bf_profiles to authenticated;
grant select, insert, update on public.bf_progress to authenticated;

-- 3. Create the profile automatically when someone signs up
create or replace function public.bf_handle_new_user() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  insert into public.bf_profiles (id, full_name, email, phone, country)
  values (new.id, new.raw_user_meta_data->>'full_name', new.email, new.raw_user_meta_data->>'phone', new.raw_user_meta_data->>'country')
  on conflict (id) do nothing;
  return new;
end $$;
drop trigger if exists bf_on_auth_user_created on auth.users;
create trigger bf_on_auth_user_created after insert on auth.users
for each row execute function public.bf_handle_new_user();

-- 4. Fill in profiles for accounts that already exist
insert into public.bf_profiles (id, full_name, email, phone, country)
select id, raw_user_meta_data->>'full_name', email, raw_user_meta_data->>'phone', raw_user_meta_data->>'country' from auth.users
on conflict (id) do update set
  email = coalesce(public.bf_profiles.email, excluded.email), full_name = coalesce(public.bf_profiles.full_name, excluded.full_name),
  phone = coalesce(public.bf_profiles.phone, excluded.phone), country = coalesce(public.bf_profiles.country, excluded.country);

-- 5. Waiting-list sign-ups for coming-soon courses and the contact form (visitors can only add rows)
create table if not exists public.bf_leads (
  id bigint generated always as identity primary key,
  name text not null check (char_length(name) between 2 and 200),
  email text not null check (char_length(email) <= 320 and email ~* '^[^@\s]+@[^@\s]+\.[^@\s]+$'),
  phone text not null check (char_length(phone) between 6 and 40),
  country text check (char_length(country) <= 100),
  source text check (char_length(source) <= 50),
  created_at timestamptz not null default now()
);
-- If bf_leads already exists, this adds the new Country column:
alter table public.bf_leads add column if not exists country text check (char_length(country) <= 100);

create table if not exists public.bf_messages (
  id bigint generated always as identity primary key,
  name text not null check (char_length(name) <= 200),
  email text not null check (char_length(email) <= 320),
  phone text check (char_length(phone) <= 40),
  subject text not null check (char_length(subject) <= 300),
  message text not null check (char_length(message) <= 5000),
  created_at timestamptz not null default now()
);
alter table public.bf_leads enable row level security;
alter table public.bf_messages enable row level security;
-- Visitors can only ADD rows. Nobody can read them through the website. View them in Table Editor.
drop policy if exists "anyone can sign up" on public.bf_leads;
create policy "anyone can sign up" on public.bf_leads for insert to anon, authenticated with check (true);
drop policy if exists "send a message" on public.bf_messages;
create policy "send a message" on public.bf_messages for insert to anon, authenticated with check (true);
grant insert on public.bf_leads, public.bf_messages to anon, authenticated;
