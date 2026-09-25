# GOOGLE LOGIN AUDIT RESULT — 25/09/2026

## 1. Kết luận và giới hạn bằng chứng

**CONFIRMED: cấu hình local trỏ tới deployment cũ, khác web production tại thời điểm audit.**

| Nguồn trước khi sửa | Deployment | Kết quả POST `studentSessionInfo`, token rỗng |
|---|---|---|
| `config/local.json` và `web_hosting/public/config.js` | `AKfycbw81t…GwZxRw` | `Cần đăng nhập Google.` |
| `https://fap-attendance-cba45.web.app/config.js` | `AKfycby7XA…O4NLwA` | `Vui lòng đăng nhập email trường.` |

Cả hai trả HTTP 200 với JSON `ok:false`, không phải HTTP 401. Probe không dùng tài khoản thật và không ghi dữ liệu. Cả hai phản hồi có `Access-Control-Allow-Origin: *` với Origin của hosting. Web production đã được cập nhật từ lần điều tra trước; không tiếp tục coi production hiện tại là bản cũ.

Trong code repository, câu `Cần đăng nhập Google.` chỉ thuộc `authenticate_()` của giảng viên; nhánh sinh viên trả câu thứ hai. Kết quả xác nhận deployment cũ không thực hiện cùng luồng sinh viên với code hiện tại. Không có mã nguồn phiên bản deployment cũ để xác định chính xác revision của nó.

**Điểm từ chối chính xác của lỗi đã báo:** `Code.gs`, `authenticate_()`, điều kiện ghép trước truy vấn Lecturers:

```js
claims.aud !== cfg.audience ||
!['accounts.google.com', 'https://accounts.google.com'].includes(claims.iss) ||
Number(claims.exp) <= Date.now() / 1000 ||
!Number.isFinite(Number(claims.exp)) ||
![true, 'true'].includes(claims.email_verified) ||
parts.length !== 2 || !parts[0] || !cfg.domains.includes(parts[1])
```

Điều kiện này phát ra `Tài khoản Google không được phép truy cập.`. Nếu token sinh viên có audience web đi vào nhánh này trong khi server mong audience desktop, nó bị từ chối ở so sánh audience dù Google account hợp lệ. **HIGHLY LIKELY** cho lỗi lịch sử: nhầm nhánh dẫn đến sai audience. Chưa có claims từ tài khoản bị lỗi hoặc quyền đọc Script Properties để chứng minh nhánh con nào của điều kiện ghép đã thất bại trên server thật. Không yêu cầu gửi token để suy đoán.

**Không kết luận tất cả lỗi Google đã được giải quyết:** API mới nhận đúng action không chứng minh login thật thành công. Còn cần kiểm tra server audience, tài khoản, roster, enrollment và sheet Attendance. Không có phiên Google có quyền quản trị trong trình duyệt công cụ; chưa sửa Cloud Console, Script Properties hay deployment.

## 2. Danh mục file đã kiểm tra trước khi sửa

Đã tìm kiếm từ khóa Google/OAuth/OIDC/credential/token/client ID/JWT/login/authorization trong source, cấu hình, scripts, docs và CI; loại dependency vendored/generated/binary khỏi đánh giá mã ứng dụng. Đọc cấu hình local có che thông tin nhạy cảm; không in client secret/token.

