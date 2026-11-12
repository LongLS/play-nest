-- Shared authorization check used by reward fulfilment RPCs.
create or replace function public.is_program_staff(p_user_id uuid default auth.uid())
returns boolean language sql stable security definer set search_path=public as $$
  select exists(
    select 1
    from public.program_users
    where user_id=p_user_id
      and active
      and (role='manager' or can_redeem)
  )
$$;

revoke all on function public.is_program_staff(uuid) from public,anon;
grant execute on function public.is_program_staff(uuid) to authenticated;

notify pgrst, 'reload schema';
