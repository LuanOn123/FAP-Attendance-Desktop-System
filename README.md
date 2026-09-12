# FAP Attendance Desktop — Member 1

Flutter Windows / Dart, theo phần **Leader / Auth / OCR Schedule / Core Integration** của tài liệu phân công PRM393.
Không sử dụng FAP API, không đăng nhập FAP và không lưu mật khẩu Google/FAP.

## Đã triển khai

- Flutter Windows runner, Material 3 theme, màn hình đăng nhập và điều hướng module.
- Google OAuth bằng trình duyệt hệ thống, loopback IPv4, PKCE và state ngẫu nhiên.
- Kiểm tra domain trường và tra cứu Lecturers ở backend; hồ sơ, đăng xuất, nhớ/gia hạn phiên bằng Windows secure storage.
- Chọn ảnh PNG/JPEG/BMP, OCR local bằng Windows.Media.Ocr qua Windows PowerShell 5.1.
- ScheduleParser; màn hình ảnh gốc + raw text + sửa từng dòng; chỉ lưu sau khi tích xác nhận.
- Nhập tay, danh sách/tìm kiếm, chỉnh sửa/xóa lịch; validation cả Flutter và server.
- Ghép lớp theo `Semester + SubjectCode + ClassCode`, chuẩn hóa hoa/thường/khoảng trắng; lọc lecturer; báo thiếu/trùng lớp.
- GoogleSheetService: `getRows`, `appendRow`, `updateRow`, `deleteRow`, `batchUpdate`.
- Apps Script: kiểm tra Google token, ownership, lock chống ghi đồng thời, batch atomic bằng Sheets API, SyncLogs.
- Demo offline, unit/widget/backend tests và workflow Windows CI.

**Chưa phải bản tích hợp toàn nhóm:** menu lớp học, điểm danh và báo cáo là điểm chờ module của member 2/3/4. Google thật cần tài khoản/cấu hình của nhóm. Chưa build được `.exe` trên máy hiện tại do thiếu Visual Studio C++ và Developer Mode. Xem `docs/TEST_REPORT.md`.

## 1. Chuẩn bị máy Windows

1. Cài Flutter stable và Git. Máy hiện tại đã có SDK cục bộ tại `.tools/flutter` (3.47.4, Dart 3.13.3), được bỏ qua bởi Git.
2. Cài **Visual Studio 2022**, workload **Desktop development with C++**, gồm Windows SDK và CMake. Visual Studio Code không thay thế được thành phần này.
3. Bật **Developer Mode** trong Windows Settings để Flutter tạo symlink cho plugin.
4. OCR cần Windows PowerShell 5.1 và language pack hỗ trợ OCR trong Windows Settings. Không cần Tesseract hoặc cloud OCR.
5. Mở PowerShell tại thư mục dự án:

```powershell
$env:PATH = "$PWD\.tools\flutter\bin;$env:PATH"
$env:PUB_CACHE = "$PWD\.tools\pub-cache"
flutter doctor -v
flutter pub get
```

Nếu dùng Flutter đã cài ở máy khác, bỏ hai lệnh thiết lập đường dẫn `.tools`.

## 2. Chạy demo khi chưa có tài khoản Google Cloud

```powershell
flutter run -d windows --dart-define=DEMO_MODE=true
```

Hoặc chạy `scripts/run_demo.ps1`. Chọn **Vào bản demo ngoại tuyến** ở màn hình đăng nhập.
Demo có một giảng viên, một lớp, một lịch mẫu. Dữ liệu demo nằm trong bộ nhớ, mất khi thoát ứng dụng; Google Login bị tắt trong demo. Không có cơ chế tự chuyển sang demo khi đăng nhập thật thất bại.

Thử nhập ảnh `test/fixtures/schedule_ocr.png`, hoặc dán dòng sau vào ô raw text rồi bấm **Phân tích lại văn bản**:

```text
FA26 PRM393 SE1848 Thu 2 Slot 1 07:30-09:00 Room AL-201
FA26 SWE201 SE1901 Wed Slot 2 09:15-10:45 Room BE-301
```

OCR không biết tên môn từ mã môn; bổ sung tên môn và các ô còn trống. `dayOfWeek` dùng ISO: 1 = Thứ 2, …, 7 = Chủ nhật. Slot chấp nhận 1–12; giờ bắt đầu/kết thúc phải nhập rõ ràng theo HH:mm.

