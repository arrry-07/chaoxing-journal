# 课业手记 Flutter 应用

主入口 `lib/main.dart`。页面在 `lib/src/features`，同步与提醒状态在 `lib/src/services/assignment_store.dart`，学习通客户端/解析器/本机迁移仓库在 `lib/src/local`。Android 原生小组件位于 `android/app/src/main`。

完整说明：[仓库首页](../../README.md)、[本轮验收](../../docs/验收.md)、[历史文档](../../docs/README.md)。

```sh
flutter pub get
flutter test
flutter analyze
flutter build apk --debug --target-platform android-arm64,android-x64
python tool/check_apk_abis.py build/app/outputs/flutter-apk/app-debug.apk --abi arm64-v8a --abi x86_64
```

体验版使用 `.journal` 包名后缀。release 构建默认没有此后缀，因此本次交付 debug 签名体验包；不要混淆两种安装身份。ABI 检查要求 APK 不得声明 `armeabi-v7a`，且 ARM64/x86_64 都必须包含 `libflutter.so`。若后续正式发布，先固定包名和私有签名方案，再迁移版本，不能用另一签名覆盖现有安装。
