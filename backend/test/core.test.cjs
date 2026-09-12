const test = require('node:test');
const assert = require('node:assert/strict');
const vm = require('node:vm');
const fs = require('node:fs');
const path = require('node:path');
const context = vm.createContext({});
vm.runInContext(fs.readFileSync(path.join(__dirname, '../apps_script/Code.gs'), 'utf8'), context);
const lecturer = {lecturerId: 'l1'};
function row(overrides = {}) { return {scheduleId: 's1', lecturerId: 'l1', semester: 'FA26', subjectCode: 'PRM393', subjectName: 'Mobile', classCode: 'SE1848', dayOfWeek: 1, slot: 1, startTime: '07:30', endTime: '09:00', room: 'AL201', sourceType: 'IMAGE', ...overrides}; }
test('Entire batch validated before mutation; retry same ID is idempotent', () => {
  const initial = [row()];
  assert.throws(() => context.mutateSchedules_(initial, 'batchUpdate', {rows: [row({room: 'New'}), row({scheduleId: 's2', startTime: '30:00'})]}, lecturer));
  assert.equal(initial[0].room, 'AL201');
  const next = context.mutateSchedules_(initial, 'batchUpdate', {rows: [row({room: 'New'})]}, lecturer);
  assert.equal(next.length, 1);
  assert.equal(next[0].room, 'New');
  assert.equal(context.mutateSchedules_(next, 'batchUpdate', {rows: [row({room: 'New'})]}, lecturer).length, 1);
});
test('No cross-lecturer update/delete or forged ownership', () => {
  const existing = [row({lecturerId: 'l2'})];
  assert.throws(() => context.mutateSchedules_(existing, 'deleteRow', {id: 's1'}, lecturer));
  assert.throws(() => context.mutateSchedules_(existing, 'batchUpdate', {rows: [row()]}, lecturer));
  assert.throws(() => context.validateSchedule_(row({lecturerId: 'l2'}), lecturer));
});
test('Reject duplicate schedules, IDs and inconsistent updates', () => {
  assert.throws(() => context.mutateSchedules_([], 'batchUpdate', {rows: [row(), row()]}, lecturer));
  assert.throws(() => context.mutateSchedules_([row()], 'appendRow', {row: row({scheduleId: 's2'})}, lecturer));
  assert.throws(() => context.mutateSchedules_([row()], 'updateRow', {id: 'other', row: row()}, lecturer));
});
test('Normalize codes and validate time/day/source', () => {
  assert.equal(context.validateSchedule_(row({subjectCode: ' prm393 '}), lecturer).subjectCode, 'PRM393');
  for (const invalid of [{dayOfWeek: 0}, {slot: 13}, {startTime: '09:00'}, {endTime: '25:00'}, {sourceType: 'AUTO'}]) {
    assert.throws(() => context.validateSchedule_(row(invalid), lecturer));
  }
});
test('Google claims reject wrong audience, unverified email, expired token and domain spoofing', () => {
  const claims = {aud: 'client', iss: 'https://accounts.google.com', exp: Date.now() / 1000 + 3600, email_verified: 'true', email: 'teacher@fpt.edu.vn'};
  context.UrlFetchApp = {fetch: () => ({getResponseCode: () => 200, getContentText: () => JSON.stringify(claims)})};
  const book = {getSheetByName: () => ({getDataRange: () => ({getDisplayValues: () => [['lecturerId','lecturerCode','fullName','email','department'], ['l1','GV','Teacher','teacher@fpt.edu.vn','IT']]})})};
  const cfg = {audience: 'client', domains: ['fpt.edu.vn']};
  assert.equal(context.authenticate_('x'.repeat(30), cfg, book).lecturerId, 'l1');
  for (const [key, value] of [['aud', 'attacker'], ['email_verified', false], ['exp', 0], ['email', 'teacher@fpt.edu.vn.evil.com']]) {
    const previous = claims[key]; claims[key] = value;
    assert.throws(() => context.authenticate_('x'.repeat(30), cfg, book));
    claims[key] = previous;
  }
});
