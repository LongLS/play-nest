-- Supabase installs pgcrypto in the extensions schema. Existing functions
-- created with search_path=public cannot resolve digest()/gen_random_bytes().
do $$
begin
  if to_regprocedure('public.lookup_member(text)') is not null then
    alter function public.lookup_member(text) set search_path=public,extensions;
  end if;
  if to_regprocedure('public.create_member(text,text,boolean,boolean,text)') is not null then
    alter function public.create_member(text,text,boolean,boolean,text) set search_path=public,extensions;
  end if;
  if to_regprocedure('public.admin_change_member_phone(uuid,text,text,text)') is not null then
    alter function public.admin_change_member_phone(uuid,text,text,text) set search_path=public,extensions;
  end if;
  if to_regprocedure('public.admin_anonymize_member(uuid,text)') is not null then
    alter function public.admin_anonymize_member(uuid,text) set search_path=public,extensions;
  end if;
  if to_regprocedure('public.customer_link_or_register(text,boolean,boolean,text)') is not null then
    alter function public.customer_link_or_register(text,boolean,boolean,text) set search_path=public,auth,extensions;
  end if;
  if to_regprocedure('public.customer_redeem_reward(uuid)') is not null then
    alter function public.customer_redeem_reward(uuid) set search_path=public,extensions;
  end if;
  if to_regprocedure('public.fulfill_redemption_code(text)') is not null then
    alter function public.fulfill_redemption_code(text) set search_path=public,extensions;
  end if;
end $$;
