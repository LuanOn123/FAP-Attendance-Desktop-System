const DESKTOP_URL = "http://127.0.0.1:8765";

async function desktopRequest(path, data) {
  const res = await fetch(DESKTOP_URL + path, {
    method: data ? "POST" : "GET",
    headers: {"Content-Type": "application/json", "X-FAP-Attendance-Client": "browser-extension"},
    ...(data ? {body: JSON.stringify(data)} : {}),
    signal: AbortSignal.timeout(data ? 120000 : 4000)
  });
  const result = await res.json();
  if (!res.ok) throw new Error(result.message || "Desktop trả lỗi " + res.status);
  return result;
}
chrome.runtime.onMessage.addListener((request, sender, sendResponse) => {
  if (sender.id !== chrome.runtime.id) return;
  if (sender.tab) {
    if (request.type !== 'GET_REPORT') return;
    try {
      const url = new URL(sender.url || sender.tab.url);
      if (!(url.hostname === 'fap.fpt.edu.vn' || ['localhost', '127.0.0.1'].includes(url.hostname) || (url.protocol === 'file:' && /attendance\.html$/i.test(url.pathname)))) return;
    } catch { return; }
  }
  if (!["CHECK_HEALTH", "SEND_SESSION", "GET_REPORT"].includes(request.type)) return;
  (async () => {
    try {
      if (request.type === "CHECK_HEALTH") {
        const data = await desktopRequest("/api/integration/health");
        if (data.application !== "FAP Attendance Desktop" || data.protocolVersion !== 1) {
          throw new Error("Bản desktop chưa hỗ trợ connector này.");
        }
        sendResponse({status: "ok", data});
      } else if (request.type === 'GET_REPORT') {
        sendResponse(await desktopRequest('/api/integration/fap/report', request.data));
      } else {
        sendResponse(await desktopRequest("/api/integration/fap/session", request.data));
      }
    } catch (e) {
      sendResponse({success: false, status: "error", message: e.message});
    }
  })();
  return true;
});
