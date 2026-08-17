# REF-13 — 删除无消费者的 recentlyPlayedProvider invalidate（P10 反面：写无读）

## §0 头部元数据

```yaml
id: REF-13
name: 删除 upsert/clear 对 recentlyPlayedProvider 的无效 invalidate
priority: P2
status: active
created_at: 2026-08-16
last_updated: 2026-08-16
spec_anchored_files:
  - lib/features/progress/progress_provider.dart
  - lib/shared/di/providers.dart
  - lib/features/player/player_provider.dart
  - test/features/progress/prg_test.dart
cross_module_impacts: [PRG, PLY]
manual_qa_required: false   # 纯 provider invalidate 行删除，无平台原生
```

---

## §1 用户视角

### 1.0 原始需求（用户原话逐字记录）

来源：`docs/cr/cr-20260816-0805-progress-timer-settings.md` D6（转 REF 需求流程，用户裁决"删 invalidate 或建消费者"）：

> #### D6. `upsertProgressProvider` / `clearProgressProvider` 对 `recentlyPlayedProvider` 的 invalidate 无消费者
>
> - 类型：DESIGN / 严重度：Minor / 维度：性能（dead invalidation）
> - 证据：`lib/features/progress/progress_provider.dart:102, 130`：
>   ```dart
>   ref.invalidate(recentlyPlayedProvider(null));
>   ```
>   全 lib grep `recentlyPlayedProvider` 除定义处与 `shared/di/providers.dart:148` re-export 外**零消费方**（无任何 UI/Provider watch/read）。每次 10 秒自动保存（`player_provider.dart:266-268`）与暂停/切歌保存都会触发一次对无人订阅的 family 的 invalidate（Riverpod 2.6.1 `container.dart:290` invalidate 对未创建元素是 no-op，故无运行时开销之外的代价）。
> - 现象与取舍：P10 纪律「写一个漏一个」的反面——写了没人读的 invalidate。是历史「最近播放」功能位的预留，还是过度防御待裁决。
> - 修复建议：删除两处 `recentlyPlayedProvider(null)` invalidate，或若确有计划做「最近播放」入口，保留并在 provider 头注释登记用途。

用户裁决：**删 invalidate**（无消费者、无近期功能计划；保留 provider 定义与 di re-export 作为 DAO 查询面，删除纯副作用行）。

### 1.1 这一功能干什么（一句话）

删掉 `upsertProgressProvider` / `clearProgressProvider` 成功路径里对 `recentlyPlayedProvider(null)` 的两行 invalidate——该 family 全项目零消费者，每次进度自动保存/清除都在执行无人读取的失效；删除后写路径 invalidate 集与真实订阅面一致（P10 纪律对齐）。

### 1.2 用户期望的场景

| ID | 你看到的样子 | 期望行为 |
|----|----|----|
| U1 | 正常听歌（每 10 秒自动保存进度、暂停/切歌保存、听完清除进度） | 一切行为与修复前完全一致：恢复对话框、最近播放数据都不受影响 |
| U2 | 开发侧：审计 progress 写路径的 invalidate | 只 invalidate 有真实订阅者的 provider（progressForFileProvider / latestPlayedProgressProvider），没有对空 family 的无效失效 |
| U3 | 未来要做"最近播放"列表 | 重新加回 invalidate 或直接 watch provider 即可，DAO 查询能力（getRecentlyPlayed）原样保留 |

---

## §2 已实现的功能骨架（代码锚点）

### 2.1 文件与分层

| 层 | 文件 | 行数 | 角色 |
|---|---|---|---|
| Provider | `lib/features/progress/progress_provider.dart` | 195 | upsertProgressProvider（:70-105，:102 invalidate 待删）；clearProgressProvider（:108-133，:130 invalidate 待删）；recentlyPlayedProvider 定义（:52-56） |
| Shared-DI | `lib/shared/di/providers.dart` | 250 | re-export recentlyPlayedProvider（:148） |
| Player | `lib/features/player/player_provider.dart` | 401 | saveProgressProvider（:255-256）经 orchestrator.saveProgress → upsertProgressProvider；10s 自动保存（:266-268） |
| 测试 | `test/features/progress/prg_test.dart` | — | PRG-T16 getRecentlyPlayed DAO 锚定（:504-541，走 DAO 不经 provider） |

