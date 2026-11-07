-- Never hide an earn request because its submitter profile is missing or changed.
-- The request itself remains the source of truth for manager approval.
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
    select e.id,e.invoice_code,m.member_code,m.display_name,e.eligible_amount,e.points,e.occurred_at,
      coalesce(u.display_name,'Tài khoản cũ/không xác định') submitted_by_name,
      e.created_at,e.status,e.abnormal,e.review_reason
    from public.earn_requests e
    join public.members m on m.id=e.member_id
    left join public.program_users u on u.user_id=e.submitted_by
    where (v_role='manager' or e.submitted_by=auth.uid()) and (p_status is null or p_status='' or e.status::text=p_status)
      and (p_search is null or p_search='' or e.invoice_code ilike '%'||p_search||'%' or m.member_code ilike '%'||p_search||'%')
      and (p_from is null or e.created_at>=p_from) and (p_to is null or e.created_at<p_to)
    order by e.created_at desc limit p_page_size offset v_offset) x;
  return jsonb_build_object('rows',v_rows,'total',v_total,'page',p_page,'page_size',p_page_size);
end $$;

revoke all on function public.earn_request_list(text,text,timestamptz,timestamptz,int,int) from public,anon;
grant execute on function public.earn_request_list(text,text,timestamptz,timestamptz,int,int) to authenticated;
