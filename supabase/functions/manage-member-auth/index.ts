import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const cors={"Access-Control-Allow-Origin":"*","Access-Control-Allow-Headers":"authorization, x-client-info, apikey, content-type"};
const json=(body:unknown,status=200)=>new Response(JSON.stringify(body),{status,headers:{...cors,"Content-Type":"application/json"}});
const temporaryPassword=()=>{const chars="ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz23456789";const bytes=crypto.getRandomValues(new Uint8Array(10));return Array.from(bytes,b=>chars[b%chars.length]).join("");};
const alias=(phone:string)=>phone.replace(/\D/g,"").replace(/^0/,"84")+"@member.playnest.vn";

Deno.serve(async(req)=>{
  if(req.method==="OPTIONS")return new Response("ok",{headers:cors});
  try{
    const url=Deno.env.get("SUPABASE_URL")!,anon=Deno.env.get("SUPABASE_ANON_KEY")!,service=Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
    const token=req.headers.get("Authorization")||"";
    const caller=createClient(url,anon,{global:{headers:{Authorization:token}}});
    const {data:{user},error:userError}=await caller.auth.getUser();if(userError||!user)return json({error:"Phiên đăng nhập không hợp lệ"},401);
    const admin=createClient(url,service,{auth:{autoRefreshToken:false,persistSession:false}});
    const {data:staff}=await admin.from("program_users").select("role,active").eq("user_id",user.id).maybeSingle();
    if(!staff?.active)return json({error:"Không có quyền quản lý tài khoản thành viên"},403);
    const {member_id}=await req.json();if(!member_id)return json({error:"Thiếu member_id"},400);
    const {data:member,error:memberError}=await admin.from("members").select("id,member_code,phone_encrypted,auth_user_id,active").eq("id",member_id).single();
    if(memberError||!member?.active)return json({error:"Không tìm thấy thành viên hoạt động"},404);
    if(member.auth_user_id&&staff.role!=="manager")return json({error:"Chỉ Admin được cấp lại mật khẩu cho tài khoản đã tồn tại"},403);
    const password=temporaryPassword(),email=alias(member.phone_encrypted);let authId=member.auth_user_id;
    if(authId){const {error}=await admin.auth.admin.updateUserById(authId,{password,email,email_confirm:true});if(error)throw error;}
    else{const {data,error}=await admin.auth.admin.createUser({email,password,email_confirm:true,user_metadata:{member_code:member.member_code}});if(error)throw error;authId=data.user.id;}
    const {error:updateError}=await admin.from("members").update({auth_user_id:authId,must_change_password:true,updated_at:new Date().toISOString()}).eq("id",member.id);if(updateError)throw updateError;
    await admin.from("membership_audit_log").insert({actor_id:user.id,action:member.auth_user_id?"member_password_reset":"member_account_created",entity_type:"member",entity_id:member.id,details:{member_code:member.member_code}});
    return json({temporary_password:password,member_code:member.member_code});
  }catch(error){return json({error:error instanceof Error?error.message:"Không thể tạo tài khoản"},400);}
});
