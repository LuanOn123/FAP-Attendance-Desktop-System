let importedAttendance = null;
let importRevision = 0;
function resetImportReview() {
  importRevision++;
  importedAttendance = null;
  $('btn-auto-attendance').disabled = true;
  $('attendance-file').value = '';
  $('import-summary').textContent = 'Chọn file .xlsx để đối chiếu với trang đang mở.';
  $('import-result').textContent = '';
}
async function attendanceMessage(type, data) {
  if (!scannedTabId) throw new Error('Quét trang điểm danh trước khi nhập Excel.');
  const [active] = await chrome.tabs.query({active: true, currentWindow: true});
  if (active?.id !== scannedTabId) throw new Error('Tab đã thay đổi. Quét lại trang và chọn lại file.');
  await chrome.scripting.executeScript({target: {tabId: scannedTabId}, files: ['content/fapAttendanceScanner.js', 'content/fapAttendanceWriter.js']});
  const result = await chrome.tabs.sendMessage(scannedTabId, {type, data});
  if (!result?.success) throw new Error(result?.message || 'Trang không phản hồi. Tải lại trang rồi thử lại.');
  return result.data;
}
document.addEventListener('DOMContentLoaded', () => {
  $('attendance-file').addEventListener('change', async event => {
    const revision = ++importRevision;
    importedAttendance = null;
    $('btn-auto-attendance').disabled = true;
    $('import-result').textContent = '';
    const file = event.target.files[0];
    if (!file) return;
    $('import-summary').textContent = 'Đang đọc và đối chiếu ' + file.name + '…';
    try {
      if (file.size > 10 * 1024 * 1024) throw new Error('File quá lớn (tối đa 10 MB).');
      const data = AttendanceWorkbook.read(await file.arrayBuffer(), file.name, XLSX);
      const preview = await attendanceMessage('PREVIEW_ATTENDANCE', data);
      if (revision !== importRevision) return;
      importedAttendance = data;
      $('import-summary').textContent = `${data.metadata.courseCode} · ${data.metadata.classCode} · ${data.metadata.date} · Slot ${data.metadata.slot}. Khớp ${preview.matched} MSSV: ${preview.present} Có mặt, ${preview.absent} Vắng mặt. Giữ nguyên ${preview.unchanged} sinh viên ngoài file.`;
      $('btn-auto-attendance').disabled = false;
    } catch (e) {
      if (revision === importRevision) $('import-summary').textContent = e.message;
    }
  });
  $('btn-auto-attendance').addEventListener('click', async () => {
    if (!importedAttendance || busy) return;
    busy = true; buttonState();
    for (const id of ['btn-auto-attendance', 'attendance-file', 'btn-rescan']) $(id).disabled = true;
    $('import-result').textContent = 'Đang điền trạng thái theo MSSV…';
    try {
      const result = await attendanceMessage('APPLY_ATTENDANCE', importedAttendance);
      $('import-result').textContent = `Đã điền ${result.applied} dòng: ${result.present} Có mặt, ${result.absent} Vắng mặt. Chưa bấm Lưu. Kiểm tra trang FAP để hoàn tất.`;
    } catch (e) { $('import-result').textContent = e.message; }
    finally {
      busy = false; buttonState();
      for (const id of ['attendance-file', 'btn-rescan']) $(id).disabled = false;
      // Require a fresh preview before another application.
      importedAttendance = null;
      $('attendance-file').value = '';
    }
  });
});
