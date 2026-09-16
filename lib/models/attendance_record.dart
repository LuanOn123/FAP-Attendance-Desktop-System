class AttendanceRecord {
  final String attendanceId;
  final String sessionId;
  final String studentId;
  final String studentCode;
  final String fullName;
  final String status; // 'PRESENT', 'LATE', 'ABSENT', 'EXCUSED'
  final String checkInTime;
  final String updatedAt;
  final String note;
  final String updatedBy;

  const AttendanceRecord({
    required this.attendanceId,
    required this.sessionId,
    required this.studentId,
    this.studentCode = '',
    this.fullName = '',
    required this.status,
    required this.checkInTime,
    required this.updatedAt,
    this.note = '',
    this.updatedBy = '',
  });

  factory AttendanceRecord.fromJson(Map<String, dynamic> json) {
    return AttendanceRecord(
      attendanceId: json['attendanceId']?.toString() ?? '',
      sessionId: json['sessionId']?.toString() ?? '',
      studentId: json['studentId']?.toString() ?? '',
      studentCode: json['studentCode']?.toString() ?? '',
      fullName: json['fullName']?.toString() ?? '',
      status: json['status']?.toString() ?? 'PRESENT',
      checkInTime: json['checkInTime']?.toString() ?? '',
      updatedAt: json['updatedAt']?.toString() ?? '',
      note: json['note']?.toString() ?? '',
      updatedBy: json['updatedBy']?.toString() ?? '',
    );
  }

  Map<String, dynamic> toJson() => {
    'attendanceId': attendanceId,
    'sessionId': sessionId,
    'studentId': studentId,
    'studentCode': studentCode,
    'fullName': fullName,
    'status': status,
    'checkInTime': checkInTime,
    'updatedAt': updatedAt,
    'note': note,
    'updatedBy': updatedBy,
  };
}
