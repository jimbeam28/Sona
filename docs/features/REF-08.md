# REF-08 — PlaylistService 时钟注入统一（服务层 DateTime.now() → 注入时钟）

## §0 头部元数据

```yaml
id: REF-08
name: PlaylistService 注入 now provider（createPlaylist/addTracksToPlaylist/importPlaylist）
priority: P2
status: active
created_at: 2026-08-16
last_updated: 2026-08-16
spec_anchored_files:
  - lib/features/playlist/domain/playlist_service.dart
  - lib/core/database/dao/playlist_dao.dart
cross_module_impacts: [PLT]   # playlist 自身（service 构造签名 + provider 装配 + DAO 时间戳语义）
manual_qa_required: false     # 纯 Dart 构造注入，全可单测，不涉平台原生
```

---

## §1 用户视角

### 1.0 原始需求（用户原话逐字记录）

来源：`docs/cr/cr-20260816-0804-connection-playlist.md` D2（cr 复核分流，用户裁决"修"→ 转 REF 需求流程，无复现测试要求）：

> #### D2. 服务层直接 DateTime.now() 绕过 DAO 注入时钟（BUG-26-S4 模式只生效一半）
> - 类型 / 严重度 / 维度：DESIGN / Minor / 可测性（P16 now 注入纪律）
> - 证据：`lib/features/playlist/domain/playlist_service.dart:36,70,166`（createPlaylist/addTracksToPlaylist/importPlaylist 各自 `DateTime.now()`）；对比 `playlist_dao.dart:13-19` 与 `connection_dao.dart:24-28` 已按 BUG-26-S4 注入可测时钟——但 service 算出的 createdAt/addedAt 直接传给 DAO，DAO 的 `insertPlaylist`/`addTracks` 不覆盖这两个时间戳（playlist_dao.dart:59-64,93-102），故注入时钟只对 update/updatePlaylist/reorderTrack 生效
> - 现象：时间相关测试（如 BUG-08 单调时间戳）只能靠真实时钟跑（bug_08_sort_timestamp_test 即如此），无法用固定时钟精确断言；非缺陷，属测试性不一致。
> - 修复建议：service 构造注入 now provider（与 DAO 同款），或 DAO insert 路径接管时间戳。

用户裁决：**service 构造注入 now provider（与 DAO 同款）**——不采用"DAO insert 接管时间戳"（该方案会改 DAO 契约语义，且 Playlist/PlaylistTrack model 的 createdAt/addedAt 字段将被忽略，改动面更大）。

### 1.1 这一功能干什么（一句话）

把播放单服务层三处"取当前时间"改为从构造函数注入的时钟读取，与 DAO 层已有的注入时钟（BUG-26-S4）同一模式——测试可以用固定时钟精确断言创建/加曲目/导入的时间戳，生产行为不变。

### 1.2 用户期望的场景

| ID | 你看到的样子 | 期望行为 |
|----|----|----|
| U1 | 正常使用：新建播放单、往播放单加曲目、导入播放单 | 一切如常——播放单创建时间、曲目加入时间照常写入，列表排序（按创建时间）不变 |
| U2 | 对播放单重命名 | 修改时间更新（现状保持，走 DAO 注入时钟路径，本修改不触碰） |
| U3 | （开发者视角）写测试代码时注入固定时钟 | 能精确断言播放单创建时间/曲目加入时间等于注入值，不再依赖真实时钟（修复前做不到） |

---

## §2 已实现的功能骨架（代码锚点）

### 2.1 文件与分层

| 层 | 文件 | 行数 | 角色 |
|---|---|---|---|
| Domain | `lib/features/playlist/domain/playlist_service.dart` | 203 | `createPlaylist`（35-42，`final now = DateTime.now();` :36）、`addTracksToPlaylist`（65-88，`final baseTime = DateTime.now();` :70 + BUG-08-S2 单调时间戳 :81）、`importPlaylist`（147-202，`final now = DateTime.now();` :166） |
| Core | `lib/core/database/dao/playlist_dao.dart` | 205 | `_clock` 注入（13-19，BUG-26-S4）：仅 `updatePlaylist`（:81 `map['updated_at'] = _clock()...`）与 `reorderTrack`（:193 `final base = _clock()...`）使用；`insertPlaylist`（59-64）与 `addTracks`（93-102）不覆盖 model 时间戳（`map.remove('id')` 后原样 insert） |
| Provider | `lib/features/playlist/playlist_provider.dart` | 167 | `playlistServiceProvider`（22-24）：`PlaylistService(dao: ref.read(playlistDaoProvider))`——不传 clock，默认 DateTime.now |
| Model | `lib/shared/models/playlist.dart` | 134 | `Playlist`（6-70）：createdAt/updatedAt 必填（:10-11），toMap 写 `created_at`/`updated_at` 毫秒（:35-36）；`PlaylistTrack`（72-134）：addedAt |
| UI | `lib/features/playlist/playlist_detail_screen.dart` | ~280 | 重命名（:276）：`playlist.copyWith(name: newName, updatedAt: DateTime.now())`——UI 层取时，但 DAO `updatePlaylist`（playlist_dao.dart:81）以 `_clock()` 覆盖 `updated_at`，该值不落库（见 §3.1 边界说明） |

