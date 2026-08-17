# REF-12 — 删除 write-only 残留 currentSpeedProvider（三处写入 + re-export + 测试迁移）

## §0 头部元数据

```yaml
id: REF-12
name: 删除 currentSpeedProvider write-only 残留（运行时速真理源归 player.speedStream）
priority: P2
status: active
created_at: 2026-08-16
last_updated: 2026-08-16
spec_anchored_files:
  - lib/features/player/player_provider.dart
  - lib/features/player/widgets/speed_control.dart
  - lib/shared/di/providers.dart
  - test/features/player/ply_07_test.dart
  - test/features/settings/settings_test.dart
  - test/features/settings/bug_bug28_repro_test.dart
  - test/helpers/mock_audio_player.dart
cross_module_impacts: [PLY, SET]
manual_qa_required: false   # 删除 provider 层镜像状态，生产运行时速（speedStream）零改动，不涉平台原生
```

---

## §1 用户视角

### 1.0 原始需求（用户原话逐字记录）

来源：`docs/cr/cr-20260816-0805-progress-timer-settings.md` D5（转 REF 需求流程，用户裁决"删残留或接读取方"）：

> #### D5. `currentSpeedProvider` 为 write-only 残留状态，无任何读取方
>
> - 类型：DESIGN / 严重度：Minor / 维度：内部一致性（死状态）
> - 证据：写入点 `lib/features/player/player_provider.dart:178`（`setDefaultSpeedProvider` 内 `ref.read(currentSpeedProvider.notifier).state = s`）、`:338`（`_startPlaybackListeners` 内同写）、`lib/features/player/widgets/speed_control.dart:80`；grep 全 lib 无 `ref.watch/read(currentSpeedProvider)` 读取方（仅 `shared/di/providers.dart:97` re-export）。运行时速度实际经 `player.speedStream`（speed_control.dart:21-24）与 orchestrator 加载时 `player.setSpeed(defaultSpeed)`（`playback_orchestrator.dart:201`）驱动。
> - 现象与取舍：REF-10 把速度管理下沉 speed_manager 后，此 StateProvider 是旧运行时速度状态残留，三处写入均无消费方。保留成本低（无副作用），但为未来维护者制造「写它有什么用」的困惑；且与 remember-speed 语义无关。
> - 修复建议：删除 currentSpeedProvider 及其三处写入（若 shared/di 导出被测试引用，同步清理），或裁决保留为「设置页默认速度与运行时速对齐」的未来数据源。

**证据修正（dev-plan 勘察，覆盖 cr 原文"无任何读取方"）**：cr 的 grep 只覆盖 `lib/`。**`test/` 下有 25+ 处读取**（ply_07_test.dart PLY-T43/44/46/47 + TST-T73~78 全组、settings_test.dart SET-T05/T06、bug_bug28_repro_test.dart 两处），这些容器测试把 currentSpeedProvider 当作"模拟用户调速"的 provider 层镜像。**裁决必须同步设计测试迁移**，且把「运行时速与默认速分离 / remember 门控」语义重新锚定到真实生产链路（SpeedControl widget + player.setSpeed）。

### 1.1 这一功能干什么（一句话）

把 `currentSpeedProvider` 这个"生产零读取、测试当模拟面"的残留状态删除干净：删掉三处写入与 shared/di re-export，把依赖它的测试改锚定到真实的运行时速链路（player.speedStream / SpeedControl widget），让维护者不再困惑"这里写了给谁读"。

### 1.2 用户期望的场景

| ID | 你看到的样子 | 期望行为 |
|----|----|----|
| U1 | 播放页点速度按钮选 2.0x | 播放速度立刻变 2.0x，按钮显示 2.0x，行为与修复前完全一致 |
| U2 | 设置里开"记住播放速度"后调速度 | 新歌仍沿用调好的速度（remember-speed 语义不变） |
| U3 | 设置里关"记住播放速度"后调速度 | 新歌仍用设置页默认速度（分离语义不变） |
| U4 | 开发侧速览 player/provider 代码 | 不再有人手写的"当前速度"provider 镜像；速度状态单一来自播放器本身 |

