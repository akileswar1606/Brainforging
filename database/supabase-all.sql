-- BrainForging: complete Supabase setup. Every object is prefixed bf_ so it cannot clash with other tables in this project.
-- (tables, security, signup trigger, XP, streaks, leaderboard) (tables, security, signup trigger, XP, streaks, leaderboard).
-- Run the WHOLE file once in Supabase -> SQL Editor. It is safe to run again.

-- 1. Tables
create table if not exists public.bf_profiles (
  id uuid primary key references auth.users(id) on delete cascade
);
alter table public.bf_profiles
  add column if not exists full_name text,
  add column if not exists phone text,
  add column if not exists country text,
  add column if not exists education text,
  add column if not exists goals text,
  add column if not exists marketing_optin boolean not null default false,
  add column if not exists created_at timestamptz not null default now(),
  add column if not exists xp int not null default 0,
  add column if not exists streak int not null default 0,
  add column if not exists last_active date;

create table if not exists public.bf_progress (
  id bigint generated always as identity primary key,
  user_id uuid not null default auth.uid() references auth.users(id) on delete cascade,
  course text not null, lesson text not null,
  score int, passed boolean not null default false,
  updated_at timestamptz not null default now(),
  unique (user_id, course, lesson)
);

create table if not exists public.bf_messages (
  id bigint generated always as identity primary key,
  name text not null check (char_length(name) <= 200),
  email text not null check (char_length(email) <= 320),
  phone text check (char_length(phone) <= 40),
  subject text not null check (char_length(subject) <= 300),
  message text not null check (char_length(message) <= 5000),
  created_at timestamptz not null default now()
);

-- 2. Row level security
alter table public.bf_profiles enable row level security;
alter table public.bf_progress enable row level security;
alter table public.bf_messages enable row level security;

drop policy if exists "read own profile" on public.bf_profiles;
drop policy if exists "update own profile" on public.bf_profiles;
drop policy if exists "read own progress" on public.bf_progress;
drop policy if exists "send a message" on public.bf_messages;
create policy "read own profile" on public.bf_profiles for select to authenticated using (auth.uid() = id);
create policy "update own profile" on public.bf_profiles for update to authenticated using (auth.uid() = id) with check (auth.uid() = id);
create policy "read own progress" on public.bf_progress for select to authenticated using (auth.uid() = user_id);
-- Anyone can send a message; nobody can read messages through the public API (read them in the Table Editor).
create policy "send a message" on public.bf_messages for insert to anon, authenticated with check (true);

-- 3. Create a profile automatically when someone signs up
create or replace function public.bf_handle_new_user() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  insert into public.bf_profiles (id, full_name, phone, country, education, goals, marketing_optin)
  values (new.id,
    new.raw_user_meta_data->>'full_name', new.raw_user_meta_data->>'phone',
    new.raw_user_meta_data->>'country', new.raw_user_meta_data->>'education',
    new.raw_user_meta_data->>'goals',
    coalesce(new.raw_user_meta_data->>'marketing', 'false') = 'true')
  on conflict (id) do nothing;
  return new;
end $$;
drop trigger if exists bf_on_auth_user_created on auth.users;
create trigger bf_on_auth_user_created after insert on auth.users
for each row execute function public.bf_handle_new_user();

-- 4. Fill in profiles for accounts that already exist
insert into public.bf_profiles (id, full_name, phone, country, education, goals)
select id, raw_user_meta_data->>'full_name', raw_user_meta_data->>'phone',
       raw_user_meta_data->>'country', raw_user_meta_data->>'education', raw_user_meta_data->>'goals'
from auth.users
on conflict (id) do update set
  full_name = coalesce(public.bf_profiles.full_name, excluded.full_name),
  phone = coalesce(public.bf_profiles.phone, excluded.phone),
  country = coalesce(public.bf_profiles.country, excluded.country);

-- 5. XP, streaks, leaderboard
create table if not exists public.bf_xp_log (
  id bigint generated always as identity primary key,
  user_id uuid not null references auth.users(id) on delete cascade,
  amount int not null, reason text,
  created_at timestamptz not null default now()
);
alter table public.bf_xp_log enable row level security;  -- no policies: only the functions below touch it

-- Students can no longer write XP or progress directly; only the functions can.
revoke update on public.bf_profiles from authenticated, anon;
grant update (full_name, phone, country, education, goals, marketing_optin) on public.bf_profiles to authenticated;
drop policy if exists "insert own progress" on public.bf_progress;
drop policy if exists "update own progress" on public.bf_progress;

create or replace function public.bf_touch_streak() returns int
language plpgsql security definer set search_path = public as $$
declare r public.bf_profiles; s int;
begin
  select * into r from public.bf_profiles where id = auth.uid();
  if not found then return 0; end if;
  if r.last_active = current_date then return r.streak; end if;
  s := case when r.last_active = current_date - 1 then r.streak + 1 else 1 end;
  update public.bf_profiles set streak = s, last_active = current_date where id = auth.uid();
  return s;
end $$;

create or replace function public.bf_complete_lesson(p_course text, p_lesson text, p_score int) returns json
language plpgsql security definer set search_path = public as $$
declare was_done boolean; gain int := 0; s int; x int;
begin
  if auth.uid() is null then raise exception 'not signed in'; end if;
  if p_score < 0 or p_score > 5 then raise exception 'bad score'; end if;
  select passed into was_done from public.bf_progress
    where user_id = auth.uid() and course = p_course and lesson = p_lesson;
  if p_score >= 4 then
    if coalesce(was_done, false) = false then gain := 50 + 10 * p_score; end if;
    insert into public.bf_progress (user_id, course, lesson, score, passed)
      values (auth.uid(), p_course, p_lesson, p_score, true)
      on conflict (user_id, course, lesson)
      do update set score = greatest(bf_progress.score, excluded.score), passed = true, updated_at = now();
  end if;
  if gain > 0 then
    insert into public.bf_xp_log (user_id, amount, reason) values (auth.uid(), gain, p_lesson);
    update public.bf_profiles set xp = xp + gain where id = auth.uid();
  end if;
  s := public.bf_touch_streak();
  select xp into x from public.bf_profiles where id = auth.uid();
  return json_build_object('gain', gain, 'xp', x, 'streak', s);
end $$;

-- Weekly top 10. Shows first names only.
create or replace function public.bf_weekly_leaderboard() returns table (name text, xp bigint, me boolean)
language sql security definer set search_path = public as $$
  select coalesce(nullif(split_part(p.full_name, ' ', 1), ''), 'Learner'),
         sum(l.amount)::bigint, (l.user_id = auth.uid())
  from public.bf_xp_log l join public.bf_profiles p on p.id = l.user_id
  where l.created_at >= date_trunc('week', now())
  group by p.full_name, l.user_id
  order by 2 desc limit 10
$$;

revoke all on function public.bf_touch_streak() from public, anon;
revoke all on function public.bf_complete_lesson(text, text, int) from public, anon;
revoke all on function public.bf_weekly_leaderboard() from public, anon;
grant execute on function public.bf_touch_streak() to authenticated;
grant execute on function public.bf_complete_lesson(text, text, int) to authenticated;
grant execute on function public.bf_weekly_leaderboard() to authenticated;
