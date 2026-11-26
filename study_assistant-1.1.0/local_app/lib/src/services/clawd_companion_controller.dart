import 'dart:async';

import 'package:flutter/widgets.dart';

import '../models/display_preferences.dart';
import '../models/sync_report.dart';
import 'assignment_store.dart';
import 'interaction_feedback_service.dart';

enum JournalPixelBuddyMood {
  idle,
  syncing,
  dueToday,
  allClear,
}

enum ClawdPrimaryTab {
  home('/assignments'),
  calendar('/calendar'),
  stats('/stats'),
  profile('/profile');

  const ClawdPrimaryTab(this.routePath);
  final String routePath;
}

enum ClawdTransientPose {
  none,
  wave,
  doubleStar,
  tsundere,
  petting,
  grabbed,
  landing,
  cheer,
}

enum ClawdProactiveBucket {
  greeting,
  allClear,
  dueToday,
}

@immutable
class ClawdSpeechMessage {
  const ClawdSpeechMessage({
    required this.id,
    required this.text,
    required this.tab,
    required this.createdAt,
    this.isTsundere = false,
    this.fromSliver = false,
  });

  final int id;
  final String text;
  final ClawdPrimaryTab tab;
  final DateTime createdAt;
  final bool isTsundere;
  final bool fromSliver;
}

@immutable
class ClawdPageContextSnapshot {
  const ClawdPageContextSnapshot({
    required this.tab,
    this.dueToday = 0,
    this.dueIn3Days = 0,
    this.overdueCount = 0,
    this.completedToday = 0,
    this.calendarSelectedDayCount = 0,
    this.calendarMonthCount = 0,
    this.calendarSelectedIsToday = true,
    this.calendarShowsWholeMonth = false,
    this.statsCompletionPercent = 0,
    this.statsTotalCount = 0,
    this.statsPendingCount = 0,
    this.followedCourseCount = 0,
    this.activeAgendaCount = 0,
  });

  final ClawdPrimaryTab tab;
  final int dueToday;
  final int dueIn3Days;
  final int overdueCount;
  final int completedToday;
  final int calendarSelectedDayCount;
  final int calendarMonthCount;
  final bool calendarSelectedIsToday;
  final bool calendarShowsWholeMonth;
  final int statsCompletionPercent;
  final int statsTotalCount;
  final int statsPendingCount;
  final int followedCourseCount;
  final int activeAgendaCount;

  String get routePath => tab.routePath;
}

String journalBuddyTapWhisper({
  required int dueToday,
  required int dueIn3Days,
  required int completedToday,
  required int tapCount,
  int comboCount = 1,
}) {
  final List<String> options;
  if (comboCount >= 3) {
    options = const <String>[
      '满格元气发射给你！',
      '比个小心心，超级棒！',
      '连击啦，今天状态拉满',
      '贴贴打气，万事顺意！',
    ];
  } else if (comboCount == 2) {
    options = <String>[
      if (dueToday > 0) ...[
        '嘿咻，一起清空待办！',
        '双击加满今日干劲啦',
        '小爪给你打气，冲呀',
      ] else if (completedToday > 0 || dueIn3Days == 0) ...[
        '好耶，节奏超稳的！',
        '双击收下今日小红花',
        '开心蹦两下，继续保持',
      ] else ...[
        '趁现在偷闲充个电！',
        '提前准备超省心的呀',
        '双击打气，稳稳拿捏',
      ],
    ];
  } else {
    options = <String>[
      if (dueToday > 0) ...[
        dueToday > 99 ? '今日待办较多，先挑急的' : '今日待办$dueToday项，稳步推进',
        dueToday > 99 ? '先清今日要紧事项吧' : '先清今日这$dueToday项吧',
        if (dueIn3Days > dueToday && dueIn3Days <= 99) '三日内共$dueIn3Days项，提前看',
        '我在盯着截止时间呢',
      ] else if (completedToday > 0) ...[
        '今日已清空，喝口水歇会儿',
        completedToday > 99 ? '今日打卡满满，真棒' : '今日已打卡$completedToday项，真棒',
        if (dueIn3Days > 0)
          dueIn3Days > 99 ? '三日内有多项，提前瞄一眼' : '三日内还有$dueIn3Days项，瞄一眼',
        '今天轻松啦，保持节奏',
      ] else if (dueIn3Days > 0) ...[
        dueIn3Days > 99 ? '三日内有多项，提前瞄一眼' : '三日内还有$dueIn3Days项，瞄一眼',
        '今日暂无急单，先备后续',
        '我在盯着截止时间呢',
      ] else ...[
        '眼前清清爽爽，真好',
        '暂无急单，喝口水歇会儿',
        '有新课业我会盯紧的',
      ],
    ];
  }
  final index = (tapCount < 0 ? -tapCount : tapCount) % options.length;
  return options[index];
}