### 2.2 关键 Provider 表

| Provider 名 | 类型 | 实现位置 | 用途 |
|---|---|---|---|
| playlistDaoProvider | Provider<IPlaylistDao> | playlist_provider.dart:20 | DAO 装配（默认构造，clock 不注入——测试直构 PlaylistDao(clock:)） |
| playlistServiceProvider | Provider<PlaylistService> | playlist_provider.dart:22-24 | Service 装配（修改后仍不传 clock，默认 DateTime.now） |

### 2.3 状态机图

本功能无状态机，跳过。

---

## §3 行为规约（Given-When-Then）

### 3.1 现有行为（逆抽）

- **[REF-08-S1]** 服务层三处直接 `DateTime.now()`，DAO 注入时钟对 insert 路径无效
  ```
  Given PlaylistService(dao: PlaylistDao(clock: fixedClock))（DAO 注入时钟，service 未注入）
  When createPlaylist('X') / addTracksToPlaylist / importPlaylist
  Then createdAt/updatedAt/addedAt 来自 DateTime.now()（真实时钟，DAO 时钟被绕过）
  And DAO insertPlaylist（playlist_dao.dart:59-64）/ addTracks（:93-102）不覆盖这些时间戳 → 落库值 = 真实时钟
  ```
  Code evidence:
  - `lib/features/playlist/domain/playlist_service.dart:36`（createPlaylist `final now = DateTime.now();`）、`:70`（addTracksToPlaylist `final baseTime = DateTime.now();`）、`:166`（importPlaylist `final now = DateTime.now();`）
  - `lib/core/database/dao/playlist_dao.dart:59-64`（insertPlaylist `map.remove('id')` 后 `db.insert`，不写 updated_at 覆盖）、`:93-102`（addTracks 同）
  - 对比：`playlist_dao.dart:13-19`（_clock 注入）、`:81`（updatePlaylist 用 _clock）、`:193`（reorderTrack 用 _clock）——注入时钟只对 update/reorder 生效（cr-0804 D2 原文确认）

- **[REF-08-S2]** addTracksToPlaylist 的单调时间戳语义（BUG-08-S2）：baseTime 读一次，逐条 `baseTime.add(milliseconds: tracks.length)`
  ```
  Given 一次 addTracksToPlaylist 传入 3 个文件（含 1 个重复 path）
  When 添加曲目
  Then baseTime 只读一次（DateTime.now() :70）
  And 实际插入的 2 条 addedAt = baseTime.add(0ms) / baseTime.add(1ms)（单调递增）
  And 去重跳过的文件不消耗序号（tracks.length 只计已插入，:81）
  ```
  Code evidence: `lib/features/playlist/domain/playlist_service.dart:65-88`（:70 baseTime + :81 `baseTime.add(Duration(milliseconds: tracks.length))` + 去重 :74）
  测试锚定：`test/features/playlist/bug_08_sort_timestamp_test.dart`（BUG-08 单调时间戳，靠真实时钟跑——cr-0804 D2 原文确认）。

### 3.2 修改方案（status: new）

设计裁决（用户裁决"service 构造注入 now provider，与 DAO 同款"）：

