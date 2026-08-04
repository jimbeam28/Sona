# BUG-25 — 播放单健壮性（LIST3 + LIST5 + LIST6 + LIST7 + LIST8）

> 来源：`docs/cr/cr-20260724-0110.md` LIST3 (line 338-343) + LIST5 (line 354-359) + LIST6 (line 361-366) + LIST7 (line 368-373) + LIST8 (line 375-379)
> dev-plan 流程：Bug 修复模式

---

## §0 头部元数据

```yaml
id: BUG-25
name: 播放单健壮性（LIST3 + LIST5 + LIST6 + LIST7 + LIST8）
priority: P2
status: draft
created_at: 2026-07-27
last_updated: 2026-08-05
spec_anchored_files:
  - lib/features/playlist/domain/playlist_service.dart
  - lib/features/playlist/playlist_detail_screen.dart
  - lib/features/playlist/playlist_list_screen.dart
  - lib/features/playlist/widgets/add_tracks_browser.dart
cross_module_impacts: [PLY]
parent_feature: Playlist
manual_qa_required: false
```

---

## §1 用户视角

### 1.0 原始需求

> cr-20260724-0110.md:
> LIST3: `playlist_service.dart:143-169` importPlaylist JSON 解析抛原始 TypeError/NoSuchMethodError；`:148` insertPlaylist 先于 track 解析留下孤儿播放单。
> LIST5: `playlist_detail_screen.dart:299` 全选 `t.id!` 强解包。
> LIST6: `add_tracks_browser.dart:97-102` fire-and-forget `.then()` 无 onError；`playlist_list_screen.dart:71-73` 删单无 await/catch。
> LIST7: `playlist_detail_screen.dart:49-56` `_playTrackAtIndex` 首次 await 后、showDialog 前缺 mounted 检查。
> LIST8: `playlist_list_screen.dart:105`、`playlist_detail_screen.dart:243` 对话框 TextEditingController 未 dispose。

### 1.1 这一功能干什么（一句话）

修复播放单功能的五个健壮性缺陷：JSON 导入健壮性、全选 null id 防御、Future 错误处理、mounted 检查、controller 释放。

### 1.2 用户期望的场景

| ID | 你看到的样子 | 期望行为 |
|----|----|----|
| U1 | 导入结构错误的 JSON | 抛出 FormatException，不残留孤儿播放单 |
| U2 | 含 null id 的曲目 + 全选 | 跳过 null id 项，不崩溃 |
| U3 | 添加曲目或删单时 DB 失败 | 显示错误提示，不静默失败 |
| U4 | 点有进度曲目后快速按返回 | showDialog 不在 defunct context 上调用 |
| U5 | 反复开关新建/重命名对话框 | 不泄漏 TextEditingController |

---

## §2 已实现的功能骨架

### 2.1 文件与分层

| 层 | 文件 | 行数 | 角色 |
|---|---|---|---|
| Domain | `lib/features/playlist/domain/playlist_service.dart` | 171 | CRUD + 导入导出 |
| UI | `lib/features/playlist/playlist_detail_screen.dart` | 366 | 详情页 + 选择模式 |
| UI | `lib/features/playlist/playlist_list_screen.dart` | 238 | 列表页 + 新建对话框 |
| Widget | `lib/features/playlist/widgets/add_tracks_browser.dart` | 221 | 添加曲目底栏 |

### 2.2 关键方法表

| 方法 | 位置 | 用途 |
|---|---|---|
| `importPlaylist` | `playlist_service.dart:142-169` | JSON 导入播放单 |
| 全选按钮 | `playlist_detail_screen.dart:294-301` | 全选曲目 |
| 添加曲目确认 | `add_tracks_browser.dart:96-103` | fire-and-forget 添加 |
| 滑动删单 | `playlist_list_screen.dart:71-73` | fire-and-forget 删除 |
| `_playTrackAtIndex` | `playlist_detail_screen.dart:40-77` | 播放曲目（含进度恢复） |
| `_showRenameDialog` | `playlist_detail_screen.dart:242-280` | 重命名对话框 |
| `_showCreateDialog` | `playlist_list_screen.dart:104-133` | 新建对话框 |

