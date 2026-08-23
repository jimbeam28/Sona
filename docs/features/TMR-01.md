# 功能详细设计文档：TMR-01 定时停止音量淡出

```yaml
id: TMR-01
name: 定时停止音量淡出（duration 模式到期前 10 秒渐弱）
priority: P1
status: active
created_at: 2026-08-23
last_updated: 2026-08-23
spec_anchored_files:
  - lib/features/timer/domain/timer_service.dart
  - lib/features/timer/timer_provider.dart
  - lib/features/player/player_provider.dart
  - lib/core/contracts/audio_player_contract.dart
  - lib/core/services/audio_player_adapter.dart
  - lib/features/home/home_screen.dart
  - lib/features/player/player_screen.dart
cross_module_impacts: [PLY, PRG]
manual_qa_required: true
```

---

## §1 用户视角

### 1.0 原始需求（用户原话逐字记录）

> 采纳 A 的 1~4（A3 = 定时器增强：到期音量渐弱）。访谈裁决记录（2026-08-23）：
> "**范围**：仅 duration 模式淡出。afterCurrent 在歌曲自然结束时才触发，音频本身已到尾部，淡出无意义。"
> "**参数**：固定 10s 线性渐弱，不做设置项。到期前 10s 开始降音量，到 0 → pause → 立即恢复音量 1.0。"
> "**打断恢复**：淡出窗口内发生任何事——取消定时器/用户手动切歌——音量必须恢复。单一写权，P14 序列化处置。"（实现裁决收敛为"下一 tick 恢复"，见 §3 S4 依据）

### 1.1 这一功能干什么（一句话）

设定"X 分钟后停止"时，最后 10 秒音量平滑减弱到零再暂停，而不是突然静音把人吵醒。

### 1.2 用户期望的场景

| ID | 你看到的样子 | 期望行为 |
|----|----|----|
| U1 | 设了 30 分钟定时听书，还剩 11 分钟以上 | 音量完全正常，感觉不到定时存在 |
| U2 | 倒计时进入最后 10 秒 | 音量开始一点一点变小，每秒降一档，很平缓 |
| U3 | 倒计时归零 | 已经几乎无声地停住，随后音量悄悄回到正常（下次播放不受影响），和现在一样提示已停止 |
| U4 | 最后 10 秒内反悔，取消了定时 | 最迟 1 秒内音量回到正常 |
| U5 | 最后 10 秒内改了主意，重新设了个更长的定时 | 音量回到正常，新定时照常走 |
| U6 | 用的是"播完当前曲停止" | 和以前完全一样，不做淡出 |
| U7 | 淡出过程中暂停了播放又继续听 | 定时器照旧倒数（现状语义不变），音量按剩余时间继续走 |

---

## §2 已实现的功能骨架（代码锚点）

### 2.1 文件与分层

| 层 | 文件 | 关键位置 | 角色 |
|---|---|---|---|
| Domain | lib/features/timer/domain/timer_service.dart | :17-26 TimerMode 枚举；:62-71 remainingTime getter（paused 读 remainingMs，过期返回 zero）；:250-258 checkExpired（清状态+返回信号）；:289 afterCurrentLabel | 定时器纯状态机 |
| Provider | lib/features/timer/timer_provider.dart | :30-31 timerServiceProvider；:38-86 TimerStateNotifier（startDuration/startAfterCurrent/cancel/checkExpired/onTrackCompleted 包装）；:89-90 timerStateProvider；:140-171 remainingTimeProvider（秒级流，UI 用）；:193-211 三个动作 provider；:218-222 checkTimerExpiryProvider | 状态通知与动作 |
| Player 接线 | lib/features/player/player_provider.dart | :320 audioPlayerProvider 消费先例；:326-330 onTrackCompleted→pause（afterCurrent 到期路径，本功能不改）；:271-303 _startAutoSaveProvider 闭包持句柄模式 | 本功能新增 tick 编排放这里 |
| Contract | lib/core/contracts/audio_player_contract.dart | :22-78 IAudioPlayer 全量方法清单——**无 setVolume** | 需扩契约 |
| Adapter | lib/core/services/audio_player_adapter.dart | :16 class AudioPlayerAdapter implements IAudioPlayer；:57-78 Actions 区（setSpeed 先例 :75） | 需加透传 |
| UI 驱动 | lib/features/home/home_screen.dart | :51-56 initState 秒级 Timer.periodic → checkTimerExpiry→pause；:60-67 lifecycle resumed 同款 | 驱动点①② |
| UI 驱动 | lib/features/player/player_screen.dart | :68-73 秒级 Timer.periodic 同款；:77-83 lifecycle resumed 同款 | 驱动点③④ |
| Bridge | lib/shared/di/providers.dart | :152-176 timer 段 export 清单（新增符号在此登记）；player 段 export 在同文件其它区段 | 跨 feature 只能经此 |

