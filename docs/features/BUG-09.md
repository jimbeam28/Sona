# BUG-09 — 添加曲目弹窗跨目录全选判定错误

> 来源：`docs/cr/cr-20260724-0110.md` LIST2
> dev-plan 流程：Bug 修复模式

---

## §0 头部元数据

```yaml
id: BUG-09
name: 添加曲目弹窗跨目录全选判定错误
priority: P1
status: draft
created_at: 2026-07-27
last_updated: 2026-07-27
spec_anchored_files:
  - lib/features/playlist/widgets/add_tracks_browser.dart
cross_module_impacts: []
parent_feature: Playlist
manual_qa_required: false
```

---

## §1 用户视角

### 1.0 原始需求

> cr-20260724-0110.md LIST2：_selectedPaths 跨目录累积，但全选判定用 _selectedPaths.length == allPaths.length（allPaths 仅当前目录），导致跨目录选择后"全选/取消全选"判定错误。

### 1.1 这一功能干什么（一句话）

修复添加曲目弹窗中跨目录选择后全选/取消全选按钮行为错误。

### 1.2 用户期望的场景

| ID | 你看到的样子 | 期望行为 |
|----|----|----|
| U1 | 目录 A 勾 1 首 → 进目录 B（1 首） | header 显示"全选"（B 中 0 首被选），点击选中 B 的全部，A 的已选保留 |
| U2 | 目录 A 全选 3 首 → 进同为 3 首的 B | header 显示"全选"（B 中 0 首被选），点击选中 B 的全部 |
| U3 | 当前目录全部已选 → 再点全选 | 变为"取消全选"，仅取消当前目录的选中，他目录已选保留 |

---

## §2 已实现的功能骨架

### 2.1 文件与分层

| 层 | 文件 | 行数 | 角色 |
|---|---|---|---|
| UI | `lib/features/playlist/widgets/add_tracks_browser.dart` | ~230 | 添加曲目文件浏览器 |

---

## §3 行为规约

### 3.1 修复后行为

- **[BUG-09-S1]** 全选判定改为当前目录集合语义 (`status: new`)
  ```
  Given _selectedPaths 跨目录累积了 {A1, A2}
    And 当前目录 B 有音频 {B1}
  When  渲染全选按钮
  Then  判定条件：当前目录所有音频 path 都在 _selectedPaths 中 → "取消全选"
        否则 → "全选"
  否定断言:
    - 不用 _selectedPaths.length == allPaths.length（当前 BUG：跨目录计数不匹配）
    - "取消全选"不清空他目录已选项（仅移除当前目录 path）
  ```
  Code evidence: `lib/features/playlist/widgets/add_tracks_browser.dart:76-83`（判定逻辑）, `:208-214`（标签逻辑）, `:216-220`（_allAudioPaths 仅当前目录）

  #### 修改指令

  **修改点 1：全选判定逻辑（onPressed 回调）**

  文件：`lib/features/playlist/widgets/add_tracks_browser.dart:76-82`

  当前代码：
  ```dart
  final allPaths = _allAudioPaths(contentsAsync);
  if (_selectedPaths.length == allPaths.length &&
      allPaths.isNotEmpty) {
    setState(() => _selectedPaths.clear());
  } else {
    setState(() => _selectedPaths.addAll(allPaths));
  }
  ```

  改为：
  ```dart
  final allPaths = _allAudioPaths(contentsAsync);
  final allSelected =
      allPaths.isNotEmpty && allPaths.every(_selectedPaths.contains);
  if (allSelected) {
    setState(() => _selectedPaths.removeAll(allPaths));
  } else {
    setState(() => _selectedPaths.addAll(allPaths));
  }
  ```

  变更说明：
  - 判定条件从 `_selectedPaths.length == allPaths.length` 改为 `allPaths.every(_selectedPaths.contains)`——集合包含语义，不受跨目录累积计数影响。
  - "取消全选"操作从 `_selectedPaths.clear()` 改为 `_selectedPaths.removeAll(allPaths)`——仅移除当前目录的 path，保留他目录已选项。

  **修改点 2：标签函数**

  文件：`lib/features/playlist/widgets/add_tracks_browser.dart:208-214`

  当前代码：
  ```dart
  String _selectAllLabel(AsyncValue<List<NasFile>> contentsAsync) {
    final allPaths = _allAudioPaths(contentsAsync);
    if (_selectedPaths.length == allPaths.length && allPaths.isNotEmpty) {
      return '取消全选';
    }
    return '全选';
  }
  ```

  改为：
  ```dart
  String _selectAllLabel(AsyncValue<List<NasFile>> contentsAsync) {
    final allPaths = _allAudioPaths(contentsAsync);
    if (allPaths.isNotEmpty && allPaths.every(_selectedPaths.contains)) {
      return '取消全选';
    }
    return '全选';
  }
  ```

  变更说明：与修改点 1 使用相同的集合包含判定，保证按钮标签与行为一致。

  **边界裁决：**
  - 当前目录无音频（`allPaths.isEmpty`）→ `allSelected = false`，标签显示"全选"，点击无效果（addAll 空集）。
  - 跨目录已选 {A1, A2}，当前目录 B 有 {B1}，B1 未选 → `allSelected = false`，标签"全选"。
  - 当前目录 B 全部已选 {B1}，另有 A1 → `allSelected = true`，标签"取消全选"，点击仅移除 B1，A1 保留。
  - 当前目录 B 全部已选且无他目录选择 → 点击后 `_selectedPaths` 为空。

  **测试文件位置：** `test/features/playlist/bug_09_test.dart`

---

## §4 不变量

- **[BUG-09-INV1]** 全选/取消全选操作仅影响当前目录的音频
  证据：`add_tracks_browser.dart:76-83`（修复目标）

---

## §5 测试规约

### 5.2 测试 ID 派生清单

```
BUG-09-S1           # 集合语义判定
BUG-09-INV1         # 仅影响当前目录
```

### 5.4 测试文件位置

| 测试 ID | 文件路径 |
|---|---|
| BUG-09-S1 | `test/features/playlist/bug_09_test.dart` |
| BUG-09-INV1 | `test/features/playlist/bug_09_test.dart` |

---

## §7 跨模块影响

无跨模块影响。修复局限在 add_tracks_browser.dart。

---

## §8 平台特性与手动 QA

本功能不涉及平台原生特性，全部可在 `flutter test` 中验证。

---

## §9 dev-status.json 条目对照

见统一更新：`docs/dev/dev-status.json`。

---

## §10 changelog

- 2026-07-27: 创建 BUG-09 spec（基于 cr-20260724-0110.md LIST2）
