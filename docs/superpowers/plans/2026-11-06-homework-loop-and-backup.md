# 作业闭环、变化记录与加密备份实施计划

**Goal:** 完成ROADMAP本轮三项，其他建议仅列入后续计划。

**Architecture:** 复用现有Flutter Store操作队列和账号归属机制。原生Android提供加密与系统文件选择器，Dart只组装严格白名单快照并通过仓库事务恢复。变化日志随账号隔离，返回核对只读取目标课程，不把打开页面视为提交。

**Tech Stack:** Flutter/Dart、SharedPreferences、Android JCA AES-GCM/PBKDF2、Storage Access Framework；不自创加密算法。

## 全局约束
- 初次同步建立基线；日志最多保留200项，不包含密码、Cookie、头像、签名URL或完整错误响应。
- 同步失败不产生虚假删除或提交确认；比较可信截止，未知状态不冒充已交。
- 返回检查有生命周期延迟与去重，切号/退出立即失效；不与现有同步并发使用同一客户端。
- 备份仅当前已登录账号。快照归属使用账号哈希；原始签名URL、密码、Cookie不导出；恢复后需要同步获得新链接。
- 文件上限8MiB明文/12MiB封装，未知schema、异常迭代次数、坏密文、错口令在写数据前拒绝。文件读写只走用户选择器，不申请广泛存储权限。
- 恢复先预览再明确确认；同账号仅补缺，保留本机较新的记录；账号变化或快照预览过期拒绝。使用持久检查点回滚多键写入。

## 分工与接口
1. Root：目标课程读取、返回核对、变化日志、路由/首页/详情入口、Store整合和验收。
2. Native backup：`study_assistant/backup`通道：encrypt({plaintext,password})->String envelope；decrypt({envelope,password})->String plaintext；save({content,suggestedName})->bool（取消false）；pick()->String?（取消null）。异常PlatformException。原生自己处理SAF结果和单任务去重，后台线程执行加密，不输出内容及口令。
3. Dart backup：BackupService通过上述通道，BackupSnapshot白名单模型、备份页面；LocalAssignmentRepository增加createBackupSnapshot(account)和restoreBackupSnapshot(snapshot,account)（返回bool或抛出，不吞失败）；事务与账号切换共用串行队列。备份页面接收AssignmentStore，恢复应用由Root提供`restoreLocalBackup(snapshot)`包装Store队列、重载记录及重新安排提醒。

## 任务与验收
- [x] Native：先测试错口令、篡改、随机nonce、空/过长/异常参数、文件上限和取消，再实现并JVM验证。
- [x] Dart备份：schema/白名单/归属/新旧合并/配置预览/失败回滚测试；页面密码不持久保存，提供显式恢复确认。
- [x] Root：变化差分与截断保存；按课程增量读取、去重和失败边界；App返回核对结果可见。
- [x] 整体：独立代码审查、Flutter测试/分析、原生测试、双架构构建，MuMu保留真实数据验收；备份恢复使用合成数据验证，不用真实账号做破坏性恢复。

## 执行记录
用户已经授权按上述优先级执行，常规实现选择由工程判断落实，不重复要求确认。使用实施计划与分任务开发技能；保留当前干净checkout，完成后自动提交推送。

## 实施记录
本轮335项Flutter测试、41项加密JVM检查、原有38项native检查通过；分析和双架构构建通过。MuMu合成SAF导出/解密预览/确认恢复/错口令/取消通过，真实记录保持32条。修复审查发现的退出后旧提示、未知覆盖、部分基线、队列陈旧提示、未来备份时间及说明正文链接泄露边界。恢复仅补缺，历史观察合并时间归零以允许真实同步。详细记录见本轮验收。
