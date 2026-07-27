# TEST-11 — SET3：设置测试缺口（LogViewer 行为测试）

> 来源：`docs/cr/cr-20260724-0110.md` SET3 (line 499-502)
> dev-plan 流程：TEST-GAP 补测模式

---

## §0 头部元数据

```yaml
id: TEST-11
name: 设置测试缺口（SET3 — LogViewer 行为测试）
priority: P1
status: draft
created_at: 2026-07-27
last_updated: 2026-07-27
spec_anchored_files:
  - lib/features/settings/log_viewer_screen.dart
  - test/features/settings/log_viewer_test.dart
cross_module_impacts: [TST]
parent_feature: Settings
manual_qa_required: false
```

---

## §1 用户视角

### 1.0 原始需求

> cr-20260724-0110.md SET3：`log_viewer_test.dart:173-195` 仅断言 tooltip 存在（过滤输入框、复制全部、清空按钮的 tooltip 文本）。若反转 `log_viewer_screen.dart:55` 的 `contains` 为 `!contains`（过滤逻辑反转），或让 `_clear` 不调 `clear()`（清空变 no-op），测试仍然通过。Filter/copy-all 是核心调试动作；copy 涉及 clipboard 副作用。

### 1.1 这一功能干什么（一句话）

为 LogViewerScreen 的过滤、复制全部、清空三个核心交互补充行为性 widget 测试。

### 1.2 用户期望的场景

| ID | 你看到的样子 | 期望行为 |
|----|----|----|
| U1 | 在过滤框输入关键字 | 列表只显示匹配的日志条目 |
| U2 | 按"复制全部"按钮 | 出现 SnackBar 提示已复制行数，剪贴板内容与可见日志一致 |
| U3 | 按"清空"按钮 | 日志列表变为空，显示"暂无日志"占位文本 |

---

## §2 已实现的功能骨架

### 2.1 文件与分层

| 层 | 文件 | 行数 | 角色 |
|---|---|---|---|
| UI | `lib/features/settings/log_viewer_screen.dart` | 156 | LogViewerScreen widget |
| Service | `lib/core/services/log_buffer.dart` | - | LogBuffer 单例（环形缓冲区） |
| Test (现有) | `test/features/settings/log_viewer_test.dart` | 233 | :173-195 仅 tooltip 断言 |

### 2.2 关键代码段

| 区域 | 行号 | 说明 |
|---|---|---|
| _visible 过滤 | `log_viewer_screen.dart:49-56` | `_filter` + `contains(needle)` 过滤 |
| _copyAll | `log_viewer_screen.dart:58-64` | Clipboard.setData + SnackBar |
| _clear | `log_viewer_screen.dart:67-69` | LogBuffer.instance.clear() |
| 过滤 TextField | `log_viewer_screen.dart:103-111` | `onChanged: (v) => setState(() => _filter = v)` |
| 空状态 | `log_viewer_screen.dart:128-131` | `visible.isEmpty → Center('暂无日志')` |
| 现有 tooltip 测试 | `log_viewer_test.dart:173-195` | 仅 `find.byTooltip(...)` 断言 |

---

## §3 行为规约

### 3.1 过滤行为

- **[TEST-11-S1]** 过滤关键字缩小日志列表 (`status: new`)
  ```
  Given LogBuffer 有 3 条日志：'[Player] started'、'[Browser] loaded'、'[Player] stopped'
        LogViewerScreen 已渲染
  When  在过滤输入框输入 'Player'
  Then  ListView 显示 2 条（'[Player] started' 和 '[Player] stopped'）
  And   不显示 '[Browser] loaded'
  And   计数文本显示 '共 2 条'
  否定断言:
    - 不过滤时不隐藏任何条目（过滤为空时显示全部）
    - 不在过滤时改变 LogBuffer 内容（纯视图过滤，不影响数据源）
    - 不过滤匹配不区分大小写（_filter.toLowerCase().contains(needle.toLowerCase())）
  ```
  Code evidence:
  - `log_viewer_screen.dart:49-56`（`_visible` getter + `contains`）
  - `log_viewer_screen.dart:110`（`onChanged` 更新 `_filter`）
  - `log_viewer_test.dart:173-195`（当前仅断言 tooltip 存在，不过滤行为）

  **测试文件位置：`test/features/settings/log_viewer_test.dart`**

### 3.2 复制全部行为

- **[TEST-11-S2]** 复制全部 → SnackBar + 剪贴板内容匹配 (`status: new`)
  ```
  Given LogBuffer 有 2 条日志
        LogViewerScreen 已渲染
  When  按"复制全部"按钮（tooltip: '复制全部'）
  Then  出现 SnackBar 显示 '已复制 2 行'
  And   剪贴板内容包含 2 条日志的 formatted 文本（以 '\n' 分隔）
  否定断言:
    - 不在日志为空时可按"复制全部"（按钮 disabled：`visible.isEmpty ? null : _copyAll`，:90）
    - 不在复制后清除 LogBuffer（只读不删）
    - 不在复制后改变过滤状态
  ```
  Code evidence:
  - `log_viewer_screen.dart:58-64`（`_copyAll`：Clipboard.setData + SnackBar）
  - `log_viewer_screen.dart:90`（`visible.isEmpty ? null : _copyAll`）
  - `log_viewer_test.dart:191`（仅断言 `find.byTooltip('复制全部')` 存在）

  **测试文件位置：`test/features/settings/log_viewer_test.dart`**

  **修改指令 — 测试需 mock Clipboard**

  测试需使用 `TestDefaultBinaryMessengerBinding` 拦截 `SystemChannels.platform` 以验证 Clipboard.setData 的内容。具体做法：
  - `SystemChannels.platform.setMockMethodCallHandler` 拦截 `Clipboard.setData`
  - 捕获传入的 `ClipboardData.text` 参数
  - 断言内容与 LogBuffer entries 的 formatted 文本一致

