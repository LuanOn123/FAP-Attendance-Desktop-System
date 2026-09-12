# Bàn giao Member 1

## Đối chiếu nhiệm vụ

| Mục | Mã nguồn / kết quả | Trạng thái |
|---|---|---|
| A Setup | Windows runner, core/theme, auth gate, NavigationRail | Đã viết, analyzer/widget test đạt |
| B Auth | GoogleOAuthService, AuthController, login/profile/logout | Đã viết; cần test Google thật sau cấu hình |
| C OCR | OcrService, assets/ocr_windows.ps1, ScheduleParser | OCR thật chạy được trên ảnh mẫu; parser có test |
| D Review | OcrReviewScreen, checkbox xác nhận, batch validation | Đã viết, test không tự lưu đạt |
| E Manual | ScheduleEditor, ScheduleScreen, ScheduleRepository | Đã viết, test nhập tay/validation đạt |
| F Mapping | ClassMappingService | Test normalized/owner/ambiguous đạt |
| G Sheets | GoogleSheetService và Code.gs | Test HTTP/backend đạt; cần deploy thật |
| H Integration | module contracts, CI, demo script | Chuẩn bị xong; chưa tích hợp member 2–4/PR/merge/build exe |

## Demo phần Member 1 (5–7 phút)

1. Mở bản demo bằng `scripts/run_demo.ps1` sau khi cài đủ build tools.
2. Giải thích nhãn DEMO; dữ liệu mẫu không phải Google Login thật.
3. Xem lịch PRM393–SE1848 và trạng thái đã ghép lớp.
4. Thêm lịch SWE201–SE1901, nhập thiếu hoặc giờ kết thúc trước bắt đầu để thể hiện validation.
5. Nhập ảnh OCR, phóng ảnh gốc, so sánh raw text; chỉ ra nhận sai ký tự/thiếu giờ.
6. Điền học kỳ/tên môn/các trường thiếu, bỏ dòng nhận sai; tích xác nhận rồi lưu.
7. Mở hồ sơ giảng viên và các điểm chờ tích hợp module khác.
8. Sau khi cấu hình Google thật, demo thêm domain không hợp lệ, email chưa đăng ký, đăng nhập hợp lệ, nhớ phiên, logout; xác minh dữ liệu và SyncLogs trong Sheets.

## Trước khi nộp bài

- [ ] Xác nhận domain email giảng viên với nhóm/trường.
- [ ] Tạo Desktop OAuth client; consent/test users; điền local.json.
- [ ] Tạo Sheets, Apps Script, setupSheets, thêm Lecturers và Classes mẫu.
- [ ] Deploy Apps Script và kiểm tra đọc/ghi bằng tài khoản thật.
- [ ] Bật Developer Mode, cài Visual Studio C++ và build Windows release.
- [ ] Chạy OCR trên ảnh thời khóa biểu thật; tinh chỉnh parser nếu cần.
- [ ] Ghép với module import/session/live/report của member 2/3/4.
- [ ] Tạo repo/remote, feature branch, commit, push, PR và merge develop theo quy trình nhóm.
- [ ] Test toàn bộ final demo: login → schedule → import lớp → session → check-in → report → export.

Không tạo PR/merge giả khi chưa có remote hoặc code của các thành viên khác. Chưa có thông tin Google Cloud tại thời điểm bàn giao.
