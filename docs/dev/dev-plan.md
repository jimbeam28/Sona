# Sona 开发计划

## 待实现

### PLY-09 播放单功能（主入口 + Tab 导航）

**来源**：新功能 | **优先级**：P1
**涉及文件**：
- `lib/features/home/home_screen.dart`（新建）
- `lib/features/browser/browser_screen.dart`（改造：去除 Scaffold/AppBar，仅保留 body）
- `lib/main.dart`（路由：`/browser` 改指向 `HomeScreen`，新增 `/playlist/:id`）

**依赖**：PLY-10、PLY-11、PLY-12、PLY-13

**实现要点**：
- 新建 `HomeScreen`（`ConsumerStatefulWidget`），持有 `TabController(length: 2)`
- Tab 0（默认）：「播放单」→ `PlaylistListScreen()`
- Tab 1：「文件浏览器」→ 改造后的 `BrowserScreen()`（仅 body）
- `AppBar` 由 `HomeScreen` 统一提供：标题「Sona」、设置图标（始终显示）、排序菜单（按当前 tab 切换内容）
- `MiniPlayerBar` 从 `BrowserScreen` 移至 `HomeScreen` body 底部，跨 tab 持久显示
- `BrowserScreen` 改造：去掉外层 `Scaffold`/`AppBar`，仅返回 `PopScope` 包裹的 `Column`（面包屑 + 文件列表）；设置图标和排序菜单逻辑迁移到 `HomeScreen`

**测试用例**：PLY-T60 ~ PLY-T65

---

### PLY-10 播放单数据层（数据库 + 模型 + DAO）

**来源**：新功能 | **优先级**：P1
**涉及文件**：
- `lib/core/database/database_helper.dart`（版本 1→2，新增两张表）
- `lib/shared/models/playlist.dart`（新建）
- `lib/core/database/dao/playlist_dao.dart`（新建）

**依赖**：无

**实现要点**：

数据库迁移（version 1 → 2）：
- `openDatabase` 增加 `onUpgrade: _onUpgrade`
- `_onCreate` 和 `_onUpgrade(oldVersion < 2)` 均执行：
  ```sql
  CREATE TABLE playlists (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    name TEXT NOT NULL,
    created_at INTEGER NOT NULL,
    updated_at INTEGER NOT NULL
  );
  CREATE TABLE playlist_tracks (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    playlist_id INTEGER NOT NULL,
    file_path TEXT NOT NULL,
    file_name TEXT NOT NULL,
    added_at INTEGER NOT NULL,
    FOREIGN KEY(playlist_id) REFERENCES playlists(id) ON DELETE CASCADE
  );
  CREATE INDEX idx_playlist_tracks_playlist_id ON playlist_tracks(playlist_id);
  ```
- 不存储 `connection_id`，路径与连接无关（与现有队列持久化模型一致）

模型 `Playlist`：`id?`、`name`、`trackCount`（JOIN 查询填充）、`createdAt`、`updatedAt`

模型 `PlaylistTrack`：`id?`、`playlistId`、`filePath`、`fileName`、`addedAt`；提供 `toNasFile()` 方法（`isDirectory=false`，`audioType` 由文件名推断）

`PlaylistDao` 方法：
- `insertPlaylist(Playlist)` → `int`（返回新 id）
- `findAllPlaylists()` → `List<Playlist>`（LEFT JOIN + GROUP BY 一次查询返回 trackCount）
- `updatePlaylist(Playlist)`
- `deletePlaylist(int id)`（CASCADE 自动删除 tracks）
- `addTracks(List<PlaylistTrack>)`（db.transaction 批量插入）
- `findTracksForPlaylist(int playlistId)` → `List<PlaylistTrack>`（按 added_at ASC）
- `removeTracks(List<int> trackIds)`（批量删除）
- `trackExists(int playlistId, String filePath)` → `bool`（去重检查）

**测试用例**：PLY-T40 ~ PLY-T55

---

### PLY-11 播放单 Provider 层

**来源**：新功能 | **优先级**：P1
**涉及文件**：
- `lib/features/playlist/playlist_provider.dart`（新建）

**依赖**：PLY-10

**实现要点**：

排序枚举：
- `PlaylistSortOption`：`createdAsc`、`createdDesc`、`nameAsc`、`nameDesc`
- `TrackSortOption`：`addedAsc`、`nameAsc`、`nameDesc`

Providers：
- `playlistDaoProvider`：`Provider<PlaylistDao>`
- `playlistSortProvider`：`StateProvider<PlaylistSortOption>`（默认 `createdAsc`）
- `trackSortProvider`：`StateProvider<TrackSortOption>`（默认 `addedAsc`）
- `playlistListProvider`：`FutureProvider<List<Playlist>>`，watch `playlistSortProvider`，排序在内存中完成；变更后调用 `ref.invalidate` 刷新（与现有 `connectionListProvider` 模式一致）
- `playlistTracksProvider`：`FutureProvider.family<List<PlaylistTrack>, int>`，watch `trackSortProvider`

变更 Provider（均为 `Provider<Future<X> Function(...)>`）：
- `createPlaylistProvider(String name)` → 插入后 `invalidate(playlistListProvider)`
- `deletePlaylistProvider(int id)` → 删除后 `invalidate(playlistListProvider)`
- `addTracksToPlaylistProvider(int playlistId, List<NasFile> files)` → 逐一调用 `trackExists` 去重，批量 `addTracks`，`invalidate(playlistTracksProvider(playlistId))`
- `removeTracksFromPlaylistProvider(int playlistId, List<int> trackIds)` → `removeTracks`，`invalidate(playlistTracksProvider(playlistId))`

