# REF-11 — 定时弹窗 15 分钟预设恢复（补回 tile，文档漂移收敛）

## §0 头部元数据

```yaml
id: REF-11
name: 定时弹窗补回 15 分钟预设 tile（对齐头注释/TMR-T26 文档）
priority: P2
status: active
created_at: 2026-08-16
last_updated: 2026-08-16
spec_anchored_files:
  - lib/features/timer/widgets/timer_button.dart
  - lib/features/timer/timer_provider.dart
  - lib/shared/di/providers.dart
  - test/features/timer/timer_test.dart
  - test/helpers/widget_helpers.dart
cross_module_impacts: [TMR, HOME]
manual_qa_required: false   # 纯 Flutter widget 弹窗集合调整，widget test 全可验，不涉平台原生
```

---

## §1 用户视角

### 1.0 原始需求（用户原话逐字记录）

来源：`docs/cr/cr-20260816-0805-progress-timer-settings.md` D3（转 REF 需求流程，用户裁决二选一）：

> #### D3. 定时弹窗 15 分钟预设缺失，与文件头注释及 TMR-T26 文档描述漂移
>
> - 类型：DESIGN / 严重度：Minor / 维度：功能-spec（行为漂移，待裁决）
> - 证据：`lib/features/timer/widgets/timer_button.dart:4-7` 头注释声明弹窗含「5 分钟 / 10 分钟 / 15 分钟 (TMR-01)」；实际构建的 tile 集合 `:56-95` 为「上次时长（可选）/ 5 分钟 / 10 分钟 / 播完当前 / 自定义 / 取消定时（仅激活时）」——**无 15 分钟项**。`timer_test.dart:16-17` 残留注释同样声明「Always shows: 5分钟 / 10分钟 / 15分钟 / 播完当前 (TMR-T26)」。`timer_test.dart:114` 的 TMR-T03 只锚定服务层 `startDuration(15)`，不锚定 UI 入口。
> - 现象与取舍：15 分钟预设要么在 REF-05 引入「自定义」时被有意替换（可自洽：自定义默认 0h5m、可滚到 15m），要么是意外丢失。用户视角：预设面板比文档少一档。两种处置都合理：补回 15 分钟 tile，或删 15 分钟并同步头注释 + TMR-T26 文档——需用户裁决。
> - 修复建议：裁决后二选一；无论哪种，用一条 TimerBottomSheet widget 测试锚定「始终显示 5/10/播完当前/自定义；激活时显示取消定时」的 tile 集合（见 T2）。

用户裁决：**补回 15 分钟 tile**（恢复文档承诺与常见用档；同步按 cr T2 补 TimerBottomSheet widget 测试锚定 tile 集合）。

### 1.1 这一功能干什么（一句话）

让定时停止弹窗重新提供"15 分钟"预设档，使 UI 与文件头注释、TMR-T26 文档描述一致，并补 widget 测试把 tile 集合钉死，防止后续漂移静默通过。

### 1.2 用户期望的场景

| ID | 你看到的样子 | 期望行为 |
|----|----|----|
| U1 | 打开定时停止弹窗 | 看到 5分钟 / 10分钟 / 15分钟 / 播完当前 / 自定义 档位（若上次自定义过，顶部还有"上次时长"），激活定时时另有"取消定时" |
| U2 | 点"15 分钟" | 立刻设定 15 分钟定时并关闭弹窗 |
| U3 | 从没自定义过时长 | 不出现"上次时长"条目（行为不变） |
| U4 | 定时器正在倒计时时再开弹窗 | 出现红色"取消定时"，其余档位不变 |

---

## §2 已实现的功能骨架（代码锚点）

### 2.1 文件与分层

| 层 | 文件 | 行数 | 角色 |
|---|---|---|---|
| UI | `lib/features/timer/widgets/timer_button.dart` | 306 | TimerBottomSheet（ConsumerWidget，:18-116）+ 自定义 picker（:118-269）；tile 集合 :56-108 |
| Provider | `lib/features/timer/timer_provider.dart` | 232 | startDurationTimerProvider（:193-197）/ startAfterCurrentProvider（:200-204）/ cancelTimerProvider（:207-211）/ lastCustomTimerMinutesProvider（:119-122）/ setLastCustomTimerMinutesProvider（:124-132） |
| Shared-DI | `lib/shared/di/providers.dart` | 250 | re-export TimerBottomSheet（:182）与全部 timer provider（:159-182） |
| 测试 | `test/features/timer/timer_test.dart` | 1318 | TMR-T01~T34 + REF-05 静态断言；头注释 :16-17 声明 15 分钟档 |
| 测试 | `test/helpers/widget_helpers.dart` | 172 | createTimerTestContainer（:165-171）+ noopRemainingTimeOverride（:158-160） |

