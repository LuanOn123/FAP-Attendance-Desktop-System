let scannedTabId = null;
let currentSessionData = null;
let online = false;
let busy = false;
const $ = id => document.getElementById(id);
const defaults = {
  1: ["07:30", "09:50"], 2: ["10:00", "12:20"], 3: ["12:50", "15:10"],
  4: ["15:20", "17:40"], 5: ["18:00", "20:20"], 6: ["20:30", "22:50"]
};
document.addEventListener("DOMContentLoaded", () => {
  $("btn-send").addEventListener("click", sendToDesktop);
  $("btn-preview").addEventListener("click", () => $("preview-container").classList.toggle("hidden"));
  $("btn-rescan").addEventListener("click", refresh);
  $("val-slot").addEventListener("change", () => {
    const times = defaults[$("val-slot").value];
    if (times) { $("val-start").value = times[0]; $("val-end").value = times[1]; }
  });
  refresh();
});
function status(text, type) {
  $("status-container").className = "status-container " + type;
  $("status-text").textContent = text;
}
function buttonState() { $("btn-send").disabled = !online || !currentSessionData || busy; }
async function refresh() {
  busy = true; currentSessionData = null; scannedTabId = null; buttonState();
  if (typeof resetImportReview === "function") resetImportReview();
  $("btn-send").textContent = "Gửi sang app Điểm danh";
  $("session-info").classList.add("hidden");
  status("Đang quét trang điểm danh…", "scanning");
  await Promise.all([checkDesktop(), scanPage()]);
  busy = false; buttonState();
}
async function checkDesktop() {
  online = false;
  let message = "";
  try {
    const result = await chrome.runtime.sendMessage({type: "CHECK_HEALTH"});
    online = result?.status === "ok"; message = result?.message || "";
  } catch (e) { message = e.message; }
  $("desktop-status").className = "desktop-status " + (online ? "online" : "offline");
  $("desktop-text").textContent = online ? "Desktop: đã kết nối" : "Mở app và đăng nhập, sau đó bấm Quét lại.";
  $("desktop-status").title = message;
}
async function scanPage() {
  try {
    const [tab] = await chrome.tabs.query({active: true, currentWindow: true});
    if (!tab?.id) throw new Error("Không tìm thấy tab hiện tại.");
    const url = new URL(tab.url || "about:blank");
    const recognized = url.protocol === "file:" ||
      (["https:", "http:"].includes(url.protocol) && ["fap.fpt.edu.vn", "localhost", "127.0.0.1"].includes(url.hostname));
    if (!recognized) throw new Error("Mở trang điểm danh FAP hoặc attendance.html rồi quét lại.");
    if (url.protocol === "file:" && !await chrome.extension.isAllowedFileSchemeAccess()) {
      throw new Error('Bật “Allow access to file URLs” trong phần Details của extension rồi tải lại trang HTML.');
    }
    let result;
    try { result = await chrome.tabs.sendMessage(tab.id, {type: "SCAN_ATTENDANCE"}); }
    catch (_) {
      await chrome.scripting.executeScript({target: {tabId: tab.id}, files: ["content/fapAttendanceScanner.js", "content/fapAttendanceWriter.js"]});
      result = await chrome.tabs.sendMessage(tab.id, {type: "SCAN_ATTENDANCE"});
    }
    if (!result?.success) throw new Error(result?.message || "Không đọc được danh sách.");
    currentSessionData = result.data;
    scannedTabId = tab.id;
    $("val-course").value = result.data.course.courseCode;
    $("val-class").value = result.data.class.classCode;
    $("val-date").value = result.data.session.date;
    $("val-slot").value = result.data.session.slot || "";
    $("val-room").value = result.data.session.room;
    $("val-start").value = result.data.session.startTime;
    $("val-end").value = result.data.session.endTime;
    $("val-students").textContent = result.data.students.length;
    $("student-list").replaceChildren(...result.data.students.map(student => {
      const item = document.createElement("div"); item.className = "student-item";
      item.textContent = student.studentCode + " · " + student.fullName;
      return item;
    }));
    for (const id of ["session-info", "btn-preview", "btn-send"]) $(id).classList.remove("hidden");
    status("Đã quét. Kiểm tra ngày, slot, phòng và giờ học trước khi gửi.", "success");
  } catch (e) { status(e.message, "error"); }
}
async function sendToDesktop() {
  if (!currentSessionData || busy) return;
  if (!$("session-form").reportValidity()) return;
  const start = $("val-start").value, end = $("val-end").value;
  if (start >= end) { status("Giờ kết thúc phải sau giờ bắt đầu.", "error"); return; }
  const payload = {
    ...currentSessionData,
    course: {...currentSessionData.course, courseCode: $("val-course").value.trim().toUpperCase()},
    class: {classCode: $("val-class").value.trim().toUpperCase()},
    session: {date: $("val-date").value, slot: Number($("val-slot").value),
      room: $("val-room").value.trim(), startTime: start, endTime: end}
  };
  busy = true; buttonState(); $("btn-rescan").disabled = true;
  $("btn-send").textContent = "Đang gửi…";
  try {
    const result = await chrome.runtime.sendMessage({type: "SEND_SESSION", data: payload});
    if (!result?.success) throw new Error(result?.message || "Không gửi được. Kiểm tra app rồi gửi lại.");
    status("Đã gửi " + result.studentCount + " sinh viên. Buổi học ở đầu tab Điểm danh với nhãn Hiện tại.", "success");
    $("btn-send").textContent = "Đã gửi — có thể gửi lại an toàn";
  } catch (e) {
    status(e.message, "error"); $("btn-send").textContent = "Gửi lại sang app";
  } finally { busy = false; $("btn-rescan").disabled = false; buttonState(); }
}
