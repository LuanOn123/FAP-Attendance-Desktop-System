class SessionModel {
  final String sessionId;
  final String classId;
  final String date;
  final int slot;
  final String startTime;
  final String endTime;
  final String status; // 'OPEN', 'CLOSED'
  final String currentToken;
  final String currentSecretCode;
  final String tokenExpiredAt;
  final String createdBy;

  const SessionModel({
    required this.sessionId,
    required this.classId,
    required this.date,
    required this.slot,
    required this.startTime,
    required this.endTime,
    required this.status,
    required this.currentToken,
    this.currentSecretCode = '',
    required this.tokenExpiredAt,
    required this.createdBy,
  });

  bool get isOpen => status.toUpperCase() == 'OPEN';

  factory SessionModel.fromJson(Map<String, dynamic> json) {
    return SessionModel(
      sessionId: json['sessionId']?.toString() ?? '',
      classId: json['classId']?.toString() ?? '',
      date: normalizeDate(json['date']?.toString() ?? ''),
      slot: int.tryParse(json['slot']?.toString() ?? '') ?? 1,
      startTime: json['startTime']?.toString() ?? '',
      endTime: json['endTime']?.toString() ?? '',
      status: (json['status']?.toString() ?? 'OPEN').trim().toUpperCase(),
      currentToken: (json['currentToken']?.toString() ?? '').split('#').first,
      currentSecretCode:
          json['currentSecretCode']?.toString() ??
          ((json['currentToken']?.toString() ?? '').contains('#')
              ? json['currentToken'].toString().split('#').last
              : ''),
      tokenExpiredAt: json['tokenExpiredAt']?.toString() ?? '',
      createdBy: json['createdBy']?.toString() ?? '',
    );
  }

  static String normalizeDate(String value) {
    final text = value.trim();
    final match = RegExp(r'^(\d{1,2})/(\d{1,2})/(\d{4})$').firstMatch(text);
    if (match != null) {
      return '${match[3]}-${match[2]!.padLeft(2, '0')}-${match[1]!.padLeft(2, '0')}';
    }
    return text;
  }

  Map<String, dynamic> toJson() => {
    'sessionId': sessionId,
    'classId': classId,
    'date': date,
    'slot': slot,
    'startTime': startTime,
    'endTime': endTime,
    'status': status,
    'currentToken': currentToken,
    'currentSecretCode': currentSecretCode,
    'tokenExpiredAt': tokenExpiredAt,
    'createdBy': createdBy,
  };

  SessionModel copyWith({
    String? status,
    String? currentToken,
    String? currentSecretCode,
    String? tokenExpiredAt,
  }) {
    return SessionModel(
      sessionId: sessionId,
      classId: classId,
      date: date,
      slot: slot,
      startTime: startTime,
      endTime: endTime,
      status: status ?? this.status,
      currentToken: currentToken ?? this.currentToken,
      currentSecretCode: currentSecretCode ?? this.currentSecretCode,
      tokenExpiredAt: tokenExpiredAt ?? this.tokenExpiredAt,
      createdBy: createdBy,
    );
  }
}
