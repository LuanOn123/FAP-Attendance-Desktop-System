# Member 1 API contract

POST HTTPS Apps Script `/exec`, Content-Type `application/json`. Token phải nằm trong body, không nằm trong URL client hoặc log.

```json
{"action":"getRows","sheet":"Schedules","idToken":"GOOGLE_ID_TOKEN"}
```

Thành công: `{"ok":true,"data":...}`. Thất bại: `{"ok":false,"error":"..."}`.
Apps Script thường trả 200 cho JSON lỗi; phải kiểm tra `ok`. ContentService trả 302/303 tới URL kết quả dùng một lần trên `script.googleusercontent.com`; client GET URL này và không gửi lại token/body.

| Action | Payload thêm | Data | Quyền hiện có |
|---|---|---|---|
| profile | không | Lecturer | Giảng viên đã đăng ký |
| getRows | sheet | danh sách object theo header | Lecturers/Schedules/Classes cùng lecturerId |
| appendRow | sheet, row | saved: true | Schedules, ID mới |
| updateRow | sheet, id, row | saved: true | Schedules, ID tồn tại và khớp |
| deleteRow | sheet, id | saved: true | Schedules, sở hữu bởi giảng viên |
| batchUpdate | sheet, rows | saved: true | Schedules, upsert 1–100 dòng |

`row` là object đầy đủ 12 trường Schedule. Không đổi header, không dùng số dòng spreadsheet làm ID. UUID được tạo trước lần lưu đầu tiên để retry giữ nguyên ID.

```json
{
  "scheduleId": "UUID", "lecturerId": "lec-001", "semester": "FA26",
  "subjectCode": "PRM393", "subjectName": "Mobile Programming", "classCode": "SE1848",
  "dayOfWeek": 1, "slot": 1, "startTime": "07:30", "endTime": "09:00",
  "room": "AL-201", "sourceType": "IMAGE"
}
```

Server chuẩn hóa semester/subjectCode/classCode. `dayOfWeek` ISO 1–7, `slot` 1–12; Sheets trả dạng chuỗi cũng được model Dart chuyển về int. Giờ lưu dưới dạng stringValue để tránh chuyển đổi theo locale/timezone của Sheets. Chuỗi bắt đầu `=` không được thực thi như công thức.

Ghi Schedules và thêm SyncLog trong cùng `Sheets.Spreadsheets.batchUpdate`. ScriptLock bao quanh đọc–validate–ghi. Không sửa trực tiếp Sheets trong lúc ứng dụng đang ghi; ScriptLock không khóa thao tác thủ công của người sở hữu spreadsheet.

Mapping là quan hệ suy ra, không thêm cột classId vào Schedules: `mappingKey(semester, subjectCode, classCode)`. Member 3 chỉ dùng `MappingResult.mappedClass` khi có đúng một match cùng lecturerId. Member 2 phải tránh trùng key trong Classes.

Các member khác mở rộng endpoint bằng hành động đặc thù, xác thực và lọc quyền trước đọc/ghi. Không mở generic CRUD cho Lecturers hoặc Students, không dùng email trong request thay cho danh tính từ token Google. Endpoint check-in của sinh viên là luồng riêng của member 3.
