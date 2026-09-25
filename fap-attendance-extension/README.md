# FAP Attendance Connector 1.2

## Install / update

1. Open `chrome://extensions` (or `edge://extensions`). Enable Developer mode.
2. Load unpacked → select this `fap-attendance-extension` directory. If already installed, click Reload.
3. For local HTML tests only, open the extension's Details and enable **Allow access to file URLs**. Reload the HTML tab after updating the extension.

## Import Excel and fill attendance

1. Open the lecturer attendance page for the correct course, class, date and slot.
2. Open the extension. Wait for scanning to complete.
3. Choose the `.xlsx` file exported from the desktop app. Keep its exported filename, e.g. `Diemdanh_PRN232_SE1917_2026-09-22_Slot1.xlsx`.
4. Review the matched count and present/absent summary.
5. Click **Bắt đầu tự điểm danh**. The extension selects attendance controls by **MSSV**, not table row order.
6. Review the page, then click the FAP Save button yourself. The extension never clicks Save or submits the form.

PRESENT → Present/Có mặt; ABSENT → Absent/Vắng mặt; LATE → Present/Có mặt for the two-state FAP form. The popup displays this mapping. No student absent from the spreadsheet is automatically marked absent.

Importing Excel works without the desktop app running. The existing web → desktop roster workflow remains available separately. Closing the popup discards the selected workbook; reopen and choose it again if needed.

## Local test page

Open `../attendance.html` or the updated `Downloads/attendance.html`. Both contain the 35-student roster corresponding to the supplied workbook, with no attendance preselected. The supplied workbook should produce **1 present (SE193416), 34 absent**, and no save message until **Lưu thử** is clicked.

Use **Đảo thứ tự để test MSSV** before import to confirm matching is independent of row position. Use **Xóa lựa chọn để test lại** to repeat. **Lưu thử** only displays local totals; it does not contact FAP. Original HTML files were backed up alongside each copy as `attendance.html.original.bak`.

This is a FAP-inspired test layout, not a verified copy of the authenticated production FAP DOM. Supported adapters: tables with Roll Number/MSSV headers and Present/Absent radio controls (including ASP.NET names and 1/0 values), and the original `.student-card` layout. Unknown or ambiguous controls stop the operation. All file students must be present on the loaded page; pagination is not traversed automatically.

## Checks and limitations

The importer validates required columns, unique MSSVs, supported statuses, FAP symbols, filename metadata, and matching page metadata before selecting any controls. Disabled/missing controls or missing/duplicate page students block the preflight. The page is scanned again on Start. A changed tab is rejected. A runtime page change may stop a partially completed operation; the result reports how many rows were processed so the lecturer can review them.

The workbook is read locally. It is not uploaded. SheetJS CE 0.20.3 is bundled under `vendor/` so Chrome Manifest V3 does not execute remotely hosted code. Source: https://docs.sheetjs.com/docs/getting-started/installation/standalone/ . License: `vendor/SheetJS-LICENSE`. SHA256 of `xlsx.full.min.js`: `CC015130AA8521E7F088F88898EBA949CCDCBFB38DF0BD129B44B7273C3A6F41`.

## Development tests

From the repository root:

```powershell
npm install --prefix .tools/extension-tests --no-audit --no-fund jsdom@26.1.0
$env:FAP_EXCEL_FIXTURE = 'C:/Users/ontri/Downloads/Diemdanh_PRN232_SE1917_2026-09-22_Slot1.xlsx'
node --test fap-attendance-extension/test/*.test.cjs
```

The real-workbook fixture test is enabled by `FAP_EXCEL_FIXTURE`; it verifies all 35 choices, counters and the lack of automatic submission. Other tests use generated in-memory workbooks and DOM fixtures, including a mocked Chrome popup message transport. Browser installation and live FAP compatibility require testing in Chrome/Edge with the real lecturer page.
# Lưu ý Excel → HTML test

Sau khi cập nhật extension, Reload tại `chrome://extensions` rồi reload cả tab HTML. Với file cục bộ, bật Details → Allow access to file URLs.

Scanner hỗ trợ `tr[data-student-code]`, `Member Code / Roll Number` và header aliases. Điền theo MSSV, không theo thứ tự dòng. Quét lại giữ Excel đã chọn và đối chiếu lại. Extension chỉ điền trạng thái; giảng viên tự bấm Lưu.

Trang và Excel có thông tin lớp/môn/ngày/slot khác nhau sẽ bị chặn. HTML gốc dự án hiện ghi 22/09/2026 Slot 4, còn file `Diemdanh_PRM393_SE1922_2026-09-25_Slot3.xlsx` ghi 25/09/2026 Slot 3. Cần mở đúng buổi trước khi nhập.

Chi tiết audit và giới hạn kiểm thử: `../docs/EXCEL_FAP_IMPORT_AUDIT.md`.
