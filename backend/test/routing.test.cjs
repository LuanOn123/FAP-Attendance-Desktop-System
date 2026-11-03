const test = require('node:test');
const assert = require('node:assert/strict');
const vm = require('node:vm');
const fs = require('node:fs');
const path = require('node:path');

test('HTTP student actions never fall through to lecturer authentication', () => {
  const context = vm.createContext({});
  vm.runInContext(fs.readFileSync(path.join(__dirname, '../apps_script/Code.gs'), 'utf8'), context);
  context.ContentService = {MimeType: {JSON: 'application/json'},
    createTextOutput: text => ({setMimeType: () => JSON.parse(text)})};
  context.config_ = () => ({id: 'test', webAudience: 'web-client', domains: ['fpt.edu.vn']});
  context.SpreadsheetApp = {openById: () => ({})};
  context.LockService = {getScriptLock: () => ({tryLock: () => true, releaseLock() {}})};
  let lecturerCalls = 0;
  context.handle_ = () => { lecturerCalls++; return {lecturer: true}; };
  for (const action of ['studentSessionInfo', 'studentCheckIn']) {
    const result = context.doPost({postData: {contents: JSON.stringify({action, idToken: '', confirmPresent: true})}});
    assert.equal(result.ok, false);
    assert.equal(result.error, 'Vui lòng đăng nhập email trường.');
  }
  assert.equal(lecturerCalls, 0);
  const codeResult = context.doPost({postData: {contents: '{"action":"studentCodeCheckIn","confirmPresent":true,"studentCode":""}'}});
  assert.equal(codeResult.error, 'Vui lòng nhập MSSV hợp lệ.');
  context.handleStudentCodeSession_ = () => ({checkInMode: 'student-code-v2'});
  assert.equal(context.doPost({postData: {contents: '{"action":"studentCodeSessionInfo"}'}}).data.checkInMode, 'student-code-v2');
  assert.equal(lecturerCalls, 0);
  assert.equal(context.doPost({postData: {contents: '{"action":"login"}'}}).ok, true);
  assert.equal(lecturerCalls, 1);
});
