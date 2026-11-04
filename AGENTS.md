# 学习通作业助手
处理学习通课程、作业、截止时间或提交状态时，先查本地参考实现 references/xuexitong-cli/xuexitong_mcp/client.py。重点看 fetch_homework、fetch_homework_detail 和 is_homework_pending。需要核对解析行为时使用 references/xuexitong-cli/tests/run_tests.py。需要逐课查询工具时可按该目录 README 和 pyproject.toml 使用 xxt hw-ls。
参考版本来自 https://github.com/DanMo661/xuexitong-cli/commit/74b843ad4a3439a6ee5ba33f6a3288d9be6ed990 ，原始许可保存在 references/xuexitong-cli/LICENSE。Android 业务在 study_assistant-1.1.0/local_app 中实现。
本机的逐课 CLI 已验证可启动。在 references/xuexitong-cli 下，用 PowerShell 运行：
    & "$env:LOCALAPPDATA/xxt-reference-venv/Scripts/python.exe" -B -m xuexitong_mcp.cli hw-ls --help
验证摘取部分使用核心测试入口 run_all()；独立桌面应用测试套件在上游仓库。
    & "$env:LOCALAPPDATA/xxt-reference-venv/Scripts/python.exe" -B -c "import runpy; raise SystemExit(runpy.run_path('tests/run_tests.py')['run_all']())"
