# Gitee 国内更新分发与每日同步设计

日期：2026-11-13

## 目标

将 Gitee 仓库 `arrry-07/chaoxing-journal-updates` 建成公开、可验证的国内更新主源。客户端优先读取 Gitee 清单并从 Gitee 下载 APK，失败时回退到 GitHub 正式 Release。GitHub 原有发布策略、Tag、APK 和 latest 不改。

APK 的 GitHub 到 Gitee 同步只在 GitHub Actions Runner 中完成，不在维护者本机下载或上传大文件，因此不消耗本机 VPN/TUN 流量。

## 当前事实

- Gitee 仓库公开，默认分支为 `master`，当前只有模板 README，Release 列表为空。
- GitHub latest 为 `v1.7.51`。
- `1.7.4+56`、`1.7.5+57`、`1.7.51+58` 的 APK 均已验证为同一包名和原体验签名。
- 已发布的 `1.7.51` 未编入 Gitee 清单地址，不能远程切换。
- 客户端已有严格清单解析和 APK 备用下载地址，但没有清单请求失败后的 GitHub 回退。
- GitHub Actions 当前只有测试和 Debug 构建，没有发布同步工作流。

## 版本策略

- `stable` 只随主/次版本前进，当前基线为 `1.7.4+56`。
- `manual` 指向最新正式补丁，迁移客户端发布后为 `1.7.52+59`。
- 未来补丁只更新 `manual`；只有更高主/次版本才同时更新 `stable`。
- Gitee 与 GitHub 的 APK 文件名、大小、SHA-256、包名、versionName、versionCode 和签名必须一致。
- Gitee 最多保留 3 个 APK Release。始终保留 stable Tag、manual Tag 和最近版本；超出的旧 Release 删除，旧版本仍可从 GitHub 获取。

## 客户端方案

默认清单地址固定为：

```text
https://raw.giteeusercontent.com/arrry-07/chaoxing-journal-updates/raw/master/update-stable.json
https://raw.giteeusercontent.com/arrry-07/chaoxing-journal-updates/raw/master/update-manual.json
```

该地址实测匿名返回 HTTP 200，不经过 `gitee.com/.../raw/...` 的 302 跳转。

清单中的 `apkUrl` 使用公开 Gitee Release 路由，`backupApkUrl` 使用对应 GitHub Release 路由。客户端继续用同一大小和 SHA-256 验证两个来源。

清单请求发生网络错误、鉴权错误、限流、非 200 或无效 JSON 时，客户端回退到 GitHub 正式 Release 检查。取消不触发回退。有效清单返回“已是最新”或“有新版本”时不额外请求 GitHub。

`1.7.52+59` 是迁移版本：

- `1.7.51` 用户可由现有冷启动检查从 GitHub 发现并安装 1.7.52。
- 更早旧客户端首次升级仍需手动检查或网页安装。
- 1.7.52 安装后，后续检查和下载默认使用 Gitee，GitHub 只作回退。

## Gitee 自动同步

新增无第三方依赖的 `scripts/gitee_release_sync.py`：

1. 校验 `GITEE_TOKEN` 对应用户和仓库。
2. 从 GitHub API 读取指定 Tag 或 latest，只接受公开、非草稿、非预发布 Release。
3. 下载 APK 与 `SHA256SUMS.txt`，核对 GitHub size/digest、校验文件、ZIP CRC、包名、versionCode、versionName 和固定签名证书。
4. 在 Gitee 创建唯一发行版并上传同名 APK；已存在且内容一致则复用，不一致则失败，不覆盖。
5. 匿名完整下载 Gitee APK，再次核对大小与 SHA-256。
6. 通过扩展后的 `scripts/update-manifest.ps1` 生成 stable/manual 清单，清单包含 GitHub 备用 APK 地址。
7. 在一个 Gitee Git 提交中原子更新两份 JSON 和静态 README，不记录 Token。
8. 等待公开清单 CDN 可读取并验证内容。
9. 删除未受 stable/manual 保护的最旧 Release，使 APK 发行版最多为 3 个。

Gitee 写入使用访问令牌请求头。Git 推送使用临时 `GIT_ASKPASS` 脚本从环境变量读取 Token，不把 Token 写进 remote URL、日志或文件。

## 调度

GitHub Actions 工作流只提供：

- `schedule`：每天 `19:17 UTC`，即北京时间次日 `03:17`，最多检查并同步一个 latest Release。
- `workflow_dispatch`：用于一次性 seed 和失败恢复。

不再监听每个 `release.published` 事件。若当天 latest 已同步，任务做幂等 no-op。一次性 seed 可显式上传 `v1.7.4`、`v1.7.5` 和迁移版本，完成首轮国内源初始化。

2026-11-13 维护者进一步收紧传输量：历史 `v1.7.4`、`v1.7.5` 只在 Gitee 网页后台上传一次，Actions 只检查 Release/附件存在，不做 Gitee 回头完整下载；最新 manual APK 由维护者本机上传一次，Actions 只对最新版做匿名完整下载和 SHA-256 校验后更新清单。云端工作流不再上传任何 APK。

## 初始部署

迁移版本发布后执行一次 seed：

```text
v1.7.4,v1.7.5,v1.7.52
```

生成结果：

- `update-stable.json`：`1.7.4+56`
- `update-manual.json`：`1.7.52+59`
- Gitee 保留这 3 个 APK

## 安全与失败边界

- Token 只存在于 GitHub Secrets 和 Actions 进程环境。
- 任一 GitHub/Gitee 身份或哈希不一致时停止，不生成或更新清单。
- Gitee APK 未通过匿名完整下载前不提交清单。
- 已存在的错误 Gitee Release 不覆盖；人工或后续单独修复。
- 删除只针对本仓库匹配 `vX.Y.Z` 且未受 stable/manual 保护的旧 Release。
- 网络、Gitee API、CDN 缓存或 Actions 限流失败都使工作流失败并输出不含 Secret 的错误。

## VPN/TUN

发布同步运行在 GitHub Actions 的云端 Runner，本机只调用小型 GitHub API 触发工作流，不传输 APK，因此不占本机 TUN 流量。

Android 客户端是否经 TUN 仍由设备上的 VPN 分流策略决定。若需要绕过，应在 VPN 应用中将 `gitee.com`、`raw.giteeusercontent.com`、`foruda.gitee.com` 及 `*.gitee.com` 设为直连。该设置属于 VPN 客户端配置，不在应用内修改系统代理或绕过用户安全策略。

## 验收

- PowerShell 清单脚本测试和 Python 同步脚本单测通过。
- Flutter 更新专项、全量测试、静态分析、格式和双时区通过。
- 在 Workflow 中实际 seed 三个 Release，匿名下载 Gitee APK 与 JSON。
- Gitee/GitHub 三个版本的大小、哈希、包名、版本和签名逐项一致。
- Gitee Release 数量不超过 3；stable/manual 指向正确。
- `1.7.52` APK 在 MuMu 覆盖安装并保留数据；实际验证 Gitee 清单成功时不请求 GitHub，Gitee 失败时能回退 GitHub。
- GitHub/gitee 发布状态、Tag、CI 和回下载结果写入正式验收记录。
