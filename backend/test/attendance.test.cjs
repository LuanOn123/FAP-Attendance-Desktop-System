const test = require('node:test');
const assert = require('node:assert/strict');
const vm = require('node:vm');
const fs = require('node:fs');
const path = require('node:path');

const context = vm.createContext({});
vm.runInContext(fs.readFileSync(path.join(__dirname, '../apps_script/Code.gs'), 'utf8'), context);

// Mock Utilities
context.Utilities = {
  getUuid: () => 'uuid-' + Math.random().toString(36).substring(2, 9)
};

// Mock LockService
context.LockService = {
  getScriptLock: () => ({
    tryLock: () => true,
    releaseLock: () => {}
  })
};

const teacher = {
  lecturerId: 'toan-se181848',
  email: 'toannvse181848@fpt.edu.vn',
  fullName: 'Nguyen Van Toan',
  department: 'Software Engineering'
};

function createMockBook() {
  const tables = {
    Lecturers: [
      ['lecturerId', 'lecturerCode', 'fullName', 'email', 'department'],
      ['toan-se181848', 'TOANNV', 'Nguyen Van Toan', 'toannvse181848@fpt.edu.vn', 'Software Engineering']
    ],
    Classes: [
      ['classId', 'semester', 'subjectCode', 'subjectName', 'classCode', 'lecturerId'],
      ['cls-001', 'FA26', 'PRM393', 'Mobile Programming', 'SE1818', 'toan-se181848']
    ],
    Students: [
      ['studentId', 'studentCode', 'fullName', 'schoolEmail'],
      ['std-001', 'SE181848', 'Nguyen Van Toan', 'toannvse181848@fpt.edu.vn'],
      ['std-002', 'SE180002', 'Tran Van B', 'tranvbse180002@fpt.edu.vn']
    ],
    Enrollments: [
      ['enrollmentId', 'classId', 'studentId'],
      ['enr-001', 'cls-001', 'std-001']
    ],
    Sessions: [
      ['sessionId', 'classId', 'date', 'slot', 'startTime', 'endTime', 'status', 'currentToken', 'tokenExpiredAt', 'createdBy']
    ],
    Attendance: [
      ['attendanceId', 'sessionId', 'studentId', 'status', 'checkInTime', 'updatedAt', 'note', 'updatedBy']
    ],
    SyncLogs: [
      ['logId', 'action', 'userEmail', 'timestamp', 'description']
    ]
  };

  const sheets = {};
  for (const [name, rows] of Object.entries(tables)) {
    sheets[name] = {
      name,
      rows: rows.map(r => [...r]),
      getDataRange() {
        return {
          getDisplayValues: () => this.rows
        };
      },
      appendRow(row) {
        this.rows.push([...row]);
      },
      getRange(rowIndex, colIndex) {
        const self = this;
        return {
          setValue(val) {
            self.rows[rowIndex - 1][colIndex - 1] = String(val);
          }
        };
      }
    };
  }

  return {
    getSheetByName(name) {
      return sheets[name] || null;
    }
  };
}

test('Teacher can create attendance session and secret code is combined into token', () => {
  const book = createMockBook();
  const cfg = { id: 'sheet-id' };

  const req = {
    action: 'createSession',
    classId: 'cls-001',
    date: '2026-09-17',
    slot: 1,
    startTime: '07:30',
    endTime: '09:00',
    currentToken: 'TKN_123456',
    currentSecretCode: '888999',
    tokenExpiredAt: new Date(Date.now() + 120000).toISOString()
  };

  const session = context.handleSession_(book, cfg, teacher, req);
  assert.equal(session.classId, 'cls-001');
  assert.equal(session.status, 'OPEN');
  assert.equal(session.createdBy, teacher.lecturerId);
  assert.equal(session.currentToken, 'TKN_123456#888999');
  assert.equal(session.currentSecretCode, '888999');

  // Verify stored in Sessions sheet
  const stored = book.getSheetByName('Sessions').rows;
  assert.equal(stored.length, 2);
  assert.equal(stored[1][7], 'TKN_123456#888999');
});

