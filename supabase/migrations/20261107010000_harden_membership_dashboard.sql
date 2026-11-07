-- Follow-up for installations where the Membership migration was already run.
-- Keeps survey admins and Membership managers aligned without exposing member data.
insert into public.program_users (user_id, display_name, role, active, can_redeem)
select a.user_id, coalesce(nullif(split_part(a.email,'@',1),''),'PlayNest Admin'), 'manager', true, true
from public.admin_users a
on conflict (user_id) do update set role='manager',active=true,can_redeem=true,updated_at=now();

drop policy if exists "Admins can read survey responses" on public.survey_responses;
create policy "Managers can read survey responses"
on public.survey_responses for select to authenticated
using (
  exists(select 1 from public.admin_users a where a.user_id=(select auth.uid()))
  or exists(select 1 from public.program_users p where p.user_id=(select auth.uid()) and p.active and p.role='manager')
);

drop policy if exists "Active users read rewards" on public.rewards;
create policy "Authorized users read rewards"
on public.rewards for select to authenticated
using (
  public.membership_role()='manager'
  or (active and public.membership_role()='staff')
);

create or replace function public.submit_earn_request(p_member_id uuid,p_invoice_code text,p_paid_amount int,p_eligible_amount int,p_occurred_at timestamptz,p_room_type text,p_applied_program text)
returns uuid language plpgsql security definer set search_path=public as $$
declare v_actor uuid:=auth.uid(); v_settings public.program_settings; v_points int; v_id uuid; v_program text:=nullif(trim(p_applied_program),'');
begin
  if public.membership_role() is null then raise exception 'Không có quyền Membership'; end if;
  if nullif(trim(p_invoice_code),'') is null then raise exception 'Mã hóa đơn là bắt buộc'; end if;
  if not exists(select 1 from public.members where id=p_member_id and active) then raise exception 'Thành viên không hoạt động'; end if;
  select * into v_settings from public.program_settings where id=true;
  v_points:=floor(p_eligible_amount::numeric/v_settings.spend_per_point);
  if p_paid_amount<=0 or p_eligible_amount<=0 or v_points<1 or p_eligible_amount>p_paid_amount then raise exception 'Số tiền đủ điều kiện không hợp lệ'; end if;
  if p_occurred_at>now()+interval '5 minutes' then raise exception 'Thời gian hóa đơn không hợp lệ'; end if;
  insert into public.earn_requests(member_id,invoice_code,paid_amount,eligible_amount,points,occurred_at,room_type,applied_program,abnormal,submitted_by)
  values(p_member_id,upper(trim(p_invoice_code)),p_paid_amount,p_eligible_amount,v_points,p_occurred_at,nullif(trim(p_room_type),''),v_program,
    p_paid_amount>=v_settings.abnormal_invoice_amount or v_program=any(v_settings.excluded_programs),v_actor)
  returning id into v_id;
  update public.members set pending_points=pending_points+v_points,updated_at=now() where id=p_member_id;
  insert into public.membership_audit_log(actor_id,action,entity_type,entity_id,details)
  values(v_actor,'earn_submitted','earn_request',v_id::text,jsonb_build_object('points',v_points,'program',v_program));
  return v_id;
exception when unique_violation then raise exception 'Hóa đơn đã được sử dụng';
end $$;

grant execute on function public.submit_earn_request(uuid,text,int,int,timestamptz,text,text) to authenticated;
