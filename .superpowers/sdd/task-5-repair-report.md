# Task 5 Repair Report

## Scope

- Repository: `/Users/enrico/Documents/GitHub/sAiity-dictus`
- Branch: `saiity-fork`
- 修复范围严格按 `task-5-repair-brief.md` 执行。
- 未创建 checkout，未重置、清理或覆盖已有改动；未修改已完成的键盘 UI 实现。

## Changed files

本轮实际修改：

- `DictusApp/Views/SettingsView.swift`
  - 将 malformed `Picker` 改为 `Picker(selection: keyboardAccessoryOrderBinding, label: Text("Control order"))`。
  - 保留原有 binding、`KeyboardAccessoryOrder.emojiFirst`、`.numberFirst` 和同一 `Keyboard` section 内的 `Models` link。
- `DictusCore/Sources/DictusCore/VoiceOnlyKeyboardPolicy.swift`
  - 删除只提供兼容转发的顶层 `rightRailFrames(for:)`、`leftUtilityFrames(for:)`、`dismissFrame(for:)`。
- `DictusCore/Tests/DictusCoreTests/VoiceOnlyKeyboardPolicyTests.swift`
  - 将辅助页测试改为验证 `auxiliaryContentFrame` 负责内容表面，且旧 UIKit voice utilities 在辅助页隐藏。
  - 将原有顶层 accessor 调用迁移到 `VoiceOnlyKeyboardPolicy.layout(...).<frame>`。
- `DictusCore/Tests/DictusCoreTests/VoiceOnlyKeyboardContractTests.swift`
  - 添加 Settings `Picker` 语法及 Keyboard section 内容的源码回归断言。

任务开始前已存在且原样保留的改动：

- `.superpowers/sdd/task-2-keyboard-order-report.md`
- `DictusKeyboard/Vendored/Models/KeyboardDefinition.swift`
- `DictusKeyboard/Vendored/Views/KeyboardView.swift`
- `.superpowers/brainstorm/`
- `docs/superpowers/plans/2026-09-02-keyboard-auxiliary-surface.md`
- `docs/superpowers/plans/2026-09-02-native-keyboard-surface-redesign.md`
- `docs/superpowers/specs/2026-09-02-keyboard-auxiliary-surface-design.md`

## Helper accessor decision

保留 `VoiceOnlyKeyboardPolicy.Layout` 上的 `leftUtilityFrames`、`rightRailFrames` 和 `dismissFrame`，删除同名的顶层静态 helper。调用扫描显示 `DictusKeyboard` 只消费 `layout.leftUtilityFrames`、`layout.rightRailFrames` 和 `layout.dismissFrame`；仓库源码和测试中没有生产代码调用三个顶层 accessor。它们只是旧兼容 API，因此按 brief 删除，并把策略测试迁移到单一 `layout(...)` 返回值。没有删除任何仍被 `DictusKeyboard` 使用的 API。

## TDD and verification

RED evidence:

- `swift test --package-path DictusCore --scratch-path /tmp/saiity-dictus-repair-policy --filter VoiceOnlyKeyboardPolicyTests`
  - 基线：exit 1；64 tests，2 failures，均为旧的辅助页 utility 可见性断言。
- `swift test --package-path DictusCore --scratch-path /tmp/saiity-dictus-repair-contract --filter VoiceOnlyKeyboardContractTests`
  - 新增 Settings 回归断言后：exit 1；58 tests，1 failure，仅为 malformed `Picker` 语法断言。

GREEN evidence:

- `swift test --package-path DictusCore --scratch-path /tmp/saiity-dictus-repair-policy --filter VoiceOnlyKeyboardPolicyTests`
  - exit 0；64 tests，0 failures。
- `swift test --package-path DictusCore --scratch-path /tmp/saiity-dictus-repair-contract --filter VoiceOnlyKeyboardContractTests`
  - exit 0；58 tests，0 failures。
- `xcodebuild -quiet -project Dictus.xcodeproj -scheme DictusApp -configuration Debug -destination 'generic/platform=iOS' -derivedDataPath /tmp/saiity-dictus-repair-xcode.19g4is build CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO`
  - exit 0；`DictusApp` Debug generic iOS 编译通过，Settings 的 Picker 类型错误不再出现。
- `git diff --check`
  - exit 0；无 whitespace error。

SwiftPM/Xcode 输出仍包含仓库已有的弃用、Swift 6 concurrency/sendability、未使用局部变量及 SwiftPM unhandled README warning；这些不是本任务新增的失败，未扩大范围处理。

## Concerns

- 按 brief 未运行实体手机、DeviceHub、iPhone Mirroring、TestFlight、release 或设备运行时验证；因此本报告只证明源码、SwiftPM contract/policy tests 和 generic compile，不宣称真实键盘交互验收。
- 删除的顶层 accessor 是 public API；仓库内已确认无生产调用，但若存在仓库外消费者，需要改用 `VoiceOnlyKeyboardPolicy.layout(...).<frame>`。
- 当前 checkout 仍保留任务开始时的其它 dirty/untracked/ahead-of-origin 状态；本轮提交只包含上述 5 个文件。
