import '../models/sync_report.dart';

class SyncIssueGroup {
  SyncIssueGroup({
    required this.kind,
    required this.message,
    required this.stage,
    required List<SyncIssue> issues,
  }) : issues = List.unmodifiable(issues);

  final SyncIssueKind kind;
  final String message;
  final String stage;
  final List<SyncIssue> issues;

  int get count => issues.length;

  Set<String> get courseKeys =>
      {for (final issue in issues) issue.courseKey}.whereType<String>().toSet();
}

List<SyncIssueGroup> groupSyncIssues(Iterable<SyncIssue> source) {
  final grouped = <String, List<SyncIssue>>{};
  for (final issue in source) {
    final key = '${issue.stage}\u0000${issue.kind.name}\u0000${issue.message}';
    (grouped[key] ??= []).add(issue);
  }
  return [
    for (final issues in grouped.values)
      SyncIssueGroup(
        kind: issues.first.kind,
        message: issues.first.message,
        stage: issues.first.stage,
        issues: issues,
      ),
  ];
}

String syncIssueStageLabel(String stage) => switch (stage) {
      'exam' => '课程考试',
      'examAccount' => '账号考试',
      'examNotice' => '考试通知',
      'detail' => '截止时间',
      'work' || 'workList' => '课程作业',
      'persistence' => '本机保存',
      'request' => '网络请求',
      _ => stage,
    };

String syncIssueKindLabel(SyncIssueKind kind) => switch (kind) {
      SyncIssueKind.network => '网络不可用',
      SyncIssueKind.authExpired => '登录已失效',
      SyncIssueKind.verificationRequired => '需要安全验证',
      SyncIssueKind.forbidden => '没有访问权限',
      SyncIssueKind.notFound => '内容不存在',
      SyncIssueKind.rateLimited => '请求过于频繁',
      SyncIssueKind.serverError => '学习通服务异常',
      SyncIssueKind.schemaChanged => '页面结构未识别',
      SyncIssueKind.partial => '部分信息未确认',
      SyncIssueKind.storage => '本机保存异常',
      SyncIssueKind.notification => '通知异常',
      SyncIssueKind.widget => '小组件异常',
      SyncIssueKind.cancelled => '已取消',
    };

String syncIssueNextAction(SyncIssueKind kind) => switch (kind) {
      SyncIssueKind.network || SyncIssueKind.serverError => '检查网络后刷新；持续失败时稍后再试',
      SyncIssueKind.authExpired => '重新登录后刷新作业',
      SyncIssueKind.verificationRequired => '完成安全验证后刷新作业',
      SyncIssueKind.rateLimited => '等待提示时间结束后再刷新',
      SyncIssueKind.forbidden => '到学习通确认该课程仍有访问权限，再刷新',
      SyncIssueKind.notFound => '到学习通确认内容仍存在，再刷新',
      SyncIssueKind.schemaChanged => '先刷新重试；若持续出现，展开原始条目并反馈',
      SyncIssueKind.partial => '刷新以补齐尚未确认的信息',
      SyncIssueKind.storage => '检查本机存储空间后重试，不要清除应用数据',
      SyncIssueKind.notification => '检查通知权限与本机通知设置',
      SyncIssueKind.widget => '重新打开应用或刷新桌面小组件',
      SyncIssueKind.cancelled => '重新发起刷新',
    };