---

## §3 行为规约

### 3.1 修复后行为

- **[BUG-25-S1]** importPlaylist JSON 解析健壮性 + 孤儿播放单消除 (`status: new`)
  ```
  Given importPlaylist 接收畸形 JSON 输入
  When  JSON 结构非承诺格式（数组、track 元素非 Map 等）
  Then  抛出 FormatException（非 TypeError/NoSuchMethodError），且不留孤儿播放单
  否定断言:
    - 不抛 TypeError 或 NoSuchMethodError
    - 不在 track 解析失败后 DB 残留 0 曲目播放单
    - 不改变合法 JSON 的正常导入行为
  ```
  Code evidence: `playlist_service.dart:143`（`jsonDecode(jsonString) as Map<String, dynamic>` — 输入为数组时 TypeError）
  Code evidence: `playlist_service.dart:148`（`insertPlaylist` 先于 track 解析）
  Code evidence: `playlist_service.dart:158`（`t['filePath'] as String?` — t 非 Map 时 NoSuchMethodError）

  **修改指令 — `lib/features/playlist/domain/playlist_service.dart`（importPlaylist）**

  位置：`:142-169`

  当前代码（:142-169）：
  ```dart
  Future<int> importPlaylist(String jsonString) async {
    final data = jsonDecode(jsonString) as Map<String, dynamic>;
    final name = (data['name'] as String?) ?? '导入的播放单';
    final trackList = (data['tracks'] as List<dynamic>?) ?? [];

    final now = DateTime.now();
    final playlistId = await _dao.insertPlaylist(Playlist(
      name: name,
      createdAt: now,
      updatedAt: now,
    ));

    final seen = <String>{};
    final tracks = trackList
        .map((t) => PlaylistTrack(
              playlistId: playlistId,
              filePath: t['filePath'] as String? ?? '',
              fileName: t['fileName'] as String? ?? '',
              addedAt: now,
            ))
        .where((t) => t.filePath.isNotEmpty && seen.add(t.filePath))
        .toList();

    if (tracks.isNotEmpty) {
      await _dao.addTracks(tracks);
    }

    return playlistId;
  }
  ```

  改为：
  ```dart
  Future<int> importPlaylist(String jsonString) async {
    final dynamic decoded = jsonDecode(jsonString);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('播放单 JSON 格式错误：顶层须为对象');
    }
    final data = decoded;
    final name = (data['name'] is String?) ? (data['name'] as String?) ?? '导入的播放单' : '导入的播放单';
    final dynamic rawTracks = data['tracks'];
    final trackList = (rawTracks is List<dynamic>) ? rawTracks : <dynamic>[];

    final seen = <String>{};
    final now = DateTime.now();
    final tracks = <PlaylistTrack>[];
    for (final t in trackList) {
      if (t is! Map<String, dynamic>) continue;
      final filePath = (t['filePath'] is String) ? t['filePath'] as String : '';
      final fileName = (t['fileName'] is String) ? t['fileName'] as String : '';
      if (filePath.isNotEmpty && seen.add(filePath)) {
        tracks.add(PlaylistTrack(
          playlistId: 0,
          filePath: filePath,
          fileName: fileName,
          addedAt: now,
        ));
      }
    }

    final playlistId = await _dao.insertPlaylist(Playlist(
      name: name,
      createdAt: now,
      updatedAt: now,
    ));

    if (tracks.isNotEmpty) {
      final fixedTracks = tracks
          .map((t) => t.copyWith(playlistId: playlistId))
          .toList();
      await _dao.addTracks(fixedTracks);
    }

    return playlistId;
  }
  ```

  边界裁决：
  - `jsonDecode` 非法 JSON → 原抛 FormatException（不变）
  - 顶层为数组 `[1,2]` → `is! Map` → 抛 FormatException（之前 TypeError）
  - track 元素为 `1`（非 Map）→ `is! Map` → 跳过（之前 NoSuchMethodError）
  - `tracks` 字段缺失或非数组 → 当作空列表
  - `name` 字段非字符串 → 使用默认名"导入的播放单"
  - `insertPlaylist` 在所有解析成功后才执行 → 解析失败不留孤儿
  - 注意：`PlaylistTrack` 构造时 `playlistId: 0` 为占位，解析成功后用 `copyWith` 设真实 id — 需确认 `PlaylistTrack` 有 `copyWith`（grep 确认无 `copyWith` → 需直接构造时传 0 后再设）

  备选方案（若 PlaylistTrack 无 copyWith）：解析分两步 — 先验证解析为 `(filePath, fileName)` 元组列表，insertPlaylist 后再构造 `PlaylistTrack`：

  ```dart
  Future<int> importPlaylist(String jsonString) async {
    final dynamic decoded = jsonDecode(jsonString);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('播放单 JSON 格式错误：顶层须为对象');
    }
    final data = decoded;
    final name = (data['name'] is String?) ? (data['name'] as String?) ?? '导入的播放单' : '导入的播放单';
    final dynamic rawTracks = data['tracks'];
    final trackList = (rawTracks is List<dynamic>) ? rawTracks : <dynamic>[];

    final seen = <String>{};
    final entries = <({String filePath, String fileName})>[];
    for (final t in trackList) {
      if (t is! Map<String, dynamic>) continue;
      final filePath = (t['filePath'] is String) ? t['filePath'] as String : '';
      final fileName = (t['fileName'] is String) ? t['fileName'] as String : '';
      if (filePath.isNotEmpty && seen.add(filePath)) {
        entries.add((filePath: filePath, fileName: fileName));
      }
    }

    final now = DateTime.now();
    final playlistId = await _dao.insertPlaylist(Playlist(
      name: name,
      createdAt: now,
      updatedAt: now,
    ));

    if (entries.isNotEmpty) {
      final tracks = entries
          .map((e) => PlaylistTrack(
                playlistId: playlistId,
                filePath: e.filePath,
                fileName: e.fileName,
                addedAt: now,
              ))
          .toList();
      await _dao.addTracks(tracks);
    }

    return playlistId;
  }
  ```

