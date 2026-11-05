# 学习通课业手记

专门服务学习通的 Android 作业手账，提供课程作业查询、截止日历、提醒与桌面小组件。基于 [mshzy/study_assistant](https://github.com/mshzy/study_assistant) 二次开发，接口参考 [xuexitong-cli](references/xuexitong-cli)。

开发入口是 [Flutter 应用](study_assistant-1.1.0/local_app)，构建环境与 CI 使用 Flutter 3.44.9、JDK 17 和 Android SDK 36。

当前版本 **1.2.7（37）**：霞鹜文楷手写风字体、无框作业时间轴和完成率环图。字体原始来源及OFL许可见[字体说明](study_assistant-1.1.0/local_app/assets/type/README.md)。

```sh
cd study_assistant-1.1.0/local_app
flutter pub get
flutter analyze --no-pub
flutter test --no-pub
flutter build apk --debug --no-pub --target-platform android-arm64,android-x64
```

本地交付包统一放在 `artifacts/packages/`，历史根目录安装包保存在 `artifacts/packages/archive/`；这些目录不上传 Git。覆盖安装需保留相同包名与签名，请勿先卸载旧版。

最新包：`artifacts/packages/chaoxing-journal-1.2.7.apk`；当前截图位于 `artifacts/current/`。

当前结果与已知限制见 [本轮验收](docs/验收.md)，旧报告、方案和截图见 [文档索引](docs/README.md)。上游版权及第三方来源见 [来源说明](docs/archive/第三方来源.md) 和 [MIT 许可证](LICENSE)。

首页刷新支持即时进度、重复点击保护及完成/失败提示。[下载最新版体验包](https://github.com/arrry-07/chaoxing-journal/releases/tag/v1.2.7)。