### 2.2 现有行为逆抽

- **到期判定是"拉"模型**：TimerService 自身无后台线程；由两个常驻页面的秒级 `Timer.periodic` 各自调 `checkTimerExpiryProvider()`（home_screen.dart:51-56 / player_screen.dart:68-73），返回 true 时调用方自行 `player.pause()`。两屏同时存活时每秒会各跑一次（幂等：第二次 checkExpired 返回 false）。
- **afterCurrent 到期路径独立**：不走路秒 tick，走 processingState==completed 监听（player_provider.dart:322-330），onTrackCompleted 返回 true 则 pause。本功能完全不触碰该路径。
- **音量现状**：全项目（lib/）对 setVolume/volume 零引用（2026-08-23 grep 实证）；just_audio 的 AudioPlayer 有公开 `Future<void> setVolume(double volume)`（pub.dev just_audio 0.9.40 API 文档，长期稳定接口），契约层尚未暴露。
- **定时器与播放解耦**：启动新队列/切歌不清除定时器；暂停播放也不暂停定时器（timer_service 无任何 player 依赖，:113-120 注释明示 caller 驱动）。TMR-01-U7 即锚定此现状。
- **paused 模式的 remainingTime 冻结**：timer_service.dart:64-66 直接返回保存的 remainingMs，不随墙钟走。

---

## §3 行为规约（Given-When-Then）

### 3.1 契约层扩展

- **[TMR-01-S1] IAudioPlayer 新增 setVolume**
  ```
  Given IAudioPlayer 抽象接口（audio_player_contract.dart:22）
  When 在 Actions 区追加 Future<void> setVolume(double volume);
  Then AudioPlayerAdapter 实现为 `Future<void> setVolume(double volume) => _impl.setVolume(volume);`
  And test/helpers/mock_audio_player.dart 基于 mockito Mock 动态分发，无需显式声明；
      但所有触发淡出路径的测试必须显式 stub（否则 MissingStubError，BUG-27 勘察先例）
  否定断言:
    - 契约中既有方法签名一个不改（diff 仅追加一行抽象方法 + 一行实现）
    - audio_handler.dart 不感知本次改动（它不经 IAudioPlayer.setVolume）
  ```
  Code evidence: contract :74-75 setSpeed 同款签名风格；adapter :57-78 Actions 区结构

### 3.2 纯函数：fade_policy

新增 `lib/features/timer/domain/fade_policy.dart`（纯 Dart，零 Flutter 依赖，Domain 层纪律同 timer_service.dart 头注释 :1-14）：

```dart
const Duration kTimerFadeWindow = Duration(seconds: 10);

/// duration 模式剩余时间 → 目标音量。
/// 返回 1.0 表示窗口外（不需要写）；[0,1) 表示淡出中应写入的音量。
double fadeVolumeForRemaining(Duration? remaining) {
  if (remaining == null) return 1.0;
  if (remaining <= Duration.zero) return 0.0;
  final windowMs = kTimerFadeWindow.inMilliseconds;
  final ms = remaining.inMilliseconds;
  if (ms >= windowMs) return 1.0;
  return ms / windowMs;
}
```

- **[TMR-01-S2] 淡出曲线**
  ```
  Given duration 模式定时器活跃
  When 以不同 remainingTime 调 fadeVolumeForRemaining
  Then 按 §6 ALG1 表输出
  否定断言:
    - 输出永远在 [0.0, 1.0] 区间（负数/大于 1 不可能出现）
    - remaining > 10s 与 remaining == null 同样返回恰好 1.0
  ```

### 3.3 编排：合并 tick provider

新增于 **player_provider.dart**（放 player 而非 timer 的原因：需要同时触达 timerStateProvider 与 audioPlayerProvider 两个跨 feature 符号，player_provider 已通过 shared/di 桥接两者——:326 onTrackCompleted 先例；timer 反向 import player 会成环）：

