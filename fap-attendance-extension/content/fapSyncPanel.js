(() => {
  'use strict';
  if (globalThis.FapSyncPanel || !globalThis.FapAttendanceScanner || !globalThis.FapAttendanceWriter) return;
  const scan = () => globalThis.FapAttendanceScanner.scan(document);
  let initial;
  try { initial = scan(); } catch { return; }
  if (!initial.students?.length) return;
  globalThis.FapSyncPanel = true;
  const host = document.createElement('aside'); host.id = 'fap-desktop-sync';
  const shadow = host.attachShadow({mode: 'closed'});
  const style = document.createElement('style');
  style.textContent = ':host{display:block;margin:18px 0;font:14px Segoe UI,Arial,sans-serif;color:#382719}.panel{border:1px solid #f1c8a8;border-left:4px solid #ed7014;border-radius:12px;background:#fff8f1;padding:18px 22px;display:flex;align-items:center;gap:24px;flex-wrap:wrap}strong{font-size:16px}p{margin:6px 0;line-height:1.5}small{color:#766557}button{border:0;background:#dc600a;color:white;padding:12px 18px;border-radius:8px;font:600 14px Segoe UI;cursor:pointer}button:disabled{opacity:.45;cursor:default}.copy{flex:1;min-width:250px}';
  const panel = document.createElement('div'); panel.className = 'panel';
  const copy = document.createElement('div'); copy.className = 'copy';
  const title = document.createElement('strong'); title.textContent = 'FAP Attendance · Đồng bộ từ desktop';
  const status = document.createElement('p'); status.setAttribute('role', 'status');
  const note = document.createElement('small'); note.textContent = 'Đối chiếu đúng buổi học. Sau khi điền, kiểm tra danh sách rồi bấm Save trên FAP.';
  const button = document.createElement('button'); button.type = 'button'; button.textContent = 'Đồng bộ điểm danh'; button.disabled = true;
  copy.append(title, status, note); panel.append(copy, button); shadow.append(style, panel);
  const first = globalThis.FapAttendanceWriter.rowsByCode(document).values().next().value;
  (first?.closest('table') || first?.parentElement || document.body).before(host);
  let snapshot = '', busy = false;
  function metadata() {
    const data = scan();
    return {courseCode: data.course.courseCode, classCode: data.class.classCode, date: data.session.date, slot: data.session.slot, startTime: data.session.startTime, endTime: data.session.endTime, ...(data.semester ? {semester: data.semester} : {})};
  }
  async function fetchReport() {
    const response = await chrome.runtime.sendMessage({type: 'GET_REPORT', data: metadata()});
    if (!response?.success || !response.data) throw new Error(response?.message || 'Mở desktop và đăng nhập giảng viên để nhận báo cáo.');
    const payload = response.data;
    const preview = globalThis.FapAttendanceWriter.plan(document, payload, globalThis.FapAttendanceScanner.scan);
    return {payload, preview, signature: JSON.stringify(payload)};
  }
  async function refresh(apply = false) {
    if (busy) return;
    busy = true; button.disabled = true;
    status.textContent = 'Đang đối chiếu báo cáo với buổi học trên trang…';
    try {
      const result = await fetchReport();
      const changed = snapshot !== result.signature;
      snapshot = result.signature;
      const m = result.payload.metadata;
      const summary = m.courseCode + ' · ' + m.classCode + ' · ' + m.date + ' · Slot ' + m.slot + ' · ' + m.startTime + '–' + m.endTime + ': ' + result.preview.present + ' có mặt, ' + result.preview.absent + ' vắng.';
      if (apply && !changed) {
        const done = globalThis.FapAttendanceWriter.apply(document, result.payload, globalThis.FapAttendanceScanner.scan);
        status.textContent = 'Đã điền ' + done.applied + ' sinh viên. Kiểm tra và bấm Save trên FAP để lưu. ' + summary;
      } else {
        status.textContent = (apply && changed ? 'Báo cáo vừa thay đổi. Kiểm tra số lượng và bấm Đồng bộ lần nữa. ' : 'Sẵn sàng. ') + summary;
      }
      button.disabled = false;
    } catch (error) { snapshot = ''; status.textContent = error.message; }
    finally { busy = false; }
  }
  button.addEventListener('click', () => refresh(true));
  refresh();
  const timer = setInterval(() => { if (!host.isConnected) clearInterval(timer); else if (!document.hidden) refresh(); }, 30000);
})();
