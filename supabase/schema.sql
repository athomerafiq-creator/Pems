-- =====================================================================
-- PEMS — Personal Executive Management System
-- Complete database: tables, row-level security, storage, realtime.
--
-- HOW TO USE: Supabase dashboard → SQL Editor → New query →
-- paste this whole file → Run. Safe to run once on a new project.
--
-- Security model (enforced by the database, not by the screen):
--   * The Principal sees and changes everything.
--   * Assistants see only the modules and workspaces the Principal grants.
--   * Records marked PERSONAL are never visible to assistants.
--   * Finance entries by assistants are always "Pending" until approved.
--   * Assistants cannot archive/delete records or approve their own work.
--   * Check-in / check-out times are stamped by the server clock.
--   * Turning an account off (profiles.active = false) blocks it at once.
-- =====================================================================

-- ---------- 0. Configuration -----------------------------------------
-- The Principal's login email. Whoever signs up with it becomes Principal.
create or replace function public.pems_principal_email() returns text
language sql immutable as $$ select 'athomerafiq@gmail.com'::text $$;

create extension if not exists pgcrypto;

-- ---------- 1. People, workspaces, permissions -----------------------
create table if not exists public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  email text not null,
  name text not null default '',
  title text not null default '',
  role text not null default 'assistant' check (role in ('principal','assistant')),
  active boolean not null default true,
  color text not null default '#0e7490',
  created_at timestamptz not null default now()
);

create table if not exists public.workspaces (
  id uuid primary key default gen_random_uuid(),
  name text not null unique,
  color text not null default '#2f6bff',
  created_at timestamptz not null default now()
);

create table if not exists public.permissions (
  user_id uuid not null references public.profiles(id) on delete cascade,
  module text not null check (module in ('dashboard','calendar','tasks','contacts','documents','portfolio','finance','payroll','meetings','chat','attendance','warnings','travel','reports')),
  level text not null check (level in ('none','view','entry','edit')),
  primary key (user_id, module)
);

create table if not exists public.workspace_access (
  user_id uuid not null references public.profiles(id) on delete cascade,
  workspace text not null references public.workspaces(name) on update cascade on delete cascade,
  primary key (user_id, workspace)
);

create table if not exists public.app_settings (
  id int primary key default 1 check (id = 1),
  data jsonb not null default '{}'::jsonb
);

-- ---------- 2. Permission helpers (run with owner rights) ------------
create or replace function public.is_active_user() returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from profiles where id = auth.uid() and active)
$$;

create or replace function public.is_principal() returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from profiles where id = auth.uid() and active and role = 'principal')
$$;

create or replace function public.perm(m text) returns text
language sql stable security definer set search_path = public as $$
  select case
    when not exists (select 1 from profiles where id = auth.uid() and active) then 'none'
    when exists (select 1 from profiles where id = auth.uid() and role = 'principal') then 'edit'
    else coalesce((select level from permissions where user_id = auth.uid() and module = m), 'none')
  end
$$;

create or replace function public.can_view(m text) returns boolean
language sql stable as $$ select public.perm(m) in ('view','entry','edit') $$;

create or replace function public.can_edit(m text) returns boolean
language sql stable as $$ select public.perm(m) = 'edit' $$;

create or replace function public.ws_ok(w text) returns boolean
language sql stable security definer set search_path = public as $$
  select public.is_principal()
      or exists (select 1 from workspace_access where user_id = auth.uid() and workspace = w)
$$;

-- may the current user read a record of module m in workspace w with scope s?
create or replace function public.rec_ok(m text, w text, s text) returns boolean
language sql stable as $$
  select public.can_view(m)
     and (public.is_principal() or (coalesce(s,'BUSINESS') <> 'PERSONAL' and public.ws_ok(w)))
$$;

create or replace function public.rec_write(m text, w text, s text) returns boolean
language sql stable as $$
  select public.can_edit(m)
     and (public.is_principal() or (coalesce(s,'BUSINESS') <> 'PERSONAL' and public.ws_ok(w)))
$$;

create or replace function public.local_now() returns timestamp
language sql stable security definer set search_path = public as $$
  select now() at time zone coalesce((select data->>'tz' from app_settings where id = 1), 'Asia/Dhaka')
$$;

