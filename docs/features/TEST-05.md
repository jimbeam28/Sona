# TEST-05 — 进度测试缺口（PRG7+PRG8+PRG9）

> 来源：`docs/cr/cr-20260724-0110.md` PRG7 (line 451-454) + PRG8 (line 456-459) + PRG9 (line 461-464)
> dev-plan 流程：TEST-GAP 补测模式

---

## §0 头部元数据

```yaml
id: TEST-05
name: 进度测试缺口（PRG7+PRG8+PRG9）
priority: P1
status: draft
created_at: 2026-07-27
last_updated: 2026-07-27
spec_anchored_files:
  - lib/features/progress/progress_dialog.dart
  - lib/features/progress/progress_provider.dart
  - lib/features/browser/browser_screen.dart
cross_module_impacts: [PRG, BRW]
parent_feature: Progress
manual_qa_required: false
```

---

## §1 用户视角

### 1.0 原始需求

> cr-20260724-0110.md PRG7：`prg_test.dart:618-643` — `expect(true, isTrue)` 占位符。"无进度→无弹窗→直接播放"决策零行为锚定。
> cr-20260724-0110.md PRG8：`prg_test.dart:863-898` — 测试在内部重建 menuItems 逻辑后断言自己的副本。生产代码长按菜单分支变更后测试仍绿。
> cr-20260724-0110.md PRG9：PRG-T17/T19/T20/T22/FIX-T01/T02 只检查 dialogResult 和文本。用错误实现替换 PRG1 的 double-pop → 测试仍绿。缺失"下层路由栈不受影响"否定断言。

### 1.1 这一功能干什么（一句话）

补齐进度模块三类测试缺口：无进度时直接播放行为锚定、长按菜单真实 UI 验证、多层路由栈下弹窗关闭不影响下层页面。

### 1.2 用户期望的场景

| ID | 你看到的样子 | 期望行为 |
|----|----|----|
| U1 | 点击无进度的文件 | 直接播放，不弹恢复对话框 |
| U2 | 长按有进度的文件 | 菜单包含"清除播放进度" |
| U3 | 长按无进度的文件 | 菜单不包含"清除播放进度" |
| U4 | 在两层路由栈中关闭进度对话框 | 下层页面仍在、对话框消失、不弹出第二层路由 |

---

## §2 已实现的功能骨架

### 2.1 文件与分层

| 层 | 文件 | 行数 | 角色 |
|---|---|---|---|
| UI | `lib/features/progress/progress_dialog.dart` | 123 | `showProgressResumeDialog` + `_ProgressResumeDialog` |
| UI | `lib/features/browser/browser_screen.dart` | 376 | 文件点击/长按处理、菜单构建 |
| Provider | `lib/features/progress/progress_provider.dart` | ~200 | progressResumeProvider |
| 测试 | `test/features/progress/prg_test.dart` | 1781 | PRG 系列测试 |

### 2.2 关键代码段

| 区域 | 行号 | 说明 |
|---|---|---|
| 占位符测试 | `prg_test.dart:627` | `expect(true, isTrue)` |
| 菜单逻辑复制 | `prg_test.dart:858-866` | 测试重建 menuItems 列表断言 |
| 菜单逻辑复制 | `prg_test.dart:874-882` | 同上，无进度分支 |
| 弹窗 showDialog | `progress_dialog.dart:34` | `showDialog<bool>` |
| 弹窗 pop | `progress_dialog.dart:60+` | Navigator.pop + dismiss |

---

## §3 行为规约

### 3.1 补测行为

- **[TEST-05-S1]** 无进度文件点击 → 直接播放无弹窗 (`status: new`)
  ```
  Given 文件 /music/new.mp3 无播放进度记录
  When  用户点击该文件
  Then  直接触发播放（IAudioPlayer.load + play）
  否定断言:
    - 不弹出 showProgressResumeDialog（无进度时无对话框）
    - 不查询 progressDao（无进度记录不需要 DB 查询弹窗决策）
    - 不修改播放队列中其他曲目的状态
  ```
  Code evidence: `lib/features/browser/browser_screen.dart`（onFileTap 路径）; `test/features/progress/prg_test.dart:627`（当前占位符）

- **[TEST-05-S2]** 有进度文件长按 → 菜单包含"清除播放进度" (`status: new`)
  ```
  Given 文件 /music/half.mp3 有播放进度记录
  When  用户长按该文件触发上下文菜单
  Then  菜单项包含"清除播放进度"
  And   菜单项包含"添加到队列"
  And   菜单项包含"查看文件信息"
  否定断言:
    - 不测试内部重建的 menuItems 列表（当前 PRG8 问题：测试重建逻辑而非真实 UI）
    - 不遗漏生产代码新增的菜单项（测试必须断言真实 widget 的菜单项）
  ```
  Code evidence: `test/features/progress/prg_test.dart:858-866`（当前测试重建逻辑）

