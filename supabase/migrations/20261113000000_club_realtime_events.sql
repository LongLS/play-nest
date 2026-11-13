-- Secure realtime invalidation channel for PlayNest Club.
-- Customers receive only global events or events belonging to their own member record.
create table if not exists public.club_realtime_events (
  id bigint generated always as identity primary key,
  member_id uuid references public.members(id) on delete cascade,
  topic text not null,
  created_at timestamptz not null default now()
);

create index if not exists club_realtime_events_member_time
  on public.club_realtime_events(member_id,created_at desc);

alter table public.club_realtime_events enable row level security;
revoke all on public.club_realtime_events from public,anon,authenticated;
grant select on public.club_realtime_events to authenticated;

drop policy if exists "Customers receive own club events" on public.club_realtime_events;
create policy "Customers receive own club events"
on public.club_realtime_events for select to authenticated
using (
  member_id is null
  or exists(
    select 1 from public.members m
    where m.id=club_realtime_events.member_id
      and m.auth_user_id=auth.uid()
      and m.active
  )
);

create or replace function public.emit_club_realtime_event()
returns trigger language plpgsql security definer set search_path=public as $$
declare v_member_id uuid;v_topic text:=tg_table_name;
begin
  if tg_table_name='members' then
    v_member_id:=coalesce(new.id,old.id);
  elsif tg_table_name in ('earn_requests','point_ledger','redemptions') then
    v_member_id:=coalesce(new.member_id,old.member_id);
  elsif tg_table_name='rewards' then
    v_member_id:=null;
  end if;

  insert into public.club_realtime_events(member_id,topic)
  values(v_member_id,v_topic);

  -- Opportunistic cleanup keeps the signal table small without a scheduled job.
  delete from public.club_realtime_events where created_at<now()-interval '7 days';
  if tg_op='DELETE' then return old; end if;
  return new;
end $$;

drop trigger if exists members_club_realtime on public.members;
create trigger members_club_realtime after insert or update on public.members
for each row execute function public.emit_club_realtime_event();

drop trigger if exists earn_requests_club_realtime on public.earn_requests;
create trigger earn_requests_club_realtime after insert or update or delete on public.earn_requests
for each row execute function public.emit_club_realtime_event();

drop trigger if exists point_ledger_club_realtime on public.point_ledger;
create trigger point_ledger_club_realtime after insert or update or delete on public.point_ledger
for each row execute function public.emit_club_realtime_event();

drop trigger if exists redemptions_club_realtime on public.redemptions;
create trigger redemptions_club_realtime after insert or update or delete on public.redemptions
for each row execute function public.emit_club_realtime_event();

drop trigger if exists rewards_club_realtime on public.rewards;
create trigger rewards_club_realtime after insert or update or delete on public.rewards
for each row execute function public.emit_club_realtime_event();

do $$
begin
  if not exists(
    select 1 from pg_publication_tables
    where pubname='supabase_realtime'
      and schemaname='public'
      and tablename='club_realtime_events'
  ) then
    alter publication supabase_realtime add table public.club_realtime_events;
  end if;
end $$;

notify pgrst, 'reload schema';
