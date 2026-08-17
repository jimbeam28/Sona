# BUG-05 — loadAndPlay 静默 catch 违反 catch-log 全局裁决：失败无日志，排障靠猜

## §0 头部元数据

```yaml
id: BUG-05
name: loadAndPlay 静默 catch 无日志（catch-log 裁决违规）
priority: P2
status: active
created_at: 2026-08-16
last_updated: 2026-08-16
spec_anchored_files:
  - lib/features/player/domain/playback_orchestrator.dart
cross_module_impacts: [PLY]
parent_feature: Player（音频播放/Player 模块）
manual_qa_required: false        # 纯日志面，flutter test 可完全验证
```

---

## §1 用户视角

### 1.0 原始需求（用户原话逐字记录）

来源：`docs/cr/cr-20260816-0802-player.md` B3（cr 复核已确认仍存在）：

> #### B3. loadAndPlay 静默 catch 违反 catch-log 全局裁决
> - 类型：BUG / 严重度：Minor / 维度：正确性（可观测性）
> - 证据：
>
> `lib/features/player/domain/playback_orchestrator.dart:241-243`：
> ```dart
> } catch (e) {
>   return const TrackLoadResult.failed();
> }
> ```
> 该 catch 吞掉 loadAndPlay 任务内全部异常（getActiveConnection 5s 超时、setAudioSource/seek/setSpeed 平台错误），无 debugLog/LogBuffer。SCHEMA.md §5 裁决：「任何 catch / catchError 必须先留日志才允许吞掉异常」，豁免清单仅含 `audio_handler.dart` 六方法（BUG-17）与 connection delete（BUG-24），本处不在豁免内。同文件 `saveProgress`（:407-413）已示范正确写法。
> - 复现路径：错误密码/断网/5s 连接超时 → loadAndPlay 返回 failed → 运行日志无任何记录，排障只能靠 UI 文案。
> - 自检答案：**分支零覆盖**——现有测试（ref_14_test 的 failed 路径）只断言返回 TrackLoadResult.failed，不检查日志输出（LogBuffer 无断言）。
> - 修复建议：catch 内先 `debugLog`（脱敏，不落凭证）再返回 failed。

### 1.1 这一功能干什么（一句话）

给 loadAndPlay 的失败 catch 补日志：任何被吞掉的加载异常必须留痕（经 debugLog 进 LogBuffer/测试捕获），且日志不含凭证。

### 1.2 用户期望的场景

| ID | 你看到的样子 | 期望行为 |
|----|----|----|
| U1 | 密码错误或断网时点播放，加载失败 | 播放器页面显示失败文案（不变）；开发者在"日志"页（Debug 模式）能看到失败原因，而不是一无所获 |
| U2 | 上述失败发生在慢 NAS/超时场景 | 日志页有带 [Player] 前缀的失败记录，可据此排障 |
| U3 | 日志记录失败原因 | 日志里绝不出现密码等敏感信息 |

---

## §2 已实现的功能骨架（代码锚点）

### 2.1 文件与分层

| 层 | 文件 | 行数 | 角色 |
|---|---|---|---|
| Domain | `lib/features/player/domain/playback_orchestrator.dart` | 479 | loadAndPlay 任务体（141-246）：catch（241-243）吞异常无日志（缺陷点）；saveProgress（407-413）正确示范 |
| Core | `lib/core/services/log_forwarder.dart` | 17 | debugLog（14）：domain 层唯一合法日志出口 |
| UI | `lib/features/settings/log_viewer_screen.dart` | — | LogBuffer 消费 debugPrint（Debug 模式日志页） |
| 测试 | `test/features/player/bug_05_repro_test.dart` | 本 spec §5.4 | 本 Bug 门禁（修复前 FAIL，已用 repro-test.sh fail 确认） |

### 2.2 关键 Provider 表

本 Bug 不涉及 provider（orchestrator 纯 domain 层）。

### 2.3 状态机图

本 Bug 不涉状态机，跳过。

---

## §3 行为规约（Given-When-Then）

### 3.1 现有行为（逆抽，缺陷态）

