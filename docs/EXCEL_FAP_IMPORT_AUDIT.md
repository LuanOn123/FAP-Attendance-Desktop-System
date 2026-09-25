# Excel → FAP attendance audit (25/09/2026)

## Luồng hiện hành: lấy báo cáo đang chọn trên Desktop

Yêu cầu mới thay thế điều kiện tìm buổi theo trang trong phần lịch sử bên dưới. Mở tab Report, chọn lớp/buổi, đợi tải thành công: Report gửi classId/sessionId vào IntegrationServer (chỉ lưu lựa chọn trong phiên đăng nhập). Extension gửi GET_REPORT với selectedReport=true; Desktop đọc mới đúng session đã chọn, kiểm tra quyền giảng viên và không dùng date/slot của HTML để chọn phiên khác. Khi Report đang tải/lỗi, lựa chọn bị vô hiệu; sau restart cần chọn lại báo cáo.

Thiếu bản ghi trong roster mặc định ABSENT như tab Report; bản ghi lịch sử ngoài roster cũng giữ trong payload. OPEN/CLOSED đều được đọc theo lựa chọn, RESET bị từ chối. Payload chứa fullName và matchMode=selectedReport. Writer đối chiếu mã lớp và toàn bộ MSSV/họ tên (Unicode NFC, không phân biệt hoa thường/khoảng trắng); tên không khớp hoặc thiếu/trùng sinh viên thì chặn. Ngày/slot/giờ của report được hiển thị để giảng viên xem, không dùng metadata HTML để chặn luồng lựa chọn này. Luồng Excel và API tìm buổi cũ giữ kiểm tra riêng.

Panel có Tải lại báo cáo, tự làm mới mỗi 30 giây khi trang hiển thị. Đồng bộ đọc lại payload; nếu report thay đổi từ preview thì yêu cầu xem lại và bấm lần nữa. Không bấm Save. Test HTTP thật localhost xác nhận report đang chọn trên UI được trả về; test DOM xác nhận khác ngày/slot vẫn preview, sai tên bị chặn, không submit. Chrome thật vẫn cần reload extension và HTML sau cập nhật.

## Cập nhật điều kiện đồng bộ trực tiếp từ Desktop

Theo yêu cầu tiếp theo của người dùng: GET_REPORT và writer cho `source: desktop` chỉ đối chiếu mã lớp, ngày học, slot, giờ bắt đầu và giờ kết thúc; không lọc theo môn/học kỳ. Vẫn kiểm tra giảng viên sở hữu phiên, phiên CLOSED, duy nhất một kết quả, roster và trạng thái hợp lệ. Không có kết quả sẽ nêu rõ các giá trị đang tìm. Luồng nhập Excel giữ quy tắc riêng bên dưới. Kết nối desktop thành công chưa đồng nghĩa đã có báo cáo cho buổi đang mở.

## Kết luận và bằng chứng trước sửa

Lỗi đã tái hiện bằng source hiện tại, file `attendance.html` ở thư mục gốc dự án và file Excel thật trong Downloads. `scan()` thấy table nhưng không nhận header `Member Code / Roll Number`; alias chỉ có `Roll Number` và các tên đơn. Hàm cũng bỏ qua `tr[data-student-code]`, nên không tìm được cột MSSV, bỏ qua cả bảng và ném thông báo khi `students.size === 0`. Writer có bộ dò header riêng và mắc cùng lỗi.

Desktop kết nối qua service worker/localhost là đường độc lập. Excel đã chọn cũng không chứng minh DOM đã quét được. `currentSessionData` và `scannedTabId` không được thiết lập khi scan thất bại, nên import không có preview hợp lệ và nút Start vẫn disabled.

