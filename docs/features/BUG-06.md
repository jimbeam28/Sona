# BUG-06 — 启动恢复 preload 绕过 SerializedRequestGate 直连 AudioPlayer：晚到副作用覆盖用户选择（P14 绕门）

## §0 头部元数据

```yaml
id: BUG-06
name: 启动恢复 preload 绕门直连 AudioPlayer，晚到副作用覆盖用户选择（P14）
priority: P1
status: active
created_at: 2026-08-16
last_updated: 2026-08-16
spec_anchored_files:
  - lib/features/browser/browser_provider.dart
  - lib/core/services/audio_source_builder.dart
  - lib/app/onboarding.dart
cross_module_impacts: [BRW, PLY]
parent_feature: Browser（文件浏览/启动恢复）
manual_qa_required: true        # 涉真机弱网启动时序
```

---

## §1 用户视角

### 1.0 原始需求（用户原话逐字记录）

来源：`docs/cr/cr-20260816-0802-player.md` F2（cr 复核已确认仍存在）：

> #### F2. 启动恢复 preload 绕过 SerializedRequestGate 直连 AudioPlayer（P14 绕门）
> - 类型：FRAGILE / 严重度：Critical（按 cr-dimensions §2.2 绕门直达 AudioPlayer 判级）/ 维度：功能-踩坑（P14）
> - 证据：
>
> `lib/features/browser/browser_provider.dart:235-242`（启动恢复路径，直接 setAudioSource）：
> ```dart
> await preloadAudioSource(
>     storage: ..., connectionId: ..., baseUrl: ..., filePath: files[idx].path,
>     username: ..., player: ref.read(audioPlayerProvider), startPositionMs: posMs);
> ```
> `lib/core/services/audio_source_builder.dart:162-167`（10s 超时内可晚到）：
> ```dart
> await player.setAudioSource(src).timeout(const Duration(seconds: 10));
> if (startPositionMs != null) { await player.seek(...).timeout(...); }
> ```
> 触发链：`restoreQueueFromPrefsProvider` → onboarding 只 `ref.read` 不 await（`onboarding.dart:64-67` 立即 `go('/browser')`）→ 用户可在 preload 未完成时点曲。
> - 复现路径（条件：慢 NAS 且启动后 ~10s 内用户点曲）：启动恢复 preload 进行中（10s 窗口）→ 用户在浏览器点另一首 → loadAndPlay（gate 内）setAudioSource 完成、开始播放 → preload 的 setAudioSource 后到 → **覆盖用户选择的 source**，播放被换回恢复的旧曲。
> - 自检答案：**该分支零覆盖**——preload 只有单元测试（无并发编排），无任何测试驱动"preload 与用户加载并发写同一 AudioPlayer"。
> - 修复建议：preload 走 SerializedRequestGate（或加载前比对 `player.audioSource`/队列连接 ID，晚到即弃）；与 loadAndPlay 共用同一把锁。

### 1.1 这一功能干什么（一句话）

让启动恢复的曲目预加载与用户手动选曲互不干扰：用户一旦选了新曲，尚未完成的旧 preload 必须立即放弃剩余步骤（晚到即弃），不得在用户选曲完成后继续对播放器发 seek / setAudioSource 等副作用。

### 1.2 用户期望的场景

| ID | 你看到的样子 | 期望行为 |
|----|----|----|
| U1 | 打开 App，上次的歌曲在后台预加载（弱网较慢） | 预加载期间浏览文件列表不受影响 |
| U2 | 预加载未完成时点了一首新歌 | 新歌正常开始播放；**旧 preload 的剩余步骤（seek 等）不得再对播放器动手**（修复前：旧曲进度会把新歌的播放位置拨乱） |
| U3 | 预加载未完成时点了一首新歌（极端弱网，preload 后到） | 播放的始终是用户点的歌，不会突然变回上次的旧曲 |
| U4 | 预加载正常完成（用户未干预） | 行为与现在一致（source 就绪、进度位恢复，mini 播放器立即可用） |

---

## §2 已实现的功能骨架（代码锚点）

### 2.1 文件与分层

