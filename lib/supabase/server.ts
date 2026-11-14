import { createServerClient } from '@supabase/ssr';
import { cookies } from 'next/headers';
export function isSupabaseConfigured(){return !!(process.env.NEXT_PUBLIC_SUPABASE_URL&&process.env.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY);}
export async function createClient(){
 const store=await cookies();
 if(!isSupabaseConfigured())throw new Error('Supabase is not configured. Add the project URL and publishable key in Vercel environment settings.');
 return createServerClient(process.env.NEXT_PUBLIC_SUPABASE_URL!,process.env.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY!,{
  cookies:{getAll:()=>store.getAll(),setAll:items=>{for(const {name,value,options} of items)store.set(name,value,options)}}
 });
}
