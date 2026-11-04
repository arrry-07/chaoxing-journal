# 离线字体

本目录字体沿用仓库 c61bb15 中的 Noto Sans SC / Noto Serif SC 字形，没有新增外部字体下载或运行依赖。两份 SIL OFL 1.1 许可保持原文件。

- `JournalBody.ttf`：Noto Sans SC 常规400，30,890个 Unicode 映射。
- `JournalBody-Semibold.ttf`：同一字体的强调600，同样覆盖30,890个映射。
- `JournalTitle.ttf`：Noto Serif SC 常规400，沿用原61字符子集，仅用于首页“课业手记”。展示字体缺字显式回退到正文。

2026-11-05 使用 FontTools `instantiateVariableFont(font, {'wght': weight})` 从原变量文件生成静态实例，再以 `subset.Subsetter` 保留全部原 cmap 字符和默认排版特性。转换后两份正文字体 cmap 完全一致，OS/2 实际字重分别为400、600，不再由未声明的100默认轴或设备合成决定。pubspec明确声明相应字重；展示标题默认轴由200固定为400。

正文＋标题总大小由17,805,024字节变为21,086,760字节，约增加3.13 MiB，换取完整中文覆盖与两个真实字重。通用页面、按钮、表单、导航、弹窗及分区标题使用正文家族，宋体不用于动态课程名和作业标题。

验收时需同时载入400、600以及Material图标。仅在测试中加载常规字体会导致截图使用合成粗体，与Android打包后的真实字重不同。