class ClawdCompanionController extends ChangeNotifier {
  ClawdCompanionController({
    DateTime Function()? clock,
    this.onBubbleTapExtension,
  }) : _clock = clock ?? DateTime.now;

  static const Duration comboWindow = Duration(milliseconds: 1200);
  static const Duration defaultBubbleDuration = Duration(milliseconds: 2500);
  static const Duration proactiveCooldown = Duration(minutes: 15);
  static const Duration syncFrameInterval = Duration(milliseconds: 180);

  /// Single source of truth for whether store sync/warning state should block
  /// interactive Clawd combos/bubbles across AppShell and primary tabs.
  static bool resolveHasBlockingSyncNotice(
    AssignmentStore store, {
    bool localBusy = false,
  }) {
    final isSyncing = localBusy ||
        store.isLoading ||
        store.syncReport.phase == SyncPhase.running;
    if (isSyncing) return false;
    final phase = store.syncReport.phase;
    return phase == SyncPhase.failed ||
        phase == SyncPhase.partial ||
        store.hasNonQuietServiceWarning ||
        store.recoveryWarning != null ||
        store.operationError != null;
  }

  static const List<String> _tsundereLines = <String>[
    '别戳啦，像素脑瓜要扁掉啦！',
    '再戳要收小鱼干当加班费啦！',
    '哼，手速这么快，待办清完没？',
    '好啦好啦，本像素盯紧进度呢！',
  ];

  static const List<String> _petLines = <String>[
    '呼噜呼噜…再摸一下下也行',
    '充能完毕，陪你把这页清掉',
  ];

  final DateTime Function() _clock;
  ValueChanged<ClawdPageContextSnapshot>? onBubbleTapExtension;

  final ValueNotifier<int> syncTick = ValueNotifier<int>(0);

  JournalPixelBuddyMood _mood = JournalPixelBuddyMood.idle;
  ClawdTransientPose _transientPose = ClawdTransientPose.none;
  int _transientPulse = 0;
  int _celebratePulse = 0;

  int _comboCount = 0;
  int _tapCount = 0;
  int _petCount = 0;
  int _grabCount = 0;
  int _bubbleSeq = 0;

  ClawdPrimaryTab _lastVisitedTab = ClawdPrimaryTab.home;
  ClawdSpeechMessage? _activeBubble;
  ClawdPageContextSnapshot? _latestSnapshot;

  DisplayPreferences _displayPrefs = const DisplayPreferences();
  bool _appResumed = true;
  bool _tickerEnabled = true;
  bool _reducedMotion = false;
  bool _isSyncing = false;
  bool _hasSyncErrorOrPending = false;
  bool _disposed = false;
  int? _previousHomeDueToday;

  final Map<ClawdProactiveBucket, DateTime> _proactiveLastShown = {};

  Timer? _comboResetTimer;
  Timer? _bubbleTimer;
  Timer? _syncTimer;
  Timer? _poseResetTimer;
  Timer? _proactiveDelayTimer;

  JournalPixelBuddyMood get mood => _mood;
  ClawdTransientPose get transientPose => _transientPose;
  int get transientPulse => _transientPulse;
  int get celebratePulse => _celebratePulse;
  int get comboCount => _comboCount;
  int get tapCount => _tapCount;
  int get petCount => _petCount;
  int get grabCount => _grabCount;
  ClawdPrimaryTab get lastVisitedTab => _lastVisitedTab;
  ClawdSpeechMessage? get activeBubble => _activeBubble;
  ClawdPageContextSnapshot? get latestSnapshot => _latestSnapshot;
  DisplayPreferences get displayPrefs => _displayPrefs;
  bool get appResumed => _appResumed;
  bool get tickerEnabled => _tickerEnabled;
  bool get reducedMotion => _reducedMotion;
  bool get isSyncing => _isSyncing;
  bool get hasSyncErrorOrPending => _hasSyncErrorOrPending;

