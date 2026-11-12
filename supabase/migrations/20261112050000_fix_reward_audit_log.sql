-- Reward fulfilment must write to the membership audit table used by this project.
create or replace function public.fulfill_redemption_code_v2(
  p_code text,
  p_booking_code text default null,
  p_applied_program text default null
)
returns jsonb language plpgsql security definer set search_path=public as $$
declare
  v_actor uuid:=auth.uid();
  v_redemption public.redemptions;
  v_reward text;
  v_member text;
  v_settings public.program_settings;
  v_booking text:=nullif(upper(trim(coalesce(p_booking_code,''))), '');
  v_program text:=nullif(trim(coalesce(p_applied_program,'')), '');
begin
  if not public.is_program_staff(v_actor) then raise exception 'Không có quyền xác nhận quà'; end if;

  select * into v_settings from public.program_settings where id=true;
  if v_program is not null and not v_settings.allow_voucher_with_promotions then
    raise exception 'Chương trình hiện không cho phép dùng quà cùng combo/khuyến mãi khác';
  end if;
  if v_booking is not null and (
    select count(*) from public.redemptions
    where booking_code=v_booking and status='fulfilled'
  )>=v_settings.max_vouchers_per_booking then
    raise exception 'Booking/hóa đơn này đã đạt số quà tối đa';
  end if;

  select * into v_redemption from public.redemptions
  where upper(claim_code)=upper(trim(p_code)) for update;
  if not found then raise exception 'Mã nhận quà không đúng'; end if;
  if v_redemption.status<>'pending' then raise exception 'Mã nhận quà đã được xử lý'; end if;
  if v_redemption.valid_until is not null and v_redemption.valid_until<now() then
    update public.redemptions set status='expired',fulfilled_at=now(),fulfilled_by=v_actor where id=v_redemption.id;
    return jsonb_build_object('expired',true,'message','Mã nhận quà đã hết hạn. Điểm không tự động hoàn.');
  end if;

  select r.name,m.member_code into v_reward,v_member
  from public.rewards r join public.members m on m.id=v_redemption.member_id
  where r.id=v_redemption.reward_id;

  update public.redemptions set
    status='fulfilled',fulfilled_at=now(),fulfilled_by=v_actor,
    booking_code=v_booking,applied_program=v_program
  where id=v_redemption.id;

  insert into public.membership_audit_log(actor_id,action,entity_type,entity_id,details)
  values(v_actor,'redemption_fulfilled','redemption',v_redemption.id::text,
    jsonb_build_object('reward',v_reward,'member',v_member,'booking_code',v_booking,'applied_program',v_program));
  return jsonb_build_object('expired',false,'reward_name',v_reward,'member_code',v_member,'message','Đã xác nhận giao quà');
end $$;

revoke all on function public.fulfill_redemption_code_v2(text,text,text) from public,anon;
grant execute on function public.fulfill_redemption_code_v2(text,text,text) to authenticated;

notify pgrst, 'reload schema';
