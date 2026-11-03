const {test} = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const {JSDOM} = require('../../.tools/extension-tests/node_modules/jsdom');
const html = fs.readFileSync(path.join(__dirname,'../public/index.html'),'utf8');
const script = fs.readFileSync(path.join(__dirname,'../public/checkin.js'),'utf8');
const flush = () => new Promise(resolve=>setImmediate(resolve));
async function fixture(t, secretEnabled, error) {
  const dom = new JSDOM(html,{url:'https://example.com/checkin?sessionId=s1&token=qr&mode=student-code',runScripts:'outside-only'});
  t.after(()=>dom.window.close());
  const w=dom.window, $=id=>w.document.getElementById(id), calls=[];
  w.FAP_CONFIG={appsScriptUrl:'https://example.com/api'};
  w.fetch=async (_,options)=>{
    const req=JSON.parse(options.body); calls.push(req);
    return {ok:true,json:async()=>error ? {ok:false,error} : {ok:true,data:req.action==='studentCodeSessionInfo' ? {
      checkInMode:'student-code-v2',session:{classCode:'SE1917',subjectCode:'PRN232',date:'2026-09-25',slot:1,startTime:'07:00',endTime:'09:15',secretEnabled}
    } : {fullName:'Student',studentCode:'SE123456'}}};
  };
  w.eval(script); await flush(); return {w,$,calls};
}
for (const secret of [false,true]) test(`MSSV and presence required, server secret mode ${secret}`,async t=>{
  const {w,$,calls}=await fixture(t,secret);
  assert.equal($('lesson').hidden,false);
  assert.equal($('secret-field').hidden,!secret);
  assert.equal($('google-button').hidden,true);
  const submit=()=> $('checkin-form').dispatchEvent(new w.Event('submit',{cancelable:true}));
  submit(); await flush(); assert.equal(calls.length,1);
  $('student-code').value='se123456'; $('student-code').dispatchEvent(new w.Event('input'));
  submit(); await flush(); assert.equal(calls.length,1);
  $('presence').checked=true; $('presence').dispatchEvent(new w.Event('change'));
  assert.equal($('submit').disabled,secret);
  if(secret) { submit(); await flush(); assert.equal(calls.length,1); $('secret').value='123456'; $('secret').dispatchEvent(new w.Event('input')); }
  submit(); submit(); await flush();
  assert.equal(calls.length,2); assert.equal(calls[1].action,'studentCodeCheckIn');
  assert.equal(calls[1].studentCode,'SE123456'); assert.equal(calls[1].idToken,undefined);
  assert.equal(calls[1].confirmPresent,true); assert.equal(calls[1].secretCode,secret?'123456':'');
  assert.equal($('success').hidden,false);
  submit(); await flush(); assert.equal(calls.length,2);
});
test('stale deployment error is actionable and keeps check-in disabled',async t=>{
  const {$}=await fixture(t,false,'Cần đăng nhập Google.');
  assert.match($('message').textContent,/phiên bản mới/);
  assert.equal($('retry').hidden,false); assert.equal($('submit').disabled,true);
});

test('Google popup callback retains QR, shows lesson on the same page and records presence once', async t => {
  const dom = new JSDOM(html,{url:'https://example.com/checkin?sessionId=s1&token=qr',runScripts:'outside-only'});
  t.after(()=>dom.window.close());
  const w=dom.window, $=id=>w.document.getElementById(id), calls=[];
  let config;
  w.FAP_CONFIG={appsScriptUrl:'https://example.com/api',googleWebClientId:'web-client'};
  w.google={accounts:{id:{initialize:c=>config=c,renderButton(){},disableAutoSelect(){}}}};
  w.fetch=async (_,options)=>{
    const request=JSON.parse(options.body); calls.push(request);
    return {ok:true,json:async()=>({ok:true,data:request.action==='studentSessionInfo' ? {
      student:{fullName:'Student',studentCode:'SE123456',email:'student@fpt.edu.vn'},
      session:{subjectName:'Mobile',subjectCode:'PRM393',classCode:'SE1928',date:'2026-10-09',slot:1,startTime:'07:00',endTime:'09:15',secretEnabled:true}
    } : {fullName:'Student',studentCode:'SE123456'}})};
  };
  w.eval(script); await new Promise(resolve=>setTimeout(resolve,180));
  assert.equal(config.ux_mode,'popup'); assert.equal(config.use_fedcm_for_button,false);
  await config.callback({credential:'verified-by-backend-token'}); await flush();
  assert.equal(w.location.href,'https://example.com/checkin?sessionId=s1&token=qr');
  assert.equal($('lesson').hidden,false); assert.equal($('identity').hidden,false);
  assert.equal($('code-field').hidden,true); assert.equal($('course').textContent,'Mobile · SE1928');
  assert.equal(calls[0].token,'qr'); assert.equal(calls[0].idToken,'verified-by-backend-token');
  $('presence').checked=true; $('presence').dispatchEvent(new w.Event('change'));
  assert.equal($('submit').disabled,true);
  $('secret').value='123456'; $('secret').dispatchEvent(new w.Event('input'));
  $('checkin-form').dispatchEvent(new w.Event('submit',{cancelable:true}));
  $('checkin-form').dispatchEvent(new w.Event('submit',{cancelable:true})); await flush();
  assert.equal(calls.length,2); assert.equal(calls[1].action,'studentCheckIn');
  assert.equal(calls[1].token,'qr'); assert.equal(calls[1].secretCode,'123456');
  assert.equal($('success').hidden,false); assert.equal($('authentication').hidden,true);
});

test('Google verification failure keeps visible UI and permits retry or switching to MSSV', async t => {
  const dom = new JSDOM(html,{url:'https://example.com/checkin?sessionId=s1&token=qr',runScripts:'outside-only'});
  t.after(()=>dom.window.close());
  const w=dom.window, $=id=>w.document.getElementById(id); let config;
  w.FAP_CONFIG={appsScriptUrl:'https://example.com/api',googleWebClientId:'web-client'};
  w.google={accounts:{id:{initialize:c=>config=c,renderButton(){},disableAutoSelect(){}}}};
  w.fetch=async()=>({ok:true,json:async()=>({ok:false,error:'Email chưa có trong danh sách lớp.'})});
  w.eval(script); await new Promise(resolve=>setTimeout(resolve,180));
  await config.callback({credential:'token'}); await flush();
  assert.match($('message').textContent,/Email chưa có/);
  assert.equal($('authentication').hidden,false); assert.equal($('retry').hidden,false);
  assert.equal($('submit').disabled,true); assert.equal(w.location.pathname,'/checkin');
  $('switch-mode').click(); await flush(); assert.equal($('google-button').hidden,true);
});
