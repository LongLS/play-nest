-- PlayNest Club: verified customer identity, self-service profile and one-time reward codes.
alter table public.members
  add column if not exists auth_user_id uuid unique references auth.users(id) on delete set null,
  add column if not exists lifetime_points integer not null default 0 check (lifetime_points >= 0);

update public.members m set lifetime_points=coalesce((select sum(greatest(l.points_delta,0)) from public.point_ledger l where l.member_id=m.id and l.type in ('earn','bonus')),0)
where m.lifetime_points=0;

alter table public.rewards
  add column if not exists description text,
  add column if not exists image_url text,
  add column if not exists stock_limit integer check (stock_limit is null or stock_limit >= 0),
  add column if not exists per_member_limit integer check (per_member_limit is null or per_member_limit > 0),
  add column if not exists starts_at timestamptz,
  add column if not exists ends_at timestamptz,
  add column if not exists archived_at timestamptz;

alter table public.redemptions
  add column if not exists status text not null default 'fulfilled',
  add column if not exists code_hash text,
  add column if not exists code_expires_at timestamptz,
  add column if not exists fulfilled_at timestamptz,
  add column if not exists fulfilled_by uuid references auth.users(id),
  add column if not exists cancelled_at timestamptz,
  add column if not exists cancellation_reason text;

alter table public.redemptions drop constraint if exists redemption_status_check;
alter table public.redemptions add constraint redemption_status_check check(status in ('pending','fulfilled','cancelled','expired'));
create unique index if not exists redemption_code_hash_unique on public.redemptions(code_hash) where code_hash is not null;

create table if not exists public.member_data_requests (
  id uuid primary key default gen_random_uuid(),
  member_id uuid not null references public.members(id),
  request_type text not null check(request_type in ('view','correct','delete')),
  note text,
  status text not null default 'pending' check(status in ('pending','processing','completed','rejected')),
  created_at timestamptz not null default now(),
  resolved_at timestamptz,
  resolved_by uuid references auth.users(id),
  resolution_note text
);
alter table public.member_data_requests enable row level security;
revoke all on public.member_data_requests from anon,authenticated;

create or replace function public.verified_customer_phone()
returns text language plpgsql stable security definer set search_path=public,auth as $$
declare v_phone text;v_confirmed timestamptz;
begin
  select phone,phone_confirmed_at into v_phone,v_confirmed from auth.users where id=auth.uid();
  if v_phone is null or v_confirmed is null then raise exception 'Số điện thoại chưa được Supabase xác minh'; end if;
  return public.normalize_phone(v_phone);
end $$;

create or replace function public.customer_link_or_register(p_name text default null,p_membership_consent boolean default false,p_marketing_consent boolean default false,p_policy_version text default '2026-11')
returns uuid language plpgsql security definer set search_path=public,auth,extensions as $$
declare v_phone text:=public.verified_customer_phone();v_member uuid;v_existing uuid;
begin
  select id,auth_user_id into v_member,v_existing from public.members where phone_hash=encode(digest(v_phone,'sha256'),'hex') for update;
  if v_member is not null then
    if v_existing is not null and v_existing<>auth.uid() then raise exception 'Hồ sơ đã liên kết danh tính khác; vui lòng liên hệ PlayNest'; end if;
    update public.members set auth_user_id=auth.uid(),phone_verified_at=coalesce(phone_verified_at,now()),phone_verification_method='Supabase SMS OTP',updated_at=now() where id=v_member;
  else
    if not p_membership_consent then raise exception 'Cần đồng ý tham gia để tạo thành viên'; end if;
    insert into public.members(phone_hash,phone_encrypted,display_name,auth_user_id,phone_verified_at,phone_verification_method,created_by)
    values(encode(digest(v_phone,'sha256'),'hex'),v_phone,nullif(trim(p_name),''),auth.uid(),now(),'Supabase SMS OTP',auth.uid()) returning id into v_member;
    insert into public.member_consents(member_id,membership_consent,marketing_consent,policy_version,recorded_by)
    values(v_member,true,coalesce(p_marketing_consent,false),p_policy_version,auth.uid());
  end if;
  insert into public.membership_audit_log(actor_id,action,entity_type,entity_id) values(auth.uid(),'customer_identity_linked','member',v_member::text);
  return v_member;
end $$;

