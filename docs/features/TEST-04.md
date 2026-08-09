# TEST-04 — 播放单测试缺口（LIST9+LIST10）

> 来源：`docs/cr/cr-20260724-0110.md` LIST9 (line 388-391) + LIST10 (line 393-396)
> dev-plan 流程：TEST-GAP 模式（补测，不修改生产代码）

---

## §0 头部元数据

```yaml
id: TEST-04
name: 播放单测试缺口（LIST9+LIST10）
priority: P2
status: draft
created_at: 2026-07-27
last_updated: 2026-07-27
spec_anchored_files:
  - lib/features/home/home_screen.dart
  - lib/features/player/widgets/mini_player_bar.dart
  - lib/features/playlist/playlist_detail_screen.dart
cross_module_impacts: [PLY, BRW]
parent_feature: Playlist
manual_qa_required: false
```

---

## §1 用户视角

### 1.0 原始需求

> cr-20260724-0110.md LIST9：`ply_09_test.dart:80-93` group 名 MiniPlayerBar，唯一断言 `find.text('Sona')`，注释自认"只验证 HomeScreen 渲染"；从 HomeScreen 删掉 MiniPlayerBar 测试仍绿。
> cr-20260724-0110.md LIST10：`ply_13_test.dart:977-1027` 断言测试内联手写的 `name.trim().isNotEmpty`，从不调用 `_showRenameDialog`；删掉 `playlist_detail_screen.dart:269` 空名守卫测试全绿。

### 1.1 这一功能干什么（一句话）

补齐播放单模块缺失的测试锚点，使 MiniPlayerBar 展示逻辑和播放单重命名校验有真实自动化守护。

### 1.2 用户期望的场景

| ID | 你看到的样子 | 期望行为 |
|----|----|----|
| U1 | 有播放队列时，主页底部显示 MiniPlayerBar | MiniPlayerBar 显示当前曲名，点击可跳转播放器 |
| U2 | 无播放队列时 | MiniPlayerBar 不显示（或显示空状态） |
| U3 | 播放单详情页，点重命名，输入空名 | 保存按钮禁用或弹错误提示，名称不变 |

---

## §2 当前测试骨架

### 2.1 测试文件与覆盖

| 层 | 文件 | 行数 | 角色 | 现状 |
|---|---|---|---|---|
| 测试 | `test/features/playlist/ply_09_test.dart` | ~93 | MiniPlayerBar | **LIST9**：只断言 `find.text('Sona')`，零守护 |
| 测试 | `test/features/playlist/ply_13_test.dart` | ~1027 | 重命名校验 | **LIST10**：断言本地函数，零守护 |

### 2.2 缺失的测试锚点

| 缺失行为 | 代码出处 | 当前测试状态 | 可逃逸的 mutation |
|---|---|---|---|
| MiniPlayerBar 展示当前曲名 | `mini_player_bar.dart:231-234` | 零守护（LIST9） | 删除 MiniPlayerBar 测试全绿 |
| 空队列时 MiniPlayerBar 不显示 | `home_screen.dart:205-210` | 零覆盖 | 删条件判断测试全绿 |
| 重命名输入空名被拦截 | `playlist_detail_screen.dart:269` | 零守护（LIST10） | 删空名守卫测试全绿 |

---

## §3 测试补强规约

### 3.1 LIST9 — MiniPlayerBar 展示

- **[TEST-04-S1]** 有队列时 MiniPlayerBar 展示当前曲名（`status: new`）
  ```
  Given currentPlayQueueProvider 返回非空队列，当前曲为 'Song A.mp3'
  When  pumpWidget(HomeScreen)
  Then  find.byType(MiniPlayerBar) 存在
  And   find.text('Song A.mp3') 存在（显示曲名，含文件扩展名——生产实测 mini_player_bar 直取 fileName 未去扩展名，2026-08-09 锚定）
  否定断言:
    - 不在有队列时不显示 MiniPlayerBar（应展示）
    - 不在显示时不展示当前曲名（应显示曲名）
    - 不在展示时误显示非当前曲目名称
    - 不改变无队列时的行为（应不显示或显示空状态）
  ```
  Code evidence: `lib/features/player/widgets/mini_player_bar.dart:231-234`（曲名展示）
  Test anchoring: `test/features/playlist/test_04_list9_test.dart:86`（断言 `find.text('Song A.mp3')`，含扩展名）
  Mutation risk: 从 HomeScreen 删除 MiniPlayerBar → 测试当前全绿（零守护）
  Test anchoring: widget test — override currentPlayQueueProvider，pump HomeScreen，断言 find.byType(MiniPlayerBar)

- **[TEST-04-S2]** 空队列时 MiniPlayerBar 不占可见内容（`status: new`）
  ```
  Given currentPlayQueueProvider 返回空队列
  When  pumpWidget(HomeScreen)
  Then  find.byType(MiniPlayerBar) 不存在或高度为 0
  否定断言:
    - 不在空队列时显示 MiniPlayerBar 内容（应隐藏）
    - 不在隐藏时占据布局空间（应不占高度）
    - 不改变有队列时的行为（应正常显示）
  ```
  Code evidence: `lib/features/home/home_screen.dart:205-210`（条件渲染）
  Test anchoring: widget test — override 空队列，pump，断言不显示