### 2.2 关键 Provider 表

| Provider 名 | 类型 | 实现位置 | 用途 |
|---|---|---|---|
| upsertProgressProvider | Provider\<void Function({...})\> | progress_provider.dart:70-105 | 写进度：saveProgress + invalidate progressForFile/recentlyPlayed/latestPlayed |
| clearProgressProvider | Provider\<void Function({...})\> | progress_provider.dart:108-133 | 清进度：clearProgress + 同三连 invalidate |
| progressForFileProvider | FutureProvider.family | progress_provider.dart:42-48 | 恢复对话框/播放前的进度查询（真实订阅方，invalidate 保留） |
| recentlyPlayedProvider | FutureProvider.family\<List\<PlayProgress\>, int?\> | progress_provider.dart:52-56 | 最近播放查询（**零消费方**） |
| latestPlayedProgressProvider | FutureProvider\<PlayProgress?\> | progress_provider.dart:60-63 | 启动恢复用（真实订阅方，invalidate 保留） |

### 2.3 状态机图

本功能无状态机，跳过。

---

## §3 行为规约（Given-When-Then）

### 3.1 现有行为（逆抽）

- **[REF-13-S1]** upsertProgressProvider 成功路径 invalidate 三连（含对零消费 family 的 :102）
  ```
  Given upsertProgressProvider 执行成功（service.saveProgress 无异常）
  Then ref.invalidate(progressForFileProvider(...))（:98-101）
  And ref.invalidate(recentlyPlayedProvider(null))（:102）
  And ref.invalidate(latestPlayedProgressProvider)（:103）
  ```
  Code evidence: `lib/features/progress/progress_provider.dart:98-103`

- **[REF-13-S2]** clearProgressProvider 成功路径同结构三连（:130 待删）
  ```
  Given clearProgressProvider 执行成功
  Then ref.invalidate(progressForFileProvider(...))（:126-129）
  And ref.invalidate(recentlyPlayedProvider(null))（:130）
  And ref.invalidate(latestPlayedProgressProvider)（:131）
  ```
  Code evidence: `lib/features/progress/progress_provider.dart:126-131`

- **[REF-13-S3]** recentlyPlayedProvider 全项目零消费方
  ```
  Given grep 全 lib+test recentlyPlayedProvider
  Then 仅命中：定义（progress_provider.dart:52-56）、两处 invalidate（:102/:130）、di re-export（providers.dart:148）
  And 无任何 watch/read（UI、provider、测试均无）
  ```
  Code evidence: grep 全库（2026-08-16 实测）；`lib/shared/di/providers.dart:148`

- **[REF-13-S4]** 写路径的真实触发频率与 DAO 查询能力
  ```
  Given player_provider.dart:266-268 每 10 秒 saveProgressProvider → orchestrator.saveProgress → upsertProgressProvider
  And 暂停/切歌 saveProgress（:275-288 _startPauseSaveProvider）
  And progress_dao.dart:173-181 getRecentlyPlayed（findLatest 复用 :189-193）
  When 听歌 10 分钟
  Then 至少 ~60 次 upsert 执行（其中每次都对无人订阅的 recentlyPlayedProvider(null) 发 invalidate）
  ```
  Code evidence: `lib/features/player/player_provider.dart:266-268, 275-288` + `lib/core/database/dao/progress_dao.dart:173-181, 189-193`

### 3.2 修改方案（status: new）

设计裁决：**删除两处 invalidate 行**，保留 recentlyPlayedProvider 定义 + di re-export + DAO getRecentlyPlayed。理由：
- family 零消费（S3 实证），invalidate 对未创建元素是 no-op，纯属噪音；
- 「最近播放」功能位保留查询能力（DAO+provider 都在），未来建 UI 时 watch 即可，需要刷新再加 invalidate；
- 与 P10 纪律对齐：写路径 invalidate 集 = 真实订阅面。