```dart
final timerTickWithFadeProvider = Provider<Future<void> Function()>((ref) {
  var lastWritten = 1.0; // 闭包持有"最后一次写入的淡出音量"，避免冗余平台调用
  return () async {
    final st = ref.read(timerStateProvider);
    final active = st != null && st.mode == TimerMode.duration;
    final target = active
        ? fadeVolumeForRemaining(st.remainingTime)
        : 1.0;
    if (target != lastWritten) {
      await ref.read(audioPlayerProvider).setVolume(target);
      lastWritten = target;
    }
    if (!active) return;
    final expired = ref.read(timerStateProvider.notifier).checkExpired();
    if (expired) {
      await ref.read(audioPlayerProvider).pause();
      if (lastWritten < 1.0) {
        await ref.read(audioPlayerProvider).setVolume(1.0);
        lastWritten = 1.0;
      }
    }
  };
});
```

- **[TMR-01-S3] 到期单 tick 完成"静默停止"**
  ```
  Given duration 定时器 remaining <= 0 且正在播放（音量已被前序 tick 降到接近 0）
  When 任一驱动点执行 timerTickWithFadeProvider()
  Then 依次发生：setVolume(0.0) → checkExpired()==true 清状态 → pause() → setVolume(1.0)
  And 之后任何 tick 不再产生 setVolume 调用（lastWritten==1.0 且 !active）
  否定断言:
    - 不调用 player.stop()（保持 completed 态现有处理语义，P2）
    - 不触碰 currentPlayQueueProvider / 进度保存（进度由既有 pause 自动保存链负责，
      player_provider.dart:296-303 was&&!playing→saveProgress，pause 触发即存）
  ```
  Code evidence: checkExpired 语义 timer_service.dart:250-258；pause 自动存进度 :299

- **[TMR-01-S4] 窗口外零副作用**
  ```
  Given 定时器未激活，或模式为 afterCurrent/paused，或 duration 剩余 >10s
  When 执行 tick
  Then 若 lastWritten 已是 1.0：不发生任何 setVolume / pause 调用（每秒空转成本≈两次 ref.read）
  否定断言:
    - afterCurrent / paused 模式下永远不会写出 <1.0 的音量（INV3）
  ```

- **[TMR-01-S5] 打断后的收敛恢复**
  ```
  Given 淡出进行中（如音量已写到 0.4）
  When 用户取消定时器 / 重设时长 / 切到播完停止（任一使 active 变 false 或 remaining 回到窗口外的操作）
  Then 最迟下一个秒级 tick 将 setVolume(1.0) 并复位 lastWritten（≤1 秒恢复，U4/U5）
  否定断言:
    - 恢复后若定时器仍以新配置活跃，从新 remaining 重新按曲线计算，不残留旧衰减斜率
  ```
  依据（访谈裁决修订说明）：原推荐"动作入口内联立即恢复"要求 timer feature 反向调 player（违反 feature 隔离且引入 import 环），故收敛为"tick 驱动恢复，上限 1 秒"。淡出语境下 1 秒延迟不可感知。

- **[TMR-01-S6] 四个驱动点统一换线**
  ```
  Given home_screen.dart:51-56 / :61-66 与 player_screen.dart:68-73 / :79-83 现为
        "checkTimerExpiryProvider() 返回 true 则手动 pause()" 四处重复
  When 改造完成
  Then 四处全部替换为一行 `ref.read(timerTickWithFadeProvider)();`（async gap 内 unawaited 或 await 均可，spec 统一用 unawaited）
  And checkTimerExpiryProvider 本体保留不删（di :172 导出、测试在用），生产调用点归零
  否定断言:
    - expiry 时 pause 恰好执行一次（不会因双屏双 tick 各 pause 一次产生额外副作用；
      checkExpired 第二次调用返回 false 是天然幂等闸，timer_service.dart:253-256）
    - home/player 两文件的 didChangeAppLifecycleState 其余逻辑（保存进度等）不动
  ```
  Code evidence: player_screen.dart:80-84 paused 存进度分支保留

### 3.4 桥接登记

