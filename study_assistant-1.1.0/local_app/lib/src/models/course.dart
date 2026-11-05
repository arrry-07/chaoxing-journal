class CourseRef {
  const CourseRef(
      {required this.courseId, required this.clazzId, required this.name});
  final String courseId, clazzId, name;
  String get key => '$courseId:$clazzId';
  Map<String, dynamic> toJson() =>
      {'courseId': courseId, 'clazzId': clazzId, 'name': name};
  factory CourseRef.fromJson(Map<String, dynamic> j) => CourseRef(
      courseId: j['courseId'] as String,
      clazzId: j['clazzId'] as String,
      name: j['name'] as String);
}
