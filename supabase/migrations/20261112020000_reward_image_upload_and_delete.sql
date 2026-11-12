-- Admin-managed reward images and safe reward deletion.
insert into storage.buckets (id,name,public,file_size_limit,allowed_mime_types)
values ('reward-images','reward-images',true,5242880,array['image/jpeg','image/png','image/webp'])
on conflict (id) do update set
  public=excluded.public,
  file_size_limit=excluded.file_size_limit,
  allowed_mime_types=excluded.allowed_mime_types;

drop policy if exists "Public read reward images" on storage.objects;
create policy "Public read reward images" on storage.objects for select
to public using (bucket_id='reward-images');

drop policy if exists "Managers upload reward images" on storage.objects;
create policy "Managers upload reward images" on storage.objects for insert
to authenticated with check (bucket_id='reward-images' and public.membership_role()='manager');

drop policy if exists "Managers update reward images" on storage.objects;
create policy "Managers update reward images" on storage.objects for update
to authenticated using (bucket_id='reward-images' and public.membership_role()='manager')
with check (bucket_id='reward-images' and public.membership_role()='manager');

drop policy if exists "Managers delete reward images" on storage.objects;
create policy "Managers delete reward images" on storage.objects for delete
to authenticated using (bucket_id='reward-images' and public.membership_role()='manager');

create or replace function public.delete_reward(p_id uuid)
returns text language plpgsql security definer set search_path=public as $$
declare v_reward public.rewards%rowtype;v_used boolean;
begin
  if public.membership_role()<>'manager' then raise exception 'Chỉ Admin được xóa phần thưởng'; end if;
  select * into v_reward from public.rewards where id=p_id for update;
  if v_reward.id is null then raise exception 'Không tìm thấy phần thưởng'; end if;
  select exists(select 1 from public.redemptions where reward_id=p_id) into v_used;
  if v_used then
    update public.rewards set active=false,updated_at=now() where id=p_id;
    insert into public.membership_audit_log(actor_id,action,entity_type,entity_id,details)
    values(auth.uid(),'reward_disabled','reward',p_id::text,jsonb_build_object('name',v_reward.name,'reason','Đã có lịch sử đổi quà'));
    return 'disabled';
  end if;
  delete from public.rewards where id=p_id;
  insert into public.membership_audit_log(actor_id,action,entity_type,entity_id,details)
  values(auth.uid(),'reward_deleted','reward',p_id::text,jsonb_build_object('name',v_reward.name));
  return 'deleted';
end $$;

revoke all on function public.delete_reward(uuid) from public,anon;
grant execute on function public.delete_reward(uuid) to authenticated;