| 层 | 文件 | 行数 | 角色 |
|---|---|---|---|
| Provider | `lib/features/browser/browser_provider.dart` | 258 | restoreQueueFromPrefsProvider（184-250）：恢复队列 + preload 触发（233-246，绕门缺陷点） |
| Core | `lib/core/services/audio_source_builder.dart` | 168 | preloadAudioSource（141-168）：setAudioSource 10s 超时（162）+ seek 10s 超时（163-167） |
| UI | `lib/app/onboarding.dart` | 171 | 64-67：只 read 不 await 即 go('/browser')（preload 未完成窗口） |
| 测试 | `test/features/browser/bug_06_repro_test.dart` | 本 spec §5.4 | 本 Bug 门禁（修复前 FAIL，已用 repro-test.sh fail 确认） |

### 2.2 关键 Provider 表

| Provider 名 | 类型 | 实现位置 | 用途 |
|---|---|---|---|
| restoreQueueFromPrefsProvider | FutureProvider<void> | browser_provider.dart:184-250 | 启动恢复：读 prefs → 重建队列 → preload 当前曲 |
| currentPlayQueueProvider | StateProvider<PlayQueue?> | browser_provider.dart（导出于 shared/di） | 恢复写队列（:219）；用户选曲改队列 |
| playModeProvider | StateProvider<PlayMode> | player_provider.dart:144 | 恢复回写播放模式（:230） |

### 2.3 状态机图

```
启动
 └─ restoreQueueFromPrefsProvider（不 await，onboarding:64-67）
     ├─ 读 prefs → 队列恢复 → playMode 恢复
     └─ preloadAudioSource（绕门，直连 player）
         ├─ t=0: 读密码（≤5s）
         ├─ t≈5s: player.setAudioSource(旧曲)  ← 挂起（慢 NAS）
         ├─ t≈6s: 用户点新曲 → loadAndPlay(gate) → player.setAudioSource(新曲) 完成
         ├─ t≈15s: preload 的 setAudioSource 完成 → player.seek(旧曲位置)  ← 缺陷副作用
         └─ （若更慢）preload 完成时序晚于用户加载 → 平台层旧曲胜出 ← 覆盖风险
```

---

## §3 行为规约（Given-When-Then）

### 3.1 现有行为（逆抽，缺陷态）

- **[BUG-06-S1]** 启动恢复直连 preloadAudioSource，不经过 SerializedRequestGate（P14 绕门）
  ```
  Given restoreQueueFromPrefsProvider 执行到恢复分支（连接匹配、有密码）
  When 触发 preload
  Then 直接调 audio_source_builder.preloadAudioSource（绕开 orchestrator 的 gate）
  And 失败仅被 catch + debugPrint 吞掉（browser_provider.dart:243-245）
  ```
  Code evidence: `lib/features/browser/browser_provider.dart:233-246`；对比 orchestrator 内 `_gate.schedule`（`lib/features/player/domain/playback_orchestrator.dart:142`）。

- **[BUG-06-S2]** preload 的 seek 在 setAudioSource 完成后无条件执行（缺陷副作用点）
  ```
  Given preload 的 setAudioSource 完成（含 10s 超时窗内晚到）
  When startPositionMs != null
  Then 无条件 await player.seek(旧曲位置)（不检查队列是否已被用户改动）
  ```
  Code evidence: `lib/core/services/audio_source_builder.dart:162-167`。

- **[BUG-06-S3]** onboarding 只 read 不 await，preload 与用户加载并发窗口存在
  ```
  Given onboarding 判定验证成功
  When postFrameCallback 执行（:64-67）
  Then ref.read(restoreStartupProgressProvider) 后立即 context.go('/browser')
  And restore 链（含 preload）未完成时用户已可点曲
  ```
  Code evidence: `lib/app/onboarding.dart:64-67`；`restoreStartupProgressProvider`（player_provider.dart:220-240）await restoreQueueFromPrefsProvider.future。

### 3.2 修复方案（status: new）

