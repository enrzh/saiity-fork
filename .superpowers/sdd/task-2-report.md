# Task 2 报告：complete model page and minimal settings

## 变更文件

- `DictusApp/Views/ModelCardView.swift`
  - 恢复模型 `localizedDescription`、引擎友好名称、大小、准确度/速度 gauge 和下载字节信息。
  - 移除 `Text(model.engine.rawValue)`，不再显示 `WK`/`PK` raw internal engine badge。
  - 保留下载、取消、选择、语言详情、失败清理和删除入口。
- `DictusApp/Views/ModelManagerView.swift`
  - 保留原生 `Installed`/`Available` 层级、设备兼容性状态和引擎说明 footer。
  - 保留模型删除确认 alert 及 partial download 删除确认。
- `DictusApp/Views/SettingsView.swift`
  - 本次没有新增 diff；提交前已与 HEAD 一致，当前为 minimal settings 形态。

## TDD RED

命令：

```text
swift test --package-path DictusCore --filter ModelInfoTests
```

关键输出：

```text
Executed 31 tests, with 0 failures
```

随后运行 focused source contract：

```text
if rg -n 'model\\.engine\\.rawValue' DictusApp/Views/ModelCardView.swift; then exit 1; fi
```

结果为 RED：

```text
FAIL: raw internal engine badge is still present
67:                Text(model.engine.rawValue)
```

## TDD GREEN

移除 raw badge 后运行：

```text
if rg -n 'model\\.engine\\.rawValue' DictusApp/Views/ModelCardView.swift; then exit 1; else echo 'PASS: no raw internal engine badge in ModelCardView.swift'; fi
swift test --package-path DictusCore --filter ModelInfoTests
git diff --check
```

关键输出：

```text
PASS: no raw internal engine badge in ModelCardView.swift
Executed 31 tests, with 0 failures
```

App 编译命令：

```text
xcodebuild -project Dictus.xcodeproj -scheme DictusApp -destination 'generic/platform=iOS Simulator' build CODE_SIGNING_ALLOWED=NO
```

关键输出：

```text
** BUILD SUCCEEDED **
```

## 提交

```text
70c89072f4b561d034bb5ad9bfd55ff04aabf116 Complete model page and minimal settings
```

本次 task commit 只包含指定 View 中实际属于本次 task 的两个文件；其它 dirty 文件未暂存、未修改、未重置。

## 未解决问题

- `xcodebuild` 仍报告既有 warning：`AVAudioSession.recordPermission` 在 iOS 17.0 deprecated；不属于本 task，未扩大改动范围。
- 工作区仍存在其它既有 dirty 文件，包括 `Dictus.xcodeproj/project.pbxproj`、keyboard/core 文件、`.superpowers/` 和 `PRODUCT.md`；均未纳入本次提交。
- 未进行 physical iPhone 验证；本次仅完成 focused core tests、source contract 和 generic iOS Simulator app build。

## Task 2 审查修复：兼容旧模型保留在 Installed

### 问题

`ModelManagerView` 从 `ModelInfo.redesignCatalog` 构建 Installed，导致 manager state 中已下载的 deprecated Tiny/Base 没有对应 row；Available 也额外按 redesign catalog ID 过滤，混淆了当前 runtime catalog 与兼容解析 catalog。

### TDD RED

在实现前运行 source contract：

```text
if rg -n 'ModelInfo\\.redesignCatalog\\.filter|catalogIDs|ModelInfo\\.redesignCatalog\\.first' DictusApp/Views/ModelManagerView.swift; then exit 1; fi
```

结果为 RED，命中 Installed、Available 和 prewarming 的 `redesignCatalog` 依赖。

### 修复与 GREEN

- Installed 改为从 `ModelInfo.allIncludingDeprecated` 按 `downloadedModels`/`modelStates[identifier] == .ready` 过滤，因此已安装的 deprecated Tiny/Base 保留在页面。
- Available 直接使用 `ModelInfo.available(on: deviceCapabilities)`，只按实际 manager state 排除已安装项；不再通过 redesign catalog ID 二次裁剪或制造重复。
- prewarming 查找也使用完整 catalog，保证兼容旧模型的活动状态可解析。
- 增加 `testAvailableCatalogHasUniqueDownloadableDeviceCompatibleRows`，覆盖可用 catalog 的唯一标识、下载可见性和设备兼容性契约。

验证命令及结果：

```text
swift test --package-path DictusCore --filter ModelInfoTests
Executed 32 tests, with 0 failures

xcodebuild -project Dictus.xcodeproj -scheme DictusApp -destination 'generic/platform=iOS Simulator' build CODE_SIGNING_ALLOWED=NO
** BUILD SUCCEEDED **

git diff --check
无输出
```

### 范围与顾虑

本次只修改 `ModelManagerView.swift`、`ModelInfoTests.swift` 和本报告；未恢复旧键盘/设置入口，未修改键盘文件。工作区中其他既有 dirty 文件未暂存、未重置。测试与 build 均未替代 physical iPhone 验证。

## Task 2 re-review Important 修复：Installed identifier 去重

### RED

新增 focused regression test：`ModelInfoTests.testModelManagerInstalledRowsDeduplicateIdentifiersAndPreferCurrentMetadata`。

先运行：

```text
swift test --filter ModelInfoTests/testModelManagerInstalledRowsDeduplicateIdentifiersAndPreferCurrentMetadata
```

结果为预期 RED：测试执行 1 项、3 failures；三个断言均因 `ModelManagerView` 尚未包含去重逻辑而失败，未发生编译错误。

### GREEN

在 `ModelManagerView.installedModels` 中反向遍历 `allIncludingDeprecated`，用 `Set` 按 identifier 保留一行，再反转恢复 catalog 顺序。由于 current 条目位于 deprecated 条目之后，重复 identifier 会选择 current metadata；只有 deprecated 条目时仍会保留。

GREEN focused test：

```text
swift test --filter ModelInfoTests/testModelManagerInstalledRowsDeduplicateIdentifiersAndPreferCurrentMetadata
Executed 1 test, with 0 failures (0 unexpected)
```

覆盖测试：

```text
swift test --enable-code-coverage
Executed 1032 tests, with 10 tests skipped and 0 failures (0 unexpected)
Test Suite 'All tests' passed
```

相关 iOS Simulator App build：

```text
xcodebuild -project Dictus.xcodeproj -scheme DictusApp -destination 'generic/platform=iOS Simulator' build CODE_SIGNING_ALLOWED=NO
** BUILD SUCCEEDED **
```

`git diff --check` 无输出。

### 变更文件与提交

- `DictusApp/Views/ModelManagerView.swift`
- `DictusCore/Tests/DictusCoreTests/ModelInfoTests.swift`
- `.superpowers/sdd/task-2-report.md`

提交：`8871aea`（amend 后 SHA 以最终 git 输出为准）。

### 顾虑

- regression test 位于现有 core test target，以 source-contract 方式锁定 app View 的去重策略；没有新增测试 target 或抽象层。
- 测试/build 输出包含既有 warning：未处理的 polish-harness README、Swift 6 Sendable/NSLock warning，以及脚本 build phase 每次运行提示；均未改变且与本修复无关。
- 未恢复旧键盘/设置入口，未修改 keyboard 文件或 ModelInfo catalog；工作区其它 dirty 文件未暂存、未重置。未进行 physical iPhone 验证。