- **[TMR-01-S7] di 导出清单更新**
  ```
  Given lib/shared/di/providers.dart timer 段（:152-176）与 player 段 export 清单
  When 新增符号
  Then timer 段 show 列表追加 `fadeVolumeForRemaining, kTimerFadeWindow`
      （来源 ../../features/timer/domain/fade_policy.dart，需新增一条 export 行）
  And player 段 show 列表追加 `timerTickWithFadeProvider`
  And home_screen / player_screen 对新符号的 import 全部走 shared/di（既有路径不变）
  否定断言:
    - 不出现 feature→feature 直接 import（cross-imports.sh feature-isolation 门禁 0 违规）
  ```
  Code evidence: REF-09 先例——progress_policy 经 core/contracts 中转供跨模块消费（INDEX.md changelog 2026-08-16）

---

## §4 不变量

- **[TMR-01-INV1]** 音量写权唯一：生产代码（lib/）中对 `IAudioPlayer.setVolume` 的调用只允许出现在 `timerTickWithFadeProvider` 闭包内部一处。
  证据：grep 基线 2026-08-23 为零调用；本功能只增这一个调用点
- **[TMR-01-INV2]** 定时器非激活稳态下播放器音量为 1.0（最多滞后一个 tick 收敛）。
  证据：S3/S5 恢复分支 + S4 稳态零副作用共同保证
- **[TMR-01-INV3]** afterCurrent 与 paused 模式从不产生 <1.0 的音量值。
  证据：timer_service.dart:63（afterCurrent remainingTime 恒 null）/ :64-66（paused 冻结值仍可能 <10s！——paused 在窗口内冻结时 target 会是 <1 的常数并被持续写入同一值，**但绝不继续下降**；恢复播放后随真实倒计时继续。此为 U7 语义，非违例；INV3 限定的是"模式本身"而非冻结数值，afterCurrent 永远 null → 永远 1.0）
- **[TMR-01-INV4]** 到期停止的副作用顺序恒为 setVolume(0) → pause → setVolume(1.0)，pause 前 0 写保证最后一刻无声。
  证据：§3.3 代码顺序

---

## §5 测试规约

### 5.1 现有测试清单

| 测试文件 | 覆盖 | 备注 |
|---|---|---|
| test/features/timer/timer_test.dart | TMR-01~05 状态机全量 | 纯函数域，本功能不改其断言 |
| test/features/player/bug_bug21_completed_seek_test.dart 等 | completed 路径 | afterCurrent 路径未被触碰的回归锚 |

### 5.2 测试 ID 派生清单

```
TMR-01-S1 ~ S7
TMR-01-INV1 ~ INV4
TMR-01-ALG1（fade 曲线表）
```

### 5.3 测试覆盖盲点

| 未覆盖 ID | 现状 | 应补偿方式 |
|---|---|---|
| S3 顺序性 | 无 | fake_async 驱动 tick 至到期，按序 verify setVolume(0)/pause/setVolume(1.0)（InOrder） |
| S5 收敛 | 无 | 写入 0.4 后改 state 为 null → 手动触发 tick → 断言恢复写 |
| S6 双屏幂等 | 无 | 同一容器连续两次 tick，verify pause 恰好 1 次 |

### 5.4 门禁测试文件位置

```
test/features/timer/tmr_01_volume_fade_test.dart   # ALG1/S2~S7 + INV1~INV4（含 InOrder 断言）
```
（命名核查 2026-08-23：test/features/timer/ 下仅有 bug_bug03/ref_11/timer_test 三族文件，无撞名。）

---

## §6 算法样例

```
ALG [TMR-01-ALG1-fadeVolumeForRemaining]:
  # window = 10000ms；公式 v = clamp(ms / 10000, 0, 1)；null → 1.0
  输入: null        → 期望: 1.0     # 非 duration 或字段缺失（S4）
  输入: 10min       → 期望: 1.0     # 窗口外，且不得产生 setVolume 写（配合 lastWritten 门）
  输入: 10s 整      → 期望: 1.0     # 边界：恰好在窗口上沿，仍视为未进入淡出
  输入: 5s          → 期望: 0.5     # 线性中点
  输入: 1s          → 期望: 0.1
  输入: 500ms       → 期望: 0.05
  输入: 0           → 期望: 0.0     # 归零点，当 tick 与到期重合（S3）
  输入: -1ms        → 期望: 0.0     # 过期但 checkExpired 未跑到的间隙
```

---

## §7 跨模块影响