-- ---------- 3. Business records --------------------------------------
create table if not exists public.appointments (
  id uuid primary key default gen_random_uuid(),
  title text not null, date date not null default current_date,
  start_time text, end_time text, location text, attendees text, notes text,
  ws text references public.workspaces(name) on update cascade,
  scope text not null default 'BUSINESS' check (scope in ('BUSINESS','SHARED','PERSONAL')),
  gcal boolean not null default true,
  archived boolean not null default false,
  created_by uuid default auth.uid() references public.profiles(id),
  created_at timestamptz not null default now()
);

create table if not exists public.tasks (
  id uuid primary key default gen_random_uuid(),
  title text not null, description text,
  priority text not null default 'Medium' check (priority in ('High','Medium','Low')),
  due date, status text not null default 'Not Started' check (status in ('Not Started','In Progress','Waiting','Review','Completed')),
  assignee uuid references public.profiles(id),
  ws text references public.workspaces(name) on update cascade,
  scope text not null default 'BUSINESS' check (scope in ('BUSINESS','SHARED','PERSONAL')),
  archived boolean not null default false,
  created_by uuid default auth.uid() references public.profiles(id),
  created_at timestamptz not null default now()
);

create table if not exists public.contacts (
  id uuid primary key default gen_random_uuid(),
  name text not null, company text, reference text, whatsapp text, email text,
  role text, category text, phone text, last_contact date, next_followup date, notes text,
  ws text references public.workspaces(name) on update cascade,
  scope text not null default 'BUSINESS' check (scope in ('BUSINESS','SHARED','PERSONAL')),
  archived boolean not null default false,
  created_by uuid default auth.uid() references public.profiles(id),
  created_at timestamptz not null default now()
);

create table if not exists public.documents (
  id uuid primary key default gen_random_uuid(),
  title text not null, category text, confidentiality text default 'Normal',
  expiry date, file_name text, file_size text, storage_key text unique, version int not null default 1,
  ws text references public.workspaces(name) on update cascade,
  scope text not null default 'BUSINESS' check (scope in ('BUSINESS','SHARED','PERSONAL')),
  archived boolean not null default false,
  created_by uuid default auth.uid() references public.profiles(id),
  created_at timestamptz not null default now()
);

create table if not exists public.meetings (
  id uuid primary key default gen_random_uuid(),
  title text not null, date date not null default current_date, participants text,
  follow_up date, agenda text, notes text, decisions text, actions text,
  ws text references public.workspaces(name) on update cascade,
  scope text not null default 'BUSINESS' check (scope in ('BUSINESS','SHARED','PERSONAL')),
  gcal boolean not null default true,
  archived boolean not null default false,
  created_by uuid default auth.uid() references public.profiles(id),
  created_at timestamptz not null default now()
);

create table if not exists public.travel (
  id uuid primary key default gen_random_uuid(),
  destination text not null, purpose text, date_from date, date_to date, booking text,
  status text not null default 'Planned', checklist text,
  ws text references public.workspaces(name) on update cascade,
  scope text not null default 'BUSINESS' check (scope in ('BUSINESS','SHARED','PERSONAL')),
  archived boolean not null default false,
  created_by uuid default auth.uid() references public.profiles(id),
  created_at timestamptz not null default now()
);

create table if not exists public.transactions (
  id uuid primary key default gen_random_uuid(),
  date date not null default current_date,
  type text not null check (type in ('Income','Expense')),
  category text not null, amount numeric(14,2) not null check (amount > 0),
  currency text not null default 'BDT' check (currency in ('BDT','USD')),
  ws text references public.workspaces(name) on update cascade, note text,
  status text not null default 'Pending' check (status in ('Pending','Approved','Rejected')),
  archived boolean not null default false,
  created_by uuid default auth.uid() references public.profiles(id),
  created_at timestamptz not null default now()
);

create table if not exists public.staff (
  id uuid primary key default gen_random_uuid(),
  name text not null, role text, salary numeric(14,2) not null default 0,
  currency text not null default 'BDT' check (currency in ('BDT','USD')),
  email text, phone text, joined date,
  user_id uuid references public.profiles(id) on delete set null,
  archived boolean not null default false,
  created_by uuid default auth.uid() references public.profiles(id),
  created_at timestamptz not null default now()
);

create table if not exists public.payroll_adjustments (
  id uuid primary key default gen_random_uuid(),
  staff_id uuid not null references public.staff(id) on delete cascade,
  month text not null check (month ~ '^\d{4}-\d{2}$'),
  type text not null check (type in ('Incentive','Bonus','Commission','Overtime','Deduction','Advance')),
  amount numeric(14,2) not null check (amount > 0),
  currency text not null default 'BDT' check (currency in ('BDT','USD')),
  note text,
  archived boolean not null default false,
  created_by uuid default auth.uid() references public.profiles(id),
  created_at timestamptz not null default now()
);

