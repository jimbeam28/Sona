# BUG-02 — addTracksToPlaylist 缺内存内去重

> 来源：`docs/cr/cr-2026-06-28.md` 第 2.5 BUG-02 / §9.1 B2
> dev-plan 流程：Bug 修复模式（已先写复现测试并确认 FAIL）

---

## §0 头部元数据

```yaml
id: BUG-02
name: addTracksToPlaylist 缺内存内去重
priority: P0
status: active
created_at: 2026-06-28
last_updated: 2026-06-28
spec_anchored_files:
  - lib/features/playlist/domain/playlist_service.dart
cross_module_impacts: []
manual_qa_required: false
```

---

## §1 用户视角（你来扫这一节就够）

### 1.1 这一功能干什么（一句话）

修一个导致**同一个文件被加入播放单两次**的缺陷。

### 1.2 用户期望的场景

| ID | 你看到的样子 | 期望行为 |
|----|----|----|
| U1 | 在"添加曲目"页连续点击同一文件两次，或批量勾选 + 上次选择残留 | 该文件只应在播放单中出现一次 |
| U2 | 同一文件路径在传入 `addTracksToPlaylist` 的 list 中重复 N 次 | 数据库只插入一条记录 |

---

## §2 已实现的功能骨架（代码锚点）

### 2.1 文件与分层

| 层 | 文件 | 行数 | 角色 |
|---|---|---|---|
| Domain | `lib/features/playlist/domain/playlist_service.dart` | 169 | 播放单 CRUD + 去重 + JSON 导入导出 |
| Data | `lib/core/database/dao/playlist_dao.dart` | — | trackExists 查询 |
| 测试 | `test/features/playlist/ref_26_test.dart` | 384 | REF-26 既有覆盖 |
| 测试 | `test/features/playlist/bug_bug02_repro_test.dart` | — | 本 bug 复现测试（FAIL 状态） |

### 2.2 关键 Provider 表

| Provider 名 | 类型 | 实现位置 | 用途 |
|---|---|---|---|
| `playlistServiceProvider` | `Provider<PlaylistService>` | `lib/features/playlist/playlist_provider.dart` | UI 调用 `addTracksToPlaylist` 入口 |

### 2.3 状态机图

N/A — 纯 service 缺陷。

---

## §3 行为规约（Given-When-Then）

### 3.1 现有行为（BUG 行为）

- **[BUG-02-S1]** 输入 list 中同一文件出现两次 → 落库两行
  ```
  Given playlistId 已创建
    And 调用 addTracksToPlaylist(playlistId, [f, f]) —— f 的 path 相同
  When  await service.addTracksToPlaylist(...)
  Then  当前实现 yield 库中两条相同 filePath 记录
  ```
  Code evidence: `lib/features/playlist/domain/playlist_service.dart:64-81`

### 3.2 修复后行为

- **[BUG-02-S2]** 内存内去重防止同批次重复 (status: new)
  ```
  Given 同一输入 list 内含 N >= 2 个同 path 文件
  When  调用 addTracksToPlaylist
  Then  仅插入一条 filePath 记录
  And   其余同 path 项被内存 seen 集合过滤
  否定断言:
    - 同 path 项不应多次插入 DB（trackExists 已返回 false 也仍不可重复插）
    - 不应跳过同批次首次出现以外的不同 path 文件
    - 不应改变 DB 中已存在同 path 文件的状态（DB 端 trackExists=true 的项应跳过——这是既有行为）
  ```
  Code evidence: `lib/features/playlist/domain/playlist_service.dart:64-81`

- **[BUG-02-S3]** importPlaylist 内存去重模式保持一致 (status: modified)
  ```
  Given 修复后内部使用 seen.add 模式
  Then  与已有 importPlaylist 的去重模式（lib/features/playlist/domain/playlist_service.dart:152-161）一致
  否定断言:
    - 不应让两个分支去重逻辑出现分歧（同 path / 空 path 处理对齐 importPlaylist）
  ```

---

## §4 不变量

- **[BUG-02-INV1]** 调用 addTracksToPlaylist 后，DB 在该 playlistId 下对每个 filePath 至多 1 行
  证据：`lib/features/playlist/domain/playlist_service.dart:67-77`（修复区域）

- **[BUG-02-INV2]** 跨批次与同批次去重规则一致：DB 已有的 path 与内存中已 add 的 path 均被视为重复
  证据：`lib/features/playlist/domain/playlist_service.dart:152`（importPlaylist 中 `seen.add` 模式参考）

---

## §5 测试规约

### 5.1 现有测试清单

| 测试文件 | 覆盖的 Scenario / INV | 备注 |
|---|---|---|
| `test/features/playlist/ref_26_test.dart` | REF-26-T02 单次/二次调用 DB 去重 | 未覆盖"同批次内重复" |
| `test/features/playlist/bug_bug02_repro_test.dart` | BUG-02-S1/S2/S3 | 复现测试，FAIL 状态 |

### 5.2 测试 ID 派生清单

```
BUG-02-S1     # 现有 BUG 行为，修复后 PASS
BUG-02-S2 S3  # 新规约断言
BUG-02-INV1 INV2
```

### 5.3 测试覆盖盲点

| 未覆盖 ID | 现状 | 应补偿方式 |
|---|---|---|
| BUG-02-S2 | 复现测试同路径，修复后 expect(tracks.length, 1) PASS | — |
| BUG-02-S3 | 无 | 在 ref_26 新增"同批次含 f / 已存 f / 新 g"三元用例 |
| BUG-02-INV1 | 复现测试有 1→3 → 2 用例 | — |
| BUG-02-INV2 | 无 | 跨批次再同批：先 add([f]) 再 add([f, g])，期望 DB 仅 2 行 |

---

## §6 算法样例

```
ALG addTracksToPlaylist:
  输入: [f, f]                                  → 期望: 1 row 插入
  输入: [f, f, f, g] (f/g path 不同)            → 期望: 2 rows 插入
  输入: [f] (DB 已有 f)                          → 期望: 0 rows 插入（既有 DB 去重，保留）
  输入: [f, f] 且 DB 已有 f                       → 期望: 0 rows 插入
  输入: []                                       → 期望: 0 rows 插入，不触发 addTracks
```

---

## §7 跨模块影响

无外部 feature 依赖此方法的去重行为。仅 UI 层 `add_tracks_browser.dart` 调用入口。

---

## §8 平台特性与手动 QA

本功能不涉及平台原生特性，全部可在 `flutter test` 中验证，无需手动 QA。

---

## §9 dev-status.json 条目对照

见统一更新：`docs/dev/dev-status.json`。

---

## §10 changelog

- 2026-06-28: 创建 BUG-02 spec（基于 cr.md B2 + 复现测试已写且 FAIL） (status: new)