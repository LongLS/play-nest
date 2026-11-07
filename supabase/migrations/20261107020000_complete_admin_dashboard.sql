-- Complete PlayNest operational dashboard APIs. Apply after 20261107010000.

alter table public.survey_responses
  add column if not exists management_status text not null default 'new',
  add column if not exists internal_note text,
  add column if not exists viewed_at timestamptz,
  add column if not exists processed_at timestamptz,
  add column if not exists management_updated_by uuid references auth.users(id),
  add column if not exists management_updated_at timestamptz,
  add column if not exists deleted_at timestamptz;

alter table public.survey_responses drop constraint if exists survey_management_status_check;
alter table public.survey_responses add constraint survey_management_status_check
  check (management_status in ('new','viewed','processed','archived'));

create index if not exists survey_management_filter_idx
  on public.survey_responses(management_status,created_at desc) where deleted_at is null;

alter table public.members
  add column if not exists phone_verified_at timestamptz,
  add column if not exists phone_verification_method text;

alter table public.program_users add column if not exists email text;
update public.program_users p set email=u.email from auth.users u where u.id=p.user_id and p.email is distinct from u.email;

create or replace function public.save_staff_access(p_email text,p_display_name text,p_role public.staff_role,p_active boolean,p_can_redeem boolean)
returns void language plpgsql security definer set search_path=public,auth as $$
declare v_user uuid;
begin
  if public.membership_role()<>'manager' then raise exception 'Chỉ quản lý được cấp quyền nhân viên'; end if;
  select id into v_user from auth.users where lower(email)=lower(trim(p_email)) limit 1;
  if v_user is null then raise exception 'Hãy tạo tài khoản trong Supabase Auth trước'; end if;
  if v_user=auth.uid() and (not p_active or p_role<>'manager') then raise exception 'Không thể tự hạ quyền hoặc khóa tài khoản quản lý đang đăng nhập'; end if;
  insert into public.program_users(user_id,email,display_name,role,active,can_redeem)
  values(v_user,lower(trim(p_email)),trim(p_display_name),p_role,p_active,p_can_redeem)
  on conflict(user_id) do update set email=excluded.email,display_name=excluded.display_name,role=excluded.role,active=excluded.active,can_redeem=excluded.can_redeem,updated_at=now();
  insert into public.membership_audit_log(actor_id,action,entity_type,entity_id,details)
  values(auth.uid(),'staff_access_saved','program_user',v_user::text,jsonb_build_object('role',p_role,'active',p_active));
end $$;

create or replace function public.admin_survey_list(
  p_search text default null,p_rating int default null,p_status text default null,
  p_from timestamptz default null,p_to timestamptz default null,p_page int default 1,p_page_size int default 20)