| File | Vai trò |
|---|---|
| `lib/main.dart` | Khởi tạo OAuth, SheetService, AuthController; chuyển màn theo lecturer |
| `lib/core/app_config.dart` | Compile-time dart defines, domain và demo mode |
| `lib/features/auth/login_screen.dart` | Nút Google desktop |
| `lib/features/auth/auth_controller.dart` | login/restore → profile; kiểm tra domain lần nữa |
| `lib/services/google_oauth_service.dart` | Authorization code + PKCE, loopback, exchange và refresh |
| `lib/services/google_sheet_service.dart` | Gửi ID token trong JSON; xử lý redirect Apps Script |
| `lib/services/student_checkin_url.dart` | QR trỏ tới hosting sinh viên |
| `lib/features/attendance/session_qr_widget.dart`, `attendance_screen.dart` | Hiển thị QR, mở trang sinh viên |
| `lib/features/attendance/student_checkin_screen.dart` | Form cũ gửi token rỗng; không còn được route/import sử dụng |
| `web_hosting/public/index.html`, `checkin.js`, `config.js` | GIS, credential callback, API session/check-in |
| `backend/apps_script/Code.gs` | Dispatch, xác minh Google, lookup, ownership, enrollment |
| `backend/apps_script/appsscript.json` | Runtime V8, Sheets và external_request scopes của chủ script |
| `lib/repositories/attendance_repository.dart`, `schedule_repository.dart` | Action API và ánh xạ dữ liệu |
| `lib/services/integration_server.dart` | Bridge localhost extension; không phải endpoint Google Login |
| `lib/services/markbook_reader.dart`, `lib/models/roster.dart`, `fap_import_dto.dart` | Đọc/nhập email, MSSV và roster |
| `config/local.json`, `scripts/run_local.ps1` | Cấu hình thực tế khi build/run desktop |
| `web_hosting/firebase.json`, `.firebaserc` | Hosting, rewrite, no-store, COOP popup |
| `.github/workflows/check.yml` | Checks và build DEMO, không triển khai production |
| `README.md`, `docs/ATTENDANCE_V2.md`, `API_CONTRACT.md`, `MEMBER1_HANDOVER.md`, `ROSTER_IMPORT.md` | Đối chiếu ý định/config và hướng dẫn |
| `backend/test/*`, `web_hosting/test/*`, `test/google_sheet_service_test.dart`, test attendance | Xác minh hành vi và lỗi |

Không tìm thấy Spring Security, Nest middleware, application JWT issuer, cấu hình Render/Vercel/Docker hay chuỗi `.env` override trong ứng dụng này. Các file Windows runner là khởi tạo cửa sổ, không xác minh Google.

## 3. Hai call flow thực tế

### Sinh viên

```text
SessionQrDisplayWidget → studentCheckinUrl() → hosting /checkin
index.html loads GIS + config.js + checkin.js
google.accounts.id.initialize(client_id=FAP_CONFIG.googleWebClientId, callback=login)
Google → response.credential (Google ID token, không phải access token/code)
login() → request('studentSessionInfo') → POST text/plain JSON {idToken, sessionId}
doPost() → handleStudentSession_() → studentContext_()
authenticateStudent_(): Google tokeninfo HTTP 200 → aud/iss/exp/email_verified/domain/hd
Students.schoolEmail: đúng một dòng → session OPEN → Enrollments → Classes
response {student, session} → hiện thông tin lớp
studentCheckIn → xác minh lại identity/enrollment → presence + QR/Secret → Attendance
```

Không redirect URI riêng trong GIS callback popup; không có app JWT, cookie session hoặc Bearer header. Credential giữ trong bộ nhớ trang, gửi lại cho hai action; refresh trang/đổi tài khoản cần đăng nhập lại. CSRF double-submit cookie cho GIS POST redirect không phải flow hiện dùng. Mọi write check-in vẫn kiểm tra Google identity, session và mã điểm danh.

### Giảng viên desktop

```text
LoginScreen → AuthController.login() → GoogleOAuthService.login()
system browser OAuth /auth: response_type=code, scope=openid email profile
state + PKCE S256, redirect http://127.0.0.1:<ephemeral-port>
callback kiểm tra path/state → _exchange() POST /token → Google id_token
AuthController._profile() → GoogleSheetService.request('profile')
doPost() → handle_() → authenticate_() → Lecturers.email đúng một dòng
AuthController kiểm tra AppConfig.domainList → lưu lecturer → ScheduleScreen
```

