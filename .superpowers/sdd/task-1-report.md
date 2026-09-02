# Task 1 报告

## Status
完成实现并提交。工作树原有 dirty/未跟踪内容均未清理或覆盖。

## RED/GREEN
- RED：`swift test --package-path DictusCore --scratch-path /tmp/saiity-keyboard-order-red` 失败：找不到 `KeyboardAccessoryOrder`，`SharedKeys` 没有 `keyboardAccessoryOrder`，`layout` 不接受 `controlOrder`，并连带缺少新布局属性。
- GREEN：`swift test --package-path DictusCore --scratch-path /tmp/saiity-keyboard-order-green --filter KeyboardAccessoryOrderPreferenceTests` 通过，7 tests、0 failures。

## 完整测试
`swift test --package-path DictusCore --scratch-path /tmp/saiity-keyboard-order-full`：1262 tests executed、10 skipped、71 failures。

失败集中在范围外的 `VoiceOnlyKeyboardPolicyTests` 与 `VoiceOnlyKeyboardContractTests`，它们仍断言旧 top accessory-row 几何；按要求未修改。后续任务需要迁移这些旧断言到 inset surface/bottom auxiliary contract。构建期间另有仓库既有 Swift 6、异步锁和资源声明 warnings。

## 文件
- `DictusKeyboard/InputView.swift`：两个初始化路径设置 `backgroundColor = .clear`、`isOpaque = false`。
- `DictusCore/Sources/DictusCore/SharedKeys.swift`：新增专用共享 key。
- `DictusCore/Sources/DictusCore/KeyboardAccessoryOrder.swift`：新增两种顺序、`CaseIterable`/`Codable`、displayName、App Group helpers。
- `DictusCore/Sources/DictusCore/VoiceOnlyKeyboardPolicy.swift`：新增顺序参数及 inset/bottom frames；旧 API 仅保留弃用兼容访问器。
- `DictusCore/Tests/DictusCoreTests/KeyboardAccessoryOrderPreferenceTests.swift`：覆盖 fallback、持久化、显示名、frame 和透明初始化。

## Self-review
已检查 diff 范围，仅 stage 本任务五个文件及本报告；其他前序修改未 stage。

## Concerns
完整测试不能全绿，原因是旧测试契约冲突；迁移后应删除弃用兼容访问器。未执行 iOS 模拟器 UI 运行验证。

Commit: `feat: share keyboard auxiliary control order`

## Task 1 Repair（2026-09-02）

### RED/GREEN
- RED：`swift test --package-path DictusCore --filter VoiceOnlyKeyboardPolicyTests.testAlternatePagesUseTheFullNativeCanvasWithoutAnInset`：1 test、8 failures。实际 bottom lane 为 inset absolute 坐标（320 宽为 `(6,160,308,44)`），预期失败原因是 stale full-canvas/top-row assertion。
- GREEN：`swift test --package-path DictusCore --filter VoiceOnlyKeyboardPolicyTests`：64 tests、0 failures。
- GREEN：`swift test --package-path DictusCore --filter 'VoiceOnlyKeyboardPolicyTests|KeyboardAccessoryOrderPreferenceTests'`：71 tests、0 failures（最终 focused 合并运行）。
- Contract geometry smoke：`swift test --package-path DictusCore --filter VoiceOnlyKeyboardContractTests.testPolicyExposesAlternatePageAccessoryAndContentGeometry`：1 test、0 failures。

### 文件与变更
- `DictusCore/Tests/DictusCoreTests/VoiceOnlyKeyboardPolicyTests.swift`：迁移错误的 x=0/full-canvas/top-row 断言到 `surfaceFrame` absolute geometry；保留 44pt 高度、target 覆盖、containment 与 gap 检查。
- `DictusCore/Tests/DictusCoreTests/VoiceOnlyKeyboardContractTests.swift`：obsolete 列表仅保留 8 个 removed names；新 bottom/content frame 使用 inset absolute geometry；同步旧 top-row source 断言。
- `DictusCore/Tests/DictusCoreTests/KeyboardAccessoryOrderPreferenceTests.swift`：使用真实 `AppGroup.defaults`，仅清理 `SharedKeys.keyboardAccessoryOrder`，并更新测试命名。

### Self-review
已确认未修改 `DictusKeyboard` 生产文件；`git diff --check` 通过。工作树中其他 dirty 改动未清理、未覆盖、未 stage。

### 未完成跨任务风险
完整 `VoiceOnlyKeyboardContractTests` 当前为 55 tests、10 failures；剩余失败集中在尚未完成的 Task 3/4 UIKit/SwiftUI migration source contract（具体包括 alternate content source wiring、native height/runtime surface wiring、UIKit backdrop/geometry 等），本修复未用假断言掩盖，也未修改 DictusKeyboard 生产代码。构建仍有既有资源声明 warning。
