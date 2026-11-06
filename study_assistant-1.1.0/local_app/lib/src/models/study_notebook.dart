import 'dart:convert';
import 'assignment.dart';
import 'personal_workspace.dart';

DateTime? notebookDate(dynamic value) {
  if (value == null) return null;
  final raw = PersonalWorkspace.text(value, 40);
  final date = DateTime.tryParse(raw);
  if (date == null ||
      date.year < 2000 ||
      date.year > 2200 ||
      date.toUtc().toIso8601String() != raw) {
    PersonalWorkspace.bad();
  }
  return date;
}

class ManualEntry {
  const ManualEntry(
      {required this.id,
      required this.title,
      required this.kind,
      this.course = '',
      this.location = '',
      this.note = '',
      this.at,
      this.done = false,
      this.remind = false,
      this.minutes = 0});
  final String id, title, kind, course, location, note;
  final DateTime? at;
  final bool done, remind;
  final int minutes;
  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'kind': kind,
        'course': course,
        'location': location,
        'note': note,
        'at': at?.toUtc().toIso8601String(),
        'done': done,
        'remind': remind,
        'minutes': minutes
      };
  factory ManualEntry.fromJson(dynamic value) {
    final j = PersonalWorkspace.map(value, {
      'id',
      'title',
      'kind',
      'course',
      'location',
      'note',
      'at',
      'done',
      'remind',
      'minutes'
    });
    final at = notebookDate(j['at']);
    if (!{'todo', 'exam'}.contains(j['kind']) ||
        j['done'] is! bool ||
        j['remind'] is! bool ||
        j['minutes'] is! int ||
        j['minutes'] < 0 ||
        j['minutes'] > 1440 ||
        (j['kind'] == 'exam' && at == null) ||
        (j['remind'] == true && at == null)) {
      PersonalWorkspace.bad();
    }
    return ManualEntry(
        id: PersonalWorkspace.text(j['id'], 100),
        title: PersonalWorkspace.text(j['title'], 200),
        kind: j['kind'],
        course: PersonalWorkspace.text(j['course'], 200, empty: true),
        location: PersonalWorkspace.text(j['location'], 200, empty: true),
        note: PersonalWorkspace.text(j['note'], 10000, empty: true),
        at: at,
        done: j['done'],
        remind: j['remind'],
        minutes: j['minutes']);
  }
  ManualEntry completed(bool value) => ManualEntry(
      id: id,
      title: title,
      kind: kind,
      course: course,
      location: location,
      note: note,
      at: at,
      done: value,
      remind: remind,
      minutes: minutes);
}

class ArchivedAssignment {
  const ArchivedAssignment(
      this.id, this.title, this.course, this.status, this.deadline, this.note);
  final String id, title, course, status;
  final DateTime? deadline;
  final PersonalWork note;
  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'course': course,
        'status': status,
        'deadline': deadline?.toUtc().toIso8601String(),
        'personal': note.toJson(portable: true)
      };
  factory ArchivedAssignment.fromJson(dynamic value) {
    final j = PersonalWorkspace.map(
        value, {'id', 'title', 'course', 'status', 'deadline', 'personal'});
    if (!{
      'pending',
      'overdue',
      'returned',
      'unknown',
      'submitted',
      'completed',
      'reviewing',
      'graded'
    }.contains(j['status'])) {
      PersonalWorkspace.bad();
    }
    final note = PersonalWork.fromJson(j['personal']);
    if (note.files.isNotEmpty) PersonalWorkspace.bad();
    return ArchivedAssignment(
        PersonalWorkspace.text(j['id'], 500),
        PersonalWorkspace.text(j['title'], 2000),
        PersonalWorkspace.text(j['course'], 500),
        j['status'],
        notebookDate(j['deadline']),
        note);
  }
  bool get completed =>
      {'submitted', 'completed', 'reviewing', 'graded'}.contains(status);
}

