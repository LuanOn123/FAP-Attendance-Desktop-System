(function (root) {
  if (root.FapAttendanceWriter) return;
  const norm = value => String(value || '').normalize('NFD').replace(/[\u0300-\u036f]/g, '').replace(/đ/g, 'd').toLowerCase().trim();
  function rowsByCode(doc) {
    const result = new Map();
    const add = (code, row) => {
      code = code.trim().toUpperCase();
      if (!code) return;
      if (result.has(code)) throw new Error('MSSV trùng trên trang: ' + code);
      result.set(code, row);
    };
    for (const item of root.FapAttendanceScanner.studentRows(doc)) {
      if (/^[A-Z]{2,6}\d{4,10}$/i.test(item.code.trim())) add(item.code, item.row);
    }
    return result;
  }
  function control(row, status) {
    const words = status === 'present' ? ['present', 'co mat', 'attended'] : ['absent', 'vang', 'vang mat'];
    const radios = [...row.querySelectorAll('input[type="radio"]')];
    const matches = radios.filter(input => {
      const labels = [...(input.labels || [])].map(label => norm(label.textContent));
      if (labels.some(text => words.includes(text))) return true;
      // Explicit text labels take precedence over ASP.NET numeric values.
      if (labels.some(text => ['present','co mat','attended','absent','vang','vang mat'].includes(text))) return false;
      return [...words, status === 'present' ? '1' : '0'].includes(norm(input.value));
    });
    if (matches.length > 1) throw new Error('Có nhiều lựa chọn trạng thái trên cùng một dòng.');
    const target = matches[0] || row.querySelector(status === 'present' ? 'button.btn-present' : 'button.btn-absent');
    if (!target || target.disabled || target.closest('fieldset[disabled]') || target.hidden || target.closest('[hidden]')) throw new Error('Không có ô trạng thái có thể chỉnh sửa.');
    if (target.tagName === 'BUTTON' && target.closest('form') && target.type !== 'button') throw new Error('Nút trạng thái có thể gửi biểu mẫu; không tự bấm.');
    return target;
  }
  function plan(doc, payload, scan) {
    if (!payload?.metadata || !Array.isArray(payload.entries) || !payload.entries.length || payload.entries.length > 1000) throw new Error('Dữ liệu nhập không hợp lệ.');
    const data = scan(doc), m = payload.metadata;
    const selectedReport = payload.source === 'desktop' && payload.matchMode === 'selectedReport';
    for (const [label, actual, expected] of [
      ...(payload.source === 'desktop' ? [] : [['môn', data.course.courseCode, m.courseCode]]), ['lớp', data.class.classCode, m.classCode],
      ...(selectedReport ? [] : [['ngày', data.session.date, m.date], ['slot', data.session.slot, m.slot]]),
    ]) if ((payload.source === 'desktop' && !actual) || (actual && String(actual).toUpperCase() !== String(expected).toUpperCase())) throw new Error(`Sai hoặc thiếu ${label} trên trang. Excel: ${expected}; trang: ${actual || 'chưa xác định'}.`);
    if (payload.source === 'desktop' && !selectedReport) {
      for (const key of ['startTime', 'endTime']) {
        const time = value => { const match = String(value || '').match(/^(\d{1,2}):(\d{2})$/); return match && +match[1] < 24 && +match[2] < 60 ? +match[1] * 60 + +match[2] : null; };
        if (time(m[key]) === null || time(data.session[key]) !== time(m[key])) throw new Error('Giờ học trên trang không khớp báo cáo desktop.');
      }
    }
    const rows = rowsByCode(doc), seen = new Set();
    const names = new Map(data.students.map(s => [s.studentCode.trim().toUpperCase(), s.fullName]));
    const missing = payload.entries.filter(entry => !rows.has(entry.studentCode)).map(entry => entry.studentCode);
    if (missing.length) throw new Error(`Khớp ${payload.entries.length - missing.length}/${payload.entries.length} sinh viên. Không tìm thấy MSSV trên trang: ${missing.join(', ')}. Kiểm tra phân trang/danh sách lớp.`);
    if (payload.source === 'desktop' && rows.size !== payload.entries.length) throw new Error('Danh sách sinh viên trên trang và app không trùng nhau.');
    for (const entry of payload.entries) {
      if (!/^[A-Z]{2,6}\d{4,10}$/.test(entry.studentCode) || !['present', 'absent'].includes(entry.status) || seen.has(entry.studentCode)) throw new Error('MSSV/trạng thái không hợp lệ hoặc bị trùng.');
      seen.add(entry.studentCode);
      if (selectedReport) {
        const normalizeName = value => String(value || '').normalize('NFC').toLocaleLowerCase('vi').replace(/\s+/g, ' ').trim();
        if (!normalizeName(entry.fullName) || normalizeName(entry.fullName) !== normalizeName(names.get(entry.studentCode))) {
          throw new Error('Họ tên không khớp báo cáo Desktop tại MSSV ' + entry.studentCode + '. Kiểm tra lại danh sách trước khi đồng bộ.');
        }
      }
      if (!rows.has(entry.studentCode)) throw new Error('Không tìm thấy MSSV trên trang: ' + entry.studentCode + '. Kiểm tra phân trang/danh sách lớp.');
      try { control(rows.get(entry.studentCode), entry.status); }
      catch (e) { throw new Error(entry.studentCode + ': ' + e.message); }
    }
    console.debug('[Attendance Mapper]', {page: rows.size, excel: payload.entries.length, matched: seen.size, missing: 0});
    return {matched: payload.entries.length, pageStudents: rows.size, unchanged: rows.size - seen.size,
      present: payload.entries.filter(e => e.status === 'present').length,
      absent: payload.entries.filter(e => e.status === 'absent').length};
  }
  function apply(doc, payload, scan) {
    const result = plan(doc, payload, scan);
    let applied = 0;
    try {
      for (const entry of payload.entries) {
        const row = rowsByCode(doc).get(entry.studentCode);
        if (!row) throw new Error('Trang đã thay đổi trong khi điền.');
        const target = control(row, entry.status);
        if (target.tagName === 'INPUT') {
          if (!target.checked) target.click();
          if (!target.checked) throw new Error('Trang không nhận trạng thái mới.');
        } else {
          target.click();
          const updated = control(rowsByCode(doc).get(entry.studentCode), entry.status);
          if (!updated.classList.contains('active') && updated.getAttribute('aria-pressed') !== 'true') throw new Error('Không xác nhận được trạng thái nút.');
        }
        applied++;
      }
      for (const entry of payload.entries) {
        const target = control(rowsByCode(doc).get(entry.studentCode), entry.status);
        if (target.tagName === 'INPUT' && !target.checked) throw new Error('Các dòng dùng chung nhóm radio hoặc trang đã đổi trạng thái: ' + entry.studentCode);
      }
    } catch (e) { throw new Error(`Đã điền ${applied}/${payload.entries.length} dòng rồi dừng: ${e.message} Kiểm tra trang trước khi thử lại.`); }
    return {...result, applied};
  }
  root.FapAttendanceWriter = {plan, apply, rowsByCode};
  if (typeof module !== 'undefined') module.exports = root.FapAttendanceWriter;
  if (typeof chrome !== 'undefined' && chrome.runtime) chrome.runtime.onMessage.addListener((request, sender, respond) => {
    if (!['PREVIEW_ATTENDANCE', 'APPLY_ATTENDANCE'].includes(request.type)) return;
    if (sender.id !== chrome.runtime.id) return;
    try {
      const fn = request.type === 'APPLY_ATTENDANCE' ? apply : plan;
      respond({success: true, data: fn(document, request.data, root.FapAttendanceScanner.scan)});
    } catch (e) { respond({success: false, message: e.message}); }
  });
})(globalThis);