| 边界情况 | 裁决 |
|---|---|
| 构造参数形态 | 与 `PlaylistDao`（playlist_dao.dart:13-19）同款：`PlaylistService({IPlaylistDao? dao, DateTime Function()? clock})`，`_clock = clock ?? DateTime.now`——不传时生产行为逐字节不变 |
| 每次方法调用取时次数 | 与现状一致：createPlaylist 1 次（:36）、addTracksToPlaylist 1 次（:70，批量内共享 baseTime，BUG-08-S2 单调性保持）、importPlaylist 1 次（:166）——不得逐条/逐字段多取时 |
| createdAt 与 updatedAt 是否同值 | 保持现状：同一 `now` 同时赋给 createdAt 与 updatedAt（:39-40） |
| provider 装配（playlist_provider.dart:22-24） | **不改**：仍 `PlaylistService(dao: ...)` 不传 clock（生产默认 DateTime.now）；测试直构 `PlaylistService(dao: dao, clock: fixed)` 覆盖 |
| DAO insert 路径 | **不改**：DAO 仍不覆盖 model 时间戳（playlist_dao.dart:59-64/:93-102）——insert 路径的时间戳权威归 service 注入时钟 |
| DAO 注入时钟与 service 注入时钟不一致时 | 允许（各自负责自己的路径：service 管 insert 的 createdAt/addedAt，DAO 管 update/reorder 的 updated_at）；无跨层一致性要求 |
| playlist_detail_screen.dart:276 重命名路径（UI 层 DateTime.now()） | **不改**：该值随 updatePlaylist 传入但被 DAO `updatePlaylist` 的 `_clock()` 覆盖（playlist_dao.dart:81 `map['updated_at'] = _clock()...`），不落库；属 UI 层既有行为，不在 cr D2 范围（cr 证据仅列 service :36/:70/:166） |

- **[REF-08-S3]** PlaylistService 构造注入时钟；createPlaylist 用 `_clock()` 取时 （status: new）
  ```
  Given PlaylistService(dao: PlaylistDao(clock: daoClock, ...), clock: fixedClock)（fixedClock 恒返 2026-01-01 00:00:00.000）
  When createPlaylist('X')
  Then _clock() 取时一次 → now = fixedClock
  And Playlist(createdAt: now, updatedAt: now) 写入 DAO（:37-41）
  And findAllPlaylists 读回 createdAt/updatedAt == fixedClock 值
  否定断言:
    - 不得读取真实时钟（断言落库时间戳精确等于 fixedClock，非 DateTime.now() 附近值）
    - _clock() 不得被调用多次（计数时钟断言 == 1）
    - 返回 id 不受影响（> 0）
  ```
  **修改点 1**：`lib/features/playlist/domain/playlist_service.dart:25-42` —— 构造器 + createPlaylist：
  ```dart
  // 修改前（25-28 行构造器 + 36 行取时）:
  class PlaylistService {
    final IPlaylistDao _dao;

    PlaylistService({IPlaylistDao? dao}) : _dao = dao ?? PlaylistDao();
    ...
    Future<int> createPlaylist(String name) {
      final now = DateTime.now();
  // 修改后:
  class PlaylistService {
    final IPlaylistDao _dao;

    /// Injectable "now" provider (REF-08, BUG-26-S4 同款模式). Defaults to
    /// [DateTime.now] so production behaviour is unchanged; tests may inject
    /// a fixed clock. Insert-path timestamps (createdAt/addedAt) are decided
    /// HERE — the DAO's own clock only covers update/reorder paths
    /// (playlist_dao.dart:81/:193).
    final DateTime Function() _clock;

    PlaylistService({IPlaylistDao? dao, DateTime Function()? clock})
        : _dao = dao ?? PlaylistDao(),
          _clock = clock ?? DateTime.now;
    ...
    Future<int> createPlaylist(String name) {
      final now = _clock();
  ```

- **[REF-08-S4]** addTracksToPlaylist 改用 `_clock()`，批量单调语义保持 （status: new）
  ```
  Given PlaylistService(dao: ..., clock: fixedClock)，fixedClock 恒返 2026-01-02 12:00:00.000
  When addTracksToPlaylist(id, [A, B, A])（A 重复）
  Then _clock() 取时一次 → baseTime = fixedClock
  And B 的 addedAt = baseTime.add(0ms)、A（第二次）被去重跳过
  And 落库两条 addedAt 严格单调（BUG-08-S2 语义在注入时钟下保持）
  否定断言:
    - _clock() 不得逐条调用（计数时钟断言 == 1，含去重文件也不多取时）
    - 去重行为不得改变（重复 path 只插入 1 条，:74）
    - 空 files 列表时不调用 _clock()（`tracks.isEmpty` → 无取时副作用，:70 在循环前——实现时保持现状位置即可）
  ```
  **修改点 2**：`lib/features/playlist/domain/playlist_service.dart:70`：
  ```dart
  // 修改前（70 行）:
  final baseTime = DateTime.now();
  // 修改后:
  final baseTime = _clock();
  ```

