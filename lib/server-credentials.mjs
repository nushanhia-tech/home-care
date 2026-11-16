import {accountConfigurationIssue} from './account-config.mjs';
export function normalizeServerKey(value){
 let key=typeof value==='string'?value.trim():'';
 key=key.replace(/^(?:export\s+)?(?:SUPABASE_SECRET_KEY|SUPABASE_SERVICE_ROLE_KEY)\s*=\s*/,'').trim();
 for(let i=0;i<2;i++){
  if(key.length>1&&['"',"'",'`'].includes(key[0])&&key.at(-1)===key[0])key=key.slice(1,-1).trim();
 }
 return key;
}
function inspectKey(key,projectRef){
 if(!key)return {code:'SERVER_KEY_MISSING',message:'Add a Supabase server secret key in Vercel and redeploy.'};
 if(key.startsWith('sb_publishable_'))return {code:'PUBLIC_KEY_IN_SERVER_SETTING',message:'The server setting contains a publishable key. Set SUPABASE_SECRET_KEY to a secret key from the same Supabase project and redeploy.'};
 if(/(?:\*{3,}|•{3,}|\.{3,}|YOUR_|PLACEHOLDER|PASTE_|PUT_)/i.test(key))return {code:'INCOMPLETE_SERVER_KEY',message:'The server setting contains a placeholder or masked key. Copy the full revealed secret key into Vercel and redeploy.'};
 if(key.startsWith('sb_secret_')&&/^sb_secret_[a-zA-Z0-9_-]+$/.test(key))return null;
 if(/^[a-zA-Z0-9_-]+\.[a-zA-Z0-9_-]+\.[a-zA-Z0-9_-]+$/.test(key)){
  try{
   const encoded=key.split('.')[1];const payload=JSON.parse(atob(encoded.replace(/-/g,'+').replace(/_/g,'/')));
   if(payload.role!=='service_role')return {code:'PUBLIC_KEY_IN_SERVER_SETTING',message:'The configured JWT is not a service-role key. Use a Supabase secret key or the legacy service_role key.'};
   if(projectRef&&payload.ref&&payload.ref!==projectRef)return {code:'SERVER_KEY_PROJECT_MISMATCH',message:'The server key belongs to a different Supabase project. Use the secret key from the project in NEXT_PUBLIC_SUPABASE_URL.'};
   if(typeof payload.exp==='number'&&payload.exp*1000<=Date.now())return {code:'EXPIRED_SERVER_KEY',message:'The server JWT has expired. Replace it with a current Supabase secret key in Vercel and redeploy.'};
   return null;
  }catch{}
 }
 return {code:'INVALID_SERVER_KEY_FORMAT',message:'The server key format is not recognized. Copy the complete secret key from Supabase API Keys into Vercel.'};
}
export function adminConfiguration(env){
 let url=typeof env.NEXT_PUBLIC_SUPABASE_URL==='string'?env.NEXT_PUBLIC_SUPABASE_URL.trim().replace(/\/$/,''):'';
 let projectRef='';
 try{const parsed=new URL(url);if(parsed.pathname!=='/'&&parsed.pathname!=='')throw new Error();projectRef=parsed.hostname.endsWith('.supabase.co')?parsed.hostname.split('.')[0]:'';}
 catch{return {configured:false,url:'',candidates:[],issues:[{code:'INVALID_PROJECT_URL',message:'Set NEXT_PUBLIC_SUPABASE_URL to the Supabase project origin, without /rest/v1/.'}]};}
 const candidates=[],issues=[];const seen=new Set();let configured=false;
 for(const source of ['SUPABASE_SECRET_KEY','SUPABASE_SERVICE_ROLE_KEY']){
  if(typeof env[source]!=='string'||!env[source].trim())continue;
  configured=true;const key=normalizeServerKey(env[source]);if(seen.has(key))continue;seen.add(key);
  const issue=inspectKey(key,projectRef);if(issue)issues.push({...issue,source});else candidates.push({key,source,kind:key.startsWith('sb_secret_')?'secret':'legacy_service_role'});
 }
 if(!configured)issues.push({code:'SERVER_KEY_MISSING',message:'Add SUPABASE_SECRET_KEY or SUPABASE_SERVICE_ROLE_KEY in Vercel and redeploy.'});
 return {configured,url,candidates,issues};
}
/** Opaque modern keys belong in apikey; real user JWTs and legacy service-role JWTs remain Bearer tokens. */
export function adminTransport(key,fetcher=fetch){
 return async(input,init={})=>{
  const headers=new Headers(input instanceof Request?input.headers:undefined);
  new Headers(init.headers).forEach((value,name)=>headers.set(name,value));
  if(key.startsWith('sb_secret_')&&headers.get('Authorization')===`Bearer ${key}`)headers.delete('Authorization');
  headers.set('apikey',key);
  return fetcher(input,{...init,headers});
 };
}
export async function resolveAdminClient(config,createClient,fetcher=fetch){
 const failures=[];
 for(const candidate of config.candidates){
  const client=createClient(config.url,candidate.key,{auth:{persistSession:false,autoRefreshToken:false},global:{fetch:adminTransport(candidate.key,fetcher)}});
  try{
   const {error,status}=await client.rpc('service_bootstrap_state');
   if(!error)return {client,source:candidate.source,kind:candidate.kind,issue:null};
   // SQLSTATE 21000 can only be returned after the secret key authenticated and
   // the service-only health RPC reached the database. Older installations may
   // have duplicate interrupted bootstrap candidates; allow server operations
   // to continue so the reset and the database hotfix remain recoverable.
   if(error.code==='21000')return {client,source:candidate.source,kind:candidate.kind,issue:null};
   const issue=accountConfigurationIssue(error,status);
   // A schema error proves the gateway accepted the key; keep its accurate setup diagnosis.
   if(issue.code==='ACCOUNT_SCHEMA_MISSING')return {client:null,source:candidate.source,kind:candidate.kind,issue};
   failures.push({...issue,source:candidate.source});
  }catch{failures.push({code:'SUPABASE_CONNECTION_FAILED',message:'The account server could not reach Supabase. Check the project URL and try again.',source:candidate.source});}
 }
 return {client:null,issue:failures[0]||config.issues[0]||{code:'SERVER_KEY_MISSING',message:'Add a Supabase server key in Vercel and redeploy.'}};
}
