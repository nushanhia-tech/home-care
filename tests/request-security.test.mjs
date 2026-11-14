import {test} from 'node:test';
import assert from 'node:assert/strict';
import {sameOrigin} from '../lib/request-security.mjs';
test('same-origin writes work when Next uses an internal localhost URL',()=>{assert.equal(sameOrigin('http://127.0.0.1:3000','http://localhost:3000/api/auth/signin','127.0.0.1:3000'),true);assert.equal(sameOrigin('https://localmate.example','https://internal.vercel.app/api/profile','localmate.example'),true)});
test('cross-origin, cross-scheme, and malformed origins remain blocked',()=>{assert.equal(sameOrigin('https://evil.example','https://localmate.example/api/profile','localmate.example'),false);assert.equal(sameOrigin('http://localmate.example','https://localmate.example/api/profile','localmate.example'),false);assert.equal(sameOrigin('null','https://localmate.example/api/profile','localmate.example'),false)});
