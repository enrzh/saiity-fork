# Task 2 报告：辅助页面交互与 geometry 回归

## 结果

Task 2 的 stale test contract 清理已完成并提交。提交：`e1b546e`（`清理语音键盘测试契约`）。

本轮仅修改两个测试文件：`testLayoutUsesTheRuntimeSurfaceHeightForBottomActions`
改为由当前 layout frames 与 `VoiceOnlyKeyboardPolicy` 常量推导 bottom action 关系；
`testLatestVoiceLayoutUsesThreeLeftTargetsAndBottomDismiss` 的 emoji 到 number 间距
改用 `VoiceOnlyKeyboardPolicy.railSpacing`。

## 真实测试输出

基线目标测试：`Executed 2 tests, with 0 failures (0 unexpected)`，未出现 RED（本轮为已完成生产实现后的契约去硬编码）。

修正后 focused 命令：`Executed 7 tests, with 0 failures (0 unexpected)`。

完整命令：`swift test --package-path DictusCore`。

结果：`Executed 1350 tests, with 10 tests skipped and 0 failures (0 unexpected)`。

`git diff --check`：通过。commit 内容仅包含 `VoiceOnlyKeyboardContractTests.swift`。

## Concerns

- SwiftPM 测试仍报告既有未声明资源 warning：`DictusCore/Sources/polish-harness/README.md`；完整测试还输出既有 `FrequencyDictionary` 测试诊断日志，但不影响通过结果。
- 本轮未重新执行 xcodebuild 或 SimSlim UI build；本次范围仅为测试契约修复。
- 其它 dirty/untracked 文件保持原状；`task-2-report.md` 本次更新未提交。
