import 'package:flutter_test/flutter_test.dart';
import 'package:study_assistant_mobile/src/models/sync_report.dart';
import 'package:study_assistant_mobile/src/services/account_identity.dart';
import 'package:study_assistant_mobile/src/services/assignment_session_coordinator.dart';

void main() {
  final previousHash = AccountIdentity.hash('previous');

  group('login transition', () {
    test('same account rotates native epoch and skips cross-account cleanup',
        () {
      final transition = AssignmentSessionTransition(
        account: ' previous ',
        previousAccount: ' previous',
        previousAccountHash: previousHash,
        previousNativeEpoch: 4,
      );
      expect(transition.account, 'previous');
      expect(transition.accountHash, previousHash);
      expect(transition.keepsNativeAccount, isTrue);
      expect(transition.changesLocalAccount, isFalse);
      expect(transition.releasesPreviousFiles, isFalse);
      expect(transition.retiresPreviousHistory, isFalse);
      expect(
        transition.rollback(nativeSwitched: true, previousPassword: 'old'),
        (
          native: NativeLoginRollback.keepRotatedEpoch,
          credentials: (account: ' previous', password: 'old'),
        ),
      );
    });

    test('switch retires valid previous history and restores the old identity',
        () {
      final transition = AssignmentSessionTransition(
        account: 'new',
        previousAccount: 'previous',
        previousAccountHash: previousHash,
        previousNativeEpoch: 4,
      );
      expect(transition.keepsNativeAccount, isFalse);
      expect(transition.nativeSwitchSourceHash, previousHash);
      expect(transition.changesLocalAccount, isTrue);
      expect(transition.releasesPreviousFiles, isTrue);
      expect(transition.retiresPreviousHistory, isTrue);
      expect(
        transition.rollback(nativeSwitched: true, previousPassword: 'old'),
        (
          native: NativeLoginRollback.switchBack,
          credentials: (account: 'previous', password: 'old'),
        ),
      );
      expect(
        transition.rollback(nativeSwitched: false, previousPassword: null),
        (native: NativeLoginRollback.none, credentials: null),
      );
    });

    test('missing native or credential snapshots clear only the affected side',
        () {
      final withoutHash = AssignmentSessionTransition(
        account: 'new',
        previousAccount: 'previous',
        previousAccountHash: null,
        previousNativeEpoch: 4,
      );
      expect(withoutHash.nativeSwitchSourceHash, previousHash);
      expect(withoutHash.retiresPreviousHistory, isFalse);
      expect(
        withoutHash.rollback(nativeSwitched: true, previousPassword: 'old'),
        (
          native: NativeLoginRollback.clearNewAccount,
          credentials: (account: 'previous', password: 'old'),
        ),
      );

      final withoutEpoch = AssignmentSessionTransition(
        account: 'new',
        previousAccount: 'previous',
        previousAccountHash: previousHash,
        previousNativeEpoch: 0,
      );
      expect(withoutEpoch.retiresPreviousHistory, isFalse);
      expect(
        withoutEpoch.rollback(nativeSwitched: true, previousPassword: null),
        (native: NativeLoginRollback.switchBack, credentials: null),
      );
      final firstLogin = AssignmentSessionTransition(
        account: 'new',
        previousAccount: null,
        previousAccountHash: null,
        previousNativeEpoch: 0,
      );
      expect(firstLogin.nativeSwitchSourceHash, isNull);
      expect(firstLogin.changesLocalAccount, isTrue);
      expect(firstLogin.releasesPreviousFiles, isFalse);
      expect(
        firstLogin.rollback(nativeSwitched: true, previousPassword: 'orphan'),
        (native: NativeLoginRollback.clearNewAccount, credentials: null),
      );
    });
  });

  test('backup restore requires an authenticated account', () {
    final accountFor = AssignmentSessionCoordinator.backupRestoreAccount;
    expect(accountFor(account: 'student', authenticated: true), 'student');
    expect(accountFor(account: 'student', authenticated: false), isNull);
    expect(accountFor(account: null, authenticated: true), isNull);
  });

  test('logout retains history-only detail and adds advice for other residues',
      () {
    const history = '提醒历史待清理';
    const widget = '退出时未能确认小组件内容已清除';
    final logoutError = AssignmentSessionCoordinator.logoutError;
    expect(
      logoutError(
        serviceWarnings: const [history, history],
        historyWarning: history,
        nativeCleanupPending: true,
        currentError: 'earlier error',
      ),
      history,
    );
    expect(
      logoutError(
        serviceWarnings: const [widget, history],
        historyWarning: history,
        nativeCleanupPending: false,
        currentError: null,
      ),
      '账号已退出，但部分提醒或桌面内容可能仍保留（提醒历史待清理）。请在系统中清除本应用通知并移除小组件。',
    );
    expect(
      logoutError(
        serviceWarnings: const [widget],
        historyWarning: null,
        nativeCleanupPending: false,
        currentError: null,
      ),
      '账号已退出，但部分提醒或桌面内容可能仍保留。请在系统中清除本应用通知并移除小组件。',
    );
  });

  test('pending native cleanup is the fallback after other logout errors', () {
    final logoutError = AssignmentSessionCoordinator.logoutError;
    expect(
      logoutError(
        serviceWarnings: const [],
        historyWarning: null,
        nativeCleanupPending: true,
        currentError: 'earlier error',
      ),
      'earlier error',
    );
    expect(
      logoutError(
        serviceWarnings: const [],
        historyWarning: null,
        nativeCleanupPending: true,
        currentError: null,
      ),
      '账号已退出，但旧账号的原生提醒清理尚未确认；应用会在下次启动或刷新时重试。',
    );
    expect(
      logoutError(
        serviceWarnings: const [],
        historyWarning: null,
        nativeCleanupPending: false,
        currentError: null,
      ),
      isNull,
    );
  });

  test('sync report recovery keeps durable data and full success independent',
      () {
    final at = DateTime.utc(2026, 11, 27, 12);
    final oldFull = at.subtract(const Duration(days: 1));
    final recover = AssignmentSessionCoordinator.recoverMissingSyncReport;
    final dataOnly = recover(
      attemptedAt: at,
      dataAt: at,
      durableFullAt: null,
      reportDamaged: false,
    );
    expect(dataOnly.phase, SyncPhase.partial);
    expect(dataOnly.lastDataSuccessAt, at.toLocal());
    expect(dataOnly.lastFullSuccessAt, isNull);
    expect(dataOnly.issues.single.message, contains('记录缺失'));

    final damaged = recover(
      attemptedAt: null,
      dataAt: oldFull,
      durableFullAt: at,
      reportDamaged: true,
    );
    expect(damaged.phase, SyncPhase.partial);
    expect(damaged.lastDataSuccessAt, at);
    expect(damaged.lastFullSuccessAt, at);
    expect(damaged.issues.single.message, contains('记录损坏'));

    final attemptOnly = recover(
      attemptedAt: at,
      dataAt: null,
      durableFullAt: null,
      reportDamaged: false,
    );
    expect(attemptOnly.phase, SyncPhase.failed);
    expect(attemptOnly.issues.single.message, contains('没有可确认的数据写入'));
    expect(
      recover(
        attemptedAt: null,
        dataAt: null,
        durableFullAt: null,
        reportDamaged: false,
      ).phase,
      SyncPhase.idle,
    );
  });
}