### 3.3 清空行为

- **[TEST-11-S3]** 清空 → 空状态 (`status: new`)
  ```
  Given LogBuffer 有 3 条日志
        LogViewerScreen 已渲染，ListView 显示 3 条
  When  按"清空"按钮（tooltip: '清空'）
  Then  LogBuffer 为空
  And   UI 显示 '暂无日志' 占位文本
  And   '复制全部' 和 '清空' 按钮变为 disabled（`visible.isEmpty ? null : ...`）
  否定断言:
    - 不在清空后仍显示日志条目（LogBuffer.clear() 必须实际执行）
    - 不在清空时保留过滤状态（_filter 应变为空或保持但不影响空结果）
    - 不在 LogBuffer 为空时清空按钮可点击（`visible.isEmpty ? null` disabled 逻辑）
  ```
  Code evidence:
  - `log_viewer_screen.dart:67-69`（`_clear` → `LogBuffer.instance.clear()`）
  - `log_viewer_screen.dart:95`（`visible.isEmpty ? null : _clear`）
  - `log_viewer_screen.dart:128-131`（空状态占位：'暂无日志'）
  - `log_viewer_test.dart:194`（仅断言 `find.byTooltip('清空')` 存在）

  **测试文件位置：`test/features/settings/log_viewer_test.dart`**

---

## §4 不变量

- **[TEST-11-INV1]** 过滤是纯视图操作，不修改 LogBuffer 数据源
  证据：`log_viewer_screen.dart:49-56`（`_visible` getter 只做 filter，不调 LogBuffer 方法）

- **[TEST-11-INV2]** 日志为空时复制全部和清空按钮 disabled
  证据：`log_viewer_screen.dart:90,95`（`visible.isEmpty ? null : ...`）

---

## §5 测试规约

### 5.1 现有测试清单

| 测试文件 | 覆盖 | 备注 |
|---|---|---|
| `log_viewer_test.dart:173-195` | tooltip 存在性 | 仅 UI 结构断言，无行为验证 |

### 5.2 测试 ID 派生清单

```
TEST-11-S1          # 过滤缩小列表
TEST-11-S2          # 复制全部 → SnackBar + clipboard
TEST-11-S3          # 清空 → 空状态
TEST-11-INV1 INV2   # 过滤纯视图 + 空时 disabled
```

### 5.3 测试覆盖盲点

| 未覆盖 ID | 现状 | 应补偿方式 |
|---|---|---|
| TEST-11-S1 | 仅断言 TextField 存在（:180-185） | 输入关键字 → 断言列表条数减少 |
| TEST-11-S2 | 仅断言按钮存在（:191） | 点击 → 断言 SnackBar + mock Clipboard 内容 |
| TEST-11-S3 | 仅断言按钮存在（:194） | 点击 → 断言 LogBuffer 空 + '暂无日志' 显示 |

### 5.4 测试文件位置

| 测试 ID | 文件路径 |
|---|---|
| TEST-11-S1 | `test/features/settings/log_viewer_test.dart`（追加到现有文件） |
| TEST-11-S2 | `test/features/settings/log_viewer_test.dart`（追加到现有文件） |
| TEST-11-S3 | `test/features/settings/log_viewer_test.dart`（追加到现有文件） |

---

## §6 算法样例

不适用——本 spec 为补测，无新算法。

---

## §7 跨模块影响

| 其它 feature | 影响点 | 需要补的回归断言 |
|---|---|---|
| 无 | LogViewer 为独立页面，不影响其他 feature | 无 |

---

## §8 平台特性与手动 QA

本功能不涉及平台原生特性，全部可在 `flutter test` 中验证。

Clipboard 在 `flutter test` 中可通过 `SystemChannels.platform.setMockMethodCallHandler` mock。

---

## §9 dev-status.json 条目对照

```json
"TEST-11": {
  "spec_file": "docs/features/TEST-11.md",
  "spec_anchored_files": [
    "lib/features/settings/log_viewer_screen.dart",
    "test/features/settings/log_viewer_test.dart"
  ],
  "scenarios": ["TEST-11-S1", "TEST-11-S2", "TEST-11-S3"],
  "invariants": ["TEST-11-INV1", "TEST-11-INV2"],
  "algorithms": [],
  "test_files": ["test/features/settings/log_viewer_test.dart"],
  "test_coverage_gaps": [],
  "cross_module_impacts": ["TST"],
  "manual_qa_required": false,
  "manual_qa_file": null,
  "user_acceptance_text": "见 §1.2",
  "impl_status": "pending",
  "test_status": "pending",
  "check_status": "pending",
  "check_round": 0,
  "last_check_round_results": "",
  "last_checked_at": "",
  "dependencies": [],
  "retry_count": 0,
  "last_error": "",
  "last_updated": "2026-07-27"
}
```

---

## §10 changelog

- 2026-07-27: 创建 TEST-11 spec（基于 cr-20260724-0110.md SET3）
