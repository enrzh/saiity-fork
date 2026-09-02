# Task 4: UIKit/SwiftUI 辅助页集成报告

## 结果

已完成最小集成：UIKit 与 SwiftUI 都读取 `KeyboardAccessoryOrder.current`；emoji/symbols auxiliary mode 下 UIKit 控件全部 hidden、disabled 且不可命中，辅助内容继续由 SwiftUI 处理。语音态恢复控件交互。未修改 Vendored 文件。

## RED

命令：`swift test --package-path DictusCore --scratch-path /tmp/saiity-task4-red --filter VoiceOnlyKeyboardContractTests`

结果：执行 55 个测试，5 个失败。失败来自当时的辅助页 surface/legacy contract 与当前实现不一致，确认测试需要先调整。

## GREEN

命令：`swift test --package-path DictusCore --scratch-path /tmp/saiity-task4-focused --filter VoiceOnlyKeyboardContractTests`

结果：执行 57 个测试，0 个失败。新增/调整契约覆盖当前顺序消费、辅助态 ownership/hit target，以及既有 mic 生命周期、delete repeat、routing 和 policy frame。

## 验证

- `git diff --check`：通过，无输出。
- `swift test --package-path DictusCore --scratch-path /tmp/saiity-task4-full3`：1273 tests，10 skipped，2 failures。失败为未纳入 Task 4 的 `VoiceOnlyKeyboardPolicyTests.testExpandedAlternateSurfaceKeepsLeftUtilitiesVisibleAboveItsContent`，其旧断言要求 auxiliary UIKit 控件可见，与 Task 4 的全部隐藏要求冲突。
- `xcodebuild build -project Dictus.xcodeproj -scheme sAiity-iOS -configuration Debug -destination 'platform=iOS Simulator,id=AC636497-5EC6-4AD4-BD83-E5E2458FA702' -derivedDataPath /tmp/saiity-task4-build4`：失败于既有 `DictusApp/Views/SettingsView.swift:30` 的 `Consecutive statements on a line must be separated by ';`，该文件无本次修改。
- 未运行物理设备、DeviceHub 或 TestFlight；未进行 simulator 安装/视觉验证，因为构建被上述既有错误阻断。

## 文件

- `DictusKeyboard/KeyboardViewController.swift`：共享当前顺序；auxiliary UIKit controls hidden/disabled/non-hit-testable；语音态恢复。
- `DictusKeyboard/KeyboardRootView.swift`：SwiftUI policy layout 读取同一当前顺序；修正 symbols content height 作用域。
- `DictusCore/Tests/DictusCoreTests/VoiceOnlyKeyboardContractTests.swift`：更新当前 source contracts 并增加行为约束。

## Concerns

完整 suite 的旧 policy 测试和 App target 的 settings 语法错误仍需单独处理；本任务按要求未修改或暂存这些范围外文件。现有 dirty 的两个 Vendored 文件也保持原样。
