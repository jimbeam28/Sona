# 实现合规性分析报告

> 分析日期：2026-05-11  
> 覆盖模块：Connection · Browser · Player · Timer · Progress · Settings  
> 分析依据：`docs/module-*.md` 设计文档 + `lib/` 实现代码

---

## 总体结论

| 模块 | 实现完整度 | 关键问题数 |
|------|-----------|-----------|
| Connection | 高 | 2（轻微） |
| Browser | 高 | 1（轻微） |
| Player | **中** | **5（严重）** |
| Timer | **低** | **3（严重）** |
| Progress | **中** | **3（严重）** |
| Settings | 高 | 0 |

---

## 一、Connection 模块

### CON-01 添加 WebDAV 连接 ✅ 基本符合

实现基本匹配设计，存在一处轻微偏差：

**问题 1（轻微）—— URL 格式校验未在表单层做**  
`connection_form.dart:137` 的 `_validateUrl` 仅校验非空，不校验格式合法性。注释说交给 `WebDavClient.isValidWebDavUrl` 处理，但这意味着用户输入明显错误的 URL（如 `ftp://...`）时，需要等到点击"测试连接"后才能收到提示，而非即时反馈。  
**建议**：在 `_validateUrl` 中增加 `isValidWebDavUrl(normaliseWebDavUrl(value))` 前置校验。

### CON-02 连接验证 ✅ 完全符合

超时 5s、错误文案、状态码映射（207/401/403/404）均与设计文档一致。

### CON-03 连接配置持久化 ✅ 完全符合

数据库 schema 匹配，密码通过 `flutter_secure_storage` 存储，DB 中只保存引用 key，符合安全设计。

### CON-04 切换当前连接 ⚠️ 存在偏差

`connection_provider.dart:149` 的 `switchActiveConnectionProvider` 仅 invalidate 了 `activeConnectionProvider` 和 `connectionListProvider`，**未清除文件浏览器缓存**。

**设计文档要求**（module-connection.md §3.4）：「更新 `connections.is_active` 字段，同时**清空文件浏览缓存**，触发重新加载」

**影响**：切换 NAS 连接后，Browser 页面可能继续显示旧连接的缓存目录内容，直到用户下拉刷新。

**建议**：在 `switchActiveConnectionProvider` 末尾调用 `ref.invalidate(directoryCacheProvider)` 和 `ref.invalidate(navigationStackProvider)`。

### CON-05 编辑连接配置 ⚠️ 存在偏差

**访问方式不符**：设计文档（§3.5）要求「连接列表 → **长按或右滑** → 编辑」，实现使用 `PopupMenuButton`（三点菜单）。

**核心逻辑符合**：修改后重验证、仅 displayName 变化时可免验证，均已正确实现。

**建议**：如果 UX 经过评审认可三点菜单方案，需更新设计文档以消除歧义；否则补充滑动操作（`Dismissible` 或 `flutter_slidable`）。

### CON-06 删除连接配置 ⚠️ 存在偏差

与 CON-05 相同的访问方式偏差。最后一条连接保护、级联删除播放进度、删除 secure storage 密码均已正确实现。

---

## 二、Browser 模块

### BRW-01 目录列表加载 ✅ 完全符合

骨架屏、错误+重试、空目录提示、支持格式列表均与设计一致。

### BRW-02 目录导航 ✅ 完全符合

面包屑 `...` 折叠（`computeBreadcrumbLayout`）、`PopScope` 系统返回键处理、`popTo` 跳层导航均已实现。

### BRW-03 音频文件过滤 ✅ 完全符合

`.m4b`/`有声书`/`audiobook` 分类为有声书图标，其余音频显示音乐图标，与设计一致。

### BRW-04 选择文件播放 ⚠️ 存在轻微问题

整体流程正确：从当前目录构建队列、检查进度记录、弹出恢复对话框。

**问题（轻微）—— 进度加载存在竞争窗口**  
`browser_screen.dart:36` 通过 `ref.listen` 触发进度加载，但 `loadProgressForDirectoryProvider` 是异步的。如果用户在目录加载完成后立即点击文件（进度尚未从 DB 查回），`playProgressProvider(path)` 返回 null，恢复对话框不会弹出，会直接从头播放。

**建议**：在 `onFileTap` 中等待 `loadProgressForDirectoryProvider` 完成后再决定是否显示对话框；或在 `directoryContentsProvider` 中同时完成进度预加载。

### BRW-05 目录内容缓存 ✅ 完全符合