returns jsonb language plpgsql security definer set search_path=public as $$
declare v_offset int; v_total bigint; v_rows jsonb; v_summary jsonb;
begin
  if public.membership_role()<>'manager' and not exists(select 1 from public.admin_users where user_id=auth.uid()) then raise exception 'Không có quyền quản lý khảo sát'; end if;
  p_page:=greatest(coalesce(p_page,1),1); p_page_size:=least(greatest(coalesce(p_page_size,20),1),100); v_offset:=(p_page-1)*p_page_size;
  select count(*) into v_total from public.survey_responses s where s.deleted_at is null
    and (p_rating is null or s.service_rating=p_rating)
    and (p_status is null or p_status='' or s.management_status=p_status)
    and (p_from is null or s.created_at>=p_from) and (p_to is null or s.created_at<p_to)
    and (p_search is null or p_search='' or coalesce(s.staff_name,'') ilike '%'||p_search||'%' or s.answers::text ilike '%'||p_search||'%');
  select jsonb_build_object('total',count(*),'service_avg',round(avg(s.service_rating)::numeric,1),'food_avg',round(avg(s.food_rating)::numeric,1),'staff_avg',round(avg(s.staff_rating)::numeric,1)) into v_summary
  from public.survey_responses s where s.deleted_at is null
    and (p_rating is null or s.service_rating=p_rating) and (p_status is null or p_status='' or s.management_status=p_status)
    and (p_from is null or s.created_at>=p_from) and (p_to is null or s.created_at<p_to)
    and (p_search is null or p_search='' or coalesce(s.staff_name,'') ilike '%'||p_search||'%' or s.answers::text ilike '%'||p_search||'%');
  select coalesce(jsonb_agg(to_jsonb(x)),'[]'::jsonb) into v_rows from (
    select s.id,s.created_at,s.service_rating,s.food_rating,s.staff_name,s.staff_rating,s.answers,
      s.management_status,s.internal_note,s.viewed_at,s.processed_at
    from public.survey_responses s where s.deleted_at is null
      and (p_rating is null or s.service_rating=p_rating)
      and (p_status is null or p_status='' or s.management_status=p_status)
      and (p_from is null or s.created_at>=p_from) and (p_to is null or s.created_at<p_to)
      and (p_search is null or p_search='' or coalesce(s.staff_name,'') ilike '%'||p_search||'%' or s.answers::text ilike '%'||p_search||'%')
    order by s.created_at desc limit p_page_size offset v_offset) x;
  return jsonb_build_object('rows',v_rows,'total',v_total,'page',p_page,'page_size',p_page_size,'summary',v_summary);
end $$;

create or replace function public.admin_update_survey(p_id uuid,p_status text,p_note text)
returns void language plpgsql security definer set search_path=public,extensions as $$
begin
  if public.membership_role()<>'manager' and not exists(select 1 from public.admin_users where user_id=auth.uid()) then raise exception 'Không có quyền'; end if;
  if p_status not in ('new','viewed','processed','archived') then raise exception 'Trạng thái không hợp lệ'; end if;
  update public.survey_responses set management_status=p_status,internal_note=nullif(trim(p_note),''),
    viewed_at=case when p_status in ('viewed','processed') then coalesce(viewed_at,now()) else viewed_at end,
    processed_at=case when p_status='processed' then coalesce(processed_at,now()) else null end,
    management_updated_by=auth.uid(),management_updated_at=now() where id=p_id and deleted_at is null;
  if not found then raise exception 'Không tìm thấy khảo sát'; end if;
  insert into public.membership_audit_log(actor_id,action,entity_type,entity_id,details) values(auth.uid(),'survey_updated','survey',p_id::text,jsonb_build_object('status',p_status));
end $$;

create or replace function public.admin_archive_survey(p_id uuid,p_reason text)
returns void language plpgsql security definer set search_path=public,extensions as $$
begin
  if public.membership_role()<>'manager' then raise exception 'Chỉ quản lý được lưu trữ khảo sát'; end if;
  if char_length(trim(p_reason))<5 then raise exception 'Cần nhập lý do'; end if;
  update public.survey_responses set management_status='archived',deleted_at=now(),internal_note=trim(p_reason),management_updated_by=auth.uid(),management_updated_at=now() where id=p_id and deleted_at is null;
  if not found then raise exception 'Không tìm thấy khảo sát'; end if;
  insert into public.membership_audit_log(actor_id,action,entity_type,entity_id,details) values(auth.uid(),'survey_archived','survey',p_id::text,jsonb_build_object('reason',p_reason));
end $$;

create or replace function public.admin_member_list(
  p_search text default null,p_active boolean default null,p_from timestamptz default null,p_to timestamptz default null,
  p_min_points int default null,p_max_points int default null,p_returning boolean default null,p_page int default 1,p_page_size int default 20)