- **[REF-08-S5]** importPlaylist 改用 `_clock()` （status: new）
  ```
  Given PlaylistService(dao: ..., clock: fixedClock)，fixedClock 恒返 2026-01-03 08:00:00.000
  When importPlaylist('{"name":"Imported","tracks":[{"filePath":"/a.mp3","fileName":"a.mp3"}]}')
  Then _clock() 取时一次 → now = fixedClock（:166）
  And 播放单行 createdAt/updatedAt == fixedClock；曲目 addedAt == fixedClock.add(0ms)（:178）
  否定断言:
    - 落库时间戳精确等于 fixedClock（不得混入真实时钟）
    - 空 tracks 导入时 _clock() 仍只调用一次（:166 在 tracks 解析前——现状位置保持）
    - 名称归一（REF-07）与结构健壮性（BUG-25-S1）行为不受影响
  ```
  **修改点 3**：`lib/features/playlist/domain/playlist_service.dart:166`：
  ```dart
  // 修改前（166 行）:
  final now = DateTime.now();
  // 修改后:
  final now = _clock();
  ```

- **[REF-08-S6]** 生产装配默认时钟不变（playlistServiceProvider 不传 clock） （status: new）
  ```
  Given playlistServiceProvider（playlist_provider.dart:22-24）
  When 读取该 provider
  Then 构造 PlaylistService(dao: ref.read(playlistDaoProvider))——不传 clock 参数 → _clock = DateTime.now
  And 生产行为与修复前一致（真实时钟）
  否定断言:
    - 生产装配不得注入固定时钟（源码级断言：playlist_provider.dart:22-24 构造调用无 clock 实参）
    - 默认构造 PlaylistService() 的 _clock 必为 DateTime.now（构造后行为 = 修复前）
  ```
  Code evidence（修改点）: 修改点 1 构造器 `clock ?? DateTime.now` + `playlist_provider.dart:22-24`（不改——负断言锚定装配不传 clock）。

---

## §4 不变量

- **[REF-08-INV1]** 播放单/曲目 insert 路径的时间戳由 service 的注入时钟唯一决定（DAO insert 不覆盖）
  证据：修改点 1~3（service 用 `_clock()`）+ `playlist_dao.dart:59-64`/`:93-102`（insert 不覆盖 model 时间戳）。insert 路径单一时钟权威，杜绝双时钟竞态。

- **[REF-08-INV2]** 同一次 addTracksToPlaylist/importPlaylist 批内 addedAt 严格单调（BUG-08-S2 语义）
  证据：`playlist_service.dart:81`/`:178`（`baseTime.add(Duration(milliseconds: tracks.length))`，序号只计实际插入数）+ 修改点 2/3（baseTime/now 仍单次取时）。

---

## §5 测试规约

### 5.1 现有测试清单

| 测试文件 | 覆盖的 Scenario / INV | 备注 |
|---|---|---|
| test/features/playlist/bug_08_sort_timestamp_test.dart | REF-08-S1（现状）、REF-08-INV2 | BUG-08 单调时间戳锚定；修复后保持绿（真实时钟下语义不变）；修复后可增加注入时钟版（§5.3 盲点） |
| test/features/playlist/ref_26_test.dart | REF-08-S1 侧面 | 直构 `PlaylistService(dao: ...)`（单参），新增可选参数 → 编译兼容，保持绿 |
| test/features/playlist/bug_bug25_repro_test.dart / bug_bug02_fixed_test.dart / ply_10_test.dart | REF-08-S1 侧面 | 同上，全部单参构造，兼容保持绿 |

### 5.2 测试 ID 派生清单（dev-exe 派发测试 Agent 用）

```
REF-08-S1 … S6        # Scenario（S1/S2 现状锚定，S3~S6 修复目标）
REF-08-INV1 … INV2    # 不变量
```

dev-exe 要求：S1/S2 由既有测试 + §5.4 门禁现状断言覆盖；S3~S6 与 INV1/2 由 §5.4 门禁文件覆盖。

### 5.3 测试覆盖盲点（dev-plan 写本文档时识别）

| 未覆盖 ID | 现状 | 应补偿方式 |
|---|---|---|
| REF-08-S3~S5（注入时钟精确断言） | 零锚定（全部时间戳测试靠真实时钟） | §5.4 门禁文件注入固定时钟断言精确值 |
| REF-08-S6（生产装配不传 clock） | 零锚定 | §5.4 门禁文件源码级断言（读 playlist_provider.dart:22-24，手法同 set_01 INV3） |
| REF-08-S4 否定面（去重文件不多取时 / 空列表不取时） | 零锚定 | §5.4 门禁文件用计数时钟断言 |