缓存 key 含 `connectionId:path`，切换连接后 key 不同，不会出现数据串扰。

### BRW-06 下拉刷新 ✅ 完全符合

`RefreshIndicator` 清除对应 key 缓存后重新 PROPFIND，逻辑正确。

### BRW-07 文件排序 ✅ 完全符合

三种排序选项、目录永远置顶、SharedPreferences 持久化，均与设计文档一致。

---

## 三、Player 模块

### PLY-01 音频流式播放 ✅ 基本符合

`AudioSourceBuilder` 正确构建带 Basic Auth 头的 `AudioSource.uri`；`PlayerScreen._loadAndPlay` 读取活跃连接并加载。

**潜在问题**：`AudioSourceBuilder.build` 使用 `buildUri`（替换 base URL 的路径），而非 `buildUriWithBasePath`（保留 base URL 的子路径）。当连接 URL 包含子路径（如 `http://host/dav/`）时，文件路径会覆盖 `/dav/`，导致 URL 错误。建议根据 connection 的 `basePath` 选择正确的构建方法。

### PLY-02 基础播放控制 🔴 存在严重缺陷

**缺陷 1（严重）—— 缺少上一首/下一首按钮**  
设计文档（§3.2）要求「上一首 / 下一首」控制。`_PlaybackControls` 只有步进快退/快进（`skipBackward`/`skipForward`）和播放/暂停，**完全没有切换到上一首或下一首的 UI**。`MiniPlayerBar` 有"下一首"按钮，但完整播放器页面没有。

**建议**：在 `_PlaybackControls` 中添加「上一首」和「下一首」IconButton，调用逻辑参考 `MiniPlayerBar._NextButton`。

**缺陷 2（严重）—— 自动保存进度未实现**  
设计文档（§3.2）：「每 10 秒自动保存一次当前播放位置到数据库」。`upsertProgressProvider` 存在于 `progress_provider.dart` 但在 `PlayerScreen` 中**从未被调用**。无论是 10s 定时保存、暂停时保存还是切换曲目时保存，均未实现。

**建议**：在 `PlayerScreen` 的 `initState` 中启动 `Timer.periodic(10s)` 调用 `upsertProgressProvider`；在 `player.playerStateStream` 监听暂停事件时保存；在曲目切换时保存前一首进度。

**次要偏差 —— 时间格式**  
设计（§3.2）展示格式为 `00:00:00`（始终三段），`formatDuration` 对不足 1 小时的时长输出 `MM:SS`，如 `05:30`。对有声书（通常超 1 小时）影响不大，但与文档有差异。

### PLY-03 后台播放 🔴 核心功能缺失

**设计文档（§3.3）要求**：通过 `audio_service` 将 `just_audio` 包装为 Android 前台服务，配置 `AndroidManifest.xml`，使 app 后台时音频继续播放。

**实际状态**：设计文档 §7 指向的 `lib/core/services/audio_handler.dart` **文件不存在**。当前实现中：
- 使用裸 `AudioPlayer`（just_audio），无前台服务
- `BackgroundPlaybackNotifier` / `BackgroundPlaybackConfig` 是**纯逻辑状态机**，不驱动任何实际的后台播放
- `background_playback.dart:9` 注释自己承认：「The actual audio_service wiring lives in lib/core/services/audio_handler.dart」

**影响**：在 Android 上，app 切后台后系统很可能暂停 Dart isolate，导致音频停止播放。

**建议**：实现 `NasAudioHandler extends BaseAudioHandler`，使用 `AudioService.init()` 初始化；在 `AndroidManifest.xml` 中添加相应权限和 service 声明。

### PLY-04 锁屏/通知栏媒体控件 🔴 核心功能缺失

与 PLY-03 同根问题：`audio_service` 未集成。

`media_control_model.dart` 定义了耳机按键映射逻辑（`mapHeadphoneAction`）和 `TrackMetadata` 模型，但这些纯逻辑**从未被 AudioHandler 调用**（AudioHandler 不存在）。通知栏控件和锁屏控件均无法工作。

### PLY-05 播放队列管理 ⚠️ 存在偏差

**缺失 1 —— 无队列视图 UI**  
设计（§3.5）：「查看当前队列（底部弹出列表）」。`PlayerScreen._buildReady` 没有"查看队列"按钮，无法展示队列列表。

**缺失 2 —— 队列不持久化**  
`currentPlayQueueProvider` 是 `StateProvider`（纯内存），app 重启后丢失。设计（§3.5）要求「应用重启后恢复上次的播放队列和位置」。`PlayQueue.toMap/fromMap` 方法已存在但未被用于 SharedPreferences 持久化。