- **[BUG-05-S1]** loadAndPlay 任务内异常一律静默吞掉（缺陷根源）
  ```
  Given loadAndPlay 任务体（:150-243）内任一步抛异常
        （getActiveConnection 5s 超时 / readPassword 失败 / setAudioSource /
        seek / setSpeed 平台错误）
  When catch (e) 执行（:241-243）
  Then return const TrackLoadResult.failed()
  And 不写任何日志（无 debugLog/LogBuffer 调用）
  ```
  Code evidence: `lib/features/player/domain/playback_orchestrator.dart:241-243`（`} catch (e) { return const TrackLoadResult.failed(); }`）。

- **[BUG-05-S2]** 同文件 saveProgress 已示范 catch-log 正确写法（修复参照）
  ```
  Given saveProgress 的 upsertProgress 失败（BUG-19）
  When catchError 执行（:407-413）
  Then debugLog('[Player] saveProgress failed: $e') 记录后吞掉
  ```
  Code evidence: `lib/features/player/domain/playback_orchestrator.dart:407-413`。

### 3.2 修复方案（status: new）

- **[BUG-05-S3]** catch 内先记日志再返回 failed（修改点 1） （status: new）
  ```
  Given loadAndPlay 任务内任一步抛异常 e
  When catch (e) 执行
  Then debugLog 记录失败（含异常文本，前缀 [Player]）
  And return const TrackLoadResult.failed()（返回值语义不变）
  否定断言:
    - 不得静默吞掉（无日志即违反 catch-log 裁决，门禁测试断言日志非空）
    - 日志不得含密码等凭证（secret-logs 门禁；异常文本含 URL 时不得带
      userinfo——本任务内异常对象为 TimeoutException/平台异常，不含凭证，
      防御性脱敏见边界裁决）
    - 正常路径（loaded）不得产生额外日志（不加无谓噪声）
  ```
  **修改点**：`lib/features/player/domain/playback_orchestrator.dart:241-243`：
  ```dart
  } catch (e) {
    // BUG-05（cr-20260816-0802 B3）：catch-log 全局裁决（SCHEMA.md §5）——
    // 任何 catch 必须先留日志才允许吞掉异常。对照 saveProgress 正确写法
    // （:407-413）。异常文本不含凭证（连接密码只经 PasswordReader 传递，
    // 不进任务体异常）；URL 含 userinfo 时按 secret-logs 门禁脱敏。
    debugLog('[Player] loadAndPlay failed: $e');
    return const TrackLoadResult.failed();
  }
  ```
  `debugLog` 已在文件头 import（`lib/features/player/domain/playback_orchestrator.dart:29`，saveProgress 在用），无需新 import。
  **脱敏裁决**：getActiveConnection/password/setAudioSource 路径产生的异常对象不包含密码明文（密码字符串只存在于局部变量，见 :168-172）；URL 类异常若含 userinfo（极罕见），按 SCHEMA.md §5「日志不得含凭证」以 `$e` 直打的风险接受与否——裁决：异常对象为平台/超时类型，不含 URL 字面量，直接 `$e` 安全；若 dev-exe 实现时发现异常文本含 URL，参照 `redactUrlForLog`（audio_handler.dart 相关用法）脱敏后再记。

**边界裁决（弱模型照此实现，无需二次判断）**：

| 边界情况 | 裁决 |
|---|---|
| getActiveConnection 5s 超时 | 走 catch → 日志 `[Player] loadAndPlay failed: TimeoutException...` → failed |
| readPassword 抛异常 | 同上（门禁测试即此路径） |
| setAudioSource/seek/setSpeed 平台错误 | 同上（BUG-08 修复后 adapter 5s TimeoutException 也走此日志） |
| gate 20s 任务超时（BUG-03） | 不经过本 catch（超时在 gate 层 completeError，provider 包装层处理，见 BUG-03-S5）；本修改点不触碰 |
| 正常 loaded 路径 | 无日志新增（否定断言） |
| 日志脱敏 | 异常文本无凭证，`$e` 直打；如含 URL userinfo 则脱敏（裁决如上） |

---

## §4 不变量

- **[BUG-05-INV1]** loadAndPlay 的失败 catch 永远先日志后吞错（catch-log 裁决在本函数的落点）
  证据：修复后 `playback_orchestrator.dart:241-243`；全局裁决 SCHEMA.md §5（豁免清单不含本处）。

