const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const {JSDOM} = require('../../.tools/extension-tests/node_modules/jsdom');
const root=path.join(__dirname,'../..');
const read=name=>fs.readFileSync(path.join(root,name),'utf8');
const flush=()=>new Promise(resolve=>setTimeout(resolve,10));

test('desktop preview reads automatically but writes only after teacher click; changed snapshot requires review', async t=>{
  const dom=new JSDOM(read('attendance.html'),{runScripts:'outside-only',url:'https://fap.fpt.edu.vn/Attendance.aspx'});
  t.after(() => dom.window.close());
  const w=dom.window; let shadow;
  const attach=w.Element.prototype.attachShadow;
  w.Element.prototype.attachShadow=function(options){shadow=attach.call(this,options);return shadow;};
  w.chrome={runtime:{id:'test-extension',onMessage:{addListener(){}},sendMessage:async()=>({success:true,data:payload})}};
  w.eval(read('fap-attendance-extension/content/fapAttendanceScanner.js'));
  w.eval(read('fap-attendance-extension/content/fapAttendanceWriter.js'));
  const data=w.FapAttendanceScanner.scan(w.document);
  let payload={source:'desktop',sessionId:'session1',metadata:{courseCode:data.course.courseCode,classCode:data.class.classCode,...data.session},entries:data.students.map((s,i)=>({studentCode:s.studentCode,status:i===0?'present':'absent'}))};
  const before=[...w.document.querySelectorAll('input[type=radio]')].map(i=>i.checked);
  let submitted=0;w.document.addEventListener('submit',e=>{submitted++;e.preventDefault();});
  w.eval(read('fap-attendance-extension/content/fapSyncPanel.js'));await flush();
  assert.deepEqual([...w.document.querySelectorAll('input[type=radio]')].map(i=>i.checked),before);
  const button=shadow.querySelector('button');assert.equal(button.disabled,false);
  payload={...payload,sessionId:'reset-session'};
  button.click();await flush();
  assert.match(shadow.textContent,/vừa thay đổi/);
  assert.deepEqual([...w.document.querySelectorAll('input[type=radio]')].map(i=>i.checked),before);
  button.click();await flush();
  assert.ok(shadow.textContent.includes('Đã điền ' + data.students.length + ' sinh viên'));assert.equal(submitted,0);
  payload={...payload,metadata:{...payload.metadata,startTime:'10:00'}};
  button.click();await flush();assert.equal(button.disabled,true);assert.match(shadow.textContent,/Giờ học/);
  dom.window.close();
});


