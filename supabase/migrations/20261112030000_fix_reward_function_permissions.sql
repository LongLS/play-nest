-- Repair RPC permissions after reward functions were replaced by later migrations.
grant usage on schema public to authenticated;

revoke all on function public.fulfill_redemption_code_v2(text,text,text) from public,anon;
grant execute on function public.fulfill_redemption_code_v2(text,text,text) to authenticated;

revoke all on function public.customer_cancel_redemption(uuid,text) from public,anon;
grant execute on function public.customer_cancel_redemption(uuid,text) to authenticated;

revoke all on function public.redemption_list(text,timestamptz,timestamptz,int,int) from public,anon;
grant execute on function public.redemption_list(text,timestamptz,timestamptz,int,int) to authenticated;

revoke all on function public.customer_redeem_reward(uuid) from public,anon;
grant execute on function public.customer_redeem_reward(uuid) to authenticated;

notify pgrst, 'reload schema';
