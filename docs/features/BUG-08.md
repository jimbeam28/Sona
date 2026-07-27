# BUG-08 — 播放单批添加 ≥40 曲目显示乱序 + 拖拽移错

> 来源：`docs/cr/cr-20260724-0110.md` LIST1
> dev-plan 流程：Bug 修复模式

---

## §0 头部元数据

```yaml
id: BUG-08
name: 播放单批添加 ≥40 曲目显示乱序 + 拖拽移错
priority: P1
status: draft
created_at: 2026-07-27
last_updated: 2026-07-27
spec_anchored_files:
  - lib/features/playlist/domain/playlist_service.dart
  - lib/features/playlist/playlist_provider.dart
  - lib/core/database/dao/playlist_dao.dart
cross_module_impacts: []
parent_feature: Playlist
manual_qa_required: false
```

---

## §1 用户视角

### 1.0 原始需求

> cr-20260724-0110.md LIST1：批内所有曲目共享同一 DateTime.now() 时间戳，Dart sort 非稳定，≥40 曲目时显示乱序；拖拽 reorder 按 DAO 的 added_at ASC, id ASC 基准序操作，与 UI 展示序不一致导致移错曲目。

### 1.1 这一功能干什么（一句话）

修复批量添加曲目时因时间戳相同 + 排序无 tiebreak 导致的显示乱序和拖拽移错。

### 1.2 用户期望的场景

| ID | 你看到的样子 | 期望行为 |
|----|----|----|
| U1 | 全选 50 首有声书章节添加到播放单 | 详情页第 1 位显示第 1 章、第 50 位显示第 50 章（展示序==插入序） |
| U2 | 接上态拖动 displayed 首项到第 3 位 | 第 1 章移到第 3 位，其余顺序不变 |

---

## §2 已实现的功能骨架

### 2.1 文件与分层

| 层 | 文件 | 行数 | 角色 |
|---|---|---|---|
| Domain | `lib/features/playlist/domain/playlist_service.dart` | ~165 | addTracksToPlaylist 批添加 |
| Provider | `lib/features/playlist/playlist_provider.dart` | ~80 | _trackSortCompare 排序比较器 |
| DAO | `lib/core/database/dao/playlist_dao.dart` | ~120 | addTracks + reorderTrack |

---

## §3 行为规约

### 3.1 修复后行为

- **[BUG-08-S1]** provider 排序比较器加 id tiebreak (`status: new`)
  ```
  Given 两曲目 addedAt 相同
  When  _trackSortCompare(a, b, TrackSortOption.addedAsc)
  Then  按 a.id!.compareTo(b.id!) 作为第二排序键
  否定断言:
    - 不返回 0（compareTo 相等时必须有 tiebreak）
    - 不改变 addedAt 不同时的一级排序结果
  ```
  Code evidence: `lib/features/playlist/playlist_provider.dart:48-52`（_trackSortCompare 无 id tiebreak）

  **修改指令：**

  **文件：** `lib/features/playlist/playlist_provider.dart:48-57`

  **当前代码：**
  ```dart
  int _trackSortCompare(PlaylistTrack a, PlaylistTrack b, TrackSortOption sort) {
    switch (sort) {
      case TrackSortOption.addedAsc:
        return a.addedAt.compareTo(b.addedAt);
      case TrackSortOption.nameAsc:
        return a.fileName.compareTo(b.fileName);
      case TrackSortOption.nameDesc:
        return b.fileName.compareTo(a.fileName);
    }
  }
  ```

  **修改为：**
  ```dart
  int _trackSortCompare(PlaylistTrack a, PlaylistTrack b, TrackSortOption sort) {
    final int primary;
    switch (sort) {
      case TrackSortOption.addedAsc:
        primary = a.addedAt.compareTo(b.addedAt);
      case TrackSortOption.nameAsc:
        primary = a.fileName.compareTo(b.fileName);
      case TrackSortOption.nameDesc:
        primary = b.fileName.compareTo(a.fileName);
    }
    if (primary != 0) return primary;
    final aId = a.id;
    final bId = b.id;
    if (aId != null && bId != null) return aId.compareTo(bId);
    if (aId != null) return -1;
    if (bId != null) return 1;
    return 0;
  }
  ```

  **边界决策：**
  - addedAt 不同 → 返回一级排序结果，不走 tiebreak
  - addedAt 相同且两 id 均非 null → 按 id ASC 排序（与 DAO `ORDER BY added_at ASC, id ASC` 一致）
  - addedAt 相同但某一 id 为 null → null id 排后面（`aId != null → -1` 表示 a 排前）
  - addedAt 相同且两 id 均为 null → 返回 0（极端情况，两 track 完全等价）
  - 空列表 → sort 不调用比较器，无影响
  - 单 track → sort 不调用比较器，无影响

  **测试文件：** `test/features/playlist/bug_08_sort_timestamp_test.dart`（避免与旧 BUG-08 测试冲突）

