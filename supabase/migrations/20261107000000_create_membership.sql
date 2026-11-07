-- PlayNest Membership. Apply after the survey/admin migrations.
create extension if not exists pgcrypto;

create type public.staff_role as enum ('staff', 'manager');
create type public.earn_status as enum ('pending', 'approved', 'rejected', 'reversed');
create type public.ledger_type as enum ('earn', 'redeem', 'adjustment', 'reversal', 'bonus', 'expiry');

create table public.program_users (
  user_id uuid primary key references auth.users(id) on delete cascade,
  email text,
  display_name text not null,
  role public.staff_role not null default 'staff',
  active boolean not null default true,
  can_redeem boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.members (
  id uuid primary key default gen_random_uuid(),
  member_code text not null unique default ('PN-' || upper(substr(replace(gen_random_uuid()::text, '-', ''), 1, 8))),
  phone_hash text not null unique,
  phone_encrypted text not null,
  display_name text,
  available_points integer not null default 0 check (available_points >= 0),
  pending_points integer not null default 0 check (pending_points >= 0),
  visit_count integer not null default 0 check (visit_count >= 0),
  is_demo boolean not null default false,
  active boolean not null default true,
  created_by uuid references auth.users(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.member_consents (
  id uuid primary key default gen_random_uuid(),
  member_id uuid not null references public.members(id),
  membership_consent boolean not null,
  marketing_consent boolean not null default false,
  policy_version text not null,
  consented_at timestamptz not null default now(),
  recorded_by uuid not null references auth.users(id)
);

create table public.program_settings (
  id boolean primary key default true check (id),
  spend_per_point integer not null default 10000 check (spend_per_point > 0),
  point_expiry_months integer not null default 12 check (point_expiry_months between 1 and 60),
  abnormal_invoice_amount integer not null default 3000000 check (abnormal_invoice_amount > 0),
  return_bonus_points integer not null default 20 check (return_bonus_points >= 0),
  return_within_days integer not null default 21 check (return_within_days > 0),
  return_bonus_monthly_limit integer not null default 1 check (return_bonus_monthly_limit >= 0),
  eligible_weekdays smallint[] not null default array[1,2,3,4,5]::smallint[],
  excluded_programs text[] not null default array['Solar','Orbit','Starlight Overnight','Weekend Bonus']::text[],
  policy_version text not null default '2026-11-demo',
  updated_by uuid references auth.users(id),
  updated_at timestamptz not null default now()
);
insert into public.program_settings (id) values (true) on conflict do nothing;

create table public.rewards (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  points_cost integer not null check (points_cost > 0),
  voucher_value integer check (voucher_value is null or voucher_value >= 0),
  conditions text,
  valid_days integer check (valid_days is null or valid_days > 0),
  active boolean not null default true,
  is_demo boolean not null default false,
  created_by uuid references auth.users(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.earn_requests (
  id uuid primary key default gen_random_uuid(),
  member_id uuid not null references public.members(id),
  invoice_code text not null unique,
  paid_amount integer not null check (paid_amount > 0),
  eligible_amount integer not null check (eligible_amount >= 0 and eligible_amount <= paid_amount),
  points integer not null check (points > 0),
  occurred_at timestamptz not null,
  room_type text,
  applied_program text,
  status public.earn_status not null default 'pending',
  abnormal boolean not null default false,
  submitted_by uuid not null references auth.users(id),
  reviewed_by uuid references auth.users(id),
  reviewed_at timestamptz,
  review_reason text,
  created_at timestamptz not null default now(),
  check ((status = 'pending' and reviewed_by is null) or status <> 'pending')
);

create table public.point_ledger (
  id uuid primary key default gen_random_uuid(),
  member_id uuid not null references public.members(id),
  type public.ledger_type not null,
  points_delta integer not null check (points_delta <> 0),
  balance_after integer not null check (balance_after >= 0),
  earn_request_id uuid references public.earn_requests(id),
  reference_id uuid,
  reason text not null,
  expires_at timestamptz,
  created_by uuid not null references auth.users(id),
  created_at timestamptz not null default now()
);

create table public.redemptions (
  id uuid primary key default gen_random_uuid(),
  member_id uuid not null references public.members(id),
  reward_id uuid not null references public.rewards(id),
  points_spent integer not null check (points_spent > 0),
  verification_method text not null check (char_length(verification_method) >= 3),
  verification_note text not null check (char_length(verification_note) >= 3),
  redeemed_by uuid not null references auth.users(id),
  redeemed_at timestamptz not null default now()
);

create table public.membership_audit_log (
  id bigint generated always as identity primary key,
  actor_id uuid references auth.users(id),
  action text not null,
  entity_type text not null,
  entity_id text,
  details jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);

create index membership_audit_actor_time on public.membership_audit_log(actor_id, created_at desc);
create index earn_requests_status_time on public.earn_requests(status, created_at desc);
create index point_ledger_member_time on public.point_ledger(member_id, created_at desc);

insert into public.program_users (user_id, display_name, role, active, can_redeem)
select user_id, split_part(email, '@', 1), 'manager', true, true from public.admin_users
on conflict (user_id) do update set role = 'manager', active = true, can_redeem = true;

insert into public.rewards (name, points_cost, voucher_value, conditions, valid_days, active, is_demo)
values
  ('Snack hoặc nước', 30, null, 'Áp dụng tại quầy PlayNest', 30, true, true),
  ('Voucher PlayNest 20.000đ', 60, 20000, 'Không quy đổi tiền mặt', 30, true, true),
  ('Voucher Galaxy 50.000đ', 120, 50000, 'Theo điều kiện của voucher', 30, true, true)
on conflict do nothing;

create or replace function public.membership_role()
returns public.staff_role language sql stable security definer set search_path = public
as $$ select role from public.program_users where user_id = auth.uid() and active limit 1 $$;

create or replace function public.mask_phone(p text)
returns text language sql immutable as $$ select left(p, 3) || '****' || right(p, 3) $$;

create or replace function public.normalize_phone(p text)
returns text language sql immutable as $$ select regexp_replace(trim(p), '[^0-9+]', '', 'g') $$;

create or replace function public.lookup_member(p_phone text)
returns table(id uuid, member_code text, masked_phone text, display_name text, available_points int, pending_points int, visit_count int)
language plpgsql security definer set search_path = public,extensions as $$
declare v_phone text := public.normalize_phone(p_phone); v_actor uuid := auth.uid();
begin
  if public.membership_role() is null then raise exception 'Không có quyền'; end if;
  if v_phone !~ '^(\+84|0)[0-9]{9,10}$' then raise exception 'Số điện thoại không hợp lệ'; end if;
  if (select count(*) from public.membership_audit_log where actor_id=v_actor and action='member_lookup' and created_at > now()-interval '1 minute') >= 15 then
    raise exception 'Tra cứu quá nhanh, vui lòng thử lại sau';
  end if;
  insert into public.membership_audit_log(actor_id,action,entity_type,details) values(v_actor,'member_lookup','member',jsonb_build_object('phone_hash',encode(digest(v_phone,'sha256'),'hex')));
  return query select m.id,m.member_code,public.mask_phone(m.phone_encrypted),m.display_name,m.available_points,m.pending_points,m.visit_count
  from public.members m where m.phone_hash=encode(digest(v_phone,'sha256'),'hex') and m.active;
end $$;

create or replace function public.create_member(p_phone text,p_name text,p_membership_consent boolean,p_marketing_consent boolean,p_policy_version text)
returns table(id uuid, member_code text, masked_phone text, display_name text, available_points int, pending_points int, visit_count int)
language plpgsql security definer set search_path=public,extensions as $$
declare v_phone text:=public.normalize_phone(p_phone); v_id uuid; v_actor uuid:=auth.uid();
begin
  if public.membership_role() is null then raise exception 'Không có quyền'; end if;
  if not p_membership_consent then raise exception 'Khách chưa đồng ý tham gia'; end if;
  if v_phone !~ '^(\+84|0)[0-9]{9,10}$' then raise exception 'Số điện thoại không hợp lệ'; end if;
  insert into public.members(phone_hash,phone_encrypted,display_name,created_by)
  values(encode(digest(v_phone,'sha256'),'hex'),v_phone,nullif(trim(p_name),''),v_actor) returning members.id into v_id;
  insert into public.member_consents(member_id,membership_consent,marketing_consent,policy_version,recorded_by)
  values(v_id,true,coalesce(p_marketing_consent,false),p_policy_version,v_actor);
  insert into public.membership_audit_log(actor_id,action,entity_type,entity_id) values(v_actor,'member_created','member',v_id::text);
  return query select * from public.lookup_member(v_phone);
exception when unique_violation then raise exception 'Số điện thoại đã là thành viên';
end $$;

create or replace function public.submit_earn_request(p_member_id uuid,p_invoice_code text,p_paid_amount int,p_eligible_amount int,p_occurred_at timestamptz,p_room_type text,p_applied_program text)
returns uuid language plpgsql security definer set search_path=public as $$
declare v_actor uuid:=auth.uid(); v_settings public.program_settings; v_points int; v_id uuid;
begin
  if public.membership_role() is null then raise exception 'Không có quyền'; end if;
  select * into v_settings from public.program_settings where id=true;
  v_points:=floor(p_eligible_amount::numeric/v_settings.spend_per_point);
  if v_points < 1 or p_eligible_amount>p_paid_amount then raise exception 'Số tiền đủ điều kiện không hợp lệ'; end if;
  insert into public.earn_requests(member_id,invoice_code,paid_amount,eligible_amount,points,occurred_at,room_type,applied_program,abnormal,submitted_by)
  values(p_member_id,upper(trim(p_invoice_code)),p_paid_amount,p_eligible_amount,v_points,p_occurred_at,p_room_type,p_applied_program,p_paid_amount>=v_settings.abnormal_invoice_amount,v_actor) returning id into v_id;
  update public.members set pending_points=pending_points+v_points,updated_at=now() where id=p_member_id;
  insert into public.membership_audit_log(actor_id,action,entity_type,entity_id,details) values(v_actor,'earn_submitted','earn_request',v_id::text,jsonb_build_object('points',v_points));
  return v_id;
exception when unique_violation then raise exception 'Hóa đơn đã được sử dụng';
end $$;

create or replace function public.review_earn_request(p_request_id uuid,p_approve boolean,p_reason text)
returns void language plpgsql security definer set search_path=public as $$
declare v_actor uuid:=auth.uid(); v_req public.earn_requests; v_balance int; v_expiry_months int;
begin
  if public.membership_role()<>'manager' then raise exception 'Chỉ quản lý được duyệt'; end if;
  select * into v_req from public.earn_requests where id=p_request_id for update;
  if v_req.status<>'pending' then raise exception 'Yêu cầu đã được xử lý'; end if;
  update public.members set pending_points=pending_points-v_req.points,
    available_points=available_points+(case when p_approve then v_req.points else 0 end),
    visit_count=visit_count+(case when p_approve then 1 else 0 end),updated_at=now()
  where id=v_req.member_id returning available_points into v_balance;
  update public.earn_requests set status=case when p_approve then 'approved' else 'rejected' end,reviewed_by=v_actor,reviewed_at=now(),review_reason=nullif(trim(p_reason),'') where id=p_request_id;
  if p_approve then select point_expiry_months into v_expiry_months from public.program_settings where id=true;
    insert into public.point_ledger(member_id,type,points_delta,balance_after,earn_request_id,reason,expires_at,created_by)
    values(v_req.member_id,'earn',v_req.points,v_balance,v_req.id,'Duyệt hóa đơn '||v_req.invoice_code,now()+make_interval(months=>v_expiry_months),v_actor); end if;
  insert into public.membership_audit_log(actor_id,action,entity_type,entity_id,details) values(v_actor,case when p_approve then 'earn_approved' else 'earn_rejected' end,'earn_request',p_request_id::text,jsonb_build_object('reason',p_reason));
end $$;

create or replace function public.redeem_reward(p_member_id uuid,p_reward_id uuid,p_method text,p_note text)
returns uuid language plpgsql security definer set search_path=public as $$
declare v_actor uuid:=auth.uid(); v_reward public.rewards; v_balance int; v_id uuid;
begin
  if not exists(select 1 from public.program_users where user_id=v_actor and active and (role='manager' or can_redeem)) then raise exception 'Không có quyền đổi quà'; end if;
  select * into v_reward from public.rewards where id=p_reward_id and active for share;
  if v_reward.id is null then raise exception 'Phần thưởng không hoạt động'; end if;
  update public.members set available_points=available_points-v_reward.points_cost,updated_at=now()
  where id=p_member_id and available_points>=v_reward.points_cost returning available_points into v_balance;
  if not found then raise exception 'Không đủ điểm'; end if;
  insert into public.redemptions(member_id,reward_id,points_spent,verification_method,verification_note,redeemed_by)
  values(p_member_id,p_reward_id,v_reward.points_cost,p_method,p_note,v_actor) returning id into v_id;
  insert into public.point_ledger(member_id,type,points_delta,balance_after,reference_id,reason,created_by)
  values(p_member_id,'redeem',-v_reward.points_cost,v_balance,v_id,'Đổi '||v_reward.name,v_actor);
  insert into public.membership_audit_log(actor_id,action,entity_type,entity_id) values(v_actor,'reward_redeemed','redemption',v_id::text);
  return v_id;
end $$;

create or replace function public.membership_dashboard(p_from timestamptz default date_trunc('month',now()),p_to timestamptz default now())
returns jsonb language plpgsql security definer set search_path=public as $$
begin
  if public.membership_role()<>'manager' then raise exception 'Chỉ quản lý được xem báo cáo'; end if;
  return jsonb_build_object(
    'total_members',(select count(*) from public.members where not is_demo),
    'new_members',(select count(*) from public.members where not is_demo and created_at between p_from and p_to),
    'visits',(select count(*) from public.earn_requests where status='approved' and not exists(select 1 from public.members m where m.id=member_id and m.is_demo) and reviewed_at between p_from and p_to),
    'returning_members',(select count(*) from (select member_id from public.earn_requests where status='approved' group by member_id having count(*)>1) r),
    'pending',(select count(*) from public.earn_requests where status='pending'),
    'points_earned',(select coalesce(sum(points_delta),0) from public.point_ledger where points_delta>0 and created_at between p_from and p_to),
    'points_redeemed',(select coalesce(-sum(points_delta),0) from public.point_ledger where type='redeem' and created_at between p_from and p_to),
    'rewards_redeemed',(select count(*) from public.redemptions where redeemed_at between p_from and p_to),
    'spend',(select coalesce(sum(eligible_amount),0) from public.earn_requests where status='approved' and reviewed_at between p_from and p_to),
    'abnormal',(select count(*) from public.earn_requests where abnormal and created_at between p_from and p_to));
end $$;

create or replace function public.update_program_settings(p_spend_per_point int,p_point_expiry_months int,p_abnormal_invoice_amount int,p_return_bonus_points int,p_return_within_days int,p_policy_version text)
returns void language plpgsql security definer set search_path=public as $$
begin
  if public.membership_role()<>'manager' then raise exception 'Chỉ quản lý được đổi cấu hình'; end if;
  update public.program_settings set spend_per_point=p_spend_per_point,point_expiry_months=p_point_expiry_months,
    abnormal_invoice_amount=p_abnormal_invoice_amount,return_bonus_points=p_return_bonus_points,return_within_days=p_return_within_days,
    policy_version=p_policy_version,updated_by=auth.uid(),updated_at=now() where id=true;
  insert into public.membership_audit_log(actor_id,action,entity_type,entity_id,details)
  values(auth.uid(),'settings_updated','program_settings','main',jsonb_build_object('spend_per_point',p_spend_per_point,'expiry_months',p_point_expiry_months));
end $$;

create or replace function public.save_reward(p_id uuid,p_name text,p_points_cost int,p_voucher_value int,p_conditions text,p_valid_days int,p_active boolean)
returns uuid language plpgsql security definer set search_path=public as $$
declare v_id uuid;
begin
  if public.membership_role()<>'manager' then raise exception 'Chỉ quản lý được sửa phần thưởng'; end if;
  if p_id is null then
    insert into public.rewards(name,points_cost,voucher_value,conditions,valid_days,active,created_by)
    values(trim(p_name),p_points_cost,p_voucher_value,nullif(trim(p_conditions),''),p_valid_days,p_active,auth.uid()) returning id into v_id;
  else
    update public.rewards set name=trim(p_name),points_cost=p_points_cost,voucher_value=p_voucher_value,
      conditions=nullif(trim(p_conditions),''),valid_days=p_valid_days,active=p_active,updated_at=now() where id=p_id returning id into v_id;
    if v_id is null then raise exception 'Không tìm thấy phần thưởng'; end if;
  end if;
  insert into public.membership_audit_log(actor_id,action,entity_type,entity_id) values(auth.uid(),'reward_saved','reward',v_id::text);
  return v_id;
end $$;

create or replace function public.save_staff_access(p_email text,p_display_name text,p_role public.staff_role,p_active boolean,p_can_redeem boolean)
returns void language plpgsql security definer set search_path=public,auth as $$
declare v_user uuid;
begin
  if public.membership_role()<>'manager' then raise exception 'Chỉ quản lý được cấp quyền nhân viên'; end if;
  select id into v_user from auth.users where lower(email)=lower(trim(p_email)) limit 1;
  if v_user is null then raise exception 'Hãy tạo tài khoản trong Supabase Auth trước'; end if;
  if v_user=auth.uid() and (not p_active or p_role<>'manager') then raise exception 'Không thể tự hạ quyền hoặc khóa tài khoản quản lý đang đăng nhập'; end if;
  insert into public.program_users(user_id,display_name,role,active,can_redeem,email)
  values(v_user,trim(p_display_name),p_role,p_active,p_can_redeem,lower(trim(p_email)))
  on conflict(user_id) do update set display_name=excluded.display_name,role=excluded.role,active=excluded.active,can_redeem=excluded.can_redeem,email=excluded.email,updated_at=now();
  insert into public.membership_audit_log(actor_id,action,entity_type,entity_id,details)
  values(auth.uid(),'staff_access_saved','program_user',v_user::text,jsonb_build_object('role',p_role,'active',p_active));
end $$;

create or replace function public.adjust_member_points(p_member_id uuid,p_points_delta int,p_reason text)
returns void language plpgsql security definer set search_path=public as $$
declare v_balance int;
begin
  if public.membership_role()<>'manager' then raise exception 'Chỉ quản lý được điều chỉnh điểm'; end if;
  if p_points_delta=0 or char_length(trim(p_reason))<5 then raise exception 'Cần số điểm và lý do hợp lệ'; end if;
  update public.members set available_points=available_points+p_points_delta,updated_at=now()
  where id=p_member_id and available_points+p_points_delta>=0 returning available_points into v_balance;
  if not found then raise exception 'Điều chỉnh làm số dư âm hoặc không tìm thấy thành viên'; end if;
  insert into public.point_ledger(member_id,type,points_delta,balance_after,reason,created_by)
  values(p_member_id,'adjustment',p_points_delta,v_balance,trim(p_reason),auth.uid());
  insert into public.membership_audit_log(actor_id,action,entity_type,entity_id,details)
  values(auth.uid(),'points_adjusted','member',p_member_id::text,jsonb_build_object('delta',p_points_delta,'reason',p_reason));
end $$;

create or replace function public.reverse_earn_request(p_request_id uuid,p_reason text)
returns void language plpgsql security definer set search_path=public as $$
declare v_req public.earn_requests; v_balance int;
begin
  if public.membership_role()<>'manager' then raise exception 'Chỉ quản lý được đảo giao dịch'; end if;
  if char_length(trim(p_reason))<5 then raise exception 'Cần lý do hoàn/hủy'; end if;
  select * into v_req from public.earn_requests where id=p_request_id for update;
  if v_req.status<>'approved' then raise exception 'Chỉ đảo yêu cầu đã duyệt'; end if;
  update public.members set available_points=available_points-v_req.points,visit_count=greatest(visit_count-1,0),updated_at=now()
  where id=v_req.member_id and available_points>=v_req.points returning available_points into v_balance;
  if not found then raise exception 'Không đủ điểm để đảo; cần tạo điều chỉnh có đối soát'; end if;
  update public.earn_requests set status='reversed',review_reason=trim(p_reason) where id=p_request_id;
  insert into public.point_ledger(member_id,type,points_delta,balance_after,earn_request_id,reason,created_by)
  values(v_req.member_id,'reversal',-v_req.points,v_balance,v_req.id,trim(p_reason),auth.uid());
  insert into public.membership_audit_log(actor_id,action,entity_type,entity_id,details)
  values(auth.uid(),'earn_reversed','earn_request',p_request_id::text,jsonb_build_object('reason',p_reason));
end $$;

-- The browser receives EXECUTE access only. It never receives table-wide member access.
alter table public.program_users enable row level security;
alter table public.members enable row level security;
alter table public.member_consents enable row level security;
alter table public.program_settings enable row level security;
alter table public.rewards enable row level security;
alter table public.earn_requests enable row level security;
alter table public.point_ledger enable row level security;
alter table public.redemptions enable row level security;
alter table public.membership_audit_log enable row level security;
revoke all on public.program_users,public.members,public.member_consents,public.program_settings,public.rewards,public.earn_requests,public.point_ledger,public.redemptions,public.membership_audit_log from anon,authenticated;
grant execute on function public.lookup_member(text),public.create_member(text,text,boolean,boolean,text),public.submit_earn_request(uuid,text,int,int,timestamptz,text,text),public.review_earn_request(uuid,boolean,text),public.redeem_reward(uuid,uuid,text,text),public.membership_dashboard(timestamptz,timestamptz),public.update_program_settings(int,int,int,int,int,text),public.save_reward(uuid,text,int,int,text,int,boolean),public.save_staff_access(text,text,public.staff_role,boolean,boolean),public.adjust_member_points(uuid,int,text),public.reverse_earn_request(uuid,text) to authenticated;
grant select on public.rewards,public.program_settings to authenticated;
grant select on public.program_users to authenticated;
create policy "Active users read rewards" on public.rewards for select to authenticated using (active and public.membership_role() is not null);
create policy "Active users read settings" on public.program_settings for select to authenticated using (public.membership_role() is not null);

-- Manager-only operational views avoid exposing raw phone numbers.
create or replace view public.pending_earn_requests with (security_invoker=true) as
select e.id,e.invoice_code,e.paid_amount,e.eligible_amount,e.points,e.occurred_at,e.room_type,e.applied_program,e.abnormal,e.created_at,
 m.member_code,m.display_name,public.mask_phone(m.phone_encrypted) masked_phone,u.display_name submitted_by_name
from public.earn_requests e join public.members m on m.id=e.member_id join public.program_users u on u.user_id=e.submitted_by where e.status='pending';
grant select on public.pending_earn_requests to authenticated;
create policy "Managers read pending earns" on public.earn_requests for select to authenticated using (public.membership_role()='manager');
create policy "Managers read members for pending view" on public.members for select to authenticated using (public.membership_role()='manager');
create policy "Managers read program users" on public.program_users for select to authenticated using (public.membership_role()='manager' or user_id=auth.uid());

comment on table public.members is 'PII: never grant table-wide access to staff; use exact-match RPC.';