---

## §2 已实现的功能骨架（代码锚点）

### 2.1 文件与分层

| 层 | 文件 | 行数 | 角色 |
|---|---|---|---|
| Provider | `lib/features/player/player_provider.dart` | 401 | currentSpeedProvider 定义（:180-181）+ 两处写入（:178 setDefaultSpeedProvider 内、:338 _startPlaybackListeners 内） |
| Widget | `lib/features/player/widgets/speed_control.dart` | 96 | 速度按钮：显示读 player.speedStream（:21-24）；onTap 写 currentSpeedProvider（:80） |
| Shared-DI | `lib/shared/di/providers.dart` | 250 | re-export currentSpeedProvider（:97） |
| 测试 | `test/features/player/ply_07_test.dart` | 730 | PLY-T43/44/46/47 + TST-T73~78（大量读 currentSpeedProvider） |
| 测试 | `test/features/settings/settings_test.dart` | 1323 | SET-T05（:145-152）/ SET-T06（:164-167） |
| 测试 | `test/features/settings/bug_bug28_repro_test.dart` | 188 | 非法 speed 断言（:154-155）/ 合法 speed 断言（:184） |
| 测试 | `test/helpers/mock_audio_player.dart` | 448 | MockAudioPlayer（speedStream :74-77、setSpeed :293-296），widget 级迁移用 |

### 2.2 关键 Provider 表

| Provider 名 | 类型 | 实现位置 | 用途 |
|---|---|---|---|
| currentSpeedProvider | StateProvider\<double\> | player_provider.dart:180-181 | 待删除的 write-only 镜像 |
| defaultSpeedProvider | Provider\<double\> | player_provider.dart:170-173 | 设置默认速（prefs 直读，保留） |
| setDefaultSpeedProvider | Provider\<void Function(double)\> | player_provider.dart:174-179 | 写 prefs + invalidate default + 写 currentSpeed（待删那行） |
| rememberSpeedProvider | Provider\<bool\> | settings_provider.dart:86-89 | remember 门控（保留） |

### 2.3 状态机图

本功能无状态机，跳过（速度门控在 speed_control.dart:78-84 单点，真实链路不涉 provider 镜像）。

---

## §3 行为规约（Given-When-Then）

### 3.1 现有行为（逆抽）

- **[REF-12-S1]** currentSpeedProvider 三处写入、零生产读取
  ```
  Given player_provider.dart:178（setDefaultSpeedProvider 内写 currentSpeed=s）、:338（_startPlaybackListeners 内写 currentSpeed=ds，仅 ds≠1.0 时）、speed_control.dart:80（onTap 写 currentSpeed=speed）
  When grep lib/ 下 watch/read(currentSpeedProvider)
  Then 零命中（仅 shared/di:97 re-export，且 di 无业务逻辑、re-export 供潜在消费方）
  ```
  Code evidence: `lib/features/player/player_provider.dart:178, 180-181, 338` + `lib/features/player/widgets/speed_control.dart:80` + `lib/shared/di/providers.dart:97`

- **[REF-12-S2]** 生产运行时速真理源为 player.speedStream / player.setSpeed
  ```
  Given speed_control.dart:21-24 StreamBuilder(player.speedStream) 显示当前速（snapshot.data ?? 1.0）
  And playback_orchestrator.dart:201 加载时 player.setSpeed(defaultSpeed)
  And speed_control.dart:79 onTap 先 player.setSpeed(speed) 再写 currentSpeedProvider
  When 用户调速
  Then 真实速度由 player 承载，currentSpeedProvider 只是冗余镜像
  ```
  Code evidence: `lib/features/player/widgets/speed_control.dart:21-24, 79` + `lib/features/player/domain/playback_orchestrator.dart:201`

- **[REF-12-S3]** 测试实测读取面（证据修正：非零读取方）
  ```
  Given 逐文件 grep currentSpeedProvider
  Then ply_07_test.dart（PLY-T43 :39-46；PLY-T44 :74-81；PLY-T46 :165-233；PLY-T47 :237-352；TST-T73~78 :433-691 等 ≥25 处）
  And settings_test.dart（SET-T05 :145-166，其中 :145 写 :147 读；SET-T06 :164-167 读）
  And bug_bug28_repro_test.dart（:154-155 读断言、:184 读断言）
  ```
  Code evidence: 各文件行号（见 §2.1）

