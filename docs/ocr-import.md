# Nhập lịch từ ảnh FA26

Trong màn hình Nhập ảnh, nhập học kỳ FA26 rồi chọn ảnh lịch tuần. OCR giữ tọa độ chữ để ghép từng ô theo thứ và slot. Chọn “Điền giờ còn thiếu theo khung NVH trong ảnh” và phân tích lại nếu thiếu giờ. Khung giờ: 1 = 07:00–09:15; 2 = 09:30–11:45; 3 = 12:30–14:45; 4 = 15:00–17:15. Giờ điền từ khung được đánh dấu riêng trong cảnh báo. Bổ sung tên môn, kiểm tra các trường trước khi xác nhận lưu.

A1/A2 học thứ 2 và 5, A3/A4 học thứ 3 và 6, A5/A6 học thứ 4 và 7; mã lẻ là slot 1, mã chẵn là slot 2. P dùng cùng cặp thứ, mã lẻ là slot 3 và mã chẵn là slot 4. Mỗi mã tạo hai dòng lịch.

Windows OCR trên ảnh phân công được cung cấp vẫn bỏ sót cột A/P. Có thể sao chép nội dung FA26_assignment_review.txt cùng thư mục vào ô văn bản OCR rồi phân tích lại. Đây là bản chép đối chiếu từ ảnh, không phải kết quả tự động. Ảnh này không có lớp/phòng cụ thể: cần bổ sung; NVH là cơ sở, không phải số phòng. Không tự ghép lớp khi một mã môn có nhiều lớp.

Nguồn có khác biệt cần đối chiếu: ảnh phân công ghi SWD392 tại A2/A6, lịch tuần ghi SWD392 SE1927 vào slot 2 thứ 3/6. Một số tên sheet trong FA26_Markbook.ods cũng khác mã môn trên lịch: 13_PRM392_SE1920, 23_PRM232, 24_PRM323_SE1928. Không tự sửa mã môn hoặc lịch từ các khác biệt này. File markbook không bị chỉnh sửa và chưa được thêm chức năng nhập ODS.

Kiểm thử dùng dữ liệu OCR thực từ hai ảnh (không chứa danh sách sinh viên), quy đổi đủ 12 mã A/P, các ô lịch tuần và thao tác duyệt không tự lưu.
