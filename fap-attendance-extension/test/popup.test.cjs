const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const {JSDOM} = require('../../.tools/extension-tests/node_modules/jsdom');

async function until(predicate) {
  for (let i = 0; i < 100; i++) {
    if (predicate()) return;
    await new Promise(resolve => setTimeout(resolve, 5));
  }
  assert.fail('Popup did not finish its asynchronous operation');
}

test('popup scans local HTML, requires metadata, sends reviewed payload', async () => {
  const dom = new JSDOM(fs.readFileSync(path.join(__dirname, '../popup/popup.html'), 'utf8'), {runScripts: 'outside-only'});
  const doc = dom.window.document;
  let sent;
  dom.window.chrome = {
    runtime: {sendMessage: async request => {
      if (request.type === 'CHECK_HEALTH') return {status: 'ok'};
      sent = request.data;
      return {success: true, studentCount: 1};
    }},
    extension: {isAllowedFileSchemeAccess: async () => true},
    tabs: {
      query: async () => [{id: 7, url: 'file:///C:/Users/ADMIN/Desktop/New%20folder/attendance.html'}],
      sendMessage: async () => ({success: true, data: {
        source: 'FAP_WEB_DOM', course: {courseCode: 'SWE102', courseName: 'Web'},
        class: {classCode: 'SE1701'}, session: {date: '2026-09-18', slot: null, room: ''},
        students: [{studentCode: 'SE123456', fullName: '<script>not executed</script>', email: 'a@fpt.edu.vn'}]
      }})
    }
  };
  dom.window.eval(fs.readFileSync(path.join(__dirname, '../popup/popup.js'), 'utf8'));
  await until(() => !doc.getElementById('btn-send').disabled);
  assert.equal(doc.getElementById('val-date').value, '2026-09-18');
  assert.equal(doc.getElementById('student-list').querySelector('script'), null);
  doc.getElementById('btn-send').click();
  assert.equal(sent, undefined); // Slot/room/times missing.
  doc.getElementById('val-slot').value = '2';
  doc.getElementById('val-slot').dispatchEvent(new dom.window.Event('change'));
  doc.getElementById('val-room').value = 'AL-201';
  doc.getElementById('btn-send').click();
  await until(() => doc.getElementById('status-text').textContent.includes('Hiện tại'));
  assert.equal(sent.session.slot, 2);
  assert.equal(sent.session.startTime, '10:00');
  assert.equal(sent.session.endTime, '12:20');
  assert.equal(sent.session.date, '2026-09-18');
  dom.window.close();
});

test('file URL permission is actionable rather than a silent scan failure', async () => {
  const dom = new JSDOM(fs.readFileSync(path.join(__dirname, '../popup/popup.html'), 'utf8'), {runScripts: 'outside-only'});
  dom.window.chrome = {
    runtime: {sendMessage: async () => ({status: 'error'})},
    extension: {isAllowedFileSchemeAccess: async () => false},
    tabs: {query: async () => [{id: 7, url: 'file:///attendance.html'}]}
  };
  dom.window.eval(fs.readFileSync(path.join(__dirname, '../popup/popup.js'), 'utf8'));
  await until(() => dom.window.document.getElementById('status-text').textContent.includes('Allow access to file URLs'));
  assert.equal(dom.window.document.getElementById('btn-send').disabled, true);
  dom.window.close();
});

test('failed reinjection reports content connection failure, not missing students', async () => {
  const dom = new JSDOM(fs.readFileSync(path.join(__dirname, '../popup/popup.html'), 'utf8'), {runScripts:'outside-only'});
  dom.window.chrome = {
    runtime: {sendMessage: async () => ({status:'ok'})},
    tabs: {query: async () => [{id:7,url:'https://fap.fpt.edu.vn/Attendance.aspx'}], sendMessage: async () => {throw new Error('Receiving end does not exist');}},
    scripting: {executeScript: async () => {throw new Error('No tab with id');}}
  };
  dom.window.eval(fs.readFileSync(path.join(__dirname, '../popup/popup.js'), 'utf8'));
  await until(() => dom.window.document.querySelector('#status-text').textContent.includes('CONTENT_SCRIPT_NOT_AVAILABLE'));
  assert.equal(dom.window.document.querySelector('#btn-send').disabled,true);
  assert.match(dom.window.document.querySelector('#desktop-text').textContent,/đã kết nối/);
  dom.window.close();
});