- **[BUG-06-S4]** preloadAudioSource 增加"晚到即弃"守卫：每个 player 调用前检查队列时效性（修改点 1） （status: new）
  ```
  Given preloadAudioSource 执行中（密码读取后、setAudioSource 前 / seek 前）
  When shouldAbandon 回调返回 true（队列已被用户改动/清空）
  Then 立即返回，不再调用 player.setAudioSource / player.seek
  否定断言:
    - shouldAbandon == true 时不得有任何 player 副作用（setAudioSource/seek 均不发）
    - shouldAbandon == false 时行为与修复前一致（正常 preload 全流程）
    - 守卫不得改变 preload 的返回值语义（Future<void>，成功路径不抛错）
  ```
  **修改点**：`lib/core/services/audio_source_builder.dart:141-168` — `preloadAudioSource` 增加可选参数 `bool Function()? shouldAbandon`，并在两处平台调用前检查：
  ```dart
  Future<void> preloadAudioSource({
    required ISecureStorage storage,
    required int connectionId,
    required String baseUrl,
    required String filePath,
    required String username,
    required AudioPlayer player,
    int? startPositionMs,
    // BUG-06（cr-20260816-0802 F2）：晚到即弃守卫——每个 player 调用前
    // 检查队列时效性。用户已在 preload 未完成时选了其它曲目 → 放弃剩余
    // 步骤，防止旧曲进度 seek 落到用户新选的曲目上（P14 绕门补口）。
    bool Function()? shouldAbandon,
  }) async {
    String? pw;
    try {
      pw = await safeStorageRead(storage, key: 'connection_password_$connectionId');
    } on SecureStorageTimeoutException {
      debugPrint('[AudioSource] preload: secure storage read timeout, skip');
      return;
    }
    if (pw == null || pw.isEmpty) return;
    if (shouldAbandon?.call() ?? false) return;
    final src = AudioSourceBuilder.buildWithBasePath(
        baseUrl: baseUrl, filePath: filePath, username: username, password: pw);
    await player.setAudioSource(src).timeout(const Duration(seconds: 10));
    if (shouldAbandon?.call() ?? false) return;
    if (startPositionMs != null) {
      await player
          .seek(Duration(milliseconds: startPositionMs))
          .timeout(const Duration(seconds: 10));
    }
  }
  ```
  **可行性依据（铁律 6）**：可选回调参数是 Dart 标准语法，本项目多处已用同类注入（如 `AudioSessionProvider` 构造注入，audio_handler.dart:35）；`shouldAbandon?.call() ?? false` 空安全模式与现有 `onSkipToNextRequested?.call()`（audio_handler.dart:314）同款。无新框架 API。

- **[BUG-06-S5]** restoreQueueFromPrefsProvider 提供队列时效性守卫（修改点 2） （status: new）
  ```
  Given restoreQueueFromPrefsProvider 调用 preloadAudioSource
  When 传递 shouldAbandon 回调
  Then 回调语义：当前队列为空 / current 曲目不再是本次恢复的曲目 / 播放器已有
       用户加载的 source → true（放弃）
  And 正常恢复场景（队列未变）→ false（preload 全流程照常）
  否定断言:
    - 回调为 true 时不得引发异常（preload 静默放弃，FakeAsync 内无 unhandled）
    - 用户清空队列后 preload 不得再发任何调用
  ```
  **修改点**：`lib/features/browser/browser_provider.dart:235-242` — preloadAudioSource 调用加 `shouldAbandon`：
  ```dart
  await preloadAudioSource(
      storage: ref.read(secureStorageProvider),
      connectionId: conn.id!,
      baseUrl: webDavEffectiveBaseUrl(conn.url, conn.basePath),
      filePath: files[idx].path,
      username: conn.username,
      player: ref.read(audioPlayerProvider),
      startPositionMs: posMs,
      // BUG-06：晚到即弃——preload 期间用户已选其它曲目（队列 current 变）
      // 或清空队列 → 放弃剩余步骤。preload 与用户加载共用同一播放器且
      // 无串行化（P14），守卫以"恢复的曲目是否仍是当前曲目"为准绳。
      shouldAbandon: () {
        final q = ref.read(currentPlayQueueProvider);
        return q == null || q.length == 0 || q.current.path != files[idx].path;
      });
  ```
  **P14 绕门裁决**：cr 修复建议给出两条路线（走 gate / 晚到即弃）。本 spec 选**晚到即弃**路线：preload 与用户加载的串行化若走同一 gate，需要把 gate 从 orchestrator 私有域暴露出来并保证"晚到任务不得重发平台调用"（gate 只影响结果不影响任务体，不能阻止 in-flight 平台调用晚到完成，见铁律 6 依据下方分析）——成本高且不收敛；晚到即弃在**每个平台调用点**前用队列时效性裁决，直接消灭副作用面。若 dev-check 后续判定需更强串行化，再单独升级。