### 2.2 关键 Provider 表

| Provider 名 | 类型 | 实现位置 | 用途 |
|---|---|---|---|
| timerStateProvider | NotifierProvider\<TimerStateNotifier, TimerState?\> | timer_provider.dart:89-90 | 定时状态（tile onTap 经 Notifier 变更） |
| startDurationTimerProvider | Provider\<void Function(int)\> | timer_provider.dart:193-197 | `ref.read(uid='X')(15)` 起 15 分钟定时 |
| startAfterCurrentProvider | Provider\<void Function()\> | timer_provider.dart:200-204 | 播完当前停止 |
| cancelTimerProvider | Provider\<void Function()\> | timer_provider.dart:207-211 | 取消定时 |
| timerActiveProvider | Provider\<bool\> | timer_provider.dart:95-98 | sheet isActive 参数用 |

### 2.3 状态机图

本功能无状态机，跳过（TimerService 状态机由既有 TMR 测试锚定）。

---

## §3 行为规约（Given-When-Then）

### 3.1 现有行为（逆抽）

- **[REF-11-S1]** tile 集合当前形态（含"上次时长"条件项、无 15 分钟）
  ```
  Given TimerBottomSheet 构建（isActive 任意）
  When 渲染 tile 序列
  Then 顺序为：上次时长（仅 lastCustomMinutesProvider!=null 时 :47-55）→ 5 分钟（:56-63）→ 10 分钟（:64-71）→ 播完当前（:72-79）→ 自定义（:80-95）→ [分隔线 + 取消定时（仅 isActive，:96-108）]
  And 无 15 分钟项
  ```
  Code evidence: `lib/features/timer/widgets/timer_button.dart:47-108`

- **[REF-11-S2]** 各 tile onTap 行为
  ```
  Given 用户 tap 某 tile
  Then 5分钟 → ref.read(startDurationTimerProvider)(5) + Navigator.pop
  And 10分钟 → ref.read(startDurationTimerProvider)(10) + pop
  And 播完当前 → ref.read(startAfterCurrentProvider)() + pop
  And 上次时长 → ref.read(startDurationTimerProvider)(lastCustomMinutes) + pop
  And 取消定时 → ref.read(cancelTimerProvider)() + pop
  And 自定义 → 捕获 rootCtx → pop → showModalBottomSheet(_CustomTimerPickerSheet)（:83-94）
  ```
  Code evidence: `lib/features/timer/widgets/timer_button.dart:51-55, 59-62, 67-70, 75-78, 84-94, 103-106`

- **[REF-11-S3]** 自定义 picker 默认 0h5m、0 分钟禁用确认
  ```
  Given _CustomTimerPickerSheet 打开
  Then 初始 _selectedHours=0 / _selectedMinutes=5（:128-129）
  And _totalMinutes == 0 时 确认按钮 onPressed null（:176-177）
  And 确认 → setLastCustomTimerMinutesProvider(_total) + startDurationTimerProvider(_total) + pop（:178-184）
  ```
  Code evidence: `lib/features/timer/widgets/timer_button.dart:128-129, 176-184`

- **[REF-11-S4]** 头注释与测试注释声称 15 分钟（漂移源）
  ```
  Given timer_button.dart 头注释 :4-7 '5 分钟 / 10 分钟 / 15 分钟 (TMR-01)'
  And timer_test.dart:16-17 'Always shows: 5分钟 / 10分钟 / 15分钟 / 播完当前 (TMR-T26)'
  When 对照实际 tile 集合
  Then 无 15 分钟项 → 文档漂移
  ```
  Code evidence: `lib/features/timer/widgets/timer_button.dart:4-7` + `test/features/timer/timer_test.dart:16-17`

### 3.2 修改方案（status: new）

设计裁决：**补回 15 分钟 tile**（选较文档成本的一侧：文档三处已承诺 15 分钟且 15 分钟是常见睡眠定时档；删文档则需改 3 处且丢档位）。插入位置为 `10 分钟` 之后、`播完当前` 之前，保持递增档序；icon 与 5/10 分钟一致（Icons.timer）。

修改点：`lib/features/timer/widgets/timer_button.dart`，在 :71（10 分钟 tile 结束）与 :72（播完当前 tile 起）之间插入：