create or replace function public.customer_club_profile()
returns jsonb language plpgsql security definer set search_path=public,extensions as $$
declare v_member public.members;
begin
  select * into v_member from public.members where auth_user_id=auth.uid() and active;
  if v_member.id is null then return null; end if;
  return jsonb_build_object(
    'id',v_member.id,'member_code',v_member.member_code,'display_name',v_member.display_name,
    'masked_phone',public.mask_phone(v_member.phone_encrypted),'available_points',v_member.available_points,
    'pending_points',v_member.pending_points,'lifetime_points',v_member.lifetime_points,'created_at',v_member.created_at,
    'marketing_consent',coalesce((select marketing_consent from public.member_consents where member_id=v_member.id order by consented_at desc limit 1),false),
    'rewards',coalesce((select jsonb_agg(to_jsonb(r) order by r.points_cost,r.name) from (
      select w.id,w.name,w.description,w.image_url,w.points_cost,w.conditions,w.valid_days,
        (v_member.available_points>=w.points_cost) eligible,greatest(w.points_cost-v_member.available_points,0) missing_points
      from public.rewards w where w.active and w.archived_at is null and (w.starts_at is null or w.starts_at<=now()) and (w.ends_at is null or w.ends_at>now())
      and (w.stock_limit is null or (select count(*) from public.redemptions d where d.reward_id=w.id and d.status in ('pending','fulfilled'))<w.stock_limit)) r),'[]'::jsonb),
    'visits',coalesce((select jsonb_agg(to_jsonb(v) order by v.occurred_at desc) from (
      select e.invoice_code,e.occurred_at,e.eligible_amount,e.points,e.status,e.review_reason from public.earn_requests e where e.member_id=v_member.id order by e.occurred_at desc limit 50) v),'[]'::jsonb),
    'ledger',coalesce((select jsonb_agg(to_jsonb(l) order by l.created_at desc) from (
      select p.type,p.points_delta,p.balance_after,p.reason,p.expires_at,p.created_at from public.point_ledger p where p.member_id=v_member.id order by p.created_at desc limit 100) l),'[]'::jsonb),
    'redemptions',coalesce((select jsonb_agg(to_jsonb(d) order by d.redeemed_at desc) from (
      select x.id,w.name reward_name,x.points_spent,x.status,x.code_expires_at,x.redeemed_at,x.fulfilled_at from public.redemptions x join public.rewards w on w.id=x.reward_id where x.member_id=v_member.id order by x.redeemed_at desc limit 50) d),'[]'::jsonb));
end $$;

create or replace function public.customer_redeem_reward(p_reward_id uuid)
returns jsonb language plpgsql security definer set search_path=public,extensions as $$
declare v_member public.members;v_reward public.rewards;v_balance int;v_id uuid;v_code text;
begin
  select * into v_member from public.members where auth_user_id=auth.uid() and active for update;
  if v_member.id is null then raise exception 'Chưa có hồ sơ thành viên đã xác minh'; end if;
  select * into v_reward from public.rewards where id=p_reward_id and active and archived_at is null and (starts_at is null or starts_at<=now()) and (ends_at is null or ends_at>now()) for share;
  if v_reward.id is null then raise exception 'Phần thưởng không khả dụng'; end if;
  if v_reward.stock_limit is not null and (select count(*) from public.redemptions where reward_id=v_reward.id and status in ('pending','fulfilled'))>=v_reward.stock_limit then raise exception 'Phần thưởng đã hết số lượng'; end if;
  if v_reward.per_member_limit is not null and (select count(*) from public.redemptions where reward_id=v_reward.id and member_id=v_member.id and status in ('pending','fulfilled'))>=v_reward.per_member_limit then raise exception 'Đã đạt giới hạn đổi phần thưởng'; end if;
  update public.members set available_points=available_points-v_reward.points_cost,updated_at=now() where id=v_member.id and available_points>=v_reward.points_cost returning available_points into v_balance;
  if not found then raise exception 'Không đủ điểm'; end if;
  v_code:=upper(substr(encode(gen_random_bytes(8),'hex'),1,10));
  insert into public.redemptions(member_id,reward_id,points_spent,verification_method,verification_note,redeemed_by,status,code_hash,code_expires_at)
  values(v_member.id,v_reward.id,v_reward.points_cost,'Mã một lần từ PlayNest Club','Khách tự đổi qua OTP',auth.uid(),'pending',encode(digest(v_code,'sha256'),'hex'),now()+interval '30 minutes') returning id into v_id;
  insert into public.point_ledger(member_id,type,points_delta,balance_after,reference_id,reason,created_by)
  values(v_member.id,'redeem',-v_reward.points_cost,v_balance,v_id,'Khách đổi '||v_reward.name,auth.uid());
  insert into public.membership_audit_log(actor_id,action,entity_type,entity_id) values(auth.uid(),'customer_reward_redeemed','redemption',v_id::text);
  return jsonb_build_object('redemption_id',v_id,'code',v_code,'expires_at',now()+interval '30 minutes');
end $$;

