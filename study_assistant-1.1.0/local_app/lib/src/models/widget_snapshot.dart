import 'package:intl/intl.dart';

class WidgetSnapshotItem {
  WidgetSnapshotItem({
    required this.assignmentId,
    required this.title,
    required this.courseName,
    required this.deadlineAt,
    required this.remainingText,
    required this.urgencyLevel,
    required this.deepLinkUrl,
  });

  final String assignmentId;
  final String title;
  final String courseName;
  final DateTime? deadlineAt;
  final String remainingText;
  final String urgencyLevel;
  final String deepLinkUrl;

  factory WidgetSnapshotItem.fromJson(Map<String, dynamic> json) {
    return WidgetSnapshotItem(
      assignmentId: json['assignmentId'] as String,
      title: json['title'] as String,
      courseName: json['courseName'] as String,
      deadlineAt: json['deadlineAt'] == null
          ? null
          : DateTime.parse(json['deadlineAt'] as String).toLocal(),
      remainingText: json['remainingText'] as String,
      urgencyLevel: json['urgencyLevel'] as String,
      deepLinkUrl: json['deepLinkUrl'] as String,
    );
  }

  Map<String, dynamic> toJson() => {
        'assignmentId': assignmentId,
        'title': title,
        'courseName': courseName,
        'deadlineAt': deadlineAt?.toIso8601String(),
        if (deadlineAt != null)
          'deadlineText': DateFormat('M月d日 HH:mm').format(deadlineAt!),
        'remainingText': remainingText,
        'urgencyLevel': urgencyLevel,
        'deepLinkUrl': deepLinkUrl,
      };
}