  bool get _canRunMotion =>
      !_disposed &&
      _appResumed &&
      _tickerEnabled &&
      !_reducedMotion &&
      _displayPrefs.showPixelBuddy;

  bool get _canInteract =>
      !_disposed &&
      _appResumed &&
      _tickerEnabled &&
      _displayPrefs.showPixelBuddy &&
      !_isSyncing &&
      !_hasSyncErrorOrPending;

  void syncContextQuietly({
    DisplayPreferences? displayPrefs,
    bool? appResumed,
    bool? tickerEnabled,
    bool? reducedMotion,
    bool? isSyncing,
    bool? hasSyncErrorOrPending,
    JournalPixelBuddyMood? mood,
    ClawdPageContextSnapshot? snapshot,
  }) {
    updateEnvironment(
      displayPrefs: displayPrefs,
      appResumed: appResumed,
      tickerEnabled: tickerEnabled,
      reducedMotion: reducedMotion,
      isSyncing: isSyncing,
      hasSyncErrorOrPending: hasSyncErrorOrPending,
      mood: mood,
      snapshot: snapshot,
      notify: false,
    );
  }

  void updateEnvironment({
    DisplayPreferences? displayPrefs,
    bool? appResumed,
    bool? tickerEnabled,
    bool? reducedMotion,
    bool? isSyncing,
    bool? hasSyncErrorOrPending,
    JournalPixelBuddyMood? mood,
    ClawdPageContextSnapshot? snapshot,
    bool notify = true,
  }) {
    if (_disposed) return;
    var changed = false;

    if (displayPrefs != null &&
            displayPrefs.clawdVisibility != _displayPrefs.clawdVisibility ||
        displayPrefs != null &&
            (displayPrefs.soundEnabled != _displayPrefs.soundEnabled ||
                displayPrefs.hapticsEnabled != _displayPrefs.hapticsEnabled)) {
      _displayPrefs = displayPrefs;
      changed = true;
    } else if (displayPrefs != null) {
      _displayPrefs = displayPrefs;
    }
    if (appResumed != null && appResumed != _appResumed) {
      _appResumed = appResumed;
      changed = true;
    }
    if (tickerEnabled != null && tickerEnabled != _tickerEnabled) {
      _tickerEnabled = tickerEnabled;
      changed = true;
    }
    if (reducedMotion != null && reducedMotion != _reducedMotion) {
      _reducedMotion = reducedMotion;
      changed = true;
    }
    if (isSyncing != null && isSyncing != _isSyncing) {
      _isSyncing = isSyncing;
      changed = true;
    }
    if (hasSyncErrorOrPending != null &&
        hasSyncErrorOrPending != _hasSyncErrorOrPending) {
      _hasSyncErrorOrPending = hasSyncErrorOrPending;
      changed = true;
    }
    if (mood != null && mood != _mood) {
      _mood = mood;
      changed = true;
    }
    if (snapshot != null) {
      _latestSnapshot = snapshot;
      _lastVisitedTab = snapshot.tab;
      if (snapshot.tab == ClawdPrimaryTab.home) {
        final prev = _previousHomeDueToday;
        _previousHomeDueToday = snapshot.dueToday;
        if (prev != null &&
            prev > 0 &&
            snapshot.dueToday == 0 &&
            snapshot.completedToday > 0 &&
            _canInteract &&
            !_reducedMotion &&
            _activeBubble == null) {
          maybeEmitProactiveBubble(justClearedToday: true, notify: notify);
        }
      }
    }

    final shouldClearInteractive = !_appResumed ||
        !_tickerEnabled ||
        !_displayPrefs.showPixelBuddy ||
        _isSyncing ||
        _hasSyncErrorOrPending;
    if (shouldClearInteractive) {
      if (_clearComboInternal()) changed = true;
      if (_clearBubbleInternal()) changed = true;
      if (clearTransientPose(notify: false)) changed = true;
      _proactiveDelayTimer?.cancel();
      _proactiveDelayTimer = null;
    } else if (_reducedMotion) {
      if (_clearComboInternal()) changed = true;
      _proactiveDelayTimer?.cancel();
      _proactiveDelayTimer = null;
      if (clearTransientPose(notify: false)) changed = true;
    }

    _reconcileSyncTimer();
    _reconcileProactiveSchedule();

    if (changed && notify) {
      notifyListeners();
    }
  }

