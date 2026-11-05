import 'package:flutter/material.dart';

import '../app/journal.dart';

enum AgreementKind {
  service('服务协议'),
  privacy('隐私协议');

  const AgreementKind(this.title);
  final String title;
}

/// In-app reading content follows the current storage and network behavior.
class AgreementScreen extends StatelessWidget {
  const AgreementScreen({super.key, required this.kind});

  final AgreementKind kind;

  @override
  Widget build(BuildContext context) {
    final sections = kind == AgreementKind.service ? _service : _privacy;
    return Scaffold(
      backgroundColor: Journal.paper,
      appBar: AppBar(title: Text(kind.title)),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final section in sections) ...[
              Semantics(
                header: true,
                child: Text(section.$1, style: Journal.section),
              ),
              const SizedBox(height: 10),
              SelectableText(section.$2, style: const TextStyle(height: 1.7)),
              const SizedBox(height: 28),
            ],
          ],
        ),
      ),
    );
  }
}

const _service = [
  (
    '服务说明',
    '学习通课业手记用于同步和查看你有权访问的学习通课程作业、截止时间与提交状态，并提供本机提醒。应用由项目维护者提供，不是学习通官方应用，不会代交作业。请使用你本人的账号。'
  ),
  (
    '登录与读取',
    '登录及同步会直接连接超星学习通，发送身份凭据、会话信息及读取所需参数，不经过维护者中转服务器。学习通的网络、权限与接口变化可能导致读取失败、记录缺失或需要安全验证。'
  ),
  (
    '作业与提醒',
    '离线时可能显示上次保存的记录。截止时间或提交状态待确认、部分课程读取失败时，请查看同步结果并以学习通原页面为准。提醒依赖通知权限及系统运行条件，不能保证每次准时投递；请自行核对重要截止时间。隐藏和取消关注只改变本机显示、统计与提醒，不修改学习通服务器中的作业。'
  ),
  (
    '记录与退出',
    '账号密码保存在本机安全存储，课程作业等记录保存在本机偏好文件。切换账号会在本机备份原账号记录，再隔离加载目标账号记录。退出登录会清理保存的登录信息、本机课程作业、隐藏状态、课程关注、提醒规则、同步记录及所有账号切换备份，并更新本机通知及小组件；不会删除学习通服务器上的数据。卸载或清除应用数据可能丢失本机记录，当前没有完整导出恢复功能。'
  ),
  (
    '更新与反馈',
    '手动检查更新会访问 GitHub Release；可用安装包下载、校验后交由系统确认安装。升级需兼容现有包名和签名。反馈复制操作不会自动发送内容；打开外部反馈页面并主动提交后，内容由对应站点处理，请先移除账号、密码、Cookie 和带签名的作业链接。'
  ),
];

const _privacy = [
  (
    '账号与本机记录',
    '学习通账号、密码、显示名和头像地址通过 flutter_secure_storage 保存在本机安全存储，Android 使用加密 SharedPreferences。课程及班级标识、作业标题、状态、截止时间、原始链接、隐藏状态、关注、提醒和同步记录保存在本机偏好文件，这些记录不属于账号密码安全存储，不能视为全部加密。'
  ),
  (
    '登录、同步与验证',
    '登录及同步直接请求超星学习通，需要向对方发送账号密码或会话 Cookie，以及课程、班级和作业读取参数。会话 Cookie 由客户端在内存维护；应用内安全验证页面会交换所需会话信息。头像可能从超星头像服务或其 CDN 联网加载。维护者没有中转这些登录和同步请求。'
  ),
  (
    '其他联网与可见信息',
    '手动检查或下载更新会访问 GitHub Release API 及安装包托管地址；配置 HTTPS 更新清单时使用该来源。打开源码、反馈和作业网页后，浏览器或目标应用会访问对应站点，适用其数据处理方式，可能需要另行登录。联网服务可以接收 IP、请求头和必要参数。故障定位中存在调试输出，因此不能承诺零日志或完全不上传数据。'
  ),
  (
    '通知、小组件与剪贴板',
    '本机通知及桌面小组件会保存或展示必要的作业标题、课程、截止提示，可能出现在桌面或锁屏。主动复制反馈会将你填写的描述、应用及系统版本写入剪贴板；主动复制链接会写入完整链接。复制不会自动提交反馈，带签名链接仅应在本人设备使用。'
  ),
  (
    '清理与保护边界',
    '切换账号会将原账号的记录及设置备份到本机偏好文件，再按账号隔离加载记录；重新登录原账号时可恢复该账号备份。退出登录清理保存的凭据、本机课程作业、隐藏和关注、提醒规则、同步记录、仓库损坏备份及所有账号切换备份（含其他账号），并更新本机通知和小组件，不删除学习通服务器数据。清除应用数据或卸载也可能丢失本机记录。设备解锁、Root、恶意软件与系统备份可能改变保护边界；安全存储并非绝对安全保证。系统备份不能作为已验证的完整迁移或恢复能力。'
  ),
  (
    '反馈前检查',
    '请勿在反馈中包含手机号、学号、姓名、密码、Cookie、令牌、课程班级个人标识、带签名的完整链接或未脱敏截图。只有主动提交后内容才会发送到反馈站点，公开问题和附件可能被其他人查看。'
  ),
];
