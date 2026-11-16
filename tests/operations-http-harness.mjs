// Test-only GoTrue/storage adapters around real PostgREST/PostgreSQL, bound to loopback.
import {createServer} from 'node:http';
import {createHmac,randomUUID,timingSafeEqual} from 'node:crypto';
import {ids,jwt,JWT_SECRET} from './helpers/operations-db.mjs';
const files=new Map();
const userFor=id=>{const who=Object.keys(ids).find(k=>ids[k]===id);return who?{id,email:who+'@qa.example',aud:'authenticated',role:'authenticated',created_at:new Date().toISOString(),email_confirmed_at:new Date().toISOString(),app_metadata:{provider:'email',providers:['email']},user_metadata:{full_name:'Test '+who},identities:[]}:null};
function decode(token){try{const [h,p,s]=token.split('.');const expected=createHmac('sha256',JWT_SECRET).update(h+'.'+p).digest();const actual=Buffer.from(s,'base64url');if(actual.length!==expected.length||!timingSafeEqual(actual,expected))return null;const data=JSON.parse(Buffer.from(p,'base64url'));return data.exp>Date.now()/1000?data:null}catch{return null}}
function send(res,status,data,headers={}){res.writeHead(status,{'content-type':'application/json',...headers});res.end(typeof data==='string'||Buffer.isBuffer(data)?data:JSON.stringify(data))}
const server=createServer(async(req,res)=>{try{
 const url=new URL(req.url,'http://127.0.0.1:3211');const chunks=[];let length=0;for await(const chunk of req){length+=chunk.length;if(length>5*1024*1024)return send(res,413,{message:'Test request too large'});chunks.push(chunk)}const body=Buffer.concat(chunks);
 let token=(req.headers.authorization||'').replace(/^Bearer /,'');const claims=decode(token);
 if(url.pathname==='/auth/v1/user'){const user=claims&&userFor(claims.sub);return send(res,user?200:401,user||{message:'Not authenticated'})}
 if(url.pathname==='/auth/v1/logout')return send(res,204,'');
 if(url.pathname==='/test/session'){const who=url.searchParams.get('who');if(!ids[who])return send(res,400,{});const user=userFor(ids[who]),access_token=jwt(who);return send(res,200,{access_token,refresh_token:'test-only-refresh',expires_at:Math.floor(Date.now()/1000)+7200,expires_in:7200,token_type:'bearer',user})}
 if(url.pathname.startsWith('/rest/v1/')){
  if(!claims)token=jwt(String(req.headers.apikey||'').startsWith('sb_secret_')?'service':null);
  const headers={...req.headers,authorization:'Bearer '+token};delete headers.host;delete headers['content-length'];delete headers.connection;
  const upstream=await fetch('http://127.0.0.1:3212'+url.pathname.slice('/rest/v1'.length)+url.search,{method:req.method,headers,...(!['GET','HEAD'].includes(req.method)?{body}:{} )});
  const outgoing=Object.fromEntries(upstream.headers);delete outgoing['content-encoding'];delete outgoing['content-length'];res.writeHead(upstream.status,outgoing);return res.end(Buffer.from(await upstream.arrayBuffer()));
 }
 if(url.pathname.startsWith('/storage/v1/object/')){
  if(!String(req.headers.apikey||'').startsWith('sb_secret_'))return send(res,403,{message:'Private test storage'});
  const path=url.pathname.replace('/storage/v1/object/','').replace(/^authenticated\//,'');
  if(req.method==='POST'){files.set(path,body);return send(res,200,{Key:path,Id:randomUUID()})}
  if(req.method==='GET'){const bytes=files.get(path);return bytes?send(res,200,bytes,{'content-type':'image/jpeg'}):send(res,404,{message:'Not found'})}
  if(req.method==='DELETE'){const data=JSON.parse(body);for(const name of data.prefixes||[])files.delete(path+'/'+name);return send(res,200,[])}
 }
 return send(res,404,{message:'Unknown test adapter route: '+url.pathname});
}catch(e){send(res,500,{message:e.message})}});
server.listen(3211,'127.0.0.1',()=>process.stdout.write('Local test auth/storage proxy ready on 127.0.0.1:3211\n'));