- **[TEST-04-S3]** 点击 MiniPlayerBar 跳转播放器（`status: new`）
  ```
  Given currentPlayQueueProvider 返回非空队列，MiniPlayerBar 已渲染
  When  点击 MiniPlayerBar
  Then  路由跳转到 /player
  否定断言:
    - 不在点击后不跳转（应跳转播放器）
    - 不在空队列时点击跳转（应无响应或隐藏）
    - 不改变其他区域的点击行为（应只影响 MiniPlayerBar）
  ```
  Code evidence: `lib/features/player/widgets/mini_player_bar.dart:231-234`（onTap → /player）
  Test anchoring: widget test — 点击 MiniPlayerBar，断言路由跳转

### 3.2 LIST10 — 重命名空名校验

- **[TEST-04-S4]** 重命名输入空串，名称不变（`status: new`）
  ```
  Given PlaylistDetailScreen 已渲染，播放单名称 'My Playlist'
  When  打开重命名对话框
  And   输入空串 ''
  And   点保存
  Then  播放单名称仍为 'My Playlist'（未变）
  否定断言:
    - 不在空串时调用 playlistService.rename()（应被校验拦截）
    - 不在空串时成功保存（应展示错误提示或禁用按钮）
    - 不改变合法名称的行为（应正常保存）
  ```
  Code evidence: `lib/features/playlist/playlist_detail_screen.dart:269`（空名守卫）
  Mutation risk: 删除空名守卫 → 空名可保存 → 测试当前全绿（零守护）
  Test anchoring: widget test — 打开对话框，输空串，点保存，断言名称未变

- **[TEST-04-S5]** 重命名输入纯空白，名称不变（`status: new`）
  ```
  Given PlaylistDetailScreen 已渲染，播放单名称 'My Playlist'
  When  打开重命名对话框
  And   输入纯空白 '   '
  And   点保存
  Then  播放单名称仍为 'My Playlist'（未变）
  否定断言:
    - 不在纯空白时调用 playlistService.rename()（应被 trim 后校验拦截）
    - 不在纯空白时成功保存（应展示错误提示或禁用按钮）
    - 不改变合法名称的行为（应正常保存）
  ```
  Code evidence: `lib/features/playlist/playlist_detail_screen.dart:269`（trim 校验）
  Test anchoring: widget test — 输入空白，点保存，断言名称未变

- **[TEST-04-S6]** 重命名输入合法名称，成功保存（`status: new`）
  ```
  Given PlaylistDetailScreen 已渲染，播放单名称 'My Playlist'
  When  打开重命名对话框
  And   输入 'New Name'
  And   点保存
  Then  调用 playlistService.rename(playlistId, 'New Name')
  And   播放单名称更新为 'New Name'
  否定断言:
    - 不在合法名称时不调用 rename（应正常保存）
    - 不在保存后不更新 UI（应刷新名称显示）
    - 不改变空名/空白名的拦截行为
  ```
  Code evidence: `lib/features/playlist/playlist_detail_screen.dart:269-280`（保存逻辑）
  Test anchoring: widget test — 输入合法名称，点保存，verify rename called

---

## §4 不变量

- **[TEST-04-INV1]** MiniPlayerBar 在有队列时展示当前曲名，空队列时隐藏
  证据：TEST-04-S1/S2 守护

- **[TEST-04-INV2]** 播放单重名校验拦截空串和纯空白
  证据：TEST-04-S4/S5 守护

---

## §5 测试规约

### 5.1 现有测试清单

| 测试文件 | 覆盖 | 备注 |
|---|---|---|
| `ply_09_test.dart` | MiniPlayerBar（空壳） | **LIST9**：只断言 'Sona'，需重写 |
| `ply_13_test.dart` | 重命名校验（空壳） | **LIST10**：断言本地函数，需改写 |

### 5.2 测试 ID 派生清单

```
TEST-04-S1~S3     # LIST9 MiniPlayerBar
TEST-04-S4~S6     # LIST10 重命名校验
TEST-04-INV1~INV2 # 不变量守护
```

### 5.3 测试覆盖盲点

| 未覆盖 ID | 现状 | 应补偿方式 |
|---|---|---|
| TEST-04-S1/S2 | MiniPlayerBar 展示零守护 | widget test：override currentPlayQueueProvider |
| TEST-04-S3 | 点击跳转零覆盖 | widget test：点击 MiniPlayerBar，断言路由 |
| TEST-04-S4~S6 | 重名校验零守护 | widget test：打开对话框，输入空/空白/合法名称 |

### 5.4 测试文件位置

| 测试 ID | 文件路径 | 类型 |
|---|---|---|
| TEST-04-S1~S3 | `test/features/playlist/test_04_list9_test.dart` | widget test |
| TEST-04-S4~S6 | `test/features/playlist/test_04_list10_test.dart` | widget test |
| TEST-04-INV1~INV2 | 同上分散 | — |

---

## §6 算法样例

不适用——本 spec 为测试补强，无新算法。

---

## §7 跨模块影响

| 其它 feature | 影响点 | 需要补的回归断言 |
|---|---|---|
| PLY | MiniPlayerBar 展示逻辑 | 现有 ply_09_test 需重写 |
| PLY | 重命名校验逻辑 | 现有 ply_13_test 需改写 |
| BRW | HomeScreen 底部 MiniPlayerBar | 现有 home test 可能需更新 |

---

## §8 平台特性与手动 QA

本 spec 不涉及平台原生特性，全部可在 `flutter test` 中验证。

---

## §9 dev-status.json 条目对照

见统一更新：`docs/dev/dev-status.json`。

---

## §10 changelog

- 2026-07-27: 创建 TEST-04 spec（基于 cr-20260724-0110.md LIST9+LIST10）
