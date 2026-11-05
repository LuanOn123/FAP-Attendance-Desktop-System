# Tính điểm FE/PE cho giảng viên

Vào **Điểm số → chọn lớp → Tính điểm FE/PE**.

Nhập điểm và trọng số từng cột (tổng 100%), để trống FE hoặc PE cần tính rồi bấm **Tính điểm cần đạt**. Có thể thêm/xóa cột và tính các cặp FE/PE. Nếu bài thi đã có điểm, nhập điểm để cố định bài đó.

Mục tiêu là tổng **> 5/10**, không phải ≥ 5. Điểm thi gợi ý nhỏ nhất theo bước 0,1; giữ đúng điểm 0 và nhận dấu phẩy thập phân. Tổng đúng 5 chưa đạt mục tiêu. Nếu dù thi 10 vẫn không đủ, hiển thị tổng tối đa. Kiểm tra thêm điểm liệt, chuyên cần và điều kiện môn trong syllabus.

Ví dụ: Assignment, PT, Quiz đều 5 điểm và mỗi cột 20%; FE 40% → cần FE 5,1, tổng 5,04.

Đây là bảng tính thử nhập tay. Không tự lấy điểm của sinh viên, không gọi API ghi hoặc sửa điểm đã công bố. Quay lại giữ nguyên bảng điểm đang sửa. Đóng màn tính thử sẽ mất dữ liệu tính thử.

Mobile/Desktop là công cụ giảng viên; Student Web dành cho sinh viên. Bộ tính Dart tại `lib/grade_forecast/` của Mobile/Desktop giống nhau và tuân theo quy tắc bản web. Không cần backend mới.

Đã có unit/widget test cho phép tính, FE/PE kết hợp, lỗi đầu vào, bố cục hẹp/rộng và test mở/đóng không ghi lên bảng điểm. Chức năng được quản lý trên nhánh `codex/group-sheet-sync` của repo Desktop, chưa merge vào main.