- **[REF-12-S4]** remember 门控真实生产链路（迁移语义的真理锚）
  ```
  Given speed_control.dart:78-84
  When 用户 tap 某速度档（onTap）
  Then player.setSpeed(speed)（:79）
  And ref.read(rememberSpeedProvider) 为真 → setDefaultSpeedProvider(speed)（:82-84）
  ```
  Code evidence: `lib/features/player/widgets/speed_control.dart:78-84`

### 3.2 修改方案（status: new）

设计裁决：**删残留**（不选"接读取方"）。理由：
- 生产运行时速真理是 `player.speedStream`（P-链证明），再保留一个手写镜像只制造双源漂移（P10 反面）；"接读取方"没有任何自然的读取点——设置页显示默认速、播放页显示 player 实速，都不需要镜像。
- REF-12 删除后"运行时速 vs 默认速分离"语义由结构保证：写 default/prefs 的唯一入口是 setDefaultSpeedProvider；运行时速在 player 侧。remember 门控在 speed_control.dart:82-84 唯一存在。
- 测试迁移把容器层"写镜像模拟调速"升级为 **SpeedControl widget 测试**（pump 真实 widget + MockAudioPlayer），锚定真实生产链路，查"门控调用 player.setSpeed + remember 条件下 setDefaultSpeedProvider"。

修改点清单：
1. `lib/features/player/player_provider.dart`：删 :178 行（setDefaultSpeedProvider 体改为 `prefs?.setDouble + ref.invalidate(defaultSpeedProvider)`，保留 `if (!sm.isValidSpeed(s)) return;`）；删 :180-181 定义；删 :336-338（_startPlaybackListeners 里 `final ds = ref.read(defaultSpeedProvider); if ((ds-1.0).abs()>0.01) ref.read(currentSpeedProvider.notifier).state = ds;` 三行）。
2. `lib/features/player/widgets/speed_control.dart`：删 :80（currentSpeed 写入行），onTap 剩 `player.setSpeed(speed); if (rememberSpeed) setDefaultSpeedProvider(speed); Navigator.pop`。
3. `lib/shared/di/providers.dart`：删 :97 currentSpeedProvider re-export。

| 边界情况 | 裁决 |
|---|---|
| 测试依赖 currentSpeedProvider 作为"模拟用户调速"载体 | 迁移策略见 §3.2 各 Scenario：能保语义的改锚 customerSpeedProvider 断言为 defaultSpeedProvider+prefs；容器模拟调速语义统一上移为 SpeedControl widget 测试 |
| PLY-T43/44（"currentSpeedProvider can be set to 0.5/2.0"） | 只验证 provider 可写（纯镜像存在性），无生产行为 → 直接删除该两条 test |
| PLY-T46（"changing currentSpeed leaves defaultSpeed unchanged"） | 语义=运行时速变化不改设置默认/不写 prefs → 迁移为 SpeedControl widget 测试（remember off，tap 2.0，断言 player.setSpeed(2.0) 被调 + prefs/default 不变） |
| PLY-T47（"currentSpeed initialized from defaultSpeed"） | 语义=运行时速从 default 起 → 迁移：保留 defaultSpeedProvider 从 prefs 初始化的容器断言（setDefaultSpeedProvider/prefs 行为），runtime 初始化为 default 的"新文件使用设置默认速"由 orchestrator.dart:201 既有 player 测试锚定；currentSpeed 的具体断言删除 |
| TST-T73~78（rememberSpeed 流） | 容量测改 widget：pump SpeedControl（MockAudioPlayer + rememberSpeed override），tap 档位；remember on → default+prefs 更新；off → 不变。真实门控 speed_control.dart:82-84 被直测 |
| SET-T05（"播放器中手动调速不影响 Settings 默认速度"） | 迁移为 SpeedControl widget 测试（remember off）或改容器断言"非 setDefaultSpeedProvider 无写 prefs 路径"（保持语义）；推荐 widget 测试 |
| SET-T06（"新文件从 default 初始化"） | 删除 currentSpeed 断言、保留 defaultSpeedProvider 从 prefs 初始化断言（defaultSpeedProvider 本身保留） |
| bug_bug28（非法 speed 不更新 currentSpeed） | currentSpeed 断言换 defaultSpeedProvider+prefs 断言（该文件 :152 已断言 defaultSpeedProvider==1.0，补 prefs isNull 即可；:184 合法 speed 断言改 defaultSpeedProvider==1.5 && prefs==1.5） |
| shared/di 除 :97 外是否有别处引 currentSpeedProvider | 已 grep 确认无（仅 di:97） |
| currentSpeedProvider 定义与默认值 `ref.read(defaultSpeedProvider)` | 定义删除后无默认化消费方，删除即可 |

