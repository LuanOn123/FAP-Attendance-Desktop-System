/* Member 1 API. Never trust lecturerId/email supplied by a desktop client. */
const SCHEMA = Object.freeze({
  Lecturers: ['lecturerId', 'lecturerCode', 'fullName', 'email', 'department'],
  Schedules: ['scheduleId', 'lecturerId', 'semester', 'subjectCode', 'subjectName', 'classCode', 'dayOfWeek', 'slot', 'startTime', 'endTime', 'room', 'sourceType'],
  Classes: ['classId', 'semester', 'subjectCode', 'subjectName', 'classCode', 'lecturerId'],
  Students: ['studentId', 'studentCode', 'fullName', 'schoolEmail'],
  Enrollments: ['enrollmentId', 'classId', 'studentId'],
  Sessions: ['sessionId', 'classId', 'date', 'slot', 'startTime', 'endTime', 'status', 'currentToken', 'tokenExpiredAt', 'createdBy'],
  Attendance: ['attendanceId', 'sessionId', 'studentId', 'status', 'checkInTime', 'updatedAt', 'note', 'updatedBy'],
  SyncLogs: ['logId', 'action', 'userEmail', 'timestamp', 'description']
});

function config_() {
  const p = PropertiesService.getScriptProperties();
  const id = p.getProperty('SPREADSHEET_ID');
  const audience = p.getProperty('GOOGLE_CLIENT_ID');
  if (!id || !audience) throw new Error('Máy chủ chưa cấu hình SPREADSHEET_ID / GOOGLE_CLIENT_ID.');
  return {id, audience, domains: (p.getProperty('SCHOOL_DOMAINS') || 'fpt.edu.vn,fe.edu.vn').split(',').map(s => s.trim().toLowerCase())};
}

/** Run manually as spreadsheet owner, never exposed through doPost. */
function setupSheets() {
  const book = SpreadsheetApp.openById(config_().id);
  Object.keys(SCHEMA).forEach(name => {
    const sheet = book.getSheetByName(name) || book.insertSheet(name);
    if (sheet.getLastRow() === 0) {
      sheet.getRange(1, 1, 1, SCHEMA[name].length).setValues([SCHEMA[name]]).setFontWeight('bold');
      sheet.setFrozenRows(1);
    }
    read_(book, name); // Stop on unexpected header rather than overwriting it.
  });
}

function read_(book, name) {
  if (!Object.prototype.hasOwnProperty.call(SCHEMA, name)) throw new Error('Sheet không được hỗ trợ.');
  const sheet = book.getSheetByName(name);
  if (!sheet) throw new Error('Thiếu sheet ' + name + '. Chạy setupSheets.');
  const values = sheet.getDataRange().getDisplayValues();
  const headers = SCHEMA[name];
  if (JSON.stringify(values[0]) !== JSON.stringify(headers)) throw new Error('Sai cấu trúc cột: ' + name);
  const rows = values.slice(1).filter(row => row.some(v => v !== '')).map(row =>
    Object.fromEntries(headers.map((h, i) => [h, row[i] || ''])));
  const ids = rows.map(r => r[headers[0]]);
  if (ids.some(id => !id) || new Set(ids).size !== ids.length) throw new Error('ID trống hoặc trùng trong ' + name);
  return {sheet, rows};
}

function authenticate_(idToken, cfg, book) {
  if (typeof idToken !== 'string' || idToken.length < 20 || idToken.length > 10000) throw new Error('Cần đăng nhập Google.');
  // Google validates the signature. Check audience, issuer, expiry and verified email here.
  const response = UrlFetchApp.fetch('https://oauth2.googleapis.com/tokeninfo?id_token=' + encodeURIComponent(idToken), {muteHttpExceptions: true});
  if (response.getResponseCode() !== 200) throw new Error('Phiên Google không hợp lệ. Đăng nhập lại.');
  const claims = JSON.parse(response.getContentText());
  const email = String(claims.email || '').trim().toLowerCase();
  const parts = email.split('@');
  if (claims.aud !== cfg.audience || !['accounts.google.com', 'https://accounts.google.com'].includes(claims.iss) ||
      Number(claims.exp) <= Date.now() / 1000 || !Number.isFinite(Number(claims.exp)) ||
      ![true, 'true'].includes(claims.email_verified) || parts.length !== 2 || !parts[0] || !cfg.domains.includes(parts[1])) {
    throw new Error('Tài khoản Google không được phép truy cập.');
  }
  const matches = read_(book, 'Lecturers').rows.filter(r => r.email.trim().toLowerCase() === email);
  if (matches.length !== 1) throw new Error('Email chưa có trong Lecturers hoặc hồ sơ bị trùng. Liên hệ trưởng nhóm.');
  return matches[0];
}