  void _reconcileSyncTimer() {
    final shouldTick = _canRunMotion && _isSyncing;
    if (!shouldTick) {
      _syncTimer?.cancel();
      _syncTimer = null;
      return;
    }
    _syncTimer ??= Timer(syncFrameInterval, _onSyncTimerTick);
  }

  void _onSyncTimerTick() {
    _syncTimer = null;
    if (!_canRunMotion || !_isSyncing) return;
    syncTick.value = (syncTick.value + 1) & 0x3fffffff;
    if (syncTick.value % 2 == 1) {
      InteractionFeedback.trigger(
        _displayPrefs,
        kind: InteractionSoundKind.clawdSyncTick,
      );
    }
    _syncTimer = Timer(syncFrameInterval, _onSyncTimerTick);
  }

  void _reconcileProactiveSchedule() {
    final canSchedule = _canInteract &&
        !_reducedMotion &&
        _activeBubble == null &&
        _transientPose == ClawdTransientPose.none &&
        _latestSnapshot != null &&
        _latestSnapshot!.tab == ClawdPrimaryTab.home;
    if (!canSchedule) {
      _proactiveDelayTimer?.cancel();
      _proactiveDelayTimer = null;
      return;
    }
    _proactiveDelayTimer ??= Timer(
      const Duration(milliseconds: 3200),
      () {
        _proactiveDelayTimer = null;
        maybeEmitProactiveBubble();
      },
    );
  }

  void handleTabChanged(ClawdPrimaryTab tab) {
    if (_disposed) return;
    final tabChanged = _lastVisitedTab != tab;
    _lastVisitedTab = tab;
    if (tabChanged && _activeBubble != null && _activeBubble!.tab != tab) {
      _clearBubbleInternal();
      notifyListeners();
    }
  }

  void registerTap({
    ClawdPageContextSnapshot? snapshot,
    bool fromSliver = false,
  }) {
    if (snapshot != null) {
      _latestSnapshot = snapshot;
      _lastVisitedTab = snapshot.tab;
    }
    final activeSnapshot = _latestSnapshot ??
        const ClawdPageContextSnapshot(tab: ClawdPrimaryTab.home);
    if (activeSnapshot.tab != ClawdPrimaryTab.home &&
        !_displayPrefs.showClawdOnSecondaryTabs) {
      return;
    }
    if (!_canInteract) {
      if (_clearComboInternal()) notifyListeners();
      return;
    }

    _proactiveDelayTimer?.cancel();
    _proactiveDelayTimer = null;
    _tapCount++;

    final int effectiveCombo;
    if (_reducedMotion) {
      _clearComboInternal();
      effectiveCombo = 1;
    } else {
      _comboResetTimer?.cancel();
      _comboCount++;
      effectiveCombo = _comboCount;
      _comboResetTimer = Timer(comboWindow, () {
        _comboResetTimer = null;
        if (_disposed) return;
        _comboCount = 0;
        notifyListeners();
      });
    }

    final isTsundere = effectiveCombo >= 3;
    final InteractionSoundKind soundKind;
    final ClawdTransientPose nextPose;
    if (effectiveCombo >= 3) {
      soundKind = InteractionSoundKind.clawdCombo3;
      nextPose = ClawdTransientPose.tsundere;
    } else if (effectiveCombo == 2) {
      soundKind = InteractionSoundKind.clawdCombo2;
      nextPose = ClawdTransientPose.doubleStar;
    } else {
      soundKind = InteractionSoundKind.clawdJump;
      nextPose = ClawdTransientPose.wave;
    }

    InteractionFeedback.trigger(_displayPrefs, kind: soundKind);
    if (!_reducedMotion) {
      _setTransientPose(nextPose, const Duration(milliseconds: 520));
    }

    final text = _buildTapLine(
      snapshot: activeSnapshot,
      tapIndex: _tapCount - 1,
      comboCount: effectiveCombo,
    );
    _showBubble(
      text: text,
      tab: activeSnapshot.tab,
      isTsundere: isTsundere,
      fromSliver: fromSliver,
    );
  }

