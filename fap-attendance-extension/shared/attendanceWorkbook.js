(function (root) {
  const normalize = value => String(value ?? '').normalize('NFD')
    .replace(/[\u0300-\u036f]/g, '').replace(/đ/g, 'd').toLowerCase().replace(/\s+/g, ' ').trim();
  const header = value => {
    const text = normalize(value);
    return ({'student code':'mssv', 'student id':'mssv', 'roll number':'mssv',
      'member code':'mssv', 'member code / roll number':'mssv',
      'status':'trang thai', 'attendance status':'trang thai',
      'full name':'ho va ten', 'student name':'ho va ten',
      'class':'lop hoc', 'group':'lop hoc', 'subject':'ma mon', 'course code':'ma mon',
      'fap':'ky hieu fap'})[text] || text;
  };
  function parseRows(rows, filename) {
    const match = filename.match(/^Diemdanh_([A-Z0-9]+)_([A-Z0-9.-]+)_(\d{4}-\d{2}-\d{2})_Slot(\d+)\.xlsx$/i);
    if (!match) throw new Error('Giữ tên file xuất từ app: Diemdanh_MON_LOP_YYYY-MM-DD_Slot1.xlsx để đối chiếu buổi học.');
    const metadata = {courseCode: match[1].toUpperCase(), classCode: match[2].toUpperCase(), date: match[3], slot: Number(match[4])};
    if (Number.isNaN(Date.parse(metadata.date)) || new Date(metadata.date).toISOString().slice(0,10) !== metadata.date || metadata.slot < 1 || metadata.slot > 12) throw new Error('Ngày hoặc slot trong tên file không hợp lệ.');
    const required = ['mssv', 'lop hoc', 'ma mon'];
    const headerIndex = rows.findIndex(row => required.every(key => row.map(header).includes(key)) && ['trang thai', 'ky hieu fap'].some(key => row.map(header).includes(key)));
    if (headerIndex < 0) throw new Error('Thiếu cột MSSV, Trạng thái, Lớp học hoặc Mã môn. Hãy dùng file xuất từ app.');
    const headers = rows[headerIndex].map(header);
    if (new Set(headers.filter(Boolean)).size !== headers.filter(Boolean).length) throw new Error('File có cột tiêu đề bị trùng.');
    const entries = [], seen = new Set();
    const value = (row, key) => String(row[headers.indexOf(key)] ?? '').trim();
    for (const [index, row] of rows.slice(headerIndex + 1).entries()) {
      if (!row.some(cell => String(cell ?? '').trim())) continue;
      const studentCode = value(row, 'mssv').toUpperCase();
      if (!/^[A-Z]{2,6}\d{4,10}$/.test(studentCode)) throw new Error(`MSSV không hợp lệ ở dòng ${headerIndex + index + 2}.`);
      if (seen.has(studentCode)) throw new Error('MSSV trùng trong Excel: ' + studentCode);
      seen.add(studentCode);
      const rawStatus = (value(row, 'trang thai') || value(row, 'ky hieu fap')).toUpperCase();
      const originalStatus = ({P:'PRESENT', A:'ABSENT', L:'LATE'})[rawStatus] || rawStatus;
      if (!['PRESENT', 'ABSENT', 'LATE'].includes(originalStatus)) throw new Error('Trạng thái không hỗ trợ: ' + studentCode + ' (' + originalStatus + ').');
      if (value(row, 'lop hoc').toUpperCase() !== metadata.classCode || value(row, 'ma mon').toUpperCase() !== metadata.courseCode) throw new Error('Môn/lớp trong Excel không khớp tên file.');
      const status = originalStatus === 'ABSENT' ? 'absent' : 'present';
      const symbol = value(row, 'ky hieu fap').toUpperCase();
      if (symbol && symbol !== ({ABSENT: 'A', PRESENT: 'P', LATE: 'L'}[originalStatus])) throw new Error('Ký hiệu FAP mâu thuẫn trạng thái: ' + studentCode);
      entries.push({studentCode, fullName: value(row, 'ho va ten'), status, originalStatus});
    }
    if (!entries.length || entries.length > 1000) throw new Error('File phải chứa từ 1 đến 1000 sinh viên.');
    return {metadata, entries};
  }
  function read(buffer, filename, XLSX) {
    if (buffer.byteLength > 10 * 1024 * 1024) throw new Error('File quá lớn (tối đa 10 MB).');
    const workbook = XLSX.read(buffer, {type: 'array', cellFormula: true});
    const candidates = [];
    for (const name of workbook.SheetNames) {
      const sheet = workbook.Sheets[name];
      if (Object.keys(sheet).some(key => !key.startsWith('!') && sheet[key].f)) throw new Error('File chứa công thức; dùng bản xuất trực tiếp từ app.');
      const rows = XLSX.utils.sheet_to_json(sheet, {header: 1, defval: '', raw: false});
      if (rows.some(row => row.map(header).includes('mssv'))) candidates.push({rows, name});
    }
    if (candidates.length !== 1) throw new Error('Cần đúng một sheet kết quả điểm danh có cột MSSV.');
    const result = parseRows(candidates[0].rows, filename);
    console.debug('[Excel Parser]', {loaded: true, sheet: candidates[0].name, rows: result.entries.length});
    return result;
  }
  root.AttendanceWorkbook = {read, parseRows};
  if (typeof module !== 'undefined') module.exports = root.AttendanceWorkbook;
})(globalThis);