class TermArchive {
  TermArchive(
      {required this.id,
      required this.label,
      required this.createdAt,
      required List<ArchivedAssignment> rows,
      required List<ManualEntry> entries,
      required List<DailyPlanItem> plans})
      : rows = List.unmodifiable(rows),
        entries = List.unmodifiable(entries),
        plans = List.unmodifiable(plans);
  final String id, label;
  final DateTime createdAt;
  final List<ArchivedAssignment> rows;
  final List<ManualEntry> entries;
  final List<DailyPlanItem> plans;
  factory TermArchive.capture(
          {required String id,
          required String label,
          required List<Assignment> rows,
          required PersonalWorkspace personal,
          required List<ManualEntry> entries}) =>
      TermArchive(
          id: id,
          label: label,
          createdAt: DateTime.now().toUtc(),
          rows: [
            for (final a in rows)
              ArchivedAssignment(
                  a.id,
                  a.title,
                  a.courseName,
                  a.status,
                  a.deadlineTrusted && !a.deadlineReadFailed
                      ? a.deadlineAt
                      : null,
                  PersonalWork.fromJson(
                      (personal.work[a.id] ?? const PersonalWork())
                          .toJson(portable: true)))
          ],
          entries: entries,
          plans: personal.plans);
  Map<String, dynamic> toJson() => {
        'id': id,
        'label': label,
        'createdAt': createdAt.toUtc().toIso8601String(),
        'rows': rows.map((v) => v.toJson()).toList(),
        'entries': entries.map((v) => v.toJson()).toList(),
        'plans': plans.map((v) => v.toJson()).toList()
      };
  factory TermArchive.fromJson(dynamic value) {
    final j = PersonalWorkspace.map(
        value, {'id', 'label', 'createdAt', 'rows', 'entries', 'plans'});
    final rows = PersonalWorkspace.list(j['rows'], 2000)
        .map(ArchivedAssignment.fromJson)
        .toList();
    final entries = PersonalWorkspace.list(j['entries'], 500)
        .map(ManualEntry.fromJson)
        .toList();
    if (rows.map((v) => v.id).toSet().length != rows.length ||
        entries.map((v) => v.id).toSet().length != entries.length) {
      PersonalWorkspace.bad();
    }
    final plans = PersonalWorkspace.fromJson(
        {...PersonalWorkspace().toJson(), 'plans': j['plans']}).plans;
    final at = notebookDate(j['createdAt']);
    if (at == null) PersonalWorkspace.bad();
    return TermArchive(
        id: PersonalWorkspace.text(j['id'], 100),
        label: PersonalWorkspace.text(j['label'], 80),
        createdAt: at,
        rows: rows,
        entries: entries,
        plans: plans);
  }
}

class StudyNotebook {
  StudyNotebook(
      {List<ManualEntry> entries = const [],
      List<TermArchive> terms = const []})
      : entries = List.unmodifiable(entries),
        terms = List.unmodifiable(terms);
  final List<ManualEntry> entries;
  final List<TermArchive> terms;
  Map<String, dynamic> toJson() => {
        'version': 1,
        'entries': entries.map((v) => v.toJson()).toList(),
        'terms': terms.map((v) => v.toJson()).toList()
      };
  String encode() => jsonEncode(toJson());
  factory StudyNotebook.decode(String raw) {
    if (raw.length > 4 * 1024 * 1024 ||
        utf8.encode(raw).length > 4 * 1024 * 1024) {
      PersonalWorkspace.bad();
    }
    return StudyNotebook.fromJson(jsonDecode(raw));
  }
  factory StudyNotebook.fromJson(dynamic value) {
    final j = PersonalWorkspace.map(value, {'version', 'entries', 'terms'});
    if (j['version'] is! int || j['version'] != 1) PersonalWorkspace.bad();
    final entries = PersonalWorkspace.list(j['entries'], 500)
        .map(ManualEntry.fromJson)
        .toList();
    final terms = PersonalWorkspace.list(j['terms'], 12)
        .map(TermArchive.fromJson)
        .toList();
    if (entries.map((v) => v.id).toSet().length != entries.length ||
        terms.map((v) => v.id).toSet().length != terms.length) {
      PersonalWorkspace.bad();
    }
    return StudyNotebook(entries: entries, terms: terms);
  }
  StudyNotebook withEntries(List<ManualEntry> value) =>
      StudyNotebook(entries: value, terms: terms);
  StudyNotebook withTerms(List<TermArchive> value) =>
      StudyNotebook(entries: entries, terms: value);
  StudyNotebook mergeMissing(StudyNotebook imported) => StudyNotebook(entries: [
        ...entries,
        ...imported.entries.where((v) => !entries.any((e) => e.id == v.id))
      ], terms: [
        ...terms,
        ...imported.terms.where((v) => !terms.any((e) => e.id == v.id))
      ]);
}