### PLY-06 播放模式切换 ✅ 基本符合

`_PlayModeControl` 循环切换四种模式，图标反映当前模式。`MiniPlayerBar` 的 Next 按钮正确传入 `playModeProvider` 的值到 `PlayQueue.nextIndex`。

### PLY-07 播放速度调节 ✅ 基本符合，存在小问题

**小问题**：`_SpeedControl` 调用 `player.setSpeed(speed)` 后只更新了 just_audio player，未更新 `currentSpeedProvider`。若其他地方读取 `currentSpeedProvider`（如恢复播放时），会读到旧值。建议在回调中同步 `ref.read(currentSpeedProvider.notifier).state = speed`。

### PLY-08 迷你播放器 ✅ 完全符合

显示时机、内容、进度条不可拖拽、点击主体跳转完整播放器，均与设计一致。

---

## 四、Timer 模块

### TMR-01 设置固定时长定时 ✅ 逻辑符合，后台可靠性存疑

底部弹出菜单、5/10/15 分钟选项均已实现。

**后台可靠性问题**：`TimerService` 使用 `DateTime.now()` 对比 `endTime`，由 `checkTimerExpiryProvider` 的调用方周期检查。设计（§3.1）要求「在 `AudioHandler`（前台服务）中管理，确保后台也能触发停止」。由于 `audio_service` 未集成，定时器在 app 后台时无法保证触发。

### TMR-02 播完当前音频后停止 🔴 触发机制缺失

**设计（§3.2）要求**：监听 `_player.processingStateStream`，当 `ProcessingState.completed` 时调用 `pause()`。

**实际状态**：`TimerService.onTrackCompleted()` 逻辑正确，但 **`PlayerScreen` 或任何播放相关代码中都没有监听 `player.processingStateStream`**，`onTrackCompletedProvider` 从未被调用。

**影响**：「播完当前」模式完全无效——当曲目播完时，播放会继续切换下一首（或停在末尾），不会触发暂停。

**建议**：在 `PlayerScreen.initState` 中添加：
```dart
player.processingStateStream.listen((state) {
  if (state == ProcessingState.completed) {
    final triggered = ref.read(onTrackCompletedProvider)();
    if (triggered) player.pause();
  }
});
```

### TMR-03 定时倒计时显示 ✅ 完全符合

格式（> 60s 显示「X分钟」，≤ 60s 显示「Xs」，afterCurrent 显示「播完停止」），`TimerButton` 展示，每秒更新的 Stream，均与设计一致。

### TMR-04 取消定时 ✅ 完全符合

激活时显示「取消定时」选项，`TimerService.cancel()` 幂等，行为正确。

### TMR-05 定时到期执行停止 🔴 到期检查未接入

**设计（§3.5）要求**：「调用 `AudioHandler.pause()`，清除定时状态，若应用在前台显示 Snackbar」

**实际状态**：`checkTimerExpiryProvider` 存在，但在 `PlayerScreen` 中**没有任何周期性检查调用**。`TimerService.checkExpired()` 永远不会被触发，固定时长定时器到期后什么都不会发生。

**建议**：在 `PlayerScreen.initState` 中启动 `Timer.periodic(Duration(seconds: 1))`，每秒调用 `ref.read(checkTimerExpiryProvider)()`；若返回 true 则 `player.pause()` 并显示 Snackbar。（理想情况下应在 AudioHandler 前台服务中实现，以支持后台触发）

---

## 五、Progress 模块

### PRG-01 自动保存播放进度 🔴 保存触发点全部缺失

**设计（§3.1）要求**五个保存时机：①每 10 秒、②用户暂停时、③切换曲目时、④进入后台时、⑤app 关闭时。

**实际状态**：`ProgressDao.upsert()` 和 `upsertProgressProvider` 均已正确实现业务规则（< 5s 不存、接近结尾清除），但 **`PlayerScreen` 没有调用任何保存逻辑**。进度永远不会被写入数据库。

**建议**：在 `PlayerScreen` 中：
- 启动 `Timer.periodic(10s)` 调用 `upsertProgressProvider`
- 监听 `player.playerStateStream`，在 `playing→paused` 转换时保存
- 在 `dispose()` 中保存当前进度（覆盖 ⑤ 场景）
- 监听 `AppLifecycleState.paused` 时保存（覆盖 ④ 场景）

### PRG-02 启动时恢复播放进度 ✅ 基本符合