function validateSchedule_(input, lecturer) {
  if (!input || typeof input !== 'object' || Array.isArray(input)) throw new Error('Dòng lịch không hợp lệ.');
  const row = {};
  SCHEMA.Schedules.forEach(key => {
    if (typeof input[key] !== 'string' && typeof input[key] !== 'number') throw new Error('Thiếu trường ' + key);
    row[key] = String(input[key]).trim();
    if (!row[key] || row[key].length > 300) throw new Error('Trường trống hoặc quá dài: ' + key);
  });
  if (row.lecturerId !== lecturer.lecturerId) throw new Error('Không được sửa lịch giảng viên khác.');
  ['semester', 'subjectCode', 'classCode'].forEach(k => row[k] = row[k].toUpperCase());
  if (!/^[A-Z]{2,6}\d{3}[A-Z0-9]*$/.test(row.subjectCode)) throw new Error('Mã môn không hợp lệ.');
  if (!/^[1-7]$/.test(row.dayOfWeek) || !/^(?:[1-9]|1[0-2])$/.test(row.slot)) throw new Error('Thứ hoặc slot không hợp lệ.');
  const time = /^(?:[01]\d|2[0-3]):[0-5]\d$/;
  if (!time.test(row.startTime) || !time.test(row.endTime) || row.startTime >= row.endTime) throw new Error('Giờ học không hợp lệ.');
  if (!['MANUAL', 'IMAGE'].includes(row.sourceType)) throw new Error('Nguồn lịch không hợp lệ.');
  return row;
}

/** Pure transformation: validates the complete batch before a single atomic write. */
function mutateSchedules_(existing, action, request, lecturer) {
  const result = existing.map(r => ({...r}));
  const index = new Map(result.map((r, i) => [r.scheduleId, i]));
  if (action === 'deleteRow') {
    const i = index.get(request.id);
    if (i === undefined) throw new Error('Không tìm thấy lịch.');
    if (result[i].lecturerId !== lecturer.lecturerId) throw new Error('Không được xóa lịch giảng viên khác.');
    result.splice(i, 1);
    return result;
  }
  const inputs = action === 'batchUpdate' ? request.rows : [request.row];
  if (!Array.isArray(inputs) || inputs.length < 1 || inputs.length > 100) throw new Error('Batch phải có 1–100 dòng.');
  const rows = inputs.map(r => validateSchedule_(r, lecturer));
  if (new Set(rows.map(r => r.scheduleId)).size !== rows.length) throw new Error('Trùng ID trong batch.');
  rows.forEach(row => {
    const i = index.get(row.scheduleId);
    if (i !== undefined && result[i].lecturerId !== lecturer.lecturerId) throw new Error('Không được sửa lịch giảng viên khác.');
    if (action === 'appendRow' && i !== undefined) throw new Error('ID lịch đã tồn tại.');
    if (action === 'updateRow' && (i === undefined || request.id !== row.scheduleId)) throw new Error('ID cập nhật không khớp.');
    if (i === undefined) { index.set(row.scheduleId, result.length); result.push(row); }
    else result[i] = row;
  });
  const signatures = new Set();
  for (const row of result) {
    const signature = [row.lecturerId, row.semester, row.subjectCode, row.classCode, row.dayOfWeek, row.slot, row.startTime, row.endTime].join('|');
    if (signatures.has(signature)) throw new Error('Lịch dạy bị trùng. Kiểm tra lại các dòng trước khi lưu.');
    signatures.add(signature);
  }
  return result;
}

