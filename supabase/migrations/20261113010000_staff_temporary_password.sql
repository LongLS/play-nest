-- Require staff to replace a temporary password before accessing operations.
alter table public.program_users
  add column if not exists must_change_password boolean not null default false;

create or replace function public.staff_password_changed()
returns void
language plpgsql
security definer
set search_path=public
as $$
begin
  update public.program_users
  set must_change_password=false, updated_at=now()
  where user_id=auth.uid() and active;

  if not found then
    raise exception 'Không tìm thấy tài khoản nhân viên đang hoạt động';
  end if;

  insert into public.membership_audit_log(actor_id,action,entity_type,entity_id)
  values(auth.uid(),'staff_password_changed','program_user',auth.uid()::text);
end
$$;

revoke all on function public.staff_password_changed() from public,anon;
grant execute on function public.staff_password_changed() to authenticated;
