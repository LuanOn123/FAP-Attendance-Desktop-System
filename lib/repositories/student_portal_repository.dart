import 'dart:convert';
import '../core/app_config.dart';
import '../services/google_sheet_service.dart';

typedef PortalRow = Map<String, dynamic>;

abstract class StudentPortalRepository {
  Future<dynamic> call(String method, [PortalRow data = const {}]);
}

class SheetStudentPortalRepository implements StudentPortalRepository {
  final GoogleSheetService sheets;
  SheetStudentPortalRepository(this.sheets);
  @override
  Future<dynamic> call(String method, [PortalRow data = const {}]) async {
    if (method == 'firebaseGroupSignup' ||
        (const bool.fromEnvironment('FIREBASE_GROUP_SIGNUP') &&
            method == 'getGroupPlan')) {
      return sheets.firebaseGroupSignup({
        ...data,
        if (method == 'getGroupPlan') 'action': 'plan',
      });
    }
    try {
      return await sheets.request('portalCall', {
        'method': method,
        'data': data,
      });
    } on AppException catch (e) {
      if (method == 'createGroupTask') rethrow;
      const messages = {
        'VERSION_CONFLICT': 'Dữ liệu đã thay đổi. Tải lại trước khi lưu.',
        'OCCURRENCE_CHANGED':
            'Lịch học đã thay đổi. Kiểm tra lại đơn trước khi duyệt.',
        'PERMISSION_DENIED': 'Bạn không có quyền xử lý lớp này.',
        'INVALID_GRADE_RANGE': 'Điểm phải là số từ 0 đến thang điểm của cột.',
        'INVALID_COMPONENTS':
            'Cột điểm bị trùng, thiếu tên hoặc thang điểm không hợp lệ.',
        'ROSTER_CHANGED':
            'Danh sách sinh viên đã thay đổi. Hãy tải lại bảng điểm.',
        'INVALID_REASON': 'Cần nhập lý do từ chối, tối đa 500 ký tự.',
        'MANUAL_CORRECTION_REQUIRED':
            'Kết quả đã có điểm danh hoặc được chỉnh thủ công. Hãy dùng chức năng sửa điểm danh.',
        'SHARED_BACKEND_SETUP_REQUIRED':
            'Cần cập nhật backend chung và chạy setupStudentPortal.',
      };
      throw AppException(messages[e.message] ?? e.message);
    }
  }
}

/// Explicit offline demo; never used as a fallback for a failed network request.
class DemoStudentPortalRepository implements StudentPortalRepository {
  PortalRow state = {
    'classId': 'demo-class',
    'version': 0,
    'activePublicationId': '',
    'components': <PortalRow>[],
    'students': <PortalRow>[
      {
        'studentId': 'demo-s1',
        'studentCode': 'SE000001',
        'fullName': 'Sinh viên mẫu',
        'grades': <String, dynamic>{},
        'comment': '',
      },
    ],
  };
  @override
  Future<dynamic> call(String method, [PortalRow data = const {}]) async {
    if (method == 'listClasses') {
      return [
        {
          'classId': 'demo-class',
          'semester': 'FA26',
          'subjectCode': 'PRM393',
          'classCode': 'SE1848',
        },
      ];
    }
    if (method == 'listClassLeaveRequests') return <PortalRow>[];
    if (method == 'getGradebook') return jsonDecode(jsonEncode(state));
    if (data['version'] != state['version']) {
      throw const AppException('Dữ liệu đã thay đổi. Hãy tải lại.');
    }
    if (method == 'saveGradebook') {
      state = {
        ...state,
        'components': data['components'],
        'students': (data['students'] as List)
            .map(
              (r) => {
                ...(state['students'] as List).cast<PortalRow>().firstWhere(
                  (s) => s['studentId'] == r['studentId'],
                ),
                ...PortalRow.from(r as Map),
              },
            )
            .toList(),
        'version': (state['version'] as int) + 1,
      };
    } else if (method == 'publishGrades' || method == 'revokeGrades') {
      state = {
        ...state,
        'activePublicationId': method == 'publishGrades'
            ? 'demo-publication'
            : '',
        'version': (state['version'] as int) + 1,
      };
    } else {
      throw const AppException('Thao tác không có trong bản demo.');
    }
    return {'saved': true};
  }
}
