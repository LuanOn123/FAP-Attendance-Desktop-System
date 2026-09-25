# Kiểm tra Report — 25/09/2026

> Cập nhật yêu cầu sau audit: người dùng xác nhận sinh viên trong roster không có bản ghi điểm danh phải mặc định ABSENT. Report đã áp dụng lại quy tắc này cho hiển thị, thống kê và Excel/CSV; không còn tạo UNMARKED cho dòng thiếu. Những mô tả UNMARKED bên dưới là kết quả audit trước khi thay đổi yêu cầu, đã được thay thế bởi quy tắc này. Việc đọc Report không tự ghi Sheet; giảng viên sửa trạng thái vẫn qua upsert, còn kết thúc phiên vẫn chốt vắng qua markAbsent.

## 1. Kết luận và nguồn dữ liệu

Report dùng chung `AttendanceRepository`, `Sessions`, `Attendance`, `Students` và `Enrollments` với màn hình điểm danh. Không có database báo cáo riêng. Tuy nhiên, trước sửa, phép chiếu trên giao diện không phản ánh đúng nguồn dữ liệu: tự tạo dòng ABSENT khi thiếu bản ghi, gộp nhiều bản ghi theo MSSV và loại sinh viên không còn trong roster hiện tại.

Sau sửa, một buổi báo cáo phải xác định đúng một session; dữ liệu tải lỗi hoặc trùng không được dùng để sửa/xuất. Dòng chưa có bản ghi là UNMARKED chỉ trên giao diện, không ghi trạng thái mới này xuống backend. Lịch sử thực đã lưu vẫn được hiển thị.

## 2. Nguyên nhân không sửa được ABSENT → PRESENT

- Dòng `absent-MSSV` do Report tự tạo không phải attendanceId đã lưu. Backend cũ chỉ cập nhật theo attendanceId nên không tìm thấy. Bản local đã có upsert theo sessionId + studentCode, kiểm tra quyền và enrollment; đợt này giữ và kiểm thử lại.
- Dialog nuốt exception khi lưu, khiến người dùng không biết schema/API/quyền đang lỗi. Đã hiển thị lỗi và giữ dialog để thử lại.
- Ảnh người dùng cho thấy backend từ chối schema Attendance. Đây là một nguyên nhân độc lập: chưa đọc được dữ liệu thì cũng không sửa được. Chưa có header Sheet thực để xác định cột nào lệch; không tự sửa header hoặc xóa dữ liệu.
- Repository trước đây không kiểm tra `saved: true`. Nay bắt buộc máy chủ xác nhận, rồi Report đọc lại dữ liệu thay vì tự thay trạng thái trong list.

## 3. Mức độ các lỗi xác nhận từ source

| Mức | Lỗi | Xử lý |
|---|---|---|
| HIGH | Lỗi lưu bị nuốt | Hiện lỗi ngay trong dialog |
| HIGH | Phản hồi tải cũ ghi đè lớp/buổi vừa chọn | Request generation bỏ phản hồi lỗi thời |
| HIGH | Nhiều phiên cùng ngày/slot hoặc nhiều bản ghi cùng MSSV bị gộp | Báo lỗi, chặn sửa/xuất |
| HIGH | Roster hiện tại làm mất lịch sử hoặc tự tạo vắng cho người vào muộn | Giữ bản ghi lịch sử; thiếu bản ghi là chưa xác nhận |
| HIGH | Dòng trống Sheet làm lệch vị trí update Attendance | Tìm physical row bằng attendanceId |
| HIGH | ID hợp lệ nhưng payload session/MSSV khác vẫn được cập nhật | Kiểm tra khớp identity phía API |
| MEDIUM | Refresh nhảy về buổi đầu | Giữ buổi đang chọn nếu còn tồn tại |
| MEDIUM | Classes bị ẩn nếu không có trong lịch hiện tại | Dùng toàn bộ classes được cung cấp |
| MEDIUM | Export dùng cache, bỏ ghi chú | Đọc mới trước xuất; giữ note; CSV quote đúng |
| MEDIUM | getClassHistory biến lỗi thành danh sách rỗng từng phiên | Bỏ catchError trả list rỗng; fallback toàn bộ API hoặc hiện lỗi |
| LOW | Slot được sắp theo chuỗi | Sắp số slot |
| LOW | Empty state chỉ nói đến QR | Dùng thông báo dữ liệu báo cáo chung |