test('Token rotation updates combined token and expiration, only session owner can rotate', () => {
  const book = createMockBook();
  const cfg = { id: 'sheet-id' };

  // Create session
  const created = context.handleSession_(book, cfg, teacher, {
    action: 'createSession',
    classId: 'cls-001',
    date: '2026-09-17',
    slot: 1,
    currentToken: 'TKN_OLD',
    currentSecretCode: '111111'
  });

  // Other teacher cannot rotate
  const otherTeacher = { lecturerId: 'other-gv', email: 'other@fpt.edu.vn' };
  assert.throws(() => context.handleSession_(book, cfg, otherTeacher, {
    action: 'rotateToken',
    sessionId: created.sessionId,
    currentToken: 'TKN_NEW',
    currentSecretCode: '222222'
  }), /Không có quyền sửa phiên điểm danh này/);

  // Owner rotates
  const rotated = context.handleSession_(book, cfg, teacher, {
    action: 'rotateToken',
    sessionId: created.sessionId,
    currentToken: 'TKN_NEW',
    currentSecretCode: '222222',
    tokenExpiredAt: new Date(Date.now() + 120000).toISOString()
  });
  assert.equal(rotated.saved, true);

  const stored = book.getSheetByName('Sessions').rows;
  assert.equal(stored[1][7], 'TKN_NEW#222222');
});

function studentFixture(overrides = {}) {
  const book = createMockBook();
  context.SpreadsheetApp = {openById: () => book};
  context.config_ = () => ({id: 'sheet-id', webAudience: 'web-client', domains: ['fpt.edu.vn']});
  let claims = {aud: 'web-client', iss: 'https://accounts.google.com', exp: Math.floor(Date.now()/1000)+3600,
    email_verified: true, hd: 'fpt.edu.vn', email: 'toannvse181848@fpt.edu.vn', ...overrides};
  context.UrlFetchApp = {fetch: () => ({getResponseCode: () => 200, getContentText: () => JSON.stringify(claims)})};
  const session = context.handleSession_(book, {id:'sheet-id'}, teacher, {action:'createSession', classId:'cls-001', date:'2026-09-22', slot:1,
    startTime:'07:00', endTime:'09:15', currentToken:'VALID_QR', currentSecretCode:'', tokenExpiredAt:new Date(Date.now()+120000).toISOString()});
  const request = {sessionId: session.sessionId, idToken:'valid-google-id-token-for-tests', token:'VALID_QR', confirmPresent:true};
  return {book, session, request, claims};
}
test('QR needs verified school identity and presence, never trusts supplied MSSV', () => {
  const {request, book} = studentFixture();
  assert.throws(() => context.handleStudentCheckIn_({...request, confirmPresent:false}), /xác nhận/);
  assert.throws(() => context.handleStudentCheckIn_({...request, idToken:''}), /đăng nhập/);
  assert.throws(() => context.handleStudentCheckIn_({...request, token:'WRONG'}), /QR/);
  const info = context.handleStudentSession_(request);
  assert.equal(info.student.studentCode, 'SE181848');
  assert.equal(info.session.secretEnabled, false);
  assert.equal(info.session.startTime, '07:00');
  const result = context.handleStudentCheckIn_({...request, studentCode:'SE180002', email:'spoof@example.com'});
  assert.equal(result.status, 'PRESENT'); assert.equal(result.studentCode,'SE181848');
  assert.equal(book.getSheetByName('Attendance').rows[1][2], 'std-001');
  assert.throws(() => context.handleStudentCheckIn_(request), /đã điểm danh/);
});
test('enabled secret requires Google and code even with a valid QR', () => {
  const {request, book, session} = studentFixture();
  assert.throws(() => context.handleStudentCheckIn_({...request, useSecret:true, secretCode:''}), /Secret Code/);
  context.handleSession_(book, {}, teacher, {action:'rotateToken', sessionId:session.sessionId, currentToken:'NEW_QR', currentSecretCode:'123456', tokenExpiredAt:new Date(Date.now()+120000).toISOString()});
  assert.throws(() => context.handleStudentCheckIn_({...request, token:'NEW_QR', useSecret:false}), /Secret Code/);
  assert.throws(() => context.handleStudentCheckIn_({...request, idToken:'', secretCode:'123456'}), /đăng nhập/);
  assert.throws(() => context.handleStudentCheckIn_({...request, useSecret:true, secretCode:'999999'}), /Secret Code/);
  assert.equal(context.handleStudentCheckIn_({...request, useSecret:true, secretCode:'123456', token:''}).status, 'PRESENT');
});
test('reject expired/malformed expiry, wrong audience/domain/unverified/non-enrolled account', () => {
  for (const overrides of [{aud:'desktop-client'}, {email:'a@gmail.com'}, {email_verified:false}, {hd:undefined}, {exp:1}, {email:'tranvbse180002@fpt.edu.vn'}]) {
    const {request} = studentFixture(overrides);
    assert.throws(() => context.handleStudentCheckIn_(request), /trường|danh sách lớp/);
  }
  for (const expiration of ['garbage', new Date(Date.now()-1).toISOString()]) {
    const {request,book} = studentFixture(); book.getSheetByName('Sessions').rows[1][8] = expiration;
    assert.throws(() => context.handleStudentCheckIn_(request), /hết hạn/);
  }
});
test('reset atomically archives old session, retains history and invalidates old QR', () => {
  const {request,book,session} = studentFixture();
  context.handleStudentCheckIn_(request);
  const sheet = book.getSheetByName('Sessions'); sheet.getSheetId = () => 42;
  context.Sheets = {Spreadsheets:{batchUpdate: body => {
    assert.equal(body.requests.length,2);
    const [update, append] = body.requests;
    sheet.rows[update.updateCells.range.startRowIndex][6] = 'RESET';
    sheet.rows.push(append.appendCells.rows[0].values.map(v=>v.userEnteredValue.stringValue));
  }}};
  assert.throws(()=>context.handleSession_(book,{}, {...teacher,lecturerId:'other'},{action:'resetSession',sessionId:session.sessionId}), /quyền/);
  const fresh=context.handleSession_(book,{},teacher,{action:'resetSession',sessionId:session.sessionId});
  assert.notEqual(fresh.sessionId,session.sessionId); assert.equal(fresh.currentSecretCode,'');
  assert.equal(book.getSheetByName('Attendance').rows.length,2);
  assert.throws(()=>context.handleStudentCheckIn_(request),/reset/);
  assert.equal(context.handleSession_(book,{},teacher,{action:'resetSession',sessionId:session.sessionId}).sessionId,fresh.sessionId);
  assert.equal(sheet.rows.length,3);
  assert.throws(() => context.handleSession_(book,{},teacher,{action:'closeSession',sessionId:session.sessionId}), /thay thế/);
  assert.equal(context.handleStudentCheckIn_({...request,sessionId:fresh.sessionId,token:fresh.currentToken}).status,'PRESENT');
});
test('create resumes an existing slot and rejects another lecturer class', () => {
  const {book,session} = studentFixture();
  const request={action:'createSession',classId:'cls-001',date:'2026-09-22',slot:1};
  assert.equal(context.handleSession_(book,{},teacher,request).sessionId,session.sessionId);
  assert.equal(book.getSheetByName('Sessions').rows.length,2);
  assert.throws(()=>context.handleSession_(book,{}, {...teacher,lecturerId:'other'},request), /giảng viên/);
});