| 其它 feature | 影响点 | 影响条件 | 需要补的回归断言 |
|---|---|---|---|
| PLY | afterCurrent 到期路径（player_provider.dart:326-330）与本功能共享 pause 调用面但互不修改 | 播完当前曲停止 | bug_bug21 族测试全绿即可；不新增断言 |
| PRG | 到期 pause 会经既有 was&&!playing 链自动保存进度（player_provider.dart:296-303） | 淡出期间用户手动暂停 | 现有 BUG-20 修复测试（dispose 后暂停保存）不改一字全绿 |
| PLY | 重排/切歌等任何播放器操作不写音量（INV1 单一写权） | 任意 | ply_01 新测试若误触 setVolume 会因 MissingStubError 暴露（天然回归网） |

---

## §8 平台特性与手动 QA

逐条核对 docs/dev/platform-pitfalls.md：

| 踩坑条目 | 是否触及 | 处置 |
|---|---|---|
| P16 时间运算精度截断 | 是 | 曲线用毫秒整除前的浮点除法（§3.2 实现），inMilliseconds 截断误差 ≤1ms，对听感无影响；ALG1 含边界行 |
| P8 播放监听器生命周期 | 否 | 未新增任何 stream 监听；tick 复用页面既有 Timer.periodic，dispose 行为先例不变（home_screen.dart:70-75） |
| P17 超时分层 | 否 | setVolume 为本地属性写，不加超时（对照 adapter 现有超时仅覆盖网络型平台调用） |
| P12 值对象相等性 | 否 | TimerState == 已含 mode/endTime/startedAt/remainingMs（timer_service.dart:85-91），本功能不改状态对象 |

**可行性依据（铁律 6）：**

- R1 just_audio `AudioPlayer.setVolume(double)`：pub.dev just_audio 0.9.40 API 文档公开方法（0.9.x 全系可用，语义=播放器流内音量乘数，0.0~1.0，与系统媒体音量独立）。仓库契约层此前未暴露，属"现有代码未使用过的 API"，依据为本条官方文档引用。
- R2 mockito 对新增接口方法的动态分发：mockito 5.4.4 `Mock` 基类经 noSuchMethod 兜底，接口加方法不需改 `MockAudioPlayer extends Mock implements AudioPlayer, IAudioPlayer`（test/helpers/mock_audio_player.dart:33）声明；但调用未 stub 方法返回 null，`await null` 合法而 verify 需要 stub —— BUG-27 勘察记录（INDEX.md 2026-08-23 条目「player.audioSource 缺 stub 会以 MissingStubError 抢占」）实证本仓库 mockito 行为。

**真机风险列：**

| 风险 | 近似测试方案 | 测不了 → 进 mqa-backlog |
|---|---|---|
| 锁屏/Doze 下 Flutter 秒级 tick 被推迟，淡出可能跳变甚至"直接停" | fake_async 无法模拟 OS 调度 | MQA：锁屏播放设 1 分钟定时，观察最后 10 秒是否平滑 |
| 真机扬声器/蓝牙上 10s 线性曲线的听感 | 无法模拟 | MQA：听感验收（过陡/过缓反馈回填参数） |
| setVolume 与系统音量、蓝牙绝对音量协议的相互作用 | 无法模拟 | MQA：蓝牙耳机上确认淡出生效 |

涉平台原生音频输出路径 → `manual_qa_required: true`。

---

## §9 dev-status.json 条目对照

```json
"TMR-01": {
  "spec_file": "docs/features/TMR-01.md",
  "spec_anchored_files": [
    "lib/features/timer/domain/timer_service.dart",
    "lib/features/timer/timer_provider.dart",
    "lib/features/player/player_provider.dart",
    "lib/core/contracts/audio_player_contract.dart",
    "lib/core/services/audio_player_adapter.dart",
    "lib/features/home/home_screen.dart",
    "lib/features/player/player_screen.dart"
  ],
  "scenarios": ["TMR-01-S1","TMR-01-S2","TMR-01-S3","TMR-01-S4","TMR-01-S5","TMR-01-S6","TMR-01-S7"],
  "invariants": ["TMR-01-INV1","TMR-01-INV2","TMR-01-INV3","TMR-01-INV4"],
  "algorithms": ["TMR-01-ALG1-fadeVolumeForRemaining"],
  "test_files": ["test/features/timer/tmr_01_volume_fade_test.dart"],
  "test_coverage_gaps": [],
  "cross_module_impacts": ["PLY", "PRG"],
  "manual_qa_required": true,
  "dependencies": [],
  "impl_status": "pending",
  "test_status": "pending",
  "check_status": "pending"
}
```
