-- ONLY for a separate presentation project. Never run in production.
do $$
declare
  v_actor uuid;
  v_lan uuid := gen_random_uuid();
  v_minh uuid := gen_random_uuid();
begin
  select user_id into v_actor from public.program_users where role='manager' and active limit 1;
  if v_actor is null then raise exception 'Create a manager before loading demo data'; end if;

  insert into public.members(id,member_code,phone_hash,phone_encrypted,display_name,available_points,pending_points,visit_count,is_demo,created_by)
  values
    (v_lan,'PN-DEMO01',encode(digest('0900000001','sha256'),'hex'),'0900000001','Lan Demo',85,20,3,true,v_actor),
    (v_minh,'PN-DEMO02',encode(digest('0900000002','sha256'),'hex'),'0900000002','Minh Demo',25,0,1,true,v_actor)
  on conflict(phone_hash) do nothing;

  insert into public.member_consents(member_id,membership_consent,marketing_consent,policy_version,recorded_by)
  values(v_lan,true,false,'demo-v1',v_actor),(v_minh,true,true,'demo-v1',v_actor)
  on conflict do nothing;

  insert into public.earn_requests(member_id,invoice_code,paid_amount,eligible_amount,points,occurred_at,status,submitted_by,abnormal)
  values(v_lan,'DEMO-PENDING-001',200000,200000,20,now()-interval '1 day','pending',v_actor,false)
  on conflict(invoice_code) do nothing;

  insert into public.point_ledger(member_id,type,points_delta,balance_after,reason,created_by)
  values(v_lan,'adjustment',85,85,'Số dư minh họa tách biệt production',v_actor),
        (v_minh,'adjustment',25,25,'Số dư minh họa tách biệt production',v_actor);
end $$;
