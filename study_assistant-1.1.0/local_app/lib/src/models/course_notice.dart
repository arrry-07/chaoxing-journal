import 'dart:convert';
import 'personal_workspace.dart';

class CourseNotice {
  const CourseNotice({
    required this.id,
    this.courseId,
    this.clazzId,
    required this.courseName,
    this.senderName = '',
    required this.title,
    this.summary = '',
    this.publishedAt,
    this.publishedTrusted = false,
    this.extractedEventAt,
    this.extractedEventTrusted = false,
    this.platformUnread = false,
    this.localRead = false,
    this.linkedManualEntryId,
    required this.lastSyncedAt,
  });

  final String id;
  final String? courseId;
  final String? clazzId;
  final String courseName;
  final String senderName;
  final String title;
  final String summary;
  final DateTime? publishedAt;
  final bool publishedTrusted;
  final DateTime? extractedEventAt;
  final bool extractedEventTrusted;
  final bool platformUnread;
  final bool localRead;
  final String? linkedManualEntryId;
  final DateTime lastSyncedAt;

  String? get courseKey =>
      courseId != null && clazzId != null ? '$courseId:$clazzId' : null;

  CourseNotice copyWith({
    String? courseId,
    String? clazzId,
    String? courseName,
    String? senderName,
    String? title,
    String? summary,
    DateTime? publishedAt,
    bool? publishedTrusted,
    DateTime? extractedEventAt,
    bool? extractedEventTrusted,
    bool? platformUnread,
    bool? localRead,
    String? linkedManualEntryId,
    bool clearLinkedManualEntryId = false,
    DateTime? lastSyncedAt,
  }) =>
      CourseNotice(
        id: id,
        courseId: courseId ?? this.courseId,
        clazzId: clazzId ?? this.clazzId,
        courseName: courseName ?? this.courseName,
        senderName: senderName ?? this.senderName,
        title: title ?? this.title,
        summary: summary ?? this.summary,
        publishedAt: publishedAt ?? this.publishedAt,
        publishedTrusted: publishedTrusted ?? this.publishedTrusted,
        extractedEventAt: extractedEventAt ?? this.extractedEventAt,
        extractedEventTrusted:
            extractedEventTrusted ?? this.extractedEventTrusted,
        platformUnread: platformUnread ?? this.platformUnread,
        localRead: localRead ?? this.localRead,
        linkedManualEntryId: clearLinkedManualEntryId
            ? null
            : (linkedManualEntryId ?? this.linkedManualEntryId),
        lastSyncedAt: lastSyncedAt ?? this.lastSyncedAt,
      );

  Map<String, dynamic> toJson({bool portable = false}) => {
        'id': id,
        'courseId': courseId,
        'clazzId': clazzId,
        'courseName': courseName,
        'senderName': senderName,
        'title': title,
        'summary': summary,
        'publishedAt': publishedAt?.toUtc().toIso8601String(),
        'publishedTrusted': portable ? false : publishedTrusted,
        'extractedEventAt': extractedEventAt?.toUtc().toIso8601String(),
        'extractedEventTrusted': portable ? false : extractedEventTrusted,
        'platformUnread': platformUnread,
        'localRead': localRead,
        'linkedManualEntryId': linkedManualEntryId,
        'lastSyncedAt': lastSyncedAt.toUtc().toIso8601String(),
      };

  static final RegExp _idPattern = RegExp(r'^cx:notice:[0-9a-f]{64}$');
  static final RegExp _identityTokenBad = RegExp(r'[:\s\x00-\x1f\x7f]');

  static String? _nullableIdentity(dynamic value) {
    if (value == null) return null;
    final text = PersonalWorkspace.text(value, 120);
    if (_identityTokenBad.hasMatch(text)) PersonalWorkspace.bad();
    return text;
  }

  static DateTime? _nullableUtcDate(dynamic value) {
    if (value == null) return null;
    final raw = PersonalWorkspace.text(value, 40);
    if (!RegExp(r'(?:[zZ]|[+-]\d{2}:?\d{2})$').hasMatch(raw)) {
      PersonalWorkspace.bad();
    }
    final parsed = DateTime.tryParse(raw);
    if (parsed == null ||
        parsed.year < 1970 ||
        parsed.year > 2200 ||
        parsed.toUtc().toIso8601String() != raw) {
      PersonalWorkspace.bad();
    }
    return parsed.toLocal();
  }

