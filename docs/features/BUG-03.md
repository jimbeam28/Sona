# BUG-03 — gate 20s 超时异常路径使 _completingProvider 永久卡死：自动切歌永久失效 + unhandled async error + ghost 播放

## §0 头部元数据

```yaml
id: BUG-03
name: gate 超时后守卫复位丢失，自动切歌永久失效（_completingProvider 卡死）
priority: P1
status: active
created_at: 2026-08-16
last_updated: 2026-08-16
spec_anchored_files:
  - lib/features/player/player_provider.dart
  - lib/features/player/domain/request_gate.dart
cross_module_impacts: [PLY, TMR]
parent_feature: Player（音频播放/Player 模块）
manual_qa_required: true        # 涉真机弱网时序（慢 NAS 超时路径）
```

---

## §1 用户视角

### 1.0 原始需求（用户原话逐字记录）

来源：`docs/cr/cr-20260816-0802-player.md` B1（cr 复核已确认仍存在）：

> #### B1. gate 超时异常路径使 `_completingProvider` 永久卡死 → 自动切歌永久失效 + unhandled async error
> - 类型：BUG / 严重度：Major / 维度：并发时序 + 功能-踩坑（P1/P14）
> - 证据：
>
> `lib/features/player/player_provider.dart:306-325`（completed 监听器）：
> ```dart
> sub = player.processingStateStream.listen((state) {
>   if (state != ProcessingState.completed) return;
>   if (ref.read(_completingProvider)) return;
>   ref.read(_completingProvider.notifier).state = true;
>   ...
>   unawaited(ref.read(loadAndPlayProvider)());
> });
> ```
> `lib/features/player/player_provider.dart:341-347`（守卫复位只在非异常路径）：
> ```dart
> final r = await ref.read(playbackOrchestratorProvider).loadAndPlay(); // ← 可能 throw
> if (r.isLoaded) _startPlaybackListeners(ref);
> ref.read(_completingProvider.notifier).state = false;  // 异常路径跳过
> ```
> `lib/features/player/domain/request_gate.dart:154-167`（gate 20s 超时抛给调用方）：
> ```dart
> final result = await request.task(request.requestId).timeout(
>   const Duration(seconds: 20),
>   onTimeout: () => throw TimeoutException(...));
> ...
> } catch (e) {
>   if (isLatest(request.requestId)) { request.completer.completeError(e); }
> ```
> - 复现路径（代码推理）：
>   1. 队列 ≥2 曲；NAS 慢导致 `setAudioSource`（`playback_orchestrator.dart:191`，经 `audio_player_adapter.dart:59-75` 直传无超时）挂起 >20s（BUG-18 同类环境，P17 分层表注明 gate 20s 先于内层 30s 到期）；
>   2. 第 1 曲自然结束 → completed 事件 → 守卫置 true（:309）→ `unawaited(loadAndPlayProvider())`（:324）；
>   3. t=20s gate 超时 → `completeError(TimeoutException)` → `loadAndPlayProvider` 的 await 重抛 → `unawaited` 无 catch → **unhandled async error**，:345 复位永不执行 → 守卫卡在 true；
>   4. 该任务继续跑，setAudioSource 最终完成 → `isLatest`（:204）仍为 true → `player.play()`（:209）→ **ghost 播放**（见 B6）；
>   5. ghost 曲播完 → completed 事件 → :308 守卫拦截 → 无自动切歌、无 `pause()`（:318 也到不了）→ 播放器停在 completed（P2 死锁态），直至用户手动 skip 且**成功**才在 skipToNextProvider（:353）复位。
>   - 期望：loadAndPlay 失败/异常后自动切歌能力不受损；实际：一次慢加载超时即永久杀死自动切歌。
> - 自检答案：**该分支零覆盖**。`bug_18_stream_wait_test.dart:141-145`（S1d）在 orchestrator 层用显式 `onError` 捕获 gate TimeoutException，从未经 provider 自动切歌路径；`bug_01_test.dart:60` 把所有 load 桩成 `() async => const TrackLoadResult.loaded()`，异常路径在测试中不存在。
> - 修复建议：守卫复位放进 `try/finally`（或 loadAndPlayProvider 内 catch 吞错 + 复位）；completed 监听器对 unawaited 调用加错误处理，杜绝 unhandled error。

### 1.1 这一功能干什么（一句话）

修复自动切歌路径上的异常处理：一次慢 NAS 加载超时（gate 20s 抛 TimeoutException）不得永久杀死自动切歌能力，不得产生 unhandled async error，不得在报错后仍 ghost 播放。

