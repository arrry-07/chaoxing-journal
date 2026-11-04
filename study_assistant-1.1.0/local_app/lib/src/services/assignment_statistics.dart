import '../models/assignment.dart';

class AssignmentStatistics {
  AssignmentStatistics(Iterable<Assignment> records) {
    for (final a in records) {
      if (a.isCompleted) {
        completed++;
      } else if (a.isPendingConfirmed) {
        pending++;
      } else {
        unknown++;
      }
    }
  }
  int completed = 0, pending = 0, unknown = 0;
  int get total => completed + pending + unknown;
  List<int> get counts => [completed, pending, unknown];
  // Largest remainders keep displayed percentages additive without distorting angles.
  List<int> get percentages {
    if (total == 0) return [0, 0, 0];
    final out = counts.map((n) => n * 100 ~/ total).toList();
    final order = [0, 1, 2]..sort((a, b) {
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