returns jsonb language plpgsql security definer set search_path=public as $$
declare v_offset int; v_total bigint; v_rows jsonb;
begin
  if public.membership_role()<>'manager' then raise exception 'Chỉ quản lý được xem danh sách thành viên'; end if;
  p_page:=greatest(coalesce(p_page,1),1); p_page_size:=least(greatest(coalesce(p_page_size,20),1),100); v_offset:=(p_page-1)*p_page_size;
  select count(*) into v_total from public.members m where not m.is_demo
    and (p_search is null or p_search='' or m.member_code ilike '%'||p_search||'%' or coalesce(m.display_name,'') ilike '%'||p_search||'%')
    and (p_active is null or m.active=p_active) and (p_from is null or m.created_at>=p_from) and (p_to is null or m.created_at<p_to)
    and (p_min_points is null or m.available_points>=p_min_points) and (p_max_points is null or m.available_points<=p_max_points)
    and (p_returning is null or (m.visit_count>1)=p_returning);
  select coalesce(jsonb_agg(to_jsonb(x)),'[]'::jsonb) into v_rows from (
    select m.id,m.member_code,m.display_name,public.mask_phone(m.phone_encrypted) masked_phone,m.available_points,m.pending_points,m.visit_count,
      coalesce((select sum(e.eligible_amount) from public.earn_requests e where e.member_id=m.id and e.status='approved'),0) total_spend,
      (select max(e.occurred_at) from public.earn_requests e where e.member_id=m.id and e.status='approved') last_visit_at,
      m.active,m.phone_verified_at,m.created_at
    from public.members m where not m.is_demo
      and (p_search is null or p_search='' or m.member_code ilike '%'||p_search||'%' or coalesce(m.display_name,'') ilike '%'||p_search||'%')
      and (p_active is null or m.active=p_active) and (p_from is null or m.created_at>=p_from) and (p_to is null or m.created_at<p_to)
      and (p_min_points is null or m.available_points>=p_min_points) and (p_max_points is null or m.available_points<=p_max_points)
      and (p_returning is null or (m.visit_count>1)=p_returning)
    order by m.created_at desc limit p_page_size offset v_offset) x;
  return jsonb_build_object('rows',v_rows,'total',v_total,'page',p_page,'page_size',p_page_size);
end $$;

create or replace function public.admin_member_detail(p_member_id uuid)
returns jsonb language plpgsql security definer set search_path=public as $$
declare v_member jsonb;
begin
  if public.membership_role()<>'manager' then raise exception 'Chỉ quản lý được xem chi tiết'; end if;
  select jsonb_build_object('id',m.id,'member_code',m.member_code,'display_name',m.display_name,'masked_phone',public.mask_phone(m.phone_encrypted),
    'available_points',m.available_points,'pending_points',m.pending_points,'visit_count',m.visit_count,'active',m.active,'phone_verified_at',m.phone_verified_at,'phone_verification_method',m.phone_verification_method,'created_at',m.created_at,
    'visits',coalesce((select jsonb_agg(to_jsonb(v) order by v.occurred_at desc) from (select e.id,e.invoice_code,e.occurred_at,e.eligible_amount,e.points,e.status,e.review_reason from public.earn_requests e where e.member_id=m.id order by e.occurred_at desc limit 100) v),'[]'::jsonb),
    'ledger',coalesce((select jsonb_agg(to_jsonb(l) order by l.created_at desc) from (select p.type,p.points_delta,p.balance_after,p.reason,p.expires_at,p.created_at from public.point_ledger p where p.member_id=m.id order by p.created_at desc limit 100) l),'[]'::jsonb),
    'redemptions',coalesce((select jsonb_agg(to_jsonb(r) order by r.redeemed_at desc) from (select d.id,w.name reward_name,d.points_spent,d.verification_method,d.redeemed_at,u.display_name staff_name from public.redemptions d join public.rewards w on w.id=d.reward_id join public.program_users u on u.user_id=d.redeemed_by where d.member_id=m.id order by d.redeemed_at desc limit 100) r),'[]'::jsonb),
    'audit',coalesce((select jsonb_agg(to_jsonb(a) order by a.created_at desc) from (select action,details,created_at from public.membership_audit_log where entity_id=m.id::text order by created_at desc limit 100) a),'[]'::jsonb)) into v_member
  from public.members m where m.id=p_member_id;
  if v_member is null then raise exception 'Không tìm thấy thành viên'; end if;
  return v_member;
