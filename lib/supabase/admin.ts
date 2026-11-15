import 'server-only';
import {createClient,type SupabaseClient} from '@supabase/supabase-js';
import {adminConfiguration,resolveAdminClient} from '../server-credentials.mjs';
import {ApiError} from '../errors';
export function administrationConfigured(){return adminConfiguration(process.env).configured;}
export async function createServiceAdmin():Promise<SupabaseClient>{
 const result=await resolveAdminClient(adminConfiguration(process.env),createClient);
 if(!result.client){const issue=result.issue||{code:'SERVER_KEY_MISSING',message:'Add a Supabase server secret key in Vercel and redeploy.'};throw new ApiError(issue.message,503,{code:issue.code});}
 return result.client;
}
export const createPaymentAdmin=createServiceAdmin;
export async function accountManagementHealth(){
 const config=adminConfiguration(process.env);
 if(!config.configured)return {configured:false,ready:false,issue:config.issues[0]};
 const result=await resolveAdminClient(config,createClient);
 return {configured:true,ready:!!result.client,issue:result.issue,source:result.source,kind:result.kind};
}