**边界裁决（弱模型照此实现，无需二次判断）**：

| 边界情况 | 裁决 |
|---|---|
| preload 正常完成（用户未干预） | shouldAbandon 全程 false → 行为与修复前完全一致（S4 否定断言） |
| 用户在 preload 密码读取期间选了新曲 | setAudioSource 前的守卫 → 放弃，不发任何调用 |
| 用户在 preload setAudioSource 挂起期间选了新曲 | setAudioSource 已发出（无法撤回，平台层 last-issued-wins 由用户调用覆盖）→ seek 前守卫 → 放弃 seek（门禁 T1 锚定的主症状） |
| 用户清空队列 | q == null → true → 放弃 |
| 队列非空但 current 被用户改成其它曲 | q.current.path != files[idx].path → true → 放弃 |
| 恢复自身写队列（:219 先于 preload） | 守卫在 preload 内读取时队列已是恢复态，current.path == files[idx].path → false，不误弃 |
| shouldAbandon 参数未传（其它调用方） | `?? false` → 行为不变（audio_source_builder 的既有单测不受影响） |
| restore 异常路径（catch :243-245） | 不变（debugPrint + 继续） |

---

## §4 不变量

- **[BUG-06-INV1]** preload 的每个 player 平台调用（setAudioSource/seek）前都必须过时效性检查：队列为 null / 空 / current 不再是恢复曲目时一律不发
  证据：修复后 `audio_source_builder.dart:141-168`（S4 修改点两处检查）。

- **[BUG-06-INV2]** 用户选择的曲目一旦开始加载，任何旧 preload 不得再改变播放器状态（source/seek 均不得）
  证据：修复后 S4/S5 组合（shouldAbandon 在 seek 前必查）；门禁测试 T1 断言。

- **[BUG-06-INV3]** 恢复链（restoreQueueFromPrefsProvider）的失败吞错语义不变（preload 放弃不算失败，不抛错）
  证据：`browser_provider.dart:243-245`（catch + debugPrint）保持；S4 放弃路径直接 return。

---

## §5 测试规约

### 5.1 现有测试清单

| 测试文件 | 覆盖的 Scenario / INV | 备注 |
|---|---|---|
| test/features/browser/bug_06_repro_test.dart | BUG-06-S4 / S5 / INV1 / INV2 / INV3 | 本 Bug 门禁（修复前 FAIL，已用 repro-test.sh fail 确认） |
| test/features/browser/net1_legacy_queue_restore_test.dart / o3_* 系列 | BUG-06-S1 的恢复面（队列恢复本身） | 恢复流程断言不涉 preload 时序 |
| audio_source_builder 既有单测 | BUG-06-S4 的参数缺省面 | 不传 shouldAbandon 行为不变 |

### 5.2 测试 ID 派生清单（dev-exe 派发测试 Agent 用）

```
BUG-06-S1 … S5        # Scenario（S1~S3 现状锚定，S4/S5 修复目标）
BUG-06-INV1 … INV3    # 不变量
BUG-06-MAN1 …         # 手动 QA 步骤（见 §8）
```

dev-exe 要求：S4/S5/INV1~3 由 §5.4 门禁测试覆盖；S1~S3 由门禁测试前置断言与既有恢复测试锚定。

### 5.3 测试覆盖盲点（dev-plan 写本文档时识别）

| 未覆盖 ID | 现状 | 应补偿方式 |
|---|---|---|
| BUG-06-MAN1~MAN2 | 真机弱网启动时序 | 进 mqa-backlog（§8） |
| "极慢 preload 完成晚于用户加载完成"的平台层 source 覆盖（T2 防御面） | 门禁 T2 断言 last-issued-wins；平台层行为（ExoPlayer 取消旧 prepare）依赖 just_audio 语义 | dev-exe 可在门禁内补一条源码扫描（audio_source_builder.dart 不得存在"setAudioSource 后无条件 seek"形态） |

