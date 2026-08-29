# REF-28 — 两处列表项补业务 ValueKey（P13 纪律）

## §0 头部元数据

```yaml
id: REF-28
name: 两处列表项补业务 ValueKey（下载行 + 搜索命中行）
priority: P3
status: active
created_at: 2026-08-29
last_updated: 2026-08-29
spec_anchored_files:
  - lib/features/downloads/downloads_screen.dart
  - lib/features/browser/browser_screen.dart
cross_module_impacts: [DL, BRW]   # 下载管理页(DL-01-S9) + 搜索命中列表(SRCH-01)
manual_qa_required: false         # 纯 widget 键添加，全可 widget 测试验证
```

---

## §1 用户视角

### 1.0 原始需求（用户原话逐字记录）

来源：`docs/cr/cr-20260826-0027.md` D2（cr 复核分流，用户裁决"修"→ 转 REF 需求流程，无复现测试要求）：

> ### D2【Info】两处新列表项未带业务 ValueKey（P13 纪律偏离）
> `lib/features/downloads/downloads_screen.dart:127`（`_DownloadRow`）与 `lib/features/browser/browser_screen.dart:460-478`（搜索结果 ListTile）未加 `ValueKey(业务 ID)`，偏离 cr-dimensions §2.4/P13「列表项一律 ValueKey(业务 ID)」纪律。现状两列表均为无状态行且追加序稳定，无可复现的用户可见缺陷；若未来行组件引入动画/Dismissible/内部状态，位置匹配将错位。属纪律一致性取舍，交用户裁决是否补键。

用户裁决：**修**——两处均补 `ValueKey(业务 ID)`。

### 1.1 这一功能干什么（一句话）

给下载管理页的每条下载记录、搜索结果里的每个命中，都加上以业务 ID 为值的 `ValueKey`，让 Flutter 按业务身份而非列表位置匹配行元素。

### 1.2 用户期望的场景

| ID | 你看到的样子 | 期望行为 |
|----|----|----|
| U1 | 打开离线下载管理页 | 每条记录行带业务键（修复前无键，位置匹配）；列表滚动、刷新、删除后行状态跟随业务条目 |
| U2 | 搜索结果列表 | 每个命中行带业务键；搜索词变化、命中集合变化时行元素按文件身份稳定匹配 |

---

## §2 已实现的功能骨架（代码锚点）

### 2.1 文件与分层

| 层 | 文件 | 关键位置 | 角色 |
|---|---|---|---|
| UI | lib/features/downloads/downloads_screen.dart | :127 `return _DownloadRow(` | 下载记录行（DL-01-S9 管理页） |
| UI | lib/features/browser/browser_screen.dart | :460-478 搜索命中 `ListTile` | SRCH-01 搜索结果行 |

### 2.2 关键 Provider 表

本功能不涉 provider，跳过。

### 2.3 状态机图

无状态机，跳过。

---

## §3 行为规约（Given-When-Then）

- **[REF-28-S1] 下载记录行补 ValueKey（status: new）**

  ```
  Given downloads_screen.dart:127 构建 _DownloadRow(record: record, ...)
  When 渲染该行
  Then 在 _DownloadRow 构造处补 ValueKey：
       `_DownloadRow(key: ValueKey(record.id), record: record, ...)`
       ——业务 ID 取 DownloadRecord.id（downloads 表主键，唯一）
  否定断言:
    - 不改变行内容/回调接线（onCancel/onRetry/onDelete 原样）
    - record.id 为 null 的防御分支保持（ValueKey(null) 不引入崩溃——正常 DB 行恒有 id）
  ```

  Code evidence: downloads_screen.dart:126-134

- **[REF-28-S2] 搜索命中行补 ValueKey（status: new）**

  ```
  Given browser_screen.dart:460 搜索命中 ListTile（hit.file / hit.parentDirPath）
  When 渲染该行
  Then ListTile 补 key：
       `key: ValueKey(hit.file.path)`（命中文件相对连接根的路径，同连接内唯一）
  否定断言:
    - 不改变行点击行为（onTap → _playSearchHit 原样）
    - 不改变 trailing 下一曲按钮的既有门禁（playNextEnabled 置灰逻辑原样）
    - 多选态行尾按钮形态不受影响（MSEL-01 不涉及搜索命中行）
  ```

  Code evidence: browser_screen.dart:460-478

---

## §4 不变量

- **[REF-28-INV1]** 列表项键值恒为业务 ID（下载记录→record.id；搜索命中→file.path），不以列表下标为键。
  证据：S1/S2 明确键值来源。

---

## §5 测试规约

### 5.1 现有测试清单

| 测试文件 | 覆盖 | 备注 |
|---|---|---|
| test/features/downloads/dl_01_download_test.dart | DL-01-S9 管理页行渲染 | 补一行 ValueKey 断言 |
| test/features/browser/srch_01_folder_search_test.dart | SRCH-01 搜索命中列表 | 补一行 ValueKey 断言 |

### 5.2 测试 ID 派生清单

```
REF-28-S1 ~ S2
REF-28-INV1
```

### 5.3 测试覆盖盲点

| 未覆盖 ID | 现状 | 应补偿方式 |
|---|---|---|
| S1 ValueKey 存在性 | dl_01 S9 组未断言键 | 在既有 S9 widget 测试中对首个行 find.byKey(ValueKey(预期 id)) |
| S2 ValueKey 存在性 | srch_01 未断言键 | 在既有命中列表 widget 测试中对命中行 find.byKey(ValueKey(文件 path)) |

### 5.4 门禁测试文件位置

```
test/features/downloads/ref_28_value_key_test.dart
test/features/browser/ref_28_value_key_test.dart
```
（命名核查 2026-08-29：grep test/ 无 ref_28 同名文件。）

---

## §6 算法样例

无纯函数，跳过。

---

## §7 跨模块影响

| 其它 feature | 影响点 | 影响条件 | 需要补的回归断言 |
|---|---|---|---|
| DL-01 | downloads_screen 下载行加 key | 管理页渲染 | dl_01 S9 组全绿 + 新增 byKey 断言 |
| SRCH-01 | 搜索命中行加 key | 搜索命中渲染 | srch_01 族全绿 + 新增 byKey 断言 |

---

## §8 平台特性与手动 QA

本功能不涉及平台原生特性，全部可在 `flutter test` 中验证。manual_qa_required=false。

---

## §9 dev-status.json 条目对照

```json
"REF-28": {
  "spec_file": "docs/features/REF-28.md",
  "spec_anchored_files": [
    "lib/features/downloads/downloads_screen.dart",
    "lib/features/browser/browser_screen.dart"
  ],
  "scenarios": ["REF-28-S1","REF-28-S2"],
  "invariants": ["REF-28-INV1"],
  "algorithms": [],
  "test_files": ["test/features/downloads/ref_28_value_key_test.dart","test/features/browser/ref_28_value_key_test.dart"],
  "test_coverage_gaps": [],
  "cross_module_impacts": ["DL", "BRW"],
  "manual_qa_required": false,
  "manual_qa_file": null,
  "dependencies": [],
  "impl_status": "pending",
  "test_status": "pending",
  "check_status": "pending"
}
```