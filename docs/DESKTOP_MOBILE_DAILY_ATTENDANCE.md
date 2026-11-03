# Đồng bộ điểm danh desktop và mobile

Ngày cập nhật: 30/10/2026.

## Cách dùng

1. Đăng nhập cùng giảng viên trên desktop/mobile; cả hai cấu hình cùng Apps Script deployment và spreadsheet.
2. Desktop có nút biểu tượng **Điểm danh nhanh hôm nay** trên thanh trên cùng. Hoặc mở thẻ **Điểm danh hôm nay** tại Lịch dạy, hoặc nút **Điểm danh nhanh trong ngày** trong màn hình Điểm danh.
3. Chọn buổi học → **Điểm danh nhanh**. Buổi đã chốt có **Xem / Điều chỉnh**.
4. Sinh viên chưa có kết quả mặc định Có mặt trong bản nháp; chỉ chọn những sinh viên Vắng. Có tìm MSSV/tên không dấu, lọc sinh viên Vắng và Hoàn tác.
5. Bấm **Kiểm tra / Lưu điểm danh**, xem số lượng và danh sách ngoại lệ, rồi **Xác nhận lưu điểm danh**. Mở trang hoặc để tất cả mặc định Có mặt không tự ghi điểm danh.
6. Bản nháp được lưu theo tài khoản + lớp + ngày + slot + lịch/ngoại lệ. Nếu danh sách hoặc revision thay đổi, không tự khôi phục lựa chọn cũ lên dữ liệu mới.
7. Mạng lỗi sau khi gửi: **Kiểm tra lần gửi trước** gửi lại đúng payload và mã yêu cầu đã lưu. Có thể đóng/mở lại trang; không tạo yêu cầu mới cho một lần gửi chưa rõ kết quả. Dùng Tải lại để đối chiếu và bỏ nháp sau khi xác nhận.

## Giờ được phép

- Điểm danh nhanh thực hiện bất kỳ lúc nào trong **ngày học**, kể cả trước giờ bắt đầu hoặc sau khi hết giờ học, đến **23:59:59 giờ Việt Nam**.
- Đúng **00:00 ngày hôm sau** không ghi hoặc điều chỉnh mới cho ngày trước. Retry một lần đã lưu có thể chỉ trả lại biên nhận cũ, không tạo thêm bản ghi.
- Giờ máy chủ và trạng thái editable là căn cứ. Máy tính đổi múi giờ không đổi quy tắc UTC+7.
- QR vẫn theo cửa sổ buổi học hiện có (mở từ 15 phút trước giờ, hạn phiên theo server). Quyền điểm danh cả ngày áp dụng cho **điểm danh nhanh**, tương tự mobile; không kéo dài QR qua đêm.
- Lịch bị hủy/đổi phải đi theo occurrence của backend. Buổi reset không được tự tạo lại bằng luồng nhanh.

## Nhắc điểm danh

Trong **Lịch dạy → mở Điểm danh hôm nay**:

1. Chọn đúng học kỳ.
2. Bật **Nhắc buổi chưa hoàn tất điểm danh**.
3. Bấm **Thử thông báo Windows** để kiểm tra thông báo hệ điều hành.

Giống mobile, có tối đa bốn mốc/buổi: giữa buổi, trước giờ kết thúc 5 phút, sau giờ kết thúc 10 phút và 21:00. Mốc trùng được gộp; không phát mốc từ 00:00 hôm sau trở đi. Khi app vừa mở không phát lại toàn bộ thông báo đã qua; buổi chưa chốt vẫn hiện trong danh sách.

Desktop đồng bộ trạng thái mỗi 30 giây khi đang đăng nhập. Buổi được chốt trên mobile, bị hủy hoặc không còn trong học kỳ đang chọn sẽ được bỏ nhắc sau lần đồng bộ tiếp theo. Thông báo bấm vào mở đúng buổi nhanh.

**Phạm vi:** thông báo Windows hoạt động khi ứng dụng còn chạy, kể cả thu nhỏ; chưa cài tác vụ nền để đánh thức ứng dụng sau khi thoát hoàn toàn. Âm thanh/banner còn phụ thuộc Windows Notifications và Không làm phiền. Nếu thông báo lỗi, dữ liệu điểm danh vẫn hoạt động và app báo riêng lỗi thông báo. Có nút bật/tắt và cài đặt riêng theo tài khoản trên máy; cài đặt nhắc Windows không tự ghi đè cài đặt Android.

