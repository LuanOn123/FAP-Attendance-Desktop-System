(() => {
  // Supports reinjection after an extension reload without duplicate listeners.
  if (globalThis.__fapScannerInstalled) return;
  globalThis.__fapScannerInstalled = true;
  const normalize = value => String(value || "").normalize("NFD")
    .replace(/[\u0300-\u036f]/g, "").replace(/đ/g, "d").toLowerCase().trim();
  const clean = node => (node?.textContent || "").replace(/\s+/g, " ").trim();
  const aliases = {
    studentCode: ["student id", "student code", "roll number", "roll no", "rollnumber", "mssv", "ma sinh vien", "code"],
    fullName: ["student name", "full name", "ho va ten", "name", "ten"],
    email: ["email", "mail"], image: ["image", "photo", "avatar", "anh"]
  };

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
    const startTime = label(doc, ["start time", "bat dau", "gio bat dau"]).match(/\b\d{2}:\d{2}\b/)?.[0] || "";
    const endTime = label(doc, ["end time", "ket thuc", "gio ket thuc"]).match(/\b\d{2}:\d{2}\b/)?.[0] || "";
    const students = new Map();
    function add(code, name, email) {
      code = code.trim().toUpperCase(); name = name.trim(); email = (email || "").trim().toLowerCase();
      if (!code || !name) return;
      const old = students.get(code);
      if (old && (old.fullName !== name || old.email !== email)) throw new Error("MSSV trùng với thông tin khác: " + code);
      students.set(code, {studentCode: code, fullName: name, email});
    }
    const cards = doc.querySelectorAll(".student-card");
    for (const card of cards) add(clean(card.querySelector(".student-code")),
      clean(card.querySelector("h3")), clean(card.querySelector(".student-meta span:last-child")));
    if (!students.size) {
      for (const table of doc.querySelectorAll("table")) {
        const rows = [...table.querySelectorAll("tr")];
        let headerIndex = -1, columns = {};
        for (let i = 0; i < Math.min(rows.length, 8); i++) {
          const cells = [...rows[i].querySelectorAll("th, td")];
          const map = {};
          cells.forEach((cell, index) => {
            const text = normalize(clean(cell));
            for (const [key, names] of Object.entries(aliases)) {
              if (names.includes(text)) map[key] = index;
            }
          });
          if (map.studentCode !== undefined && map.fullName !== undefined) {
            headerIndex = i; columns = map; break;
          }
        }
        if (headerIndex < 0) continue;
        for (const row of rows.slice(headerIndex + 1)) {
          const cells = row.querySelectorAll("td");
          add(clean(cells[columns.studentCode]), clean(cells[columns.fullName]), clean(cells[columns.email]));
        }
        if (students.size) break;
      }
    }
    if (!students.size) throw new Error("Không tìm thấy danh sách sinh viên. Mở trang điểm danh rồi quét lại.");
    return {
      source: "FAP_WEB_DOM", course: {courseCode, courseName: courseLabel.replace(/\s*\([^)]*\)\s*$/, "").trim() || courseCode},
      class: {classCode}, session: {date, slot, room, startTime, endTime}, students: [...students.values()]
    };
  }
  // Export only in the Node test harness.
  globalThis.FapAttendanceScanner = {scan, isoDate};
  if (typeof module !== "undefined") module.exports = {scan, isoDate};
  if (typeof chrome !== "undefined" && chrome.runtime) {
    chrome.runtime.onMessage.addListener((request, sender, sendResponse) => {
      if (request.type !== "SCAN_ATTENDANCE") return;
      try { sendResponse({success: true, data: scan(document)}); }
      catch (e) { sendResponse({success: false, message: e.message}); }
    });
  }
})();