create table if not exists public.attendance (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null default auth.uid() references public.profiles(id) on delete cascade,
  date date not null, check_in text not null, check_out text,
  archived boolean not null default false,
  created_by uuid default auth.uid() references public.profiles(id),
  created_at timestamptz not null default now()
);

create table if not exists public.warnings (
  id uuid primary key default gen_random_uuid(),
  staff_id uuid not null references public.staff(id) on delete cascade,
  grade text not null check (grade in ('Grade 1','Grade 2','Grade 3')),
  action text, date date not null default current_date, reason text not null, details text,
  acknowledged date,
  archived boolean not null default false,
  created_by uuid default auth.uid() references public.profiles(id),
  created_at timestamptz not null default now()
);

create table if not exists public.chat_messages (
  id uuid primary key default gen_random_uuid(),
  channel text not null, from_user uuid not null default auth.uid() references public.profiles(id),
  body text not null default '', file_key text, file_name text,
  created_at timestamptz not null default now()
);

create table if not exists public.chat_seen (
  user_id uuid not null default auth.uid() references public.profiles(id) on delete cascade,
  channel text not null, seen_at timestamptz not null default now(),
  primary key (user_id, channel)
);

create table if not exists public.focus_items (
  id uuid primary key default gen_random_uuid(),
  text text not null, done boolean not null default false,
  created_at timestamptz not null default now()
);

create table if not exists public.audit_log (
  id bigserial primary key,
  at timestamptz not null default now(),
  actor uuid not null default auth.uid(),
  action text not null, detail text
);

create table if not exists public.email_outbox (
  id uuid primary key default gen_random_uuid(),
  created_at timestamptz not null default now(),
  to_email text not null, subject text not null, body text, kind text,
  sent_at timestamptz, error text
);

create table if not exists public.report_runs (
  id uuid primary key default gen_random_uuid(),
  week_from date not null unique, week_to date not null, generated date not null default current_date
);

create table if not exists public.payroll_runs (
  id uuid primary key default gen_random_uuid(),
  month text not null unique, generated date not null default current_date
);

-- ---------- 4. Guard triggers ----------------------------------------
-- created_by cannot be changed; only the Principal can archive/restore.
create or replace function public.guard_record() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if tg_op = 'INSERT' then
    if not public.is_principal() then new.created_by := auth.uid(); new.archived := false; end if;
    return new;
  end if;
  new.created_by := old.created_by;
  if new.archived is distinct from old.archived and not public.is_principal() then
    raise exception 'Only the Principal can archive or restore records';
  end if;
  return new;
end $$;

do $$ declare t text; begin
  foreach t in array array['appointments','tasks','contacts','documents','meetings','travel','transactions','staff','payroll_adjustments','attendance','warnings'] loop
    execute format('drop trigger if exists guard_%1$s on public.%1$s', t);
    execute format('create trigger guard_%1$s before insert or update on public.%1$s for each row execute function public.guard_record()', t);
  end loop;
end $$;

-- Tasks: only the Principal approves an item that is waiting for review.
create or replace function public.guard_task() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if tg_op = 'UPDATE' and old.status = 'Review' and new.status = 'Completed' and not public.is_principal() then
    raise exception 'Only the Principal can approve a task under review';
  end if;
  return new;
end $$;
drop trigger if exists guard_task_status on public.tasks;
create trigger guard_task_status before update on public.tasks for each row execute function public.guard_task();

-- Finance: assistant entries are always Pending; only the Principal approves.
create or replace function public.guard_transaction() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if not public.is_principal() then
    if tg_op = 'INSERT' then new.status := 'Pending';
    elsif new.status <> 'Pending' then raise exception 'Only the Principal can approve or reject';
    end if;
  end if;
  return new;
end $$;
drop trigger if exists guard_tx on public.transactions;
create trigger guard_tx before insert or update on public.transactions for each row execute function public.guard_transaction();

