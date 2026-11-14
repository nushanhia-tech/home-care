import {build} from 'esbuild';
import {mkdir,readFile,writeFile,cp,readdir} from 'node:fs/promises';
await mkdir('dist/server',{recursive:true});
await build({entryPoints:['src/main.jsx'],bundle:true,minify:true,outfile:'dist/app.js',format:'iife',jsx:'automatic',define:{'process.env.NODE_ENV':'"production"'}});
const js=await readFile('dist/app.js','utf8'),css=await readFile('src/style.css','utf8'),house=await readFile('src/house.svg','utf8');
const html=`<!doctype html><html lang="en"><head><meta charset="UTF-8"/><meta name="viewport" content="width=device-width,initial-scale=1.0"/><meta name="theme-color" content="#0e98e8"/><meta name="description" content="Your neighbourhood. Your trusted helpers. Discover local services in Pattambi, Kerala."/><title>Local Mate — Your neighbourhood, taken care of</title><link rel="preconnect" href="https://fonts.googleapis.com"><link rel="preconnect" href="https://fonts.gstatic.com" crossorigin><link href="https://fonts.googleapis.com/css2?family=DM+Sans:wght@400;500;600;700&family=Manrope:wght@400;500;600;700;800&display=swap" rel="stylesheet"><style>${css}</style></head><body><div id="root"></div><script>${js.replaceAll('</script','<\\/script')}</script></body></html>`;
const assets={};for(const file of await readdir('public/assets')){assets['/assets/'+file]=(await readFile('public/assets/'+file)).toString('base64');}
await writeFile('dist/document.js',`export const html=${JSON.stringify(html)}; export const house=${JSON.stringify(house)}; export const assets=${JSON.stringify(assets)};`);
await build({entryPoints:['src/worker.js'],bundle:true,format:'esm',platform:'browser',outfile:'dist/server/index.js',minify:true});
await mkdir('dist/.openai',{recursive:true});await cp('.openai/hosting.json','dist/.openai/hosting.json');await cp('migrations','dist/migrations',{recursive:true});
console.log('Built React application and Worker API.');
