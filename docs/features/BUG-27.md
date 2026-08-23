# BUG-27 — restoreStartupProgress 写回/seek 无时效复核，竞态窗口覆盖用户选曲

```yaml
id: BUG-27
name: 启动进度恢复在 latestPlayed await 间隙不复核队列时效，可覆盖用户新选队列并错位 seek
priority: P3
status: active
created_at: 2026-08-23
last_updated: 2026-08-23
spec_anchored_files:
  - lib/features/player/player_provider.dart
cross_module_impacts:
  - lib/features/browser/browser_provider.dart
parent_feature: Player
manual_qa_required: false
```

---

## §1 用户视角

### 1.0 原始需求（来源逐字记录）

> 来源：docs/cr/cr-20260823-1421.md F5（走查发现，复核确认仍存在，2026-08-23 分流）。
>
> "restoreStartupProgressProvider（player_provider.dart:216-236）在读 currentPlayQueueProvider（:218）与写回/seek（:229-234）之间横跨 latestPlayedProgressProvider.future 异步间隙，且写回前不复核 provider 当前值是否仍是读时的 q。BUG-06（晚到即弃）已在 preloadAudioSource 侧加 shouldAbandon 双闸，本启动恢复路径是同族 hazard 的未设防兄弟路径。"
> 自检答案："bug_06 系列只锚定 preload 的 abandon 行为，restoreStartupProgress 与用户并发操作无用例 → 分支零覆盖。"
> 复核裁决（2026-08-23）：FRAGILE/Minor → dev-plan Bug 流程。

### 1.1 一句话

App 刚启动时的"恢复上次播放位置"动作，如果用户已经在点歌了，必须立刻让位——不许把用户刚选的歌换成昨天的队列、更不许把位置拨乱。

### 1.2 用户期望的场景

| ID | 你看到的样子 | 期望行为 |
|----|----|----|
| U1 | 启动后立即点了一首歌 | 播的就是点的这首，进度从头开始 |
| U2 | 启动后没人操作，恢复流程正常走完 | 上次队列与进度照常恢复（既有行为不变） |

---

## §2 已实现骨架（逆抽锚点）

| 层 | 文件 | 角色 |
|---|---|---|
| Provider | lib/features/player/player_provider.dart:216-236 | restoreStartupProgressProvider：:217 先等 restoreQueueFromPrefs；:218 读 q；:220 await latestPlayedProgressProvider（**竞态窗口**）；:229-230 `if (r != null && r != q)` 写回派生值 r；:231-234 audioSource 非空则 seek（缺陷点：写回与 seek 前无时效复核） |
| 对照组 | lib/core/services/audio_source_builder.dart:149-179 | BUG-06 晚到即弃双闸（shouldAbandon + _sourceStillIssued）——同族 hazard 已设防的先例 |
| 上游 | lib/features/browser/browser_provider.dart:191-266 | restoreQueueFromPrefsProvider：恢复持久化队列至 currentPlayQueueProvider（含 preload abandon 守卫） |
| 门禁测试 | test/features/player/bug_bug27_restore_race_test.dart | 可控 Completer DAO 制造窗口，修复前 FAIL（repro-test.sh fail 确认 2026-08-23） |

---

## §3 行为规约

### 3.1 现状锚定（逆抽）

- **[BUG-27-S0]** 正常恢复语义：同连接同曲目时把 sanitizeResumePosition 后的进度注入队列 startPositionMs
  Code evidence: `lib/features/player/player_provider.dart:196-214`（applyLatestProgressToQueue）
- **[BUG-27-S0b]** 用户操作发生在 :217 restoreQueueFromPrefs.await 阶段时天然安全：:218 在其后重读 provider
  Code evidence: 同上 :217-218（本修复不得破坏该安全序）

### 3.2 修复目标

- **[BUG-27-S1]** 写回与 seek 前必须确认队列未被并发修改（`status: new`）
  ```
  Given 恢复流程已读取 q 并停在 latestPlayedProgressProvider.future
  When 进度返回且 r != q（正常命中分支）
  Then 仅当 currentPlayQueueProvider 当前值 identical(q) 时才写回 r 并 seek
       否则整个写回+seek 让位（abandon），用户当前队列原样保留
  否定断言:
    - abandon 分支不产生任何 provider 写入
    - abandon 分支不对 player 调用 seek
    - 无并发修改时（U2 场景）恢复行为与现状逐字节一致（S0 回归）
  ```
  Code evidence: 修改点 `lib/features/player/player_provider.dart:229-234`