-- Attendance: people without attendance edit rights get server-clock times.
create or replace function public.guard_attendance() returns trigger
language plpgsql security definer set search_path = public as $$
declare n timestamp := public.local_now();
begin
  if public.can_edit('attendance') then return new; end if;
  if tg_op = 'INSERT' then
    new.user_id := auth.uid(); new.date := n::date; new.check_in := to_char(n, 'HH24:MI'); new.check_out := null;
    if exists (select 1 from attendance where user_id = auth.uid() and check_out is null and not archived) then
      raise exception 'You are already checked in';
    end if;
  else
    if old.check_out is not null then raise exception 'This entry is closed'; end if;
    new.user_id := old.user_id; new.date := old.date; new.check_in := old.check_in;
    new.check_out := case when n::date > old.date then '23:59' else to_char(n, 'HH24:MI') end;
  end if;
  return new;
end $$;
drop trigger if exists guard_att on public.attendance;
create trigger guard_att before insert or update on public.attendance for each row execute function public.guard_attendance();

-- An assistant acknowledges a warning issued to them.
create or replace function public.ack_warning(wid uuid) returns void
language plpgsql security definer set search_path = public as $$
begin
  update warnings w set acknowledged = current_date
  where w.id = wid and w.acknowledged is null
    and exists (select 1 from staff s where s.id = w.staff_id and s.user_id = auth.uid());
  if not found then raise exception 'Not allowed'; end if;
  insert into audit_log(actor, action, detail) values (auth.uid(), 'Acknowledged warning', wid::text);
end $$;

create or replace function public.my_staff_ids() returns setof uuid
language sql stable security definer set search_path = public as $$
  select id from staff where user_id = auth.uid()
$$;

-- Chat channel rule: general, a workspace channel the user can see, or a DM they are part of.
create or replace function public.chan_ok(ch text) returns boolean
language sql stable as $$
  select public.can_view('chat') and (
       ch = 'general'
    or (ch like 'ws:%' and public.ws_ok(substr(ch, 4)))
    or (ch like 'dm:%' and strpos(ch, auth.uid()::text) > 0)
  )
$$;

-- ---------- 5. New user → profile with default access ----------------
create or replace function public.handle_new_user() returns trigger
language plpgsql security definer set search_path = public as $$
declare
  is_p boolean := lower(new.email) = lower(public.pems_principal_email());
  em text := lower(new.email);
  nm text := coalesce(nullif(new.raw_user_meta_data->>'name', ''), split_part(new.email, '@', 1));
  ttl text := 'Assistant';
  mods jsonb;
  wss text[] := array[]::text[];
  k text;
begin
  if is_p then
    insert into profiles(id, email, name, title, role, color) values (new.id, new.email, 'M Rafiq Hoque', 'Principal', 'principal', '#b45309')
      on conflict (id) do nothing;
    return new;
  end if;
  if em = 'pstocoo.ishc@gmail.com' then
    nm := 'Md Sumon Reza'; ttl := 'Executive Assistant (PA)';
    mods := '{"dashboard":"view","calendar":"edit","tasks":"edit","contacts":"edit","documents":"view","portfolio":"none","finance":"none","payroll":"none","meetings":"edit","chat":"edit","attendance":"view","warnings":"view","travel":"edit","reports":"view"}';
    wss := array['Big7Placements','AGL Group','Consulting & Partnerships'];
  elsif em = 'support@revenuehelper.org' then
    nm := 'PA02'; ttl := 'Administrative Assistant (PA02)';
    mods := '{"dashboard":"view","calendar":"view","tasks":"edit","contacts":"view","documents":"edit","portfolio":"none","finance":"entry","payroll":"none","meetings":"view","chat":"edit","attendance":"view","warnings":"view","travel":"view","reports":"view"}';
    wss := array['Big7Placements','AGL Group'];
  else
    -- unknown people start switched OFF; the Principal turns them on in Settings
    mods := '{"dashboard":"view","tasks":"edit","chat":"edit","attendance":"view","warnings":"view"}';
  end if;
  insert into profiles(id, email, name, title, role, color, active)
    values (new.id, new.email, nm, ttl, 'assistant', case when em = 'pstocoo.ishc@gmail.com' then '#be185d' else '#0e7490' end,
            em in ('pstocoo.ishc@gmail.com','support@revenuehelper.org'))
    on conflict (id) do nothing;
  for k in select jsonb_object_keys(mods) loop
    insert into permissions(user_id, module, level) values (new.id, k, mods->>k) on conflict do nothing;
  end loop;
  insert into workspace_access(user_id, workspace)
    select new.id, w from unnest(wss) w where exists (select 1 from workspaces where name = w)
    on conflict do nothing;
  return new;
