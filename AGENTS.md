# 学习通作业助手
处理学习通课程、作业、截止时间或提交状态时，先查本地参考实现 references/xuexitong-cli/xuexitong_mcp/client.py。重点看 fetch_homework、fetch_homework_detail 和 is_homework_pending。需要核对解析行为时使用 references/xuexitong-cli/tests/run_tests.py。需要逐课查询工具时可按该目录 README 和 pyproject.toml 使用 xxt hw-ls。
参考版本来自 https://github.com/DanMo661/xuexitong-cli/commit/74b843ad4a3439a6ee5ba33f6a3288d9be6ed990 ，原始许可保存在 references/xuexitong-cli/LICENSE。Android 业务在 study_assistant-1.1.0/local_app 中实现。
参考 CLI 的 Python 环境由维护者本机自行准备，不假定仓库存在固定虚拟环境。先在 `references/xuexitong-cli` 下确认 Python 与依赖可用，再运行：
    python -B -m xuexitong_mcp.cli hw-ls --help
    python -B -c "import runpy; raise SystemExit(runpy.run_path('tests/run_tests.py')['run_all']())"
如果 `python` 指向 Microsoft Store/WindowsApps stub 或依赖未安装，应先配置可用 Python 环境；不要将个人虚拟环境绝对路径写进项目规则。当前本机复核发现历史硬编码路径 `%LOCALAPPDATA%/xxt-reference-venv/Scripts/python.exe` 不存在，当前 Python 命令解析为 WindowsApps stub，因此上述参考 CLI/测试命令尚未在本机重新验证。摘取部分使用核心测试入口 run_all()；独立桌面应用测试套件在上游仓库。

## 工程状态与按需交接

- 新任务或接手时，先读本文件和 `docs/ai-workflow/PROJECT_STATE.md`，核对实际工作目录、分支、HEAD、工作区及暂存区；只按当前目标读取相关计划、验收记录和实现，不遍历全部历史。状态文件缺失时根据现场证据建立，不猜测历史。
- `PROJECT_STATE.md` 是可过时的当前工作摘要，不代替代码、Git、原始检查结果或远端状态。区分计划、已修改、检查通过、实际运行验证、已提交、已推送与已发布；证据注明时间、源码提交或工作区范围及未覆盖项。后续修改不能自动继承旧测试结果。
- 完成有实质成果的任务、关键决策/验证/阻塞变化，或用户要求“保存进度”时，增量更新状态。长任务在重要进展后保存；普通问答、微小修改和无变化的重复检查不新增记录。已有计划、验收及交付证据直接引用，不重复建立流程。
- 仅在用户要求交接、准备切换对话或暂停复杂任务时，在 `docs/ai-workflow/handoffs/` 按日期和任务命名保存交接记录，并在状态文件链接最新相关记录。交接包括目标与约束、成果与证据、未完成项、下一项具体动作和可复制的接手提示；目录按需创建。
- 同一任务的开发、审查、修复和回归可以持续在同一对话完成；不按工序、上下文占用或压缩次数强制停止。保留现有压缩行为，用户自行决定手动压缩；本机制不修改压缩阈值、上下文窗口、Provider 或模型路由，不新增 Hooks、后台任务或自动创建对话。
- 并行任务各自维护已有任务记录，由明确的一方更新项目总览；更新前重读当前文件，保留其他任务进展，不把自己的完成状态覆盖到整个项目。接手提示只指向已授权的下一步，不自动扩大授权；历史阶段的临时限制不能直接当作本轮指令。
- 保留已有修改与未知来源文件；状态及交接不得包含密码、令牌、Cookie、会话内容、私密账号响应或敏感日志。提交时仅包含本次任务的精确范围，遵守当前有效的 Git 与发布授权。