Desktop không gửi access token thay ID token. Refresh token chỉ được lưu FlutterSecureStorage nếu nhớ phiên; ID token ở memory. Mỗi request gọi `oauth.idToken()`, có refresh khi hết hạn. Chưa xác minh binary nào người dùng đang mở; bản build mới cuối audit sử dụng `config/local.json` đã sửa.

## 4. Client IDs và cấu hình

| Vị trí | ID đã che / nguồn | Môi trường, mục đích |
|---|---|---|
| `config/local.json: GOOGLE_CLIENT_ID` | `673290516613-9a292oqq…` (A) | Desktop authorization code / PKCE |
| `AppConfig.clientId` | compile-time `GOOGLE_CLIENT_ID`, mặc định rỗng | Desktop; không đọc JSON động lúc chạy |
| `web_hosting/public/config.js` | `673290516613-h1o52ha4…` (B) | GIS web sinh viên |
| Production hosting `config.js` | B, so sánh toàn bộ khớp local | Web đang phục vụ |
| Apps Script `config_().audience` | Script Property `GOOGLE_CLIENT_ID` — chưa đọc được giá trị | Phải là A |
| Apps Script `config_().webAudience` | Script Property `GOOGLE_WEB_CLIENT_ID` — chưa đọc được giá trị | Phải là B, không fallback sang A |
| CI Windows artifact | `DEMO_MODE=true`, không truyền ID | Demo, không dùng kiểm chứng production login |

A khác B là đúng thiết kế. Cùng prefix số chưa đủ chứng minh loại OAuth client và cài đặt Cloud Console. Không thay cả hai thành một ID. Không phát hiện thêm ID thực khác trong các source/config/docs đã tìm; test dùng ID giả `web-client`, `desktop-client`, `client`.

`GOOGLE_CLIENT_SECRET` chỉ được desktop dùng ở token exchange; không có trong web hay extension. Không in giá trị. Desktop là public installed client: không coi secret nhúng binary là bí mật server.

`SCHOOL_DOMAINS` mặc định `fpt.edu.vn,fe.edu.vn` ở Flutter và Apps Script; local khớp mặc định. Script Properties thật có thể override, chưa xác minh. `APPS_SCRIPT_URL` không có fallback URL trong Dart; thiếu cấu hình thì login bị vô hiệu hóa. Web URL là giá trị tĩnh trong config.js. Không có VITE/REACT_APP/NEXT_PUBLIC/JWT_SECRET hoặc cơ chế .env chồng nhau trong code.

## 5. Chính sách identity, role, status và quyền

- Google tokeninfo xác minh token upstream, code kiểm tra thêm issuer, audience, expiry hữu hạn, verified email. `email_verified` chấp nhận cả boolean true và chuỗi "true"; false/null/missing bị chặn. Đây không phải lỗi chuyển kiểu.
- Student bắt buộc `hd` trong allowlist và domain email trong allowlist. `student.fpt.edu.vn` không có trong cấu hình repo; không tự thêm. Gmail cá nhân bị chặn theo chính sách email trường. Không bỏ `hd` vì chưa có bằng chứng chính sách trường cho phép tài khoản ngoài Workspace.
- Lookup bằng email trim/lowercase, không dùng `sub` hoặc suy MSSV từ tên email. MSSV/tên lấy từ roster. Account phải được nhập trước; không auto-register.
- Import cho phép email rỗng. `importRoster_()` giữ nguyên student đã tồn tại, không bổ sung email mới vào student cũ. **Rủi ro đã xác nhận từ code**, nhưng chưa chứng minh dữ liệu thật mắc lỗi này: sinh viên có MSSV vẫn có thể thiếu `schoolEmail` và bị từ chối. Chưa tự sửa dữ liệu hoặc chính sách import.
- Không cột role: quyền giảng viên từ Lecturers, quyền sinh viên từ Students + Enrollments. Không có lỗi khác casing STUDENT/ROLE_STUDENT.
- Không có trạng thái account ACTIVE/INACTIVE/locked/deleted. `Sessions.status` là trạng thái buổi học, không phải account. Nếu nghiệp vụ cần khóa tài khoản, đó là yêu cầu bổ sung chưa được triển khai, không giả báo TC05 đã đạt.
- `doPost` phân tuyến student trước `handle_` giảng viên. Không middleware yêu cầu app JWT trước Google login. API deployment phải cho request tới doPost; quyền ứng dụng được kiểm tra trong server.
- Ownership lecturerId lấy từ Google lookup, không tin client. Student cần Enrollment đúng class của session. Không nới quyền trong audit.
- Bridge `integration_server.dart` chỉ bind loopback và kiểm tra Origin extension; CORS bridge không điều khiển website sinh viên → Apps Script.
- `Sai cấu trúc cột: Attendance` nằm tại `read_()` trước đọc/ghi bảng: so sánh chính xác headers. Không phải OAuth rejection. Không có row header thật để sửa an toàn; không đổi schema/dữ liệu trong audit này.

