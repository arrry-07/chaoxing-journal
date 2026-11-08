# 学习通作业助手
处理学习通课程、作业、截止时间或提交状态时，先查本地参考实现 references/xuexitong-cli/xuexitong_mcp/client.py。重点看 fetch_homework、fetch_homework_detail 和 is_homework_pending。需要核对解析行为时使用 references/xuexitong-cli/tests/run_tests.py。需要逐课查询工具时可按该目录 README 和 pyproject.toml 使用 xxt hw-ls。
参考版本来自 https://github.com/DanMo661/xuexitong-cli/commit/74b843ad4a3439a6ee5ba33f6a3288d9be6ed990 ，原始许可保存在 references/xuexitong-cli/LICENSE。Android 业务在 study_assistant-1.1.0/local_app 中实现。
参考 CLI 的 Python 环境由维护者本机自行准备，不假定仓库存在固定虚拟环境。先在 `references/xuexitong-cli` 下确认 Python 与依赖可用，再运行：
    python -B -m xuexitong_mcp.cli hw-ls --help
    python -B -c "import runpy; raise SystemExit(runpy.run_path('tests/run_tests.py')['run_all']())"
如果 `python` 指向 Microsoft Store/WindowsApps stub 或依赖未安装，应先配置可用 Python 环境；不要将个人虚拟环境绝对路径写进项目规则。当前本机复核发现历史硬编码路径 `%LOCALAPPDATA%/xxt-reference-venv/Scripts/python.exe` 不存在，当前 Python 命令解析为 WindowsApps stub，因此上述参考 CLI/测试命令尚未在本机重新验证。摘取部分使用核心测试入口 run_all()；独立桌面应用测试套件在上游仓库。
