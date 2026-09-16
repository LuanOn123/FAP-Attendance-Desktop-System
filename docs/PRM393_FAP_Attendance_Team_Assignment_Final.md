# PHÂN CÔNG CÔNG VIỆC DỰ ÁN PRM393

## 1. Thông tin dự án

- **Tên dự án:** FAP Attendance Desktop System
- **Môn học:** PRM393
- **Nền tảng:** Flutter Desktop
- **Ngôn ngữ:** Dart
- **Database:** Google Sheets
- **Đăng nhập:** Google OAuth bằng email trường FPT
- **Số thành viên:** 4
- **Nguyên tắc:** Không sử dụng API FAP, không tự động đăng nhập FAP, không lưu mật khẩu FAP.

## 2. Mục tiêu hệ thống

Ứng dụng Desktop hỗ trợ giảng viên:

1. Đăng nhập bằng email trường.
2. Nhập thời khóa biểu bằng ảnh hoặc nhập thủ công.
3. Nếu nhập ảnh, OCR đọc thông tin và giảng viên review/chỉnh sửa trước khi lưu.
4. Import file danh sách lớp và sinh viên do giảng viên cung cấp.
5. Tự động ghép thời khóa biểu với lớp theo `Semester + SubjectCode + ClassCode`.
6. Bắt đầu phiên điểm danh.
7. Hiển thị QR Code và Secret Code động, đổi mỗi 2–3 phút.
8. Sinh viên quét QR, đăng nhập bằng email trường và check-in.
9. Kết quả được ghi vào Google Sheets và cập nhật trên Desktop App.
10. Kết thúc điểm danh, sinh viên chưa check-in được đánh dấu `ABSENT`.
11. Giảng viên có thể chỉnh sửa kết quả nếu cần.
12. Export Excel theo template để giảng viên nhập thủ công lên FAP.

## 3. Luồng tổng thể

```text
Lecturer Google Login
        ↓
Import Schedule Image OR Manual Schedule
        ↓
OCR → Parse → Review/Edit → Confirm
        ↓
Import Class/Student File
        ↓
Auto Mapping
        ↓
Start Attendance
        ↓
Dynamic QR + Secret Code
        ↓
Student Scan QR
        ↓
Student Google Login
        ↓
Validate Student + Session + Token + Secret
        ↓
Save Attendance → Google Sheets
        ↓
Live Update on Flutter Desktop
        ↓
End Attendance
        ↓
Mark Missing Students ABSENT
        ↓
Review / Edit
        ↓
Export FAP Excel
```

## 4. Công nghệ dự kiến

### Flutter Desktop
- Flutter / Dart
- Provider hoặc Riverpod
- `http`
- `shared_preferences`
- `file_picker`
- `excel`
- `csv`
- `qr_flutter`
- `intl`
- `fl_chart`

### OCR
Ưu tiên OCR local trên Windows:
- `platform_ocr`
- hoặc `pp_ocr`

OCR chỉ có nhiệm vụ đọc text. Dữ liệu phải qua `ScheduleParser` và màn hình Review trước khi lưu.

### Authentication
- Google OAuth / Google Sign-In
- Kiểm tra email domain trường
- Không lưu Google password
- Không dùng FAP account

### API trung gian
- Google Apps Script Web App

Dùng để:
- Đọc/ghi Google Sheets
- Xử lý check-in
- Validate session
- Validate QR token
- Validate Secret Code

## 5. Cấu trúc Google Sheets

### `Lecturers`
```text
lecturerId
lecturerCode
fullName
email
department
```

### `Schedules`
```text
scheduleId
lecturerId
semester
subjectCode
subjectName
classCode
dayOfWeek
slot
startTime
endTime
room
sourceType
```

`sourceType`: `IMAGE` hoặc `MANUAL`

### `Classes`
```text
classId
semester
subjectCode
subjectName
classCode
lecturerId
```

### `Students`
```text
studentId
studentCode
fullName
schoolEmail
```

