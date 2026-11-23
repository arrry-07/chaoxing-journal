# 课业手记 Flutter 应用

主入口 `lib/main.dart`。页面在 `lib/src/features`，同步与提醒状态在 `lib/src/services/assignment_store.dart`，学习通客户端/解析器/本机迁移仓库在 `lib/src/local`。Android 原生小组件位于 `android/app/src/main`。

完整说明：[仓库首页](../../README.md)、[本轮验收](../../docs/验收.md)、[历史文档](../../docs/README.md)。

```sh
flutter pub get --enforce-lockfile
dart analyze lib test # 含中文路径时勿在本地直接跑 flutter analyze
flutter test --no-pub
flutter build apk --debug --no-pub --target-platform android-arm64,android-x64
python tool/check_apk_abis.py build/app/outputs/flutter-apk/app-debug.apk --abi arm64-v8a --abi x86_64
```

当前 `debug` 与 `release` 构建均使用 `.journal` 包名后缀（`com.example.studyassistant.journal`）；公开正式包为非 debuggable 的 Release 构建，但证书沿用既有 Android Debug 体验证书，覆盖升级依赖同一包名与签名。ABI 检查要求 APK 不得声明 `armeabi-v7a`，且 ARM64/x86_64 都必须包含 `libflutter.so`。完整环境、签名与发布约定见[开发与贡献](../../docs/guides/开发与贡献.md#安装身份与发布)。