### 1.2 用户期望的场景

| ID | 你看到的样子 | 期望行为 |
|----|----|----|
| U1 | 正在播放一个播放单（≥2 首），网络慢时一首播完、下一首加载超时 | 播放器停住或显示加载失败，但**此后任意一首自然播完仍能自动切到下一首**（修复前：从这次超时起自动切歌永久失效） |
| U2 | 加载超时报错的同时，刚才挂起的加载任务"姗姗来迟"完成 | 不得突然冒出声音开始播放（修复前会 ghost 播放：报错 UI 下音频开始响） |
| U3 | 上述超时场景后打开日志/错误报告 | 没有未处理的异步异常日志（unhandled error） |
| U4 | 队列只剩最后一首时它自然播完 | 正常停在播完态（暂停收尾），不因本 Bug 的守卫卡死而连暂停都不发生 |

---

## §2 已实现的功能骨架（代码锚点）

### 2.1 文件与分层

| 层 | 文件 | 行数 | 角色 |
|---|---|---|---|
| Provider | `lib/features/player/player_provider.dart` | 401 | completed 监听器（306-325）+ loadAndPlayProvider 包装（341-347）+ skip/select 同型包装（349-373） |
| Domain | `lib/features/player/domain/request_gate.dart` | 202 | SerializedRequestGate：20s 任务超时（154-167），超时以 completeError 抛给调用方 |
| Domain | `lib/features/player/domain/playback_orchestrator.dart` | 479 | loadAndPlay 任务体（141-246）：setAudioSource 无超时（191）→ 与 BUG-08 同源 |
| 测试 | `test/features/player/bug_03_repro_test.dart` | 本 spec §5.4 | 本 Bug 门禁（修复前 FAIL，已用 repro-test.sh fail 确认） |

### 2.2 关键 Provider 表

| Provider 名 | 类型 | 实现位置 | 用途 |
|---|---|---|---|
| _completingProvider | StateProvider<bool> | player_provider.dart:253 | 曲目完成处理一次性守卫（P1） |
| startProcessingListenerProvider | Provider<void Function()> | player_provider.dart:299-328 | completed 监听器唯一注册点 |
| loadAndPlayProvider | Provider<Future<TrackLoadResult> Function()> | player_provider.dart:341-347 | 自动切歌调用的编排入口（本 Bug 缺陷点） |
| skipToNextProvider / skipToPreviousProvider / selectQueueIndexProvider | 同型 | player_provider.dart:349-373 | 手动切歌入口（：353/:362/:371 的复位语句是守卫的恢复路径） |

### 2.3 状态机图

```
guard=false ──completed 事件──▶ guard=true ──loadAndPlayProvider() 成功──▶ guard=false
   ▲                                  │
   │                                  ├─ loadAndPlay() 抛异常 ──▶ guard=true 卡死（缺陷）
   │                                  └─ 手动 skip 成功（:353）──────▶ guard=false（唯一恢复路）
   └── 下一首播完再进 completed（守卫拦截 → 无自动切歌）──┐
```

---

## §3 行为规约（Given-When-Then）

### 3.1 现有行为（逆抽，缺陷态）

- **[BUG-03-S1]** completed 监听器一次性守卫：处理中重复 completed 被拦截
  ```
  Given startProcessingListenerProvider 已注册（:299-328）
  When processingStateStream 连续发出两个 completed（P1：completed 事件可能重复投递）
  Then 第一个 completed：守卫置 true（:309）→ 走 onTrackCompleted/computeNextQueue 分支
  And 第二个 completed：:308 守卫检查为 true → 直接 return，不重复处理
  ```
  Code evidence: `lib/features/player/player_provider.dart:306-325`（`:308` 守卫、`:309` 置 true、`:312/:319` 正常路径复位）。

- **[BUG-03-S2]** 守卫复位语句只在 loadAndPlay 正常返回后执行（缺陷根源）
  ```
  Given loadAndPlayProvider 被调用且 loadAndPlay() 抛异常（gate 20s TimeoutException，
      request_gate.dart:154-167 → :164 completeError）
  When 异常向上传播
  Then await 重抛 → :345 `state = false` 不执行 → 守卫永久 true
  And unawaited(:324) 无 catch → TimeoutException 成为 unhandled async error
  ```
  Code evidence: `lib/features/player/player_provider.dart:341-347`（:343 await、:345 复位）；`lib/features/player/domain/request_gate.dart:154-167`（:156-158 onTimeout throw、:164 completeError）；`player_provider.dart:324`（`unawaited(ref.read(loadAndPlayProvider)())` 无错误处理）。

