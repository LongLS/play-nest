-- Type-ahead member suggestions for authenticated PlayNest staff.
create or replace function public.search_members_by_phone(
  p_query text,
  p_limit integer default 6
)
returns table(
  id uuid,
  member_code text,
  phone text,
  masked_phone text,
  display_name text,
  available_points integer,
  pending_points integer,
  visit_count integer
)
language plpgsql
security definer
set search_path=public
as $$
declare
  v_query text := regexp_replace(coalesce(p_query,''),'[^0-9]','','g');
  v_limit integer := least(greatest(coalesce(p_limit,6),1),8);
begin
  if public.membership_role() is null then
    raise exception 'Không có quyền Membership';
  end if;

  if length(v_query) < 3 then
    return;
  end if;

  if left(v_query,2)='84' then
    v_query := '0'||substr(v_query,3);
  end if;

  return query
  select
    m.id,
    m.member_code,
    m.phone_encrypted,
    public.mask_phone(m.phone_encrypted),
    m.display_name,
    m.available_points,
    m.pending_points,
    m.visit_count
  from public.members m
  where m.active
    and (
      case
        when left(regexp_replace(m.phone_encrypted,'[^0-9]','','g'),2)='84'
          then '0'||substr(regexp_replace(m.phone_encrypted,'[^0-9]','','g'),3)
        else regexp_replace(m.phone_encrypted,'[^0-9]','','g')
      end
    ) like v_query||'%'
  order by
    case when regexp_replace(m.phone_encrypted,'[^0-9]','','g')=regexp_replace(p_query,'[^0-9]','','g') then 0 else 1 end,
    m.updated_at desc
  limit v_limit;
end
$$;

revoke all on function public.search_members_by_phone(text,integer) from public,anon;
grant execute on function public.search_members_by_phone(text,integer) to authenticated;