## 6. Bảng truy nguyên thông báo

| Thông báo / nguồn | Điều kiện |
|---|---|
| `Cần đăng nhập Google.` — `Code.gs/authenticate_` | Token không phải string hoặc độ dài ngoài 20–10000; nhánh giảng viên |
| `Tài khoản Google không được phép truy cập.` — `authenticate_` | Một điều kiện aud/iss/exp/verified/domain thất bại; trước lookup |
| `Email chưa có trong Lecturers...` — `authenticate_` | Lookup lecturer email không đúng một dòng |
| `Máy chủ chưa cấu hình GOOGLE_WEB_CLIENT_ID.` — `authenticateStudent_` | Thiếu audience web |
| `Vui lòng đăng nhập email trường.` — `authenticateStudent_` | Token rỗng/sai loại/độ dài |
| `Phiên Google không hợp lệ. Đăng nhập lại.` — cả hai verifier | Google tokeninfo không trả 200 |
| `Cấu hình đăng nhập sinh viên không khớp...` — `authenticateStudent_` | aud khác webAudience |
| `Chỉ tài khoản Google email trường đã xác minh...` — `authenticateStudent_` | iss/exp/verified/domain/hd thất bại |
| `Email trường chưa có... hoặc đang bị trùng` — `authenticateStudent_` | Lookup Students không đúng một dòng |
| `Email của bạn không thuộc danh sách lớp...` — `studentContext_` | Không có Enrollment cho class/session |
| `Phiên đã kết thúc hoặc được reset...` — `studentContext_` | Session không OPEN |
| `Sai cấu trúc cột: Attendance` — `read_` | Header array khác SCHEMA.Attendance |
| `Email không thuộc domain trường đã cấu hình.` — `AuthController._profile` | Server profile qua được nhưng domain Flutter không cho phép |
| `Không thể cấp/gia hạn phiên Google...` — `GoogleOAuthService._exchange` | Token exchange HTTP !=200 |
| `Load failed`/`Failed to fetch` — browser fetch | Transport/CORS/redirect/mạng; chưa có JSON auth rejection |
| `API đang dùng luồng đăng nhập giảng viên...` — web `request()` | Nhận một trong hai thông báo lecturer cũ; thông báo chẩn đoán, không thay xác minh |

## 7. Xếp hạng 20 khả năng được yêu cầu