- **[BUG-25-S2]** 全选按钮过滤 null id (`status: new`)
  ```
  Given 播放单含 id 为 null 的曲目（理论边界）
  When  用户点全选
  Then  null id 项被跳过，不崩溃
  否定断言:
    - 不在全选时抛 Null check operator error
    - 不改变 tap/long-press 路径的 null id 守卫行为
    - 不改变正常曲目全选的行为
  ```
  Code evidence: `playlist_detail_screen.dart:299`（`tracks.map((t) => t.id!)`）
  对照：`playlist_detail_screen.dart:160`（tap 路径有 `if (track.id == null) return;` 守卫）
  对照：`playlist_detail_screen.dart:170`（long-press 路径有 `if (track.id == null) return;` 守卫）

  **修改指令 — `lib/features/playlist/playlist_detail_screen.dart`（全选按钮）**

  位置：`:294-301`

  当前代码（:294-301）：
  ```dart
          onPressed: () {
            final tracks =
                ref.read(playlistTracksProvider(playlistId)).valueOrNull;
            if (tracks != null) {
              setState(() {
                _selectedIds.addAll(tracks.map((t) => t.id!));
              });
            }
          },
  ```

  改为：
  ```dart
          onPressed: () {
            final tracks =
                ref.read(playlistTracksProvider(playlistId)).valueOrNull;
            if (tracks != null) {
              setState(() {
                _selectedIds.addAll(tracks
                    .map((t) => t.id)
                    .whereType<int>());
              });
            }
          },
  ```

  边界裁决：
  - 所有曲目 id 非空 → `whereType<int>()` 透传所有 → 行为不变
  - 部分曲目 id 为 null → 过滤掉 → 只选非 null 项
  - 全部曲目 id 为 null → `_selectedIds` 空 → 选择模式仍在但无选中项（可接受降级）

