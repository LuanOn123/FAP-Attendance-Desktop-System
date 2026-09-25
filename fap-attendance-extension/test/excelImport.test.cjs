const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const {JSDOM} = require('../../.tools/extension-tests/node_modules/jsdom');
const XLSX = require('../vendor/xlsx.full.min.js');
const {read, parseRows} = require('../shared/attendanceWorkbook.js');
const {scan} = require('../content/fapAttendanceScanner.js');
const {plan, apply} = require('../content/fapAttendanceWriter.js');
const filename = 'Diemdanh_PRN232_SE1917_2026-09-22_Slot1.xlsx';
const headers = ['MSSV', 'Trạng thái', 'Lớp học', 'Mã môn', 'Họ và tên', 'Ký hiệu FAP'];
const input = () => [headers, ['SE193416', 'PRESENT', 'SE1917', 'PRN232', 'Student A', 'P'], ['SA194282', 'ABSENT', 'SE1917', 'PRN232', 'Student B', 'A']];
const payload = () => parseRows(input(), filename);
function fixture(codes = ['SA194282', 'SE193416', 'SS180069']) {
  const dom = new JSDOM(`<p>Subject: PRN232</p><p>Group: SE1917</p><p>Date: 22/09/2026</p><p>Slot: 1</p>
    <form><table><tr><th>Roll Number</th><th>Full Name</th><th>Status</th></tr>${codes.map((code, i) => `<tr><td>${code}</td><td>Student ${i}</td><td>
    <label><input type="radio" name="r${i}" value="0">Absent</label><label><input type="radio" name="r${i}" value="1">Present</label></td></tr>`).join('')}</table><button type="submit">Save</button></form>`);
  return dom;
}
test('Excel parses statuses, exact metadata and late mapping', () => {
  const rows = input(); rows[1][1] = 'LATE'; rows[1][5] = 'L';
  const result = parseRows(rows, filename);
  assert.equal(result.entries[0].status, 'present');
  assert.equal(result.metadata.date, '2026-09-22');
  assert.equal(result.metadata.slot, 1);
});
test('reject duplicate codes, unknown status, conflicting symbol, wrong course and filename', () => {
  assert.throws(() => parseRows([...input(), input()[1]], filename), /trùng/);
  let rows = input(); rows[1][1] = 'UNKNOWN'; assert.throws(() => parseRows(rows, filename), /không hỗ trợ/);
  rows = input(); rows[1][5] = 'A'; assert.throws(() => parseRows(rows, filename), /mâu thuẫn/);
  rows = input(); rows[1][3] = 'PRM393'; assert.throws(() => parseRows(rows, filename), /không khớp/);
  assert.throws(() => parseRows(input(), 'random.xlsx'), /tên file/);
});
test('preview never changes controls; apply matches shuffled MSSVs, emits change and never submits', () => {
  const dom = fixture(), doc = dom.window.document;
  let changes = 0, submits = 0;
  doc.addEventListener('change', () => changes++);
  doc.addEventListener('submit', e => { e.preventDefault(); submits++; });
  assert.equal(plan(doc, payload(), scan).unchanged, 1);
  assert.equal(doc.querySelectorAll(':checked').length, 0);
  assert.equal(apply(doc, payload(), scan).applied, 2);
  assert.equal(doc.querySelector('input[name=r0]:checked').value, '0');
  assert.equal(doc.querySelector('input[name=r1]:checked').value, '1');
  assert.equal(doc.querySelector('input[name=r2]:checked'), null);
  assert.equal(changes, 2); assert.equal(submits, 0);
  apply(doc, payload(), scan); assert.equal(changes, 2);
  dom.window.close();
});
test('preflight blocks all writes for missing/duplicate students or disabled controls', () => {
  for (const dom of [fixture(['SE193416']), fixture(['SE193416', 'SA194282', 'SE193416']), fixture()]) {
    const doc = dom.window.document;
    if (doc.querySelectorAll('tr').length === 4) doc.querySelector('input').disabled = true;
    assert.throws(() => apply(doc, payload(), scan));
    assert.equal(doc.querySelectorAll(':checked').length, 0);
    dom.window.close();
  }
});
test('block different date, slot, course and class before any changes', () => {
  for (const key of ['date', 'slot', 'courseCode', 'classCode']) {
    const dom = fixture(), data = payload(); data.metadata[key] = 'wrong';
    assert.throws(() => apply(dom.window.document, data, scan), /Sai hoặc thiếu/);
    assert.equal(dom.window.document.querySelectorAll(':checked').length, 0); dom.window.close();
  }
});
test('read compressed XLSX, reject formulas and multiple attendance sheets', () => {
  const book = XLSX.utils.book_new();
  XLSX.utils.book_append_sheet(book, XLSX.utils.aoa_to_sheet(input()), 'Results');
  const bytes = () => XLSX.write(book, {type: 'array', bookType: 'xlsx', compression: true});
  assert.equal(read(bytes(), filename, XLSX).entries.length, 2);
  book.Sheets.Results.A2.f = '"SE193416"';
  assert.throws(() => read(bytes(), filename, XLSX), /công thức/);
  delete book.Sheets.Results.A2.f;
  XLSX.utils.book_append_sheet(book, XLSX.utils.aoa_to_sheet(input()), 'Another');
  assert.throws(() => read(bytes(), filename, XLSX), /đúng một sheet/);
});
if (process.env.FAP_EXCEL_FIXTURE) test('actual exported workbook fills the 35-student HTML fixture after reorder', () => {
  const data = read(fs.readFileSync(process.env.FAP_EXCEL_FIXTURE), path.basename(process.env.FAP_EXCEL_FIXTURE), XLSX);
  const dom = new JSDOM(fs.readFileSync(path.join(__dirname, '../../attendance.html'), 'utf8'), {runScripts: 'dangerously'});
  const doc = dom.window.document;
  doc.querySelector('#reverse').click();
  // The user's HTML represents another date/slot. Prove rejection first,
  // then change only this in-memory test page to the workbook's session.
  const before = [...doc.querySelectorAll('input')].map(input => input.checked);
  assert.throws(() => apply(doc, data, scan), /Sai hoặc thiếu/);
  assert.deepEqual([...doc.querySelectorAll('input')].map(input => input.checked), before);
  for (const span of doc.querySelectorAll('span')) {
    if (/^Date:/.test(span.textContent.trim())) span.textContent = 'Date: ' + data.metadata.date;
    if (/^Slot:/.test(span.textContent.trim())) span.textContent = 'Slot: ' + data.metadata.slot;
  }
  const result = apply(doc, data, scan);
  assert.equal(result.applied, 35); assert.equal(result.present, 1); assert.equal(result.absent, 34);
  for (const entry of data.entries) {
    assert.equal(doc.querySelector(`[data-student-code="${entry.studentCode}"] input:checked`).value, entry.status === 'present' ? '1' : '0');
  }
  assert.equal(doc.querySelector('#presentCount').textContent, '1');
  assert.equal(doc.querySelector('#absentCount').textContent, '34');
  assert.equal(doc.querySelector('#notice').textContent, '');
  dom.window.close();
});