### `Enrollments`
```text
enrollmentId
classId
studentId
```

### `Sessions`
```text
sessionId
classId
date
slot
startTime
endTime
status
currentToken
tokenExpiredAt
createdBy
```

### `Attendance`
```text
attendanceId
sessionId
studentId
status
checkInTime
updatedAt
note
updatedBy
```

Status:
```text
PRESENT
LATE
ABSENT
EXCUSED
```

### `SyncLogs`
```text
logId
action
userEmail
timestamp
description
```

---

# 6. MEMBER 1 – LEADER / AUTH / OCR SCHEDULE / CORE INTEGRATION

## Vai trò
- Team Leader
- System Architect
- Core Flutter Developer
- Integration Owner

## Nhiệm vụ

### A. Setup Project
- Khởi tạo Flutter Desktop.
- Tạo routing, theme, constants, utilities.
- Tạo cấu trúc module dùng chung.

```text
lib/
├── core/
├── models/
├── services/
├── repositories/
├── features/
│   ├── auth/
│   ├── schedule/
│   ├── classes/
│   ├── attendance/
│   └── reports/
├── shared/
└── main.dart
```

### B. Google Authentication
- Google Login.
- Kiểm tra domain email trường.
- Lecturer Profile.
- Logout.
- Remember Session.

Flow:
```text
Google Login
   ↓
OAuth
   ↓
Get Email
   ↓
Validate School Domain
   ↓
Find Lecturer
   ↓
Login Success
```

### C. Schedule OCR
Tạo `OcrService`:
- Chọn ảnh bằng File Picker.
- OCR ảnh.
- Trả Raw Text.
- Xử lý lỗi OCR.

Tạo `ScheduleParser` để extract:
- Subject Code
- Class Code
- Day
- Slot
- Start Time
- End Time
- Room

### D. OCR Review
Bắt buộc có bước:

```text
OCR
 ↓
Detected Data
 ↓
Review / Edit
 ↓
Confirm
 ↓
Save
```

Không tự động lưu dữ liệu OCR.

### E. Manual Schedule
Form nhập:
- Semester
- Subject Code
- Subject Name
- Class Code
- Day
- Slot
- Start Time
- End Time
- Room

### F. Auto Class Mapping
Dùng key:

```text
Semester + SubjectCode + ClassCode
```

Ví dụ:

```text
FA26_PRM393_SE1848
```

### G. Google Sheets Core Service
Tạo:
```text
GoogleSheetService
```

Các method:
```text
getRows()
appendRow()
updateRow()
deleteRow()
batchUpdate()
```

### H. Integration
- Merge Pull Request.
- Resolve Conflict.
- Review code.
- Integration Test.
- Build Windows.
- Chuẩn bị Final Demo.

## Deliverables
- Flutter base project
- Google Login
- Lecturer Profile
- OCR Service
- Schedule Parser
- OCR Review Screen
- Manual Schedule
- Auto Class Mapping
- Google Sheets Core Service
- Final Integration

## Branch
```text
feature/core
feature/google-auth
feature/schedule-ocr
feature/manual-schedule
feature/class-mapping
feature/google-sheet-core
feature/integration
```

---

# 7. MEMBER 2 – IMPORT DATA / CLASS / STUDENT / ENROLLMENT

## Vai trò
- Data Import Developer
- Class & Student Management Developer

## Nhiệm vụ

### A. Import File lớp
Hỗ trợ:
- Excel
- CSV
- Google Sheet export

Flow:
```text
Select File
 ↓
Read File
 ↓
Validate
 ↓
Preview
 ↓
Confirm
 ↓
Save
```

### B. Validation
Kiểm tra:
- Missing Student Code
- Missing Student Name
- Missing Class Code
- Missing Subject Code
- Duplicate Student
- Duplicate Enrollment
- Empty File
- Invalid Column
- Invalid Class

### C. Class Management
- View Class List
- View Class Detail
- Search Class
- Create/Edit/Delete Class