- **[REF-12-S5]** 删除 player_provider 两处写入与定义 、speed_control 写入、di re-export （status: new）
  ```
  Given 上述修改点 1/2/3 全部落地
  When 全 lib grep currentSpeedProvider
  Then 零命中（含 shared/di，含 player_provider 定义）
  否定断言:
    - defaultSpeedProvider / SET-defaultSpeed / rememberSpeedProvider 等保留符号行为不变（setDefaultSpeedProvider 仍校验+写 prefs+invalidate default）
    - player.setSpeed 调用点（speed_control:79、orchestrator:201）不得删
    - shared/di 其它 re-export（speedOptions/isValidSpeed/defaultSpeedProvider/setDefaultSpeedProvider 等）不得动
  ```
  修改点：`lib/features/player/player_provider.dart:178, 180-181, 336-338` 删除；`lib/features/player/widgets/speed_control.dart:80` 删除；`lib/shared/di/providers.dart:97` 删除。

- **[REF-12-S6]** SpeedControl widget 门控测试锚定真实链路（remember off：调速只动 player，不碰默认/prefs） （status: new）
  ```
  Given PumpWidget(SpeedControl in ProviderScope：audioPlayerProvider→MockAudioPlayer(speedStream、setSpeed 可 verify)；rememberSpeedProvider→false；sharedPreferencesProvider→mock prefs 默认 1.0)
  When tap 速度按钮开 sheet → tap '2.0x'
  Then verify(player.setSpeed(2.0)) 被调
  And prefs['default_playback_speed'] 保持 1.0（未写入）
  And defaultSpeedProvider 保持 1.0
  否定断言:
    - SpeedControl onTap 不再引用 currentSpeedProvider（读源断言 / 运行不抛 ProviderNotFound）
    - remember off 时不得调用 setDefaultSpeedProvider（prefs 不动）
  ```
  修改点：新增测试文件 `test/features/player/ref_12_speed_gate_test.dart`（见 §5.4）。

- **[REF-12-S7]** SpeedControl widget 门控测试（remember on：调速同步默认+持久化） （status: new）
  ```
  Given 同 S6 但 rememberSpeedProvider→true
  When tap '2.0x'
  Then verify(player.setSpeed(2.0)) 被调
  And prefs['default_playback_speed'] == 2.0
  And defaultSpeedProvider == 2.0
  否定断言:
    - remember on 只允许经 setDefaultSpeedProvider 一条写路径更新 default/prefs（断言不出现第二次 setDefault 调用）
    - 空档/未 tap 时不产生副作用
  ```
  修改点：同 §5.4 测试文件。

