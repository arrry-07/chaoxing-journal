# 课业手记 Flutter 应用

主入口 `lib/main.dart`。页面在 `lib/src/features`，同步与提醒状态在 `lib/src/services/assignment_store.dart`，学习通客户端/解析器/本机迁移仓库在 `lib/src/local`。Android 原生小组件位于 `android/app/src/main`。

完整说明：[仓库首页](../../README.md)、[需求与验收](../../docs/验收记录.md)。

```sh
flutter pub get
flutter test
flutter analyze
flutter build apk --debug --target-platform android-arm64,android-x64
```

体验版使用 `.journal` 包名后缀。release 构建默认没有此后缀，因此本次交付 debug 签名体验包；不要混淆两种安装身份。若后续正式发布，先固定包名和私有签名方案，再迁移版本，不能用另一签名覆盖现有安装。