  factory CourseNotice.fromJson(dynamic value) {
    final j = PersonalWorkspace.map(value, {
      'id',
      'courseId',
      'clazzId',
      'courseName',
      'senderName',
      'title',
      'summary',
      'publishedAt',
      'publishedTrusted',
      'extractedEventAt',
      'extractedEventTrusted',
      'platformUnread',
      'localRead',
      'linkedManualEntryId',
      'lastSyncedAt',
    });
    final id = PersonalWorkspace.text(j['id'], 100);
    if (!_idPattern.hasMatch(id)) PersonalWorkspace.bad();
    final courseId = _nullableIdentity(j['courseId']);
    final clazzId = _nullableIdentity(j['clazzId']);
    if ((courseId == null) != (clazzId == null)) PersonalWorkspace.bad();

    final publishedAt = _nullableUtcDate(j['publishedAt']);
    final extractedEventAt = _nullableUtcDate(j['extractedEventAt']);
    final lastSyncedAt = _nullableUtcDate(j['lastSyncedAt']);
    if (lastSyncedAt == null) PersonalWorkspace.bad();

    if (j['publishedTrusted'] is! bool ||
        j['extractedEventTrusted'] is! bool ||
        j['platformUnread'] is! bool ||
        j['localRead'] is! bool) {
      PersonalWorkspace.bad();
    }
    final publishedTrusted = j['publishedTrusted'] as bool;
    final extractedEventTrusted = j['extractedEventTrusted'] as bool;
    if ((publishedTrusted && publishedAt == null) ||
        (extractedEventTrusted && extractedEventAt == null)) {
      PersonalWorkspace.bad();
    }

    final rawEntryId = j['linkedManualEntryId'];
    final linkedManualEntryId =
        rawEntryId == null ? null : PersonalWorkspace.text(rawEntryId, 100);

    return CourseNotice(
      id: id,
      courseId: courseId,
      clazzId: clazzId,
      courseName: PersonalWorkspace.text(j['courseName'], 200),
      senderName: PersonalWorkspace.text(j['senderName'], 120, empty: true),
      title: PersonalWorkspace.text(j['title'], 500),
      summary: PersonalWorkspace.text(j['summary'], 4000, empty: true),
      publishedAt: publishedAt,
      publishedTrusted: publishedTrusted,
      extractedEventAt: extractedEventAt,
      extractedEventTrusted: extractedEventTrusted,
      platformUnread: j['platformUnread'] as bool,
      localRead: j['localRead'] as bool,
      linkedManualEntryId: linkedManualEntryId,
      lastSyncedAt: lastSyncedAt,
    );
  }
}

class CourseNoticeCollection {
  CourseNoticeCollection({List<CourseNotice> items = const []})
      : items = List.unmodifiable(_normalize(items));

  static const int maxItems = 300;
  static const int maxBytes = 2 * 1024 * 1024;

  final List<CourseNotice> items;

  int get unreadCount => items.where((item) => !item.localRead).length;

  static List<CourseNotice> _normalize(List<CourseNotice> source) {
    final deduped = <String, CourseNotice>{};
    for (final item in source) {
      final prev = deduped[item.id];
      if (prev == null || !item.lastSyncedAt.isBefore(prev.lastSyncedAt)) {
        deduped[item.id] = item;
      }
    }
    final list = deduped.values.toList()
      ..sort((a, b) {
        final atA = a.publishedAt ?? a.lastSyncedAt;
        final atB = b.publishedAt ?? b.lastSyncedAt;
        final byTime = atB.compareTo(atA);
        return byTime != 0 ? byTime : a.id.compareTo(b.id);
      });
    return list.length > maxItems ? list.sublist(0, maxItems) : list;
  }

  CourseNoticeCollection mergeIncoming(List<CourseNotice> incoming) {
    final byId = {for (final item in items) item.id: item};
    for (final item in incoming) {
      final prior = byId[item.id];
      byId[item.id] = prior == null
          ? item
          : item.copyWith(
              localRead: prior.localRead,
              linkedManualEntryId: prior.linkedManualEntryId,
            );
    }
    return CourseNoticeCollection(items: byId.values.toList());
  }

  CourseNoticeCollection markLocalRead(String id, {bool read = true}) =>
      CourseNoticeCollection(items: [
        for (final item in items)
          if (item.id == id) item.copyWith(localRead: read) else item,
      ]);

  CourseNoticeCollection markAllLocalRead() => CourseNoticeCollection(
        items: [
          for (final item in items)
            item.localRead ? item : item.copyWith(localRead: true),
        ],
      );

  CourseNoticeCollection bindManualEntry(String noticeId, String entryId) =>
      CourseNoticeCollection(items: [
        for (final item in items)
          if (item.id == noticeId)
            item.copyWith(linkedManualEntryId: entryId, localRead: true)
          else
            item,
      ]);

  CourseNoticeCollection mergeImported(
    CourseNoticeCollection imported, {
    Set<String> validEntryIds = const {},
  }) {
    final byId = {for (final item in items) item.id: item};
    for (final item in imported.items) {
      if (byId.containsKey(item.id)) continue;
      final keepLink = item.linkedManualEntryId != null &&
          validEntryIds.contains(item.linkedManualEntryId);
      byId[item.id] =
          keepLink ? item : item.copyWith(clearLinkedManualEntryId: true);
    }
    return CourseNoticeCollection(items: byId.values.toList());
  }

  Map<String, dynamic> toJson({bool portable = false}) => {
        'version': 1,
        'items': items.map((e) => e.toJson(portable: portable)).toList(),
      };

  String encode({bool portable = false}) =>
      jsonEncode(toJson(portable: portable));

  factory CourseNoticeCollection.decode(String raw) {
    if (raw.length > maxBytes || utf8.encode(raw).length > maxBytes) {
      PersonalWorkspace.bad();
    }
    return CourseNoticeCollection.fromJson(jsonDecode(raw));
  }

  factory CourseNoticeCollection.fromJson(dynamic value) {
    final j = PersonalWorkspace.map(value, {'version', 'items'});
    if (j['version'] is! int || j['version'] != 1) PersonalWorkspace.bad();
    final parsed = PersonalWorkspace.list(j['items'], maxItems)
        .map(CourseNotice.fromJson)
        .toList();
    if (parsed.map((e) => e.id).toSet().length != parsed.length) {
      PersonalWorkspace.bad();
    }
    return CourseNoticeCollection(items: parsed);
  }
}
