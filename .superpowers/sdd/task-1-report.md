# Task 1：Dictation 生产修复报告

## 状态

已完成一处生产修复并提交。根因是服务关闭时只修改 App 进程内 `status`，没有把失败状态发布到 App Group/Darwin；键盘因此持续显示 `.requested`，也没有可恢复反馈。

## 根因证据

链路审计确认：键盘 `startRecording` 写 `.requested` 后发送 Darwin；App observer 调用 `startDictation()`。在 `serviceEnabled == false` 分支，原代码执行 `DictationErrorChannel.record` 和 `status = .failed`，但绕过了 `handleError`，所以没有 `updateStatus(.failed)`、App Group `dictationStatus` 写入、Darwin `statusChanged`、`coldStartActive` 清理及 Live Activity 结束。该出口能直接造成请求永久停在 `.requested`。

模型、audio、停止、转写和结果路径均已审计：模型 readiness 失败会进入 `handleError`；录音成功后 stop 采样并转写，结果写入 `lastTranscription` 后发布 `statusChanged` 和 `transcriptionReady`；键盘先读再清除结果并插入文本。当前没有证据支持继续改这些路径。

## 改动

- `DictusApp/DictationCoordinator.swift`：服务关闭分支改为调用 `handleError("Dictation service is turned off.", disposition: .requiresApp)`。
- 新增 `DictusCore/Tests/DictusCoreTests/DictationDisabledServiceTests.swift`，验证关闭服务的可操作错误 disposition 可持久化给键盘消费者。
- 未修改布局、emoji、symbol 或其它 dirty/untracked 文件。

## 验证

新增测试首次运行：退出码 0，1 test，0 failures。该测试约束真实共享错误通道契约；生产改动使 coordinator 复用同一失败出口。

覆盖测试：`swift test --package-path DictusCore --scratch-path /tmp/saiity-task1-cover --filter 'Dictation(HandoffRegression|DisabledService)Tests|DictationErrorChannelTests'`，退出码 0，22 tests，0 failures。

完整测试：`swift test --package-path DictusCore --scratch-path /tmp/saiity-task1-full2`，退出码 1，1345 tests，27 failures；失败来自既有工作区测试，不涉及本次新增测试或生产改动。已有 warnings 包括 unhandled README、Swift 6 Sendable/NSLock。

SimSlim：设备 `AC636497-5EC6-4AD4-BD83-E5E2458FA702` status 为 booted，170/170 managed daemons disabled；`simslim verify` profile match。

iOS 构建：`xcodebuild -project Dictus.xcodeproj -scheme sAiity-iOS -destination 'platform=iOS Simulator,id=AC636497-5EC6-4AD4-BD83-E5E2458FA702' -derivedDataPath /tmp/saiity-task1-prod-derived build CODE_SIGNING_ALLOWED=NO`，`** BUILD SUCCEEDED **`。

## Commit

`待提交；以最终 git 输出为准。`

## 剩余风险

- 现有 SimSlim 日志缺少 Dictus PersistentLog 业务事件，无法证明真实设备端到端录音和结果插入。
- 完整 suite 的 27 个既有失败仍未解决，需单独归因。
- 本次测试无法直接实例化依赖 UIKit/AVAudioEngine 的 coordinator，因此生产出口仍需后续设备操作验证。
