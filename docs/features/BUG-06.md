# BUG-06 — "下一曲"图标启用态不响应播放状态

> 来源：`docs/cr/cr-20260724-0110.md` BRW2
> dev-plan 流程：Bug 修复模式

---

## §0 头部元数据

```yaml
id: BUG-06
name: "下一曲"图标启用态不响应播放状态
priority: P1
status: draft
created_at: 2026-07-27
last_updated: 2026-07-27
spec_anchored_files:
  - lib/features/browser/browser_screen.dart
  - lib/features/player/player_provider.dart
cross_module_impacts: [PLY]
parent_feature: Browser
manual_qa_required: false
```

---

## §1 用户视角

### 1.0 原始需求

> cr-20260724-0110.md BRW2：browser_screen.dart watch audioPlayerProvider 取 .playing 快照，但 provider 持同一实例永不重建 → 图标启用态冻结在 build 瞬间。

### 1.1 这一功能干什么（一句话）

修复浏览器页"下一曲"图标不随播放/暂停状态变化的缺陷。

### 1.2 用户期望的场景

| ID | 你看到的样子 | 期望行为 |
|----|----|----|
| U1 | 冷启动恢复队列 playing=false，进浏览器页 | 图标初始灰禁；迷你栏点播放后图标立即变亮 |
| U2 | 播放中浏览列表，迷你栏暂停 | 图标立即变灰禁；点击不触发 insertAfterCurrent |

---

## §2 已实现的功能骨架

### 2.1 文件与分层

| 层 | 文件 | 行数 | 角色 |
|---|---|---|---|
| UI | `lib/features/browser/browser_screen.dart` | ~370 | 浏览器页，含"下一曲"图标 |
| Provider | `lib/features/player/player_provider.dart` | ~330 | audioPlayerProvider 持 AudioPlayer 实例 |

---

## §3 行为规约

### 3.1 修复后行为

- **[BUG-06-S1]** 新增 playingStream StreamProvider 响应播放状态 (`status: new`)
  ```
  Given AudioPlayer 实例的 playingStream 发射 true/false
  When  browser_screen watch playingStreamProvider
  Then  图标 enabled 状态实时响应
  否定断言:
    - 不依赖 audioPlayerProvider 实例变化触发重建（实例永不变）
    - 不在 playing=false 时触发 insertAfterCurrentProvider（BRW-09 S9）
  ```
  Code evidence: `lib/features/browser/browser_screen.dart:77-78`（当前用 ref.watch(audioPlayerProvider).playing 快照）

  **修改指令（3 处变更）：**

  **变更 1 — 新增 provider：** `lib/features/player/player_provider.dart:50`（在 `audioPlayerProvider` 定义之后插入）

  **新增代码：**
  ```dart
  final audioPlayingProvider = StreamProvider<bool>((ref) {
    final player = ref.watch(audioPlayerProvider);
    return player.playingStream;
  });
  ```

  **变更 2 — 导出 provider：** `lib/shared/di/providers.dart:79`（在 `show` 列表中添加 `audioPlayingProvider`）

  **当前代码：**
  ```dart
  export '../../features/player/player_provider.dart'
      show
          // Infrastructure
          audioPlayerProvider,
          audioHandlerProvider,
  ```

  **修改为：**
  ```dart
  export '../../features/player/player_provider.dart'
      show
          // Infrastructure
          audioPlayerProvider,
          audioPlayingProvider,
          audioHandlerProvider,
  ```

  **变更 3 — 消费端：** `lib/features/browser/browser_screen.dart:77-78`

  **当前代码：**
  ```dart
  playNextEnabled: ref.watch(audioPlayerProvider).playing &&
      ref.watch(currentPlayQueueProvider) != null,
  ```

  **修改为：**
  ```dart
  playNextEnabled: (ref.watch(audioPlayingProvider).valueOrNull ?? false) &&
      ref.watch(currentPlayQueueProvider) != null,
  ```

  **边界决策：**
  - stream 尚未发射首值时 `valueOrNull` 返回 null → `?? false` 兜底，图标初始灰禁（安全默认值）
  - AudioPlayer.playingStream 在 just_audio 中会在 playing 属性变化时立即发射 → 无需额外初始值注入
  - provider 随 audioPlayerProvider 重建而重建（ref.watch）→ 生命周期正确

  **测试文件：** `test/features/browser/bug_06_playing_stream_test.dart`（避免与旧 BUG-06 测试冲突）

- **[BUG-06-S2]** playing=false 时点击图标不触发 provider 调用 (`status: new`)
  ```
  Given playing=false, 当前有队列
  When  点击"下一曲"图标
  Then  图标 onPressed 为 null（禁用态）或回调内早退
  否定断言:
    - 不调用 insertAfterCurrentProvider（BRW-09 INV4）
  ```
  Code evidence: `lib/features/browser/browser_screen.dart:84-85`（playNextEnabled 计算）

  **修改指令：**

  **文件：** `lib/features/browser/browser_screen.dart:77-78`（与 BUG-06-S1 同一处修改）

  修改后 `playNextEnabled` 在 `playing=false` 时为 `false`，图标自动变为禁用态（`onPressed: null`），无需额外代码。

  **验证方式：** 确认 `_FileList` widget 在 `playNextEnabled=false` 时渲染禁用态 IconButton（`onPressed: null`）。

  **边界决策：**
  - playing=false 且无队列 → `false && false` = false → 图标禁用
  - playing=true 且无队列 → `true && false` = false → 图标禁用
  - playing=false 且有队列 → `false && true` = false → 图标禁用（核心修复点）

  **测试文件：** `test/features/browser/bug_06_playing_stream_test.dart`

---

## §4 不变量

- **[BUG-06-INV1]** "下一曲"图标 enabled 态与 AudioPlayer.playing 实时同步
  证据：`browser_screen.dart:77-78`（修复目标）

---

## §5 测试规约

### 5.2 测试 ID 派生清单

```
BUG-06-S1 S2          # 响应性 + 禁用态
BUG-06-INV1           # 同步不变量
```

### 5.4 测试文件位置

| 测试 ID | 文件路径 |
|---|---|
| BUG-06-S1 | `test/features/browser/bug_06_playing_stream_test.dart` |
| BUG-06-S2 | `test/features/browser/bug_06_playing_stream_test.dart` |
| BUG-06-INV1 | `test/features/browser/bug_06_playing_stream_test.dart` |

---

## §7 跨模块影响

| 其它 feature | 影响点 | 影响条件 | 需要补的回归断言 |
|---|---|---|---|
| PLY | insertAfterCurrentProvider 不被 playing=false 触发 | 图标禁用态 | widget 测试：playing=false → 点击 → verify 不调用 |

---

## §8 平台特性与手动 QA

本功能不涉及平台原生特性，全部可在 `flutter test` 中验证。

---

## §9 dev-status.json 条目对照

见统一更新：`docs/dev/dev-status.json`。

---

## §10 changelog

- 2026-07-27: 创建 BUG-06 spec（基于 cr-20260724-0110.md BRW2）
