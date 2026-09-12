# Kết quả kiểm tra — 12/09/2026

Môi trường: Windows 11, Flutter 3.47.4 stable, Dart 3.13.3. SDK cục bộ trong `.tools/flutter`.

| Kiểm tra | Kết quả |
|---|---|
| flutter analyze --no-pub | PASS — No issues found |
| flutter test --no-pub | PASS — 9 tests |
| node --test backend/test/core.test.cjs | PASS — 5 tests |
| scripts/test_ocr.ps1 | PASS thực thi Windows OCR, JSON ok=true |
| flutter pub get | Package đã tải; bước symlink báo cần Developer Mode |
| Windows toolchain | Thiếu Visual Studio Desktop development with C++ |
| Google OAuth + Sheets trực tiếp | Chưa chạy: nhóm chưa có Client ID/Apps Script URL |
| flutter build windows --release --no-pub --dart-define=DEMO_MODE=true | Đã thử; dừng ở lỗi symlink, yêu cầu bật Developer Mode. Doctor cũng xác nhận thiếu Visual Studio C++ |
| GitHub Actions / PR / merge | Chưa chạy: chưa có remote |

Unit tests bao gồm domain spoofing, mapping khác giảng viên/học kỳ/trùng key, OCR trường thiếu, giờ sai, model roundtrip, HTTP redirect và JSON lỗi.

Widget tests xác minh form không lưu khi còn trường bắt buộc, nhập lịch hợp lệ xuất hiện trong danh sách, OCR parse không ghi repository, nút xác nhận chưa bật trước khi duyệt. Test phát hiện lỗi tràn nhãn thống kê; đã sửa bằng bố cục co giãn và chạy lại đạt.

Backend tests kiểm tra toàn batch trước mutation, retry theo ID, quyền sở hữu, giả mạo lecturerId, ID/lịch trùng, giờ/day/source, audience/expiry/email_verified/domain của Google claims. Đây là test dùng mock, không thay thế deployment integration test.

OCR smoke test trên ảnh sinh bằng System.Drawing thực tế trả:

```json
{"text":"FA26 PRM393 SEI 848 Mon Slot 1\nRoom AL-201","ok":true}
```

Windows OCR đã đọc sai SE1848 và bỏ sót giờ của ảnh mẫu. Không coi nhận diện là chính xác tuyệt đối; người dùng phải sửa/điền trường thiếu ở màn hình review. Chưa có ảnh FAP thực tế để đo độ chính xác hoặc hỗ trợ layout dạng lưới.