边界裁决表：

| 场景 | 裁决 |
|---|---|
| r == q（进度未命中当前曲/跨连接） | 现状不变：无写入无 seek |
| identical(当前值, q) 且 r != q | 现状不变：写回 + 条件 seek |
| 当前值已被替换（任何来源） | 新增：abandon——不写回、不 seek |
| pl.audioSource == null | 现状不变：只写回不 seek |

---

## §4 不变量

- **[BUG-27-INV1]** 对共享播放器状态（currentPlayQueueProvider / AudioPlayer）的启动期后台写动作，落盘前必须校验目标仍是自己读到的快照（晚到即弃纪律，BUG-06 同款）
  证据：player_provider.dart:229-234（修改点）对照 audio_source_builder.dart:149-179（先例）

---

## §5 测试规约

### 5.1 现有测试清单

| 测试文件 | 覆盖 | 备注 |
|---|---|---|
| test/features/browser/bug_06_repro_test.dart 等 | preload abandon 双闸 | 全绿即可（对照组不受影响） |
| test/features/home/onboarding_test.dart | 启动路由链 | 全绿即可 |

### 5.2 测试 ID 派生清单

```
BUG-27-S1, BUG-27-INV1
```

### 5.3 测试覆盖盲点

真实 sqflite 时延分布不可测——单测以可控 Completer 确定性展开窗口；真机上窗口为一次 DB 读量级。

### 5.4 门禁测试文件（spec-scan --gate 硬校验）

| 测试文件 | 覆盖 ID | 说明 |
|---|---|---|
| test/features/player/bug_bug27_restore_race_test.dart | BUG-27-S1 | 修复前 FAIL 已由 repro-test.sh fail 确认（2026-08-23）；修复后必须 PASS |

---

## §6 算法样例

不涉及纯函数算法，跳过。

---

## §7 跨模块影响

impact 反查（2026-08-23）：player_provider ← main.dart（override）、app/onboarding.dart（触发点）、shared/di/providers.dart（re-export）、player 各 widgets。

| 其它模块 | 影响点 | 影响条件 | 回归断言要求 |
|---|---|---|---|
| app/onboarding | postFrame 触发 restoreStartupProgress | 无并发修改时行为零变更 | onboarding_test 全绿 |
| browser | restoreQueueFromPrefs 上游 | 零变更 | bug_06 系列全绿 |

**修改点（弱模型照单执行）**：
1. `lib/features/player/player_provider.dart` restoreStartupProgressProvider 写回段（现 :229-235）改为：
   ```dart
   if (r != null && r != q) {
     // BUG-27: 晚到即弃——窗口内队列已被用户/其它入口改写时让位
     // （audio_source_builder.dart BUG-06 同款纪律）。
     if (!identical(ref.read(currentPlayQueueProvider), q)) {
       return;
     }
     ref.read(currentPlayQueueProvider.notifier).state = r;
     final pl = ref.read(audioPlayerProvider);
     if (pl.audioSource != null) {
       await pl.seek(Duration(milliseconds: r.startPositionMs ?? 0));
     }
   }
   ```
   即在写回语句前插入 identical 复核守卫。
2. 全量回归：cov-gate --skip-test + flutter test 全绿（重点 bug_06 系列 / onboarding_test）。

---

## §8 平台特性与手动 QA

核对踩坑库：P14 相关（共享加载态并发危害类）；P11 不触及（写动作不在 build 期）。真机风险：无新增平台面（复用既有 provider/player API）。manual_qa_required=false。

---

## §9 dev-status.json 条目对照

```json
"BUG-27": {
  "spec_file": "docs/features/BUG-27.md",
  "spec_anchored_files": ["lib/features/player/player_provider.dart"],
  "scenarios": ["BUG-27-S1"],
  "invariants": ["BUG-27-INV1"],
  "algorithms": [],
  "manual_qa_required": false,
  "user_acceptance_text": "见 §1.2"
}
```