- **[REF-12-S8]** ply_07 / settings / bug_bug28 三类测试按裁决迁移 （status: new）
  ```
  Given ply_07_test.dart：PLY-T43/44 删除；PLY-T46 语义迁 S6 型 widget（remember off）；PLY-T47 保留 defaultSpeedProvider 初始化断言、删 currentSpeed 断言与 "currentSpeed 镜像"+ 由新 widget 直测；TST-T73~78 改为 S6/S7 型 widget（remember on/off 两态）
  And settings_test.dart SET-T05 迁 widget、SET-T06 改 defaultSpeedProvider 断言
  And bug_bug28_repro_test.dart :154-155/:184 改 defaultSpeedProvider+prefs 断言
  When 全量跑迁移后测试
  Then 全绿，且不再出现 currentSpeedProvider 标识符
  否定断言:
    - migrate 后任何测试文件不得再 import/refer currentSpeedProvider（grep test/ 零命中）
    - 被删除测试的语义（default 不受运行时速影响、remember 门控）不得真的消失——由新 widget 测试显式承担
  ```
  修改点：`test/features/player/ply_07_test.dart`、`test/features/settings/settings_test.dart`、`test/features/settings/bug_bug28_repro_test.dart` 逐组迁移（§5.4 列出精确行号）。

---

## §4 不变量

- **[REF-12-INV1]** 写 defaultSpeed/prefs 的唯一入口是 setDefaultSpeedProvider（RuntimeSpeed 分离结构保证）
  证据：player_provider.dart:174-179（改后仅 prefs.write + invalidate）+ speed_control.dart:82-84（remember 门控唯一调用 setDefault 处）。

- **[REF-12-INV2]** 运行时速唯一真理源为 player（speedStream + setSpeed），provider 层不再存在速度镜像状态
  证据：speed_control.dart:21-24（显示读 speedStream）+ :79（写 player）+ playback_orchestrator.dart:201（加载时 setSpeed(defaultSpeed)）+ currentSpeedProvider 删除。

- **[REF-12-INV3]** remember-speed 语义保留：remember on → 调速同步默认；off → 分离
  证据：speed_control.dart:82-84（门控不动）+ S6/S7 widget 测试锚定。

---

## §5 测试规约

### 5.1 现有测试清单

| 测试文件 | 覆盖的 Scenario / INV | 备注 |
|---|---|---|
| test/features/player/ply_07_test.dart | REF-12-S1、S3、S8 | PLY-T43/44/46/47 + TST-T73~78 需按迁移删除/改写 |
| test/features/settings/settings_test.dart | REF-12-S3、S8 | SET-T05/T06 迁移 |
| test/features/settings/bug_bug28_repro_test.dart | REF-12-S3、S8 | :154-155/:184 改锚 |
| test/helpers/mock_audio_player.dart | REF-12-S6、S7（支撑） | SpeedControl pump 用 MockAudioPlayer（speedStream/setSpeed 已具备） |

### 5.2 测试 ID 派生清单（dev-exe 派发测试 Agent 用）

```
REF-12-S1 … S8        # Scenario（S1~S4 现状锚定，S5~S8 修改目标）
REF-12-INV1 … INV3    # 不变量
```

dev-exe 要求：S5（grep 断言）与 S6/S7（widget 门控）与 INV1~3 由 §5.4 门禁文件覆盖；S8 的迁移由三个既有测试文件内改完成。

### 5.3 测试覆盖盲点（dev-plan 写本文档时识别）

| 未覆盖 ID | 现状 | 应补偿方式 |
|---|---|---|
| REF-12-S6/S7（remember 门控 widget 真人路径） | 容器测试是模拟镜像而非 widget 实际链路 | §5.4 新增 widget 测试直测 speed_control.dart:78-84 |
| REF-12-S5（删除后 grep 零命中） | 无现成断言 | §5.4 门禁文件源扫描 |

### 5.4 测试文件位置（spec-scan --gate 硬校验）

命名防撞已核：`test/features/player/` 现有 ref_11_test / ref_12_test / ref_13_test（旧轮遗留，与本 REF ID 无关，不可覆盖）——新文件取名避开前缀撞名。新建：

`test/features/player/ref_12_speed_gate_test.dart`（widget 测试）：

