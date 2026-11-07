-- Customer login uses a phone-derived private Auth alias and a temporary password.
alter table public.members add column if not exists must_change_password boolean not null default false;

create or replace function public.customer_club_profile()
returns jsonb language plpgsql security definer set search_path=public,extensions as $$
declare v_member public.members;
begin
  select * into v_member from public.members where auth_user_id=auth.uid() and active;
  if v_member.id is null then return null; end if;
  return jsonb_build_object(
    'id',v_member.id,'member_code',v_member.member_code,'display_name',v_member.display_name,'must_change_password',v_member.must_change_password,
    'masked_phone',public.mask_phone(v_member.phone_encrypted),'available_points',v_member.available_points,
    'pending_points',v_member.pending_points,'lifetime_points',v_member.lifetime_points,'created_at',v_member.created_at,
    'marketing_consent',coalesce((select marketing_consent from public.member_consents where member_id=v_member.id order by consented_at desc limit 1),false),
    'rewards',coalesce((select jsonb_agg(to_jsonb(r) order by r.points_cost,r.name) from (
      select w.id,w.name,w.description,w.image_url,w.points_cost,w.conditions,w.valid_days,(v_member.available_points>=w.points_cost) eligible,greatest(w.points_cost-v_member.available_points,0) missing_points
      from public.rewards w where w.active and w.archived_at is null and (w.starts_at is null or w.starts_at<=now()) and (w.ends_at is null or w.ends_at>now())
      and (w.stock_limit is null or (select count(*) from public.redemptions d where d.reward_id=w.id and d.status in ('pending','fulfilled'))<w.stock_limit)) r),'[]'::jsonb),
    'visits',coalesce((select jsonb_agg(to_jsonb(v) order by v.occurred_at desc) from (select e.invoice_code,e.occurred_at,e.eligible_amount,e.points,e.status,e.review_reason from public.earn_requests e where e.member_id=v_member.id order by e.occurred_at desc limit 50) v),'[]'::jsonb),
    'ledger',coalesce((select jsonb_agg(to_jsonb(l) order by l.created_at desc) from (select p.type,p.points_delta,p.balance_after,p.reason,p.expires_at,p.created_at from public.point_ledger p where p.member_id=v_member.id order by p.created_at desc limit 100) l),'[]'::jsonb),
    'redemptions',coalesce((select jsonb_agg(to_jsonb(d) order by d.redeemed_at desc) from (select x.id,w.name reward_name,x.points_spent,x.status,x.code_expires_at,x.redeemed_at,x.fulfilled_at from public.redemptions x join public.rewards w on w.id=x.reward_id where x.member_id=v_member.id order by x.redeemed_at desc limit 50) d),'[]'::jsonb));
end $$;

create or replace function public.customer_password_changed()
returns void language plpgsql security definer set search_path=public as $$
begin
  update public.members set must_change_password=false,updated_at=now() where auth_user_id=auth.uid() and active;
  if not found then raise exception 'Không tìm thấy hồ sơ thành viên'; end if;
  insert into public.membership_audit_log(actor_id,action,entity_type,entity_id)
  select auth.uid(),'customer_password_changed','member',id::text from public.members where auth_user_id=auth.uid();
end $$;

revoke all on function public.customer_password_changed() from public,anon;
grant execute on function public.customer_password_changed() to authenticated;