- **[BUG-25-S3]** fire-and-forget Future 补错误处理 (`status: new`)
  ```
  Given 添加曲目或删单操作触发
  When  DB 操作失败（磁盘满/库锁）
  Then  显示错误提示，不静默失败
  否定断言:
    - 不在 DB 失败时产生 unhandled Future rejection
    - 不在 DB 失败时 UI 停留操作前状态无反馈
    - 不改变正常操作成功时的行为
  ```
  Code evidence: `add_tracks_browser.dart:97-102`（`.then((_) { if (mounted) Navigator.of(context).pop(); })` 无 onError）
  Code evidence: `playlist_list_screen.dart:71-73`（`del(playlist.id!)` 未 await 无 catch）

  **修改指令 — `lib/features/playlist/widgets/add_tracks_browser.dart`（添加曲目确认）**

  位置：`:96-103`

  当前代码（:96-103）：
  ```dart
                          ref
                              .read(addTracksToPlaylistProvider)
                              (widget.playlistId, files)
                              .then((_) {
                            if (mounted) Navigator.of(context).pop();
                          });
  ```

  改为：
  ```dart
                          ref
                              .read(addTracksToPlaylistProvider)
                              (widget.playlistId, files)
                              .then((_) {
                            if (mounted) Navigator.of(context).pop();
                          }).catchError((e) {
                            if (mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text('添加失败：$e'),
                                  backgroundColor: Theme.of(context).colorScheme.error,
                                ),
                              );
                            }
                          });
  ```

  **修改指令 — `lib/features/playlist/playlist_list_screen.dart`（滑动删单）**

  位置：`:71-74`

  当前代码（:71-74）：
  ```dart
                          if (confirmed == true) {
                            final del = ref.read(deletePlaylistProvider);
                            del(playlist.id!);
                          }
  ```

  改为：
  ```dart
                          if (confirmed == true) {
                            final del = ref.read(deletePlaylistProvider);
                            try {
                              await del(playlist.id!);
                            } catch (e) {
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text('删除失败：$e'),
                                    backgroundColor: Theme.of(context).colorScheme.error,
                                  ),
                                );
                              }
                            }
                          }
  ```

  边界裁决：
  - DB 成功 → 正常路径（行为不变）
  - DB 失败 → 显示 SnackBar 错误提示
  - widget 已卸载 → `mounted`/`context.mounted` 守卫 → 不操作 UI
  - `playlist.id!` 强解包 — Playlist 从 DB 查出 id 恒非空，保持原样