- **[BUG-03-S3]** gate 超时后任务继续执行：晚到的 setAudioSource 完成后仍 `player.play()`（ghost）
  ```
  Given gate 20s 已超时抛错（调用方已收到错误），但任务体仍在跑
  When 挂起的 setAudioSource 最终完成（慢 NAS 恢复）
  Then :204 isLatest 仍为 true（无新请求）→ :209 unawaited(player.play()) 照常执行
  And 播放器在"报错/超时"状态下开始播放（ghost）
  ```
  Code evidence: `lib/features/player/domain/playback_orchestrator.dart:191`（setAudioSource 无超时）、`:204-209`（isLatest 检查 + play）；`audio_player_adapter.dart:59-75`（六动作直传无超时——与 BUG-08 同源）。

- **[BUG-03-S4]** 手动 skip 成功是守卫的唯一恢复路径（现状锚定）
  ```
  Given 守卫卡在 true（S2）
  When 用户手动点下一首且加载成功
  Then skipToNextProvider 执行完毕 → :353 守卫复位为 false
  ```
  Code evidence: `lib/features/player/player_provider.dart:349-355`（:353 复位）。

### 3.2 修复方案（status: new）

- **[BUG-03-S5]** loadAndPlayProvider 异常路径复位守卫（修改点 1） （status: new）
  ```
  Given loadAndPlayProvider 被调用
  When loadAndPlay() 抛异常（gate 超时 / 任意平台错误）或正常返回
  Then 无论成败守卫一律复位为 false（异常路径不再跳过）
  And loadAndPlay() 的异常不再从 loadAndPlayProvider 向外传播（unhandled error 杜绝）
  否定断言:
    - 任何 completed 处理中发生的异常都不得使 _completingProvider 停留在 true
    - 异常不得以 unhandled async error 形式泄漏（flutter_test 测试区内即失败）
    - 守卫复位后不得影响守卫的正常路径语义（处理中重复 completed 仍被拦截，S1 不变）
  ```
  **修改点**：`lib/features/player/player_provider.dart:341-347` — 把守卫复位放进 `try/finally`，并对异常记录日志后吞掉（catch-log 裁决：有日志才允许吞）：
  ```dart
  final Provider<Future<TrackLoadResult> Function()> loadAndPlayProvider =
      Provider<Future<TrackLoadResult> Function()>((ref) => () async {
            TrackLoadResult r;
            try {
              r = await ref.read(playbackOrchestratorProvider).loadAndPlay();
            } catch (e, st) {
              // BUG-03: gate 超时/平台错误经异常路径抛回（request_gate.dart:154-167
              // completeError）。守卫必须无条件复位（try/finally 语义），异常
              // 记日志后吞掉——completed 监听器（:324）unawaited 无错误处理，
              // 放任传播即 unhandled async error（cr-20260816-0802 B1）。
              debugLog('[Player] loadAndPlay failed: $e\n$st');
              return const TrackLoadResult.failed();
            } finally {
              ref.read(_completingProvider.notifier).state = false;
            }
            if (r.isLoaded) _startPlaybackListeners(ref);
            return r;
          });
  ```
  同型修改点（同一缺陷，同一裁决）：`skipToNextProvider`（:349-355）、`skipToPreviousProvider`（:357-364）、`selectQueueIndexProvider`（:366-373）——四个包装函数统一 try/catch + finally 复位。`debugLog` 需 import `lib/core/services/log_forwarder.dart`（domain 层同款用法：`playback_orchestrator.dart:29/412`）。
  **注意**：`TrackLoadResult.failed` 返回值语义与现有 failed 分支一致（UI 显示加载失败，player_screen.dart:192-218），不引入新状态。
  **异常吞掉与 BUG-08 的交互**：BUG-08 修复后（adapter 5s 超时）loadAndPlay 以 TimeoutException 抛出的频率降低（5s 内失败 → catch :241 → failed 正常返回），但 gate 20s 超时与其它异常路径仍然存在——本修改点独立成立。

- **[BUG-03-S6]** 手动切歌包装函数同样异常安全（修改点 2） （status: new）
  ```
  Given skipToNextProvider / skipToPreviousProvider / selectQueueIndexProvider 被调用
  When orchestrator 方法抛异常（gate 超时同源路径）
  Then 与 S5 相同：守卫复位 + 日志 + 返回 failed，不泄漏
  否定断言:
    - 手动切歌的异常不得留下守卫卡死（后续自动切歌不受损）
    - 页面内 15s UI 超时（player_screen.dart:148-176）与本层不冲突：S5 吞错后
      loadAndPlayProvider 返回 failed，_runSerializedLoad 的 15s timeout 不再触发
  ```
  Code evidence（修改点）: `lib/features/player/player_provider.dart:349-373`；参照 S5 的 try/catch/finally 模式（同一文件同一风格）。

