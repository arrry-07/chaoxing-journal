import 'dart:convert';

class PersonalStep {
  const PersonalStep(this.text, {this.done = false});
  final String text;
  final bool done;
  Map<String, dynamic> toJson() => {'text': text, 'done': done};
}

class PersonalLink {
  const PersonalLink(this.label, this.url);
  final String label, url;
  Map<String, dynamic> toJson() => {'label': label, 'url': url};
}

class PersonalWork {
  const PersonalWork(
      {this.note = '',
      this.steps = const [],
      this.links = const [],
      this.files = const []});
  final String note;
  final List<PersonalStep> steps;
  final List<PersonalLink> links, files;
  Map<String, dynamic> toJson({bool portable = false}) => {
        'note': note,
        'steps': steps.map((s) => s.toJson()).toList(),
        'links': links.map((s) => s.toJson()).toList(),
        'files': portable ? [] : files.map((s) => s.toJson()).toList()
      };
  factory PersonalWork.fromJson(dynamic value) {
    final j = PersonalWorkspace.map(value, {'note', 'steps', 'links', 'files'});
    final note = PersonalWorkspace.text(j['note'], 10000, empty: true);
    final steps = PersonalWorkspace.list(j['steps'], 50).map((v) {
      final s = PersonalWorkspace.map(v, {'text', 'done'});
      if (s['done'] is! bool) PersonalWorkspace.bad();
      return PersonalStep(PersonalWorkspace.text(s['text'], 200),
          done: s['done'] as bool);
    }).toList();
    List<PersonalLink> refs(dynamic v, int max, bool file) =>
        PersonalWorkspace.list(v, max).map((v) {
          final s = PersonalWorkspace.map(v, {'label', 'url'});
          final url = PersonalWorkspace.text(s['url'], 4096);
          if (file
              ? !PersonalWorkspace.validFile(url)
              : !PersonalWorkspace.validUrl(url)) {
            PersonalWorkspace.bad();
          }
          return PersonalLink(PersonalWorkspace.text(s['label'], 200), url);
        }).toList();
    return PersonalWork(
        note: note,
        steps: List.unmodifiable(steps),
        links: List.unmodifiable(refs(j['links'], 20, false)),
        files: List.unmodifiable(refs(j['files'], 10, true)));
  }
}

class DailyPlanItem {
  const DailyPlanItem(this.assignmentId, this.day, this.minutes,
      {this.done = false});
  final String assignmentId, day;
  final int minutes;
  final bool done;
  Map<String, dynamic> toJson() =>
      {'id': assignmentId, 'day': day, 'minutes': minutes, 'done': done};
}

class PersonalWorkspace {
  PersonalWorkspace(
      {Map<String, PersonalWork> work = const {},
      List<DailyPlanItem> plans = const [],
      this.summaryEnabled = false,
      this.summaryHour = 20,
      this.summaryMinute = 0})
      : work = Map.unmodifiable(work),
        plans = List.unmodifiable(plans);
  final Map<String, PersonalWork> work;
  final List<DailyPlanItem> plans;
  final bool summaryEnabled;
  final int summaryHour, summaryMinute;
  static Never bad() => throw const FormatException('个人记录格式无效或超出上限');
  static Map<String, dynamic> map(dynamic v, Set<String> keys) {
    if (v is! Map ||
        v.length != keys.length ||
        v.keys.any((k) => !keys.contains(k))) {
      bad();
    }
    return Map<String, dynamic>.from(v);
  }

  static String text(dynamic v, int max, {bool empty = false}) {
    if (v is! String || v.length > max || (!empty && v.trim().isEmpty)) bad();
    return v;
  }

  static List list(dynamic v, int max) {
    if (v is! List || v.length > max) bad();
    return v;
  }

  static bool validUrl(String raw) {
    final u = Uri.tryParse(raw);
    return raw.trim() == raw &&
        !RegExp(r'[\x00-\x20\\]').hasMatch(raw) &&
        u != null &&
        u.scheme == 'https' &&
        u.host.isNotEmpty &&
        u.userInfo.isEmpty &&
        u.port == 443;
  }

