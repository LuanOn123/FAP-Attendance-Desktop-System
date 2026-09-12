const test = require('node:test');
const assert = require('node:assert/strict');
const vm = require('node:vm');
const fs = require('node:fs');
const path = require('node:path');
const ctx = vm.createContext({});
vm.runInContext(fs.readFileSync(path.join(__dirname, '../apps_script/Code.gs'), 'utf8'), ctx);
const owner = {lecturerId: 'l1'};
const target = {semester: 'FA26', subjectCode: 'PRN232', classCode: 'SE1917'};
const student = {classCode: 'SE1917', studentCode: 'SE000001', fullName: 'Student A', schoolEmail: 'a@example.com'};
let id = 0; const uuid = () => `id-${++id}`;
const initial = () => ({classes: [], students: [], enrollments: [], schedules: [{...target, lecturerId: 'l1', subjectName: 'Development'}]});
const request = (students = [student]) => ({...target, students});
test('Import creates class from owned schedule and retry adds nothing', () => {
  const state = initial();
  const next = ctx.importRoster_(request(), state, owner, uuid);
  assert.equal(next.added, 1); assert.equal(next.classes.length, 1);
  assert.equal(state.classes.length, 0); assert.equal(state.students.length, 0);
  const again = ctx.importRoster_(request(), {...next, schedules: state.schedules}, owner, uuid);
  assert.equal(again.added, 0); assert.equal(again.existing, 1);
  assert.equal(again.students.length, 1); assert.equal(again.enrollments.length, 1);
});
test('Shared student reused across subjects, email preserved', () => {
  const state = initial();
  const first = ctx.importRoster_(request(), state, owner, uuid);
  const nextState = {...first, schedules: [...state.schedules, {...state.schedules[0], subjectCode: 'PRM393'}]};
  const next = ctx.importRoster_({...request([{...student, schoolEmail: 'changed@example.com'}]), subjectCode: 'PRM393'}, nextState, owner, uuid);
  assert.equal(next.students.length, 1); assert.equal(next.classes.length, 2); assert.equal(next.enrollments.length, 2);
  assert.equal(next.students[0].schoolEmail, 'a@example.com');
});
test('Wrong owner, class, semester, subject and ambiguous class are rejected', () => {
  const state = initial();
  assert.throws(() => ctx.importRoster_(request(), state, {lecturerId: 'l2'}, uuid));
  for (const change of [{classCode:'SE9999'}, {semester:'SP26'}, {subjectCode:'PRM393'}]) {
    assert.throws(() => ctx.importRoster_({...request(), ...change}, state, owner, uuid));
  }
  assert.throws(() => ctx.importRoster_(request([{...student, classCode:'SE9999'}]), state, owner, uuid));
  state.classes = [{...target, classId:'c1',lecturerId:'l1'}, {...target, classId:'c2',lecturerId:'l1'}];
  assert.throws(() => ctx.importRoster_(request(), state, owner, uuid));
});
test('Invalid batch does not mutate input, conflicting identity is rejected', () => {
  const state = initial();
  assert.throws(() => ctx.importRoster_(request([student, {...student, studentCode:'',fullName:''}]), state, owner, uuid));
  assert.equal(state.students.length, 0); assert.equal(state.enrollments.length, 0);
  assert.throws(() => ctx.importRoster_(request([student, {...student, fullName:'Different'}]), state, owner, uuid));
  const next = ctx.importRoster_(request(), state, owner, uuid);
  assert.throws(() => ctx.importRoster_(request([{...student, fullName:'Different'}]), {...next,schedules:state.schedules}, owner, uuid));
});
