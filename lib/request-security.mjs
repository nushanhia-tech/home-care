/** Next's internal URL may use localhost behind a proxy; Host remains the browser's target. */
export function sameOrigin(origin,requestUrl,host){
 if(!origin)return true;
 try{
  const source=new URL(origin),target=new URL(requestUrl);
  if(source.origin===target.origin)return true;
  return !!host&&source.origin===new URL(target.protocol+'//'+host).origin;
 }catch{return false;}
}
