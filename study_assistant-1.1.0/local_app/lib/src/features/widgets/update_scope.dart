import 'package:flutter/material.dart';

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
          color: Theme.of(context).colorScheme.secondaryContainer,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            if (controller.downloading)
              LinearProgressIndicator(value: progress),
            Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 8, 4),
                child: Row(children: [
                  Expanded(
                      child: Semantics(
                          liveRegion: !controller.downloading,
                          child: Text(label,
                              maxLines: 2, overflow: TextOverflow.ellipsis))),
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
                ])),
          ]),
        );
      });
}