- **[BUG-08-S2]** 批添加让时间戳单调递增 (`status: new`)
  ```
  Given 批量添加 N 首曲目
  When  addTracksToPlaylist 构造 PlaylistTrack 列表
  Then  每首曲目的 addedAt 在基础时间戳上 +index 毫秒，保证单调
  否定断言:
    - 不全部共享同一 DateTime.now()（当前 BUG 行为）
    - 不改变去重逻辑（seen 集合）
  ```
  Code evidence: `lib/features/playlist/domain/playlist_service.dart:64-79`（now 一次性取值，所有曲目共享）

  **修改指令：**

  **文件：** `lib/features/playlist/domain/playlist_service.dart:64-79`

  **当前代码：**
  ```dart
  Future<void> addTracksToPlaylist(int playlistId, List<NasFile> files) async {
    final now = DateTime.now();
    final seen = <String>{};
    final tracks = <PlaylistTrack>[];
    for (final file in files) {
      if (file.path.isEmpty || !seen.add(file.path)) continue;
      final exists = await _dao.trackExists(playlistId, file.path);
      if (!exists) {
        tracks.add(PlaylistTrack(
          playlistId: playlistId,
          filePath: file.path,
          fileName: file.name,
          addedAt: now,
        ));
      }
    }
  ```

  **修改为：**
  ```dart
  Future<void> addTracksToPlaylist(int playlistId, List<NasFile> files) async {
    final baseTime = DateTime.now();
    final seen = <String>{};
    final tracks = <PlaylistTrack>[];
    var index = 0;
    for (final file in files) {
      if (file.path.isEmpty || !seen.add(file.path)) continue;
      final exists = await _dao.trackExists(playlistId, file.path);
      if (!exists) {
        tracks.add(PlaylistTrack(
          playlistId: playlistId,
          filePath: file.path,
          fileName: file.name,
          addedAt: baseTime.add(Duration(milliseconds: index)),
        ));
        index++;
      }
    }
  ```

  **边界决策：**
  - 空 files 列表 → for 循环不执行，tracks 为空，不触发 DAO 插入（行为不变）
  - 单 track → index=0，addedAt = baseTime + 0ms（等价于原来的 now）
  - 去重跳过的文件 → 不增加 index（只有实际插入的 track 才递增 index，保证单调性）
  - ≥40 track → 每首间隔 1ms，总跨度 ≤40ms，远小于用户感知阈值
  - 去重逻辑（seen 集合）→ 不受影响，仍在 timestamp 构造之前执行

  **测试文件：** `test/features/playlist/bug_08_sort_timestamp_test.dart`

---

## §4 不变量

- **[BUG-08-INV1]** 展示序 == DAO reorder 基准序（added_at ASC, id ASC）
  证据：`playlist_dao.dart:103`（reorderTrack orderBy）, `playlist_provider.dart:48-52`（UI 排序，修复后一致）

---

## §5 测试规约

### 5.2 测试 ID 派生清单

```
BUG-08-S1 S2          # tiebreak + 单调时间戳
BUG-08-INV1           # 展示序==DB序
```

### 5.3 测试覆盖盲点

| 未覆盖 ID | 现状 | 应补偿方式 |
|---|---|---|
| BUG-08-S1 | provider 排序测试只用 n=3 | 补 ≥40 同批添加 → 展示序==插入序 |
| BUG-08-S2 | 测试手工递增时间戳（TST-T82） | 补等值时间戳下 reorder UI/DB 序一致 |

### 5.4 测试文件位置

| 测试 ID | 文件路径 |
|---|---|
| BUG-08-S1 | `test/features/playlist/bug_08_sort_timestamp_test.dart` |
| BUG-08-S2 | `test/features/playlist/bug_08_sort_timestamp_test.dart` |
| BUG-08-INV1 | `test/features/playlist/bug_08_sort_timestamp_test.dart` |

---

## §7 跨模块影响

无跨模块影响。修复局限在 playlist 模块内部。

---

## §8 平台特性与手动 QA

本功能不涉及平台原生特性，全部可在 `flutter test` 中验证。

---

## §9 dev-status.json 条目对照

见统一更新：`docs/dev/dev-status.json`。

---

## §10 changelog

- 2026-07-27: 创建 BUG-08 spec（基于 cr-20260724-0110.md LIST1）