Triển khai toast dựa trên API chính thức của [local_notifier](https://pub.dev/packages/local_notifier). Kết quả kiểm thử tự động không thay thế kiểm tra banner/âm thanh trên máy Windows thực tế.

## Backend cần cập nhật

Mã backend dùng chung ở **C:/PRM/lecture_mobile/backend/apps_script**. Cập nhật **Code.gs** và **AttendanceSafety.gs** trong cùng Apps Script project đang phục vụ mobile. Giữ các file hỗ trợ Lab2Free.gs, ScheduleAttendance.gs, ClassTools.gs, SubjectInsights.gs và StudentPortal.gs theo phiên bản hiện có.

Không deploy Code.gs độc lập của repo desktop đè lên backend chung.

- Nếu chưa có bảng Lab2*, chạy `setupLab2Free()` thủ công với quyền chủ sở hữu trước.
- Tạo version mới và cập nhật deployment `/exec` đang dùng cho cả hai app.
- Không đổi các Script Properties xác thực Google/Firebase đang hoạt động. Desktop tiếp tục dùng Google OAuth token, mobile dùng Firebase token theo đường xác thực riêng.
- Chưa chạy deploy hoặc thao tác dữ liệu thật trong lượt sửa mã này.

Thêm action `desktopAttendanceCall` sau xác thực lecturer, chỉ cho ba thao tác:

| name | Hành vi |
| --- | --- |
| getAttendanceDay | Buổi của giảng viên theo ngày, lịch ngoại lệ, trạng thái hoàn tất và khả năng QR/quick |
| getQuickAttendanceContext | Dùng lab2QuickContext_ giống mobile: danh sách, baseline, revision, editable, serverTime |
| submitQuickAttendance | Dùng lab2Mutate_ / lab2QuickSubmit_ giống mobile: lock, kiểm tra revision/roster, audit, receipt idempotent và chốt buổi |

Các kết quả vẫn lưu vào Sessions, Attendance, Lab2SessionMeta, Lab2AttendanceCompletion và AttendanceAudit; không tạo kho dữ liệu riêng cho desktop. LATE/EXCUSED trong trình biên tập hai trạng thái được xử lý theo baseline/chuẩn hóa của luồng nhanh mobile hiện có; không thay chính sách tỷ lệ vắng hoặc quy tắc xuất FAP trong đợt này.

## Kiểm tra và chạy

Desktop:

```powershell
cd C:\PRM\FAP-Attendance-Desktop-System
flutter pub get
flutter analyze --no-pub
flutter test --no-pub
flutter run -d windows --dart-define-from-file=config/local.json
```

Backend chung:

```powershell
cd C:\PRM\lecture_mobile
node --test backend/test/auth.test.cjs backend/test/lab2-free.test.cjs backend/test/student-portal.test.cjs backend/test/desktop-daily-attendance.test.cjs
```

Kiểm tra thủ công với lớp thử: mở nhanh chưa lưu không có Attendance; lưu mặc định/ngoại lệ; đọc trên mobile; sửa mobile rồi thử gửi nháp desktop cũ; lưu lại khi dữ liệu mới; kiểm tra buổi đổi/hủy; kiểm tra thông báo thử, nhắc tự động, chốt trên mobile và gỡ nhắc; đăng xuất tài khoản khác không thấy nháp/nhắc của tài khoản trước.

## Kết quả kiểm tra local 30/10/2026

- Flutter analyzer: không có lỗi/cảnh báo.
- Toàn bộ desktop: 66 tests qua, gồm các ca kiểm tra bản nháp được dùng lại từ mobile.
- Backend chung: 103 tests qua, gồm transport OAuth mới, xung đột mobile/desktop, default Present/ngoại lệ, lịch đổi/hủy, 23:59:59 và 00:00, retry không ghi trùng.
- Windows release build với `--dart-define-from-file=config/local.json`: thành công.
- Chưa deploy backend hoặc thử ghi dữ liệu lớp thật; thông báo native cần bấm Thử thông báo Windows trên máy sử dụng.

Bản đã build: `C:/PRM/FAP-Attendance-Desktop-System/build/windows/x64/runner/Release/fap_attendance.exe`. Phân phối toàn bộ thư mục Release (bao gồm plugin thông báo, các DLL và data), không chỉ copy file exe.
