import 'package:flutter/material.dart';
import '../../app/journal.dart';

import '../../services/app_update_controller.dart';
import 'update_dialog.dart';

class AppUpdateScope extends InheritedWidget {
  const AppUpdateScope(
      {super.key, required this.controller, required super.child});
  final AppUpdateController controller;
  static AppUpdateController? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<AppUpdateScope>()?.controller;
  @override
  bool updateShouldNotify(AppUpdateScope oldWidget) =>
      controller != oldWidget.controller;
}

class UpdateDownloadBanner extends StatelessWidget {
  const UpdateDownloadBanner({super.key, required this.controller});
  final AppUpdateController controller;

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        if (!controller.showBanner) return const SizedBox.shrink();
        final progress = controller.progress;
        final label = controller.downloading
            ? '${controller.message}${progress == null ? '' : ' · ${(progress * 100).floor()}%'}'
            : controller.message;
        return Material(
          color: Journal.sage,
          child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 12, 8),
              child: LayoutBuilder(builder: (context, constraints) {
                final status = Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Semantics(
                          liveRegion: !controller.downloading,
                          child: Text(label,
                              style: Journal.metadata
                                  .copyWith(color: Journal.ink))),
                      if (controller.downloading) ...[
                        const SizedBox(height: 8),
                        LinearProgressIndicator(value: progress, minHeight: 3),
                      ],
                    ]);
                final actions = Row(mainAxisSize: MainAxisSize.min, children: [
                  TextButton(
                      onPressed: () => showUpdateDialog(context, controller),
                      child: Text(controller.phase == UpdatePhase.ready
                          ? '安装更新'
                          : '查看进度')),
                  if (!controller.busy)
                    IconButton(
                        tooltip: '稍后再说',
                        onPressed: controller.hideBanner,
                        icon: const Icon(Icons.close, size: 20)),
                ]);
                if (constraints.maxWidth < 400 ||
                    MediaQuery.textScalerOf(context).scale(14) > 21) {
                  return Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        status,
                        const SizedBox(height: 4),
                        Align(alignment: Alignment.centerRight, child: actions)
                      ]);
                }
                return Row(children: [
                  Expanded(child: status),
                  const SizedBox(width: 16),
                  actions
                ]);
              })),
        );
      });
}