**测试用例**：PLY-T56 ~ PLY-T59

---

### PLY-12 播放单列表页

**来源**：新功能 | **优先级**：P1
**涉及文件**：
- `lib/features/playlist/playlist_list_screen.dart`（新建）
- `lib/features/playlist/widgets/playlist_list_item.dart`（新建）

**依赖**：PLY-11

**实现要点**：
- `PlaylistListScreen`：`ConsumerWidget`，watch `playlistListProvider`，处理 loading/error/empty 三态（与 `BrowserScreen` 风格一致）
- 空态：图标 + 「还没有播放单，点击 + 新建」提示
- `FloatingActionButton`（`Icons.add`）→ `AlertDialog`（`TextField` 输入名称，名称不能为空）→ 调用 `createPlaylistProvider`
- 每行 `PlaylistListItem`：播放单名称 + 曲目数量 chip（如「12 首」）
- 删除：`Dismissible` 向右滑动 → 弹出确认 `AlertDialog`（「确认删除播放单『xxx』？此操作不可撤销。」）→ 确认后调用 `deletePlaylistProvider`；取消则恢复列表项
- 点击行 → `context.push('/playlist/$id')`
- 排序菜单由 `HomeScreen` AppBar 提供（当 Tab 0 激活时），选项：创建时间升序/降序、名称升序/降序

**测试用例**：PLY-T66 ~ PLY-T72

---

### PLY-13 播放单详情页 + 添加曲目弹窗

**来源**：新功能 | **优先级**：P1
**涉及文件**：
- `lib/features/playlist/playlist_detail_screen.dart`（新建）
- `lib/features/playlist/widgets/playlist_track_item.dart`（新建）
- `lib/features/playlist/widgets/add_tracks_browser.dart`（新建）

**依赖**：PLY-11

**实现要点**：

`PlaylistDetailScreen`（`ConsumerStatefulWidget`，路由 `/playlist/:id`）：
- 本地状态：`Set<int> _selectedIds`（选中的 track id）、`bool _selectionMode`
- watch `playlistTracksProvider(playlistId)`，处理 loading/error/empty 三态
- **普通模式** AppBar：播放单名称 + 排序菜单 + 「添加」按钮（`Icons.add`）
- **选择模式** AppBar：「已选 N 首」+ 「全选」/「取消全选」/「删除」图标按钮
- 点击曲目：将播放单所有曲目转为 `NasFile` 列表，以点击索引为起点构建 `PlayQueue`，设置 `currentPlayQueueProvider` 和 `lastQueueConnectionIdProvider`（取当前活跃连接 id），`push('/player')`
- 长按曲目：进入选择模式，选中该曲目
- 批量删除：调用 `removeTracksFromPlaylistProvider`，退出选择模式
- 排序选项：添加时间、文件名升序、文件名降序

`AddTracksBrowserSheet`（`ConsumerStatefulWidget`）：
- 通过 `showModalBottomSheet(isScrollControlled: true)` 打开
- 使用 **`ProviderScope` override** 注入独立的 `NavigationStackNotifier`，避免与主浏览器 tab 共享导航状态：
  ```dart
  ProviderScope(
    overrides: [navigationStackProvider.overrideWith((_) => NavigationStackNotifier())],
    child: AddTracksBrowserSheet(playlistId: id),
  )
  ```
- 本地状态：`Set<String> _selectedPaths`
- 渲染 `BreadcrumbBar` + 目录内容（复用 `directoryContentsProvider`）：目录可点击导航，音频文件显示 `Checkbox`
- 顶部：「添加曲目」标题 + 「全选/取消全选」+ 「确认 (N)」按钮
- 确认：调用 `addTracksToPlaylistProvider`（内部去重），关闭弹窗

**测试用例**：PLY-T73 ~ PLY-T85

---

### CON-08 连接表单支持 DDNS 域名提示

**来源**：新功能 | **优先级**：P2
**涉及文件**：
- `lib/features/connection/widgets/connection_form.dart`（修改 hint text 和校验提示文案）

**依赖**：无

**实现要点**：

现有代码已完整支持域名输入（`normaliseWebDavUrl` 和 `isValidWebDavUrl` 均基于 `Uri.parse`，域名与 IP 均可正常解析），无需改动网络层或数据层。

仅需更新 UI 文案：
- 服务器地址字段 `hintText`：`'http://192.168.1.100:5005'` → `'http://192.168.1.100:5005 或 http://nas.example.com'`
- URL 校验失败提示：`'请输入有效的服务器地址（如 http://192.168.1.1:5005）'` → `'请输入有效的服务器地址（如 http://192.168.1.100:5005 或 http://nas.example.com）'`

**测试用例**：CON-T35 ~ CON-T37

- CON-T35：输入 DDNS 域名（如 `http://nas.example.com`），`isValidWebDavUrl` 返回 true
- CON-T36：输入带端口的域名（如 `http://nas.example.com:5005`），校验通过
- CON-T37：输入裸域名（无 scheme，如 `nas.example.com`），`normaliseWebDavUrl` 自动补全 `http://` 后校验通过

---

## 已完成

（暂无）
