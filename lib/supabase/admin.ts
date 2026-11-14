import 'server-only';
import {accountConfigurationIssue} from '../account-config.mjs';
import {createClient} from '@supabase/supabase-js';
export function administrationConfigured(){return !!(process.env.NEXT_PUBLIC_SUPABASE_URL&&process.env.SUPABASE_SERVICE_ROLE_KEY);}
export function createServiceAdmin(){
 const url=process.env.NEXT_PUBLIC_SUPABASE_URL,key=process.env.SUPABASE_SERVICE_ROLE_KEY;
 if(!url||!key)throw new Error('Add SUPABASE_SERVICE_ROLE_KEY to the server environment.');
 return createClient(url,key,{auth:{persistSession:false,autoRefreshToken:false}});
}
export const createPaymentAdmin=createServiceAdmin;

export async function accountManagementHealth(){
 if(!administrationConfigured())return {configured:false,ready:false,issue:{code:'SERVER_KEY_MISSING',message:'Add SUPABASE_SERVICE_ROLE_KEY in Vercel and redeploy.'}};
 try{const {error,status}=await createServiceAdmin().rpc('service_bootstrap_state');return {configured:true,ready:!error,issue:error?accountConfigurationIssue(error,status):null};}
 catch{return {configured:true,ready:false,issue:{code:'INVALID_SERVER_CONFIGURATION',message:'Check the Supabase project URL and server key in Vercel, then redeploy.'}};}
}