**边界裁决（弱模型照此实现，无需二次判断）**：

| 边界情况 | 裁决 |
|---|---|
| loadAndPlay 正常返回 loaded/failed/superseded | finally 复位守卫；仅 loaded 时 _startPlaybackListeners（语义不变）；结果原样返回 |
| loadAndPlay 抛 TimeoutException（gate 20s） | catch → debugLog 记录 → 返回 failed → finally 复位 |
| loadAndPlay 抛其它异常（连接 5s 超时、平台错误等） | 同上（统一 catch） |
| completed 监听器内 onTrackCompleted 为 true（定时器到期，:310-314） | 守卫在 :312 正常复位，不经 loadAndPlayProvider —— 本修改点不触碰该分支 |
| 处理中重复 completed（P1） | 守卫 true 期间拦截语义不变（S1），finally 只负责复位 |
| 守卫复位在 finally 与正常路径双写 | 幂等（StateProvider.state=false 重复赋值无副作用）——可保留 :345 原行，也可删除由 finally 统一承担；二者择一即可，不得双路径造成语义差异 |

---

## §4 不变量

- **[BUG-03-INV1]** `_completingProvider` 守卫是"处理中一次性"标志：任何 completed 处理路径（含异常路径）结束后必须回到 false；true 的持续时间不超过单次 completed 处理
  证据：`lib/features/player/player_provider.dart:309`（置 true）+ 修复后 try/finally 复位（S5 修改点）；对照 P1 踩坑库（"任何 completed 处理必须带一次性守卫标志，处理完复位"）。

- **[BUG-03-INV2]** 自动切歌失败（异常或 failed）不得杀死后续自动切歌能力：一次 completed 处理结束后，后续 completed 事件必须仍走完整处理链
  证据：`player_provider.dart:306-325` 监听器语义（守卫为 false 即处理）+ 修复后 S5/S6 的 finally 复位。

- **[BUG-03-INV3]** 播放加载路径的异常不得以 unhandled async error 泄漏（fire-and-forget 面：completed 监听器 :324 的 unawaited）
  证据：`player_provider.dart:324`（unawaited）+ S5 修改点 catch；参照 SCHEMA.md §5 错误处理纪律与 BUG-19 同型裁决（saveProgress :407-413 的 catchError 先例）。

---

## §5 测试规约

### 5.1 现有测试清单

| 测试文件 | 覆盖的 Scenario / INV | 备注 |
|---|---|---|
| test/features/player/bug_18_stream_wait_test.dart:141-145 | BUG-03-S2 的 orchestrator 层变体（S1d 显式 onError 捕获 gate 超时） | 只测到 orchestrator 层，未走 provider 自动切歌路径（cr 自检答案） |
| test/features/player/bug_bug19_repro_test.dart | BUG-03-INV3 的 saveProgress 面 | 同型裁决（fire-and-forget 不泄漏） |
| test/features/player/bug_03_repro_test.dart | BUG-03-S5 / BUG-03-S6 / BUG-03-INV1 / INV2 / INV3 | 本 Bug 门禁（修复前 FAIL，已用 repro-test.sh fail 确认） |

### 5.2 测试 ID 派生清单（dev-exe 派发测试 Agent 用）

```
BUG-03-S1 … S6        # Scenario（S1~S4 现状锚定，S5/S6 修复目标）
BUG-03-INV1 … INV3    # 不变量
BUG-03-MAN1 …         # 手动 QA 步骤（见 §8）
```

dev-exe 要求：S5/S6/INV1~3 由 §5.4 门禁测试覆盖；S1~S4 由门禁测试顺带锚定（S1 = 门禁的前置断言语义，S3 = ghost 面由 BUG-08 门禁锚定，S4 = 既有 skip 测试锚定）。

### 5.3 测试覆盖盲点（dev-plan 写本文档时识别）

| 未覆盖 ID | 现状 | 应补偿方式 |
|---|---|---|
| BUG-03-S3 ghost 播放面 | 本门禁只锚定守卫复位 + unhandled error；ghost 断言在 BUG-08 门禁（bug_08_repro_test.dart T2） | BUG-08 spec 覆盖 |
| BUG-03-MAN1 | 慢 NAS 真机时序 | 进 mqa-backlog（§8） |

