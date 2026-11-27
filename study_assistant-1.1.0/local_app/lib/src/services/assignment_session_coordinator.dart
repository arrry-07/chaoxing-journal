import '../models/sync_report.dart';
import 'account_identity.dart';

enum NativeLoginRollback { none, keepRotatedEpoch, switchBack, clearNewAccount }

/// Plans the local and native account transitions after a successful login.
class AssignmentSessionTransition {
  AssignmentSessionTransition({
    required String account,
    required this.previousAccount,
    required this.previousAccountHash,
    required int previousNativeEpoch,
  })  : account = account.trim(),
        accountHash = AccountIdentity.hash(account),
        _previousNativeEpoch = previousNativeEpoch;

  final String account;
  final String accountHash;
  final String? previousAccount;
  final String? previousAccountHash;
  final int _previousNativeEpoch;

  bool get keepsNativeAccount => previousAccountHash == accountHash;

  String? get nativeSwitchSourceHash {
    final previous = previousAccount;
    return previousAccountHash ??
        (previous == null ? null : AccountIdentity.hash(previous));
  }

  bool get changesLocalAccount => previousAccount?.trim() != account;
  bool get releasesPreviousFiles =>
      previousAccount != null && changesLocalAccount;
  bool get retiresPreviousHistory =>
      previousAccountHash != null &&
      !keepsNativeAccount &&
      _previousNativeEpoch > 0;

  /// Restore only the identity data actually present before login.
  ({
    NativeLoginRollback native,
    ({String account, String password})? credentials,
  }) rollback({
    required bool nativeSwitched,
    required String? previousPassword,
  }) {
    final previous = previousAccount;
    final native = !nativeSwitched
        ? NativeLoginRollback.none
        : previous == null || previousAccountHash == null
            ? NativeLoginRollback.clearNewAccount
            : keepsNativeAccount
                ? NativeLoginRollback.keepRotatedEpoch
                : NativeLoginRollback.switchBack;
    return (
      native: native,
      credentials: previous == null || previousPassword == null
          ? null
          : (account: previous, password: previousPassword),
    );
  }
}

/// User-visible recovery outcomes for account-scoped operations.
abstract final class AssignmentSessionCoordinator {
  static String? backupRestoreAccount({
    required String? account,
    required bool authenticated,
  }) =>
      authenticated ? account : null;

  static String? logoutError({
    required List<String> serviceWarnings,
    required String? historyWarning,
    required bool nativeCleanupPending,
    required String? currentError,
  }) {
    var result = currentError;
    if (serviceWarnings.isNotEmpty) {
      final hasOtherWarnings =
          serviceWarnings.any((warning) => warning != historyWarning);
      final historyDetail = historyWarning == null ? '' : '（$historyWarning）';
      result = hasOtherWarnings
          ? '账号已退出，但部分提醒或桌面内容可能仍保留$historyDetail。请在系统中清除本应用通知并移除小组件。'
          : historyWarning;
    }
    if (nativeCleanupPending) {
      result ??= '账号已退出，但旧账号的原生提醒清理尚未确认；应用会在下次启动或刷新时重试。';
    }
    return result;
  }

  static SyncReport recoverMissingSyncReport({
    required DateTime? attemptedAt,
    required DateTime? dataAt,
    required DateTime? durableFullAt,
    required bool reportDamaged,
  }) {
    final recoveredDataAt = dataAt?.toLocal();
    final lastDataAt = recoveredDataAt == null ||
            (durableFullAt != null && durableFullAt.isAfter(recoveredDataAt))
        ? durableFullAt
        : recoveredDataAt;
    final hasDurableData = lastDataAt != null;
    final hasAttempt = attemptedAt != null;
    final hasRecoverableState = hasDurableData || hasAttempt || reportDamaged;
    final issue = reportDamaged
        ? '上次同步结果记录损坏；已依据本机数据时间恢复可确认部分，请重新同步核对'
        : hasDurableData
            ? '上次同步结果记录缺失；已依据本机数据时间恢复可确认部分，请重新同步核对'
            : '上次同步尝试记录存在，但结果报告缺失且没有可确认的数据写入，请重新同步';
    // The data mirror advances on partial writes. Only the repository can
    // provide a confirmed full-success timestamp.
    return SyncReport(
      phase: hasDurableData
          ? SyncPhase.partial
          : hasRecoverableState
              ? SyncPhase.failed
              : SyncPhase.idle,
      attemptedAt: attemptedAt,
      lastDataSuccessAt: lastDataAt,
      lastFullSuccessAt: durableFullAt,
      issues: hasRecoverableState
          ? [SyncIssue(SyncIssueKind.storage, issue, stage: 'persistence')]
          : const [],
    );
  }
}
