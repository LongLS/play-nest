create table if not exists public.admin_users (
  user_id uuid primary key references auth.users(id) on delete cascade,
  email text not null,
  created_at timestamptz not null default now()
);

alter table public.admin_users enable row level security;

revoke all on table public.admin_users from anon, authenticated;
grant select on table public.admin_users to authenticated;

drop policy if exists "Admins can view own membership"
  on public.admin_users;

create policy "Admins can view own membership"
on public.admin_users
for select
to authenticated
using ((select auth.uid()) = user_id);

-- Register the PlayNest account when it already exists in Supabase Auth.
insert into public.admin_users (user_id, email)
select id, email
from auth.users
where lower(email) = lower('playnest.vn@gmail.com')
on conflict (user_id) do update set email = excluded.email;

revoke all on table public.survey_responses from anon, authenticated;
grant insert on table public.survey_responses to anon, authenticated;
grant select on table public.survey_responses to authenticated;

drop policy if exists "Admins can read survey responses"
  on public.survey_responses;

create policy "Admins can read survey responses"
on public.survey_responses
for select
to authenticated
using (
  exists (
    select 1
    from public.admin_users
    where admin_users.user_id = (select auth.uid())
  )
);
