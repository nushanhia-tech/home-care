import 'server-only';
import {createClient} from '@supabase/supabase-js';
export function administrationConfigured(){return !!(process.env.NEXT_PUBLIC_SUPABASE_URL&&process.env.SUPABASE_SERVICE_ROLE_KEY);}
export function createServiceAdmin(){
 const url=process.env.NEXT_PUBLIC_SUPABASE_URL,key=process.env.SUPABASE_SERVICE_ROLE_KEY;
 if(!url||!key)throw new Error('Add SUPABASE_SERVICE_ROLE_KEY to the server environment.');
 return createClient(url,key,{auth:{persistSession:false,autoRefreshToken:false}});
}
export const createPaymentAdmin=createServiceAdmin;