end $$;

create or replace function public.admin_update_member(p_member_id uuid,p_display_name text,p_active boolean,p_reason text)
returns void language plpgsql security definer set search_path=public as $$
begin
  if public.membership_role()<>'manager' then raise exception 'Chỉ quản lý được sửa thành viên'; end if;
  if char_length(trim(p_reason))<5 then raise exception 'Cần nhập lý do thay đổi'; end if;
  update public.members set display_name=nullif(trim(p_display_name),''),active=p_active,updated_at=now() where id=p_member_id;
  if not found then raise exception 'Không tìm thấy thành viên'; end if;
  insert into public.membership_audit_log(actor_id,action,entity_type,entity_id,details) values(auth.uid(),'member_updated','member',p_member_id::text,jsonb_build_object('active',p_active,'reason',p_reason));
end $$;

create or replace function public.verify_member_phone(p_member_id uuid,p_method text,p_note text)
returns void language plpgsql security definer set search_path=public as $$
begin
  if public.membership_role() is null then raise exception 'Không có quyền'; end if;
  if char_length(trim(p_method))<3 or char_length(trim(p_note))<5 then raise exception 'Cần phương thức và ghi chú xác minh'; end if;
  update public.members set phone_verified_at=now(),phone_verification_method=trim(p_method),updated_at=now() where id=p_member_id and active;
  if not found then raise exception 'Không tìm thấy thành viên hoạt động'; end if;
  insert into public.membership_audit_log(actor_id,action,entity_type,entity_id,details) values(auth.uid(),'phone_verified','member',p_member_id::text,jsonb_build_object('method',p_method,'note',p_note));
end $$;

create or replace function public.admin_change_member_phone(p_member_id uuid,p_new_phone text,p_method text,p_note text)
returns void language plpgsql security definer set search_path=public,extensions as $$
declare v_phone text:=public.normalize_phone(p_new_phone);
begin
  if public.membership_role()<>'manager' then raise exception 'Chỉ quản lý được đổi số điện thoại'; end if;
  if v_phone !~ '^(\+84|0)[0-9]{9,10}$' then raise exception 'Số điện thoại không hợp lệ'; end if;
  if char_length(trim(p_method))<3 or char_length(trim(p_note))<10 then raise exception 'Cần bằng chứng xác minh và ghi chú rõ ràng'; end if;
  update public.members set phone_encrypted=v_phone,phone_hash=encode(digest(v_phone,'sha256'),'hex'),phone_verified_at=now(),phone_verification_method=trim(p_method),updated_at=now() where id=p_member_id;
  if not found then raise exception 'Không tìm thấy thành viên'; end if;
  insert into public.membership_audit_log(actor_id,action,entity_type,entity_id,details) values(auth.uid(),'member_phone_changed','member',p_member_id::text,jsonb_build_object('method',p_method,'note',p_note));
exception when unique_violation then raise exception 'Số điện thoại đã thuộc thành viên khác';
end $$;

create or replace function public.admin_anonymize_member(p_member_id uuid,p_reason text)
returns void language plpgsql security definer set search_path=public,extensions as $$
begin
  if public.membership_role()<>'manager' then raise exception 'Chỉ quản lý được ẩn danh'; end if;
  if char_length(trim(p_reason))<10 then raise exception 'Cần lý do ẩn danh rõ ràng'; end if;
  if exists(select 1 from public.earn_requests where member_id=p_member_id and status='pending') then raise exception 'Còn yêu cầu tích điểm chờ xử lý'; end if;
  update public.members set display_name=null,phone_encrypted='ANONYMIZED',phone_hash=encode(digest(gen_random_uuid()::text,'sha256'),'hex'),active=false,updated_at=now() where id=p_member_id;
  if not found then raise exception 'Không tìm thấy thành viên'; end if;
  update public.member_consents set membership_consent=false,marketing_consent=false where member_id=p_member_id;
  insert into public.membership_audit_log(actor_id,action,entity_type,entity_id,details) values(auth.uid(),'member_anonymized','member',p_member_id::text,jsonb_build_object('reason',p_reason));