  static bool validFile(String raw) {
    final u = Uri.tryParse(raw);
    return u != null &&
        u.scheme == 'content' &&
        u.host.isNotEmpty &&
        raw.length <= 4096;
  }

  static String dayKey(DateTime at) {
    final d = at.toUtc().add(const Duration(hours: 8));
    return '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
  }

  static bool validDay(String s) {
    final d = DateTime.tryParse('${s}T00:00:00Z');
    return RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(s) &&
        d != null &&
        d.year >= 2000 &&
        d.year <= 2200 &&
        d.toIso8601String().startsWith(s);
  }

  Map<String, dynamic> toJson({bool portable = false}) => {
        'version': 1,
        'work': {
          for (final e in work.entries)
            e.key: e.value.toJson(portable: portable)
        },
        'plans': plans.map((p) => p.toJson()).toList(),
        'summaryEnabled': summaryEnabled,
        'summaryHour': summaryHour,
        'summaryMinute': summaryMinute
      };
  String encode({bool portable = false}) =>
      jsonEncode(toJson(portable: portable));
  factory PersonalWorkspace.decode(String raw) {
    if (raw.length > 2 * 1024 * 1024 ||
        utf8.encode(raw).length > 2 * 1024 * 1024) {
      bad();
    }
    return PersonalWorkspace.fromJson(jsonDecode(raw));
  }
  factory PersonalWorkspace.fromJson(dynamic value) {
    final j = map(value, {
      'version',
      'work',
      'plans',
      'summaryEnabled',
      'summaryHour',
      'summaryMinute'
    });
    if (j['version'] is! int ||
        j['version'] != 1 ||
        j['work'] is! Map ||
        (j['work'] as Map).length > 500 ||
        j['summaryEnabled'] is! bool ||
        j['summaryHour'] is! int ||
        j['summaryMinute'] is! int ||
        j['summaryHour'] < 0 ||
        j['summaryHour'] > 23 ||
        j['summaryMinute'] < 0 ||
        j['summaryMinute'] > 59) {
      bad();
    }
    final work = <String, PersonalWork>{};
    for (final e in (j['work'] as Map).entries) {
      work[text(e.key, 500)] = PersonalWork.fromJson(e.value);
    }
    final seen = <String>{};
    final plans = <DailyPlanItem>[];
    for (final v in list(j['plans'], 500)) {
      final p = map(v, {'id', 'day', 'minutes', 'done'});
      final id = text(p['id'], 500), day = text(p['day'], 10);
      if (!validDay(day) ||
          p['minutes'] is! int ||
          p['minutes'] < 1 ||
          p['minutes'] > 1440 ||
          p['done'] is! bool ||
          !seen.add('$day:$id')) {
        bad();
      }
      plans.add(
          DailyPlanItem(id, day, p['minutes'] as int, done: p['done'] as bool));
    }
    return PersonalWorkspace(
        work: work,
        plans: plans,
        summaryEnabled: j['summaryEnabled'] as bool,
        summaryHour: j['summaryHour'] as int,
        summaryMinute: j['summaryMinute'] as int);
  }
  PersonalWorkspace withWork(String id, PersonalWork value) =>
      PersonalWorkspace(
          work: {...work, id: value},
          plans: plans,
          summaryEnabled: summaryEnabled,
          summaryHour: summaryHour,
          summaryMinute: summaryMinute);
  PersonalWorkspace withPlans(List<DailyPlanItem> values) => PersonalWorkspace(
      work: work,
      plans: values,
      summaryEnabled: summaryEnabled,
      summaryHour: summaryHour,
      summaryMinute: summaryMinute);
  PersonalWorkspace withSummary(bool enabled, int hour, int minute) =>
      PersonalWorkspace(
          work: work,
          plans: plans,
          summaryEnabled: enabled,
          summaryHour: hour,
          summaryMinute: minute);
}