function writeSchedules_(cfg, sheet, rows, lecturer, action) {
  const columns = SCHEMA.Schedules;
  const count = Math.max(sheet.getLastRow(), rows.length + 1);
  const requests = [];
  if (count > sheet.getMaxRows()) requests.push({appendDimension: {sheetId: sheet.getSheetId(), dimension: 'ROWS', length: count - sheet.getMaxRows()}});
  requests.push({updateCells: {
    range: {sheetId: sheet.getSheetId(), startRowIndex: 1, endRowIndex: count, startColumnIndex: 0, endColumnIndex: columns.length},
    rows: rows.map(row => ({values: columns.map(key => ({userEnteredValue: {stringValue: String(row[key])}}))})),
    fields: 'userEnteredValue'
  }});
  // stringValue avoids formulas even when a room/name starts with '='.
  const logs = SpreadsheetApp.openById(cfg.id).getSheetByName('SyncLogs');
  if (!logs) throw new Error('Thiếu SyncLogs. Chạy setupSheets.');
  requests.push({appendCells: {sheetId: logs.getSheetId(), fields: 'userEnteredValue', rows: [{values:
    [Utilities.getUuid(), action, lecturer.email, new Date().toISOString(), 'Schedules: ' + rows.length + ' rows after mutation']
      .map(value => ({userEnteredValue: {stringValue: value}}))}]}});
  Sheets.Spreadsheets.batchUpdate({requests}, cfg.id);
}

