# sAiity-fork 键盘布局实现报告

## 修改文件

- `DictusCore/Sources/DictusCore/VoiceOnlyKeyboardPolicy.swift`
  - 左侧收敛为 @、emoji、123；@ 位于上方，emoji 与 123 位于底部控制区。
  - 保持 216pt fallback 与 runtime height；右侧 delete/return/dismiss 使用 88x44 命中框。
  - 备用页内容区域避开右侧 rail，并保留动态窄屏 rail 判断。
- `DictusKeyboard/KeyboardRootView.swift`
  - 使用共享 geometry；保留 iOS 26 `glassEffect` 与旧系统 material/semantic fallback。
  - 移除 globe 视觉入口，保留中心 microphone 与现有 global controls。
- `DictusKeyboard/KeyboardViewController.swift`
  - 移除 switch-keyboard/globe UIKit 控件、事件路由与 globe delegate；保留 proxy、Emoji/number owner、delete repeat、dismiss routing。
  - 123 打开 symbols1，ABC/关闭回到 normal。
- `DictusKeyboard/KeyboardLayouts.swift`
  - 移除 needsGlobe 布局参数及符号页相关 globe 输入。
- `DictusKeyboard/Vendored/Views/KeyboardView.swift`
  - 移除旧 globe cell 的隐藏 overlay 与 delegate wiring。
- `DictusCore/Tests/DictusCoreTests/VoiceOnlyKeyboardPolicyTests.swift`
- `DictusCore/Tests/DictusCoreTests/VoiceOnlyKeyboardContractTests.swift`
  - 更新旧的四控件/globe 断言，增加三左控件与底部 dismiss geometry contract。

## 测试

命令：

```text
swift test --package-path DictusCore --filter 'VoiceOnlyKeyboardPolicyTests|VoiceOnlyKeyboardContractTests|KeyboardAreaModeTests'
```

原样结果摘要：

```text
Test Suite 'Selected tests' passed
Executed 69 tests, with 0 failures (0 unexpected)
```

generic keyboard build 尝试：

```text
xcodebuild -project Dictus.xcodeproj -scheme DictusKeyboard -configuration Debug -sdk iphonesimulator CODE_SIGNING_ALLOWED=NO build
```

原样结果：

```text
error: unable to attach DB: ... build.db: database is locked
** BUILD FAILED **
```

随后用独立 `-derivedDataPath /tmp/saiity-dictus-keyboard-build` 重试，但在本轮未能取得最终输出；没有创建 simulator，也没有使用物理 iPhone。

## 未验证项 / concerns

- 未进行 simulator UI 截图或真实触控验证，因此 Liquid Glass 显示、不同 runtime 高度下的视觉 clipping 与实际 hit testing 仍需设备/模拟器验证。
- generic build 受并发/耗时影响未取得最终成功证明；focused DictusCore tests 已通过。
- 工作区中其他 app/model/dictation 文件的既有 dirty 改动未修改、未 stage。