end $$;

create or replace function public.earn_request_list(
  p_status text default null,p_search text default null,p_from timestamptz default null,p_to timestamptz default null,p_page int default 1,p_page_size int default 20)
returns jsonb language plpgsql security definer set search_path=public as $$
declare v_role public.staff_role:=public.membership_role(); v_offset int; v_total bigint; v_rows jsonb;
begin
  if v_role is null then raise exception 'Không có quyền'; end if;
  p_page:=greatest(coalesce(p_page,1),1);p_page_size:=least(greatest(coalesce(p_page_size,20),1),100);v_offset:=(p_page-1)*p_page_size;
  select count(*) into v_total from public.earn_requests e join public.members m on m.id=e.member_id
  where (v_role='manager' or e.submitted_by=auth.uid()) and (p_status is null or p_status='' or e.status::text=p_status)
    and (p_search is null or p_search='' or e.invoice_code ilike '%'||p_search||'%' or m.member_code ilike '%'||p_search||'%')
    and (p_from is null or e.created_at>=p_from) and (p_to is null or e.created_at<p_to);
  select coalesce(jsonb_agg(to_jsonb(x)),'[]'::jsonb) into v_rows from (
    select e.id,e.invoice_code,m.member_code,m.display_name,e.eligible_amount,e.points,e.occurred_at,u.display_name submitted_by_name,e.created_at,e.status,e.abnormal,e.review_reason
    from public.earn_requests e join public.members m on m.id=e.member_id join public.program_users u on u.user_id=e.submitted_by
    where (v_role='manager' or e.submitted_by=auth.uid()) and (p_status is null or p_status='' or e.status::text=p_status)
      and (p_search is null or p_search='' or e.invoice_code ilike '%'||p_search||'%' or m.member_code ilike '%'||p_search||'%')
      and (p_from is null or e.created_at>=p_from) and (p_to is null or e.created_at<p_to)
    order by e.created_at desc limit p_page_size offset v_offset) x;
  return jsonb_build_object('rows',v_rows,'total',v_total,'page',p_page,'page_size',p_page_size);
end $$;

create or replace function public.cancel_earn_request(p_request_id uuid,p_reason text)
returns void language plpgsql security definer set search_path=public as $$
declare v_req public.earn_requests;
begin
  select * into v_req from public.earn_requests where id=p_request_id for update;
  if v_req.status<>'pending' then raise exception 'Chỉ hủy được yêu cầu đang chờ'; end if;
  if v_req.submitted_by<>auth.uid() and public.membership_role()<>'manager' then raise exception 'Không có quyền hủy'; end if;
  if char_length(trim(p_reason))<5 then raise exception 'Cần nhập lý do hủy'; end if;
  update public.members set pending_points=pending_points-v_req.points,updated_at=now() where id=v_req.member_id;
  update public.earn_requests set status='rejected',review_reason='HỦY: '||trim(p_reason),reviewed_by=auth.uid(),reviewed_at=now() where id=p_request_id;
  insert into public.membership_audit_log(actor_id,action,entity_type,entity_id,details) values(auth.uid(),'earn_cancelled','earn_request',p_request_id::text,jsonb_build_object('reason',p_reason));
end $$;

