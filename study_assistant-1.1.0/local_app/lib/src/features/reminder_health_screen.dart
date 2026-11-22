import 'package:flutter/material.dart';

import '../services/assignment_store.dart';
import '../services/permission_settings_service.dart';
import 'reminder_settings_screen.dart';

/// Forwarding shell preserving deep compatibility for `/reminder-health` callers
/// now unified into [ReminderSettingsScreen]（「提醒与通知」）.
class ReminderHealthScreen extends StatelessWidget {
  const ReminderHealthScreen({
    super.key,
    required this.store,
    this.permissionSettingsService = const PermissionSettingsService(),
  });

  final AssignmentStore store;
  final PermissionSettingsService permissionSettingsService;

  @override
  Widget build(BuildContext context) => ReminderSettingsScreen(
        assignmentStore: store,
        permissionSettingsService: permissionSettingsService,
        initialExpandHealth: true,
      );
}
