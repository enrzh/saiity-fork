# 73b89b8 审查 findings 修复报告

## 范围

本次仅修复 voice-only keyboard 的共享几何、键盘 vendored globe 路径及对应 focused contract tests。未修改 `DictusApp`、dictation pipeline、model pipeline，也未处理其他已有 dirty/untracked 文件。

## 修复内容

- `VoiceOnlyKeyboardPolicy`：标准高度下 `@` 位于 `height - 88`，emoji 与 `123` 同在 `height - 44`，并保持左对齐相邻；Delete/Enter 保持精确 `88 x 44` hit area，dismiss 保持右下角独立区域。
- runtime height 小于三组右侧 controls 所需高度时 fail-closed 隐藏 rails；mic frame 在过短高度下返回 zero，避免负坐标或越界 frame。正常 216pt 布局保持完整。
- 移除 vendored `SystemKeys` 的 globe 生成、`KeyView` globe 渲染、`KeySoundPolicy` globe 声音分类、controller globe 分支及无用 globe 类型；保留 `InputView` 的 `inputViewStyle: .keyboard`。
- focused tests 覆盖宽度 320/375/390/430、高度 64/88/96/216，断言 emoji/123 同 y、`number.x == emoji.maxX`、所有非零 action frames 在 bounds 内，并检查 globe 路径确实不存在。

## 验证

- `swift test --package-path DictusCore --filter 'VoiceOnlyKeyboardPolicyTests|VoiceOnlyKeyboardContractTests|KeyboardAreaModeTests'`
  - 通过：71 tests，0 failures（KeyboardAreaMode 15、VoiceOnlyKeyboardContract 18、VoiceOnlyKeyboardPolicy 38）。
- `xcodebuild -project Dictus.xcodeproj -scheme DictusKeyboard -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' -derivedDataPath /tmp/saiity-dictus-keyboard-build-fix build -quiet`
  - 通过，退出码 0；未创建或启动 simulator。

## 其他说明

首次并行误触发的第二次 build 因第一条串行 build 仍持有同一 derived data 的 `build.db` 锁而失败；等待锁释放后按同一命令重新执行并通过。未删除 derived data、未 reset/clean/stash。
