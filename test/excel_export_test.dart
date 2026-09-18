import 'package:flutter_test/flutter_test.dart';
import 'package:archive/archive.dart';
import 'package:fap_attendance/services/excel_export_service.dart';

void main() {
  test('generateXlsx creates valid ZIP/XLSX structure', () {
    final bytes = ExcelExportService.generateXlsx(
      sheetName: 'DiemDanh_SE1818',
      headers: ['STT', 'Lớp học', 'MSSV', 'Họ và tên', 'Trạng thái'],
      rows: [
        ['1', 'SE1818', 'SE181848', 'Nguyen Van Toan', 'Có mặt'],
        ['2', 'SE1818', 'SE181849', 'Tran Thi B', 'Vắng'],
      ],
    );

    expect(bytes, isNotEmpty);
    final zip = ZipDecoder().decodeBytes(bytes);
    expect(zip.findFile('[Content_Types].xml'), isNotNull);
    expect(zip.findFile('xl/workbook.xml'), isNotNull);
    expect(zip.findFile('xl/worksheets/sheet1.xml'), isNotNull);
  });
}
