export function normalizeUsername(value){return typeof value==='string'?value.trim().toLowerCase():'';}
export function validUsername(value){return /^[a-z0-9][a-z0-9_.-]{2,31}$/.test(value);}
export function validPassword(value,min=8){return typeof value==='string'&&value.length>=min&&value.length<=128;}
export const reservedUsernames=new Set(['admin','administrator','root','superadmin','support','system']);
