# BUG-13 — "从头播放"不删进度记录

> 来源：`docs/cr/cr-20260724-0110.md` PRG3
> dev-plan 流程：Bug 修复模式

---

## §0 头部元数据

```yaml
id: BUG-13
name: "从头播放"不删进度记录
priority: P1
status: draft
created_at: 2026-07-27
last_updated: 2026-07-27
spec_anchored_files:
  - lib/features/progress/progress_dialog.dart
  - lib/features/browser/browser_screen.dart
  - lib/features/playlist/playlist_detail_screen.dart
cross_module_impacts: []
parent_feature: Progress
manual_qa_required: false
```

---

## §1 用户视角

### 1.0 原始需求

> cr-20260724-0110.md PRG3：progress_dialog.dart 注释声明"从头播放 — delete the progress record"，但两调用方只消费返回值不删记录。选"从头播放"后短期退出再进仍弹旧进度对话框。

### 1.1 这一功能干什么（一句话）

修复"从头播放"按钮不删除进度记录导致对话框反复弹出的缺陷。

### 1.2 用户期望的场景

| ID | 你看到的样子 | 期望行为 |
|----|----|----|
| U1 | 文件有 30s 进度 → 选"从头播放" → 播 3 秒退出 → 再点 | 不弹对话框，从头播放（进度已清除） |

---

## §2 已实现的功能骨架

### 2.1 文件与分层

| 层 | 文件 | 行数 | 角色 |
|---|---|---|---|
| UI | `lib/features/progress/progress_dialog.dart` | ~120 | 恢复对话框 |
| UI | `lib/features/browser/browser_screen.dart` | ~370 | 调用方 1 |
| UI | `lib/features/playlist/playlist_detail_screen.dart` | ~310 | 调用方 2 |

---

## §3 行为规约

### 3.1 修复后行为

- **[BUG-13-S1]** "从头播放"调用方清除进度记录 (`status: new`)
  ```
  Given 文件 F 有进度记录（positionMs >= 5000）
    And 用户在恢复对话框选"从头播放"（resume == false）
  When  调用方处理 resume == false 分支
  Then  调 clearProgressProvider 删除 F 的进度记录
  否定断言:
    - 不忽略 resume == false（当前 BUG 行为：只处理 true 分支）
    - 不清除其他文件的进度记录
    - 不阻塞播放流程（clear 失败静默继续从头播放）
  ```
  Code evidence: `lib/features/progress/progress_dialog.dart:6-7`（注释声明删除）, `:110-112`（按钮返回 false）
  调用方 1：`lib/features/browser/browser_screen.dart:120-127`（只处理 resume == true）
   调用方 2：`lib/features/playlist/playlist_detail_screen.dart:51-59`（只处理 resume == true）

   **修改指令 — 调用方 1：`lib/features/browser/browser_screen.dart`**

   位置：`:124-126`（`if (resume == true)` 块之后，仍在 `if (progress != null ...)` 块内）

   当前代码（:124-126）：
   ```dart
                           if (resume == true) {
                             startPositionMs = progress.positionMs;
                           }
   ```

   改为：
   ```dart
                           if (resume == true) {
                             startPositionMs = progress.positionMs;
                           } else if (resume == false) {
                             ref.read(clearProgressProvider)(
                               connectionId: conn.id!,
                               filePath: tappedFile.path,
                             );
                           }
   ```

   边界裁决：
   - `resume == null`（对话框被 dismiss 而非按钮触发）→ 不进入任何分支，`startPositionMs` 保持 null → 从头播放但不删记录（用户未明确选择）
   - `clearProgressProvider` 内部已有 try/catch（`progress_provider.dart:120-122`），失败静默 → 不阻塞播放
   - 不 await clearProgressProvider（它返回类型声明为 `void Function(...)` 虽然内部 async）→ 播放不等待清除完成
   - `conn` 和 `tappedFile` 均已在作用域内（`:111-113` 和 `:93`），无需额外变量
   - `clearProgressProvider` 已通过 `shared/di/providers.dart:149` 导出，`browser_screen.dart:22` 已 import → 无需新增 import

   **修改指令 — 调用方 2：`lib/features/playlist/playlist_detail_screen.dart`**

   位置：`:57-59`（`if (resume == true)` 块之后，仍在 `if (progress != null ...)` 块内）

   当前代码（:57-59）：
   ```dart
             if (resume == true) {
               startPositionMs = progress.positionMs;
             }
   ```

   改为：
   ```dart
             if (resume == true) {
               startPositionMs = progress.positionMs;
             } else if (resume == false) {
               ref.read(clearProgressProvider)(
                 connectionId: conn.id!,
                 filePath: filePath,
               );
             }
   ```

   边界裁决：
   - `filePath` 在 `:41` 已定义（`final filePath = tracks[index].filePath`），在作用域内
   - `conn` 在 `:42` 已定义，`conn.id!` 安全（`:47` 已 guard `conn.id != null`）
   - `clearProgressProvider` 已通过 `shared/di/providers.dart` 导出，`playlist_detail_screen.dart:13` 已 import → 无需新增 import
   - 失败静默（同上，clearProgressProvider 内部 catch）→ 不阻塞播放

   **测试文件位置：`test/features/progress/bug_13_repro_test.dart`**

---

## §4 不变量

- **[BUG-13-INV1]** 对话框注释与实现行为一致
  证据：`progress_dialog.dart:6-7`（注释）→ 调用方实现

---

## §5 测试规约

### 5.2 测试 ID 派生清单

```
BUG-13-S1           # 从头播放删进度
BUG-13-INV1         # 注释=实现
```

### 5.4 测试文件位置

| 测试 ID | 文件路径 |
|---------|----------|
| BUG-13-S1 | `test/features/progress/bug_13_repro_test.dart` |

---

## §7 跨模块影响

无跨模块影响。修复局限在 progress 调用方。

---

## §8 平台特性与手动 QA

本功能不涉及平台原生特性，全部可在 `flutter test` 中验证。

---

## §9 dev-status.json 条目对照

见统一更新：`docs/dev/dev-status.json`。

---

## §10 changelog

- 2026-07-27: 创建 BUG-13 spec（基于 cr-20260724-0110.md PRG3）
