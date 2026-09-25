const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const {JSDOM} = require('../../.tools/extension-tests/node_modules/jsdom');
const {scan} = require('../content/fapAttendanceScanner.js');

test('semantic row IDs win with extra/reordered columns and compound headers', () => {
  const dom = new JSDOM(`<table id="ctl00_mainContent_gvStudents"><tr><th> Full   Name </th><th>Topic</th><th>Member Code / Roll Number</th></tr>
    <tr data-student-code="se183277"><td>Student A</td><td>Example</td><td>SE999999</td></tr>
    <tr><td>Student B</td><td>Example</td><td>SE123456</td></tr></table>`);
  assert.deepEqual(scan(dom.window.document).students.map(s => s.studentCode), ['SE183277', 'SE123456']);
  dom.window.close();
});

test('missing table differs from table without valid codes', () => {
  const wrong = new JSDOM('<p>Other page</p>');
  assert.throws(() => scan(wrong.window.document), e => e.code === 'STUDENT_TABLE_NOT_FOUND');
  const empty = new JSDOM('<table id="ctl00_mainContent_gvStudents"><tr><td>Unknown</td></tr></table>');
  assert.throws(() => scan(empty.window.document), e => e.code === 'STUDENT_CODES_NOT_FOUND');
  wrong.window.close(); empty.window.close();
});

test('card layout: extract actual course, class, date and four students', () => {
  const doc = new JSDOM(`<div class="course-info"><h1>Lập Trình Web (SWE102)</h1>
    <p>Giảng viên: Tran Van B &bull; Lớp: SE1701 &bull; Ngày: 18/09/2026</p></div>
    ${[1,2,3,4].map(n => `<div class="student-card"><h3>Student ${n}</h3>
      <div class="student-meta"><span class="student-code">SE12345${n}</span>
      <span>student${n}@fpt.edu.vn</span></div></div>`).join('')}`).window.document;
  const data = scan(doc);
  assert.equal(data.course.courseCode, 'SWE102');
  assert.equal(data.class.classCode, 'SE1701');
  assert.equal(data.session.date, '2026-09-18');
  assert.equal(data.session.slot, null); // Missing metadata must be reviewed.
  assert.equal(data.session.room, '');
  assert.equal(data.students.length, 4);
});

test('table headers, d/m/yyyy, exact metadata, duplicate roster deduplication', () => {
  const doc = new JSDOM(`<p>Subject: PRM393</p><p>Group: SE1848</p><p>Date: 3/9/2026</p>
    <p>Slot: 2</p><p>Room: AL-201</p><table><tr><th>Roll Number</th><th>Full Name</th><th>Email</th></tr>
    <tr><td>se123456</td><td>Nguyen A</td><td>a@fpt.edu.vn</td></tr>
    <tr><td>SE123456</td><td>Nguyen A</td><td>a@fpt.edu.vn</td></tr></table>`).window.document;
  const data = scan(doc);
  assert.equal(data.session.date, '2026-09-03');
  assert.equal(data.session.slot, 2);
  assert.equal(data.session.room, 'AL-201');
  assert.equal(data.students.length, 1);
});

test('missing date is never silently changed to today', () => {
  const doc = new JSDOM('<div class="student-card"><h3>Student</h3><span class="student-code">SE123456</span></div>').window.document;
  assert.equal(scan(doc).session.date, '');
});

test('conflicting duplicate identity fails instead of losing a student', () => {
  const doc = new JSDOM(['A','B'].map(name => `<div class="student-card"><h3>${name}</h3><span class="student-code">SE123456</span></div>`).join('')).window.document;
  assert.throws(() => scan(doc), /MSSV trùng/);
});

if (process.env.FAP_HTML_FIXTURE) {
  test('scan the user Desktop attendance.html with its rendered students', () => {
    const dom = new JSDOM(fs.readFileSync(path.resolve(process.env.FAP_HTML_FIXTURE), 'utf8'), {runScripts: 'outside-only'});
    // Run this explicitly supplied local fixture; never run untrusted remote HTML.
    for (const script of dom.window.document.querySelectorAll('script:not([src])')) dom.window.eval(script.textContent);
    const data = scan(dom.window.document);
    assert.equal(data.course.courseCode, 'SWE102');
    assert.equal(data.class.classCode, 'SE1701');
    assert.equal(data.session.date, '2026-09-18');
    assert.equal(data.students.length, 4);
    assert.equal(data.students[0].studentCode, 'SE123456');
    dom.window.close();
  });
}
