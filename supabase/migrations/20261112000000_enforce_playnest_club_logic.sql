-- Enforce the production PlayNest Club rules without rewriting historical transactions.
alter table public.program_settings
  add column if not exists max_vouchers_per_booking integer not null default 1 check (max_vouchers_per_booking > 0),
  add column if not exists allow_voucher_with_promotions boolean not null default false;

create table if not exists public.program_policy_history (
  id bigint generated always as identity primary key,
  policy_version text not null,
  settings jsonb not null,
  effective_at timestamptz not null default now(),
  changed_by uuid references auth.users(id)
);
alter table public.program_policy_history enable row level security;
revoke all on public.program_policy_history from anon,authenticated;

alter table public.redemptions
  add column if not exists claim_code text,
  add column if not exists valid_until timestamptz,
  add column if not exists booking_code text,
  add column if not exists applied_program text;
create unique index if not exists redemption_claim_code_unique on public.redemptions(claim_code) where claim_code is not null;

create or replace function public.update_program_settings_v2(
  p_spend_per_point int,p_point_expiry_months int,p_abnormal_invoice_amount int,
  p_return_bonus_points int,p_return_within_days int,p_policy_version text,
  p_max_vouchers_per_booking int,p_allow_voucher_with_promotions boolean)
returns void language plpgsql security definer set search_path=public as $$
declare v_before jsonb;v_after jsonb;
begin
  if public.membership_role()<>'manager' then raise exception 'Chỉ Admin được đổi cấu hình'; end if;
  if p_spend_per_point<1 or p_point_expiry_months not between 1 and 60 or p_max_vouchers_per_booking<1 then
    raise exception 'Cấu hình không hợp lệ';
  end if;
  select to_jsonb(s) into v_before from public.program_settings s where id=true;
  update public.program_settings set spend_per_point=p_spend_per_point,point_expiry_months=p_point_expiry_months,
    abnormal_invoice_amount=p_abnormal_invoice_amount,return_bonus_points=p_return_bonus_points,
    return_within_days=p_return_within_days,policy_version=trim(p_policy_version),
    max_vouchers_per_booking=p_max_vouchers_per_booking,
    allow_voucher_with_promotions=coalesce(p_allow_voucher_with_promotions,false),
    updated_by=auth.uid(),updated_at=now() where id=true;
  select to_jsonb(s) into v_after from public.program_settings s where id=true;
  insert into public.program_policy_history(policy_version,settings,changed_by)
  values(trim(p_policy_version),v_after,auth.uid());
  insert into public.membership_audit_log(actor_id,action,entity_type,entity_id,details)
  values(auth.uid(),'settings_updated','program_settings','main',jsonb_build_object('before',v_before,'after',v_after));
end $$;

create or replace function public.save_reward_v2(
  p_id uuid,p_name text,p_description text,p_image_url text,p_points_cost int,p_voucher_value int,
  p_conditions text,p_valid_days int,p_stock_limit int,p_per_member_limit int,
  p_starts_at timestamptz,p_ends_at timestamptz,p_active boolean)
returns uuid language plpgsql security definer set search_path=public as $$
declare v_id uuid;v_before jsonb;v_after jsonb;
begin
  if public.membership_role()<>'manager' then raise exception 'Chỉ Admin được sửa phần thưởng'; end if;
  if nullif(trim(p_name),'') is null or p_points_cost<1 then raise exception 'Tên và điểm đổi quà không hợp lệ'; end if;
  if p_ends_at is not null and p_starts_at is not null and p_ends_at<=p_starts_at then raise exception 'Ngày kết thúc phải sau ngày bắt đầu'; end if;
  if p_id is null then
    insert into public.rewards(name,description,image_url,points_cost,voucher_value,conditions,valid_days,stock_limit,per_member_limit,starts_at,ends_at,active,created_by)
    values(trim(p_name),nullif(trim(p_description),''),nullif(trim(p_image_url),''),p_points_cost,p_voucher_value,
      nullif(trim(p_conditions),''),p_valid_days,p_stock_limit,p_per_member_limit,p_starts_at,p_ends_at,p_active,auth.uid())
    returning id into v_id;
  else
    select to_jsonb(r) into v_before from public.rewards r where id=p_id for update;
    update public.rewards set name=trim(p_name),description=nullif(trim(p_description),''),
      image_url=nullif(trim(p_image_url),''),points_cost=p_points_cost,voucher_value=p_voucher_value,
      conditions=nullif(trim(p_conditions),''),valid_days=p_valid_days,stock_limit=p_stock_limit,
      per_member_limit=p_per_member_limit,starts_at=p_starts_at,ends_at=p_ends_at,
      active=p_active,updated_at=now() where id=p_id returning id into v_id;
    if v_id is null then raise exception 'Không tìm thấy phần thưởng'; end if;
  end if;
  select to_jsonb(r) into v_after from public.rewards r where id=v_id;
  insert into public.membership_audit_log(actor_id,action,entity_type,entity_id,details)
  values(auth.uid(),'reward_saved','reward',v_id::text,jsonb_build_object('before',v_before,'after',v_after));
  return v_id;
