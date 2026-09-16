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

test('Student Check-In validates secret code, enrollment, and rejects duplicates', () => {
  const book = createMockBook();
  context.SpreadsheetApp = {
    openById: () => book
  };
  context.config_ = () => ({ id: 'sheet-id', audience: 'client', domains: ['fpt.edu.vn'] });

  // Create session
  const session = context.handleSession_(book, { id: 'sheet-id' }, teacher, {
    action: 'createSession',
    classId: 'cls-001',
    date: '2026-09-17',
    slot: 1,
    currentToken: 'TKN_VALID',
    currentSecretCode: '654321',
    tokenExpiredAt: new Date(Date.now() + 120000).toISOString()
  });

  // 1. Check-in with wrong secret code fails
  assert.throws(() => context.handleStudentCheckIn_({
    sessionId: session.sessionId,
    token: 'TKN_VALID',
    secretCode: '999999',
    studentCode: 'SE181848'
  }), /Secret Code không chính xác/);

  // 2. Student not enrolled in class fails
  assert.throws(() => context.handleStudentCheckIn_({
    sessionId: session.sessionId,
    token: 'TKN_VALID',
    secretCode: '654321',
    studentCode: 'SE180002' // std-002 not enrolled in cls-001
  }), /không thuộc danh sách lớp học này/);

  // 3. Valid check-in succeeds
  const checkinResult = context.handleStudentCheckIn_({
    sessionId: session.sessionId,
    token: 'TKN_VALID',
    secretCode: '654321',
    studentCode: 'SE181848'
  });
  assert.equal(checkinResult.ok, true);
  assert.equal(checkinResult.status, 'PRESENT');
  assert.equal(checkinResult.studentCode, 'SE181848');

  // 4. Duplicate check-in fails
  assert.throws(() => context.handleStudentCheckIn_({
    sessionId: session.sessionId,
    token: 'TKN_VALID',
    secretCode: '654321',
    studentCode: 'SE181848'
  }), /đã được ghi nhận điểm danh trước đó/);

  // 5. Close session -> check-in rejected
  context.handleSession_(book, { id: 'sheet-id' }, teacher, {
    action: 'closeSession',
    sessionId: session.sessionId
  });
  assert.throws(() => context.handleStudentCheckIn_({
    sessionId: session.sessionId,
    token: 'TKN_VALID',
    secretCode: '654321',
    studentCode: 'SE181848'
  }), /Phiên điểm danh đã kết thúc/);
});