| 边界情况 | 裁决 |
|---|---|
| 删除后 recentlyPlayedProvider 定义是否保留 | 保留（未来功能位 + DAO 查询的 provider 封装；成本零） |
| di re-export（:148）是否删 | 保留（re-export 不产生副作用，删它反而断未来接入面） |
| progressForFileProvider / latestPlayedProgressProvider invalidate 是否保留 | **必须保留**（真实订阅方：恢复对话框/启动恢复） |
| 测试是否依赖 recentlyPlayedProvider invalidate 行为 | 否（S3 已证 test 零引用） |
| Riverpod 语义：对已创建但无人读的 family invalidate | 同样 no-op 无消费方；删除行为在测试中不可直接观察——用"invalidate 集收敛"静态断言 + 行为回归锚定 |

- **[REF-13-S5]** 删除 upsert/clear 中对 recentlyPlayedProvider(null) 的两行 invalidate （status: new）
  ```
  Given progress_provider.dart:102 与 :130
  When 删除这两行
  Then upsert/clear 成功路径 invalidate 集收敛为 {progressForFileProvider, latestPlayedProgressProvider}
  And 全文件 grep recentlyPlayedProvider 仅剩定义（:52-56）与头注释（若有）
  否定断言:
    - progressForFileProvider / latestPlayedProgressProvider 两行 invalidate 不得被误删（写路径刷新能力保留）
    - recentlyPlayedProvider 定义、di:148 re-export、DAO getRecentlyPlayed（progress_dao.dart:173-181）不得删
    - upsert/clear 的成功/失败分支结构（try-catch + debugPrint，BUG-09 加固）不得改
  ```
  修改点：`lib/features/progress/progress_provider.dart:102, 130` 行删除。

- **[REF-13-S6]** 写路径行为回归：upsert/clear 后 progressForFile/latestPlayed 仍刷新 （status: new）
  ```
  Given upsertProgressProvider 执行成功（fake DAO 记录调用）
  When 断言 invalidate 面
  Then progressForFileProvider / latestPlayedProgressProvider 仍被 invalidate（经既有 prg 测试的恢复/清除流程锚定）
  否定断言:
    - 删除后不得引入任何 catch 行为变化（BUG-09 的 debugPrint 日志仍在）
    - 不得改动 service.saveProgress/clearProgress 的 DAO 调用参数
  ```
  修改点：无（回归断言由 §5.4 门禁测试承担）。

---

## §4 不变量

- **[REF-13-INV1]** 写路径（upsert/clear）invalidate 集 == 真实订阅面（P10 纪律）
  证据：progress_provider.dart:98-101+103 / :126-129+131（改后）+ S3 零消费实证。

- **[REF-13-INV2]** recentlyPlayedProvider 查询能力（DAO getRecentlyPlayed + family 封装 + di re-export）保留为未来功能位
  证据：progress_dao.dart:173-181 + progress_provider.dart:52-56 + providers.dart:148（改后均不动）。

---

## §5 测试规约

### 5.1 现有测试清单

| 测试文件 | 覆盖的 Scenario / INV | 备注 |
|---|---|---|
| test/features/progress/prg_test.dart | REF-13-S4（DAO 能力）、INV2 | PRG-T16 :504-541 getRecentlyPlayed DAO 锚定（provider 不涉）；恢复/清除流程（PRG-T01~T28）锚定 S6 |
| test/features/progress/bug_09_test.dart | REF-13-S6（catch-log 回归） | 写路径 try-catch + debugPrint 锚定，不动 |
| test/features/player/ply_01_test.dart 等 | REF-13-S6 | saveProgress 触发链路（orchestrator）既有锚定，不动 |

### 5.2 测试 ID 派生清单（dev-exe 派发测试 Agent 用）

```
REF-13-S1 … S6        # Scenario（S1~S4 现状锚定，S5~S6 修改目标）
REF-13-INV1 … INV2    # 不变量
```

dev-exe 要求：S5（源静态断言）与 S6（行为回归）与 INV1/2 由 §5.4 门禁文件覆盖。

### 5.3 测试覆盖盲点（dev-plan 写本文档时识别）

