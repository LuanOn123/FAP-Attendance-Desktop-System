(() => {
  // Supports reinjection after an extension reload without duplicate listeners.
  if (globalThis.__fapScannerInstalled) return;
  globalThis.__fapScannerInstalled = true;
  const normalize = value => String(value || "").normalize("NFD")
    .replace(/[\u0300-\u036f]/g, "").replace(/đ/g, "d").toLowerCase().replace(/\s+/g, ' ').trim();
  const clean = node => (node?.textContent || "").replace(/\s+/g, " ").trim();
  const aliases = {
    studentCode: ["student id", "student code", "roll number", "roll no", "rollnumber", "mssv", "ma sinh vien", "code", "member code", "member code / roll number"],
    fullName: ["student name", "full name", "ho va ten", "name", "ten"],
    email: ["email", "mail"], image: ["image", "photo", "avatar", "anh"]
  };

  // Scanner and writer share the same DOM identity rules; never use row order.
  function studentRows(doc) {
    const cards = [...doc.querySelectorAll('.student-card')];
    if (cards.length) return cards.map(row => ({row,
      code: clean(row.querySelector('.student-code')),
      name: clean(row.querySelector('h3')),
      email: clean(row.querySelector('.student-meta span:last-child'))}));
    const result = [];
    let tableFound = false;
    for (const table of doc.querySelectorAll('table')) {
      const rows = [...table.rows];
      let columns = {}, headerIndex = -1;
      for (let i = 0; i < Math.min(rows.length, 8); i++) {
        const map = {};
        [...rows[i].cells].forEach((cell, index) => {
          for (const [key, names] of Object.entries(aliases)) {
            if (names.includes(normalize(clean(cell)))) map[key] = index;
          }
        });
        if (map.fullName !== undefined && (map.studentCode !== undefined || table.querySelector('tr[data-student-code]'))) {
          columns = map; headerIndex = i; break;
        }
      }
      const tagged = rows.filter(row => row.hasAttribute('data-student-code'));
      if (headerIndex < 0 && !tagged.length && table.id !== 'ctl00_mainContent_gvStudents') continue;
      tableFound = true;
      const candidates = headerIndex >= 0 ? rows.slice(headerIndex + 1) : tagged;
      for (const row of candidates) {
        if (!row.querySelector('td')) continue;
        result.push({row,
          code: row.dataset.studentCode || clean(row.cells[columns.studentCode]),
          name: row.dataset.fullName || clean(row.cells[columns.fullName]),
          email: row.dataset.email || clean(row.cells[columns.email])});
      }
    }
    if (!tableFound) throw Object.assign(new Error('Không tìm thấy bảng điểm danh sinh viên trên trang hiện tại.'), {code: 'STUDENT_TABLE_NOT_FOUND'});
    return result;
  }

  function label(doc, names) {
    // Do not read large parent divs: they contain multiple unrelated labels.
    for (const el of doc.querySelectorAll("td, span, b, strong, label, p")) {
      const raw = clean(el);
      if (raw.length > 500) continue;
      for (const part of raw.split(/[•\n|]/)) {
        const pair = part.match(/^\s*([^:]+):\s*(.*?)\s*$/);
        if (pair && names.includes(normalize(pair[1]))) {
          return pair[2] || clean(el.nextElementSibling);
        }
        if (names.includes(normalize(part))) return clean(el.nextElementSibling);
      }
    }
    return "";
  }

  function isoDate(raw) {
    const iso = raw.match(/\b(\d{4})-(\d{2})-(\d{2})\b/);
    if (iso) return iso[0];
    const dmy = raw.match(/\b(\d{1,2})[/-](\d{1,2})[/-](\d{4})\b/);
    return dmy ? dmy[3] + "-" + dmy[2].padStart(2, "0") + "-" + dmy[1].padStart(2, "0") : "";
  }

  function scan(doc) {
    let courseLabel = label(doc, ["course", "subject", "mon", "mon hoc"]);
    const heading = clean(doc.querySelector(".course-info h1"));
    if (heading) courseLabel = heading;
    const courseCode = courseLabel.match(/\b[A-Z]{2,6}\d{3}[A-Z0-9]*\b/i)?.[0]?.toUpperCase() || "";
    const classLabel = label(doc, ["class", "group", "lop", "nhom"]);
    const classCode = classLabel.match(/\b[A-Z]{2,6}\d+[A-Z0-9._-]*\b/i)?.[0]?.toUpperCase() || classLabel;
    const date = isoDate(doc.querySelector('input[type="date"]')?.value || label(doc, ["date", "ngay"]));
    const slot = Number(label(doc, ["slot", "ca", "ca hoc"]).match(/\d+/)?.[0]) || null;
    const room = label(doc, ["room", "phong", "phong hoc"]);
    const clock = value => {
      const match = String(value || '').match(/\b(\d{1,2}):(\d{2})\b/);
      return match && +match[1] < 24 && +match[2] < 60 ? match[1].padStart(2, '0') + ':' + match[2] : '';
    };
    const range = (label(doc, ['time', 'thoi gian', 'slot', 'ca hoc']) || '').match(/(\d{1,2}:\d{2})\s*[-–—]\s*(\d{1,2}:\d{2})/);
    const startTime = clock(label(doc, ['start time', 'bat dau', 'gio bat dau'])) || clock(range?.[1]);
    const endTime = clock(label(doc, ['end time', 'ket thuc', 'gio ket thuc'])) || clock(range?.[2]);
    const students = new Map();
    function add(code, name, email) {
      code = code.trim().toUpperCase(); name = name.trim(); email = (email || "").trim().toLowerCase();
      if (!code || !name) return;
      const old = students.get(code);
      if (old && (old.fullName !== name || old.email !== email)) throw new Error("MSSV trùng với thông tin khác: " + code);
      students.set(code, { studentCode: code, fullName: name, email });
    }
    const rows = studentRows(doc);
    for (const row of rows) {
      if (/^[A-Z]{2,6}\d{4,10}$/i.test(row.code.trim())) add(row.code, row.name || row.code, row.email);
    }
    if (!students.size) throw Object.assign(new Error('Đã tìm thấy bảng nhưng không đọc được MSSV hợp lệ.'), {code: 'STUDENT_CODES_NOT_FOUND'});
    console.debug('[FAP Scanner]', {tableFound: true, rows: rows.length, students: students.size});
    return {
      source: "FAP_WEB_DOM", course: { courseCode, courseName: courseLabel.replace(/\s*\([^)]*\)\s*$/, "").trim() || courseCode },
      class: { classCode }, session: { date, slot, room, startTime, endTime }, students: [...students.values()]
    };
  }
  // Export only in the Node test harness.
  globalThis.FapAttendanceScanner = { scan, isoDate, studentRows };
  if (typeof module !== "undefined") module.exports = { scan, isoDate, studentRows };
  if (typeof chrome !== "undefined" && chrome.runtime) {
    chrome.runtime.onMessage.addListener((request, sender, sendResponse) => {
      if (request.type !== "SCAN_ATTENDANCE") return;
      try { sendResponse({ success: true, data: scan(document) }); }
      catch (e) { sendResponse({ success: false, code: e.code || 'SCAN_FAILED', message: e.message }); }
    });
  }
})();
// flutter run -d windows --dart-define-from-file=config/local.json
