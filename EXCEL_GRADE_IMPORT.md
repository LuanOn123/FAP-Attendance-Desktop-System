# Nhập điểm Excel trên Desktop

## Cách dùng

1. Mở **Điểm số**, chọn đúng học kỳ/môn/lớp.
2. Bấm **Tải file mẫu Excel** để lấy danh sách MSSV, các cột điểm và điểm hiện tại của lớp. Hoặc dùng file `.xlsx` có sẵn.
3. Nhập điểm trong Excel rồi lưu file. Với `.xls`, dùng Save As thành `.xlsx`.
4. Bấm **Nhập điểm từ Excel**. Chọn sheet, dòng tiêu đề, cột MSSV và dòng dữ liệu cuối; loại các dòng tổng kết ở cuối file.
5. Chọn những cột điểm cần nhập. Ghép với cột điểm hiện có, hoặc tạo cột mới với tên và thang điểm riêng. Có thể ghép thêm cột nhận xét.
6. Bấm **Kiểm tra / Xem trước**, kiểm tra từng thay đổi, sửa file nếu có lỗi. Tích xác nhận đúng lớp rồi bấm **Đưa vào bảng nháp**.
7. Bấm **Lưu bản nháp** để lưu lên backend chung. Sau đó dùng **Xem trước / Công bố** khi muốn sinh viên xem điểm trên Student Web.

## Quy tắc

- Ghép bằng MSSV, không dựa vào thứ tự hàng hoặc họ tên. Trim và chuẩn hóa chữ hoa khi đối chiếu; giữ nguyên studentId từ backend.
- Chấp nhận điểm 0 và dấu phẩy thập phân, ví dụ `8,5`. Điểm phải là số hữu hạn trong thang điểm của từng cột.
- Ô trống mặc định giữ điểm/nhận xét cũ. Chỉ xóa khi bật tùy chọn **Xóa điểm cũ khi ô Excel trống**. Sinh viên không có trong file và cột không được chọn giữ nguyên.
- MSSV thiếu, trùng hoặc ngoài lớp; điểm lỗi, ngày, phần trăm, boolean hoặc vượt thang đều chặn áp dụng toàn bộ lần nhập.
- Nếu file có cột Học kỳ/Mã môn/Mã lớp, mọi dòng phải khớp lớp được chọn. File không có các cột này vẫn cần xác nhận lớp trong màn xem trước.
- Công thức không được tính lại. Chỉ dùng kết quả Excel đã lưu khi giảng viên chủ động bật tùy chọn; công thức không có kết quả vẫn bị chặn.
- Tối đa file 20 MB, nội dung ZIP khai báo 100 MB, 20.000 dòng/sheet, 256 cột/sheet và 30 cột điểm trong bảng. Chỉ đọc các sheet hiển thị.
- Hủy hoặc thay đổi cách ghép cột không ghi lên server. Thay đổi tùy chọn sẽ xóa kết quả xem trước và yêu cầu kiểm tra lại.

## Liên kết ba nền tảng

Desktop và Mobile dành cho giảng viên; Student Web dành cho sinh viên. Tính năng này gọi lại API `saveGradebook` / `publishGrades` hiện có của backend chung, không tạo kho điểm độc lập. Backend kiểm tra quyền sở hữu lớp, phiên bản và roster khi lưu/công bố.

Điểm đang công bố là snapshot: nhập hoặc lưu bản nháp mới không tự sửa điểm sinh viên đang nhìn thấy. Cần công bố lại để tạo bản điểm mới. Không cần thêm API/backend deployment riêng cho chức năng nhập Excel nếu deployment hiện tại đã hỗ trợ các API bảng điểm này.

## Phạm vi kiểm tra

Đã kiểm tra bộ đọc XLSX, ghép cột, bảo toàn dữ liệu cũ, lỗi đầu vào, màn xem trước/xác nhận/hủy và quy tắc lưu/công bố của backend bằng test tự động. Chưa nhập/công bố điểm thật hoặc kiểm thử end-to-end với tài khoản trường trên deployment đang chạy.

Mã nằm trên nhánh `codex/group-sheet-sync` của repo Desktop; chức năng nhập Excel được tách thành commit riêng. Chưa merge vào main.