| 测试文件 | 覆盖 ID | 说明 |
|---|---|---|
| test/features/player/ref_12_speed_gate_test.dart | REF-12-S5（grep + import 源扫描）、S6、S7、INV1、INV2、INV3 | ①读 player_provider/speed_control/di 源码断言无 currentSpeedProvider；②pump SpeedControl（audioPlayerProvider=MockAudioPlayer、rememberSpeedProvider override 两态、sharedPreferencesProvider=mock）→ tap 档位 → verify player.setSpeed / prefs / defaultSpeedProvider 断言 |
| test/features/player/ply_07_test.dart | REF-12-S8 | 既有文件逐组改（PLY-T43/44 删，PLY-T46 语义入 widget，PLY-T47/TST-T73~78 改锚） |
| test/features/settings/settings_test.dart | REF-12-S8 | SET-T05 迁 widget、SET-T06 改 defaultSpeedProvider 断言 |
| test/features/settings/bug_bug28_repro_test.dart | REF-12-S8 | :154-155/:184 改 defaultSpeedProvider+prefs 断言 |

---

## §6 算法样例

本功能为状态删除 + 测试迁移，无纯函数算法样例，跳过。

---

## §7 跨模块影响

用 `cross-imports.sh impact lib/features/player/player_provider.dart` + `lib/features/player/widgets/speed_control.dart` 实测（2026-08-16）：

- player_provider.dart → main.dart / app/onboarding.dart / player 内 15+ widget、provider
- speed_control.dart → player_screen.dart

| 其它 feature | 影响点 | 影响条件 | 需要补的回归断言 |
|---|---|---|---|
| PLY（player_screen / mini_player_bar / play_mode_control / now_playing_icon / progress_slider） | 这些消费 player_provider 但均不读 currentSpeedProvider（已 grep 证实） | 定义删除不影响其 import（currentSpeedProvider 未在其 export 面） | 既有 ply_01~08 / player 相关 widget 测试全绿 |
| SET（settings_provider/settings_test/bug_bug28） | setDefaultSpeedProvider 行为不变（S5 断言）；SET-T05/T06 迁移 | defaultSpeedProvider/rememberSpeedProvider 保留 | settings_test 全绿 + ref_12_speed_gate_test PASS |
| shared/di（providers.dart） | 删 :97 re-export | 无 lib 消费方 | 依赖 di 的既有测试全绿（bug_bug28 等） |
| 测试 ply_07_test.dart | TST-T73~78 由容器改 widget | remember 语义别丢 | ref_12_speed_gate_test S6/S7 承担，ply_07 其余组全绿 |

---

## §8 平台特性与手动 QA

设计前已核对 `docs/dev/platform-pitfalls.md`：本修改删 provider 层镜像、加 widget 门控测试，不触 P1~P17 任一条（不涉 audio_service/焦点/后台/时序；player.setSpeed 与 speedStream 是 just_audio 既有 API，调用点不变）。

**真机风险列**：

| 风险 | 近似测试方案 | 测不了 → 进 mqa-backlog |
|---|---|---|
| 真机播放页速度按钮显示/调速 | widget 测试用 MockAudioPlayer 模拟 speedStream 与 setSpeed；真实链路（speedStream 回写）由 Ply_02/player 测试锚定 | 真机项：播放页点 2.0x，按钮显示 2.0x 且实际变速（进 mqa-backlog REF-12 条目，可选） |

本功能不涉及平台原生特性，全部可在 `flutter test` 中验证 → `manual_qa_required = false`。

---

## §9 dev-status.json 条目对照

```json
"REF-12": {
  "spec_file": "docs/features/REF-12.md",
  "spec_anchored_files": [
    "lib/features/player/player_provider.dart",
    "lib/features/player/widgets/speed_control.dart",
    "lib/shared/di/providers.dart",
    "test/features/player/ply_07_test.dart",
    "test/features/settings/settings_test.dart",
    "test/features/settings/bug_bug28_repro_test.dart",
    "test/helpers/mock_audio_player.dart"
  ],
  "scenarios": ["REF-12-S1", "REF-12-S2", "REF-12-S3", "REF-12-S4", "REF-12-S5", "REF-12-S6", "REF-12-S7", "REF-12-S8"],
  "invariants": ["REF-12-INV1", "REF-12-INV2", "REF-12-INV3"],
  "algorithms": [],
  "manual_qa_required": false,
  "user_acceptance_text": "见 §1.2"
}
```