### D. Student Management
- Student List
- Student Detail
- Search Student
- Add/Edit/Remove Student

### E. Enrollment Management
Quản lý quan hệ Student ↔ Class.

### F. Mapping Support
Chuẩn hóa dữ liệu để Member 1 mapping theo:
```text
semester
subjectCode
classCode
```

## Deliverables
- File Import
- Excel/CSV Parser
- Import Preview
- Validation
- Class Management
- Student Management
- Enrollment Management

## Branch
```text
feature/import
feature/import-preview
feature/class-management
feature/student-management
feature/enrollment
```

---

# 8. MEMBER 3 – ATTENDANCE SESSION / DYNAMIC QR / STUDENT CHECK-IN

## Vai trò
- Attendance Core Developer
- QR Developer
- Check-in Developer

## Nhiệm vụ

### A. Attendance Session
Tạo session từ:
- Class
- Date
- Slot
- Start Time
- End Time

### B. QR Generator
QR chứa:
```text
sessionId
token
timestamp
```

Không chứa Student ID.

### C. Secret Code
- Mã 6 chữ số.
- Đồng bộ với session/token hiện tại.

### D. Dynamic QR Rotation
QR và Secret Code thay đổi sau:
```text
120–180 giây
```

Flow:
```text
Generate Token + Secret
      ↓
Display
      ↓
Countdown
      ↓
Expire
      ↓
Generate New Token + Secret
```

### E. Student Check-in Web
Flow:
```text
Scan QR
 ↓
Open Browser
 ↓
Google Login
 ↓
Validate School Email
 ↓
Find Student
 ↓
Verify Secret
 ↓
Check-in
```

### F. Validation
Kiểm tra:
- Session tồn tại.
- Session đang mở.
- Token đúng.
- Token chưa hết hạn.
- Secret Code đúng.
- Student thuộc lớp.
- Email đúng Student.
- Chưa check-in trước đó.

### G. Attendance Status
Ví dụ:
```text
07:30–07:45 → PRESENT
07:46–08:00 → LATE
Sau khi session đóng và chưa check-in → ABSENT
```

### H. Anti Duplicate
Rule:
```text
1 Student + 1 Session = 1 Attendance Record
```

## Deliverables
- Attendance Session
- Dynamic QR
- Secret Code
- Countdown
- Student Check-in Web
- Student Google Login
- Check-in Validation
- Duplicate Prevention
- Present/Late Logic

## Branch
```text
feature/session
feature/qr-attendance
feature/secret-code
feature/student-checkin
feature/attendance-validation
```

---

# 9. MEMBER 4 – LIVE ATTENDANCE / HISTORY / REPORT / FAP EXCEL EXPORT

## Vai trò
- Monitoring Developer
- Reporting Developer
- Export Developer

## Nhiệm vụ

### A. Live Attendance
Hiển thị:
```text
PRM393 - SE1848
17 / 30 Checked-in
```

Danh sách:
```text
SE184297
Nguyen Van A
PRESENT
07:35:12
```

Refresh Google Sheets/API mỗi 2–5 giây.

### B. End Attendance
Flow:
```text
End Attendance
 ↓
Close Session
 ↓
Invalidate QR
 ↓
Find Missing Students
 ↓
Mark ABSENT
```

### C. Manual Update
Cho phép Lecturer:
- `ABSENT → PRESENT`
- `PRESENT → LATE`
- `LATE → PRESENT`
- Add Note / Reason

### D. Attendance History
Filter:
- Class
- Subject
- Date
- Student
- Status

### E. Dashboard
Hiển thị:
- Total Classes
- Total Students
- Today Sessions
- Attendance Rate
- Present
- Late
- Absent

### F. Reports
- Class Attendance Report
- Student Attendance Report
- Attendance Rate
- At-risk warning, ví dụ `< 80%`

### G. FAP Excel Export
Không dùng FAP API.

Flow:
```text
Load FAP Excel Template
        ↓
Read Student Code
        ↓
Match Attendance
        ↓
Fill Status
        ↓
Generate New Excel
```

