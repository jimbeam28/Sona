# BUG-07 — AppBar 排序菜单不随 Tab 切换刷新

> 来源：`docs/cr/cr-20260724-0110.md` HOME1
> dev-plan 流程：Bug 修复模式

---

## §0 头部元数据

```yaml
id: BUG-07
name: AppBar 排序菜单不随 Tab 切换刷新
priority: P1
status: draft
created_at: 2026-07-27
last_updated: 2026-07-27
spec_anchored_files:
  - lib/features/home/home_screen.dart
cross_module_impacts: []
parent_feature: Home
manual_qa_required: false
```

---

## §1 用户视角

### 1.0 原始需求

> cr-20260724-0110.md HOME1：AppBar actions 按 _tabController.index 分支渲染，但监听器只做持久化不 setState → 排序菜单冻结在上次 build 的 Tab。

### 1.1 这一功能干什么（一句话）

修复主页切换 Tab 后 AppBar 排序菜单不刷新的缺陷。

### 1.2 用户期望的场景

| ID | 你看到的样子 | 期望行为 |
|----|----|----|
| U1 | 冷启动默认 Tab 0（播放单），切到文件浏览 Tab | 排序图标弹出文件浏览排序项（文件名/日期），不是播放单排序项 |
| U2 | 文件浏览 Tab 切回播放单 Tab | 排序图标弹出播放单排序项 |

---

## §2 已实现的功能骨架

### 2.1 文件与分层

| 层 | 文件 | 行数 | 角色 |
|---|---|---|---|
| UI | `lib/features/home/home_screen.dart` | ~200 | 主页 Tab 导航 + AppBar |

---

## §3 行为规约

### 3.1 修复后行为

- **[BUG-07-S1]** Tab 切换触发 AppBar actions 重建 (`status: new`)
  ```
  Given HomeScreen 有两个 Tab（播放单 / 文件浏览）
  When  用户从 Tab 0 切到 Tab 1
  Then  AppBar actions 重建，展示 Tab 1 对应的排序菜单
  否定断言:
    - 不依赖无关 setState 触发重建（当前 BUG：无任何机制触发重建）
    - Tab 切换不丢失已选排序项（排序状态持久化不受影响）
  ```
  Code evidence: `lib/features/home/home_screen.dart:91-93`（AppBar actions 按 _tabController.index 分支）, `:42-46`（监听器只持久化不 setState）

  **修改指令：**

  **文件：** `lib/features/home/home_screen.dart:42-46`

  **当前代码：**
  ```dart
  _tabController.addListener(() {
    if (!_tabController.indexIsChanging) {
      prefs?.setInt(_tabIndexKey, _tabController.index);
    }
  });
  ```

  **修改为：**
  ```dart
  _tabController.addListener(() {
    if (!_tabController.indexIsChanging) {
      prefs?.setInt(_tabIndexKey, _tabController.index);
      if (mounted) setState(() {});
    }
  });
  ```

  **边界决策：**
  - `indexIsChanging == true`（动画进行中）→ 不 setState，避免动画期间多次重建
  - `indexIsChanging == false`（动画完成 / 直接设置 index）→ setState 触发一次重建
  - `mounted == false`（widget 已销毁但 listener 仍触发）→ 跳过 setState，避免 Flutter 框架异常
  - 排序状态持久化不受影响（`prefs?.setInt` 调用保持不变）

  **测试文件：** `test/features/home/bug_07_tab_sort_test.dart`（避免与旧 BUG-07 测试冲突）

---

## §4 不变量

- **[BUG-07-INV1]** AppBar 排序菜单始终对应当前活跃 Tab
  证据：`home_screen.dart:91-93`（修复目标）

---

## §5 测试规约

### 5.2 测试 ID 派生清单

```
BUG-07-S1           # Tab 切换刷新菜单
BUG-07-INV1         # 菜单对应活跃 Tab
```

### 5.4 测试文件位置

| 测试 ID | 文件路径 |
|---|---|
| BUG-07-S1 | `test/features/home/bug_07_tab_sort_test.dart` |
| BUG-07-INV1 | `test/features/home/bug_07_tab_sort_test.dart` |

---

## §7 跨模块影响

无跨模块影响。修复局限在 home_screen.dart。

---

## §8 平台特性与手动 QA

本功能不涉及平台原生特性，全部可在 `flutter test` 中验证。

---

## §9 dev-status.json 条目对照

见统一更新：`docs/dev/dev-status.json`。

---

## §10 changelog

- 2026-07-27: 创建 BUG-07 spec（基于 cr-20260724-0110.md HOME1）
