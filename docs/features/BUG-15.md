# BUG-15 — 新建播放单 fire-and-forget 无错误处理，DB 失败成未捕获异常

## §0 头部元数据

```yaml
id: BUG-15
name: 新建播放单 fire-and-forget 无错误处理，DB 失败成未捕获异常
priority: P2
status: active
created_at: 2026-08-16
last_updated: 2026-08-16
spec_anchored_files:
  - lib/features/playlist/playlist_list_screen.dart
cross_module_impacts: [Playlist]
parent_feature: Playlist（播放单模块）
manual_qa_required: false
```

---

## §1 用户视角

### 1.0 原始需求（用户原话逐字记录）

来源：`docs/cr/cr-20260816-0804-connection-playlist.md` F2（cr 复核 2026-08-16 已确认仍存在）：

> #### F2. 新建播放单 fire-and-forget 无错误处理，DB 失败成未捕获异常（与删除路径不一致）
> - 类型 / 严重度 / 维度：FRAGILE / Minor / 正确性（错误处理不一致）
> - 证据：
>   - `lib/features/playlist/playlist_list_screen.dart:166-170` — `ref.read(createPlaylistProvider)(name); Navigator.of(context).pop();` 不 await、无 try/catch
>   - 对比同文件删除路径 `:71-88` 有完整 try/catch + SnackBar + debugPrint（BUG-25-S3 纪律）；add_tracks 路径 `add_tracks_browser.dart:102-116` 也有 `.catchError` 处理
> - 复现路径（条件：创建时 DB 写失败，如磁盘满/库损坏）：新建播放单弹窗 → 输入名称 → 创建 → insert 抛异常 → Future 无人 await → unhandled async exception（debug 崩测试 zone / release 走 FlutterError.onError），用户无任何反馈，对话框已关。期望：与删除一致——log + SnackBar"创建失败"。
> - 自检答案：分支零覆盖——ply_11 PLY-T56 只测创建成功 + 列表刷新，无失败注入（对比删除有 bug_bug25 的 S3 失败注入系列）。
> - 修复建议：与 BUG-25-S3 同款：`await` + try/catch + 失败 log + SnackBar。

### 1.1 这一功能干什么（一句话）

新建播放单的创建调用与删除路径同款错误处理：await + try/catch + 日志 + SnackBar，DB 失败不再成为未捕获异常且用户获得反馈。

### 1.2 用户期望的场景

| ID | 你看到的样子 | 期望行为 |
|----|----|----|
| U1 | 新建播放单时磁盘满/数据库损坏，创建失败 | 对话框关闭后出现"创建失败：…"的红色提示条，日志有记录；不再有未捕获异常（修复前：无声无息，debug 下直接崩测试区/红屏） |
| U2 | 正常创建播放单 | 行为完全不变：输入名称点"创建"→ 对话框关闭 → 列表出现新播放单 |
| U3 | 名称输入为空点"创建" | 保持现状：直接忽略（空名门禁 :167-168 不进入创建调用） |

---

## §2 已实现的功能骨架（代码锚点）

### 2.1 文件与分层

| 层 | 文件 | 行数 | 角色 |
|---|---|---|---|
| UI | `lib/features/playlist/playlist_list_screen.dart` | 281 | 创建对话框 `_CreatePlaylistDialog`（:134-177）：创建按钮 :165-173 fire-and-forget；删除路径 :71-88（BUG-25-S3 同款 try/catch） |
| Provider | `lib/features/playlist/playlist_provider.dart` | ~110 | `createPlaylistProvider`（:92-98）：await service.createPlaylist 成功后 invalidate playlistListProvider |
| Domain | `lib/features/playlist/domain/playlist_service.dart` | ~170 | createPlaylist（:36 起） |
| 测试 | `test/features/playlist/bug_bug15_repro_test.dart` | 本 spec §5.4 | 本 Bug 门禁 |

### 2.2 关键 Provider 表

| Provider 名 | 类型 | 实现位置 | 用途 |
|---|---|---|---|
| playlistListProvider | FutureProvider<List<Playlist>> | playlist_provider.dart | 列表数据源 |
| createPlaylistProvider | Provider<Future<void> Function(String)> | playlist_provider.dart:92-98 | 创建入口（成功后 invalidate 列表） |

### 2.3 状态机图

本 Bug 不涉状态机，跳过。

---

## §3 行为规约（Given-When-Then）

### 3.1 现有行为（逆抽，缺陷态）

