import 'package:flutter/material.dart';

import '../../app/journal.dart';
import '../../models/display_preferences.dart';
import '../../models/home_filters.dart';
import '../../models/personal_workspace.dart';
import '../../models/sync_report.dart';
import '../../services/clawd_companion_controller.dart';
import '../../services/home_course_filter.dart';
import '../../services/home_sync_presentation.dart';
import '../../services/home_upcoming_exam.dart';
import 'clawd_title_stage.dart';
import 'home_action_bar.dart';
import 'home_filter_sheet.dart';
import 'home_manual_sections.dart';
import 'journal_grouped_card.dart';
import 'journal_pixel_buddy.dart';

class HomeAmbientGlowPainter extends CustomPainter {
  const HomeAmbientGlowPainter({
    required this.primaryGlow,
    required this.warmGlow,
    required this.fade,
  });

  final Color primaryGlow;
  final Color warmGlow;
  final double fade;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty || fade <= 0.01) return;

    final baseAlpha = (primaryGlow.a * fade).clamp(0.0, 1.0);
    if (baseAlpha <= 0.001) return;

    final rect = Offset.zero & size;
    final paint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        stops: const [0.0, 0.36, 0.72, 1.0],
        colors: [
          primaryGlow.withValues(alpha: baseAlpha),
          primaryGlow.withValues(alpha: baseAlpha * 0.56),
          primaryGlow.withValues(alpha: baseAlpha * 0.16),
          primaryGlow.withValues(alpha: 0.0),
        ],
      ).createShader(rect);
    canvas.drawRect(rect, paint);
  }

  @override
  bool shouldRepaint(covariant HomeAmbientGlowPainter oldDelegate) =>
      oldDelegate.primaryGlow != primaryGlow ||
      oldDelegate.warmGlow != warmGlow ||
      oldDelegate.fade != fade;
}

class HomeDayHeading extends StatelessWidget {
  const HomeDayHeading({
    super.key,
    required this.label,
    this.top = 12,
    this.bottom = 8,
    this.tone = HomeDayHeadingTone.normal,
    this.badge,
  });

  final String label;
  final double top;
  final double bottom;
  final HomeDayHeadingTone tone;
  final String? badge;