create or replace function public.redemption_list(p_search text default null,p_from timestamptz default null,p_to timestamptz default null,p_page int default 1,p_page_size int default 20)
returns jsonb language plpgsql security definer set search_path=public as $$
declare v_role public.staff_role:=public.membership_role();v_offset int;v_total bigint;v_rows jsonb;
begin
  if v_role is null then raise exception 'Không có quyền'; end if;
  p_page:=greatest(coalesce(p_page,1),1);p_page_size:=least(greatest(coalesce(p_page_size,20),1),100);v_offset:=(p_page-1)*p_page_size;
  select count(*) into v_total from public.redemptions d join public.members m on m.id=d.member_id join public.rewards r on r.id=d.reward_id
    where (v_role='manager' or d.redeemed_by=auth.uid()) and (p_search is null or p_search='' or m.member_code ilike '%'||p_search||'%' or r.name ilike '%'||p_search||'%') and (p_from is null or d.redeemed_at>=p_from) and (p_to is null or d.redeemed_at<p_to);
  select coalesce(jsonb_agg(to_jsonb(x)),'[]'::jsonb) into v_rows from (
    select d.id,m.member_code,m.display_name,r.name reward_name,d.points_spent,d.verification_method,d.verification_note,u.display_name redeemed_by_name,d.redeemed_at
    from public.redemptions d join public.members m on m.id=d.member_id join public.rewards r on r.id=d.reward_id join public.program_users u on u.user_id=d.redeemed_by
    where (v_role='manager' or d.redeemed_by=auth.uid()) and (p_search is null or p_search='' or m.member_code ilike '%'||p_search||'%' or r.name ilike '%'||p_search||'%') and (p_from is null or d.redeemed_at>=p_from) and (p_to is null or d.redeemed_at<p_to)
    order by d.redeemed_at desc limit p_page_size offset v_offset) x;
  return jsonb_build_object('rows',v_rows,'total',v_total,'page',p_page,'page_size',p_page_size);
end $$;

create or replace function public.admin_activity_list(p_search text default null,p_page int default 1,p_page_size int default 20)
returns jsonb language plpgsql security definer set search_path=public as $$
declare v_offset int;v_total bigint;v_rows jsonb;
begin
  if public.membership_role()<>'manager' then raise exception 'Chỉ quản lý được xem nhật ký'; end if;
  p_page:=greatest(coalesce(p_page,1),1);p_page_size:=least(greatest(coalesce(p_page_size,20),1),100);v_offset:=(p_page-1)*p_page_size;
  select count(*) into v_total from public.membership_audit_log a left join public.program_users u on u.user_id=a.actor_id where p_search is null or p_search='' or a.action ilike '%'||p_search||'%' or coalesce(u.display_name,'') ilike '%'||p_search||'%';
  select coalesce(jsonb_agg(to_jsonb(x)),'[]'::jsonb) into v_rows from (select a.id,a.action,a.entity_type,a.entity_id,a.details,a.created_at,u.display_name actor_name from public.membership_audit_log a left join public.program_users u on u.user_id=a.actor_id where p_search is null or p_search='' or a.action ilike '%'||p_search||'%' or coalesce(u.display_name,'') ilike '%'||p_search||'%' order by a.created_at desc limit p_page_size offset v_offset) x;
  return jsonb_build_object('rows',v_rows,'total',v_total,'page',p_page,'page_size',p_page_size);
end $$;

