# Task 2 键盘设置报告

## Status

已完成键盘控制顺序设置。现有 `Keyboard` Section 保留 `Models` 行，并新增原生 SwiftUI `Picker`，仅提供 `Emoji, 123` 与 `123, Emoji` 两个选项。

## TDD RED/GREEN

先新增 `KeyboardOrderSettingsContractTests`，在设置页尚未实现 Picker 时运行：

```text
Executed 1 test, with 3 failures (0 unexpected)
XCTAssertTrue failed: 缺少 KeyboardAccessoryOrder、App Group store 与两个选项契约
```

实现后聚焦测试：

```text
Executed 1 test, with 0 failures (0 unexpected)
```

完整测试：

```text
swift test --package-path DictusCore --scratch-path /tmp/saiity-keyboard-settings-green
Executed 1264 tests, with 10 tests skipped and 0 failures (0 unexpected)
```

## Files

- `DictusApp/Views/SettingsView.swift`
  - 使用 `@AppStorage(SharedKeys.keyboardAccessoryOrder, store: UserDefaults(suiteName: AppGroup.identifier))`。
  - 默认 raw value 为 `KeyboardAccessoryOrder.emojiFirst.rawValue`。
  - Picker 通过 `KeyboardAccessoryOrder.allCases` 和 `displayName` 渲染两个选项；非法值回落 `emojiFirst`。
  - 未恢复 keyboard language/layout/number row/haptic/sounds/autocorrect 等旧入口。
- `DictusCore/Tests/DictusCoreTests/KeyboardOrderSettingsContractTests.swift`
  - 锁定 App Group store、当前枚举选择及显示名，并排除旧设置入口。

## Concerns

- 完整测试在 macOS 主机上有 10 个既有 App Group 权限相关 skipped 测试。
- 测试输出仍有既有 Swift 6 并发 warning、未处理 README warning，以及 `FrequencyDictionary` fixture 解码诊断；本次测试最终退出成功。
- 未运行 iOS Simulator UI 测试；本任务要求的设置源码契约和 DictusCore 全量测试均已通过。