  @override
  Widget build(BuildContext context) {
    final journal = Journal.of(context);
    final textColor = switch (tone) {
      HomeDayHeadingTone.overdue => journal.muted,
      HomeDayHeadingTone.undated => journal.ochre,
      HomeDayHeadingTone.today => journal.ink,
      HomeDayHeadingTone.normal => journal.muted,
    };
    final baseStyle = journal.dayHeading.copyWith(
      color: textColor,
      fontSize: 14,
    );
    final date = RegExp(r'^(\d{4}年)?(\d{1,2}月\d{1,2}日)(.*)$').firstMatch(label);
    final Widget labelWidget = date == null
        ? Text(label, style: baseStyle)
        : Text.rich(
            TextSpan(children: [
              if (date[1] != null)
                TextSpan(
                  text: date[1],
                  style: baseStyle.copyWith(fontWeight: FontWeight.w500),
                ),
              TextSpan(
                text: date[2],
                style: baseStyle.copyWith(fontWeight: FontWeight.w700),
              ),
              TextSpan(
                text: date[3],
                style: baseStyle.copyWith(fontWeight: FontWeight.w400),
              ),
            ]),
            style: baseStyle,
          );
    return Padding(
      padding: EdgeInsets.only(top: top, bottom: bottom, left: 2),
      child: Row(
        children: [
          Flexible(child: labelWidget),
          if (badge != null) ...[
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
              decoration: BoxDecoration(
                color: tone == HomeDayHeadingTone.overdue
                    ? journal.parchment
                    : journal.sage,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                badge!,
                style: journal.metadata.copyWith(
                  fontSize: 11,
                  height: 1.2,
                  fontWeight: FontWeight.w600,
                  color: tone == HomeDayHeadingTone.overdue
                      ? journal.muted
                      : journal.ink,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class HomeUpcomingExamStrip extends StatelessWidget {
  const HomeUpcomingExamStrip({
    super.key,
    required this.upcomingExam,
    required this.inExamView,
    required this.onTap,
  });

  final HomeUpcomingExam upcomingExam;
  final bool inExamView;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final journal = Journal.of(context);
    return Semantics(
      button: true,
      label: '${upcomingExam.label}，点击${inExamView ? '返回全部课业' : '查看考试筛选视图'}',
      onTap: onTap,
      child: Material(
        color: inExamView ? journal.sage : journal.parchment,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(
            color: inExamView ? journal.sageBorder : journal.rule,
            width: 0.8,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          key: const ValueKey('home-upcoming-exam-strip'),
          onTap: onTap,
          enableFeedback: false,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 44),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: ExcludeSemantics(
                child: Row(
                  children: [
                    Icon(
                      Icons.school_outlined,
                      size: 16,
                      color: inExamView ? journal.accent : journal.muted,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        upcomingExam.label,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: journal.metadata.copyWith(
                          color: journal.ink,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    if (inExamView)
                      Text(
                        '返回',
                        style: journal.metadata.copyWith(
                          color: journal.accent,
                          fontWeight: FontWeight.w600,
                        ),
                      )
                    else
                      Icon(
                        Icons.chevron_right_rounded,
                        size: 18,
                        color: journal.muted,
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class HomeRecoveryHeader extends StatelessWidget {
  const HomeRecoveryHeader({
    super.key,
    required this.scopeLabel,
    required this.count,
    required this.onExit,
  });

  final String scopeLabel;
  final int count;
  final VoidCallback onExit;

  @override
  Widget build(BuildContext context) {
    final journal = Journal.of(context);
    return Column(
      key: const ValueKey('assignment-recovery-scope'),
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 44),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Icon(Icons.filter_alt_outlined, size: 17, color: journal.muted),
              const SizedBox(width: 8),
              Expanded(
                child: Wrap(
                  spacing: 6,
                  runSpacing: 2,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(
                      scopeLabel,
                      style: journal.entryTitle.copyWith(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Text(
                      '· 共 $count 项',
                      style: journal.metadata.copyWith(
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              TextButton(
                style: TextButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  foregroundColor: journal.ink,
                  minimumSize: const Size(48, 40),
                  tapTargetSize: MaterialTapTargetSize.padded,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                ),
                onPressed: onExit,
                child: const Text('返回全部'),
              ),
            ],
          ),
        ),
        const SizedBox(height: 4),
        Divider(height: 1, thickness: 0.8, color: journal.rule),
      ],
    );
  }
}

class HomeEmptyStateCard extends StatelessWidget {
  const HomeEmptyStateCard({
    super.key,
    required this.icon,
    required this.message,
    this.actions = const [],
  });

  final IconData icon;
  final String message;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    final journal = Journal.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 18),
      child: JournalGroupedCard(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 30),
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: journal.parchment,
                  shape: BoxShape.circle,
                ),
                alignment: Alignment.center,
                child: Icon(icon, size: 22, color: journal.muted),
              ),
              const SizedBox(height: 14),
              Text(
                message,
                textAlign: TextAlign.center,
                style: journal.metadata.copyWith(
                  color: journal.ink,
                  fontSize: 14.5,
                ),
              ),
              if (actions.isNotEmpty) ...[
                const SizedBox(height: 18),
                Wrap(
                  alignment: WrapAlignment.center,
                  spacing: 10,
                  runSpacing: 8,
                  children: actions,
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

class HomeTitleHeaderRow extends StatelessWidget {
  const HomeTitleHeaderRow({
    super.key,
    required this.controller,
    required this.showPixelBuddy,
    required this.busy,
    required this.reduceMotion,
    required this.recoveryActive,
    required this.syncErrorOrPending,
    required this.themeMode,
    required this.buddyMood,
    required this.homeSnapshot,
    required this.stageAnchor,
    required this.onOpenAgenda,
    required this.onRefresh,
    required this.onCycleTheme,
    required this.onOpenMoreMenu,
  });

  final ClawdCompanionController controller;
  final bool showPixelBuddy;
  final bool busy;
  final bool reduceMotion;
  final bool recoveryActive;
  final bool syncErrorOrPending;
  final JournalThemeMode themeMode;
  final JournalPixelBuddyMood buddyMood;
  final ClawdPageContextSnapshot homeSnapshot;
  final ValueNotifier<ClawdStageAnchor> stageAnchor;
  final VoidCallback onOpenAgenda;
  final VoidCallback onRefresh;
  final VoidCallback onCycleTheme;
  final void Function(BuildContext anchorContext) onOpenMoreMenu;

  @override
  Widget build(BuildContext context) {
    final journal = Journal.of(context);

    Widget action(String label, Widget button) => Stack(
          alignment: Alignment.topCenter,
          children: [
            button,
            Positioned(
              bottom: 2,
              child: IgnorePointer(
                child: ExcludeSemantics(
                  child: Text(
                    label,
                    style: journal.metadata.copyWith(
                      fontSize: 11,
                      height: 1,
                    ),
                  ),
                ),
              ),
            ),
          ],
        );

    final actionsRow = Row(mainAxisSize: MainAxisSize.min, children: [
      if (!recoveryActive)
        action(
          '待办',
          IconButton(
            key: const ValueKey('home-agenda-entry'),
            tooltip: '个人待办与考试',
            padding: const EdgeInsets.only(bottom: 12),
            iconSize: 21,
            constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
            onPressed: onOpenAgenda,
            icon: const Icon(Icons.checklist_rounded),
          ),
        ),
      action(
        '刷新',
        IconButton(
          enableFeedback: false,
          tooltip: '刷新作业',
          padding: const EdgeInsets.only(bottom: 12),
          iconSize: 21,
          constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
          onPressed: busy ? null : onRefresh,
          icon: busy
              ? reduceMotion
                  ? Icon(Icons.hourglass_top_rounded,
                      size: 19, color: journal.ink)
                  : SizedBox.square(
                      dimension: 19,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: journal.ink,
                      ),
                    )
              : const Icon(Icons.sync_rounded),
        ),
      ),
      if (!recoveryActive)
        action(
          '主题',
          IconButton(
            key: const ValueKey('home-theme-toggle'),
            enableFeedback: false,
            padding: const EdgeInsets.only(bottom: 12),
            iconSize: 21,
            constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
            tooltip: '切换主题（当前：${themeMode.label}）',
            icon: Icon(switch (themeMode) {
              JournalThemeMode.system => Icons.brightness_auto_outlined,
              JournalThemeMode.light => Icons.light_mode_outlined,
              JournalThemeMode.dark => Icons.dark_mode_outlined,
            }),
            onPressed: onCycleTheme,
          ),
        ),
      action(
        '更多',
        Builder(
          builder: (moreContext) => IconButton(
            key: const ValueKey('home-more-menu'),
            tooltip: '更多',
            padding: const EdgeInsets.only(bottom: 12),
            iconSize: 21,
            constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
            onPressed: () => onOpenMoreMenu(moreContext),
            icon: const Icon(Icons.more_horiz_rounded),
          ),
        ),
      ),
    ]);

    return LayoutBuilder(
      builder: (context, constraints) {
        final screenWidth = MediaQuery.sizeOf(context).width;
        final largeText = JournalLayout.isLargeText(context);
        final buddySize = ClawdTitleStage.resolvedBuddySize(context);
        final allowStageMotion = showPixelBuddy &&
            !reduceMotion &&
            !recoveryActive &&
            !largeText &&
            screenWidth >= 350.0 &&
            constraints.maxWidth >= 316.0;
        final roofHeadroom = ClawdTitleStage.roofHeadroomFor(
          allowStageMotion: allowStageMotion,
          buddySize: buddySize,
        );
        final titleStage = AnimatedBuilder(
          animation: controller,
          builder: (context, _) => ClawdTitleStage(
            title: '课业手记',
            titleStyle: journal.display,
            controller: controller,
            showBuddy: showPixelBuddy,
            buddySize: buddySize,
            interactive: !busy && !syncErrorOrPending,
            allowStageMotion: allowStageMotion,
            snapshotBuilder: () => homeSnapshot,
            anchorNotifier: stageAnchor,
            moodOverride: buddyMood,
          ),
        );
        if (!largeText && constraints.maxWidth >= 300) {
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: titleStage),
              const SizedBox(width: 8),
              Padding(
                padding: EdgeInsets.only(top: roofHeadroom),
                child: actionsRow,
              ),
            ],
          );
        }
        return Wrap(
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            ConstrainedBox(
              constraints: BoxConstraints(maxWidth: constraints.maxWidth),
              child: titleStage,
            ),
            actionsRow,
          ],
        );
      },
    );
  }
}

class HomeSyncStatusRow extends StatelessWidget {
  const HomeSyncStatusRow({
    super.key,
    required this.statusRowKey,
    required this.sync,
    required this.syncPhase,
    required this.statusText,
    required this.syncStage,
    required this.syncBusyWithBuddy,
    required this.reduceMotion,
    required this.busy,
    required this.showDueSummary,
    required this.dueSummary,
    required this.nearDueActive,
    required this.controller,
    required this.onRetrySync,
    required this.onOpenSyncIssues,
    required this.onToggleNearDueFilter,
  });

  final GlobalKey statusRowKey;
  final HomeSyncPresentation sync;
  final SyncPhase syncPhase;
  final String statusText;
  final dynamic syncStage;
  final bool syncBusyWithBuddy;
  final bool reduceMotion;
  final bool busy;
  final bool showDueSummary;
  final HomeDueSummary dueSummary;
  final bool nearDueActive;
  final ClawdCompanionController controller;
  final VoidCallback onRetrySync;
  final VoidCallback onOpenSyncIssues;
  final VoidCallback onToggleNearDueFilter;

  @override
  Widget build(BuildContext context) {
    final journal = Journal.of(context);
    return KeyedSubtree(
      key: statusRowKey,
      child: LayoutBuilder(builder: (context, constraints) {
        final compactSummary =
            constraints.maxWidth <= 360 || JournalLayout.isLargeText(context);
        final summaryLabel = dueSummary.label(compact: compactSummary);
        final statusIcon = sync.gentle
            ? Icons.wifi_off_rounded
            : syncPhase == SyncPhase.failed
                ? Icons.error_outline_rounded
                : syncPhase == SyncPhase.partial
                    ? Icons.info_outline_rounded
                    : Icons.schedule_rounded;
        final statusColor = sync.gentle
            ? journal.muted
            : syncPhase == SyncPhase.failed
                ? journal.berry
                : syncPhase == SyncPhase.partial
                    ? journal.ochre
                    : journal.muted;
        final VoidCallback? onSyncTap =
            sync.gentle && sync.action == HomeSyncAction.retry
                ? (busy ? null : onRetrySync)
                : sync.action == HomeSyncAction.none
                    ? null
                    : onOpenSyncIssues;
        final showChevron = sync.action != HomeSyncAction.none && !sync.gentle;

        final effectiveStatusText = syncBusyWithBuddy
            ? journalBuddySyncPhrase(syncStage, controller.syncTick.value)
            : statusText;

        final scaler = MediaQuery.textScalerOf(context);
        final direction = Directionality.of(context);
        double measureWidth(String text, TextStyle style) {
          final painter = TextPainter(
            text: TextSpan(text: text, style: style),
            textScaler: scaler,
            textDirection: direction,
          )..layout();
          final width = painter.width.ceilToDouble();
          painter.dispose();
          return width;
        }

        final summaryStyle = journal.metadata.copyWith(
          color: nearDueActive || dueSummary.dueToday > 0
              ? journal.accent
              : journal.muted,
          fontWeight: nearDueActive || dueSummary.dueToday > 0
              ? FontWeight.w600
              : FontWeight.w400,
        );
        final leftWidth = 14.5 +
            5.0 +
            measureWidth(effectiveStatusText, journal.metadata) +
            (showChevron ? 18.0 : 0.0) +
            4.0;
        final rightWidth = showDueSummary
            ? measureWidth(summaryLabel, summaryStyle) + 4.0
            : 0.0;
        final fitsSingleRow = !showDueSummary ||
            (leftWidth + rightWidth + 6.0 <= constraints.maxWidth);

        Widget buildStatusContent({
          required Widget leading,
          required String text,
          required TextStyle style,
        }) {
          return Semantics(
            liveRegion: true,
            button: onSyncTap != null,
            label: text,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                leading,
                const SizedBox(width: 5),
                Flexible(
                  fit: FlexFit.loose,
                  child: ExcludeSemantics(child: Text(text, style: style)),
                ),
                if (showChevron)
                  Icon(
                    Icons.chevron_right_rounded,
                    size: 18,
                    color: journal.muted,
                  ),
              ],
            ),
          );
        }

        final statusControl = Material(
          type: MaterialType.transparency,
          child: InkWell(
            key: const ValueKey('home-sync-status'),
            onTap: onSyncTap,
            borderRadius: BorderRadius.circular(8),
            child: ConstrainedBox(
              constraints: BoxConstraints(
                minHeight: onSyncTap == null ? (showDueSummary ? 40 : 22) : 48,
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 2),
                child: syncBusyWithBuddy
                    ? ValueListenableBuilder<int>(
                        valueListenable: controller.syncTick,
                        builder: (context, tick, _) {
                          final glyph = reduceMotion
                              ? '✻'
                              : kJournalSpinnerGlyphs[
                                  tick % kJournalSpinnerGlyphs.length];
                          final phrase =
                              journalBuddySyncPhrase(syncStage, tick);
                          return buildStatusContent(
                            leading: SizedBox(
                              width: 14.5,
                              child: Center(
                                child: ExcludeSemantics(
                                  child: Text(
                                    glyph,
                                    style: journal.metadata.copyWith(
                                      color: journal.accent,
                                      fontWeight: FontWeight.w600,
                                      height: 1.0,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            text: phrase,
                            style: journal.metadata,
                          );
                        },
                      )
                    : buildStatusContent(
                        leading:
                            Icon(statusIcon, size: 14.5, color: statusColor),
                        text: statusText,
                        style: journal.metadata,
                      ),
              ),
            ),
          ),
        );

        final summaryControl = !showDueSummary
            ? null
            : Material(
                type: MaterialType.transparency,
                child: InkWell(
                  key: const ValueKey('home-due-summary'),
                  onTap: onToggleNearDueFilter,
                  borderRadius: BorderRadius.circular(8),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(minHeight: 40),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 2),
                      child: Semantics(
                        button: true,
                        label: '$summaryLabel，点击筛选7天内临期课业',
                        child: ExcludeSemantics(
                          child: Center(
                            widthFactor: 1,
                            child: Text(summaryLabel, style: summaryStyle),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              );

        if (fitsSingleRow) {
          return Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Flexible(fit: FlexFit.loose, child: statusControl),
              if (summaryControl != null) ...[
                const SizedBox(width: 6),
                summaryControl,
              ],
            ],
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            statusControl,
            if (summaryControl != null) summaryControl,
          ],
        );
      }),
    );
  }
}

class HomeTodayPlanBanner extends StatelessWidget {
  const HomeTodayPlanBanner({
    super.key,
    required this.doneCount,
    required this.totalCount,
    required this.onTap,
  });

  final int doneCount;
  final int totalCount;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final journal = Journal.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 6, bottom: 4),
      child: JournalGroupedCard(
        backgroundColor: Color.lerp(
          journal.sheet,
          journal.sage,
          journal.isDark ? 0.35 : 0.45,
        ),
        children: [
          Material(
            type: MaterialType.transparency,
            child: InkWell(
              key: const ValueKey('home-plan-summary'),
              onTap: onTap,
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 46),
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  child: Row(children: [
                    Icon(Icons.checklist_rounded, size: 18, color: journal.ink),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '今日计划 · 已完成$doneCount/$totalCount',
                        style: journal.metadata.copyWith(
                          color: journal.ink,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    Icon(Icons.chevron_right_rounded, color: journal.muted),
                  ]),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class HomeSyncProgressBanner extends StatelessWidget {
  const HomeSyncProgressBanner({
    super.key,
    required this.reduceMotion,
    required this.label,
  });

  final bool reduceMotion;
  final String label;

  @override
  Widget build(BuildContext context) {
    final journal = Journal.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 8, bottom: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(2),
            child: reduceMotion
                ? Container(height: 3, color: journal.sageBorder)
                : LinearProgressIndicator(
                    minHeight: 3,
                    backgroundColor: journal.parchment,
                    color: journal.ink,
                  ),
          ),
          const SizedBox(height: 6),
          Semantics(
            liveRegion: true,
            child: Text(
              label,
              style: journal.metadata.copyWith(color: journal.ink),
            ),
          ),
        ],
      ),
    );
  }
}

class HomeSliverSyncStatus extends StatelessWidget {
  const HomeSliverSyncStatus({
    super.key,
    required this.syncTick,
    required this.syncStage,
    required this.reduceMotion,
  });

  final ValueNotifier<int> syncTick;
  final dynamic syncStage;
  final bool reduceMotion;

  @override
  Widget build(BuildContext context) {
    final journal = Journal.of(context);
    return ValueListenableBuilder<int>(
      valueListenable: syncTick,
      builder: (context, tick, _) {
        final glyph = reduceMotion
            ? '✻'
            : kJournalSpinnerGlyphs[tick % kJournalSpinnerGlyphs.length];
        final phrase = journalBuddySyncPhrase(syncStage, tick);
        return Semantics(
          liveRegion: true,
          label: phrase,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: 14.5,
                child: Center(
                  child: ExcludeSemantics(
                    child: Text(
                      glyph,
                      style: journal.metadata.copyWith(
                        color: journal.accent,
                        fontWeight: FontWeight.w600,
                        height: 1.0,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 5),
              Flexible(
                child: ExcludeSemantics(
                  child: Text(
                    phrase,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: journal.metadata,
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

List<Widget> buildHomeSliverActions(
  BuildContext context, {
  required JournalThemeMode themeMode,
  required bool recoveryActive,
  required bool busy,
  required VoidCallback onAddManual,
  required VoidCallback onOpenAgenda,
  required VoidCallback onRefresh,
  required VoidCallback onCycleTheme,
}) {
  final journal = Journal.of(context);
  return [
    if (!recoveryActive)
      IconButton(
        key: const ValueKey('home-sliver-add-manual'),
        tooltip: '添加课业或待办',
        iconSize: 20,
        onPressed: onAddManual,
        icon: const Icon(Icons.add_rounded),
      ),
    if (!recoveryActive)
      IconButton(
        key: const ValueKey('home-sliver-agenda-entry'),
        tooltip: '个人待办与考试',
        iconSize: 20,
        onPressed: onOpenAgenda,
        icon: const Icon(Icons.checklist_rounded),
      ),
    IconButton(
      tooltip: '刷新作业',
      enableFeedback: false,
      iconSize: 20,
      onPressed: busy ? null : onRefresh,
      icon: busy
          ? SizedBox.square(
              dimension: 17,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: journal.ink,
              ),
            )
          : const Icon(Icons.sync_rounded),
    ),
    if (!recoveryActive)
      IconButton(
        enableFeedback: false,
        tooltip: '切换主题',
        iconSize: 20,
        onPressed: onCycleTheme,
        icon: Icon(switch (themeMode) {
          JournalThemeMode.system => Icons.brightness_auto_outlined,
          JournalThemeMode.light => Icons.light_mode_outlined,
          JournalThemeMode.dark => Icons.dark_mode_outlined,
        }),
      ),
  ];
}

class HomeHeaderSection extends StatelessWidget {
  const HomeHeaderSection({
    super.key,
    required this.controller,
    required this.showPixelBuddy,
    required this.busy,
    required this.reduceMotion,
    required this.recoveryLabel,
    required this.recoveryItemCount,
    required this.syncErrorOrPending,
    required this.displayPrefs,
    required this.accountEpoch,
    required this.account,
    required this.buddyMood,
    required this.homeSnapshot,
    required this.stageAnchor,
    required this.statusRowKey,
    required this.sync,
    required this.syncPhase,
    required this.statusText,
    required this.syncStage,
    required this.syncBusyWithBuddy,
    required this.showDueSummary,
    required this.dueSummary,
    required this.plans,
    required this.upcomingExam,
    required this.filtersActive,
    required this.query,
    required this.typeFilter,
    required this.deadlineFilter,
    required this.courseKey,
    required this.sortOrder,
    required this.courseOptions,
    required this.syncProgressLabel,
    required this.hasTimelineItems,
    required this.onOpenAgenda,
    required this.onRefresh,
    required this.onRetrySync,
    required this.onOpenSyncIssues,
    required this.onToggleNearDueFilter,
    required this.onCycleTheme,
    required this.onOpenMoreMenu,
    required this.onExitRecoveryScope,
    required this.onOpenPlan,
    required this.onToggleUpcomingExam,
    required this.onOpenFilters,
    required this.onSelectSortOrder,
    required this.onAddManual,
    required this.onClearQuery,
    required this.onClearType,
    required this.onClearDeadline,
    required this.onClearCourse,
    required this.onResetAllFilters,
  });

  final ClawdCompanionController controller;
  final bool showPixelBuddy;
  final bool busy;
  final bool reduceMotion;
  final String? recoveryLabel;
  final int recoveryItemCount;
  final bool syncErrorOrPending;
  final DisplayPreferences displayPrefs;
  final int accountEpoch;
  final String? account;
  final JournalPixelBuddyMood buddyMood;
  final ClawdPageContextSnapshot homeSnapshot;
  final ValueNotifier<ClawdStageAnchor> stageAnchor;
  final GlobalKey statusRowKey;
  final HomeSyncPresentation sync;
  final SyncPhase syncPhase;
  final String statusText;
  final dynamic syncStage;
  final bool syncBusyWithBuddy;
  final bool showDueSummary;
  final HomeDueSummary dueSummary;
  final List<DailyPlanItem> plans;
  final HomeUpcomingExam? upcomingExam;
  final bool filtersActive;
  final String query;
  final AssignmentTypeFilter typeFilter;
  final AssignmentDeadlineFilter deadlineFilter;
  final String? courseKey;
  final HomeSortOrder sortOrder;
  final List<HomeCourseFilterOption> courseOptions;
  final String syncProgressLabel;
  final bool hasTimelineItems;
  final VoidCallback onOpenAgenda;
  final VoidCallback onRefresh;
  final VoidCallback onRetrySync;
  final VoidCallback onOpenSyncIssues;
  final VoidCallback onToggleNearDueFilter;
  final VoidCallback onCycleTheme;
  final void Function(BuildContext anchorContext) onOpenMoreMenu;
  final VoidCallback onExitRecoveryScope;
  final VoidCallback onOpenPlan;
  final VoidCallback onToggleUpcomingExam;
  final VoidCallback onOpenFilters;
  final Future<void> Function(
    HomeSortOrder order,
    int openingEpoch,
    String? openingAccount,
  ) onSelectSortOrder;
  final VoidCallback onAddManual;
  final VoidCallback onClearQuery;
  final VoidCallback onClearType;
  final VoidCallback onClearDeadline;
  final VoidCallback onClearCourse;
  final VoidCallback onResetAllFilters;

  @override
  Widget build(BuildContext context) {
    final recoveryActive = recoveryLabel != null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        HomeTitleHeaderRow(
          controller: controller,
          showPixelBuddy: showPixelBuddy,
          busy: busy,
          reduceMotion: reduceMotion,
          recoveryActive: recoveryActive,
          syncErrorOrPending: syncErrorOrPending,
          themeMode: displayPrefs.themeMode,
          buddyMood: buddyMood,
          homeSnapshot: homeSnapshot,
          stageAnchor: stageAnchor,
          onOpenAgenda: onOpenAgenda,
          onRefresh: onRefresh,
          onCycleTheme: onCycleTheme,
          onOpenMoreMenu: onOpenMoreMenu,
        ),
        const SizedBox(height: 2),
        HomeSyncStatusRow(
          statusRowKey: statusRowKey,
          sync: sync,
          syncPhase: syncPhase,
          statusText: statusText,
          syncStage: syncStage,
          syncBusyWithBuddy: syncBusyWithBuddy,
          reduceMotion: reduceMotion,
          busy: busy,
          showDueSummary: showDueSummary,
          dueSummary: dueSummary,
          nearDueActive: deadlineFilter == AssignmentDeadlineFilter.next7Days,
          controller: controller,
          onRetrySync: onRetrySync,
          onOpenSyncIssues: onOpenSyncIssues,
          onToggleNearDueFilter: onToggleNearDueFilter,
        ),
        if (recoveryLabel != null) ...[
          const SizedBox(height: 6),
          HomeRecoveryHeader(
            scopeLabel: recoveryLabel!,
            count: recoveryItemCount,
            onExit: onExitRecoveryScope,
          ),
          const SizedBox(height: 8),
        ],
        if (plans.isNotEmpty)
          HomeTodayPlanBanner(
            doneCount: plans.where((p) => p.done).length,
            totalCount: plans.length,
            onTap: onOpenPlan,
          ),
        if (upcomingExam != null)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: HomeUpcomingExamStrip(
              upcomingExam: upcomingExam!,
              inExamView: typeFilter == AssignmentTypeFilter.exam,
              onTap: onToggleUpcomingExam,
            ),
          ),
        if (!recoveryActive) ...[
          const SizedBox(height: 6),
          HomeActionBar(
            filtersActive: filtersActive,
            sortOrder: sortOrder,
            displayPrefs: displayPrefs,
            accountEpoch: accountEpoch,
            account: account,
            onOpenFilters: onOpenFilters,
            onSelectSortOrder: onSelectSortOrder,
            onAddManual: onAddManual,
          ),
          AnimatedSize(
            duration: JournalLayout.motionDuration(context),
            curve: Curves.easeOutCubic,
            alignment: Alignment.topCenter,
            child: filtersActive
                ? Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: ActiveFilterSummaryBar(
                      query: query,
                      typeFilter: typeFilter,
                      deadlineFilter: deadlineFilter,
                      courseKey: courseKey,
                      options: courseOptions,
                      onClearQuery: onClearQuery,
                      onClearType: onClearType,
                      onClearDeadline: onClearDeadline,
                      onClearCourse: onClearCourse,
                      onResetAll: onResetAllFilters,
                    ),
                  )
                : const SizedBox.shrink(),
          ),
        ],
        if (busy)
          HomeSyncProgressBanner(
            reduceMotion: reduceMotion,
            label: syncProgressLabel,
          ),
        if (hasTimelineItems && !recoveryActive)
          SizedBox(height: displayPrefs.compact ? 6 : 12),
      ],
    );
  }
}