### 5.4 测试文件位置（spec-scan --gate 硬校验）

| 测试文件 | 覆盖 ID | 说明 |
|---|---|---|
| test/features/player/bug_03_repro_test.dart | BUG-03-S5、BUG-03-S6、BUG-03-INV1、BUG-03-INV2、BUG-03-INV3 | 门禁：dev-exe 修复后必须 PASS（repro-test.sh pass） |

---

## §6 算法样例

本 Bug 不涉纯函数算法，跳过。

---

## §7 跨模块影响

`bash cross-imports.sh impact lib/features/player/player_provider.dart lib/features/player/domain/request_gate.dart`（2026-08-16）→ 引用方：

| 其它 feature | 影响点 | 影响条件 | 需要补的回归断言 |
|---|---|---|---|
| TMR（timer_provider.dart:228 onTrackCompletedProvider） | completed 监听器 :310 消费定时器到期回调 | 修改只在 loadAndPlayProvider 异常面，onTrackCompleted 分支（:310-314）不动 | timer 既有测试全绿（timer_provider / timer_* 测试） |
| Player（player_screen.dart:168-176） | _runSerializedLoad 15s UI 超时与 S5 catch 的交互 | S5 吞错返回 failed → UI 走 failed 分支（非超时分支） | ply_01/ply_14 等页面加载测试全绿；bug_03_repro_test.dart PASS |
| Player（skipToNext/skipToPrevious/selectQueueIndex 包装 :349-373） | S6 同型修改 | 四个包装函数行为对齐 | bug_03_repro_test.dart（S6 面）+ 既有 skip 测试（ply_05/ref_14 等）全绿 |
| Player（playback_orchestrator.dart） | 异常语义不变（gate 仍 completeError） | 本 Bug 只在 provider 包装层处理，orchestrator 不动 | bug_18_stream_wait_test.dart 全绿（orchestrator 层超时语义不变） |
| BUG-08（adapter 5s 超时） | 修复后 loadAndPlay 多数平台错误 5s 内 failed 返回，gate 20s 超时触发率下降 | 独立成立，两者不互斥 | bug_08_repro_test.dart PASS |

---

## §8 平台特性与手动 QA

设计前已逐条核对 `docs/dev/platform-pitfalls.md`：本 Bug 即 **P1**（completed 一次性守卫——守卫复位必须覆盖异常路径）与 **P14**（加载并发串行化——异常路径不得破坏门后串行语义）的直接处置；**P17** 分层表（gate 20s 先于内层 30s 到期）是复现路径的时序前提；**P4**（平台调用挂起）与 BUG-08 共同处置。

**真机风险列**（fake 测不到、只有真机会出问题的）：

| 风险 | 近似测试方案 | 测不了 → 进 mqa-backlog |
|---|---|---|
| 慢 NAS 下自动切歌加载超时后，后续曲目播完不再自动切歌（本次修复的主症状） | bug_03_repro_test.dart（ProviderContainer + FakeAsync 21s 超时后二次 completed → pause） | BUG-03-MAN1：真机慢速 NAS（如限速 Wi-Fi）播放 ≥2 曲队列，第 1 曲播完让下一首加载超时，再手动重试加载第 2 首，播完后必须自动切到第 3 首 |
| 超时报错后 ghost 播放（报错 UI 下音频突然响起） | bug_08_repro_test.dart T2（晚到 setAudioSource 不得触发 play） | BUG-03-MAN2：同上环境，观察超时提示出现后是否有音频突然播放；`adb logcat` 无 PlayerException/TimeoutException 崩溃栈 |
| unhandled async error 的 logcat 痕迹 | bug_03_repro_test.dart（flutter_test 区内 unhandled error 即失败） | BUG-03-MAN3：慢 NAS 场景下 `adb logcat` 无 Unhandled exception / TimeoutException 栈 |

涉及真机弱网时序 → `manual_qa_required = true`。

---

## §9 dev-status.json 条目对照

```json
"BUG-03": {
  "spec_file": "docs/features/BUG-03.md",
  "spec_anchored_files": [
    "lib/features/player/player_provider.dart",
    "lib/features/player/domain/request_gate.dart"
  ],
  "scenarios": ["BUG-03-S1", "BUG-03-S2", "BUG-03-S3", "BUG-03-S4", "BUG-03-S5", "BUG-03-S6"],
  "invariants": ["BUG-03-INV1", "BUG-03-INV2", "BUG-03-INV3"],
  "algorithms": [],
  "manual_qa_required": true,
  "user_acceptance_text": "见 §1.2"
}
```
