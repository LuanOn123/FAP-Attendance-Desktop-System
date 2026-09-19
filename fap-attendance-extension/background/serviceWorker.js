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
  // Only the extension popup may write. Content scripts merely scan the DOM.
  if (sender.id !== chrome.runtime.id || sender.tab) return;
  if (!["CHECK_HEALTH", "SEND_SESSION"].includes(request.type)) return;
  (async () => {
    try {
      if (request.type === "CHECK_HEALTH") {
        const data = await desktopRequest("/api/integration/health");
        if (data.application !== "FAP Attendance Desktop" || data.protocolVersion !== 1) {
          throw new Error("Bản desktop chưa hỗ trợ connector này.");
        }
        sendResponse({status: "ok", data});
      } else {
        sendResponse(await desktopRequest("/api/integration/fap/session", request.data));
      }
    } catch (e) {
      sendResponse({success: false, status: "error", message: e.message});
    }
  })();
  return true;
});