- **[BUG-25-S4]** `_playTrackAtIndex` showDialog 前补 mounted 检查 (`status: new`)
  ```
  Given 用户点击有进度的曲目
  When  progress future 完成的毫秒窗口内按返回退出详情页
  Then  showDialog 不在 defunct context 上调用
  否定断言:
    - 不在 widget 已卸载后调用 showDialog
    - 不改变 mounted 为 true 时的正常进度恢复行为
    - 不改变无进度或进度 < 5s 的行为
  ```
  Code evidence: `playlist_detail_screen.dart:49-56`（await 后直接 showDialog，mounted 检查在 `:66` 即对话框**之后**）

  **修改指令 — `lib/features/playlist/playlist_detail_screen.dart`（_playTrackAtIndex）**

  位置：`:47-66`

  当前代码（:47-66）：
  ```dart
    if (conn != null && conn.id != null) {
      try {
        final progress = await ref.read(progressForFileProvider(
            (connectionId: conn.id!, filePath: filePath)).future);
        if (progress != null && progress.positionMs >= 5000) {
          final resume = await showProgressResumeDialog(
            context,
            ProviderScope.containerOf(context),
            progress,
          );
          if (resume == true) {
            startPositionMs = progress.positionMs;
          }
        }
      } catch (_) {
        // On error, play from beginning
      }
    }

    if (!context.mounted) return;
  ```

  改为：
  ```dart
    if (conn != null && conn.id != null) {
      try {
        final progress = await ref.read(progressForFileProvider(
            (connectionId: conn.id!, filePath: filePath)).future);
        if (!context.mounted) return;
        if (progress != null && progress.positionMs >= 5000) {
          final resume = await showProgressResumeDialog(
            context,
            ProviderScope.containerOf(context),
            progress,
          );
          if (resume == true) {
            startPositionMs = progress.positionMs;
          }
        }
      } catch (_) {
        // On error, play from beginning
      }
    }

    if (!context.mounted) return;
  ```

  边界裁决：
  - progress future 完成 + widget 仍在 → mounted 检查通过 → 弹对话框（行为不变）
  - progress future 完成 + widget 已卸载 → `context.mounted` false → return
  - showProgressResumeDialog 后 → 已有 `:66` mounted 检查 → 二次保护
  - progress < 5s → 不弹对话框 → 直接进入已有 mounted 检查

  > **⚠ 更正（2026-08-05，cr-20260804-1922 复核）**：原方案的 `context.mounted` 检查被门禁
  > 实证**不可行**——defunct State 上 `context` getter 本身即抛（debug FlutterError /
  > release null check），await 后行 51 的 `context.mounted` 检查被外层 catch 吞掉、
  > 行 72 原崩溃点照样再抛，对目标场景零防护（复核报告 M8 第 6 条）。
  > 实际落地实现（commit ef3d386）改用 **State 级 `mounted`**：
  > - `lib/features/playlist/playlist_detail_screen.dart:51-54` — await progress 之后
  >   `if (!mounted) return;`（注释注明不用 `context.mounted` 的原因）
  > - `lib/features/playlist/playlist_detail_screen.dart:78-79` — showDialog 之后同款守卫
  >
  > State 的 `mounted` 属性不依赖 context getter，State defunct 后仍可安全读取，
  > 才能守住本 Scenario 要防的场景。原「改为 context.mounted」修改指令及对应边界裁决
  > 两条作废，本 Scenario 的 Then/否定断言语义不变。