create or replace function public.admin_overview_series(p_from timestamptz,p_to timestamptz)
returns jsonb language plpgsql security definer set search_path=public as $$
begin
  if public.membership_role()<>'manager' then raise exception 'Chỉ quản lý được xem báo cáo'; end if;
  return jsonb_build_object(
    'daily',coalesce((select jsonb_agg(to_jsonb(x) order by x."day") from (
      select report_date::date as "day",
        (select count(*) from public.members m where not m.is_demo and m.created_at>=report_date and m.created_at<report_date+interval '1 day') new_members,
        (select count(*) from public.earn_requests e where e.status='approved' and e.reviewed_at>=report_date and e.reviewed_at<report_date+interval '1 day') visits,
        (select coalesce(sum(greatest(l.points_delta,0)),0) from public.point_ledger l where l.created_at>=report_date and l.created_at<report_date+interval '1 day') points_earned,
        (select coalesce(-sum(least(l.points_delta,0)),0) from public.point_ledger l where l.type='redeem' and l.created_at>=report_date and l.created_at<report_date+interval '1 day') points_used
      from generate_series(date_trunc('day',p_from),date_trunc('day',p_to),interval '1 day') as series(report_date)) x),'[]'::jsonb),
    'top_rewards',coalesce((select jsonb_agg(to_jsonb(r) order by r.redemptions desc) from (
      select w.name,count(*) redemptions from public.redemptions d join public.rewards w on w.id=d.reward_id where d.redeemed_at between p_from and p_to group by w.id,w.name order by count(*) desc limit 5) r),'[]'::jsonb),
    'recent_activity',coalesce((select jsonb_agg(to_jsonb(a) order by a.created_at desc) from (
      select l.action,l.entity_type,l.created_at,u.display_name actor_name from public.membership_audit_log l left join public.program_users u on u.user_id=l.actor_id order by l.created_at desc limit 8) a),'[]'::jsonb)
  );
end $$;

create or replace function public.membership_dashboard(p_from timestamptz default date_trunc('month',now()),p_to timestamptz default now())
returns jsonb language plpgsql security definer set search_path=public as $$
begin
  if public.membership_role()<>'manager' then raise exception 'Chỉ quản lý được xem báo cáo'; end if;
  return jsonb_build_object(
    'total_members',(select count(*) from public.members where not is_demo),
    'new_members',(select count(*) from public.members where not is_demo and created_at between p_from and p_to),
    'visits',(select count(*) from public.earn_requests e join public.members m on m.id=e.member_id where e.status='approved' and not m.is_demo and e.reviewed_at between p_from and p_to),
    'returning_members',(select count(*) from (select e.member_id from public.earn_requests e join public.members m on m.id=e.member_id where e.status='approved' and not m.is_demo group by e.member_id having count(*)>1) r),
    'pending',(select count(*) from public.earn_requests where status='pending'),
    'pending_points',(select coalesce(sum(points),0) from public.earn_requests where status='pending'),
    'rejected',(select count(*) from public.earn_requests where status='rejected' and reviewed_at between p_from and p_to),
    'points_earned',(select coalesce(sum(points_delta),0) from public.point_ledger where points_delta>0 and created_at between p_from and p_to),
    'points_redeemed',(select coalesce(-sum(points_delta),0) from public.point_ledger where type='redeem' and created_at between p_from and p_to),
    'rewards_redeemed',(select count(*) from public.redemptions where redeemed_at between p_from and p_to),
    'spend',(select coalesce(sum(eligible_amount),0) from public.earn_requests where status='approved' and reviewed_at between p_from and p_to),
    'abnormal',(select count(*) from public.earn_requests where abnormal and created_at between p_from and p_to));
end $$;

grant execute on function public.admin_survey_list(text,int,text,timestamptz,timestamptz,int,int),public.admin_update_survey(uuid,text,text),public.admin_archive_survey(uuid,text),
  public.admin_member_list(text,boolean,timestamptz,timestamptz,int,int,boolean,int,int),public.admin_member_detail(uuid),public.admin_update_member(uuid,text,boolean,text),public.verify_member_phone(uuid,text,text),public.admin_change_member_phone(uuid,text,text,text),public.admin_anonymize_member(uuid,text),
  public.earn_request_list(text,text,timestamptz,timestamptz,int,int),public.cancel_earn_request(uuid,text),public.redemption_list(text,timestamptz,timestamptz,int,int),public.admin_activity_list(text,int,int),public.admin_overview_series(timestamptz,timestamptz)
to authenticated;
