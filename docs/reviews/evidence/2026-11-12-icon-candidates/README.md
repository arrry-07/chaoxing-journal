# 1.7.3 应用图标候选

日期：2026-11-12（Asia/Shanghai）

本目录保存两种应用图标方向。候选 A 已采用并替换 Android 启动图标，候选 B 保留为比较记录。

- `candidate-a-book-check.png`：书页与勾选。
- `candidate-b-notebook-bookmark.png`：手记本与书签。

两张图均由内置 `image_gen` 生成，使用透明背景、平涂、无文字和安全区构图。最终资源应以选定方向重绘为可维护的 SVG/Android Vector，并复用应用现有纸色 `#F7F5EC`、深墨绿 `#243E34`、鼠尾草绿 `#DFE8D8`。

2026-11-12 最终采用 A。48px 对照中 A 的开放书页与勾选轮廓更清楚，B 在小尺寸下容易退化为深色块。对应的可编辑源码为：

- `art/app-icons/candidate-a-book-check.svg`
- `art/app-icons/candidate-b-notebook-bookmark.svg`

Android 资源由 `study_assistant-1.1.0/local_app/tool/generate_app_icons.py --candidate a --install` 生成。
