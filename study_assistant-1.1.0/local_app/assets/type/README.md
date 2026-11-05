# 霞鹜文楷屏幕阅读版

应用全部界面文字使用同一个离线手写风字体，包含展示标题、中文正文、英文、数字、按钮、输入框、导航和弹窗。

- 原始字体：[LXGW WenKai Screen v1.530](https://github.com/lxgw/LxgwWenKai-Screen/releases/tag/v1.530)，文件 LXGWWenKaiScreen.ttf，未修改、未裁剪。
- SHA256：ABD13364163E3CD84372B333F2FDCEE9EFB848634668F1C0CE5788DCD059EE61。
- 实际字重400，包含47,883个Unicode映射；检查应用源码中的458个汉字均有字形。强调文字由Flutter按请求字重绘制，保持同一家族。
- SIL OFL 1.1许可保存在 OFL-WenKai.txt，并在应用开源许可页注册。保留作者版权与字体内部名称，不联网加载。
- 原Noto正文、粗体、宋体资产及旧许可已移入本地忽略的artifacts/archive/fonts，不再打包。

字体渲染验收会检查真实RichText字形样式和EditableText字体继承，而非只断言ThemeData。字体原始文件约24.9MiB，与此前三文件约20.1MiB相比增加约4.8MiB。