```dart
_TimerOptionTile(
  icon: Icons.timer,
  label: '15 分钟',
  onTap: () {
    ref.read(startDurationTimerProvider)(15);
    Navigator.of(context).pop();
  },
),
```

| 边界情况 | 裁决 |
|---|---|
| 15 分钟 tile 与自定义可达性重复（自定义可滚到 15） | 允许：预设档为快捷入口，服务层 startDuration(15) 已存在（TMR-T03 锚定），无冲突 |
| 上次时长 == 15 的场景 | 仍显示两个独立项（上次时长 + 15 预设），命名不冲突，行为各自独立 |
| isActive=true 时 15 分钟仍显示 | 始终显示（与 5/10 一致，不受 isActive 影响） |
| 头注释/测试注释是否需要改 | 不需要——补回后即与文档一致（S4 漂移自动消除） |
| cr T2 要求的 tile 集合 widget 测试 | 由 REF-11 一并落地（见 §5.4），锚定 5/10/15/播完当前/自定义恒显 + 取消定时 isActive 条件显 + 上次时长条件显 |

- **[REF-11-S5]** 15 分钟 tile 出现且顺序正确、onTap 生效 （status: new）
  ```
  Given TimerBottomSheet(isActive: false) 渲染
  When 断言 tile 集合
  Then find.text('15 分钟') findsOneWidget
  And 顺序为 上次时长?→5 分钟→10 分钟→15 分钟→播完当前→自定义（见 S1）
  And tap '15 分钟' → TimerStateNotifier.startDuration(15) 被调（startDurationTimerProvider 生效）→ Navigator.pop 关闭弹窗
  否定断言:
    - 弹窗内不得出现第二个 '15 分钟'（不重复添加）
    - isActive=false 时不得出现 '取消定时'（find.text('取消定时') findsNothing，S1 :96 守卫仍生效）
    - 15 分钟 tile 不得改变 5/10/播完当前/自定义 既有 onTap 行为（S2 其余分支正则断言仍通过）
  ```
  修改点：`lib/features/timer/widgets/timer_button.dart` :72 前插入上述片段。

- **[REF-11-S6]** 自定义 picker 与上一次时长逻辑不受影响（回归） （status: new）
  ```
  Given lastCustomTimerMinutesProvider 有值时渲染
  When 断言
  Then '上次时长（...）' tile 仍出现（S1 条件项）
  And 自定义 picker 默认 0h5m、0 分钟禁用确认（S3）
  否定断言:
    - 15 分钟 tile 插入不影响 上次时长 条件判断（lastCustomMinutes==null 时仍 findNothing）
    - 不改变 _formatMinutesLabel / picker 滚动范围（24h/60m，:207/:240）
  ```
  修改点：无新增代码，由 §5.4 widget 测试回归断言。

---

## §4 不变量

- **[REF-11-INV1]** 弹窗预设档恒含 5/10/15 分钟三档（TMR-01 承诺）
  证据：timer_button.dart:56-71（改后）+ 头注释 :4-7 + timer_test.dart:16-17。

- **[REF-11-INV2]** 每个预设/操作档 onTap 必 `ref.read(...Provider)(...)` + `Navigator.pop`
  证据：timer_button.dart:51-55, 59-62, 67-70（改后同构插入 15 分钟 :71 后）, 75-78, 103-106 + :88-89（自定义 pop 例外：rootCtx 捕获后先 pop 再 showModal）。

- **[REF-11-INV3]** 取消定时仅 isActive 时显示，隔分发色的树结构不变
  证据：timer_button.dart:96-108（`if (isActive) ...[Divider + 红色 _TimerOptionTile]`）。

---

## §5 测试规约

### 5.1 现有测试清单

| 测试文件 | 覆盖的 Scenario / INV | 备注 |
|---|---|---|
| test/features/timer/timer_test.dart:114-121（TMR-T03） | REF-11-S5 服务端部分 | 服务层 startDuration(15) 锚定；UI 入口缺失是 D3 问题所在 |
| test/features/timer/timer_test.dart:1008-1028（REF-05 静态断言） | REF-11-S1 相关（TimerBottomSheet 保留） | 不动 |
| test/features/timer/timer_test.dart:16-17 头注释 | REF-11-S4 | 文档侧，补回后即一致，不需改 |

### 5.2 测试 ID 派生清单（dev-exe 派发测试 Agent 用）

```
REF-11-S1 … S6        # Scenario（S1~S4 现状锚定，S5~S6 修改目标）
REF-11-INV1 … INV3    # 不变量
```