| 未覆盖 ID | 现状 | 应补偿方式 |
|---|---|---|
| REF-13-S5（invalidate 收敛） | 无现成断言 | §5.4 门禁文件源扫描：progress_provider.dart 中 `recentlyPlayedProvider(null)` 零命中、`progressForFileProvider` 与 `latestPlayedProgressProvider` invalidate 各 ≥1 处 |
| REF-13-INV1（invalidate 集==订阅面） | 隐性 | 静态断言 + 全 lib grep recentlyPlayedProvider 消费方仍零 |

### 5.4 测试文件位置（spec-scan --gate 硬校验）

命名防撞已核：`test/features/progress/` 现有文件无 ref_13 前缀（ref_13_test.dart 在 test/features/player/ 是旧轮遗留、与本 REF 无关，不可覆盖）。新建：

`test/features/progress/ref_13_recently_played_test.dart`：

| 测试文件 | 覆盖 ID | 说明 |
|---|---|---|
| test/features/progress/ref_13_recently_played_test.dart | REF-13-S5、S6、INV1、INV2 | ①读 progress_provider.dart 源：断言不含 `recentlyPlayedProvider(` 调用（除定义）；断言含 `ref.invalidate(progressForFileProvider(` 与 `ref.invalidate(latestPlayedProgressProvider)` 各 ≥1；②ProviderContainer + fake DAO 跑 upsert/clear，断言 progressForFileProvider / latestPlayedProgressProvider 重读返回新值（刷新保留）；③静态断言 progress_dao.dart 仍含 getRecentlyPlayed（INV2） |

---

## §6 算法样例

本功能为 invalidate 行删除，无纯函数算法样例，跳过。

---

## §7 跨模块影响

用 `cross-imports.sh impact lib/features/progress/progress_provider.dart` 实测（2026-08-16）：引用方为 `lib/features/progress/progress_dialog.dart`（progressResumeProvider 消费）与 player 侧经 shared/di 的桥接（`player_provider.dart:96-100` _Deps.upsertProgress 经 shared/di import 的 upsertProgressProvider）。

| 其它 feature | 影响点 | 影响条件 | 需要补的回归断言 |
|---|---|---|---|
| PLY（player_provider _Deps.upsertProgress / saveProgress 10s 链路） | 每 10s/暂停/切歌触发 upsertProgressProvider | 仅删 :102 invalidate，provider 接口与返回不变 | ply_01/ply_02/orchestrator 既有 saveProgress 测试全绿 |
| PRG（progress_dialog / progressForFile / latestPlayed 消费方） | progressForFileProvider / latestPlayedProgressProvider invalidate 保留 | 恢复对话框与启动恢复刷新面不变 | prg_test 全绿 + ref_13 门禁文件 PASS |
| shared/di（providers.dart:148） | re-export 保留 | 未来功能位 | 无行为变化，编译绿 |

---

## §8 平台特性与手动 QA

设计前已核对 `docs/dev/platform-pitfalls.md`：本修改为 provider 层两行 invalidate 删除，不触 P1~P17 任一条（不涉音频/时序/存储通道；写路径 BUG-09 catch-log 与 10s 自动保存链路均不动）。

**真机风险列**：无——invalidate 对零消费者是 no-op，删除后运行时可观测行为为零变化；恢复进度/自动保存全部由既有 prg/ply 测试在 mock DAO 上覆盖。未来若做「最近播放」UI，需在 provider 头注释登记并补 invalidate（本 spec INV2 已预留）。

本功能不涉及平台原生特性，全部可在 `flutter test` 中验证 → `manual_qa_required = false`。

---

## §9 dev-status.json 条目对照

```json
"REF-13": {
  "spec_file": "docs/features/REF-13.md",
  "spec_anchored_files": [
    "lib/features/progress/progress_provider.dart",
    "lib/shared/di/providers.dart",
    "lib/features/player/player_provider.dart",
    "test/features/progress/prg_test.dart"
  ],
  "scenarios": ["REF-13-S1", "REF-13-S2", "REF-13-S3", "REF-13-S4", "REF-13-S5", "REF-13-S6"],
  "invariants": ["REF-13-INV1", "REF-13-INV2"],
  "algorithms": [],
  "manual_qa_required": false,
  "user_acceptance_text": "见 §1.2"
}
```