Không phát hiện thêm lỗi mức CRITICAL trong phạm vi source đã kiểm tra. Điều này không phải xác nhận hệ thống production không còn lỗi.

## 4. Files của đợt sửa Report

- `lib/features/reports/attendance_report_screen.dart`: tải/refresh, chống race, kiểm tra trùng, lịch sử, trạng thái chưa xác nhận, export.
- `lib/features/reports/widgets/manual_update_dialog.dart`: lỗi lưu hiển thị; phải chọn trạng thái hợp lệ.
- `lib/features/reports/widgets/report_table.dart`: trạng thái chưa xác nhận, empty state, giờ UTC+7.
- `lib/repositories/attendance_repository.dart`: xác nhận lưu; không che lỗi lịch sử từng phiên.
- `backend/apps_script/Code.gs`: xác thực identity của update; physical row; ghi một range cho status/checkInTime/updatedAt/note/updatedBy; deduplicate danh sách chốt vắng.
- `backend/test/attendance.test.cjs`, `test/attendance_report_test.dart`, `test/extension_workflow_test.dart`: hồi quy và Excel thực.

Các thay đổi khác đã có trong working tree từ trước; không thuộc đợt audit này.

## 5. API và luồng lưu

Report gọi `getRows(Sessions)`/`getSessionsByClass`, `getRoster`, `getSessionAttendance`, `updateAttendance`. `getClassHistory` dùng cùng nguồn nhưng không phải đường tải chính của màn hình Report.

Luồng sửa: chọn record → gửi attendanceId, sessionId, studentCode, status, note → Google xác thực giảng viên → kiểm tra chủ phiên → kiểm tra identity/status → upsert nếu chưa có và sinh viên thuộc lớp, hoặc update dòng thực → `saved: true` → đọc lại session attendance → tính lại counters từ list vừa nhận. updatedBy phía server lấy từ giảng viên đã xác thực, không tin client.

Nếu lưu thành công nhưng đọc lại thất bại, không báo thành công giả bằng dữ liệu UI; Report hiển thị lỗi tải và có thể refresh để kiểm tra trạng thái đã lưu.

## 6. Database và schema

Không migration, xóa lịch sử, thay tên cột hay thêm cột. Attendance vẫn có đúng 8 cột:

`attendanceId, sessionId, studentId, status, checkInTime, updatedAt, note, updatedBy`

Không ghi UNMARKED xuống Sheet. Dòng thực vẫn dùng PRESENT/LATE/ABSENT. checkInTime gốc giữ nguyên khi giảng viên chỉnh sửa; updatedAt/updatedBy/note phản ánh lần sửa gần nhất. Chưa có audit trail bất biến lưu tất cả các lần sửa.

## 7. Kiến trúc trước / sau

Trước: cache attendance → gộp theo MSSV, ưu tiên PRESENT → giao với roster hiện tại → suy diễn vắng → sửa list sau request → xuất cache và bỏ note.

Sau: đúng một phiên → đọc attendance mới → phát hiện dữ liệu trùng/sai phiên → ghép tên roster nhưng giữ lịch sử → dòng thiếu chưa xác nhận → backend xác nhận lưu → đọc mới → counters → đọc mới trước Excel/CSV.

## 8. Tương thích vòng đời phiên

OPEN và CLOSED giữ hành vi cho phép giảng viên sở hữu chỉnh trạng thái. Không tự reopen/create/reset session trong Report. RESET không nằm trong danh sách Report, bản ghi cũ vẫn giữ trong Sheet. Backend hiện không có nghiệp vụ CANCELLED riêng; chưa tự đặt luật hủy buổi. Chốt phiên vẫn do Attendance screen gọi closeSession và markAbsent.

Ngày/slot lấy từ session; export giữ tên file lớp/môn/ngày/slot và 9 cột Member04 để tương thích extension. Hiển thị timestamp ISO theo UTC+7. Timestamp legacy không có timezone hoặc định dạng locale vẫn cần chuẩn hóa tại nguồn; không thể suy ra timezone gốc chắc chắn.

## 9. Roster, thống kê và giới hạn nghiệp vụ

Enrollments không có joinedAt/leftAt hoặc snapshot roster theo session. Do đó không thể khôi phục chính xác ai phải dự một buổi lịch sử chỉ từ roster hiện tại. Report không tự kết luận vắng cho trường hợp thiếu dữ liệu, và giữ bản ghi thật của người không còn trong roster.

