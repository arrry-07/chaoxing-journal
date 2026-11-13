import '../models/assignment.dart';

class AssignmentStatistics {
  AssignmentStatistics(Iterable<Assignment> records, {DateTime? now}) {
    final referenceTime = now ?? DateTime.now();
    for (final a in records) {
      switch (a.deadlineBucketAt(referenceTime)) {
        case AssignmentDeadlineBucket.completed:
          completed++;
        case AssignmentDeadlineBucket.overdue:
          expired++;
        case AssignmentDeadlineBucket.notExpiredWithDeadline:
        case AssignmentDeadlineBucket.confirmedNoDeadline:
          pending++;
        case AssignmentDeadlineBucket.unconfirmed:
          if (a.isPendingConfirmed) {
            pending++;
          } else {
            unknown++;
          }
      }
    }
  }
  int completed = 0, pending = 0, expired = 0, unknown = 0;
  int get total => completed + pending + expired + unknown;
  List<int> get counts => [completed, pending, expired, unknown];
  // Keep the headline completion rate conventionally rounded, independent of
  // how unfinished work is split. Apportion the remaining labels to total 100;
  // the ring angles always use the exact counts.
  List<int> get percentages {
    if (total == 0) return [0, 0, 0, 0];
    final out = counts.map((n) => n * 100 ~/ total).toList();
    out[0] = (completed * 100 / total).round();
    final order = [1, 2, 3]..sort((a, b) {
        final c = (counts[b] * 100 % total).compareTo(counts[a] * 100 % total);
        return c == 0 ? a.compareTo(b) : c;
      });
    final remainder = 100 - out.reduce((a, b) => a + b);
    for (var i = 0; i < remainder; i++) {
      out[order[i]]++;
    }
    return out;
  }
}