function handleSession_(book, cfg, lecturer, request) {
  const lock = LockService.getScriptLock();
  if (!lock.tryLock(15000)) throw new Error('Máy chủ đang bận. Thử lại sau.');
  try {
    const sessions = read_(book, 'Sessions');
    if (request.action === 'createSession') {
      const classId = String(request.classId || '').trim();
      const slot = String(request.slot || '').trim();
      const date = String(request.date || '').trim();
      const startTime = String(request.startTime || '').trim();
      const endTime = String(request.endTime || '').trim();
      const token = String(request.currentToken || '').trim();
      const secret = String(request.currentSecretCode || '').trim();
      const expiredAt = String(request.tokenExpiredAt || '').trim();

      if (!classId || !date || !slot) throw new Error('Thiếu thông tin tạo phiên điểm danh.');
      const sessionId = Utilities.getUuid();
      const combinedToken = secret ? (token + '#' + secret) : token;

      const newRow = {
        sessionId: sessionId,
        classId: classId,
        date: date,
        slot: slot,
        startTime: startTime,
        endTime: endTime,
        status: 'OPEN',
        currentToken: combinedToken,
        tokenExpiredAt: expiredAt,
        createdBy: lecturer.lecturerId
      };

      const sheet = sessions.sheet;
      const columns = SCHEMA.Sessions;
      sheet.appendRow(columns.map(k => String(newRow[k] || '')));
      return {
        ...newRow,
        currentSecretCode: secret
      };
    }

    if (request.action === 'rotateToken') {
      const sessionId = String(request.sessionId || '').trim();
      const token = String(request.currentToken || '').trim();
      const secret = String(request.currentSecretCode || '').trim();
      const expiredAt = String(request.tokenExpiredAt || '').trim();

      const index = sessions.rows.findIndex(r => r.sessionId === sessionId);
      if (index === -1) throw new Error('Không tìm thấy phiên điểm danh.');
      if (sessions.rows[index].createdBy !== lecturer.lecturerId) throw new Error('Không có quyền sửa phiên điểm danh này.');

      const combinedToken = secret ? (token + '#' + secret) : token;
      const rowIndex = index + 2;
      const tokenCol = SCHEMA.Sessions.indexOf('currentToken') + 1;
      const expCol = SCHEMA.Sessions.indexOf('tokenExpiredAt') + 1;

      sessions.sheet.getRange(rowIndex, tokenCol).setValue(combinedToken);
      sessions.sheet.getRange(rowIndex, expCol).setValue(expiredAt);
      return {saved: true};
    }

    if (request.action === 'closeSession') {
      const sessionId = String(request.sessionId || '').trim();
      const index = sessions.rows.findIndex(r => r.sessionId === sessionId);
      if (index === -1) throw new Error('Không tìm thấy phiên điểm danh.');
      if (sessions.rows[index].createdBy !== lecturer.lecturerId) throw new Error('Không có quyền kết thúc phiên điểm danh này.');

      const rowIndex = index + 2;
      const statusCol = SCHEMA.Sessions.indexOf('status') + 1;
      sessions.sheet.getRange(rowIndex, statusCol).setValue('CLOSED');
      return {closed: true};
    }

    if (request.action === 'getSessionAttendance') {
      const sessionId = String(request.sessionId || '').trim();
      const attendance = read_(book, 'Attendance').rows.filter(r => r.sessionId === sessionId);
      const students = read_(book, 'Students').rows;
      const studentMap = new Map(students.map(s => [s.studentId, s]));

      return attendance.map(a => {
        const student = studentMap.get(a.studentId);
        return {
          ...a,
          studentCode: student ? student.studentCode : '',
          fullName: student ? student.fullName : ''
        };
      });
    }

    if (request.action === 'getSessionsByClass') {
      const targetId = String(request.classId || '').trim().toUpperCase();
      if (!targetId) return [];
      return sessions.rows.filter(r => {
        const rowClassId = String(r.classId || '').trim().toUpperCase();
        if (!rowClassId) return false;
        const matchesLecturer = (r.createdBy === lecturer.lecturerId || !r.createdBy);
        const matchesClass = (rowClassId === targetId || rowClassId.includes(targetId) || targetId.includes(rowClassId));
        return matchesLecturer && matchesClass;
      });
    }

    if (request.action === 'getClassHistory') {
      const classId = String(request.classId || '').trim();
      const classSessions = sessions.rows.filter(r => r.classId === classId);
      const sessionIds = new Set(classSessions.map(s => s.sessionId));
      const attendance = read_(book, 'Attendance').rows.filter(r => sessionIds.has(r.sessionId));
      const students = read_(book, 'Students').rows;
      const studentMap = new Map(students.map(s => [s.studentId, s]));
      return attendance.map(a => {
        const student = studentMap.get(a.studentId);
        return {
          ...a,
          studentCode: student ? student.studentCode : '',
          fullName: student ? student.fullName : ''
        };
      });
    }

    if (request.action === 'getLecturerClasses') {
      const lecturerId = String(request.lecturerId || lecturer.lecturerId).trim();
      return read_(book, 'Classes').rows.filter(r => r.lecturerId === lecturerId);
    }

    if (request.action === 'updateAttendance') {
      const attendanceId = String(request.attendanceId || '').trim();
      const status = String(request.status || '').trim().toUpperCase();
      const note = String(request.note || '').trim();
      const updatedBy = String(request.updatedBy || lecturer.email).trim();
      const nowIso = new Date().toISOString();

      const attendance = read_(book, 'Attendance');
      const index = attendance.rows.findIndex(r => r.attendanceId === attendanceId);
      if (index === -1) throw new Error('Không tìm thấy bản ghi điểm danh.');

      const rowIndex = index + 2;
      const statusCol = SCHEMA.Attendance.indexOf('status') + 1;
      const noteCol = SCHEMA.Attendance.indexOf('note') + 1;
      const timeCol = SCHEMA.Attendance.indexOf('updatedAt') + 1;
      const byCol = SCHEMA.Attendance.indexOf('updatedBy') + 1;

      attendance.sheet.getRange(rowIndex, statusCol).setValue(status);
      attendance.sheet.getRange(rowIndex, noteCol).setValue(note);
      attendance.sheet.getRange(rowIndex, timeCol).setValue(nowIso);
      attendance.sheet.getRange(rowIndex, byCol).setValue(updatedBy);
      return {saved: true};
    }

    if (request.action === 'markAbsent') {
      const sessionId = String(request.sessionId || '').trim();
      const studentCodes = Array.isArray(request.studentCodes) ? request.studentCodes : [];
      const markedBy = String(request.markedBy || lecturer.email).trim();
      const nowIso = new Date().toISOString();

      const attendance = read_(book, 'Attendance');
      const students = read_(book, 'Students').rows;
      const studentMap = new Map(students.map(s => [s.studentCode, s]));

      const newRows = [];
      studentCodes.forEach(code => {
        const student = studentMap.get(code);
        if (student) {
          const already = attendance.rows.some(a => a.sessionId === sessionId && a.studentId === student.studentId);
          if (!already) {
            const newRecord = {
              attendanceId: Utilities.getUuid(),
              sessionId: sessionId,
              studentId: student.studentId,
              status: 'ABSENT',
              checkInTime: '',
              updatedAt: nowIso,
              note: 'Chốt vắng tự động khi kết thúc phiên',
              updatedBy: markedBy
            };
            newRows.push(SCHEMA.Attendance.map(k => String(newRecord[k] || '')));
          }
        }
      });

      if (newRows.length > 0) {
        attendance.sheet.getRange(attendance.sheet.getLastRow() + 1, 1, newRows.length, SCHEMA.Attendance.length).setValues(newRows);
      }
      return {saved: true, count: newRows.length};
    }

    throw new Error('Thao tác session chưa được hỗ trợ.');
  } finally { lock.releaseLock(); }
}