create or replace function public.fulfill_redemption_code(p_code text)
returns jsonb language plpgsql security definer set search_path=public,extensions as $$
declare v_redemption public.redemptions;v_reward text;v_member text;v_balance int;
begin
  if not exists(select 1 from public.program_users where user_id=auth.uid() and active and (role='manager' or can_redeem)) then raise exception 'Không có quyền xác nhận quà'; end if;
  select * into v_redemption from public.redemptions where code_hash=encode(digest(upper(trim(p_code)),'sha256'),'hex') for update;
  if v_redemption.id is null then raise exception 'Mã đổi quà không hợp lệ'; end if;
  if v_redemption.status<>'pending' then raise exception 'Mã đã được sử dụng hoặc đã hủy'; end if;
  if v_redemption.code_expires_at<=now() then
    update public.members set available_points=available_points+v_redemption.points_spent,updated_at=now() where id=v_redemption.member_id returning available_points into v_balance;
    update public.redemptions set status='expired',cancelled_at=now(),cancellation_reason='Mã hết hạn tự động' where id=v_redemption.id;
    insert into public.point_ledger(member_id,type,points_delta,balance_after,reference_id,reason,created_by)
    values(v_redemption.member_id,'adjustment',v_redemption.points_spent,v_balance,v_redemption.id,'Hoàn điểm do mã đổi quà hết hạn',auth.uid());
    return jsonb_build_object('expired',true,'message','Mã đã hết hạn và điểm đã được hoàn');
  end if;
  update public.redemptions set status='fulfilled',fulfilled_at=now(),fulfilled_by=auth.uid(),verification_note=verification_note||' · Đã giao quà' where id=v_redemption.id;
  select r.name,m.member_code into v_reward,v_member from public.rewards r,public.members m where r.id=v_redemption.reward_id and m.id=v_redemption.member_id;
  insert into public.membership_audit_log(actor_id,action,entity_type,entity_id) values(auth.uid(),'redemption_fulfilled','redemption',v_redemption.id::text);
  return jsonb_build_object('reward_name',v_reward,'member_code',v_member,'points_spent',v_redemption.points_spent);
end $$;

create or replace function public.reverse_earn_request(p_request_id uuid,p_reason text)
returns void language plpgsql security definer set search_path=public as $$
declare v_actor uuid:=auth.uid();v_req public.earn_requests;v_balance int;
begin
  if public.membership_role()<>'manager' then raise exception 'Chỉ Admin được đảo giao dịch'; end if;
  if nullif(trim(p_reason),'') is null then raise exception 'Cần nhập lý do đảo điểm'; end if;
  select * into v_req from public.earn_requests where id=p_request_id for update;
  if v_req.status<>'approved' then raise exception 'Chỉ đảo được yêu cầu đã duyệt'; end if;
  update public.members set available_points=available_points-v_req.points,
    lifetime_points=greatest(lifetime_points-v_req.points,0),visit_count=greatest(visit_count-1,0),updated_at=now()
  where id=v_req.member_id and available_points>=v_req.points returning available_points into v_balance;
  if not found then raise exception 'Số dư khả dụng không đủ để đảo; hãy dùng điều chỉnh có kiểm soát'; end if;
  update public.earn_requests set status='reversed',review_reason=trim(p_reason),reviewed_by=v_actor,reviewed_at=now() where id=p_request_id;
  insert into public.point_ledger(member_id,type,points_delta,balance_after,earn_request_id,reason,created_by)
  values(v_req.member_id,'reversal',-v_req.points,v_balance,v_req.id,'Đảo hóa đơn '||v_req.invoice_code||': '||trim(p_reason),v_actor);
  insert into public.membership_audit_log(actor_id,action,entity_type,entity_id,details)
  values(v_actor,'earn_reversed','earn_request',p_request_id::text,jsonb_build_object('reason',p_reason,'points',v_req.points));
end $$;

create or replace function public.customer_cancel_redemption(p_redemption_id uuid,p_reason text default 'Khách hủy trước khi nhận quà')
returns void language plpgsql security definer set search_path=public as $$
declare v_redemption public.redemptions;v_balance int;
begin
  select d.* into v_redemption from public.redemptions d join public.members m on m.id=d.member_id
  where d.id=p_redemption_id and (m.auth_user_id=auth.uid() or public.membership_role()='manager') for update of d;
  if v_redemption.id is null then raise exception 'Không tìm thấy giao dịch'; end if;
  if v_redemption.status<>'pending' then raise exception 'Chỉ hủy được mã chưa sử dụng'; end if;
  update public.members set available_points=available_points+v_redemption.points_spent,updated_at=now() where id=v_redemption.member_id returning available_points into v_balance;
  update public.redemptions set status='cancelled',cancelled_at=now(),cancellation_reason=trim(p_reason) where id=v_redemption.id;
  insert into public.point_ledger(member_id,type,points_delta,balance_after,reference_id,reason,created_by)
  values(v_redemption.member_id,'adjustment',v_redemption.points_spent,v_balance,v_redemption.id,'Hoàn điểm hủy đổi quà: '||trim(p_reason),auth.uid());
  insert into public.membership_audit_log(actor_id,action,entity_type,entity_id,details) values(auth.uid(),'redemption_cancelled','redemption',v_redemption.id::text,jsonb_build_object('reason',p_reason));