- **[BUG-05-INV2]** loadAndPlay 返回 failed 时调用方语义不变（failed 结果与修复前一致，UI 失败文案不变）
  证据：`player_screen.dart:192-218`（failed → classifyLoadFailure → 文案）；修复不改返回值。

---

## §5 测试规约

### 5.1 现有测试清单

| 测试文件 | 覆盖的 Scenario / INV | 备注 |
|---|---|---|
| test/features/player/ref_14_test.dart | BUG-05-S1 的返回值面（failed 路径） | 只断言返回 failed，不检查日志（cr 自检答案） |
| test/features/player/bug_05_repro_test.dart | BUG-05-S3 / INV1 / INV2 | 本 Bug 门禁（修复前 FAIL，已用 repro-test.sh fail 确认） |

### 5.2 测试 ID 派生清单（dev-exe 派发测试 Agent 用）

```
BUG-05-S1 … S3        # Scenario（S1/S2 现状锚定，S3 修复目标）
BUG-05-INV1 … INV2    # 不变量
```

dev-exe 要求：S3/INV1/INV2 由 §5.4 门禁测试覆盖；S1/S2 由门禁测试顺带锚定（S1 = 门禁的失败注入路径，S2 = saveProgress 既有测试）。

### 5.3 测试覆盖盲点（dev-plan 写本文档时识别）

| 未覆盖 ID | 现状 | 应补偿方式 |
|---|---|---|
| 日志页（LogBuffer）实际可见性 | 门禁断言 debugPrint 捕获；LogBuffer 为既有机制（log_viewer） | 无需补偿（debugLog → debugPrint → LogBuffer 链路已有测试） |

### 5.4 测试文件位置（spec-scan --gate 硬校验）

| 测试文件 | 覆盖 ID | 说明 |
|---|---|---|
| test/features/player/bug_05_repro_test.dart | BUG-05-S3、BUG-05-INV1、BUG-05-INV2 | 门禁：dev-exe 修复后必须 PASS（repro-test.sh pass） |

---

## §6 算法样例

本 Bug 不涉纯函数算法，跳过。

---

## §7 跨模块影响

`bash cross-imports.sh impact lib/features/player/domain/playback_orchestrator.dart`（2026-08-16）→ 引用方：

| 其它 feature | 影响点 | 影响条件 | 需要补的回归断言 |
|---|---|---|---|
| Player（player_provider.dart:341-373 四个包装） | loadAndPlay 返回值语义不变（failed） | 仅日志面变化 | 既有 player 测试全绿；bug_05_repro_test.dart PASS |
| Player（player_screen.dart:192-218 失败文案） | failed 分支不变 | 无 | ply_01~14 全绿 |
| secret-logs 门禁 | 新增日志不得含凭证 | debugLog 文本含异常对象 | `cross-imports.sh secret-logs` exit 0（dev-exe cov-gate 已含） |
| BUG-08（adapter 5s 超时） | 平台错误改走本 catch 日志 | 独立成立 | bug_08_repro_test.dart PASS |

---

## §8 平台特性与手动 QA

设计前已逐条核对 `docs/dev/platform-pitfalls.md`：本 Bug 不触及任何平台特性条目（纯日志可观测性修复）；P17 分层表的 gate 超时路径（BUG-03 管辖）不经过本 catch。

**真机风险列**：

| 风险 | 近似测试方案 | 测不了 → 进 mqa-backlog |
|---|---|---|
| 无（日志面全部可在 flutter test 验证） | bug_05_repro_test.dart（debugPrint 捕获） | — |

本功能不涉及平台原生特性，全部可在 `flutter test` 中验证 → `manual_qa_required = false`。

---

## §9 dev-status.json 条目对照

```json
"BUG-05": {
  "spec_file": "docs/features/BUG-05.md",
  "spec_anchored_files": [
    "lib/features/player/domain/playback_orchestrator.dart"
  ],
  "scenarios": ["BUG-05-S1", "BUG-05-S2", "BUG-05-S3"],
  "invariants": ["BUG-05-INV1", "BUG-05-INV2"],
  "algorithms": [],
  "manual_qa_required": false,
  "user_acceptance_text": "见 §1.2"
}
```