- **[BUG-15-S1]** 创建按钮 fire-and-forget：不 await、无 try/catch
  ```
  Given _CreatePlaylistDialog 打开，用户输入非空名称
  When 点击"创建"
  Then onPressed 执行 ref.read(createPlaylistProvider)(name)（不 await）
  And 立即 Navigator.of(context).pop()（对话框关闭）
  And 若 createPlaylistProvider 抛错 → Future 无人监听 → unhandled
       async exception（debug 崩测试 zone / release FlutterError.onError）
  ```
  Code evidence: `lib/features/playlist/playlist_list_screen.dart:165-173`

- **[BUG-15-S2]** 对比参照：删除路径有完整错误处理（BUG-25-S3）
  ```
  Given 用户删除播放单
  When deletePlaylistProvider 抛错
  Then debugPrint('[Playlist] delete failed: $e')（:78）
  And SnackBar '删除失败：$e'（:79-87）
  ```
  Code evidence: `lib/features/playlist/playlist_list_screen.dart:71-88`

### 3.2 修复方案（status: new）

- **[BUG-15-S3]** 创建路径与删除路径同款错误处理（status: new）
  ```
  Given 用户输入非空名称点击"创建"
  When createPlaylistProvider 成功
  Then 对话框关闭（pop），列表刷新（createPlaylistProvider 内部 invalidate，行为不变）
  When createPlaylistProvider 抛错（DB 写失败）
  Then debugPrint('[Playlist] create failed: $e')（catch-log 纪律，SCHEMA §5）
  And 对话框关闭（与删除路径一致：对话框先关、SnackBar 反馈）
  And SnackBar '创建失败：$e'（红色 error 样式，与删除 :79-87 同款）
  And 无 unhandled async exception 泄漏
  否定断言:
    - 失败时列表不刷新（createPlaylistProvider 的 invalidate 只在成功后执行——
      playlist_provider.dart:92-98，异常上抛时 invalidate 不执行）
    - 空名称仍被 :167-168 门禁拦截（不进入创建调用）
    - 对话框成功关闭（不残留 dialog 在导航栈）
  ```
  **修改点（唯一生产代码改动）**：`lib/features/playlist/playlist_list_screen.dart:165-173`：
  ```dart
  // 修改前（165-173 行）:
  TextButton(
    onPressed: () {
      final name = _controller.text.trim();
      if (name.isEmpty) return;
      ref.read(createPlaylistProvider)(name);
      Navigator.of(context).pop();
    },
    child: const Text('创建'),
  ),
  // 修改后:
  TextButton(
    onPressed: () async {
      final name = _controller.text.trim();
      if (name.isEmpty) return;
      try {
        await ref.read(createPlaylistProvider)(name);
      } catch (e) {
        // BUG-25-S3 同款纪律：DB 失败不得静默消失。
        debugPrint('[Playlist] create failed: $e');
      } finally {
        if (context.mounted) Navigator.of(context).pop();
      }
      // 失败时 SnackBar 在对话框 pop 之后显示（ScaffoldMessenger 沿
      // MaterialApp 层查找，对话框 context 有效）——与删除路径一致。
    },
    child: const Text('创建'),
  ),
  ```
  SnackBar 展示位置说明（弱模型照抄）：在 `finally` 的 pop 之后、回调末尾追加（或 pop 前捕获错误文本后 pop、再 `ScaffoldMessenger.of(context).showSnackBar`）——**必须用 `if (context.mounted)` 守卫**（P9：setState/回调在 defunct 元素上调用会崩；对话框 pop 动画期间回调 context 仍有效，但 await 之后必须守卫）。文件头已 `import 'package:flutter/material.dart'`（debugPrint 来自 flutter/foundation，经 material 导出），无新增 import。
  **模式依据（铁律 6）**：`if (context.mounted)` 是 Flutter 3.7+ 官方推荐的 async-gap 守卫（本项目 BUG-25 系列已大量使用同款：playlist_list_screen.dart:79、connection_screen.dart:211 等——file:line 实证，不需重复验证）；`Navigator.of(context).pop()` 在 await 后经 `context.mounted` 守卫。

**边界裁决（弱模型照此实现，无需二次判断）**：