| # | Khả năng | Kết luận |
|---|---|---|
| 1–2 | Testing / thiếu Test User | POSSIBLE nếu scopes khác; chưa đọc Console. Basic identity có ngoại lệ, không mặc định đổ lỗi |
| 3 | Internal nhưng account ngoài tổ chức | POSSIBLE, cần Console/admin |
| 4 | Sai loại/value Client ID | POSSIBLE phía Console; web live khớp repo |
| 5–6 | Frontend/backend aud mismatch | HIGHLY LIKELY với API cũ; unit test tái hiện web token bị lecturer verifier chặn; properties live chưa biết |
| 7 | Sai Authorized JavaScript Origin | POSSIBLE, chưa đọc Console; không giải thích JSON lecturer rejection sau credential thành công |
| 8 | Sai redirect | POSSIBLE cho desktop; web callback popup không dùng login_uri redirect |
| 9 | Domain sai | POSSIBLE trên tài khoản thật; repo/local nhất quán |
| 10 | hd bị yêu cầu sai | NOT A PROBLEM đối với chính sách Workspace trường; account thật chưa kiểm chứng |
| 11 | email_verified string/boolean | NOT A PROBLEM, test cả hai dạng |
| 12 | Thiếu student/email/enrollment | POSSIBLE; code yêu cầu pre-registration, import có thể giữ email rỗng |
| 13–14 | Role sai / inactive | NOT APPLICABLE: không có những trường này |
| 15 | Endpoint bị auth middleware chặn | CONFIRMED nhầm nhánh trên API cũ; NOT A PROBLEM ở dispatch source hiện tại |
| 16 | CORS | POSSIBLE cho lỗi tải riêng; HTTP probe có ACAO *, chưa kiểm tra điện thoại |
| 17 | Không lưu app JWT | NOT APPLICABLE: không phát hành app JWT |
| 18 | Cấu hình production/local cũ | CONFIRMED: hai deployment khác nhau; đã đồng bộ local |
| 19 | .env override | NOT A PROBLEM: không có cơ chế này; Dart dùng compile-time defines |
| 20 | Credential cũ hardcode | CONFIRMED endpoint cũ; không chứng minh OAuth ID cũ/sai |

## 8. Cloud Console / Script Properties cần kiểm tra thủ công

1. Web client B có loại Web application; origins có `https://fap-attendance-cba45.web.app` và `https://fap-attendance-cba45.firebaseapp.com` nếu dùng host thứ hai. Localhost chỉ thêm đúng origin/port nếu thực sự test tại đó.
2. Desktop client A có loại Desktop app, phù hợp loopback động. Không áp cấu hình redirect web vào desktop.
3. Internal/External phù hợp tổ chức của sinh viên. Kiểm tra chính sách Workspace admin và lỗi cụ thể Google hiển thị.
4. Kiểm tra scopes và trạng thái Testing/Production, verification. **Ngoại lệ:** chỉ các scopes identity cơ bản `openid`, `email`, `profile` không mặc định yêu cầu user nằm trong test allowlist theo tài liệu Google. Desktop đang yêu cầu đúng bộ này; Apps Script spreadsheet scopes là quyền chạy server của chủ script, không phải scope GIS của sinh viên.
5. `GOOGLE_CLIENT_ID=A`, `GOOGLE_WEB_CLIENT_ID=B`, `SCHOOL_DOMAINS` đúng miền thực tế, `SPREADSHEET_ID` đúng bảng. Không có cơ sở xác minh giá trị live chỉ qua token rỗng.
6. Manage deployments: URL mới đang dùng chạy phiên bản chứa student actions; Execute as chủ script và quyền truy cập cho phép browser gọi doPost. Giữ xác thực Google trong code.
7. Students.schoolEmail có đúng email thực, không rỗng/trùng; Enrollments có studentId/classId; Lecturers dành cho tài khoản desktop. Xác minh header Attendance độc lập.

Nguồn chính thức đã đối chiếu:

- [OAuth app state: ngoại lệ basic identity scopes](https://developers.google.com/identity/protocols/oauth2/production-readiness/overview)
- [Xác minh ID token và hd](https://developers.google.com/identity/gsi/web/guides/verify-google-id-token)
- [GIS setup và client/origins](https://developers.google.com/identity/gsi/web/guides/get-google-api-clientid)
- [GIS credential callback](https://developers.google.com/identity/gsi/web/reference/js-reference)

Google khuyến nghị verifier library; tokeninfo phù hợp chẩn đoán và có phụ thuộc mạng/quota. Không viết lại verifier trong audit cấu hình này.

## 9. Sửa đổi tối thiểu

- Chỉ thay `APPS_SCRIPT_URL` trong local JSON (file ignored) và `appsScriptUrl` trong web config sang endpoint hiện được production hosting công bố. Giữ nguyên hai Client IDs và mọi secret/domain.
- Thêm `backend/test/auth.test.cjs`: kiểm thử doPost thật với Google/Sheets giả lập, student/teacher dispatch, audience, issuer, expiry, email_verified, hd, missing/duplicate user, enrollment, session và invalid token.
- CI chạy toàn bộ backend tests thay vì chỉ core.test.cjs để bảo vệ nhánh student login.
- Không thêm log chứa credential, không thêm quyền, không thay role/domain/hd checks, không phát hành JWT mới, không sửa dữ liệu Sheets.
- Các thay đổi report/attendance/web error handling đã tồn tại trước audit không được tính là sửa mới của audit này.

## 10. Test matrix và cách xác nhận

Kết quả chạy audit: 55 JavaScript tests PASS (gồm 16 auth tests mới), 45 Flutter tests PASS; `flutter analyze --no-pub` không có lỗi/cảnh báo. Các test identity dùng mock, không thay thế kiểm chứng tài khoản Google thật.

Build Windows release với `config/local.json` đã đồng bộ endpoint thành công: `build/windows/x64/runner/Release/fap_attendance.exe`.

| Case | Kết quả / giới hạn |
|---|---|
| TC01 allowed student | PASS unit dispatch + web DOM với Google mock; login account thật chưa chạy |
| TC02 ngoài domain | PASS reject |
| TC03 Google hợp lệ, không có Student | PASS reject theo pre-registration |
| TC04 ACTIVE student | N/A field ACTIVE; student hợp lệ không có status được test thành công |
| TC05 INACTIVE student | N/A: chưa có policy account status; không báo reject giả |
| TC06 wrong audience | PASS reject |
| TC07 expired Google token | PASS reject |
| TC08 invalid token | PASS reject khi Google trả non-200 hoặc input token rỗng |
| TC09 tạo app JWT | N/A; dùng Google ID token, không phát hành app JWT |
| TC10 protected endpoint | PASS student web token bị lecturer profile từ chối; không có protected endpoint dùng app JWT |
| TC11 production expectations | Web Client ID local/live bằng nhau; endpoint sau sửa bằng nhau; server audience và Google account thật còn cần kiểm tra |
| TC12 không log secret/token | Không thêm logging; kiểm tra source auth không có print/console/Logger credential. Không kiểm chứng được logging ngoài repository/hạ tầng Google |

Chạy local:

```powershell
node --test backend/test/*.test.cjs web_hosting/test/*.test.cjs fap-attendance-extension/test/*.test.cjs
flutter analyze --no-pub
flutter test --no-pub
flutter build windows --release --no-pub --dart-define-from-file=config/local.json
```

DOM tests dùng jsdom từ `.tools/extension-tests/node_modules` hiện có. Đóng bản app cũ rồi mở bản Release vừa build để áp dụng compile-time URL. Không dùng artifact CI demo để kiểm chứng Google login.

Production: dùng đúng student đã có email/enrollment, mở phiên mới trên desktop, quét QR, đăng nhập Google và kiểm tra đúng tên/lớp. Thử tài khoản ngoài lớp/ngoài domain phải bị chặn. Nếu lỗi, ghi thông báo và action thất bại; không gửi token. Với Load failed, kiểm tra Network trên thiết bị: status, CORS, redirect đăng nhập hoặc response HTML; không copy request chứa idToken. Google thành công nhưng API từ chối phải được tách khỏi Google consent/origin error.

Không có xác nhận đăng nhập thật end-to-end cho đến khi hoàn thành bước production trên tài khoản có quyền. Việc sửa cấu hình không chứng minh dữ liệu Attendance đã đúng cấu trúc.