### 5.4 测试文件位置（spec-scan --gate 硬校验）

新建：`test/features/playlist/ref_08_clock_injection_test.dart`（PlaylistService + PlaylistDao(clock:) + 内存测试库，手法同 ref_26_test/bug_08_sort_timestamp_test；命名已核实与既有文件无冲突）

| 测试文件 | 覆盖 ID | 说明 |
|---|---|---|
| test/features/playlist/ref_08_clock_injection_test.dart | REF-08-S1、S2、S3、S4、S5、S6、REF-08-INV1、REF-08-INV2 | 门禁：dev-exe 修复后必须 PASS（cov-gate 内） |
| test/features/playlist/bug_08_sort_timestamp_test.dart / ref_26_test.dart / bug_bug25_repro_test.dart / ply_10_test.dart | REF-08-S1（现状回归） | 既有文件，断言不变，修复后保持绿 |

---

## §6 算法样例

本 REF 不涉纯函数算法（取时与单调偏移均为既有逻辑，偏移公式见 INV2 证据），跳过。

---

## §7 跨模块影响

`bash cross-imports.sh impact lib/features/playlist/domain/playlist_service.dart`（2026-08-16）→ 引用方：

| 其它 feature | 影响点 | 影响条件 | 需要补的回归断言 |
|---|---|---|---|
| Playlist（playlist_provider.dart:22-24） | playlistServiceProvider 装配 | service 构造签名新增可选参数 → 现有 `PlaylistService(dao: ...)` 调用编译兼容；装配不传 clock（S6） | ply_10 import/CRUD 链路用例保持绿；ref_08 门禁 S6 PASS |
| Playlist UI（playlist_detail_screen.dart:276） | 重命名路径的 UI 层 DateTime.now() | **不改**（DAO updatePlaylist :81 以自身 _clock 覆盖 updated_at，该值不落库） | 既有重命名测试保持绿 |
| Core DAO（playlist_dao.dart:13-19/:59-64/:81/:93-102/:193） | 零改动 | 无（insert 不覆盖语义是 INV1 依赖，不改） | bug_08_sort_timestamp_test / ref_26 保持绿 |
| 桥接（shared/di/providers.dart:207-228） | playlist 桥接面 | 无（provider 名不变） | 编译 + analyze 0 warning |
| BUG-08 链路 | 单调时间戳语义 | 修改点 2/3 保持单次取时 + `tracks.length` 偏移 | bug_08_sort_timestamp_test 保持绿 |
| BUG-26-S4 模式 | DAO 注入时钟先例 | 本 REF 是同一模式的 service 侧补齐 | 无新断言（模式一致性由 ref_08 门禁体现） |

---

## §8 平台特性与手动 QA

设计前已逐条核对 `docs/dev/platform-pitfalls.md`：
- **P16（now 注入纪律）**：本 REF 即 P16"需要当前时刻的逻辑注入 now provider（可测），不直接 DateTime.now()"在 playlist 服务层的落地——注入模式与 `playlist_dao.dart:13-19`/`connection_dao.dart:24-28`（BUG-26-S4）同款；取时结果仍为 DateTime 对象（毫秒精度字段由 model toMap 截断，playlist.dart:35-36），无精度截断问题。
- 其余条目（P1~P15、P17）均不触及：不涉音频/生命周期/并发/平台通道/超时分层。

**真机风险列**：

| 风险 | 近似测试方案 | 测不了 → 进 mqa-backlog |
|---|---|---|
| 无（纯构造注入，生产路径默认时钟逐字节不变；时间戳写入行为由注入时钟单测全覆盖） | — | 无 |

本功能不涉及平台原生特性，全部可在 `flutter test` 中验证 → `manual_qa_required = false`。

---

## §9 dev-status.json 条目对照

```json
"REF-08": {
  "spec_file": "docs/features/REF-08.md",
  "spec_anchored_files": [
    "lib/features/playlist/domain/playlist_service.dart",
    "lib/core/database/dao/playlist_dao.dart"
  ],
  "scenarios": ["REF-08-S1", "REF-08-S2", "REF-08-S3", "REF-08-S4", "REF-08-S5", "REF-08-S6"],
  "invariants": ["REF-08-INV1", "REF-08-INV2"],
  "algorithms": [],
  "manual_qa_required": false,
  "user_acceptance_text": "见 §1.2"
}
```