function handleStudentCheckIn_(request) {
  const sessionId = String(request.sessionId || '').trim();
  const token = String(request.token || '').trim();
  const secretCode = String(request.secretCode || '').trim();
  const studentCode = String(request.studentCode || '').trim().toUpperCase();
  const email = String(request.email || '').trim().toLowerCase();

  if (!sessionId || !studentCode || !secretCode) {
    throw new Error('Vui lòng điền đầy đủ mã sinh viên và Secret Code.');
  }

  const cfg = config_();
  const book = SpreadsheetApp.openById(cfg.id);
  const lock = LockService.getScriptLock();
  if (!lock.tryLock(15000)) throw new Error('Hệ thống đang bận ghi nhận điểm danh. Vui lòng bấm thử lại.');

  try {
    const sessions = read_(book, 'Sessions');
    const session = sessions.rows.find(r => r.sessionId === sessionId);
    if (!session) throw new Error('Phiên điểm danh không tồn tại.');
    if (String(session.status).toUpperCase() !== 'OPEN') throw new Error('Phiên điểm danh đã kết thúc.');

    const parts = String(session.currentToken || '').split('#');
    const expectedToken = parts[0] || '';
    const expectedSecret = parts[1] || '';

    if (expectedSecret && secretCode !== expectedSecret) {
      throw new Error('Secret Code không chính xác. Vui lòng nhìn lại trên màn hình máy chiếu.');
    }

    if (token && expectedToken && token !== expectedToken) {
      const expiredTime = new Date(session.tokenExpiredAt).getTime();
      const now = Date.now();
      if (!isNaN(expiredTime) && now > expiredTime + 30000) {
        throw new Error('Mã QR đã hết hạn. Vui lòng quét lại mã mới nhất trên máy chiếu.');
      }
    }

    const students = read_(book, 'Students').rows;
    let student = students.find(s => String(s.studentCode).trim().toUpperCase() === studentCode);
    if (!student && email) {
      student = students.find(s => String(s.schoolEmail).trim().toLowerCase() === email);
    }
    if (!student) {
      throw new Error('Không tìm thấy thông tin sinh viên với mã: ' + studentCode);
    }

    const enrollments = read_(book, 'Enrollments').rows;
    const isEnrolled = enrollments.some(e => e.classId === session.classId && e.studentId === student.studentId);
    if (!isEnrolled) {
      throw new Error('Sinh viên ' + studentCode + ' không thuộc danh sách lớp học này.');
    }

    const attendance = read_(book, 'Attendance');
    const already = attendance.rows.some(a => a.sessionId === sessionId && a.studentId === student.studentId);
    if (already) {
      throw new Error('Sinh viên ' + studentCode + ' đã được ghi nhận điểm danh trước đó.');
    }

    let status = 'PRESENT';
    const now = new Date();
    const nowIso = now.toISOString();

    const attendanceId = Utilities.getUuid();
    const newRecord = {
      attendanceId: attendanceId,
      sessionId: sessionId,
      studentId: student.studentId,
      status: status,
      checkInTime: nowIso,
      updatedAt: nowIso,
      note: 'Self QR Check-in',
      updatedBy: student.studentCode
    };

    attendance.sheet.appendRow(SCHEMA.Attendance.map(k => String(newRecord[k] || '')));

    const logs = book.getSheetByName('SyncLogs');
    if (logs) {
      logs.appendRow([Utilities.getUuid(), 'studentCheckIn', student.schoolEmail || student.studentCode, nowIso, 'Check-in ' + status + ' for class ' + session.classId]);
    }

    return {
      ok: true,
      status: status,
      checkInTime: nowIso,
      studentCode: student.studentCode,
      fullName: student.fullName
    };
  } finally { lock.releaseLock(); }
}

