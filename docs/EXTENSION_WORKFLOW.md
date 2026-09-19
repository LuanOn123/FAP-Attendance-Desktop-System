# Extension → Điểm danh → Báo cáo Excel

Phạm vi: FAP Attendance Desktop. Không sử dụng API Sports Center.

## Chạy thử với file HTML hiện có

1. Mở bản desktop mới tại `build/windows/x64/runner/Release/fap_attendance.exe` và đăng nhập giảng viên. Giữ nguyên cả thư mục Release khi sao chép ứng dụng, không chỉ lấy file exe.
2. Trong Chrome/Edge, mở trang quản lý Extensions, bật Developer mode, chọn **Load unpacked** và chọn thư mục `fap-attendance-extension` của repository. Nếu đã nạp extension trước đó, bấm **Reload**.
3. Trong Details của extension, bật **Allow access to file URLs**. Mở/tải lại `C:/Users/ADMIN/Desktop/New folder/attendance.html`.
4. Bấm icon extension. Popup tự quét trang và kiểm tra app desktop. File mẫu trả về `SWE102`, `SE1701`, `18/09/2026`, 4 sinh viên. File không có slot/phòng/giờ: điền các ô này, sửa ngày nếu muốn tạo buổi khác. Giờ gợi ý theo slot có thể sửa.
5. Kiểm tra danh sách rồi bấm **Gửi sang app Điểm danh**. Desktop tự chuyển sang tab **Điểm danh**, đưa buổi vừa nhập lên đầu với nhãn **Hiện tại**. Nhãn này chỉ buổi vừa nhập, không tự đổi ngày học thành hôm nay.
6. Bấm **Tạo phiên**, thực hiện điểm danh QR theo luồng hiện có. Gửi lại cùng dữ liệu không nhân đôi lịch/danh sách. Mở lại cùng lớp/ngày/slot dùng phiên đã có. Đổi tab không làm mất phiên đang mở.
7. Bấm **Kết thúc phiên**: khóa check-in rồi ghi ABSENT cho những người chưa điểm danh. Nếu bước ghi vắng lỗi mạng, bấm **Chốt danh sách vắng** để thử lại.
8. Bấm **Báo cáo / Excel**: mở đúng lớp, ngày và slot vừa điểm danh. Kiểm tra/chỉnh trạng thái rồi bấm **Xuất Excel (.xlsx)** và chọn nơi lưu. Sử dụng màn hình và bộ xuất Excel đã merge từ Member 4.

Extension nhập thông tin buổi học và danh sách sinh viên; các nút Có mặt/Vắng mặc định của HTML mẫu không tự được coi là kết quả điểm danh. Kết quả được ghi qua phiên trong app. Danh sách nhập và phiên đã tạo được lưu qua repository; nhãn Hiện tại và ngữ cảnh ngày trước khi tạo phiên giữ trong lần đăng nhập hiện tại. Nếu khởi động lại trước khi tạo phiên, quét/gửi lại trang để chọn đúng ngày.

## Cấu hình và kết nối

- Desktop mở HTTP loopback `127.0.0.1:8765` sau khi đăng nhập; đăng xuất đóng kết nối.
- `GET /api/integration/health` trả application + protocolVersion.
- `POST /api/integration/fap/session` nhận JSON với header `X-FAP-Attendance-Client: browser-extension`.
- Request phải đến từ background worker của extension. Origin web thông thường bị từ chối; payload tối đa 1 MB, 1–1.000 sinh viên.
- Popup hiển thị thiếu quyền đọc file, desktop chưa mở, thiếu trường, lỗi mạng hoặc lỗi backend. Bấm **Quét lại / Kết nối lại** sau khi khắc phục.
- Nếu cổng 8765 đã có app khác dùng, desktop hiển thị biểu tượng lỗi ở thanh trên. Đóng bản app cũ rồi đăng nhập lại.

## Backend và giới hạn kiểm chứng

Nhánh `origin/feature/report` đã merge vào `feature/FE-Management_Student` ở commit `8da9a0a`. Google Apps Script đang deploy phải tương ứng với `backend/apps_script/Code.gs` của nhánh đã merge, gồm `createSession`, `getSessionsByClass`, `getSessionAttendance`, `markAbsent`, `updateAttendance` và roster. Nếu server báo thao tác chưa hỗ trợ, cập nhật deployment hiện có từ Code.gs; không cần tạo một hệ thống Sports Center khác.

Đã kiểm tra file HTML thật bằng DOM test, popup và kết nối loopback. Test toàn luồng dùng repository demo: POST → ghim buổi học → tạo phiên đúng ngày → check-in → đóng phiên/ghi vắng → báo cáo → mở và kiểm tra nội dung XLSX thực sự. Chưa kiểm chứng đăng nhập Google/điện thoại trên deployment thật trong phiên làm việc này, chưa thay đổi deployment cloud.

## Kiểm tra lại

```powershell
flutter analyze --no-pub
flutter test --no-pub
node --test backend/test/*.test.cjs
npm install --prefix .tools/extension-tests --no-audit --no-fund jsdom@26.1.0
$env:FAP_HTML_FIXTURE = 'C:\Users\ADMIN\Desktop\New folder\attendance.html'
node --test fap-attendance-extension/test/*.test.cjs
flutter build windows --release --dart-define-from-file=config/local.json
```

`config/local.json` chứa cấu hình riêng và phải tiếp tục nằm trong `.gitignore`. Không gửi file cấu hình hoặc bundle exe có thông tin riêng lên repository công khai.
