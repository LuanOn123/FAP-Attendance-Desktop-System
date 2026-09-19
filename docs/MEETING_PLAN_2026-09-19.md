# Kế hoạch họp triển khai feedback 18/09

## Mục tiêu buổi họp

Chốt phạm vi, owner, API contract và tiêu chí hoàn thành cho từng feedback trước khi bắt đầu code. Không nhận task khi chưa có endpoint, dữ liệu vào/ra, trạng thái lỗi và người review.

## Lưu ý phạm vi

Tài liệu phân công gốc hiện có 4 người: Member 1–4. Kế hoạch này thêm **Member 5 – Backend/API** theo quy mô nhóm 5 người hiện tại. Feedback có hai mảng:

1. **Sports Center**: phòng, lớp, coach, membership, enrollment.
2. **FAP Attendance**: session, QR/extension check-in, live attendance, report và xuất Excel.

Hai mảng dùng mô hình dữ liệu khác nhau. Chỉ tích hợp endpoint Sports Center khi cả nhóm thống nhất dùng nó làm backend chính; không trộn `member` của Sports Center với `student` của FAP bằng ID tạm.

## Agenda 75 phút

| Thời lượng | Nội dung | Kết quả bắt buộc |
|---:|---|---|
| 0–10' | Chốt sản phẩm demo và backend chính | Một quyết định: dùng Sports Center API hay Google Sheets/API hiện tại của FAP |
| 10–25' | Đi qua feedback lớp, lịch, phòng, coach | Danh sách rule và API còn thiếu |
| 25–40' | Đi qua QR/extension và điểm danh | Contract giữa extension, backend và desktop |
| 40–55' | Chia owner theo bảng dưới | Mỗi task có branch, đầu ra và ngày demo |
| 55–65' | Chốt thứ tự tích hợp | API mock/contract, thứ tự merge, người review |
| 65–75' | Nêu blocker, rủi ro và action sau họp | Biên bản có owner và hạn xử lý |

## Phân công đề xuất

| Member | Owner | Việc phải chốt và triển khai | Đầu ra kiểm chứng được |
|---|---|---|---|
| 1 – Leader/Core | Luồng ứng dụng, model dùng chung, tích hợp | Quyết định backend; mapping `Schedule → Class → AttendanceSession`; navigation mở tab Điểm danh trước khi có lượt check-in mới; review/merge | API client/model chung, màn hình điều hướng, demo end-to-end |
| 2 – Class & data | Lớp, học viên, enrollment | Màn hình lớp; danh sách học viên; xử lý import và mapping; rule học viên có được đăng ký lịch trùng hay không; hiển thị capacity | Validation/UX và test case trùng lịch, hết chỗ, enrollment |
| 3 – QR & check-in | Session, QR động, extension/web check-in | Xác định payload extension gửi về; endpoint check-in; xác thực token/session/student; chống điểm danh trùng; status PRESENT/LATE/ABSENT | Extension/web scan gửi được event; desktop nhận được attendance record thật |
| 4 – Live attendance & report | Live list, chỉnh trạng thái, lịch sử, báo cáo, Excel | Refresh event; record mới nằm đầu danh sách với thời gian check-in; lịch sử/filter; export theo FAP Excel template | Tab điểm danh, report, file Excel xuất được từ dữ liệu attendance |
| 5 – Backend/API | API Sports Center, policy, dữ liệu và migration | Bổ sung/hoàn thiện endpoint còn thiếu; trả lỗi business `409`; tài liệu request/response; không để OAuth secret trong Git | Swagger cập nhật, test API, collection/Postman hoặc curl mẫu |

## Backlog đã đối chiếu Swagger

### Có API, cần xác nhận rule/UI

- Class/room/coach: `/classes`, `/rooms`, `POST /classes/{id}/coaches`, `DELETE /classes/{id}/coaches/{coachId}`.
- Lịch: `/class-schedules`; tạo/sửa có kiểm tra conflict phòng và coach.
- Enrollment: `POST /enrollments`, `GET /enrollments/my`, `DELETE /enrollments/{id}`.
- Membership: `/membership-plans`, `/subscriptions`, `/subscriptions/{id}/renew`, `/subscriptions/{id}/status`.
- Attendance cơ bản: `GET/POST /attendance`, `PATCH /attendance/{id}`.
- Báo cáo Sports Center: `/reports/*`.

### Chưa có API/rule rõ ràng — Member 5 phải chốt với team

1. Check-in từ QR/Bluetooth extension: cần endpoint ví dụ `POST /attendance/check-in` nhận `sessionId`, `rotatingToken`, `studentIdentity`, `checkedInAt`; server tự quyết định status.
2. Realtime tới desktop: chọn polling 2–5 giây hoặc WebSocket/SSE; desktop không nhận record bằng cách extension gọi thẳng local app.
3. Học viên đăng ký hai lịch bị trùng, capacity, điều kiện đối tượng: trả `409 Conflict` cùng lý do cụ thể.
4. Chính sách cancel: thời hạn hoàn tiền, transfer, trạng thái enrollment/payment và ai được thao tác.
5. Membership: mua đồng thời, nâng/hạ gói, quá hạn, gói active có được xóa hay không.
6. Source đăng ký: thêm `registrationSource` (`SELF`, `RECEPTION`) vào account/enrollment/subscription để phục vụ report marketing.
7. Xuất Excel: định nghĩa endpoint lấy dữ liệu report hoặc để desktop export trực tiếp; chuẩn hóa status mapping sang template FAP.

## Contract cần chốt trong họp

### Luồng QR/extension

```text
Desktop mở attendance session
  → Backend tạo session + rotating token
  → QR/extension quét token
  → Extension/Web gọi backend check-in
  → Backend validate và ghi attendance
  → Desktop polling/realtime lấy record mới
  → Tab Điểm danh đưa record đó lên đầu
  → Member 4 xuất report/Excel
```

Quyết định bắt buộc:

- Extension quét **QR động**, không tự giữ Google OAuth client secret.
- Backend là nguồn dữ liệu duy nhất để quyết định `PRESENT`, `LATE`, `ABSENT`.
- Check-in dùng `sessionId + token` và danh tính người học đã xác thực; không tin `memberId` do extension tự gửi.
- Một học viên chỉ có một record cho một session. Lần gọi lặp lại trả record cũ, không tạo dòng mới.

## Definition of Done chung

- Endpoint có Swagger, role/auth, request/response example và lỗi 400/401/403/404/409.
- UI hiển thị loading, empty, error và success.
- Có ít nhất một test case happy path và một business conflict.
- Không commit `.env`, `config/local.json`, OAuth client secret hoặc token.
- Merge qua PR vào `develop`; Member 1 review integration.

## Biên bản để điền ngay trong họp

| Quyết định | Chốt | Owner | Hạn | Ghi chú |
|---|---|---|---|---|
| Backend chính |  | Member 1 + 5 |  |  |
| Chính sách cancel/refund/transfer |  | Member 5 |  |  |
| Rule trùng lịch/capacity |  | Member 2 + 5 |  |  |
| Contract QR/extension |  | Member 3 + 5 |  |  |
| Cách realtime/polling |  | Member 3 + 4 + 5 |  |  |
| Export Excel |  | Member 4 |  |  |
| Ngày demo tích hợp |  | Member 1 |  |  |
