import {NextRequest,NextResponse} from 'next/server';
import {createHash,randomUUID} from 'node:crypto';
import {createClient as plainClient,type SupabaseClient} from '@supabase/supabase-js';
import {administrationConfigured,createServiceAdmin} from './supabase/admin';
import {ApiError} from './errors';
import {accountConfigurationIssue} from './account-config.mjs';
import {normalizeUsername,validUsername,validPassword,reservedUsernames} from './username.mjs';
async function rpc(client:SupabaseClient,name:string,args:Record<string,unknown>={}){const {data,error,status}=await client.rpc(name,args);if(error){if(error.code==='P0001'||error.code==='23505'||error.code?.startsWith('22'))throw error;const issue=accountConfigurationIssue(error,status);console.error('Account operation failed',{operation:name,code:error.code||'UPSTREAM_ERROR',status});throw new ApiError(issue.message,503,{code:issue.code,operation:name,providerCode:error.code||null});}return data;}
export async function authAdmin(){if(!administrationConfigured())throw new ApiError('Username sign-in needs server setup. Add SUPABASE_SERVICE_ROLE_KEY in Vercel and redeploy.',503);return await createServiceAdmin();}
async function attempt(req:NextRequest,kind:string){
 const client=await authAdmin();const ip=req.headers.get('x-vercel-forwarded-for')||req.headers.get('x-forwarded-for')?.split(',')[0]||req.headers.get('x-real-ip')||'local';
 await rpc(client,'service_auth_attempt',{p_key:createHash('sha256').update(ip.trim()).digest('hex'),p_action:kind});return client;
}
export async function passwordPublicRoute(req:NextRequest,path:string,body:any,supabase:SupabaseClient){
 if(!['/auth/signin','/auth/signup'].includes(path)||req.method!=='POST')return null;
 const username=normalizeUsername(body.username),password=body.password;
 if(!validUsername(username)||!validPassword(password))throw new ApiError('Enter a username (3–32 letters, numbers, dots, dashes or underscores) and a password of at least 8 characters.');
 const admin=await attempt(req,path.endsWith('signup')?'signup':'signin');
 let account=await rpc(admin,'service_resolve_username',{p_username:username});
 if(path==='/auth/signup'){
  const cfg=await supabase.from('website_configuration').select('registration_enabled,maintenance_mode').eq('id',true).single();
  if(cfg.error)throw cfg.error;if(!cfg.data.registration_enabled||cfg.data.maintenance_mode)throw new ApiError('New account registration is temporarily paused.',403);
  if(reservedUsernames.has(username)||account)throw new ApiError('Choose a different username.',409);
  const name=typeof body.name==='string'?body.name.trim().slice(0,100):username;if(!name)throw new ApiError('Enter your name.');
  const email='u.'+randomUUID()+'@localmate.invalid';
  const {data,error}=await admin.auth.admin.createUser({email,password,email_confirm:true,user_metadata:{full_name:name}});if(error||!data.user)throw new ApiError('The account could not be created. Please try again.',503);
  try{await rpc(admin,'service_set_login',{p_user:data.user.id,p_username:username,p_change_password:false});}
  catch(error){await admin.auth.admin.deleteUser(data.user.id);throw error;}
  account={email,is_active:true,must_change_password:false};
 }else if(!account&&username==='admin'){
  const initialPassword=process.env.ADMIN_INITIAL_PASSWORD||'admin123';
  if(password!==initialPassword)throw new ApiError('Incorrect username or password.',401);
  const state=await rpc(admin,'service_bootstrap_state');
  if(!state.completed){
   let id=state.candidate_id;
   if(!id){const {data,error}=await admin.auth.admin.createUser({email:'admin@localmate.invalid',password:initialPassword,email_confirm:true,user_metadata:{full_name:'Administrator'},app_metadata:{local_mate_bootstrap:true}});if(error||!data.user)throw new ApiError('Administrator setup could not complete. Please retry.',503);id=data.user.id;}
   await rpc(admin,'service_finish_bootstrap',{p_user:id});
   account=await rpc(admin,'service_resolve_username',{p_username:username});
  }
 }
 if(!account||!account.is_active)throw new ApiError('Incorrect username or password.',401);
 const {error}=await supabase.auth.signInWithPassword({email:account.email,password});
 if(error)throw new ApiError(error.status===429?'Too many sign-in attempts. Please wait and try again.':'Incorrect username or password.',error.status===429?429:401);
 const {data:adminAccess}=await supabase.rpc('is_admin');
 return NextResponse.json({ok:true,admin:!!adminAccess,must_change_password:!!account.must_change_password},{headers:{'Cache-Control':'no-store'}});
}
export async function verifyCurrentPassword(req:NextRequest,email:string,password:unknown){
 if(typeof password!=='string'||!password)throw new ApiError('Enter your current password.');
 await attempt(req,'reauthenticate');
 const client=plainClient(process.env.NEXT_PUBLIC_SUPABASE_URL!,process.env.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY!,{auth:{persistSession:false,autoRefreshToken:false}});
 const {error}=await client.auth.signInWithPassword({email,password});
 if(error)throw new ApiError('Current password is incorrect.',403);
 await client.auth.signOut({scope:'local'});
}
export async function updateCredentials(req:NextRequest,user:any,state:any,body:any){
 await verifyCurrentPassword(req,user.email,body.current_password);
 const username=normalizeUsername(body.username||state?.username);
 if(!validUsername(username))throw new ApiError('Enter a valid username.');
 if(username!==state?.username&&reservedUsernames.has(username))throw new ApiError('Choose a different username.');
 const admin=await authAdmin();const existing=await rpc(admin,'service_resolve_username',{p_username:username});
 if(existing&&existing.user_id!==user.id)throw new ApiError('Choose a different username.',409);
 const password=body.new_password;
 if(state?.must_change_password&&!password)throw new ApiError('Set a new password before continuing.');
 if(password){if(!validPassword(password,12)||password==='admin123'||password===body.current_password)throw new ApiError('Choose a different password with at least 12 characters.');const {error}=await admin.auth.admin.updateUserById(user.id,{password});if(error)throw new ApiError('Your password could not be changed.',503);}
 await rpc(admin,'service_set_login',{p_user:user.id,p_username:username,p_change_password:false});
 return {ok:true};
}
export async function setManagedCredentials(actorId:string,body:any){
 const username=normalizeUsername(body.username);if(!validUsername(username)||!validPassword(body.password,12))throw new ApiError('Choose a valid username and a temporary password of at least 12 characters.');
 if(body.user_id===actorId)throw new ApiError('Use your own account settings to change your credentials.');
 if(reservedUsernames.has(username))throw new ApiError('Choose a different username.');
 const admin=await authAdmin();const existing=await rpc(admin,'service_resolve_username',{p_username:username});
 if(existing&&existing.user_id!==body.user_id)throw new ApiError('This username is already in use.',409);
 const {error}=await admin.auth.admin.updateUserById(body.user_id,{password:body.password,email_confirm:true});if(error)throw new ApiError('Credentials could not be updated.',503);
 await rpc(admin,'service_set_login',{p_user:body.user_id,p_username:username,p_change_password:true});return {ok:true};
}
export async function deleteAllData(req:NextRequest,user:any,supabase:SupabaseClient,body:any){
 if(body.confirmation!=='DELETE ALL DATA')throw new ApiError('Type DELETE ALL DATA to confirm.');
 await verifyCurrentPassword(req,user.email,body.current_password);
 const admin=await authAdmin();const targets:string[]=[];
 for(let page=1;;page++){const {data,error}=await admin.auth.admin.listUsers({page,perPage:1000});if(error)throw new ApiError('User accounts could not be listed. Nothing has been deleted.',503);targets.push(...data.users.filter(u=>u.id!==user.id).map(u=>u.id));if(data.users.length<1000)break;}
 await rpc(admin,'service_reset_marketplace',{p_actor:user.id,p_confirmation:body.confirmation});
 targets.length=0;
 for(let page=1;;page++){const {data,error}=await admin.auth.admin.listUsers({page,perPage:1000});if(error)throw new ApiError('Marketplace records were removed and the website is paused. Retry account cleanup.',503);targets.push(...data.users.filter(u=>u.id!==user.id).map(u=>u.id));if(data.users.length<1000)break;}
 const failed:string[]=[];for(const id of targets){const {error}=await admin.auth.admin.deleteUser(id);if(error)failed.push(id);}
 await rpc(admin,'service_reset_progress',{p_actor:user.id,p_note:JSON.stringify({deleted:targets.length-failed.length,failed:failed.length})});
 return {ok:failed.length===0,deleted_accounts:targets.length-failed.length,remaining_accounts:failed.length,message:failed.length?'Marketplace records were removed. Some accounts remain; retry cleanup.':'All marketplace records and other accounts were removed. The website is paused and your administrator login is preserved.'};
}