end $$;

create or replace function public.process_member_point_expiry(p_member_id uuid)
returns integer language plpgsql security definer set search_path=public as $$
declare v_expired_grants int;v_consumed int;v_to_expire int;v_balance int;
begin
  if auth.uid() is null then raise exception 'Chưa đăng nhập'; end if;
  if public.membership_role() is null and not exists(
    select 1 from public.members where id=p_member_id and auth_user_id=auth.uid()
  ) then raise exception 'Không có quyền xử lý điểm'; end if;
  perform 1 from public.members where id=p_member_id for update;
  select coalesce(sum(points_delta),0) into v_expired_grants from public.point_ledger
    where member_id=p_member_id and points_delta>0 and type in ('earn','bonus')
      and expires_at is not null and expires_at<=now();
  select coalesce(-sum(points_delta),0) into v_consumed from public.point_ledger
    where member_id=p_member_id and points_delta<0;
  select least(available_points,greatest(v_expired_grants-v_consumed,0)) into v_to_expire
    from public.members where id=p_member_id;
  if coalesce(v_to_expire,0)<=0 then return 0; end if;
  update public.members set available_points=available_points-v_to_expire,updated_at=now()
    where id=p_member_id returning available_points into v_balance;
  insert into public.point_ledger(member_id,type,points_delta,balance_after,reason,created_by)
  values(p_member_id,'expiry',-v_to_expire,v_balance,'Điểm hết hạn theo chính sách',auth.uid());
  insert into public.membership_audit_log(actor_id,action,entity_type,entity_id,details)
  values(auth.uid(),'points_expired','member',p_member_id::text,jsonb_build_object('points',v_to_expire,'balance_after',v_balance));
  return v_to_expire;
end $$;

create or replace function public.customer_club_profile()
returns jsonb language plpgsql security definer set search_path=public,extensions as $$
declare v_member public.members;
begin
  select * into v_member from public.members where auth_user_id=auth.uid() and active;
  if v_member.id is null then return null; end if;
  perform public.process_member_point_expiry(v_member.id);
  select * into v_member from public.members where id=v_member.id;
  return jsonb_build_object(
    'id',v_member.id,'member_code',v_member.member_code,'display_name',v_member.display_name,
    'must_change_password',v_member.must_change_password,'masked_phone',public.mask_phone(v_member.phone_encrypted),
    'available_points',v_member.available_points,'pending_points',v_member.pending_points,
    'lifetime_points',v_member.lifetime_points,'created_at',v_member.created_at,
    'marketing_consent',coalesce((select marketing_consent from public.member_consents where member_id=v_member.id order by consented_at desc limit 1),false),
    'rewards',coalesce((select jsonb_agg(to_jsonb(r) order by r.points_cost,r.name) from (
      select w.id,w.name,w.description,w.image_url,w.points_cost,w.conditions,w.valid_days,w.active,
        w.stock_limit,w.per_member_limit,
        greatest(coalesce(w.stock_limit,2147483647)-(select count(*) from public.redemptions d where d.reward_id=w.id and d.status in ('pending','fulfilled')),0) remaining_stock,
        (w.stock_limit is not null and (select count(*) from public.redemptions d where d.reward_id=w.id and d.status in ('pending','fulfilled'))>=w.stock_limit) out_of_stock,
        greatest(w.points_cost-v_member.available_points,0) missing_points,
        (v_member.available_points>=w.points_cost
          and not (w.stock_limit is not null and (select count(*) from public.redemptions d where d.reward_id=w.id and d.status in ('pending','fulfilled'))>=w.stock_limit)
          and not (w.per_member_limit is not null and (select count(*) from public.redemptions d where d.reward_id=w.id and d.member_id=v_member.id and d.status in ('pending','fulfilled'))>=w.per_member_limit)) eligible
      from public.rewards w where w.active and w.archived_at is null
        and (w.starts_at is null or w.starts_at<=now()) and (w.ends_at is null or w.ends_at>now())) r),'[]'::jsonb),
    'visits',coalesce((select jsonb_agg(to_jsonb(v) order by v.occurred_at desc) from (
      select e.invoice_code,e.occurred_at,e.eligible_amount,e.points,e.status,e.review_reason
      from public.earn_requests e where e.member_id=v_member.id order by e.occurred_at desc limit 50) v),'[]'::jsonb),
    'ledger',coalesce((select jsonb_agg(to_jsonb(l) order by l.created_at desc) from (
      select p.type,p.points_delta,p.balance_after,p.reason,p.expires_at,p.created_at
      from public.point_ledger p where p.member_id=v_member.id order by p.created_at desc limit 100) l),'[]'::jsonb),
    'redemptions',coalesce((select jsonb_agg(to_jsonb(d) order by d.redeemed_at desc) from (
      select x.id,w.name reward_name,x.points_spent,x.status,x.claim_code,
        coalesce(x.valid_until,x.code_expires_at) valid_until,x.redeemed_at,x.fulfilled_at,x.cancelled_at
      from public.redemptions x join public.rewards w on w.id=x.reward_id
      where x.member_id=v_member.id order by x.redeemed_at desc limit 50) d),'[]'::jsonb));