end $$;

create or replace function public.customer_update_account(p_display_name text,p_marketing_consent boolean)
returns void language plpgsql security definer set search_path=public as $$
declare v_member uuid;
begin
  select id into v_member from public.members where auth_user_id=auth.uid() and active;
  if v_member is null then raise exception 'Không tìm thấy hồ sơ'; end if;
  update public.members set display_name=nullif(trim(p_display_name),''),updated_at=now() where id=v_member;
  insert into public.member_consents(member_id,membership_consent,marketing_consent,policy_version,recorded_by) values(v_member,true,p_marketing_consent,'2026-11',auth.uid());
  insert into public.membership_audit_log(actor_id,action,entity_type,entity_id) values(auth.uid(),'customer_account_updated','member',v_member::text);
end $$;

create or replace function public.customer_data_request(p_request_type text,p_note text)
returns uuid language plpgsql security definer set search_path=public as $$
declare v_member uuid;v_id uuid;
begin
  select id into v_member from public.members where auth_user_id=auth.uid();
  if v_member is null then raise exception 'Không tìm thấy hồ sơ'; end if;
  insert into public.member_data_requests(member_id,request_type,note) values(v_member,p_request_type,nullif(trim(p_note),'')) returning id into v_id;
  insert into public.membership_audit_log(actor_id,action,entity_type,entity_id,details) values(auth.uid(),'customer_data_request','member',v_member::text,jsonb_build_object('request_id',v_id,'type',p_request_type));
  return v_id;
end $$;

-- Approved points increase both spendable and lifetime totals. Reversals reduce both.
create or replace function public.review_earn_request(p_request_id uuid,p_approve boolean,p_reason text)
returns void language plpgsql security definer set search_path=public as $$
declare v_actor uuid:=auth.uid();v_req public.earn_requests;v_balance int;v_expiry_months int;
begin
  if public.membership_role()<>'manager' then raise exception 'Chỉ Admin được duyệt'; end if;
  select * into v_req from public.earn_requests where id=p_request_id for update;
  if v_req.status<>'pending' then raise exception 'Yêu cầu đã được xử lý'; end if;
  if v_req.submitted_by=v_actor then raise exception 'Không được tự duyệt yêu cầu của mình'; end if;
  update public.members set pending_points=pending_points-v_req.points,available_points=available_points+(case when p_approve then v_req.points else 0 end),
    lifetime_points=lifetime_points+(case when p_approve then v_req.points else 0 end),visit_count=visit_count+(case when p_approve then 1 else 0 end),updated_at=now()
  where id=v_req.member_id returning available_points into v_balance;
  update public.earn_requests set status=case when p_approve then 'approved' else 'rejected' end,reviewed_by=v_actor,reviewed_at=now(),review_reason=nullif(trim(p_reason),'') where id=p_request_id;
  if p_approve then select point_expiry_months into v_expiry_months from public.program_settings where id=true;insert into public.point_ledger(member_id,type,points_delta,balance_after,earn_request_id,reason,expires_at,created_by) values(v_req.member_id,'earn',v_req.points,v_balance,v_req.id,'Duyệt hóa đơn '||v_req.invoice_code,now()+make_interval(months=>v_expiry_months),v_actor);end if;
  insert into public.membership_audit_log(actor_id,action,entity_type,entity_id,details) values(v_actor,case when p_approve then 'earn_approved' else 'earn_rejected' end,'earn_request',p_request_id::text,jsonb_build_object('reason',p_reason));
end $$;

revoke all on function public.customer_link_or_register(text,boolean,boolean,text),public.customer_club_profile(),public.customer_redeem_reward(uuid),public.customer_cancel_redemption(uuid,text),public.customer_update_account(text,boolean),public.customer_data_request(text,text),public.fulfill_redemption_code(text) from public,anon;
grant execute on function public.customer_link_or_register(text,boolean,boolean,text),public.customer_club_profile(),public.customer_redeem_reward(uuid),public.customer_cancel_redemption(uuid,text),public.customer_update_account(text,boolean),public.customer_data_request(text,text) to authenticated;
grant execute on function public.fulfill_redemption_code(text) to authenticated;
revoke execute on function public.verified_customer_phone() from anon;
