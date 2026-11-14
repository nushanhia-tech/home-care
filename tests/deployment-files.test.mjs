import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readdir } from 'node:fs/promises';
import { fileURLToPath } from 'node:url';
import { spawnSync } from 'node:child_process';
const root=fileURLToPath(new URL('../',import.meta.url));
const rules=fileURLToPath(new URL('../.vercelignore',import.meta.url));
function excluded(paths){
 const result=spawnSync('git',['-c','core.excludesFile='+rules,'check-ignore','--no-index','--stdin'],{cwd:root,input:paths.join('\n')+'\n',encoding:'utf8'});
 assert.ok([0,1].includes(result.status),result.stderr);
 return result.stdout.trim().split('\n').filter(Boolean);
}
async function files(directory){
 const entries=await readdir(new URL('../'+directory+'/',import.meta.url),{withFileTypes:true});
 const found=await Promise.all(entries.map(entry=>entry.isDirectory()?files(directory+'/'+entry.name):[directory+'/'+entry.name]));
 return found.flat();
}
test('Vercel upload retains application modules and public assets, including nested Supabase clients',async()=>{
 const runtime=[...(await files('app')),...(await files('lib')),...(await files('src')),...(await files('public')),'proxy.ts','next.config.ts','tsconfig.json','package.json','package-lock.json'];
 assert.deepEqual(excluded(runtime),[],'Deployment ignore rules must not remove runtime imports or assets.');
});
test('Vercel upload excludes root database migrations and tests',()=>{
 const development=['supabase/migrations/20261114000100_marketplace.sql','tests/database.test.mjs'];
 assert.deepEqual(excluded(development),development);
});
