# Task 2 报告：emoji/symbol interaction + geometry

## 状态

实现完成。最新硬性要求为 shared surface fallback 从 216 精确增加 10%，因此采用 `216 * 1.10 = 237.6`。旧的 5%/226.8 版本已覆盖。

## RED

命令：`swift test --package-path DictusCore --filter KeyboardRegressionTests`

结果：执行 4 项，1 failure；新 10% 高度断言以旧实现 226.8 失败，确认 RED。

## GREEN

命令：`swift test --package-path DictusCore --filter KeyboardRegressionTests`

结果：执行 4 项，0 failures。

命令：`xcodebuild build -project Dictus.xcodeproj -scheme sAiity-iOS -configuration Debug -destination 'platform=iOS Simulator,id=AC636497-5EC6-4AD4-BD83-E5E2458FA702' -derivedDataPath /tmp/saiity-dictus-task2-build CODE_SIGNING_ALLOWED=NO`

结果：`BUILD SUCCEEDED`。仅使用指定 SimSlim UDID；`simslim status` 为 170/170 managed daemons disabled，`simslim verify` 通过。

## 测试摘要

- focused keyboard regression：4/4 passed（10% 断言）。
- Core full suite：1342 executed，10 skipped，27 failures（既有基线失败，非本次 focused regression）。
- `git diff --check`：通过。
- 未使用真实 iPhone、DeviceHub、iPhone Mirroring 或 TestFlight。

## 改动

- emoji 插入后移除 `state.closeArea()`，保持 emoji 页。
- 移除符号页父级 competing `simultaneousGesture`，普通 tap 由 Button 提交。
- `@` frame 改为与 emoji frame 使用相同 `railSpacing` 垂直 gap；emoji 到 123 已使用该常量。
- fallback 改为 `216 * 1.10`；保留原有非法输入和全屏输入高度的边界安全逻辑。

## Commit

初始任务提交：`52c03f7f7e713259d2361a704e70ec0dd8c5d643`

最终 amend 提交：`0eaa73d6abda773e39b1629b0db4a8b88d2464fc`

## 风险 / concerns

- Core 全套仍有 27 个基线失败，本次未扩大范围处理。
- Xcode 构建有既有 unhandled README、Sendable 等 warning；未发现本次改动导致的编译失败。
- 本次完成了 SimSlim 构建与 profile 验证，但未进行额外 UI 截图自动化；运行时交互风险仍需后续人工复核。
