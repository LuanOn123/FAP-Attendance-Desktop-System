class Lecturer {
  final String lecturerId, lecturerCode, fullName, email, department;
  const Lecturer({
    required this.lecturerId,
    required this.lecturerCode,
    required this.fullName,
    required this.email,
    required this.department,
  });
  factory Lecturer.fromJson(Map<String, dynamic> j) => Lecturer(
    lecturerId: j['lecturerId'].toString(),
    lecturerCode: j['lecturerCode'].toString(),
    fullName: j['fullName'].toString(),
    email: j['email'].toString(),
    department: j['department'].toString(),
  );
}
