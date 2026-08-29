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
