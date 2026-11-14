-- BrainForging: contact details only. Run once in Supabase -> SQL Editor. Safe to run again.
create table if not exists public.bf_leads (
  id bigint generated always as identity primary key,
  name text not null check (char_length(name) between 2 and 200),
  email text not null check (char_length(email) <= 320 and email ~* '^[^@\s]+@[^@\s]+\.[^@\s]+$'),
  phone text not null check (char_length(phone) between 6 and 40),
  source text check (char_length(source) <= 50),
  created_at timestamptz not null default now()
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
alter table public.bf_leads enable row level security;
alter table public.bf_messages enable row level security;
-- Visitors can only ADD rows. Nobody can read them through the website. View them in Table Editor.
drop policy if exists "anyone can sign up" on public.bf_leads;
create policy "anyone can sign up" on public.bf_leads for insert to anon, authenticated with check (true);
drop policy if exists "send a message" on public.bf_messages;
create policy "send a message" on public.bf_messages for insert to anon, authenticated with check (true);
grant insert on public.bf_leads, public.bf_messages to anon, authenticated;
