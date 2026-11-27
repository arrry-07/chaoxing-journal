import 'package:flutter/material.dart';

import '../../app/journal_motion.dart';

/// Shared modal bottom sheet entry applying the app's unified spring-open and
/// crisp 180ms ease-out dismiss motion (plus reduced-motion fallback).
Future<T?> showJournalModalSheet<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  bool useRootNavigator = true,
  bool isScrollControlled = true,
  bool useSafeArea = true,
  Color? backgroundColor,
  ShapeBorder? shape,
  Color? barrierColor,
  bool enableDrag = true,
  bool isDismissible = true,
}) {
  return showModalBottomSheet<T>(
    context: context,
    builder: builder,
    useRootNavigator: useRootNavigator,
    isScrollControlled: isScrollControlled,
    useSafeArea: useSafeArea,
    backgroundColor: backgroundColor,
    shape: shape,
    barrierColor: barrierColor,
    enableDrag: enableDrag,
    isDismissible: isDismissible,
    sheetAnimationStyle: JournalMotion.modalSheetAnimationStyle(context),
  );
}
