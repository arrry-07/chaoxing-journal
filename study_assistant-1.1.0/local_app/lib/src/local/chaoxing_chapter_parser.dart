import '../models/course_chapter_progress.dart';
import 'chaoxing_api_parser.dart';
import 'chaoxing_exam_parser.dart';

class ChaoxingChapterParser {
  const ChaoxingChapterParser._();

  static final RegExp _progressPattern = RegExp(
    r'已完成任务点\s*[:：]\s*<span[^>]*>\s*(\d+)\s*</span>\s*/\s*(\d+)',
  );

  static final RegExp _chapterPattern = RegExp(
    r'<div\b[^>]*class=["\x27][^"\x27]*\bcatalog_num\b[^"\x27]*["\x27][^>]*>[\s\S]*?<em[^>]*>\s*(\d+)\s*</em>[\s\S]*?<div\b[^>]*class=["\x27][^"\x27]*\bcatalog_name\b[^"\x27]*["\x27][^>]*>[\s\S]*?<span[^>]*title=(["\x27])(.*?)\2',
    caseSensitive: false,
  );

  static final RegExp _sectionPattern = RegExp(
    r'<div\b[^>]*class=["\x27][^"\x27]*\bchapter_item\b[^"\x27]*["\x27][^>]*\btitle=(["\x27])(.*?)\1',
    caseSensitive: false,
  );

  static final RegExp _sectionNumPattern = RegExp(
    r'<span\b[^>]*class=["\x27][^"\x27]*\bcatalog_sbar\b[^"\x27]*["\x27][^>]*>\s*([\d.]+)\s*</span>',
    caseSensitive: false,
  );

  static final RegExp _pendingPointsPattern = RegExp(
    r'<span\b[^>]*class=["\x27][^"\x27]*\bcatalog_points_yi\b[^"\x27]*["\x27][^>]*>\s*(\d+)\s*</span>',
    caseSensitive: false,
  );

  static CourseChapterSnapshot? parse(
    String html,
    ChaoxingCourseRef course, {
    DateTime? now,
  }) {
    if (html.contains('没有此页面访问权限')) {
      throw StateError('chapterAccessDenied');
    }
    if (!CourseChapterSnapshot.isValidIdentityToken(course.courseId) ||
        !CourseChapterSnapshot.isValidIdentityToken(course.clazzId)) {
      return null;
    }
    final hasMarkers = html.contains('chapter_item') ||
        html.contains('catalog_name') ||
        html.contains('已完成任务点') ||
        RegExp(r'暂无章节|暂无目录|暂无内容').hasMatch(html);
    if (!hasMarkers) {
      return null;
    }

    int? completed;
    int? total;
    var progressTrusted = false;
    final progressMatch = _progressPattern.firstMatch(html);
    if (progressMatch != null) {
      final parsedDone = int.tryParse(progressMatch[1]!);
      final parsedTotal = int.tryParse(progressMatch[2]!);
      if (parsedDone != null &&
          parsedTotal != null &&
          parsedDone >= 0 &&
          parsedTotal >= parsedDone) {
        completed = parsedDone;
        total = parsedTotal;
        progressTrusted = true;
      }
    }

    final events = <({
      int offset,
      int level,
      String code,
      String title,
      ChapterTaskState state,
      int pending
    })>[];

    for (final m in _chapterPattern.allMatches(html)) {
      final code = m[1]!.trim();
      final title = ChaoxingExamParser.text(ChaoxingExamParser.entities(m[3]!));
      if (code.isEmpty || title.isEmpty) continue;
      events.add((
        offset: m.start,
        level: 0,
        code: code,
        title: title,
        state: ChapterTaskState.noTaskPoints,
        pending: 0,
      ));
    }

    for (final m in _sectionPattern.allMatches(html)) {
      final maxEnd = (m.start + 2200).clamp(0, html.length);
      var seg = html.substring(m.start, maxEnd);
      final liEnd = seg.indexOf('</li>');
      if (liEnd > 0) {
        seg = seg.substring(0, liEnd);
      }
      final numMatch = _sectionNumPattern.firstMatch(seg);
      if (numMatch == null) continue;
      final code = numMatch[1]!.trim();
      final title = ChaoxingExamParser.text(ChaoxingExamParser.entities(m[2]!));
      if (code.isEmpty || title.isEmpty) continue;
      late final ChapterTaskState state;
      var pending = 0;
      if (seg.contains('icon_yiwanc')) {
        state = ChapterTaskState.completed;
      } else {
        final mp = _pendingPointsPattern.firstMatch(seg);
        if (mp != null) {
          final parsed = int.tryParse(mp[1]!) ?? 1;
          state = ChapterTaskState.pendingPoints;
          pending = parsed.clamp(1, ChapterNode.maxPendingPoints);
        } else if (seg.contains('暂未开放')) {
          state = ChapterTaskState.locked;
        } else {
          state = ChapterTaskState.noTaskPoints;
        }
      }
      events.add((
        offset: m.start,
        level: 1,
        code: code,
        title: title,
        state: state,
        pending: pending,
      ));
    }

    events.sort((a, b) => a.offset.compareTo(b.offset));

    final seenBaseIds = <String, int>{};
    final sectionIds = <String>{};
    final nodes = <ChapterNode>[];
    for (final ev in events) {
      if (nodes.length >= CourseChapterSnapshot.maxNodes) break;
      final code = _truncate(ev.code, ChapterNode.maxCodeLength).trim();
      final title = _truncate(ev.title, ChapterNode.maxTitleLength).trim();
      if (code.isEmpty || title.isEmpty) continue;
      final baseId = _truncate(
        'cx:chapter:${course.courseId}:${course.clazzId}:${ev.level}:$code',
        ChapterNode.maxSectionIdLength,
      );
      var seq = seenBaseIds[baseId] ?? 0;
      late String sectionId;
      // Reserving room for the suffix can make distinct base IDs collide.
      do {
        seq++;
        final suffix = seq == 1 ? '' : '#$seq';
        final prefix =
            _truncate(baseId, ChapterNode.maxSectionIdLength - suffix.length);
        sectionId = '$prefix$suffix';
      } while (!sectionIds.add(sectionId));
      seenBaseIds[baseId] = seq;
      nodes.add(ChapterNode(
        sectionId: sectionId,
        level: ev.level,
        code: code,
        title: title,
        state: ev.state,
        pendingPoints: ev.pending,
      ));
    }

    final courseName =
        _truncate(course.courseName, CourseChapterSnapshot.maxCourseNameLength)
            .trim();
    return CourseChapterSnapshot(
      courseId: course.courseId,
      clazzId: course.clazzId,
      courseName: courseName.isEmpty ? '未命名课程' : courseName,
      completedPoints: completed,
      totalPoints: total,
      progressTrusted: progressTrusted,
      nodes: nodes,
      lastSyncedAt: now ?? DateTime.now(),
    );
  }

  static String _truncate(String value, int maxLength) =>
      value.length > maxLength ? value.substring(0, maxLength) : value;
}
