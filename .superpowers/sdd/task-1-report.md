# Task 1：Dictation 生产修复报告

## 状态

Task 1 reviewer findings 已完成并提交。HEAD 为 `6ed14b279ad1acb59a16b93d10b1560c47c9fb1d`。

## 根因证据

链路审计确认：键盘 `startRecording` 写 `.requested` 后发送 Darwin；App observer 调用 `startDictation()`。在 `serviceEnabled == false` 分支，原代码执行 `DictationErrorChannel.record` 和 `status = .failed`，但绕过了 `handleError`，所以没有 `updateStatus(.failed)`、App Group `dictationStatus` 写入、Darwin `statusChanged`、`coldStartActive` 清理及 Live Activity 结束。该出口能直接造成请求永久停在 `.requested`。

模型、audio、停止、转写和结果路径均已审计：模型 readiness 失败会进入 `handleError`；录音成功后 stop 采样并转写，结果写入 `lastTranscription` 后发布 `statusChanged` 和 `transcriptionReady`；键盘先读再清除结果并插入文本。当前没有证据支持继续改这些路径。

## 改动

- `DictusKeyboard/KeyboardViewController.swift`：将 `computeKeyboardHeight()` 的 policy fallback 改为 `Double(nativeHeight) * 1.10`。
- 纳入 `DictusCore/Tests/DictusCoreTests/DictationHandoffRegressionTests.swift`，覆盖 handoff retry/report、取消/超时、防止共享 controller 身份依赖、callback 路由和 10% runtime fallback。
- 仅提交上述两个文件；未修改或提交 Task 2 的 `KeyboardRegressionTests.swift`、报告、计划及其它已有 dirty/untracked 文件。

## 验证

TDD RED：`swift test --package-path DictusCore --filter 'DictationHandoffRegressionTests'`，退出码 1，5 tests，1 failure；失败为 fallback 字符串断言。

TDD GREEN：同一命令，退出码 0，5 tests，0 failures。输出包含既有 warning：`DictusCore/Sources/polish-harness/README.md` 未声明为 resource。

SimSlim：设备 `AC636497-5EC6-4AD4-BD83-E5E2458FA702` status 为 booted，170/170 managed daemons disabled；`simslim verify` profile match。

iOS 构建：`xcodebuild -project Dictus.xcodeproj -scheme sAiity-iOS -destination 'platform=iOS Simulator,id=AC636497-5EC6-4AD4-BD83-E5E2458FA702' -derivedDataPath /tmp/saiity-task1-prod-derived build CODE_SIGNING_ALLOWED=NO`，`** BUILD SUCCEEDED **`。

## Commit

`6ed14b279ad1acb59a16b93d10b1560c47c9fb1d`：`修复键盘运行时高度回退并纳入 Task 1 回归测试`

## 剩余风险

- 未修改 callback weak capture 的 Minor finding；当前实现仍依赖闭包捕获的 controller 生命周期，需后续结合实际键盘重建场景评估。
- 本次 focused suite 只验证源码契约与 DictusCore policy，未证明真实设备端到端录音和结果插入。
- 未运行完整 suite；本次证据范围仅为指定的 `DictationHandoffRegressionTests`。
