# Android 升级合成探针

此工具不打进应用 APK。`seed` 会清空目标应用偏好和安全存储，只能用于无真实账号、可丢弃的测试模拟器，不能在用户设备上执行。

固定样例包含四条正式作业的标题、课程、UTC 截止、原始链接、要求、同步时间和不同提交状态，以及两条隐藏记录、取消关注课程、两项提醒和完整虚构凭据。`both` 还混入旧平台凭据/记录；`retired` 只放旧平台数据。`verify` 按字段和时间瞬时值核对迁移结果，并核对旧键删除；PASS 不代表真实登录、同步或设备迁移已验收。

本次样例比旧版本完整，复用旧模拟器时需要重新 seed。保留现有包名和测试签名，构建探针的命令仍为 `./build.ps1 -Sdk <Android SDK> -Jdk <JDK>`。构建的是仅测试用途的 instrumentation APK，不是发布安装包。

`./test.ps1` 在本机 JVM 上运行浏览器 URL 边界和升级核对器的篡改回归，不连接 Android 或学习通。可用 `-Jdk`、`-JsonJar` 指定 JDK 和现有 `org.json` JVM jar；默认从本地 Gradle 缓存查找 jar，不下载依赖。

仍需独立设备验收：浏览器有/无/多应用选择、验证码 WebView 连续两次会话及退出后的 Cookie/DOM storage/cache、Android 云备份和设备迁移。JVM 回归与 XML 策略检查不能代替这些系统行为检查。