for (const actual of process.env.FAP_EXCEL_FIXTURE ? [false, true] : [false]) test(`popup imports ${actual ? 'actual 35-row' : 'generated'} XLSX and applies only after Start, even when desktop is offline`, async () => {
  const page = actual ? new JSDOM(fs.readFileSync(path.join(__dirname, '../../attendance.html'), 'utf8'), {runScripts:'dangerously'}) : fixture();
  const uploadName = actual ? path.basename(process.env.FAP_EXCEL_FIXTURE) : filename;
  const count = actual ? 35 : 2;
  const popup = new JSDOM(fs.readFileSync(path.join(__dirname, '../popup/popup.html'), 'utf8'), {runScripts: 'outside-only'});
  const doc = popup.window.document;
  const wait = async predicate => {
    for (let i = 0; i < 150; i++) { if (predicate()) return; await new Promise(r => setTimeout(r, 5)); }
    assert.fail(doc.querySelector('#import-summary').textContent + ' / ' + doc.querySelector('#import-result').textContent);
  };
  const book = XLSX.utils.book_new(); XLSX.utils.book_append_sheet(book, XLSX.utils.aoa_to_sheet(input()), 'Results');
  const bytes = actual ? fs.readFileSync(process.env.FAP_EXCEL_FIXTURE) : XLSX.write(book, {type: 'array', bookType: 'xlsx'});
  if (actual) {
    const data = read(bytes, uploadName, XLSX);
    for (const span of page.window.document.querySelectorAll('span')) {
      if (/^Date:/.test(span.textContent.trim())) span.textContent = 'Date: ' + data.metadata.date;
      if (/^Slot:/.test(span.textContent.trim())) span.textContent = 'Slot: ' + data.metadata.slot;
    }
    page.window.document.querySelector('#reset').click();
    page.window.document.querySelector('#reverse').click();
  }
  let activeId = 7;
  popup.window.AttendanceWorkbook = {read}; popup.window.XLSX = XLSX;
  popup.window.chrome = {
    runtime: {sendMessage: async () => ({status: 'error', message: 'Offline'})},
    extension: {isAllowedFileSchemeAccess: async () => true},
    scripting: {executeScript: async () => []},
    tabs: {query: async () => [{id: activeId, url: 'file:///attendance.html'}], sendMessage: async (id, message) => {
      try { return {success: true, data: message.type === 'SCAN_ATTENDANCE' ? scan(page.window.document) :
        (message.type === 'PREVIEW_ATTENDANCE' ? plan : apply)(page.window.document, message.data, scan)}; }
      catch (e) { return {success: false, message: e.message}; }
    }},
  };
  popup.window.eval(fs.readFileSync(path.join(__dirname, '../popup/popup.js'), 'utf8') + '\n' + fs.readFileSync(path.join(__dirname, '../popup/excelImport.js'), 'utf8'));
  await wait(() => doc.querySelector('#status-text').textContent.includes('Đã quét'));
  const fileInput = doc.querySelector('#attendance-file');
  Object.defineProperty(fileInput, 'files', {value: [{name: uploadName, size: bytes.byteLength, arrayBuffer: async () => bytes}], configurable: true});
  fileInput.dispatchEvent(new popup.window.Event('change'));
  await wait(() => !doc.querySelector('#btn-auto-attendance').disabled);
  assert.equal(doc.querySelector('#btn-send').disabled, true);
  assert.equal(page.window.document.querySelectorAll('input:checked').length, 0);
  doc.querySelector('#btn-rescan').click();
  await wait(() => !doc.querySelector('#btn-auto-attendance').disabled);
  assert.ok(doc.querySelector('#import-summary').textContent.includes(`Khớp ${count}/${count}`));
  doc.querySelector('#btn-auto-attendance').click();
  await wait(() => doc.querySelector('#import-result').textContent.includes(`Đã điền ${count} dòng`));
  assert.equal(page.window.document.querySelectorAll('input:checked').length, count);
  // Changed active tab must invalidate the next preview rather than write elsewhere.
  activeId = 9;
  fileInput.dispatchEvent(new popup.window.Event('change'));
  await wait(() => doc.querySelector('#import-summary').textContent.includes('Tab đã thay đổi'));
  assert.equal(doc.querySelector('#btn-auto-attendance').disabled, true);
  popup.window.close(); page.window.close();
});

test('symbol fallback, aliases and normalized status preserve strict validation', () => {
  const result = parseRows([['Student Code', 'FAP', 'Class', 'Subject'],
    ['se123456', 'p', 'SE1917', 'PRN232'], ['SE123457', 'a', 'SE1917', 'PRN232']], filename);
  assert.deepEqual(result.entries.map(e => e.status), ['present', 'absent']);
  assert.throws(() => parseRows([['MSSV','Trạng thái','Ký hiệu FAP','Lớp học','Mã môn'],
    ['SE123456','unknown','P','SE1917','PRN232']], filename), /không hỗ trợ/);
});

test('Excel may omit unavailable page metadata but known mismatches remain blocked', () => {
  const dom = fixture();
  dom.window.document.querySelectorAll('p').forEach(p => p.remove());
  assert.equal(plan(dom.window.document, payload(), scan).matched, 2);
  assert.throws(() => plan(dom.window.document, {...payload(), source:'desktop'}, scan), /Sai hoặc thiếu/);
  dom.window.close();
});