  void startPet({ClawdPageContextSnapshot? snapshot}) {
    if (snapshot != null) {
      _latestSnapshot = snapshot;
      _lastVisitedTab = snapshot.tab;
    }
    if (!_canInteract || _reducedMotion) return;
    _proactiveDelayTimer?.cancel();
    _proactiveDelayTimer = null;
    _clearComboInternal();
    _petCount++;
    _poseResetTimer?.cancel();
    _poseResetTimer = null;
    _transientPose = ClawdTransientPose.petting;
    _transientPulse++;
    InteractionFeedback.trigger(
      _displayPrefs,
      kind: InteractionSoundKind.clawdPet,
    );
    final line = _petLines[(_petCount - 1) % _petLines.length];
    _showBubble(
      text: line,
      tab: (_latestSnapshot?.tab) ?? _lastVisitedTab,
      isTsundere: false,
    );
  }

  void endPet() {
    if (_disposed) return;
    if (_transientPose != ClawdTransientPose.petting) return;
    if (_reducedMotion || !_canInteract) {
      clearTransientPose(notify: true);
      return;
    }
    _setTransientPose(
      ClawdTransientPose.petting,
      const Duration(milliseconds: 600),
    );
    notifyListeners();
  }

  void startGrab({ClawdPageContextSnapshot? snapshot}) {
    if (snapshot != null) {
      _latestSnapshot = snapshot;
      _lastVisitedTab = snapshot.tab;
    }
    if (!_canInteract || _reducedMotion) return;
    _proactiveDelayTimer?.cancel();
    _proactiveDelayTimer = null;
    _clearComboInternal();
    _grabCount++;
    _poseResetTimer?.cancel();
    _poseResetTimer = null;
    _transientPose = ClawdTransientPose.grabbed;
    _transientPulse++;
    InteractionFeedback.trigger(
      _displayPrefs,
      kind: InteractionSoundKind.clawdGrab,
    );
    _showBubble(
      text: '呜哇！快放我下来，够不着字啦！',
      tab: (_latestSnapshot?.tab) ?? _lastVisitedTab,
      isTsundere: true,
    );
  }

  void landFromGrab() {
    if (_disposed) return;
    if (_reducedMotion || !_displayPrefs.showPixelBuddy) {
      _transientPose = ClawdTransientPose.none;
      notifyListeners();
      return;
    }
    InteractionFeedback.trigger(
      _displayPrefs,
      kind: InteractionSoundKind.clawdLand,
    );
    _setTransientPose(
      ClawdTransientPose.landing,
      const Duration(milliseconds: 320),
    );
    _showBubble(
      text: '噗咚，安全着陆！',
      tab: (_latestSnapshot?.tab) ?? _lastVisitedTab,
      isTsundere: false,
      duration: const Duration(milliseconds: 1800),
    );
  }

  void triggerCheer({bool withSound = true}) {
    if (!_canRunMotion || _isSyncing) return;
    _celebratePulse++;
    if (withSound) {
      InteractionFeedback.trigger(
        _displayPrefs,
        kind: InteractionSoundKind.clawdCheer,
      );
    }
    _setTransientPose(
      ClawdTransientPose.cheer,
      const Duration(milliseconds: 460),
    );
    notifyListeners();
  }