## 3. Tạo Google OAuth từ đầu

1. Vào [Google Cloud Console](https://console.cloud.google.com/), tạo project cho nhóm.
2. Cấu hình Google Auth Platform / consent screen: tên ứng dụng, email hỗ trợ. Nếu dùng External + Testing, thêm email giảng viên vào Test users. Nếu trường giới hạn ứng dụng bên ngoài, cần quản trị Workspace cho phép.
3. Tạo OAuth client với loại **Desktop app**. Không chọn Web application cho Flutter Windows.
4. Ghi lại Client ID; nếu cấu hình Desktop client cung cấp client secret thì điền vào file cấu hình cục bộ. Desktop client không thể giữ một secret bí mật tuyệt đối; server không dùng secret đó để quyết định quyền người dùng.
5. Ứng dụng chỉ yêu cầu `openid email profile`, mở trình duyệt và nhận callback ở `http://127.0.0.1:<random-port>`. Không sử dụng embedded webview hoặc OOB flow.

## 4. Tạo Sheets và Apps Script

1. Tạo Google Spreadsheet riêng của nhóm. Không chia sẻ công khai file chứa dữ liệu sinh viên.
2. Mở Extensions → Apps Script. Dán `backend/apps_script/Code.gs` vào project.
3. Bật hiển thị manifest trong Project Settings; thay `appsscript.json` bằng file cùng tên trong `backend/apps_script`.
4. Trong Services, bảo đảm **Google Sheets API v4** đã bật. Nếu dùng Cloud project riêng cho Apps Script, bật Google Sheets API trong Cloud project đó.
5. Thêm Script Properties:

| Property | Giá trị |
|---|---|
| `SPREADSHEET_ID` | Phần ID giữa `/d/` và `/edit` của URL spreadsheet |
| `GOOGLE_CLIENT_ID` | Cùng Desktop Client ID dùng trong Flutter |
| `SCHOOL_DOMAINS` | Danh sách domain thực tế của trường, ví dụ `fpt.edu.vn,fe.edu.vn` |

6. Chạy thủ công `setupSheets()` từ editor và cấp quyền cho tài khoản chủ sở hữu. Hàm tạo đủ 8 sheet với header theo tài liệu; không ghi đè sheet có header khác.
7. Trong sheet **Lecturers**, thêm một dòng bằng email Google thật của giảng viên:

```text
lecturerId | lecturerCode | fullName       | email                  | department
lec-001    | GV001        | Nguyen Van A   | EMAIL_TRUONG_CUA_BAN   | CNTT
```

8. Trong **Classes**, có thể thêm dữ liệu mẫu để kiểm tra mapping (email không dùng trong khóa):

```text
classId | semester | subjectCode | subjectName        | classCode | lecturerId
cls-001 | FA26     | PRM393      | Mobile Programming | SE1848    | lec-001
```

9. Deploy → New deployment → Web app: **Execute as: Me**, quyền truy cập **Anyone** nếu chính sách trường cho phép. Endpoint tự kiểm tra Google ID token trên mọi request, không tin email/lecturerId gửi từ client. Nếu tài khoản không cho phép deployment này, cần quản trị cho phép hoặc đổi kiến trúc backend trước khi sử dụng.
10. Lưu URL deployment kết thúc bằng `/exec`. Khi sửa backend, tạo version mới và cập nhật deployment; không dùng `/dev` trong ứng dụng.

## 5. Kết nối ứng dụng thật

```powershell
Copy-Item config/example.json config/local.json
```

Điền Client ID, client secret (nếu cần), Apps Script URL và domain vào `config/local.json`. File đã được `.gitignore` bỏ qua; không điền mật khẩu Google/FAP. Để `DEMO_MODE` là `false`.

```powershell
flutter run -d windows --dart-define-from-file=config/local.json
```

Hoặc chạy `powershell -ExecutionPolicy Bypass -File scripts/run_local.ps1`; script kiểm tra file rỗng, JSON và khóa bắt buộc trước khi mở Flutter. Với VS Code, chọn cấu hình **FAP Attendance - Local Google config** rồi F5.

Ứng dụng đọc `String.fromEnvironment` tại thời điểm biên dịch, không tự đọc file JSON lúc mở exe. Phải lưu `config/local.json` xuống ổ đĩa, dừng ứng dụng rồi chạy lại bằng lệnh có `--dart-define-from-file`. Hot reload không cập nhật những giá trị này. Nếu mở một exe đã build trước khi cấu hình, cần build lại với cùng tham số.

Giảng viên cần đồng thời có email Google đã xác minh, domain hợp lệ và đúng một hồ sơ trong Lecturers. Danh sách domain trong Flutter và Script Properties phải giống nhau. Domain mặc định chỉ là giá trị mẫu, trưởng nhóm cần xác nhận với tài khoản thực tế.

## 6. Kiểm tra và build

```powershell
flutter analyze --no-pub
flutter test --no-pub
node --test backend/test/core.test.cjs
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/test_ocr.ps1
flutter build windows --release --dart-define-from-file=config/local.json
```

Node 22+ chỉ cần cho test backend. `scripts/check.ps1` chạy pub get/analyzer/test cả Flutter và backend. Test OCR tạo ảnh mẫu rồi đọc bằng Windows OCR thật; chất lượng nhận diện phụ thuộc font/ảnh/language pack.

Khi build thành công, phân phối **toàn bộ thư mục** `build/windows/x64/runner/Release`, bao gồm `data` và DLL, không chỉ file exe. Workflow `.github/workflows/check.yml` build bản **DEMO** trên GitHub Actions khi repo được push; workflow chưa chạy trong phiên làm việc này.

## 7. Kiến trúc và bàn giao

```text
lib/
  core/           cấu hình, lỗi, theme
  models/         Lecturer, Schedule, ClassModel
  services/       OAuth, Sheets HTTP, OCR, parser, mapping
  repositories/   ScheduleRepository, Sheets adapter, demo adapter
  features/
    auth/         login, auth controller
    schedule/     danh sách, form, OCR review
    classes/      hướng dẫn tích hợp member 2
    attendance/   hướng dẫn tích hợp member 3
    reports/      hướng dẫn tích hợp member 4
  shared/         giao diện module chờ tích hợp
  main.dart       composition root + auth gate
backend/          Apps Script và test Node
docs/             API contract, checklist bàn giao, kết quả kiểm tra
```

Xem `docs/API_CONTRACT.md` cho giao thức và giới hạn quyền; `docs/MEMBER1_HANDOVER.md` cho bài demo và checklist. Repo chưa có remote, nên chưa có push/PR/merge; không coi các bước đó đã hoàn tất.

## Giới hạn cần biết

- Parser đọc theo dòng, hỗ trợ một số mẫu mã môn/lớp/thứ/slot/giờ/phòng. Ảnh thời khóa biểu dạng lưới FAP phức tạp chưa có mẫu thật để tinh chỉnh; nên crop theo dòng, sửa raw text hoặc nhập tay. Không tự suy diễn slot → giờ.
- Google `tokeninfo` được dùng để xác minh token trong MVP Apps Script. Phải kiểm tra tải/quota trước khi mở rộng; backend triển khai lớn nên dùng thư viện xác minh JWT chính thức trong môi trường server phù hợp.
- Lưu batch tối đa 100 lịch; update theo ID là upsert, retry giữ nguyên ID không tạo thêm dòng. Chỉnh sửa đồng thời cùng lịch hiện theo last-write-wins, chưa có version conflict UI.
- Core endpoint hiện chỉ đọc Lecturers/Schedules/Classes của giảng viên và ghi Schedules. Các sheet khác cần handler và quyền riêng khi tích hợp module tương ứng.
- Đăng xuất xóa phiên ở ứng dụng; không đăng xuất tài khoản khỏi trình duyệt Google. Có thể thu hồi quyền ứng dụng tại Google Account khi cần.

## Tài liệu kỹ thuật đã đối chiếu

- [Flutter Windows setup](https://docs.flutter.dev/platform-integration/windows/setup)
- [Google OAuth desktop / PKCE / loopback](https://developers.google.com/identity/protocols/oauth2/native-app)
- [Apps Script Web Apps](https://developers.google.com/apps-script/guides/web)
- [Apps Script ContentService](https://developers.google.com/apps-script/reference/content/content-service)
- [Windows OCR API](https://learn.microsoft.com/en-us/uwp/api/windows.media.ocr.ocrengine)