Counters PRESENT/LATE/ABSENT tính từ trạng thái thực; UNMARKED không được cộng vào ABSENT. Tổng dòng có thể gồm người chưa xác nhận. Module hiện không có tỷ lệ phần trăm, bộ lọc trạng thái, tìm kiếm hoặc pagination; không thêm tính năng ngoài phạm vi sửa. ListView dựng dòng theo nhu cầu, nhưng backend vẫn quét sheet và chưa có load benchmark lớn.

## 10. Excel/CSV

Trước export đọc lại dữ liệu; nếu người dùng đổi lớp/buổi trong khi chờ, export đó bị hủy. Dữ liệu chưa xác nhận hoặc trạng thái ngoài P/L/A chặn xuất FAP. XLSX giữ ghi chú và trạng thái sau sửa. CSV dùng quoted fields, giữ dấu phẩy/dấu ngoặc kép/newline thay vì cắt mất tên/ghi chú.

Test integration thực: extension POST localhost → tạo phiên → QR demo → kết thúc, chốt vắng → Report → đổi sinh viên vắng thành có mặt, ghi note → ghi `.xlsx` → unzip XML kiểm tra PRESENT, không còn ABSENT và note mới. Đây là test local với demo repository, không phải Google Sheet production.

## 11. Ma trận kiểm chứng

| Case | Kết quả / phạm vi |
|---|---|
| TC01 mở report | Widget tests: dữ liệu/counters đúng fixture |
| TC02 ABSENT → PRESENT | UI integration + backend mock Sheets upsert/update |
| TC03 tải lại | Màn hình đọc lại repository và nhận attendanceId thật |
| TC04 PRESENT → ABSENT | UI + backend test |
| TC05/18 cách ly phiên | Backend test xác nhận bản ghi session khác không đổi; mismatch session bị từ chối |
| TC06 QR | Integration extension → demo check-in → Report |
| TC07 thủ công | Dialog/repository/backend tests |
| TC08 trùng | Backend retry không thêm dòng; duplicate hiện lỗi trên UI/backend |
| TC09 hủy | Không có CANCELLED; RESET đã có test giữ lịch sử và vô hiệu QR |
| TC10 hoàn tất | Test sửa phiên CLOSED |
| TC11 counters | Widget summary và list đọc mới; chưa test tất cả tổ hợp counter |
| TC12 tỷ lệ | Không có tính năng trong module hiện tại |
| TC13/14 lọc P/A | Không có bộ lọc trạng thái trong module hiện tại |
| TC15 Excel sau sửa | File XLSX thực được đọc và kiểm tra XML |
| TC16 restart backend/app | Mock persistence/readback đã kiểm tra; chưa restart và xác minh Sheet production |
| TC17 không có quyền | Backend auth/owner/enrollment/reset tests |
| TC19 vào lớp muộn | Thiếu dữ liệu là UNMARKED; test giữ lịch sử ngoài roster; chưa có timeline enrollment |
| TC20 dữ liệu lớn | Đã đọc source ListView và truy vấn; chưa đo latency/quota thực tế với Sheet lớn |

## 12. Validation

JavaScript suite: 56 tests pass (backend, web check-in, extension). Flutter: 48 tests, gồm test mới và test workflow Excel sau chỉnh sửa. Analyze không có lỗi. Kết quả build Windows ghi trong phản hồi kèm tài liệu này.

## 13. Các phần cố ý giữ nguyên

Google authorization, chủ sở hữu phiên, trạng thái phiên, quy trình tạo/đóng/reset, format tích hợp FAP và nguồn dữ liệu chung. Không thay schema để giả lập enrollment timeline, không tự merge/xóa các dòng dữ liệu trùng.

## 14. Production và việc còn phải xác minh

Chưa deploy Apps Script trong đợt này. Code local mới phải được cập nhật vào đúng Apps Script deployment mà desktop sử dụng. Chưa kiểm chứng lỗi header Attendance trên Google Sheet thực; cần đối chiếu header và nội dung cột trước migration có backup. Không thể khẳng định ABSENT → PRESENT đã hoạt động trên production chỉ dựa vào test local.

Debt còn lại: roster timeline/snapshot, immutable correction audit log, pagination/index cho sheet lớn, quota/concurrency ngoài Apps Script lock (sửa trực tiếp Google Sheet không theo lock), timestamp legacy, kiểm thử race class switching đầy đủ và thử nghiệm tài khoản thật sau deploy.