end $$;

create or replace function public.customer_redeem_reward(p_reward_id uuid)
returns jsonb language plpgsql security definer set search_path=public,extensions as $$
declare v_member public.members;v_member_id uuid;v_reward public.rewards;v_balance int;v_id uuid;v_code text;v_valid_until timestamptz;
begin
  select id into v_member_id from public.members where auth_user_id=auth.uid() and active;
  if v_member_id is null then raise exception 'Tài khoản thành viên không hoạt động'; end if;
  perform public.process_member_point_expiry(v_member_id);
  select * into v_member from public.members where id=v_member_id for update;
  select * into v_reward from public.rewards where id=p_reward_id and active and archived_at is null
    and (starts_at is null or starts_at<=now()) and (ends_at is null or ends_at>now()) for update;
  if v_reward.id is null then raise exception 'Phần thưởng không khả dụng'; end if;
  if v_reward.stock_limit is not null and (select count(*) from public.redemptions where reward_id=v_reward.id and status in ('pending','fulfilled'))>=v_reward.stock_limit then raise exception 'Phần thưởng tạm hết'; end if;
  if v_reward.per_member_limit is not null and (select count(*) from public.redemptions where reward_id=v_reward.id and member_id=v_member.id and status in ('pending','fulfilled'))>=v_reward.per_member_limit then raise exception 'Bạn đã đạt giới hạn đổi phần thưởng này'; end if;
  update public.members set available_points=available_points-v_reward.points_cost,updated_at=now()
    where id=v_member.id and available_points>=v_reward.points_cost returning available_points into v_balance;
  if not found then raise exception 'Không đủ điểm khả dụng'; end if;
  v_code:=upper(substr(encode(gen_random_bytes(8),'hex'),1,10));
  v_valid_until:=now()+make_interval(days=>coalesce(v_reward.valid_days,30));
  insert into public.redemptions(member_id,reward_id,points_spent,verification_method,verification_note,
    redeemed_by,status,code_hash,claim_code,code_expires_at,valid_until)
  values(v_member.id,v_reward.id,v_reward.points_cost,'Mã nhận quà PlayNest Club','Khách chủ động đổi quà',
    auth.uid(),'pending',encode(digest(v_code,'sha256'),'hex'),v_code,v_valid_until,v_valid_until) returning id into v_id;
  insert into public.point_ledger(member_id,type,points_delta,balance_after,reference_id,reason,created_by)
  values(v_member.id,'redeem',-v_reward.points_cost,v_balance,v_id,'Khách đổi '||v_reward.name,auth.uid());
  insert into public.membership_audit_log(actor_id,action,entity_type,entity_id,details)
  values(auth.uid(),'customer_reward_redeemed','redemption',v_id::text,jsonb_build_object('points',v_reward.points_cost,'valid_until',v_valid_until));
  return jsonb_build_object('redemption_id',v_id,'code',v_code,'valid_until',v_valid_until);
end $$;