Không thay đổi cấu trúc template nếu FAP yêu cầu format cố định.

## Deliverables
- Live Attendance UI
- Auto Refresh
- End Attendance
- Manual Update
- Attendance History
- Dashboard
- Reports
- Warning
- FAP Excel Export

## Branch
```text
feature/live-attendance
feature/end-attendance
feature/history
feature/dashboard
feature/report
feature/fap-export
```

---

# 10. Phân bố khối lượng

| Thành viên | Module | Độ khó |
|---|---|---|
| Member 1 – Leader | Auth + OCR + Schedule + Mapping + Core | ★★★★★ |
| Member 2 | Import + Class + Student + Enrollment | ★★★★☆ |
| Member 3 | Session + Dynamic QR + Secret + Check-in | ★★★★★ |
| Member 4 | Live Attendance + History + Reports + Excel | ★★★★☆ |

---

# 11. Git Workflow

Branches chính:
```text
main
develop
```

Không push trực tiếp lên `main`.

```text
feature/*
   ↓
Pull Request
   ↓
develop
   ↓
Integration Test
   ↓
main
```

Commit convention:
```text
feat: implement schedule OCR
feat: add manual schedule form
feat: implement dynamic attendance QR
feat: add student check-in validation
feat: export attendance to FAP template
fix: prevent duplicate attendance
fix: correct schedule mapping
refactor: update Google Sheet repository
```

---

# 12. Definition of Done

Một task chỉ hoàn thành khi:

- Code chạy được.
- Không compile error.
- UI hoàn chỉnh.
- Có validation.
- Có error handling cơ bản.
- Đã test.
- Push đúng branch.
- Commit rõ ràng.
- Tạo Pull Request.
- Leader review.
- Merge vào `develop` thành công.

---

# 13. MVP bắt buộc

### Authentication
- Google Login
- Email trường validation
- Logout

### Schedule
- Import ảnh
- OCR
- OCR Review/Edit
- Manual Schedule
- View Schedule

### Class Data
- Import danh sách sinh viên
- Class
- Student
- Enrollment
- Auto Mapping

### Attendance
- Start Attendance
- Dynamic QR
- Secret Code
- Student Google Login
- Student Check-in
- Present / Late / Absent

### Monitoring
- Live Attendance
- End Attendance
- Manual Update

### Report
- Attendance History
- Class Report
- Student Report

### Export
- Export Excel theo template FAP

---

# 14. Optional Features

Chỉ làm nếu còn thời gian:

- Same Wi-Fi validation
- Device fingerprint
- Advanced anti-cheating
- OCR image preprocessing
- OCR confidence score
- Dashboard charts nâng cao
- Dark Mode
- Notifications
- GPS Attendance
- Face Recognition

---

# 15. Final Demo Flow

```text
Lecturer Google Login
        ↓
Import Schedule Image
        ↓
OCR Detect
        ↓
Review / Correct
        ↓
Save Schedule
        ↓
Import Class/Student File
        ↓
Auto Mapping
        ↓
Open Today's Class
        ↓
Start Attendance
        ↓
Show Dynamic QR + Secret
        ↓
Student Scan QR
        ↓
Student Google Login
        ↓
Check-in
        ↓
Desktop Live Update
        ↓
QR Automatically Rotates
        ↓
End Attendance
        ↓
Missing Students → ABSENT
        ↓
Lecturer Review/Edit
        ↓
View Report
        ↓
Export FAP Excel
```

---

# 16. Trách nhiệm chung của cả nhóm

Tất cả thành viên phải:

- Hiểu flow tổng thể.
- Biết chạy project.
- Biết cấu trúc Google Sheets.
- Hiểu cơ chế QR/Secret.
- Có contribution trên Git.
- Test module của mình.
- Tham gia Integration Test.
- Biết trình bày module phụ trách.
- Không phụ thuộc hoàn toàn vào Leader khi bảo vệ.
