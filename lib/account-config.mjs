/** Public setup diagnostics never include provider messages, account identifiers or credentials. */
export function accountConfigurationIssue(error,status=0){
 const providerCode=typeof error?.code==='string'?error.code:'';
 const message=typeof error?.message==='string'?error.message:'';
 if(status===401||['PGRST301','PGRST302','PGRST303'].includes(providerCode)||/invalid api key|invalid jwt|jwt expired|no api key found/i.test(message))return {
  code:'INVALID_SERVER_KEY',
  message:'Supabase rejected the server key. Replace SUPABASE_SERVICE_ROLE_KEY in Vercel with a valid secret key from the same Supabase project, then redeploy.'
 };
 if(providerCode==='42501'||status===403)return {
  code:'SERVER_KEY_PERMISSION',
  message:'Account management requires a Supabase secret or service-role key. Check SUPABASE_SERVICE_ROLE_KEY in Vercel and redeploy.'
 };
 if(['PGRST202','PGRST205','42P01','42703','42883'].includes(providerCode))return {
  code:'ACCOUNT_SCHEMA_MISSING',
  message:'The username login database setup is incomplete. Run the latest supabase/setup.sql in Supabase SQL Editor, then try again.'
 };
 if(/fetch failed|network|timeout/i.test(message))return {code:'SUPABASE_CONNECTION_FAILED',message:'The account server could not reach Supabase. Check that the project is running and try again.'};
 return {code:'ACCOUNT_SETUP_ERROR',message:'Supabase could not complete the account setup. Reference: '+(providerCode.replace(/[^a-zA-Z0-9_]/g,'').slice(0,32)||'UPSTREAM_ERROR')+'.'};
}
