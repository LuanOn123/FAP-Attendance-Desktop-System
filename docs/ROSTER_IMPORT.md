# Lịch tuần và nhập sinh viên

## Sử dụng

1. Mở bản ứng dụng cập nhật. Lịch mặc định hiển thị theo bảng tuần; chọn học kỳ hoặc tìm môn/lớp/phòng. Bấm vào buổi học để xem chi tiết, sửa hoặc xóa. Nút **Danh sách** chuyển về kiểu danh sách.
2. Mở **Lớp học**. Các lớp được lấy từ lịch dạy và bảng Classes hiện có. Chọn lớp rồi bấm **Nhập sinh viên từ Excel / ODS**.
3. Chọn `.xlsx` hoặc `.ods`, sheet, học kỳ và mã lớp. Ứng dụng đọc `Class`, `RollNumber`, `FullName`, `Email` (không bắt buộc). Không lấy điểm hoặc ExamNote.
4. Lớp/môn được chọn tự động khi khớp học kỳ + mã lớp + môn trong tên sheet. Nếu mã môn không khớp hoặc có nhiều khả năng, cần chọn lớp/môn đích sau khi đối chiếu. Không ghép chỉ theo môn hoặc mã lớp.
5. Duyệt danh sách và bấm **Thêm … sinh viên vào lớp**. Lớp chỉ có trong lịch được tạo trong Classes; sinh viên dùng RollNumber làm khóa; Enrollments nối sinh viên với lớp học. Các buổi cùng môn/lớp dùng chung danh sách. Lặp lại cho sheet/lớp tiếp theo nếu file chứa nhiều lớp.

Nhập lại không tạo enrollment trùng. Không xóa sinh viên cũ vắng mặt trong file mới. Hồ sơ sinh viên đã tồn tại được giữ nguyên; nếu cùng mã sinh viên nhưng khác họ tên, máy chủ từ chối toàn bộ lần nhập để đối chiếu. Email cá nhân trong mẫu được chấp nhận. `.xls` cũ cần Save As `.xlsx`. File được đọc cục bộ; chỉ danh sách đã chọn được gửi đến Google Sheets đã cấu hình khi bấm thêm.

## Cập nhật máy chủ (bắt buộc cho tài khoản thật)

Ứng dụng mới gọi hai action `getRoster` và `importRoster`; deployment cũ chưa có các action này.

1. Mở project Apps Script đang phục vụ ứng dụng, thay nội dung **Code.gs** bằng `backend/apps_script/Code.gs` trong dự án này và lưu.
2. Giữ nguyên Script Properties và URL hiện có. Bảo đảm Google Sheets API v4 đã bật như cấu hình cũ.
3. Nếu thiếu sheet, chạy `setupSheets()`. Hàm chỉ tạo sheet/header còn thiếu, không xóa dữ liệu. Các sheet cần có: Classes, Students, Enrollments, Schedules và SyncLogs, với header theo SCHEMA trong Code.gs.
4. Chọn **Deploy → Manage deployments → Edit → Version: New version → Deploy** cho deployment hiện tại. Chỉ Save code chưa cập nhật endpoint `/exec`. Giữ URL để không cần thay cấu hình Flutter.
5. Trong bản ứng dụng mới, mở Lớp học, chọn một lớp và Tải lại. Sau khi nhập, tải lại hoặc mở lại ứng dụng để xác minh danh sách lưu trên Sheets.

Không triển khai tự động vào tài khoản thật trong phiên sửa mã này vì chưa có phiên quản trị Apps Script kết nối. Chưa ghi danh sách sinh viên mẫu vào dữ liệu thật.

## File mẫu đã kiểm tra

`FA26_Markbook.ods`: 8 sheet, 282 dòng sinh viên theo lớp/môn (không phải 282 sinh viên duy nhất). Các sheet có 35, 35, 36, 36, 35, 35, 33 và 37 dòng; không có lỗi dữ liệu bắt buộc. Sheet `23_PRM232` lấy mã SE1922 từ cột Class; không suy ra lớp từ tên sheet. Các mã PRM392, PRM232, PRM323 trong một số tên sheet khác ảnh lịch: phần duyệt không tự đổi mã môn.

## Kiểm thử

Parser có kiểm thử ODS (ô/dòng lặp), XLSX (shared/inline strings, ô trống), Unicode, dữ liệu thiếu và trùng. Widget tests kiểm tra tự ghép, môn không khớp, sai lớp, nhập lại và lịch tuần. Backend tests kiểm tra ownership, tạo lớp từ lịch, tái sử dụng sinh viên, chống trùng, từ chối sai họ tên và không thay đổi dữ liệu khi batch lỗi. Toàn bộ thay đổi Classes/Students/Enrollments được gửi cùng một Sheets batchUpdate; các dòng hiện có được giữ nguyên.

Thư viện đọc cấu trúc bảng tính: [archive](https://pub.dev/packages/archive) và [xml](https://pub.dev/packages/xml).
