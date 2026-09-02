# Task 3 实现报告

日期：2026-09-02
基线：`54bded4`
实现 commit：`41e0fc5fe4e9b021923727dbf6fc1bac94c41776`

## RED

先在现有 DictusCore policy/source-contract tests 中加入最小契约：

```text
swift test --package-path DictusCore --filter 'VoiceOnlyKeyboardPolicyTests|VoiceOnlyKeyboardContractTests'
```

第一次运行因新 policy API 尚不存在而编译失败：

```text
error: value of type 'VoiceOnlyKeyboardPolicy.Layout' has no member 'alternateAccessoryFrames'
```

将该条改为可编译的 source-contract RED 后再次运行，得到预期 XCTest 失败：

```text
Executed 92 tests, with 19 failures (1 unexpected)
```

失败集中在 accessory frames、辅助模式控件 visibility/routing、symbols 内容 frame、root backdrop 和 pressed corner radius，证明测试覆盖的是尚未实现的 task 3 行为。

## GREEN

实现后运行 focused suite：

```text
swift test --package-path DictusCore --filter 'VoiceOnlyKeyboardPolicyTests|VoiceOnlyKeyboardContractTests'
```

结果：

```text
Executed 92 tests, with 0 failures (0 unexpected)
```

完整 suite：

```text
swift test --package-path DictusCore
```

结果：

```text
Executed 1227 tests, with 10 tests skipped and 0 failures (0 unexpected)
```

现有 SwiftPM warning（未处理的 polish-harness README、Swift 6 Sendable warning）以及既有 frequency fixture 解码诊断仍会输出，但没有失败。

## 实现内容

- `DictusCore/Sources/DictusCore/VoiceOnlyKeyboardPolicy.swift`
  - 在现有 `Layout` 增加 accessory revert/mic/delete/return 四个绝对 frame和 frames 集合。
  - mic frame 的中心严格等于 accessory row 中心；正常目标宽度下四个 hit frame 均至少 44pt 高且互不重叠。
- `DictusKeyboard/KeyboardRootView.swift`
  - auxiliary row 改为相对 row frame 的 `ZStack` 绝对定位，避免不对称左右控件导致 mic 偏移。
  - auxiliary 静态视觉只保留 revert、白色 mic、delete、appleControlSurface 圆形 return，并保持 `allowsHitTesting(false)`。
  - auxiliary content 继续从 `alternateContentBelowAccessoryFrame` 开始；移除 auxiliary 下的额外固定 system background 矩形。
  - voice 模式原有语言、delete、return、dismiss 视觉路径保留。
- `DictusKeyboard/KeyboardViewController.swift`
  - emoji/symbols 模式隐藏 at、emoji、dismiss；现有 number/mic/delete/return 控件使用 accessory frames。
  - voice/recording 继续使用原有 voice frames；保留 mic touch lifecycle、delete repeat、return、dismiss routing 和 symbols page navigation。
  - symbols `numberKeyboardView` 在辅助状态放到 `alternateContentBelowAccessoryFrame`，不再覆盖 accessory row。
  - frame 更新后按实际 button bounds 更新 corner radius，主 voice mic 与 SwiftUI capsule 高度一致。
  - `.keyboard` UIInputView、clear background、nonopaque 设置保留。
- `DictusCore/Tests/DictusCoreTests/VoiceOnlyKeyboardPolicyTests.swift`
  - 新增四 frame 的中心、边界、44pt 和不重叠契约；更新旧 alternate content 断言。
- `DictusCore/Tests/DictusCoreTests/VoiceOnlyKeyboardContractTests.swift`
  - 新增辅助模式 ownership/visibility、静态 row 和 backdrop/radius source contracts；更新旧 UIKit frame 断言。

## 构建与 SimSlim

`git diff --check`：通过。

generic iOS Simulator build：

```text
xcodebuild build -project Dictus.xcodeproj -scheme sAiity-iOS \
  -destination 'platform=iOS Simulator,id=AC636497-5EC6-4AD4-BD83-E5E2458FA702' \
  -derivedDataPath /tmp/saiity-dictus-task3 CODE_SIGNING_ALLOWED=NO
```

结果：

```text
** BUILD SUCCEEDED **
```

SimSlim 目标为既有授权设备 `AC636497-5EC6-4AD4-BD83-E5E2458FA702`，状态检查结果为 `109/170 managed daemons disabled`，即部分 slim。已确认 build 产物生成 `DictusApp.app` 和 `DictusKeyboard.appex`。

本次没有完成 voice/emoji/symbols 三状态的屏幕截图和逐个 hit target 的人工交互检查：当前 checkout 没有现成的键盘状态切换脚本，且本任务不允许使用实体 iPhone。该部分是明确的 runtime follow-up，不作为已完成的截图证据或发布结论。

## 疑点

1. SimSlim 当前不是 `170/170`，而是 `109/170` 部分 slim；本次没有强制修复或修改其环境。
2. SwiftUI/ UIKit 的实际触控命中和 emoji/symbols 页面视觉仍需在 SimSlim 中打开键盘后人工确认；source contract、policy tests、完整 suite 和 generic build 已通过。
3. 没有运行实体 iPhone、没有安装实体设备、没有上传或发布操作。

## 修复轮次（2026-09-02）

基线：`41e0fc5fe4e9b021923727dbf6fc1bac94c41776`

### RED

先增加 focused policy/contract regression tests，覆盖短 surface fail-closed、辅助 row 两侧 `visibleControlGap` 留白，以及 controller 在辅助 frame 不可用时隐藏四个辅助控件：

```text
swift test --package-path DictusCore --filter 'VoiceOnlyKeyboardPolicyTests|VoiceOnlyKeyboardContractTests'
```

预期 RED 已确认：`Executed 95 tests, with 9 failures (0 unexpected)`。失败来自新增边界/间距断言和尚未存在的 controller visibility contract，不是测试编译错误。

### GREEN

修改文件：

- `DictusCore/Sources/DictusCore/VoiceOnlyKeyboardPolicy.swift`
- `DictusKeyboard/KeyboardViewController.swift`
- `DictusCore/Tests/DictusCoreTests/VoiceOnlyKeyboardPolicyTests.swift`
- `DictusCore/Tests/DictusCoreTests/VoiceOnlyKeyboardContractTests.swift`

行为：alternate accessory row 在 surface 高度小于 44pt 或宽度不足以容纳四个 hit target 与边缘留白时返回空 frame；可用时四个 frame 均在 row 内、至少 44pt 高、互不重叠，并在左右边缘保留 `visibleControlGap`。controller 用共享 frame 可用性隐藏辅助控件，避免向可交互按钮设置零/小 frame。未修改 emoji/model/app 代码，也未触碰 `.superpowers/brainstorm/`。

Focused：

```text
swift test --package-path DictusCore --filter 'VoiceOnlyKeyboardPolicyTests|VoiceOnlyKeyboardContractTests'
Executed 95 tests, with 0 failures (0 unexpected)
```

完整覆盖：

```text
swift test --package-path DictusCore
Executed 1230 tests, with 10 tests skipped and 0 failures (0 unexpected)
```

附加验证：`git diff --check` 通过。

### Commit

提交：`bde3e6656869579691b5016488702203df91c64b`

### 疑点

本轮未重复运行上一轮未完成的 SimSlim 三状态人工截图/逐个 hit target 检查；未运行实体 iPhone。测试输出仍包含既有未处理 README resource warning、Swift 6 Sendable warning，以及 frequency fixture JSON 解码诊断；均未造成测试失败。