点击文件时查询进度逻辑正确。注意 BRW-04 中已分析的进度加载竞争窗口问题同样影响此处。

### PRG-03 进度恢复确认提示 ✅ 完全符合

5 秒倒计时、自动选择「继续播放」、按钮显示倒计时数字，均与设计一致。

**注**：对话框标题为「恢复播放进度」，设计文档示例内容为「上次播放到 1:23:45 / 是否从此处继续？」。内容实现正确，标题用词差异属于产品文案范畴。

### PRG-04 清除单个文件进度 🔴 UI 入口缺失

**设计（§3.4）要求**：「文件列表**长按** → 『清除播放进度』（仅有进度记录的文件显示此选项）」

**实际状态**：`AudioFileListTile` 无 `onLongPress` 回调；`browser_screen.dart` 的 `_FileList` 也未传入长按处理器；`clearProgressProvider` 存在但没有 UI 调用入口。

**建议**：
1. 在 `AudioFileListTile` 添加 `onLongPress` 参数
2. 在 `browser_screen.dart` 检查 `playProgressProvider(file.path) != null` 来决定是否显示清除选项
3. 弹出 `BottomSheet` 或 `AlertDialog` 确认后调用 `clearProgressProvider`

---

## 六、Settings 模块

### SET-01 默认播放速度设置 ✅ 完全符合

选项 0.5x–2.0x，持久化到 SharedPreferences，与设计一致。

### SET-02 NAS 连接管理入口 ✅ 完全符合

`ListTile` → `/connections`，行为正确。

### SET-03 界面主题切换 ✅ 完全符合

跟随系统/亮色/暗色，`MaterialApp` 的 `themeMode` 从 `themeModeProvider` 读取，持久化正确。

### SET-04 快进/快退步长设置 ✅ 完全符合

选项 10/15/30/60 秒，同步更新 `seekStepProvider`（player 实时生效），正确。

### SET-05 关于页面 ✅ 完全符合

应用名、版本、开源许可证列表均已展示。

---

## 七、问题汇总与优先级

### P0 严重缺陷（核心功能无法使用）

| # | 问题 | 影响功能 | 位置 |
|---|------|---------|------|
| 1 | `audio_service` / `AudioHandler` 完全未实现，后台播放和媒体控件缺失 | PLY-03, PLY-04 | 需新建 `lib/core/services/audio_handler.dart` |
| 2 | PlayerScreen 没有上一首/下一首按钮 | PLY-02 | `player_screen.dart:_PlaybackControls` |
| 3 | 播放进度自动保存触发点全部缺失 | PRG-01 | `player_screen.dart` 缺少定时器和事件监听 |
| 4 | TMR-02「播完当前」触发机制缺失（未监听 processingStateStream） | TMR-02 | `player_screen.dart` |
| 5 | TMR-05 定时到期检查从未被调用 | TMR-05 | `player_screen.dart` 缺少周期检查 |
| 6 | PRG-04 长按清除进度的 UI 入口缺失 | PRG-04 | `file_list_item.dart`, `browser_screen.dart` |

### P1 功能偏差（功能存在但行为与设计不符）

| # | 问题 | 影响功能 | 位置 |
|---|------|---------|------|
| 7 | 切换连接后未清除浏览器缓存 | CON-04 | `connection_provider.dart:switchActiveConnectionProvider` |
| 8 | 无播放队列查看 UI | PLY-05 | `player_screen.dart` 缺少队列按钮 |
| 9 | 播放队列重启后丢失（未持久化） | PLY-05 | `browser_provider.dart:currentPlayQueueProvider` |
| 10 | 目录进度加载与文件点击的竞争窗口 | PRG-02, BRW-04 | `browser_screen.dart:36` |
| 11 | 建议使用 `buildUriWithBasePath` 处理含子路径的连接 URL | PLY-01 | `player_screen.dart:_loadAndPlay` |

### P2 轻微偏差（不影响主流程）

| # | 问题 | 影响功能 | 位置 |
|---|------|---------|------|
| 12 | CON-05/CON-06 访问方式用三点菜单代替长按/右滑 | CON-05, CON-06 | `connection_list_screen.dart` |
| 13 | 时间格式 `MM:SS` 而非 `00:00:00` | PLY-02 | `player_provider.dart:formatDuration` |
| 14 | 调速后 `currentSpeedProvider` 未同步 | PLY-07 | `player_screen.dart:_SpeedControl` |
| 15 | 表单层 URL 格式无前置校验 | CON-01 | `connection_form.dart:_validateUrl` |
