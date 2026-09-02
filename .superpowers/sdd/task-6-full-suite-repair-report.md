# Task 6: Full DictusCore Suite Repair

Date: 2026-09-02
Repository: `/Users/enrico/Documents/GitHub/sAiity-dictus`
Branch: `saiity-fork`

## Change

Updated only the stale assertion in
`DictusCore/Tests/DictusCoreTests/AppleAppFoundationContractTests.swift`.
The settings contract now positively checks the shipped native keyboard-order
Picker binding:

```swift
XCTAssertTrue(settings.contains("Picker(selection: keyboardAccessoryOrderBinding, label: Text(\"Control order\"))"))
```

The six native sections, shipped destinations, and obsolete-setting checks were
left unchanged. No production code or keyboard UI was modified.

Changed files in this task:

- `DictusCore/Tests/DictusCoreTests/AppleAppFoundationContractTests.swift`
- `.superpowers/sdd/task-6-full-suite-repair-report.md`

## Verification

### RED baseline

Command:

```text
swift test --package-path DictusCore --scratch-path /tmp/saiity-dictus-full-repair --filter AppleAppFoundationContractTests
```

Result: exit code 1. The selected suite executed 28 tests with 1 failure. The
only failure was
`testSettingsTaskFourUsesGroupedNativeSectionsAndShippedDestinations` at line
243, where the obsolete `XCTAssertFalse(settings.contains("Picker("))`
assertion rejected the approved keyboard-order Picker.

### Focused suite after the change

Command:

```text
swift test --package-path DictusCore --scratch-path /tmp/saiity-dictus-full-repair --filter AppleAppFoundationContractTests
```

Result: exit code 0. `AppleAppFoundationContractTests` executed 28 tests with
0 failures.

### Full suite

Command:

```text
swift test --package-path DictusCore --scratch-path /tmp/saiity-dictus-full-repair-full
```

Result: exit code 0. `DictusCoreTests.xctest` and `All tests` each reported
1274 executed, 10 skipped, and 0 failures.

### Diff check

Command:

```text
git diff --check
```

Result: exit code 0 with no output.

## Concerns

- The test build reports existing Swift 6 compatibility warnings for the
  `Sendable`/`SpeechEngine` relationship, `NSLock` use from an async test
  context, and an unused local in `VoiceOnlyKeyboardContractTests`.
- The full run logs a `FrequencyDictionary` JSON decoding diagnostic and
  performance measurements after the test suites pass. This did not produce a
  test failure and is outside the changed test contract, but remains a separate
  diagnostic worth tracking.
- Verification used only the requested host-side Swift test commands and
  `git diff --check`; no physical iPhone, DeviceHub, iPhone Mirroring,
  TestFlight, or release tooling was used.