- **[TEST-05-S3]** 无进度文件长按 → 菜单不包含"清除播放进度" (`status: new`)
  ```
  Given 文件 /music/new.mp3 无播放进度记录
  When  用户长按该文件触发上下文菜单
  Then  菜单项不包含"清除播放进度"
  And   菜单项仅包含"添加到队列"和"查看文件信息"
  否定断言:
    - 不在无进度时显示"清除播放进度"选项
    - 不测试内部重建的 menuItems 列表（必须断言真实 widget）
  ```
  Code evidence: `test/features/progress/prg_test.dart:874-882`（当前测试重建逻辑）

- **[TEST-05-S4]** 两层路由栈关闭进度对话框 → 下层页面完整 (`status: new`)
  ```
  Given Navigator 栈为 [BrowserPage, ProgressResumeDialog]（两层路由）
  When  用户关闭进度对话框（按钮点击或自动超时）
  Then  栈变为 [BrowserPage]（仅一层）
  And   BrowserPage 仍在栈中（未被 pop）
  And   对话框 widget 已移除
  否定断言:
    - 不弹出下层路由（当前 PRG9 问题：缺失"下层路由栈不受影响"断言）
    - 不在关闭对话框时多 pop 一层（double-pop 问题）
    - 不抛出 Navigator 操作异常
  ```
  Code evidence: `lib/features/progress/progress_dialog.dart:34-42`（showDialog + then dismiss）; PRG-T17/T19/T20/T22/FIX-T01/T02（仅检查 dialogResult 和文本）

---

## §4 不变量

- **[TEST-05-INV1]** 无进度文件点击路径不经过进度对话框
  证据：`browser_screen.dart` 中 onFileTap 仅在 progressForFile 非 null 时调用 `showProgressResumeDialog`

- **[TEST-05-INV2]** 长按菜单项由生产代码真实构建（非测试内部重建）
  证据：测试须断言真实 widget 的 PopupMenuItem / menu items

---

## §5 测试规约

### 5.1 现有测试清单

| 测试文件 | 覆盖 | 备注 |
|---|---|---|
| `test/features/progress/prg_test.dart:618-643` | PRG-T18 占位符 | `expect(true, isTrue)` — 零行为验证 |
| `test/features/progress/prg_test.dart:858-898` | PRG-T24/T25 | 内部重建 menuItems 逻辑 — 不与真实 UI 绑定 |
| `test/features/progress/prg_test.dart` PRG-T17/T19/T20/T22/FIX-T01/T02 | 弹窗结果 | 仅检查 dialogResult 和文本 — 缺失路由栈断言 |

### 5.2 测试 ID 派生清单

```
TEST-05-S1          # 无进度文件直接播放
TEST-05-S2          # 有进度文件长按菜单
TEST-05-S3          # 无进度文件长按菜单
TEST-05-S4          # 两层路由栈关闭对话框
TEST-05-INV1        # 无进度不弹对话框
TEST-05-INV2        # 菜单项由真实 UI 构建
```

### 5.3 测试覆盖盲点

| 未覆盖 ID | 现状 | 应补偿方式 |
|---|---|---|
| TEST-05-S1 | `prg_test.dart:627` 占位符 | Widget test：空 DB → 点击文件 → 断言直接播放、无弹窗 |
| TEST-05-S2 | `prg_test.dart:858-866` 内部重建 | Widget test：长按有进度文件 → 断言真实 menu items |
| TEST-05-S3 | `prg_test.dart:874-882` 内部重建 | Widget test：长按无进度文件 → 断言真实 menu items 不含清除选项 |
| TEST-05-S4 | PRG-T17/T19 等仅检查 dialogResult | Host test with two-layer routes → 关闭 dialog → 断言下层页面仍在 + dialog 消失 |

### 5.4 测试文件位置

| 测试 ID | 文件路径 |
|---|---|
| TEST-05-S1 | `test/features/progress/prg_test.dart`（替换占位符） |
| TEST-05-S2 | `test/features/progress/prg_test.dart`（替换内部重建） |
| TEST-05-S3 | `test/features/progress/prg_test.dart`（替换内部重建） |
| TEST-05-S4 | `test/features/progress/prg_test.dart`（新增路由栈测试） |

---

## §6 算法样例

不适用——本 spec 为补测，无新算法。

---

## §7 跨模块影响

| 其它 feature | 影响点 | 需要补的回归断言 |
|---|---|---|
| BRW | `browser_screen.dart` onFileTap | 无进度直接播放路径未被补测破坏 |
| BRW | `browser_screen.dart` onLongPress | 长按菜单真实构建逻辑未被破坏 |

---

## §8 平台特性与手动 QA

本功能不涉及平台原生特性，全部可在 `flutter test` 中验证。

---

## §9 dev-status.json 条目对照

见统一更新：`docs/dev/dev-status.json`。

---

## §10 changelog

- 2026-07-27: 创建 TEST-05 spec（基于 cr-20260724-0110.md PRG7 + PRG8 + PRG9）
