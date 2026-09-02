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
