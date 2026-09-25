const {test} = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const {JSDOM} = require('../../.tools/extension-tests/node_modules/jsdom');
const html = fs.readFileSync(path.join(__dirname, '../public/index.html'), 'utf8');
const script = fs.readFileSync(path.join(__dirname, '../public/checkin.js'), 'utf8');

async function fixture(t, secretEnabled) {
  const dom = new JSDOM(html, {url:'https://example.com/checkin?sessionId=s1&token=qr', runScripts:'outside-only'});
  t.after(() => dom.window.close());
  const w = dom.window, $ = id => w.document.getElementById(id);
  let login, ready;
  const calls = [];
  w.FAP_CONFIG = {appsScriptUrl:'https://example.com/api',googleWebClientId:'web'};
  w.AbortSignal.timeout = () => undefined;
  w.setInterval = cb => { ready = cb; return 1; };
  w.google = {accounts:{id:{initialize: options => {login = options.callback;},renderButton(){},disableAutoSelect(){}}}};
  w.fetch = async (_, options) => {
    calls.push(JSON.parse(options.body));
    return {ok:true,json:async()=>({ok:true,data:{student:{fullName:'Sinh viên',studentCode:'SE123456',email:'svse123456@fpt.edu.vn'},
      session:{subjectCode:'PRN232',classCode:'SE1917',date:'2026-09-25',slot:1,startTime:'07:00',endTime:'09:15',secretEnabled}}})};
  };
  w.eval(script); ready(); await login({credential:'google-id-token'});
  return {w,$,calls};
}

for (const enabled of [false,true]) test(`Google login follows server secret mode ${enabled}`, async t => {
  const {w,$,calls} = await fixture(t,enabled);
  assert.equal($('lesson').hidden,false);
  assert.equal($('secret-field').hidden,!enabled);
  assert.equal($('use-secret').disabled,true);
  assert.equal($('submit').disabled,true);
  $('presence').checked=true; $('presence').dispatchEvent(new w.Event('change'));
  assert.equal($('submit').disabled,enabled);
  if (enabled) { $('secret').value='123456'; $('secret').dispatchEvent(new w.Event('input')); }
  assert.equal($('submit').disabled,false);
  w.fetch = async (_,options) => {
    calls.push(JSON.parse(options.body));
    return {ok:true,json:async()=>({ok:true,data:{fullName:'Sinh viên',checkInTime:new Date().toISOString()}})};
  };
  $('checkin-form').dispatchEvent(new w.Event('submit',{cancelable:true}));
  await new Promise(resolve=>setImmediate(resolve));
  assert.equal(calls[1].idToken,'google-id-token');
  assert.equal(calls[1].useSecret,enabled);
  assert.equal(calls[1].confirmPresent,true);
  assert.equal($('success').hidden,false);
});

test('switching account ignores a previous pending check-in result', async t => {
  const {w,$} = await fixture(t,false);
  let finish;
  w.fetch = () => new Promise(resolve=>{finish=resolve;});
  $('presence').checked=true;
  $('checkin-form').dispatchEvent(new w.Event('submit',{cancelable:true}));
  $('switch-account').click();
  finish({ok:true,json:async()=>({ok:true,data:{fullName:'Old account',checkInTime:new Date().toISOString()}})});
  await new Promise(resolve=>setImmediate(resolve));
  assert.equal($('success').hidden,true);
  assert.equal($('google-button').hidden,false);
  assert.equal($('login-hint').hidden,false);
  assert.equal($('message').textContent,'');
});