- **[BUG-25-S5]** 对话框 TextEditingController 正确 dispose (`status: new`)
  ```
  Given 打开重命名或新建对话框
  When  对话框关闭（保存或取消）
  Then  TextEditingController 被 dispose，不泄漏
  否定断言:
    - 不在对话框关闭后保留 controller 的 listener
    - 不改变对话框正常输入和返回值的逻辑
    - 不改变对话框的 UI 外观和行为
  ```
  Code evidence: `playlist_list_screen.dart:105`（`_showCreateDialog` 局部 controller 无 dispose）
  Code evidence: `playlist_detail_screen.dart:243`（`_showRenameDialog` 局部 controller 无 dispose）

  **修改指令 — `lib/features/playlist/playlist_list_screen.dart`（_showCreateDialog）**

  位置：`:104-133`

  当前代码（:104-133）：
  ```dart
  void _showCreateDialog(BuildContext context, WidgetRef ref) {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('新建播放单'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(hintText: '播放单名称'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () {
              final name = controller.text.trim();
              if (name.isEmpty) return;
              final create = ref.read(createPlaylistProvider);
              create(name);
              Navigator.of(ctx).pop();
            },
            child: const Text('创建'),
          ),
        ],
      ),
    );
  }
  ```

  改为：
  ```dart
  void _showCreateDialog(BuildContext context, WidgetRef ref) {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('新建播放单'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(hintText: '播放单名称'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () {
              final name = controller.text.trim();
              if (name.isEmpty) return;
              final create = ref.read(createPlaylistProvider);
              create(name);
              Navigator.of(ctx).pop();
            },
            child: const Text('创建'),
          ),
        ],
      ),
    ).then((_) => controller.dispose());
  }
  ```

  **修改指令 — `lib/features/playlist/playlist_detail_screen.dart`（_showRenameDialog）**

  位置：`:242-280`

  当前代码（:242-280）：
  ```dart
  Future<void> _showRenameDialog(int playlistId, String currentName) async {
    final controller = TextEditingController(text: currentName);
    final newName = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('重命名播放单'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: '名称',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(controller.text.trim()),
            child: const Text('保存'),
          ),
        ],
      ),
    );

    if (newName != null && newName.isNotEmpty && newName != currentName) {
  ```

  改为：
  ```dart
  Future<void> _showRenameDialog(int playlistId, String currentName) async {
    final controller = TextEditingController(text: currentName);
    final newName = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('重命名播放单'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: '名称',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(controller.text.trim()),
            child: const Text('保存'),
          ),
        ],
      ),
    );
    controller.dispose();

    if (newName != null && newName.isNotEmpty && newName != currentName) {
  ```

  边界裁决：
  - `_showCreateDialog`：`showDialog` 返回 Future，`.then((_) => controller.dispose())` 在对话框关闭后释放（无论 pop 值）
  - `_showRenameDialog`：`await showDialog` 完成后立即 `controller.dispose()`，后续 `updatePlaylist` 不再需 controller
  - 对话框被系统 pop（如返回键）→ dispose 仍触发（showDialog future 完成）
  - 多次开/关对话框 → 每次创建+释放，无泄漏

  > **⚠ 更正（2026-08-05，cr-20260804-1922 复核）**：原方案（`.then((_) => controller.dispose())`
  > 与「`await showDialog` 后 dispose」）被门禁实证**与退场动画竞态**——showDialog 返回的
  > Future 在 `pop` 被调用时即完成，但此时退场动画仍在播放、对话框内容仍 mounted 且
  > TextField 仍持有 controller，立即 dispose → use-after-disposed 崩溃
  > （复核报告 M8 第 7 条）。实际落地实现（commit ef3d386）按 CR 首推方案
  > **对话框内容抽成 StatefulWidget，controller 随对话框元素 dispose**：
  > - 新建对话框：`lib/features/playlist/playlist_list_screen.dart:119-128`
  >   （`_showCreateDialog` 委托 `builder: (_) => const _CreatePlaylistDialog()`）、
  >   `:131-149`（`_CreatePlaylistDialog` ConsumerStatefulWidget，controller 字段 `:143`，
  >   State.dispose 内释放 `:145-149`）
  > - 重命名对话框：`lib/features/playlist/playlist_detail_screen.dart:259-267`
  >   （`_showRenameDialog` 委托 `builder: (_) => _RenamePlaylistDialog(initialText: currentName)`）、
  >   `:371-388`（`_RenamePlaylistDialog` StatefulWidget，controller `:381-382`，
  >   State.dispose 内释放 `:384-388`）
  >
  > 退场动画结束、对话框元素 unmount 时 State.dispose 才触发 → controller 安全释放，
  > 无竞态、无泄漏。原两段「改为 .then/await 后 dispose」修改指令与上方边界裁决四条作废，
  > 本 Scenario 的 Then/否定断言语义不变。

  **测试文件位置：`test/features/playlist/bug_bug25_repro_test.dart`**

---

## §4 不变量

- **[BUG-25-INV1]** importPlaylist 不抛 TypeError/NoSuchMethodError，只抛 FormatException
  证据：`playlist_service.dart:143,158`（修复目标）

- **[BUG-25-INV2]** importPlaylist 的 `insertPlaylist` 在 track 解析完全成功之后
  证据：`playlist_service.dart:148`（修复目标：移到解析后）

- **[BUG-25-INV3]** 所有选择模式入口（tap / long-press / 全选）对 null id 有守卫
  证据：`playlist_detail_screen.dart:160,170`（已有）→ `:299`（修复目标）

- **[BUG-25-INV4]** 所有变更类 Future 调用有错误处理
  证据：`add_tracks_browser.dart:97-102`、`playlist_list_screen.dart:71-73`（修复目标）

- **[BUG-25-INV5]** 所有 await 后调用 showDialog / Navigator 前有 mounted 检查
  证据：`playlist_detail_screen.dart:49-66`（修复目标）
  更正（2026-08-05）：已落地为 State 级 `mounted`——`playlist_detail_screen.dart:51-54,78-79`（ef3d386；不用 `context.mounted`，理由见 S4 更正块）