create or replace function public.fulfill_redemption_code(p_code text)
returns jsonb language plpgsql security definer set search_path=public,extensions as $$
declare v_redemption public.redemptions;v_reward text;v_member text;
begin
  if not exists(select 1 from public.program_users where user_id=auth.uid() and active and (role='manager' or can_redeem)) then raise exception 'Không có quyền xác nhận quà'; end if;
  select * into v_redemption from public.redemptions
    where code_hash=encode(digest(upper(trim(p_code)),'sha256'),'hex') for update;
  if v_redemption.id is null then raise exception 'Mã nhận quà không hợp lệ'; end if;
  if v_redemption.status<>'pending' then raise exception 'Mã đã được sử dụng, hủy hoặc hết hạn'; end if;
  if coalesce(v_redemption.valid_until,v_redemption.code_expires_at)<=now() then
    update public.redemptions set status='expired',cancelled_at=now(),cancellation_reason='Hết hạn sử dụng' where id=v_redemption.id;
    insert into public.membership_audit_log(actor_id,action,entity_type,entity_id)
    values(auth.uid(),'redemption_expired','redemption',v_redemption.id::text);
    return jsonb_build_object('expired',true,'message','Mã nhận quà đã hết hạn; điểm không tự động hoàn');
  end if;
  update public.redemptions set status='fulfilled',fulfilled_at=now(),fulfilled_by=auth.uid(),
    verification_note=verification_note||' · Đã giao quà' where id=v_redemption.id;
  select r.name,m.member_code into v_reward,v_member from public.rewards r,public.members m
    where r.id=v_redemption.reward_id and m.id=v_redemption.member_id;
  insert into public.membership_audit_log(actor_id,action,entity_type,entity_id,details)
  values(auth.uid(),'redemption_fulfilled','redemption',v_redemption.id::text,jsonb_build_object('reward',v_reward,'member',v_member));
  return jsonb_build_object('reward_name',v_reward,'member_code',v_member,'points_spent',v_redemption.points_spent);
end $$;

create or replace function public.fulfill_redemption_code_v2(p_code text,p_booking_code text,p_applied_program text default null)
returns jsonb language plpgsql security definer set search_path=public,extensions as $$
declare v_redemption public.redemptions;v_reward text;v_member text;v_settings public.program_settings;
begin
  if not exists(select 1 from public.program_users where user_id=auth.uid() and active and (role='manager' or can_redeem)) then raise exception 'Không có quyền xác nhận quà'; end if;
  if nullif(upper(trim(p_booking_code)),'') is null then raise exception 'Cần nhập mã booking/hóa đơn sử dụng quà'; end if;
  select * into v_settings from public.program_settings where id=true;
  if nullif(trim(p_applied_program),'') is not null and not v_settings.allow_voucher_with_promotions then
    raise exception 'Voucher không được cộng dồn với combo/khuyến mãi khác';
  end if;
  if (select count(*) from public.redemptions where booking_code=upper(trim(p_booking_code)) and status='fulfilled')>=v_settings.max_vouchers_per_booking then
    raise exception 'Booking này đã đạt giới hạn voucher';
  end if;
  select * into v_redemption from public.redemptions
    where code_hash=encode(digest(upper(trim(p_code)),'sha256'),'hex') for update;
  if v_redemption.id is null then raise exception 'Mã nhận quà không hợp lệ'; end if;
  if v_redemption.status<>'pending' then raise exception 'Mã đã được sử dụng, hủy hoặc hết hạn'; end if;
  if coalesce(v_redemption.valid_until,v_redemption.code_expires_at)<=now() then
    update public.redemptions set status='expired',cancelled_at=now(),cancellation_reason='Hết hạn sử dụng' where id=v_redemption.id;
    insert into public.membership_audit_log(actor_id,action,entity_type,entity_id)
    values(auth.uid(),'redemption_expired','redemption',v_redemption.id::text);
    return jsonb_build_object('expired',true,'message','Mã nhận quà đã hết hạn; điểm không tự động hoàn');
  end if;
  update public.redemptions set status='fulfilled',fulfilled_at=now(),fulfilled_by=auth.uid(),
    booking_code=upper(trim(p_booking_code)),applied_program=nullif(trim(p_applied_program),''),
    verification_note=verification_note||' · Đã giao quà' where id=v_redemption.id;
  select r.name,m.member_code into v_reward,v_member from public.rewards r,public.members m
    where r.id=v_redemption.reward_id and m.id=v_redemption.member_id;
  insert into public.membership_audit_log(actor_id,action,entity_type,entity_id,details)
  values(auth.uid(),'redemption_fulfilled','redemption',v_redemption.id::text,
    jsonb_build_object('reward',v_reward,'member',v_member,'booking_code',upper(trim(p_booking_code)),'applied_program',p_applied_program));
  return jsonb_build_object('reward_name',v_reward,'member_code',v_member,'points_spent',v_redemption.points_spent);
end $$;