end $$;
drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created after insert on auth.users for each row execute function public.handle_new_user();

-- ---------- 6. Row-level security ------------------------------------
do $$ declare t text; begin
  foreach t in array array['profiles','workspaces','permissions','workspace_access','app_settings','appointments','tasks','contacts','documents','meetings','travel','transactions','staff','payroll_adjustments','attendance','warnings','chat_messages','chat_seen','focus_items','audit_log','email_outbox','report_runs','payroll_runs'] loop
    execute format('alter table public.%I enable row level security', t);
  end loop;
end $$;

-- drop old policies so this file can be re-run safely
do $$ declare r record; begin
  for r in select policyname, tablename from pg_policies where schemaname = 'public' loop
    execute format('drop policy %I on public.%I', r.policyname, r.tablename);
  end loop;
end $$;

-- people & access
create policy p_profiles_read on public.profiles for select using (public.is_active_user());
create policy p_profiles_write on public.profiles for update using (public.is_principal()) with check (public.is_principal());
create policy p_ws_read on public.workspaces for select using (public.is_active_user());
create policy p_ws_write on public.workspaces for all using (public.is_principal()) with check (public.is_principal());
create policy p_perm_read on public.permissions for select using (public.is_principal() or user_id = auth.uid());
create policy p_perm_write on public.permissions for all using (public.is_principal()) with check (public.is_principal());
create policy p_wsa_read on public.workspace_access for select using (public.is_principal() or user_id = auth.uid());
create policy p_wsa_write on public.workspace_access for all using (public.is_principal()) with check (public.is_principal());
create policy p_settings_read on public.app_settings for select using (public.is_active_user());
create policy p_settings_write on public.app_settings for all using (public.is_principal()) with check (public.is_principal());

-- workspace-scoped modules
do $$ declare t text; m text; begin
  for t, m in select * from (values ('appointments','calendar'),('contacts','contacts'),('documents','documents'),('meetings','meetings'),('travel','travel')) v(t,m) loop
    execute format('create policy p_%1$s_read on public.%1$s for select using (public.rec_ok(%2$L, ws, scope))', t, m);
    execute format('create policy p_%1$s_ins on public.%1$s for insert with check (public.rec_write(%2$L, ws, scope))', t, m);
    execute format('create policy p_%1$s_upd on public.%1$s for update using (public.rec_write(%2$L, ws, scope)) with check (public.rec_write(%2$L, ws, scope))', t, m);
    execute format('create policy p_%1$s_del on public.%1$s for delete using (public.is_principal())', t);
  end loop;
end $$;

-- tasks: also visible to the person they are assigned to
create policy p_tasks_read on public.tasks for select using (public.rec_ok('tasks', ws, scope) or (public.can_view('tasks') and assignee = auth.uid()));
create policy p_tasks_ins on public.tasks for insert with check (public.rec_write('tasks', ws, scope));
create policy p_tasks_upd on public.tasks for update
  using (public.rec_write('tasks', ws, scope) or (public.can_edit('tasks') and assignee = auth.uid()))
  with check (public.rec_write('tasks', ws, scope) or (public.can_edit('tasks') and assignee = auth.uid()));
create policy p_tasks_del on public.tasks for delete using (public.is_principal());

-- finance
create policy p_tx_read on public.transactions for select
  using (public.is_principal() or public.perm('finance') = 'edit' or (public.perm('finance') in ('view','entry') and created_by = auth.uid()));
create policy p_tx_ins on public.transactions for insert with check (public.perm('finance') in ('entry','edit'));
create policy p_tx_upd on public.transactions for update
  using (public.is_principal() or (created_by = auth.uid() and status = 'Pending' and public.perm('finance') in ('entry','edit')))
  with check (public.is_principal() or (created_by = auth.uid() and status = 'Pending'));
create policy p_tx_del on public.transactions for delete using (public.is_principal());

-- payroll
create policy p_staff_read on public.staff for select using (public.can_view('payroll') or public.can_edit('warnings') or user_id = auth.uid());
create policy p_staff_write on public.staff for all using (public.can_edit('payroll')) with check (public.can_edit('payroll'));
create policy p_adj_read on public.payroll_adjustments for select using (public.can_view('payroll'));
create policy p_adj_write on public.payroll_adjustments for all using (public.can_edit('payroll')) with check (public.can_edit('payroll'));
create policy p_payruns_read on public.payroll_runs for select using (public.can_view('payroll'));
create policy p_payruns_write on public.payroll_runs for insert with check (public.can_edit('payroll'));

