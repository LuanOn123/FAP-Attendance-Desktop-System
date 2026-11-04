# Google Sheets đăng ký nhóm

Worktree này thêm panel tạo/mở/sao chép link/đồng bộ/chốt Google Sheets trong Nhóm học tập. Dữ liệu vẫn đọc `PortalGroupPlans` qua Apps Script chung. Màn nhóm tự kiểm version mỗi 15 giây; có bản nháp hoặc thao tác chưa lưu thì giữ nguyên và chờ lượt tiếp theo.

Backend triển khai từ `C:/Users/ADMIN/Desktop/FPT-Lecturer-Mobile-App/backend/apps_script` với module `GroupSignupSheets.gs`, router/schema và manifest tương ứng; owner chạy `setupGroupSignupSheets()` rồi cập nhật deployment. Worktree desktop chỉ thay giao diện và test. Hướng dẫn đầy đủ ở `docs/GROUP_SELF_SIGNUP_SHEETS.md` trong repo mobile.

Nhánh local: `codex/group-sheet-sync`, dựa trên origin/main `3263f63`. Checkout desktop gốc đang có sửa đổi chưa commit được giữ nguyên. Sử dụng config/local.json của desktop hiện tại khi chạy; config này chưa được chép sang worktree.

Thay đổi được quản lý trên nhánh `codex/group-sheet-sync`. Chưa triển khai backend; kiểm thử widget dùng API giả lập, không tạo/chia sẻ Sheet thật.