| Kiểm tra | Kết quả thực tế |
|---|---|
| Active Chrome tab | Không truy cập được Chrome của người dùng qua công cụ hiện có; inventory chỉ có in-app browser không có tab |
| Content script trong Chrome thật | Chưa xác minh; không khẳng định đã inject |
| File URL permission thực tế | Chưa xác minh công tắc của người dùng |
| Manifest | Đã có file:///* ở host_permissions và content_scripts.matches, activeTab, scripting |
| HTML gốc dự án | 1 bảng `ctl00_mainContent_gvStudents`, 35 dòng có data-student-code |
| Trước sửa | Quét thất bại với đúng thông báo người dùng báo |
| Excel thực | `Diemdanh_PRM393_SE1922_2026-09-25_Slot3.xlsx` |
| Workbook | 1 sheet `DiemDanh_SE1922`, 35 dòng hợp lệ, 1 PRESENT, 34 ABSENT |
| Metadata HTML | PRM393 / SE1922 / 22-09-2026 / Slot 4 |
| Metadata Excel | PRM393 / SE1922 / 25-09-2026 / Slot 3 |
| Desktop/New folder/attendance.html | Bản cũ SWE102 / SE1701, 4 sinh viên; không dùng với Excel trên |

File quyền bị tắt có thông báo riêng từ popup trước khi gọi scanner. Vì lỗi parser đã tái hiện độc lập, không có bằng chứng rằng thiếu quyền file là nguyên nhân của thông báo cụ thể này.

## Call flow thực tế

1. `popup/popup.html` tải `popup.js`, vendor SheetJS, `shared/attendanceWorkbook.js`, `excelImport.js`.
2. `popup.js`: DOMContentLoaded → `refresh()` → song song `checkDesktop()` và `scanPage()`.
3. `checkDesktop()` → runtime CHECK_HEALTH → `background/serviceWorker.js` → `desktopRequest('/api/integration/health')`. Kết quả chỉ cập nhật trạng thái desktop.
4. `scanPage()` → tabs.query active/currentWindow → kiểm tra URL và `isAllowedFileSchemeAccess()` → tabs.sendMessage SCAN_ATTENDANCE. Nếu chưa có listener, executeScript scanner + writer rồi gửi lại.
5. `content/fapAttendanceScanner.js`: listener → `scan(document)` → `studentRows(document)` → trả course/class/session/students.
6. Popup lưu currentSessionData/scannedTabId và hiển thị số sinh viên. Lỗi quét không được coi là desktop offline.
7. `excelImport.js`: change file → `AttendanceWorkbook.read()` → parseRows theo header → tự quét lại nếu chưa có dữ liệu trang → `reviewSelectedWorkbook()`.
8. `attendanceMessage('PREVIEW_ATTENDANCE')` → kiểm tra tab hiện tại → writer `plan()` → scan metadata + rowsByCode + kiểm tra control từng dòng. Preview không thay đổi radio.
9. Chỉ khi preview thành công và không busy, lưu importedAttendance và bật Start.
10. Start → APPLY_ATTENDANCE → `apply()` chạy lại plan trước khi ghi → tìm từng row theo MSSV → radio 1/0 hoặc nút trạng thái tương ứng → cập nhật qua click/change tự nhiên của control. Không click Save/submit.

`content/fapSyncPanel.js` là luồng panel lấy report trực tiếp từ Desktop bằng GET_REPORT; dùng cùng scanner/writer. Service worker không giữ roster hoặc workbook trong biến dùng lâu dài. Popup giữ state trong vòng đời popup; đóng popup cần chọn lại Excel. Không cần thêm storage permission.

## Thay đổi

- `content/fapAttendanceScanner.js`: alias Member Code và compound header; ưu tiên data-student-code; normalize whitespace/Unicode; tách lỗi thiếu bảng và không đọc được MSSV; cung cấp studentRows dùng chung.
- `content/fapAttendanceWriter.js`: dùng studentRows, ghép bằng normalized MSSV; kiểm tra thiếu MSSV trước mọi thay đổi, báo số khớp và danh sách thiếu. Không ghép theo tên hoặc vị trí dòng.
- `popup/popup.js`: lỗi file permission/content unavailable/page access riêng biệt; rescan khóa nút, quét lại tab và kết nối desktop, chạy lại preview.
- `popup/excelImport.js`: giữ workbook khi rescan, invalidate preview cũ, tự scan khi chọn file mà chưa có roster, summary số Excel/trang/khớp/ngoài file.
- `shared/attendanceWorkbook.js`: thêm alias header, fallback ký hiệu FAP, hỗ trợ P/A/L và chữ thường. Unknown hoặc status/symbol mâu thuẫn vẫn chặn.
- Tests: scanner, popup, excelImport bổ sung hồi quy; fixture Excel thật được truyền bằng FAP_EXCEL_FIXTURE, không thêm dữ liệu cá nhân vào source test.