-- attendance
create policy p_att_read on public.attendance for select using (public.can_edit('attendance') or (public.is_active_user() and user_id = auth.uid()));
create policy p_att_ins on public.attendance for insert with check (public.can_edit('attendance') or (public.is_active_user() and user_id = auth.uid()));
create policy p_att_upd on public.attendance for update
  using (public.can_edit('attendance') or (public.is_active_user() and user_id = auth.uid() and check_out is null))
  with check (public.can_edit('attendance') or user_id = auth.uid());
create policy p_att_del on public.attendance for delete using (public.is_principal());

-- warnings
create policy p_warn_read on public.warnings for select
  using (public.can_edit('warnings') or (public.can_view('warnings') and staff_id in (select public.my_staff_ids())));
create policy p_warn_write on public.warnings for all using (public.can_edit('warnings')) with check (public.can_edit('warnings'));

-- chat
create policy p_chat_read on public.chat_messages for select using (public.chan_ok(channel));
create policy p_chat_ins on public.chat_messages for insert with check (public.can_edit('chat') and public.chan_ok(channel) and from_user = auth.uid());
create policy p_chat_del on public.chat_messages for delete using (public.is_principal());
create policy p_seen_all on public.chat_seen for all using (user_id = auth.uid()) with check (user_id = auth.uid());

-- principal-only and logs
create policy p_focus_all on public.focus_items for all using (public.is_principal()) with check (public.is_principal());
create policy p_audit_read on public.audit_log for select using (public.is_principal() or actor = auth.uid());
create policy p_audit_ins on public.audit_log for insert with check (public.is_active_user() and actor = auth.uid());
create policy p_outbox_read on public.email_outbox for select using (public.is_principal());
create policy p_outbox_ins on public.email_outbox for insert with check (public.is_active_user());
create policy p_runs_read on public.report_runs for select using (public.can_view('reports'));
create policy p_runs_ins on public.report_runs for insert with check (public.is_principal());

-- ---------- 7. Grants ------------------------------------------------
revoke all on all tables in schema public from anon;
grant select, insert, update, delete on all tables in schema public to authenticated;
grant usage, select on all sequences in schema public to authenticated;
grant execute on all functions in schema public to authenticated;

-- ---------- 8. File storage (private) --------------------------------
insert into storage.buckets (id, name, public) values ('pems-files', 'pems-files', false)
  on conflict (id) do nothing;

drop policy if exists pems_files_read on storage.objects;
drop policy if exists pems_files_insert on storage.objects;
drop policy if exists pems_files_delete on storage.objects;
create policy pems_files_read on storage.objects for select to authenticated using (
  bucket_id = 'pems-files' and (
       (name like 'docs/%' and exists (select 1 from public.documents d where d.storage_key = storage.objects.name))
    or (name like 'chat/%' and exists (select 1 from public.chat_messages c where c.file_key = storage.objects.name))
  ));
create policy pems_files_insert on storage.objects for insert to authenticated with check (
  bucket_id = 'pems-files' and (
       (name like 'docs/%' and public.can_edit('documents'))
    or (name like 'chat/%' and public.can_edit('chat'))
  ));
create policy pems_files_delete on storage.objects for delete to authenticated using (bucket_id = 'pems-files' and public.is_principal());

-- ---------- 9. Realtime for chat --------------------------------------
do $$ begin
  alter publication supabase_realtime add table public.chat_messages;
exception when duplicate_object then null; end $$;

-- ---------- 10. Starting data ----------------------------------------
insert into public.workspaces (name, color) values
  ('Big7Placements', '#2f6bff'), ('AGL Group', '#22c55e'),
  ('Consulting & Partnerships', '#8b5cf6'), ('Personal Affairs', '#f59e0b')
  on conflict (name) do nothing;

insert into public.app_settings (id, data) values (1, jsonb_build_object(
  'view', 'BDT', 'rate', 123, 'late', '09:30', 'tz', 'Asia/Dhaka',
  'notify', jsonb_build_object('on', true, 'email', 'athomerafiq@gmail.com', 'cal', true, 'calEmail', 'athomerafiq@gmail.com',
     'ev', jsonb_build_object('approvals', true, 'tasks', true, 'meetings', true, 'warnings', true, 'reports', true, 'payroll', true))
)) on conflict (id) do nothing;
