# Điểm danh theo slot và đồng bộ FAP

## Những thay đổi đã thực hiện

- Thời khóa biểu đánh dấu slot đang dạy theo UTC+7, gồm giờ bắt đầu và không gồm giờ kết thúc. Bấm slot đang dạy hoặc mục Điểm danh sẽ mở/resume phiên. Nếu nhiều lịch trùng giờ/học kỳ, chọn đúng lớp; không tự chọn ngẫu nhiên. Lịch hiện tại là lịch tuần; dữ liệu chưa có ngày bắt đầu/kết thúc học kỳ.
- QR độc lập với Secret Code. Mặc định tắt Secret Code; giảng viên mở bằng công tắc. Mã đổi mỗi 120 giây. Đổi mã thất bại sẽ ẩn QR và cho thử lại.
- Điểm danh lại tạo phiên mới, đánh dấu phiên cũ RESET. Bản ghi cũ còn trong Sheets để truy vết, không nhập vào báo cáo mới. QR cũ không sử dụng được.
- Lớp học có học kỳ, số sinh viên, các slot sắp tới và truy cập báo cáo theo ngày/slot. Ngày chưa có phiên không bị thay bằng phiên gần nhất hoặc gán cả lớp vắng.
- Sinh viên đăng nhập Google email trường. Backend kiểm tra chữ ký qua Google tokeninfo, audience, issuer, thời hạn, email đã xác minh, miền trường và danh sách lớp. Tên/MSSV lấy từ roster, không nhận từ biểu mẫu sinh viên. Checkbox “Bạn đang có mặt trong lớp này để điểm danh” bắt buộc cả ở giao diện và backend.
- Extension 1.3.0 tự lấy báo cáo mới từ desktop mỗi 30 giây trên trang điểm danh. Chỉ phiên CLOSED, đã chốt đủ roster mới được đồng bộ. Phải trùng môn/lớp/ngày/slot/giờ và toàn bộ MSSV. LATE ánh xạ có mặt; ABSENT ánh xạ vắng. Bấm Đồng bộ điểm danh để điền; extension không bấm Save. Báo cáo đổi kể từ lúc xem thì cần kiểm tra lại rồi bấm lần nữa.

## Cập nhật môi trường đang chạy

Các thay đổi local phải được cập nhật đồng bộ; không chỉ thay file Flutter.

1. Google Cloud → APIs & Services → Credentials: kiểm tra Client ID dùng cho trang sinh viên thuộc loại **Web application**. Client ID công khai đã được điền trong `web_hosting/public/config.js`. Không đặt Client Secret vào web/extension. Nếu ID hiện tại thuộc Desktop app, tạo Web application ID rồi thay `googleWebClientId` ở file này và property ở bước 2; giữ ID desktop riêng.
   Authorized JavaScript origins:
   - https://fap-attendance-cba45.web.app
   - https://fap-attendance-cba45.firebaseapp.com
   Callback dùng popup JavaScript, không cần tự tạo URL redirect cho trang này. Nếu OAuth đang Testing, bổ sung tài khoản thử được phép hoặc cấu hình audience trường phù hợp.
2. Apps Script: cập nhật toàn bộ `backend/apps_script/Code.gs`. Project Settings → Script Properties thêm `GOOGLE_WEB_CLIENT_ID` bằng đúng Web Client ID. Giữ `GOOGLE_CLIENT_ID` dùng xác thực desktop, `SPREADSHEET_ID` và `SCHOOL_DOMAINS` (`fpt.edu.vn,fe.edu.vn`). Bật Advanced Google Sheets service (đã dùng cho import roster và reset nguyên tử).
3. Deploy → Manage deployments → Edit → Version: New version. Web app Execute as: chủ script, access: Anyone; API tự xác thực Google ID token. Giữ deployment hiện có để URL `/exec` không đổi. Nếu tạo deployment khác, cập nhật đồng thời `config/local.json` của desktop và `web_hosting/public/config.js`.
4. Từ thư mục `web_hosting`, chạy `firebase deploy --only hosting --project fap-attendance-cba45` sau khi backend mới đã được triển khai. Không dùng project cũ có hậu tố f7850.
5. Build desktop: `flutter build windows --release --dart-define-from-file=config/local.json`. Đóng app cũ, chạy app mới rồi đăng nhập.
6. Chrome → Extensions → Developer mode → Reload extension tại thư mục `fap-attendance-extension`. Reload trang FAP. Với `attendance.html` local, bật Allow access to file URLs. Desktop và trình duyệt phải chạy trên cùng máy để dùng 127.0.0.1:8765.

## Kiểm tra thực tế sau triển khai

- Roster cần email Google trường đúng cho từng MSSV, không để trống. Tài khoản không thuộc lớp phải bị từ chối.
- Vào slot hiện tại, quét QR bằng điện thoại, đăng nhập: đúng tên, lớp, ngày, giờ; chưa tích checkbox không được gửi. Có thể điểm danh không nhập Secret Code.
- Bật Secret Code trên desktop, chọn nhập mã ở điện thoại để kiểm tra phương án thay thế. Sau khi đăng nhập quá lâu/mã đổi, quét mã mới hoặc nhập Secret Code hiện tại.
- Reset: số điểm danh về 0 ở phiên mới, mã cũ từ chối, bản ghi lượt trước vẫn ở Sheets.
- Kết thúc phiên và chốt danh sách vắng. Trên FAP thấy số có mặt/vắng khớp app; bấm Đồng bộ, kiểm tra rồi Save. Đổi ngày/slot/giờ sai phải bị chặn trước khi tick.

## Xác thực đã chạy local

Flutter widget/unit tests, Apps Script VM tests và JavaScript DOM tests kiểm tra các nhánh chính. Các test dùng mock cho Google login và Sheets; không thay thế việc quét điện thoại và xác nhận OAuth trên môi trường thật. Chưa tự triển khai backend hoặc hosting khi chưa truy cập được tài khoản Apps Script để cấu hình property và version.

Tài liệu Google: https://developers.google.com/identity/gsi/web/guides/get-google-api-clientid và https://developers.google.com/identity/gsi/web/guides/verify-google-id-token.