test('localized sheet dates preserve a closed session instead of creating another', () => {
  const {book,session} = studentFixture();
  const row = book.getSheetByName('Sessions').rows[1];
  row[2] = '22/9/2026'; row[6] = 'CLOSED';
  const result = context.handleSession_(book,{},teacher,{action:'createSession',classId:'cls-001',date:'2026-09-22',slot:1});
  assert.equal(result.sessionId,session.sessionId);
  assert.equal(result.status,'CLOSED');
  assert.equal(book.getSheetByName('Sessions').rows.length,2);
});

test('typed Sheets date takes priority over a US-formatted display date', () => {
  const {book,session} = studentFixture();
  const sheet = book.getSheetByName('Sessions');
  sheet.rows[1][2] = '9/22/2026'; sheet.rows[1][6] = 'CLOSED';
  const raw = sheet.rows.map(row => [...row]);
  raw[1][2] = new Date('2026-09-21T17:00:00Z');
  raw[1][8] = new Date('2026-09-22T02:00:00Z');
  sheet.getDataRange = () => ({getDisplayValues:()=>sheet.rows.map(row=>[...row]),getValues:()=>raw});
  context.Utilities.formatDate = (date,zone,format) => {
    assert.equal(date.toISOString(),'2026-09-21T17:00:00.000Z');
    assert.equal(zone,'Asia/Ho_Chi_Minh'); assert.equal(format,'yyyy-MM-dd');
    return '2026-09-22';
  };
  const result = context.handleSession_(book,{},teacher,{action:'createSession',classId:'cls-001',date:'2026-09-22',slot:1});
  assert.equal(result.sessionId,session.sessionId);
  assert.equal(result.status,'CLOSED');
  assert.equal(result.tokenExpiredAt,'2026-09-22T02:00:00.000Z');
  assert.equal(sheet.rows.length,2);
});