dev-exe 要求：S5/S6 与 INV1~3 由 §5.4 门禁文件覆盖；S1~S4 中 S1/S2/S3 现状由门禁文件锚定（改后态），S4 文档一致由注释静态断言锚定。

### 5.3 测试覆盖盲点（dev-plan 写本文档时识别）

| 未覆盖 ID | 现状 | 应补偿方式 |
|---|---|---|
| 整个 TimerBottomSheet tile 集合（cr T2 直接原因） | 零 widget 测试（只有 REF-05 静态断言 + TMR 服务层测试） | §5.4 门禁文件 pump TimerBottomSheet 断言精确集合 |

### 5.4 测试文件位置（spec-scan --gate 硬校验）

命名防撞已核：`test/features/timer/` 现有 timer_test / bug_bug03* / bug_bug29，无 ref_11 前缀。新建：

`test/features/timer/ref_11_timer_sheet_test.dart`（widget 测试，pump TimerBottomSheet；使用 widget_helpers 的 createTimerTestContainer / noopRemainingTimeOverride 模式——见 timer_test.dart:65-79 与 widget_helpers.dart:158-171）：

| 测试文件 | 覆盖 ID | 说明 |
|---|---|---|
| test/features/timer/ref_11_timer_sheet_test.dart | REF-11-S1、S2、S5、S6、INV1、INV2、INV3 | 门禁：ProviderScope override timerServiceProvider + remainingTimeProvider 后 pump `MaterialApp(home: Scaffold(body: TimerBottomSheet(isActive:false/true)))`；断言 tile 集合精确出现/不出现、顺序、各 tile onTap 触发对应 provider（startDurationTimerProvider(5/10/15)、startAfterCurrentProvider、cancelTimerProvider）+ Navigator.pop；自定义 picker 打开后 0 分钟禁确认 |

---

## §6 算法样例

本功能为 widget 集合调整，无纯函数算法样例，跳过。

---

## §7 跨模块影响

用 `cross-imports.sh impact lib/features/timer/widgets/timer_button.dart` 实测（2026-08-16）——引用方为 `lib/features/player/widgets/timer_control.dart`（:58 builder 返回 `TimerBottomSheet(isActive: isActive)`，经 shared/di re-export）与 `lib/shared/di/providers.dart:182`：

| 其它 feature | 影响点 | 影响条件 | 需要补的回归断言 |
|---|---|---|---|
| Player（timer_control.dart:58） | PlayerScreen 弹窗入口调用 TimerBottomSheet(isActive:) | 新增 15 分钟 tile 不改变构造签名与 isActive 语义 | 既有 ply_01/ply_02/player 相关测试全绿 |
| Home（home_screen.dart timer 到期 checker） | 定时状态消费方（timer_provider export 不变） | 新增档位只增 UI 项，不改 provider API | 既有 home / timer 测试全绿 |
| timer_provider（startDurationTimerProvider(15)） | 服务层能力（TMR-T03 既有） | 无修改 | timer_test TMR-T03 保持绿 |

---

## §8 平台特性与手动 QA

设计前已核对 `docs/dev/platform-pitfalls.md`：本功能为纯 widget 弹窗档位集合调整，不触及 P1~P17 任一条（不涉 audio_service / TimerService 状态机 / Provider 并发时序 / 平台通道）。

**真机风险列**：

| 风险 | 近似测试方案 | 测不了 → 进 mqa-backlog |
|---|---|---|
| showModalBottomSheet 弹出动画在真机缩放（自定义 picker rootCtx 捕获） | widget 测试可 pump 动画（pumpAndSettle）；rootCtx 模式已存在（:88-89），未改 | 无（弹窗行为全部 widget test 可验，不涉平台原生） |

本功能不涉及平台原生特性，全部可在 `flutter test` 中验证 → `manual_qa_required = false`。

---

## §9 dev-status.json 条目对照

```json
"REF-11": {
  "spec_file": "docs/features/REF-11.md",
  "spec_anchored_files": [
    "lib/features/timer/widgets/timer_button.dart",
    "lib/features/timer/timer_provider.dart",
    "lib/shared/di/providers.dart",
    "test/features/timer/timer_test.dart",
    "test/helpers/widget_helpers.dart"
  ],
  "scenarios": ["REF-11-S1", "REF-11-S2", "REF-11-S3", "REF-11-S4", "REF-11-S5", "REF-11-S6"],
  "invariants": ["REF-11-INV1", "REF-11-INV2", "REF-11-INV3"],
  "algorithms": [],
  "manual_qa_required": false,
  "user_acceptance_text": "见 §1.2"
}
```