  bool maybeEmitProactiveBubble({
    DateTime? now,
    bool justClearedToday = false,
    bool notify = true,
  }) {
    final snapshot = _latestSnapshot;
    if (!_canInteract ||
        _reducedMotion ||
        snapshot == null ||
        _activeBubble != null ||
        _transientPose != ClawdTransientPose.none) {
      return false;
    }
    if (snapshot.tab != ClawdPrimaryTab.home) return false;

    final current = (now ?? _clock()).toLocal();
    bool cooledDown(ClawdProactiveBucket bucket) {
      final last = _proactiveLastShown[bucket];
      if (last == null) return true;
      final elapsed = current.difference(last);
      return !elapsed.isNegative && elapsed >= proactiveCooldown;
    }

    ClawdProactiveBucket? pickedBucket;
    String? text;

    if ((justClearedToday ||
            (snapshot.dueToday == 0 && snapshot.completedToday > 0)) &&
        cooledDown(ClawdProactiveBucket.allClear)) {
      pickedBucket = ClawdProactiveBucket.allClear;
      text = '今日待办清空啦，真棒！';
    } else if (_isMorningWindow(current) &&
        cooledDown(ClawdProactiveBucket.greeting)) {
      pickedBucket = ClawdProactiveBucket.greeting;
      text = snapshot.dueToday > 0
          ? '早安，今日有${snapshot.dueToday}项待办哦'
          : '早安，今天节奏很轻快呀';
    } else if (_isLateNightWindow(current) &&
        cooledDown(ClawdProactiveBucket.greeting)) {
      pickedBucket = ClawdProactiveBucket.greeting;
      text = '夜深啦，忙完这一笔早点休息';
    } else if (snapshot.dueToday > 0 &&
        cooledDown(ClawdProactiveBucket.dueToday)) {
      pickedBucket = ClawdProactiveBucket.dueToday;
      text = snapshot.dueToday > 99
          ? '今日临期较多，记得先收尾'
          : '今日还剩${snapshot.dueToday}项临期课业';
    }

    if (pickedBucket == null || text == null) return false;
    _proactiveLastShown[pickedBucket] = current;
    _showBubble(
      text: text,
      tab: ClawdPrimaryTab.home,
      isTsundere: false,
      notify: notify,
    );
    return true;
  }

  static bool _isMorningWindow(DateTime local) {
    final mins = local.hour * 60 + local.minute;
    return mins >= 6 * 60 && mins <= 10 * 60 + 30;
  }

  static bool _isLateNightWindow(DateTime local) {
    final mins = local.hour * 60 + local.minute;
    return mins >= 22 * 60 + 30 || mins <= 4 * 60 + 30;
  }

  void onBubbleTapped() {
    if (_disposed) return;
    final hook = onBubbleTapExtension;
    final snapshot = _latestSnapshot;
    if (hook != null && snapshot != null) {
      hook(snapshot);
      return;
    }
    dismissBubble();
  }

  void dismissBubble() {
    if (_disposed) return;
    if (_clearBubbleInternal()) {
      notifyListeners();
    }
  }

  /// Idempotently cancels any pending transient-pose timer and resets
  /// [transientPose] to [ClawdTransientPose.none]. Pass `notify: false`
  /// when calling from widget lifecycle hooks invoked during `build()`.
  bool clearTransientPose({bool notify = true}) {
    _poseResetTimer?.cancel();
    _poseResetTimer = null;
    if (_transientPose == ClawdTransientPose.none) return false;
    _transientPose = ClawdTransientPose.none;
    if (notify && !_disposed) {
      notifyListeners();
    }
    return true;
  }

  void resetForAccountChange() {
    if (_disposed) return;
    _comboResetTimer?.cancel();
    _comboResetTimer = null;
    _bubbleTimer?.cancel();
    _bubbleTimer = null;
    _syncTimer?.cancel();
    _syncTimer = null;
    _poseResetTimer?.cancel();
    _poseResetTimer = null;
    _proactiveDelayTimer?.cancel();
    _proactiveDelayTimer = null;

    _comboCount = 0;
    _tapCount = 0;
    _petCount = 0;
    _grabCount = 0;
    _activeBubble = null;
    _transientPose = ClawdTransientPose.none;
    _proactiveLastShown.clear();
    _previousHomeDueToday = null;
    syncTick.value = 0;
    notifyListeners();
  }

  void _setTransientPose(ClawdTransientPose pose, Duration duration) {
    _poseResetTimer?.cancel();
    _transientPose = pose;
    _transientPulse++;
    _poseResetTimer = Timer(duration, () {
      _poseResetTimer = null;
      if (_disposed) return;
      if (_transientPose == pose) {
        _transientPose = ClawdTransientPose.none;
        notifyListeners();
      }
    });
  }

  void _showBubble({
    required String text,
    required ClawdPrimaryTab tab,
    required bool isTsundere,
    bool fromSliver = false,
    Duration duration = defaultBubbleDuration,
    bool notify = true,
  }) {
    _bubbleTimer?.cancel();
    _bubbleSeq++;
    _activeBubble = ClawdSpeechMessage(
      id: _bubbleSeq,
      text: text,
      tab: tab,
      createdAt: _clock(),
      isTsundere: isTsundere,
      fromSliver: fromSliver,
    );
    _bubbleTimer = Timer(duration, () {
      _bubbleTimer = null;
      if (_disposed) return;
      if (_activeBubble != null) {
        _activeBubble = null;
        notifyListeners();
      }
    });
    if (notify) notifyListeners();
  }

