# Giao việc nhóm trên Desktop

Vào Nhóm học tập, chọn lớp, mở nhóm đã lưu rồi bấm **Giao việc cho nhóm**. Nhập tên việc/yêu cầu, chọn hạn giờ Việt Nam, xem xác nhận nhóm và số người nhận rồi bấm Giao việc. Backend chung tạo thông báo Student Web và hàng đợi email trường.

Màn hình hiển thị việc đã giao, số người đọc trên Web, email đã gửi/chờ/bỏ qua/cần kiểm tra. Email SENT chỉ là backend đã chấp nhận gửi, không chứng minh sinh viên đã đọc email. Khi lỗi mạng chưa rõ kết quả, Thử lại dùng cùng payload/requestKey, không tạo một lần giao việc mới.

Cần lưu thay đổi nhóm và xử lý bản nháp chat trước khi mở màn. Quyền lớp/nhóm, phiên bản roster, email thành viên và idempotency vẫn do Apps Script kiểm. Gói backend canonical nằm trong repo Mobile, module GroupTasks.gs; không dùng backend Desktop độc lập thay toàn bộ deployment chung.

Các thay đổi FE/PE đi cùng đợt này cho phép nhập ngưỡng điểm tối thiểu FE/PE từ đề cương. Mặc định 0 = bỏ điều kiện ngưỡng riêng. Tổng vẫn phải >5; chuyên cần/điều kiện khác kiểm riêng. Bảng tính thử không sửa điểm chính thức.

Chức năng được quản lý trên nhánh main của repo Desktop. Chưa deploy; test dùng dữ liệu giả, chưa gửi việc/email tới sinh viên thật.
