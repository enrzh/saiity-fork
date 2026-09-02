# Task 3：SwiftUI Emoji 与符号辅助页报告

## 状态

已完成实现并提交。`KeyboardViewController.swift` 未修改、未暂存；工作树中其它 dirty/untracked 内容保持原样。

## 本轮审查修复

- Emoji 与 symbols 现在均由根视图唯一包裹共享的 inset `embeddedSurface`；surface 外保持透明，辅助内容使用 surface 内局部坐标，避免重复绝对 inset。
- symbols page 1 的 `#+=` 切换 page 2；page 2 的 `ABC` 走既有 close voice 路径。
- Emoji 按键在 `accessibilityReduceMotion` 开启时禁用 snappy 与 scale 反馈，正常模式保留轻微反馈。
- focused contract tests 增加 shared surface、坐标清理、reduced motion 与 page2 close 路由约束。

## TDD 证据

先新增 `DictusCore/Tests/DictusCoreTests/AuxiliarySurfaceContractTests.swift`，覆盖：

- 辅助模式移除旧 `alternateAccessoryRow`，并使用共享 surface 结构；
- Emoji 分类栏固定左侧 mic 返回 voice，分类横向 ScrollView 独立滚动，分类项不使用 glass；
- 符号页三行布局、底部 emoji/mic 控件、页切换与 delete/return 路由，以及 44pt 命中区。

RED 命令：

`swift test --package-path DictusCore --scratch-path /tmp/saiity-keyboard-surfaces-red --filter AuxiliarySurfaceContractTests`

结果：失败，3 个测试共 8 个断言失败；失败原因是缺少返回闭包/固定 mic、分类项仍有 glass、符号控制契约未满足。首次运行还暴露测试 helper 缺失，补齐 helper 后得到上述预期 RED。

GREEN 命令：

`swift test --package-path DictusCore --scratch-path /tmp/saiity-keyboard-surfaces-green --filter AuxiliarySurfaceContractTests`

结果：通过，3 tests、0 failures。

必要 suite：

`swift test --package-path DictusCore --scratch-path /tmp/saiity-keyboard-surfaces-green`

结果：该 suite 的其它测试通过；完整 suite 仍有 5 个 `VoiceOnlyKeyboardContractTests` 失败。这 5 个失败是后续未提交的 `KeyboardViewController.swift` 跨任务 warning 契约，不属于本轮辅助页修改，不能宣称全量通过。构建仍报告既有 Swift 6 Sendable/NSLock 警告，以及 `polish-harness/README.md` unhandled resource 警告。

## 实现文件

- `DictusKeyboard/KeyboardRootView.swift`：Emoji/符号共享 inset surface；移除旧顶部 accessory row；符号页原生 SwiftUI 三行按键、底部 emoji/mic/page controls；回调路由到 `KeyboardState` 和既有 proxy 路由。
- `DictusKeyboard/Views/EmojiPickerView.swift`：增加 `onBackToVoice`，传递给分类栏。
- `DictusKeyboard/Views/EmojiCategoryBar.swift`：增加固定 44pt mic 返回按钮；分类项去除独立 glass/material 容器。
- `DictusKeyboard/KeyboardLayouts.swift`：明确符号页为三行真实内容布局。
- `DictusCore/Tests/DictusCoreTests/AppleAppFoundationContractTests.swift`：同步 Emoji/category 命中区与无搜索按钮契约。
- `DictusCore/Tests/DictusCoreTests/AuxiliarySurfaceContractTests.swift`：新增 focused contract tests。

## Self-review

- 未使用 UIKit 的旧 `GiellaKeyboardView` 渲染符号页。
- Emoji、symbols、voice 的 surface 结构保持由根视图统一定位；新按钮具有 accessibility label，实际控件命中区至少 44pt。
- symbols 的 `#+=`/`ABC`、emoji、mic、delete、return 均有真实闭包路径；符号 page 2 的 toggle 保持现有 close transition。
- reduced transparency/motion/increased contrast 分支沿用现有 semantic/material policy；按键动画尊重 reduced motion。

## Concerns

- 项目存在 `.xcodeproj`/`.xcworkspace`，但本任务未执行 Xcode/SimSlim runtime verification；本次验证限于 source contract/policy geometry 与 DictusCore suite。
- 既有编译警告未由本任务引入，建议后续单独处理 Swift 6 Sendable/NSLock 警告。

## Commit

本轮修复追加内容：符号页三行网格现在使用 bottom auxiliary lane 以上的独立高度；Emoji、voice、page toggle 控件使用用途和 page-specific accessibility labels；focused policy/contract tests 锁定 lane 不重叠及 routes/labels。

目标 commit：`fix: separate symbol controls from grid`