  String _buildTapLine({
    required ClawdPageContextSnapshot snapshot,
    required int tapIndex,
    required int comboCount,
  }) {
    if (comboCount >= 3) {
      return _tsundereLines[
          (comboCount - 3 + tapIndex) % _tsundereLines.length];
    }
    switch (snapshot.tab) {
      case ClawdPrimaryTab.home:
        return journalBuddyTapWhisper(
          dueToday: snapshot.dueToday,
          dueIn3Days: snapshot.dueIn3Days,
          completedToday: snapshot.completedToday,
          tapCount: tapIndex,
          comboCount: comboCount,
        );
      case ClawdPrimaryTab.calendar:
        if (snapshot.calendarShowsWholeMonth) {
          final monthCount = snapshot.calendarMonthCount;
          final options = monthCount > 0
              ? <String>[
                  '本月共有$monthCount项日程，排好节奏',
                  '看着月历排兵布阵真稳',
                ]
              : const <String>[
                  '本月暂无排期，适合提前预习',
                  '月历清清爽爽，真好',
                ];
          return options[tapIndex % options.length];
        }
        final dayCount = snapshot.calendarSelectedDayCount;
        final dayLabel = snapshot.calendarSelectedIsToday ? '今天' : '这天';
        final options = dayCount > 0
            ? <String>[
                '$dayLabel有$dayCount项安排，稳步清完',
                '盯紧$dayLabel这$dayCount项就行',
              ]
            : <String>[
                '$dayLabel空空的，可以歇口气',
                '$dayLabel暂无到期，先充个电',
              ];
        return options[tapIndex % options.length];
      case ClawdPrimaryTab.stats:
        if (snapshot.statsTotalCount == 0) {
          return '暂无统计记录，同步后再来看看';
        }
        final pct = snapshot.statsCompletionPercent;
        final pending = snapshot.statsPendingCount;
        final options = pending > 0
            ? <String>[
                '当前完成率$pct%，还有$pending项待处理',
                '已拿下$pct%啦，再清$pending项！',
              ]
            : <String>[
                '完成率$pct%，本范围全部搞定！',
                '统计全绿啦，保持这股劲头',
              ];
        return options[tapIndex % options.length];
      case ClawdPrimaryTab.profile:
        final courses = snapshot.followedCourseCount;
        final agenda = snapshot.activeAgendaCount;
        if (courses == 0 && agenda == 0) {
          return '同步课程后，手帐马上就位';
        }
        final options = <String>[
          '已关注$courses门课，$agenda项待办进行中',
          agenda > 0 ? '还有$agenda项个人待办陪你盯着' : '已关注$courses门课，手帐整理得真好',
        ];
        return options[tapIndex % options.length];
    }
  }

  bool _clearComboInternal() {
    _comboResetTimer?.cancel();
    _comboResetTimer = null;
    if (_comboCount == 0) return false;
    _comboCount = 0;
    return true;
  }

  bool _clearBubbleInternal() {
    _bubbleTimer?.cancel();
    _bubbleTimer = null;
    if (_activeBubble == null) return false;
    _activeBubble = null;
    return true;
  }

  @override
  void dispose() {
    _disposed = true;
    _comboResetTimer?.cancel();
    _comboResetTimer = null;
    _bubbleTimer?.cancel();
    _bubbleTimer = null;
    _syncTimer?.cancel();
    _syncTimer = null;
    _poseResetTimer?.cancel();
    _poseResetTimer = null;
    _proactiveDelayTimer?.cancel();
    _proactiveDelayTimer = null;
    syncTick.dispose();
    super.dispose();
  }
}

class ClawdCompanionScope extends InheritedNotifier<ClawdCompanionController> {
  const ClawdCompanionScope({
    super.key,
    required ClawdCompanionController controller,
    required super.child,
  }) : super(notifier: controller);

  static ClawdCompanionController? maybeOf(BuildContext context) => context
      .dependOnInheritedWidgetOfExactType<ClawdCompanionScope>()
      ?.notifier;

  static ClawdCompanionController of(BuildContext context) {
    final controller = maybeOf(context);
    assert(controller != null, 'No ClawdCompanionScope found in context');
    return controller!;
  }
}