### 5.4 测试文件位置（spec-scan --gate 硬校验）

| 测试文件 | 覆盖 ID | 说明 |
|---|---|---|
| test/features/browser/bug_06_repro_test.dart | BUG-06-S4、BUG-06-S5、BUG-06-INV1、BUG-06-INV2、BUG-06-INV3 | 门禁：dev-exe 修复后必须 PASS（repro-test.sh pass） |

---

## §6 算法样例

本 Bug 不涉纯函数算法，跳过。

---

## §7 跨模块影响

`bash cross-imports.sh impact lib/features/browser/browser_provider.dart lib/core/services/audio_source_builder.dart lib/app/onboarding.dart`（2026-08-16）→ 引用方：

| 其它 feature | 影响点 | 影响条件 | 需要补的回归断言 |
|---|---|---|---|
| PLY（player_provider.dart:220-240 restoreStartupProgressProvider） | await restoreQueueFromPrefsProvider → preload 语义变化 | 修复只在 preload 剩余步骤（放弃 seek/setAudioSource），恢复队列/进度补丁（applyLatestProgressToQueue + seek）不变 | o3_*/net1 恢复测试全绿；bug_06_repro_test.dart PASS |
| PLY（audio_player_provider 消费者） | preload 放弃后播放器状态由用户加载独占 | 无（用户加载路径不动） | ply_01~14 全绿 |
| BRW（restoreQueueFromPrefsProvider 其它调用方） | 恢复流程不变 | 无（onboarding 仍不 await，正常） | test_01_brw09~11 / bug_14 / bug_bug30/31 全绿 |
| onboarding（app 层） | 不 await 行为保持 | 修复不碰 onboarding | onboarding 既有测试全绿 |
| audio_source_builder 既有单测 | 新参数缺省 = 旧行为 | `?? false` | audio_source_builder 既有测试全绿 |

---

## §8 平台特性与手动 QA

设计前已逐条核对 `docs/dev/platform-pitfalls.md`：本 Bug 即 **P14**（加载并发写同一 AudioPlayer 必须串行化——绕门路径补"晚到即弃"守卫）的直接处置；**P4**（平台调用挂起）是 10s 超时窗口的成因；**P17** 分层表（preload setAudioSource/seek 10s）数值不变，只加守卫不改数值。

**真机风险列**（fake 测不到、只有真机会出问题的）：

| 风险 | 近似测试方案 | 测不了 → 进 mqa-backlog |
|---|---|---|
| 弱网启动 + 立即点曲：旧曲 seek 把新歌位置拨乱 | bug_06_repro_test.dart（挂起 setAudioSource + 释放 → 断言无 seek） | BUG-06-MAN1：真机限速启动 App，恢复曲预加载未完成时立即点另一首 → 期望新歌从头正常播放，无跳变 |
| 极端时序：preload 完成晚于用户加载完成（平台层 source 竞争） | bug_06 T2（last-issued-wins 契约） | BUG-06-MAN2：同上场景观察播放曲目是否稳定为用户所选；重复 5 次 |
| 预加载正常路径（用户未干预）不受影响 | bug_06 门禁 + audio_source_builder 既有单测 | BUG-06-MAN3：正常启动（不限速）→ mini 播放器立即可用、进度位正确 |

涉及真机弱网时序 → `manual_qa_required = true`。

---

## §9 dev-status.json 条目对照

```json
"BUG-06": {
  "spec_file": "docs/features/BUG-06.md",
  "spec_anchored_files": [
    "lib/features/browser/browser_provider.dart",
    "lib/core/services/audio_source_builder.dart",
    "lib/app/onboarding.dart"
  ],
  "scenarios": ["BUG-06-S1", "BUG-06-S2", "BUG-06-S3", "BUG-06-S4", "BUG-06-S5"],
  "invariants": ["BUG-06-INV1", "BUG-06-INV2", "BUG-06-INV3"],
  "algorithms": [],
  "manual_qa_required": true,
  "user_acceptance_text": "见 §1.2"
}
```
