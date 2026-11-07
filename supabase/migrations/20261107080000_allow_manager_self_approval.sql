-- Managers have full operational authority, including reviewing requests they submitted.
-- Staff still cannot review any earn request because membership_role() must be manager.
create or replace function public.review_earn_request(p_request_id uuid,p_approve boolean,p_reason text)
returns void language plpgsql security definer set search_path=public as $$
declare v_actor uuid:=auth.uid();v_req public.earn_requests;v_balance int;v_expiry_months int;
begin
  if public.membership_role()<>'manager' then raise exception 'Chỉ Admin được duyệt'; end if;
  select * into v_req from public.earn_requests where id=p_request_id for update;
  if not found then raise exception 'Không tìm thấy yêu cầu'; end if;
  if v_req.status<>'pending' then raise exception 'Yêu cầu đã được xử lý'; end if;
  update public.members set pending_points=pending_points-v_req.points,available_points=available_points+(case when p_approve then v_req.points else 0 end),
    lifetime_points=lifetime_points+(case when p_approve then v_req.points else 0 end),visit_count=visit_count+(case when p_approve then 1 else 0 end),updated_at=now()
  where id=v_req.member_id returning available_points into v_balance;
  update public.earn_requests set status=case when p_approve then 'approved'::public.earn_status else 'rejected'::public.earn_status end,reviewed_by=v_actor,reviewed_at=now(),review_reason=nullif(trim(p_reason),'') where id=p_request_id;
  if p_approve then
    select point_expiry_months into v_expiry_months from public.program_settings where id=true;
    insert into public.point_ledger(member_id,type,points_delta,balance_after,earn_request_id,reason,expires_at,created_by)
    values(v_req.member_id,'earn',v_req.points,v_balance,v_req.id,'Duyệt hóa đơn '||v_req.invoice_code,now()+make_interval(months=>v_expiry_months),v_actor);
  end if;
  insert into public.membership_audit_log(actor_id,action,entity_type,entity_id,details)
  values(v_actor,case when p_approve then 'earn_approved' else 'earn_rejected' end,'earn_request',p_request_id::text,jsonb_build_object('reason',p_reason,'self_approved',v_req.submitted_by=v_actor));
end $$;

revoke all on function public.review_earn_request(uuid,boolean,text) from public,anon;
grant execute on function public.review_earn_request(uuid,boolean,text) to authenticated;
