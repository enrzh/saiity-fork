# Task 3 报告

## 根因调查

`123` 的状态转换路径本身存在：公共按钮调用 `presentArea(.panel)`，状态发布后 controller 安装并显示 `symbols1`。不可观察切换的根因是公共控件只在 `keys/recording` 视觉显示，且 alternate 内容使用的宽度没有遵循 `VoiceOnlyKeyboardPolicy` 的 center region，造成 panel/emoji 的公共动作与内容层边界不一致。symbols 页底行也必须由公共 UIKit 控件拥有，避免重复动作和不可见拦截层。

## 改动文件

- `DictusCore/Sources/DictusCore/KeyboardAreaMode.swift`
- `DictusCore/Tests/DictusCoreTests/KeyboardAreaModeTests.swift`
- `DictusCore/Sources/DictusCore/VoiceOnlyKeyboardPolicy.swift`
- `DictusKeyboard/KeyboardRootView.swift`
- `DictusKeyboard/KeyboardViewController.swift`
- `DictusKeyboard/KeyboardLayouts.swift`
- `DictusKeyboard/Views/EmojiCategoryBar.swift`
- `DictusKeyboard/Views/EmojiPickerView.swift`

公共模式控件现在在 alternate surface 保持可见并显示 `ABC`；emoji 与 symbols 使用 shared policy 的 center region；symbols 页不再复制底部公共动作；delete/return/dismiss 与左右按钮继续由 UIKit 公共命中区域处理。

## TDD RED

命令：`swift test --package-path DictusCore --filter KeyboardAreaModeTests/testModeControlTitleReflectsTheVisibleSurface`

结果：按预期失败，编译器报告 `KeyboardAreaMode` 没有 `modeControlTitle`，证明回归测试捕获了缺失行为。

## GREEN

命令：`swift test --package-path DictusCore --filter KeyboardAreaModeTests`

结果：14 tests，0 failures。

覆盖的现有测试还核对 mode 转换、公共 rail 几何、44x44 命中目标和 88x44 delete/return 区域。

## 构建

命令：`xcodebuild -project Dictus.xcodeproj -scheme DictusKeyboard -sdk iphonesimulator -configuration Debug build CODE_SIGNING_ALLOWED=NO`

结果：`BUILD SUCCEEDED`。存在既有 deprecated/API 与 Sendable warnings。

完整 Core 命令 `swift test --package-path DictusCore`（此前基线）：1155 tests，10 skipped，4 failures。失败集合为 `PolishAvailabilityGateTests.testUnavailableAutoModeReturnsTheAutoFloor`、`PolishAvailabilityGateTests.testTheDefaultGateLeavesTheTransformUntouched`、`PolishContextBudgetTests.testTransformRunsAnUnboundedEngineOnAnEnormousInput`、`PolishContextBudgetTests.testTransformStillCallsTheEngineWhenTheInputFits`。本次复跑已为 1155 tests、10 skipped、0 failures。

## 差异检查与提交

`git diff --check`：通过。

Commit：实现提交为 `1702c1c230dc6c09ee647825339f2e4685e4c0c3` 和 `6ce9f5062d3a8253b4022c757a93e15023747752`。报告本身不记录自引用 hash；当前提交以 `git log -- .superpowers/sdd/task-3-report.md` 为准。

## 未验证风险

- 尚未在 SimSlim 中完成实际触控截图/命中回放，因此 123、ABC、emoji、delete、return、dismiss 的真实 UIKit 触控链仍需设备级验证。
- 完整 Core 基线失败集合已在上方列出；本次复跑已清零。
- 构建使用无签名 simulator generic build，不等同于安装或发布验证。

## 本轮独立审查修复

- RED：`swift test --package-path DictusCore --filter 'KeyboardAreaModeTests|VoiceOnlyKeyboardPolicyTests|VoiceOnlyKeyboardContractTests'` 捕获 3 个旧 bottom-row/全宽契约失败。
- GREEN：同一命令通过，64 tests，0 failures。
- 修复 number keyboard frame，使 x、width、height 分别与 policy center region 和 alternate content height 一致；保留公共 UIKit controls 及其 hit targets。
- 删除外层 `EmojiPickerView.onDelete`，保留搜索输入内部 delete；删除 `bottomRow` dead helper 并统一使用空白保留行。
- 构建：`xcodebuild -project Dictus.xcodeproj -scheme DictusKeyboard -sdk iphonesimulator -configuration Debug -derivedDataPath /tmp/saiity-keyboard-fix-build CODE_SIGNING_ALLOWED=NO build`，结果 `BUILD SUCCEEDED`。
- `git diff --check`：通过。
- 本轮聚焦修复前 RED 集合：`VoiceOnlyKeyboardContractTests.testUIKitOverlayIsHiddenWhenPolicyHasNoRightRail`、`VoiceOnlyKeyboardPolicyTests.testActionCentersAndRectanglesFitWithoutOverlapAtTargetWidths`、`VoiceOnlyKeyboardPolicyTests.testNormalPhoneWidthsKeepFourUtilityTargetsOutsideCenterSurface`、`VoiceOnlyKeyboardPolicyTests.testRightRailUsesThreeCommandsAndOneSeparateDismissAction`、`VoiceOnlyKeyboardPolicyTests.testVoiceSurfaceExposesStableCenterAreaAndRailGeometry`。
- 本轮 GREEN：聚焦测试 65 tests，0 failures；完整 Core 复跑 1155 tests、10 skipped、0 failures。