Không sửa manifest, không thêm quyền, không sửa service worker, không thay HTML và workbook thật của người dùng. Những thay đổi có sẵn ở scanner được giữ khi cập nhật.

## Quy tắc mapping và metadata

- PRESENT / P → present → value 1.
- ABSENT / A → absent → value 0.
- LATE / L → present → value 1 (giữ quy tắc hiện có).
- Unknown, MSSV trùng, control disabled hoặc thiếu control: chặn trước ghi.
- Excel thiếu 1 MSSV trên trang: báo ví dụ Khớp 34/35 và MSSV thiếu; không tự nhập phần còn lại.
- Trang có thêm sinh viên ngoài Excel: giữ nguyên các dòng đó, hiển thị số lượng; đây là hành vi Excel import đã có.
- Metadata thực sự tồn tại trên trang phải khớp. Với Excel, metadata không tồn tại không gây lỗi; như yêu cầu, không suy đoán metadata trang từ file. Với report nguồn desktop, vẫn yêu cầu đủ metadata và giờ học khớp như trước.
- HTML thật hiện khác ngày/slot Excel nên sau sửa scanner, nút vẫn bị chặn đúng lý do metadata. Không bỏ kiểm tra này để bật nút giả.

## Test và giới hạn

22 tests extension đạt khi chạy với FAP_EXCEL_FIXTURE trỏ tới Excel thật. Bao gồm scanner alias/data attribute/thứ tự cột, layout card cũ, header FAP, file access có/không (mock), reinjection thất bại, unknown status, sai lớp/môn/ngày/slot, radio disabled, MSSV thiếu/trùng, LATE, preview không ghi, đảo dòng, rescan giữ file, tab thay đổi, desktop offline, panel desktop và Google check-in liên quan.

Acceptance Excel thật: xác nhận HTML nguyên bản bị chặn do khác ngày/slot và radio không đổi; sau đó chỉnh chỉ DOM trong bộ nhớ test sang ngày/slot Excel, đảo 35 dòng, preview thành công, bật nút Start trong popup test, điền 35 dòng. Kiểm tra từng radio theo MSSV, bộ đếm 1 có mặt/34 vắng, notice Save không đổi. Không thay source HTML để che mismatch.

TC01/02/15/18 là JSDOM + Chrome API mock; không phải thao tác extension trên Chrome thật. TC03 kiểm tra cấu trúc DOM FAP tương thích và URL production qua mock, chưa thao tác tài khoản FAP thật. Không thể chứng minh Chrome setting hoặc content script đang chạy trong profile người dùng bằng các test này. Trang iframe/shadow DOM/phân trang chưa tải hết không được tự gom; cần mở đủ danh sách.

## Chạy local và giữ production

1. Mở chrome://extensions, Reload extension trỏ tới thư mục `fap-attendance-extension` trong dự án này.
2. Vào Details, bật Allow access to file URLs. Đây là công tắc theo từng extension; xem [tài liệu Chrome](https://developer.chrome.com/docs/extensions/reference/extension).
3. Reload tab HTML để thay listener cũ. Scanner/writer có guard chống duplicate listener, vì vậy chỉ reload popup có thể vẫn giữ bản content script cũ.
4. Mở đúng HTML lớp/môn/ngày/slot tương ứng với Excel. File gốc hiện ngày 22/09 Slot 4; Excel ngày 25/09 Slot 3 cần trang buổi tương ứng.
5. Mở popup → Quét lại → chọn Excel → xem summary → Start → kiểm tra → tự bấm Lưu.

Allowlist vẫn là FAP + file/local dev đã có. Không dùng all_urls, không bỏ page validation, không thêm cookies/tabs/storage permissions. Build production riêng nếu phát hành Store cần loại content matches và host permissions local-test; việc đóng gói Store chưa nằm trong đợt sửa này.
