# Dữ liệu chung với Mobile Lab 2

Mobile ở `C:\PRM\lecture_mobile` dùng Firebase Auth xác minh email, sau đó đọc/ghi cùng Google Sheets qua deployment Apps Script hiện có. `Code.gs` bổ sung hook cho ba action `lab2Health/lab2Snapshot/lab2Call`; `Lab2Free.gs` xử lý API Mobile. Các action Desktop giữ nguyên. Không có bản sao Firestore hoặc Cloud Functions trong luồng miễn phí.

Chủ workbook chạy `setupLab2Free`: khởi tạo header cho tab trống bằng `setupSheets` hiện có, thêm các tab `Lab2SessionMeta`, `Lab2SharedArticles`, `Lab2ArticleCache`, `Lab2Feeds`. Không seed hoặc xóa dữ liệu. Backend Mobile tìm giảng viên theo `Lecturers.email`, sinh viên theo `Students.schoolEmail`, đối chiếu Classes/Enrollments cho quyền lớp. Email Firebase phải được xác minh và thuộc SCHOOL_DOMAINS. Tài khoản Firebase dùng mật khẩu riêng.

Điểm danh Mobile ghi vào Sessions/Attendance hiện có. Desktop bấm tải lại để thấy thay đổi; Mobile làm mới mỗi 30s khi màn hình đang mở hoặc bấm nút đồng bộ. Cùng lớp/ngày/slot là một phiên. QR Mobile tương thích token Desktop; mã xác nhận nếu bật được nhập riêng và không nhúng vào QR. Quiz bị tắt cho bản miễn phí. OpenAlex key giữ tại Script Properties; không nằm trong mobile config.

Hướng dẫn chạy tại `C:\PRM\lecture_mobile\docs\FREE_DESKTOP_SYNC.md`. Khi chỉnh Apps Script, cập nhật phiên bản của deployment hiện có để giữ URL chung.