create or replace function public.customer_cancel_redemption(p_redemption_id uuid,p_reason text default null)
returns void language plpgsql security definer set search_path=public as $$
declare v_redemption public.redemptions;v_balance int;
begin
  if public.membership_role()<>'manager' then raise exception 'Chỉ Admin được xử lý hủy và hoàn điểm'; end if;
  if char_length(trim(coalesce(p_reason,'')))<5 then raise exception 'Cần nhập lý do hủy'; end if;
  select * into v_redemption from public.redemptions where id=p_redemption_id for update;
  if v_redemption.id is null then raise exception 'Không tìm thấy giao dịch'; end if;
  if v_redemption.status<>'pending' then raise exception 'Chỉ hủy được mã chưa sử dụng'; end if;
  update public.members set available_points=available_points+v_redemption.points_spent,updated_at=now()
    where id=v_redemption.member_id returning available_points into v_balance;
  update public.redemptions set status='cancelled',cancelled_at=now(),cancellation_reason=trim(p_reason)
    where id=v_redemption.id;
  insert into public.point_ledger(member_id,type,points_delta,balance_after,reference_id,reason,created_by)
  values(v_redemption.member_id,'adjustment',v_redemption.points_spent,v_balance,v_redemption.id,
    'Admin hoàn điểm hủy đổi quà: '||trim(p_reason),auth.uid());
  insert into public.membership_audit_log(actor_id,action,entity_type,entity_id,details)
  values(auth.uid(),'redemption_cancelled','redemption',v_redemption.id::text,
    jsonb_build_object('reason',p_reason,'points_refunded',v_redemption.points_spent));
end $$;

create or replace function public.redemption_list(p_search text default null,p_from timestamptz default null,p_to timestamptz default null,p_page int default 1,p_page_size int default 20)
returns jsonb language plpgsql security definer set search_path=public as $$
declare v_role public.staff_role:=public.membership_role();v_offset int;v_total bigint;v_rows jsonb;
begin
  if v_role is null then raise exception 'Không có quyền'; end if;
  p_page:=greatest(coalesce(p_page,1),1);p_page_size:=least(greatest(coalesce(p_page_size,20),1),100);v_offset:=(p_page-1)*p_page_size;
  select count(*) into v_total from public.redemptions d join public.members m on m.id=d.member_id join public.rewards r on r.id=d.reward_id
    where (v_role='manager' or d.fulfilled_by=auth.uid() or d.redeemed_by=auth.uid())
      and (p_search is null or p_search='' or m.member_code ilike '%'||p_search||'%' or r.name ilike '%'||p_search||'%')
      and (p_from is null or d.redeemed_at>=p_from) and (p_to is null or d.redeemed_at<p_to);
  select coalesce(jsonb_agg(to_jsonb(x)),'[]'::jsonb) into v_rows from (
    select d.id,m.member_code,m.display_name,r.name reward_name,d.points_spent,d.status,
      d.verification_method,coalesce(f.display_name,s.display_name) handled_by_name,
      d.redeemed_at,coalesce(d.valid_until,d.code_expires_at) valid_until,d.fulfilled_at
    from public.redemptions d join public.members m on m.id=d.member_id join public.rewards r on r.id=d.reward_id
    left join public.program_users f on f.user_id=d.fulfilled_by left join public.program_users s on s.user_id=d.redeemed_by
    where (v_role='manager' or d.fulfilled_by=auth.uid() or d.redeemed_by=auth.uid())
      and (p_search is null or p_search='' or m.member_code ilike '%'||p_search||'%' or r.name ilike '%'||p_search||'%')
      and (p_from is null or d.redeemed_at>=p_from) and (p_to is null or d.redeemed_at<p_to)
    order by d.redeemed_at desc limit p_page_size offset v_offset) x;
  return jsonb_build_object('rows',v_rows,'total',v_total,'page',p_page,'page_size',p_page_size);
end $$;

revoke all on function public.update_program_settings_v2(int,int,int,int,int,text,int,boolean),
  public.save_reward_v2(uuid,text,text,text,int,int,text,int,int,int,timestamptz,timestamptz,boolean),
  public.fulfill_redemption_code_v2(text,text,text),public.process_member_point_expiry(uuid) from public,anon;
grant execute on function public.update_program_settings_v2(int,int,int,int,int,text,int,boolean),
  public.save_reward_v2(uuid,text,text,text,int,int,text,int,int,int,timestamptz,timestamptz,boolean),
  public.fulfill_redemption_code_v2(text,text,text),public.process_member_point_expiry(uuid) to authenticated;
