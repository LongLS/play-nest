import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const cors={"Access-Control-Allow-Origin":"*","Access-Control-Allow-Headers":"authorization, x-client-info, apikey, content-type"};
const json=(body:unknown,status=200)=>new Response(JSON.stringify(body),{status,headers:{...cors,"Content-Type":"application/json"}});
const temporaryPassword=()=>{const chars="ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz23456789!@";const bytes=crypto.getRandomValues(new Uint8Array(12));return Array.from(bytes,b=>chars[b%chars.length]).join("");};

Deno.serve(async(req)=>{
  if(req.method==="OPTIONS")return new Response("ok",{headers:cors});
  try{
    const url=Deno.env.get("SUPABASE_URL")!,anon=Deno.env.get("SUPABASE_ANON_KEY")!,service=Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
    const token=req.headers.get("Authorization")||"";
    const caller=createClient(url,anon,{global:{headers:{Authorization:token}}});
    const {data:{user},error:userError}=await caller.auth.getUser();
    if(userError||!user)return json({error:"Phiên đăng nhập không hợp lệ"},401);
    const admin=createClient(url,service,{auth:{autoRefreshToken:false,persistSession:false}});
    const {data:manager}=await admin.from("program_users").select("role,active").eq("user_id",user.id).maybeSingle();
    if(!manager?.active||manager.role!=="manager")return json({error:"Chỉ Admin được quản lý tài khoản nhân viên"},403);
    const body=await req.json(),username=String(body.username||"").trim().toLowerCase();
    if(!/^[a-z0-9._-]{3,40}$/.test(username))return json({error:"Tên đăng nhập không hợp lệ"},400);
    const email=username+"@staff.playnest.vn";
    const {data:list,error:listError}=await admin.auth.admin.listUsers({page:1,perPage:1000});if(listError)throw listError;
    let account=list.users.find(item=>item.email?.toLowerCase()===email);
    if(body.delete_account){
      if(!account)return json({error:"Không tìm thấy tài khoản nhân viên"},404);
      if(account.id===user.id)return json({error:"Không thể tự xóa tài khoản Admin đang đăng nhập"},400);
      const {data:target,error:targetError}=await admin.from("program_users").select("role,display_name").eq("user_id",account.id).maybeSingle();if(targetError)throw targetError;
      if(!target)return json({error:"Tài khoản không còn trong danh sách nhân viên"},404);
      if(target.role==="manager"){
        const {count,error:countError}=await admin.from("program_users").select("user_id",{count:"exact",head:true}).eq("role","manager").eq("active",true);if(countError)throw countError;
        if((count||0)<=1)return json({error:"Không thể xóa Admin hoạt động cuối cùng"},400);
      }
      const {error:auditError}=await admin.from("membership_audit_log").insert({actor_id:user.id,action:"staff_account_deleted",entity_type:"program_user",entity_id:account.id,details:{username,display_name:target.display_name,role:target.role}});if(auditError)throw auditError;
      const {error:accessError}=await admin.from("program_users").delete().eq("user_id",account.id);if(accessError)throw accessError;
      const {error:deleteError}=await admin.auth.admin.deleteUser(account.id,true);if(deleteError)throw deleteError;
      return json({deleted:true,username});
    }
    if(!["staff","manager"].includes(body.role))return json({error:"Vai trò không hợp lệ"},400);
    const password=temporaryPassword();let created=false,temporary_password:string|undefined;
    if(!account){
      const createdUser=await admin.auth.admin.createUser({email,password,email_confirm:true,user_metadata:{display_name:String(body.display_name||username),staff_username:username}});
      if(createdUser.error)throw createdUser.error;account=createdUser.data.user;created=true;temporary_password=password;
    }else if(body.reset_password){
      const updated=await admin.auth.admin.updateUserById(account.id,{password,user_metadata:{display_name:String(body.display_name||username),staff_username:username}});
      if(updated.error)throw updated.error;temporary_password=password;
    }
    if(account.id===user.id&&(!body.active||body.role!=="manager"))return json({error:"Không thể tự khóa hoặc hạ quyền Admin đang đăng nhập"},400);
    const {error:upsertError}=await admin.from("program_users").upsert({user_id:account.id,email,display_name:String(body.display_name||username).trim(),role:body.role,active:Boolean(body.active),can_redeem:Boolean(body.can_redeem),updated_at:new Date().toISOString()},{onConflict:"user_id"});
    if(upsertError)throw upsertError;
    await admin.from("membership_audit_log").insert({actor_id:user.id,action:created?"staff_account_created":"staff_access_saved",entity_type:"program_user",entity_id:account.id,details:{username,role:body.role,active:Boolean(body.active),password_reset:Boolean(body.reset_password)}});
    return json({created,username,temporary_password});
  }catch(error){return json({error:error instanceof Error?error.message:"Không thể quản lý tài khoản nhân viên"},400);}
});
