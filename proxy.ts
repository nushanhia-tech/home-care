import { createServerClient } from '@supabase/ssr';
import { NextRequest,NextResponse } from 'next/server';
export async function proxy(request:NextRequest){
 let response=NextResponse.next({request});
 const url=process.env.NEXT_PUBLIC_SUPABASE_URL,key=process.env.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY;
 if(!url||!key)return response;
 const client=createServerClient(url,key,{cookies:{getAll:()=>request.cookies.getAll(),setAll:items=>{for(const {name,value} of items)request.cookies.set(name,value);response=NextResponse.next({request});for(const {name,value,options} of items)response.cookies.set(name,value,options);}}});
 // Validate and refresh the session; this is not the final authorization check.
 try{await client.auth.getUser();}catch{}
 return response;
}
export const config={matcher:['/((?!_next/static|_next/image|favicon.ico|assets/).*)']};