function handle_(request) {
  const cfg = config_();
  const book = SpreadsheetApp.openById(cfg.id);
  const lecturer = authenticate_(request.idToken, cfg, book);
  if (request.action === 'profile') return lecturer;
  if (['getRoster', 'importRoster'].includes(request.action)) {
    return handleRoster_(book, cfg, lecturer, request);
  }
  if (['createSession', 'rotateToken', 'closeSession', 'getSessionAttendance', 'getSessionsByClass', 'getClassHistory', 'updateAttendance', 'markAbsent', 'getLecturerClasses'].includes(request.action)) {
    return handleSession_(book, cfg, lecturer, request);
  }
  if (request.action === 'getRows') {
    if (!['Lecturers', 'Schedules', 'Classes', 'Sessions', 'Attendance'].includes(request.sheet)) throw new Error('Module này chưa được cấp quyền đọc.');
    return read_(book, request.sheet).rows.filter(r => r.lecturerId === lecturer.lecturerId || r.createdBy === lecturer.lecturerId);
  }
  if (request.sheet !== 'Schedules' || !['appendRow', 'updateRow', 'deleteRow', 'batchUpdate'].includes(request.action)) {
    throw new Error('Thao tác chưa được hỗ trợ. Không có generic write cho sheet khác.');
  }
  const lock = LockService.getScriptLock();
  if (!lock.tryLock(15000)) throw new Error('Máy chủ đang bận. Thử lại sau.');
  try {
    const current = read_(book, 'Schedules');
    const rows = mutateSchedules_(current.rows, request.action, request, lecturer);
    writeSchedules_(cfg, current.sheet, rows, lecturer, request.action);
    return {saved: true};
  } finally { lock.releaseLock(); }
}

function rosterTarget_(request, classes, schedules, lecturer) {
  const fields = ['semester', 'subjectCode', 'classCode'];
  const target = Object.fromEntries(fields.map(k => [k, String(request[k] || '').trim().toUpperCase()]));
  if (fields.some(k => !target[k] || target[k].length > 100)) throw new Error('Thiếu học kỳ, môn hoặc mã lớp.');
  const matches = r => r.lecturerId === lecturer.lecturerId && fields.every(k => String(r[k]).trim().toUpperCase() === target[k]);
  const found = classes.filter(matches);
  if (found.length > 1) throw new Error('Trùng khóa lớp. Cần xử lý trước khi nhập sinh viên.');
  const schedule = schedules.find(matches);
  if (!found.length && !schedule) throw new Error('Lớp không thuộc lịch dạy của bạn.');
  return {...target, lecturerId: lecturer.lecturerId, classId: found[0]?.classId || '', subjectName: found[0]?.subjectName || schedule?.subjectName || ''};
}

/** Pure, idempotent roster import. Never removes enrollments or overwrites a shared student. */
function importRoster_(request, state, lecturer, uuid) {
  const target = rosterTarget_(request, state.classes, state.schedules, lecturer);
  if (!Array.isArray(request.students) || !request.students.length || request.students.length > 1000) throw new Error('Nhập từ 1 đến 1.000 sinh viên mỗi lần.');
  const students = state.students.map(s => ({...s}));
  const classes = state.classes.map(c => ({...c}));
  const enrollments = state.enrollments.map(e => ({...e}));
  const codes = new Map();
  for (const s of students) {
    const code = String(s.studentCode).trim().toUpperCase();
    if (codes.has(code)) throw new Error('Mã sinh viên trùng trong hệ thống. Cần xử lý trước khi nhập.');
    codes.set(code, s);
  }
  if (!target.classId) {
    target.classId = uuid();
    classes.push({...target});
  }
  const enrolled = new Set(enrollments.filter(e => e.classId === target.classId).map(e => e.studentId));
  let added = 0, existing = 0;
  const seen = new Map();
  for (const input of request.students) {
    if (!input || typeof input !== 'object') throw new Error('Dòng sinh viên không hợp lệ.');
    const code = String(input.studentCode || '').trim().toUpperCase();
    const fullName = String(input.fullName || '').trim();
    const schoolEmail = String(input.schoolEmail || '').trim().toLowerCase();
    if (String(input.classCode || '').trim().toUpperCase() !== target.classCode) throw new Error('Mã lớp trong file không khớp lớp đích.');
    if (!/^[A-Z0-9][A-Z0-9._-]{1,39}$/.test(code) || !fullName || fullName.length > 200 || schoolEmail.length > 254 ||
        (schoolEmail && !/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(schoolEmail))) throw new Error('Mã sinh viên, họ tên hoặc email không hợp lệ.');
    const signature = JSON.stringify([fullName, schoolEmail]);
    if (seen.has(code) && seen.get(code) !== signature) throw new Error('Một mã sinh viên có nhiều thông tin khác nhau trong file.');
    seen.set(code, signature);
    let student = codes.get(code);
    if (student && String(student.fullName).trim().toLowerCase().replace(/\s+/g, ' ') !== fullName.toLowerCase().replace(/\s+/g, ' ')) {
      throw new Error('Họ tên không khớp mã sinh viên ' + code + ' đã có. Kiểm tra lại file.');
    }
    if (!student) {
      student = {studentId: uuid(), studentCode: code, fullName, schoolEmail};
      students.push(student); codes.set(code, student);
    }
    if (enrolled.has(student.studentId)) { existing++; continue; }
    enrollments.push({enrollmentId: uuid(), classId: target.classId, studentId: student.studentId});
    enrolled.add(student.studentId); added++;
  }
  return {classes, students, enrollments, added, existing, classId: target.classId};
}