- **[BUG-25-INV6]** 所有 TextEditingController 在使用后被 dispose
  证据：`playlist_list_screen.dart:105`、`playlist_detail_screen.dart:243`（修复目标）
  更正（2026-08-05）：已落地为对话框 StatefulWidget 自持——`playlist_list_screen.dart:142-149`（_CreatePlaylistDialogState.dispose）、`playlist_detail_screen.dart:380-388`（_RenamePlaylistDialogState.dispose）（ef3d386，见 S5 更正块）

---

## §5 测试规约

### 5.2 测试 ID 派生清单

```
BUG-25-S1           # importPlaylist JSON 健壮性
BUG-25-S2           # 全选 null id 防御
BUG-25-S3           # fire-and-forget 错误处理
BUG-25-S4           # _playTrackAtIndex mounted 检查
BUG-25-S5           # controller dispose
BUG-25-INV1         # importPlaylist 不抛 TypeError
BUG-25-INV2         # insertPlaylist 在解析后
BUG-25-INV3         # null id 守卫完整
BUG-25-INV4         # Future 错误处理完整
BUG-25-INV5         # mounted 检查完整
BUG-25-INV6         # controller dispose 完整
```

### 5.4 测试文件位置

| 测试 ID | 文件路径 |
|---------|----------|
| BUG-25-S1 | `test/features/playlist/bug_bug25_repro_test.dart` |
| BUG-25-S2 | `test/features/playlist/bug_bug25_repro_test.dart` |
| BUG-25-S3 | `test/features/playlist/bug_bug25_repro_test.dart` |
| BUG-25-S4 | `test/features/playlist/bug_bug25_repro_test.dart` |
| BUG-25-S5 | `test/features/playlist/bug_bug25_repro_test.dart` |
| BUG-25-INV1 | `test/features/playlist/bug_bug25_repro_test.dart` |
| BUG-25-INV2 | `test/features/playlist/bug_bug25_repro_test.dart` |
| BUG-25-INV3 | `test/features/playlist/bug_bug25_repro_test.dart` |
| BUG-25-INV4 | `test/features/playlist/bug_bug25_repro_test.dart` |
| BUG-25-INV5 | `test/features/playlist/bug_bug25_repro_test.dart` |
| BUG-25-INV6 | `test/features/playlist/bug_bug25_repro_test.dart` |

---

## §7 跨模块影响

| 模块 | 影响 | 说明 |
|------|------|------|
| PLY | 正面 | 播放单功能更健壮，边界情况不崩溃 |
| CON | 无 | 不涉及连接 |
| BRW | 无 | 不涉及浏览 |

---

## §8 平台特性与手动 QA

本功能不涉及平台原生特性。S1-S5 全部可在 `flutter test` 中验证：
- S1: 纯 Dart 单元测试（PlaylistService + fake DAO）
- S2: Widget 测试（mock playlistTracksProvider 注入 null id 数据）
- S3: Widget 测试（mock provider 注入异常）
- S4: Widget 测试（模拟 await 后 widget 卸载）
- S5: Widget 测试（spy on controller.dispose）

---

## §9 dev-status.json 条目对照

见统一更新：`docs/dev/dev-status.json`。

---

## §10 changelog

- 2026-07-27: 创建 BUG-25 spec（基于 cr-20260724-0110.md LIST3 + LIST5 + LIST6 + LIST7 + LIST8）
- 2026-08-05: cr-20260804-1922 复核：修订实现性错误/门禁指向——S4 原方案 context.mounted 门禁实证不可行（defunct State 上 context getter 本身即抛），更正为实际落地的 State 级 mounted（playlist_detail_screen.dart:51-54,78-79，ef3d386）；S5 原方案「showDialog 后 dispose controller」与退场动画竞态，更正为实际落地的对话框抽 StatefulWidget、controller 随对话框元素 dispose（playlist_list_screen.dart:131-149 / playlist_detail_screen.dart:371-388，ef3d386）；INV5/INV6 证据同步
