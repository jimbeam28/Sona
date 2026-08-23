# BUG-22 — deletePlaylist 后曲目 family 缓存不失效，幽灵数据滞留

```yaml
id: BUG-22
name: deletePlaylist 漏 invalidate playlistTracksProvider(id)，keepAlive 缓存滞留已删数据
priority: P3
status: active
created_at: 2026-08-22
last_updated: 2026-08-22
spec_anchored_files:
  - lib/features/playlist/playlist_provider.dart
cross_module_impacts: []
parent_feature: Playlist
manual_qa_required: false
```

---

## §1 用户视角

### 1.0 原始需求（来源逐字记录）

> 来源：docs/cr/cr-20260822-2051.md F4（走查发现，复核确认仍存在）。
>
> "复现路径（条件化）：删除播放单 N → 内存中 playlistTracksProvider(N) 永久持有已删曲目快照；若未来任何入口以同 id 再读该 provider（深链/调试工具），读到的是幽灵数据而非空列表。"
>
> 处置裁决（2026-08-22 cr 复核）：FRAGILE/Minor，用户选定进入 dev-plan Bug 流程第一批。

### 1.1 一句话

删除播放单后，它的曲目缓存必须一并作废——不允许内存里留一份"看起来还存在"的幽灵曲目列表。

### 1.2 用户期望的场景

| ID | 你看到的样子 | 期望行为 |
|----|----|----|
| U1 | 删除一个播放单 | 列表立即消失（现状已正确），且任何途径再查询该播放单的曲目都得到空 |
| U2 | 删除 A 播放单后继续使用 B 播放单 | B 的曲目列表与删除前完全一致 |

---

## §2 已实现骨架（逆抽锚点）

| 层 | 文件 | 角色 |
|---|---|---|
| Provider | lib/features/playlist/playlist_provider.dart | :81-88 playlistTracksProvider（非 autoDispose family，元素创建后永生直至显式 invalidate）；:101-107 deletePlaylistProvider 只 invalidate playlistListProvider（缺陷点）；对照组 :118-126 addTracks / :139-147 removeTracks 均双刷 tracks+list |
| DB | lib/core/database/dao/playlist_dao.dart:86-89 | deletePlaylist 删 playlists 行，FK CASCADE 级联删 tracks（DB 侧无残留） |
| 门禁测试 | test/features/playlist/bug_bug22_repro_test.dart | 真 SQLite 驱动，修复前 FAIL |

---

## §3 行为规约

### 3.1 现状锚定（逆抽）

- **[BUG-22-S0]** 写路径失效纪律：addTracks/removeTracks 后同时 invalidate playlistTracksProvider(id) 与 playlistListProvider；reorder 仅刷 tracks
  Code evidence: `lib/features/playlist/playlist_provider.dart:118-126, :139-147, :128-137`

### 3.2 修复目标

- **[BUG-22-S1]** 删除播放单后，其曲目 family 元素必须失效并重新查询到空 （`status: new`）
  ```
  Given playlistTracksProvider(id) 已建立缓存（读过一次）
  When deletePlaylistProvider(id) 执行完成
  Then 再次读取 playlistTracksProvider(id) 返回空列表（重新查询 DB 所致）
       且 playlistListProvider 已刷新（既有行为保留）
  否定断言:
    - 其它未删除播放单 id 的 family 元素不得被波及（内容与删除前一致）
    - 不新增对 DAO 的写操作（本修复仅补 invalidate）
  ```
  Code evidence: 修改点 `lib/features/playlist/playlist_provider.dart:103-106`

---

## §4 不变量

- **[BUG-22-INV1]** playlist 数据源的全部写路径（create/update/delete/add/remove/reorder/import）之后，其对应订阅方 provider 的失效覆盖必须完整：list 类写刷 list、track 类写刷 tracks、两者皆变则双刷
  证据：playlist_provider.dart:92-147 各写路径对照

---

## §5 测试规约

### 5.1 现有测试清单

| 测试文件 | 覆盖 | 备注 |
|---|---|---|
| test/features/playlist/ref_26_test.dart 等 | 播放单 CRUD 既有行为 | 全绿即可 |

### 5.2 测试 ID 派生清单

```
BUG-22-S1, BUG-22-INV1
```

### 5.3 测试覆盖盲点

| 未覆盖 ID | 现状 | 应补偿方式 |
|---|---|---|
| INV1 的 import 路径 | importPlaylist 新建播放单不存在存量订阅方，语义安全（playlist_service.dart:194 先建后加） | 无需补测，注释说明即可 |

### 5.4 门禁测试文件（spec-scan --gate 硬校验）

| 测试文件 | 覆盖 ID | 说明 |
|---|---|---|
| test/features/playlist/bug_bug22_repro_test.dart | BUG-22-S1 | 修复前 FAIL 已由 repro-test.sh fail 确认（2026-08-22）；修复后必须 PASS |

---

## §6 算法样例

不涉及纯函数算法，跳过。

---

## §7 跨模块影响

impact 反查（2026-08-22）：playlist_provider.dart ← playlist 两 screen、add_tracks_browser、shared/di/providers.dart re-export。

| 其它 feature | 影响点 | 影响条件 | 回归断言要求 |
|---|---|---|---|
| BROWSER | add_tracks_browser 读 playlistTracksProvider | 无（只读路径不变） | ply 既有测试全绿 |

**修改点（弱模型照单执行）**：
1. `lib/features/playlist/playlist_provider.dart` deletePlaylistProvider 闭包（现 :103-106）改为：
   ```dart
   return (int id) async {
     await service.deletePlaylist(id);
     ref.invalidate(playlistTracksProvider(id));
     ref.invalidate(playlistListProvider);
   };
   ```
   即在既有 `ref.invalidate(playlistListProvider);` 之前插入一行 `ref.invalidate(playlistTracksProvider(id));`。invalidate 一个从未创建过的 family 元素是 Riverpod 2.x 安全空操作（同款用法见 :123/:135/:144）。
2. 全量回归：`flutter analyze --no-fatal-infos` 0 warning + `flutter test` 全绿。

---

## §8 平台特性与手动 QA

核对踩坑库：P10 直接相关（多订阅数据源写后漏失效——本 Bug 即 delete 路径漏了 tracks 订阅方）；其余条款无交集。

本功能不涉及平台原生特性，全部可在 `flutter test` 中验证。

---

## §9 dev-status.json 条目对照

```json
"BUG-22": {
  "spec_file": "docs/features/BUG-22.md",
  "spec_anchored_files": [
    "lib/features/playlist/playlist_provider.dart"
  ],
  "scenarios": ["BUG-22-S1"],
  "invariants": ["BUG-22-INV1"],
  "algorithms": [],
  "manual_qa_required": false,
  "user_acceptance_text": "见 §1.2"
}
```