| 边界情况 | 裁决 |
|---|---|
| 创建成功 | await 正常返回 → finally pop（原行为：立即 pop，现在改为成功后 pop，时序差一帧无感）；列表由 createPlaylistProvider 内部 invalidate 刷新 |
| 创建失败 | catch 记日志 → finally pop（对话框关）→ SnackBar '创建失败：$e' |
| 空名称 | :167-168 先 return，不进入 try（无任何调用） |
| await 期间用户又点创建（对话框未关） | 按钮可连点——但每次创建都是独立调用；失败/成功语义各自独立。既有行为已是如此（fire-and-forget 同样可连点），本次不改（不扩大改动面） |
| 对话框 pop 动画期间 await 完成 | `context.mounted` 在 pop 动画期间仍为 true（元素仍在树中），pop 调用安全（与删除路径 :79 同款语义） |

---

## §4 不变量

- **[BUG-15-INV1]** 播放单创建成功才刷新列表：`createPlaylistProvider` 的 `ref.invalidate(playlistListProvider)` 仅在 `service.createPlaylist` 成功后执行，异常上抛路径不刷新
  证据：`lib/features/playlist/playlist_provider.dart:92-98`（await service.createPlaylist 之后才 invalidate）

---

## §5 测试规约

### 5.1 现有测试清单

| 测试文件 | 覆盖的 Scenario / INV | 备注 |
|---|---|---|
| test/features/playlist/ply_11_test.dart（PLY-T56~T59） | 创建成功 + 列表刷新 | 无失败注入（自检答案） |
| test/features/playlist/bug_bug25_repro_test.dart | 删除路径失败注入（S3） | 修复参照系 |

### 5.2 测试 ID 派生清单（dev-exe 派发测试 Agent 用）

```
BUG-15-S1, S2        # 缺陷态/现状锚定
BUG-15-S3            # 修复目标
BUG-15-INV1          # 不变量
```

dev-exe 要求：S3 由 §5.4 门禁测试覆盖（成功/失败两分支由既有 ply_11 + 门禁共同锚定）；INV1 由 ply_11 既有"创建成功刷新"测试锚定。

### 5.3 测试覆盖盲点（dev-plan 写本文档时识别）

| 未覆盖 ID | 现状 | 应补偿方式 |
|---|---|---|
| 无 | — | — |

### 5.4 测试文件位置（spec-scan --gate 硬校验）

| 测试文件 | 覆盖 ID | 说明 |
|---|---|---|
| test/features/playlist/bug_bug15_repro_test.dart | BUG-15-S3 | 门禁：修复前 FAIL（已用 repro-test.sh fail 确认——unhandled async exception 使 testWidgets 失败）；dev-exe 修复后必须 PASS（repro-test.sh pass，断言 '创建失败' SnackBar 出现） |

---

## §6 算法样例

本 Bug 不涉纯函数算法，跳过。

---

## §7 跨模块影响

`bash cross-imports.sh impact lib/features/playlist/playlist_list_screen.dart`（2026-08-16）→ 引用方：playlist feature 内部（playlist_list_screen 仅被自身 feature 引用，无跨 feature import）。

| 其它 feature | 影响点 | 影响条件 | 需要补的回归断言 |
|---|---|---|---|
| Playlist（playlist_provider.dart:92-98） | createPlaylistProvider 消费方 | 修复只改 UI 侧调用方式（await+try/catch），provider 行为不变 | ply_11 既有创建测试全绿 |
| Playlist（删除路径 :71-88） | 同文件既有 BUG-25-S3 逻辑 | 不动删除路径代码 | bug_bug25 系列测试全绿 |
| add_tracks_browser.dart:102-116（.catchError 路径） | 同模块其它错误处理 | 不改 | net1_legacy / ply_10 既有测试全绿 |

---

## §8 平台特性与手动 QA

设计前已逐条核对 `docs/dev/platform-pitfalls.md`：触及 **P9**（await 后 setState/回调需 mounted 守卫——本修复 finally pop 用 context.mounted 守卫，显式处置见 §3 边界裁决）。P13（async gap 重建）不涉及（无列表项 Key 变更）。

**真机风险列**：无。本功能不涉及平台原生特性，全部可在 `flutter test` 中验证（DB 失败注入用 provider override 即可）。

---

## §9 dev-status.json 条目对照

```json
"BUG-15": {
  "spec_file": "docs/features/BUG-15.md",
  "spec_anchored_files": ["lib/features/playlist/playlist_list_screen.dart"],
  "scenarios": ["BUG-15-S1", "BUG-15-S2", "BUG-15-S3"],
  "invariants": ["BUG-15-INV1"],
  "algorithms": [],
  "manual_qa_required": false,
  "user_acceptance_text": "见 §1.2"
}
```