function handleRoster_(book, cfg, lecturer, request) {
  const lock = LockService.getScriptLock();
  if (!lock.tryLock(15000)) throw new Error('Máy chủ đang bận. Thử lại sau.');
  try {
    const classes = read_(book, 'Classes'), students = read_(book, 'Students'), enrollments = read_(book, 'Enrollments');
    const schedules = read_(book, 'Schedules').rows;
    const target = rosterTarget_(request, classes.rows, schedules, lecturer);
    if (request.action === 'getRoster') {
      const ids = new Set(enrollments.rows.filter(e => e.classId === target.classId).map(e => e.studentId));
      return students.rows.filter(s => ids.has(s.studentId)).map(s => ({...s, classCode: target.classCode}));
    }
    const next = importRoster_(request, {classes: classes.rows, students: students.rows, enrollments: enrollments.rows, schedules}, lecturer, () => Utilities.getUuid());
    const requests = [];
    for (const [name, current, rows] of [['Classes', classes, next.classes], ['Students', students, next.students], ['Enrollments', enrollments, next.enrollments]]) {
      const appended = rows.slice(current.rows.length);
      if (!appended.length) continue;
      // Preserve existing rows, formulas and other lecturers' data.
      requests.push({appendCells: {sheetId: current.sheet.getSheetId(), fields: 'userEnteredValue', rows: appended.map(row => ({values:
        SCHEMA[name].map(k => ({userEnteredValue: {stringValue: String(row[k] || '')}}))}))}});
    }
    const logs = book.getSheetByName('SyncLogs');
    if (!logs) throw new Error('Thiếu SyncLogs. Chạy setupSheets.');
    requests.push({appendCells: {sheetId: logs.getSheetId(), fields: 'userEnteredValue', rows: [{values:
      [Utilities.getUuid(), 'importRoster', lecturer.email, new Date().toISOString(), 'Added enrollments: ' + next.added]
        .map(v => ({userEnteredValue: {stringValue: v}}))}]}});
    Sheets.Spreadsheets.batchUpdate({requests}, cfg.id);
    return {added: next.added, existing: next.existing, classId: next.classId};
  } finally { lock.releaseLock(); }
}

function doPost(e) {
  let result;
  try {
    const text = e && e.postData && e.postData.contents;
    if (!text || text.length > 200000) throw new Error('Yêu cầu trống hoặc quá lớn.');
    const request = JSON.parse(text);
    if (!request || typeof request !== 'object' || Array.isArray(request)) throw new Error('Yêu cầu không hợp lệ.');
    if (request.action === 'studentCheckIn') {
      result = {ok: true, data: handleStudentCheckIn_(request)};
    } else {
      result = {ok: true, data: handle_(request)};
    }
  } catch (error) {
    // Do not log tokens, requests or upstream exception details containing URLs.
    const message = String(error.message || 'Yêu cầu thất bại.');
    result = {ok: false, error: /https?:|tokeninfo|id_token|Exception|Service /i.test(message) ? 'Lỗi máy chủ hoặc kết nối Google. Kiểm tra cấu hình và thử lại.' : message};
  }
  return ContentService.createTextOutput(JSON.stringify(result)).setMimeType(ContentService.MimeType.JSON);
}
