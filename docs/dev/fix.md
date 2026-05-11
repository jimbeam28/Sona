# 修复开发计划

> 依据：`docs/analysis.md` 分析报告  
> 制定日期：2026-05-11  
> 优先级分级：P0 核心功能缺失 → P1 功能偏差 → P2 轻微偏差

---

## 总览

| 批次 | 优先级 | 任务数 | 说明 |
|------|--------|--------|------|
| Batch A | P0 | 6 | 核心功能无法使用，必须优先修复 |
| Batch B | P1 | 5 | 功能偏差，不影响基础体验但与设计不符 |
| Batch C | P2 | 4 | 轻微偏差，有时间再处理 |

---

## Batch A — P0 严重缺陷

### A-1  实现 AudioHandler（后台播放 + 媒体控件）

**关联问题**：PLY-03 后台播放、PLY-04 锁屏/通知栏媒体控件  
**当前状态**：`lib/core/services/audio_handler.dart` 文件不存在。`BackgroundPlaybackNotifier` 是纯逻辑状态机，不驱动实际的后台服务。

**需要完成的工作：**

1. **新建 `lib/core/services/audio_handler.dart`**  
   实现 `NasAudioHandler extends BaseAudioHandler with QueueHandler, SeekHandler`：
   - 持有 `AudioPlayer _player` 实例
   - 实现 `play() / pause() / stop() / seek() / skipToNext() / skipToPrevious() / skipToQueueItem(int) / setSpeed(double)`
   - 在 `play/pause/stop` 中同步 `playbackState` 流，让 `audio_service` 驱动通知栏按钮状态
   - 在 `skipToNext / skipToPrevious` 中读取 `PlayQueue`，更新 `mediaItem` 流
   - 在 `onTaskRemoved()` 中停止播放并保存进度（配合 A-3）

2. **在 `main.dart` 使用 `AudioService.init()` 初始化 handler**  
   ```dart
   final handler = await AudioService.init(
     builder: () => NasAudioHandler(),
     config: const AudioServiceConfig(
       androidNotificationChannelId: 'com.example.nas_audio.channel',
       androidNotificationChannelName: 'NAS 音乐播放器',
       androidNotificationOngoing: true,
     ),
   );
   ```
   将 handler 暴露为 Riverpod provider（`audioHandlerProvider`）。

3. **更新 `android/app/src/main/AndroidManifest.xml`**（按设计文档 §3.3）：
   - 添加 `android.permission.FOREGROUND_SERVICE`
   - 声明 `AudioServiceIsolate` service，`android:foregroundServiceType="mediaPlayback"`

4. **将现有 `audioPlayerProvider` 替换为从 handler 内部获取 player**  
   或保持独立 player，由 handler 委托调用。所有原来直接调用 `player.play/pause/seek` 的地方改为调用 `handler` 的对应方法。

5. **接入耳机按键**  
   `audio_service` 自动处理媒体键事件，handler 中 `onMediaButton` 调用 `mapHeadphoneAction`（`media_control_model.dart` 已实现）映射到对应操作。

**涉及文件**：
- 新建：`lib/core/services/audio_handler.dart`
- 修改：`lib/main.dart`
- 修改：`android/app/src/main/AndroidManifest.xml`
- 修改：`lib/features/player/player_screen.dart`（操作改走 handler）
- 修改：`lib/features/player/player_provider.dart`（添加 `audioHandlerProvider`）

---

### A-2  PlayerScreen 添加上一首/下一首按钮

**关联问题**：PLY-02 基础播放控制  
**当前状态**：`_PlaybackControls` 只有快退/快进/播放暂停，缺少曲目切换按钮。

**需要完成的工作：**

1. 在 `player_screen.dart` 的 `_PlaybackControls.build` 中调整按钮布局：
   ```
   [上一首]  [快退Xs]  [播放/暂停]  [快进Xs]  [下一首]
   ```

2. 上一首/下一首的点击逻辑：
   - 读取 `currentPlayQueueProvider` 和 `playModeProvider`
   - 调用 `PlayQueue.previousIndex / nextIndex` 获取目标 index
   - 更新 `currentPlayQueueProvider.notifier.state` 到新 index 的队列
   - 通过 handler（A-1 完成后）或 player 加载新曲目并播放

3. 按钮 enabled/disabled 状态：
   - `previousIndex == null` 时上一首按钮置灰
   - `nextIndex == null` 时下一首按钮置灰

**涉及文件**：
- 修改：`lib/features/player/player_screen.dart`（`_PlaybackControls` widget）

---

### A-3  实现播放进度自动保存（五个触发点）

**关联问题**：PRG-01 自动保存播放进度  
**当前状态**：`upsertProgressProvider` 和 `ProgressDao.upsert` 均已实现，但 `PlayerScreen` 从未调用保存逻辑。

**需要完成的工作：**

在 `PlayerScreen._PlayerScreenState` 中添加以下逻辑：

1. **每 10 秒定时保存**（触发点①）：
   ```dart
   Timer.periodic(const Duration(seconds: 10), (_) => _saveProgress());
   ```
   在 `dispose()` 中 `cancel()`。

2. **暂停时立即保存**（触发点②）：
   监听 `player.playerStateStream`，在 `playing→paused` 转换时调用 `_saveProgress()`。

3. **切换曲目时保存上一首进度**（触发点③）：
   在切换到上一首/下一首的逻辑中，先保存当前进度再切曲。

4. **进入后台时保存**（触发点④）：
   在 `_PlayerScreenState` 中混入 `WidgetsBindingObserver`，在 `didChangeAppLifecycleState(AppLifecycleState.paused)` 时调用 `_saveProgress()`。

5. **页面销毁时保存**（触发点⑤）：
   在 `dispose()` 中调用 `_saveProgress()`（同步版或最后一次异步写）。

`_saveProgress` 辅助方法：
```dart
Future<void> _saveProgress() async {
  final queue = ref.read(currentPlayQueueProvider);
  final conn  = ref.read(activeConnectionProvider).valueOrNull;
  if (queue == null || conn?.id == null) return;
  final player = ref.read(audioPlayerProvider);
  ref.read(upsertProgressProvider)(
    connectionId: conn!.id!,
    filePath: queue.current.path,
    positionMs: player.position.inMilliseconds,
    durationMs: player.duration?.inMilliseconds,
  );
}
```

**涉及文件**：
- 修改：`lib/features/player/player_screen.dart`

---

### A-4  TMR-02 接入 processingStateStream 触发「播完当前」

**关联问题**：TMR-02 播完当前音频后停止  
**当前状态**：`TimerService.onTrackCompleted()` 逻辑正确，但 `PlayerScreen` 从未监听 `player.processingStateStream`，`onTrackCompletedProvider` 从未被调用。

**需要完成的工作：**

在 `PlayerScreen._loadAndPlay()` 末尾（或 `initState`）添加：
```dart
_processingSubscription = player.processingStateStream.listen((state) {
  if (state == ProcessingState.completed) {
    final triggered = ref.read(onTrackCompletedProvider)();
    if (triggered) {
      player.pause();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('定时停止已触发')),
        );
      }
    } else {
      // 正常自动播放下一首（PLY-05 逻辑）
      _playNext();
    }
  }
});
```

在 `dispose()` 中取消订阅。

**说明**：A-1 完成后，这部分逻辑可迁移到 `NasAudioHandler` 内实现，以支持后台触发。

**涉及文件**：
- 修改：`lib/features/player/player_screen.dart`

---

### A-5  TMR-05 添加定时到期的周期检查

**关联问题**：TMR-05 定时到期执行停止  
**当前状态**：`checkTimerExpiryProvider` 存在但从未被调用，固定时长定时器到期后什么都不发生。

**需要完成的工作：**

在 `PlayerScreen._PlayerScreenState.initState` 中添加每秒检查：
```dart
_timerExpiryChecker = Timer.periodic(const Duration(seconds: 1), (_) {
  final expired = ref.read(checkTimerExpiryProvider)();
  if (expired && mounted) {
    final player = ref.read(audioPlayerProvider);
    player.pause();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('定时停止已触发')),
    );
  }
});
```

在 `dispose()` 中 `cancel()`。

**说明**：A-1 完成后迁移到 `NasAudioHandler` 内以支持后台触发。

**涉及文件**：
- 修改：`lib/features/player/player_screen.dart`

---

### A-6  PRG-04 添加长按清除进度 UI 入口

**关联问题**：PRG-04 清除单个文件进度  
**当前状态**：`clearProgressProvider` 已实现，但 `AudioFileListTile` 无长按回调，`_FileList` 也未传入长按处理器。

**需要完成的工作：**

1. **`file_list_item.dart`**：为 `AudioFileListTile` 添加 `onLongPress` 参数：
   ```dart
   class AudioFileListTile extends StatelessWidget {
     final VoidCallback? onLongPress;   // ← 新增
     // ...
   }
   // 在 ListTile 上传入：onLongPress: onLongPress,
   ```

2. **`browser_screen.dart`** 的 `_FileList.itemBuilder` 中，为 `AudioFileListTile` 传入 `onLongPress`：
   ```dart
   AudioFileListTile(
     file: file,
     onTap: (_) => onFileTap(file),
     onLongPress: onFileLongPress != null ? () => onFileLongPress!(file) : null,
   )
   ```

3. **`browser_screen.dart`** 的 `BrowserScreen.build` 中添加长按处理逻辑：
   - 读取 `playProgressProvider(file.path)` 判断是否有进度
   - 有进度：弹出 `showModalBottomSheet` 显示「清除播放进度」选项
   - 用户确认后调用 `ref.read(clearProgressProvider)(connectionId: ..., filePath: ...)`
   - 无进度：可不响应或展示空菜单

**涉及文件**：
- 修改：`lib/features/browser/widgets/file_list_item.dart`
- 修改：`lib/features/browser/browser_screen.dart`

---

## Batch B — P1 功能偏差

### B-1  切换连接后清除浏览器缓存

**关联问题**：CON-04 切换当前连接  
**当前状态**：`switchActiveConnectionProvider` 切换后只 invalidate 了连接相关 provider，未清缓存，Browser 页面会显示旧连接的目录内容。

**修复方案**：在 `connection_provider.dart` 的 `switchActiveConnectionProvider` 末尾添加：
```dart
ref.invalidate(directoryCacheProvider);
// 重置导航栈回根目录，避免旧路径在新连接上报错
ref.invalidate(navigationStackProvider);
```

需要在 `connection_provider.dart` 中 import `browser_provider.dart`（注意循环依赖风险；如有循环，可将 clear 逻辑提取到调用方 UI 层处理）。

**涉及文件**：
- 修改：`lib/features/connection/connection_provider.dart`  
  或 修改：`lib/features/connection/connection_list_screen.dart`（在 `_switchConnection` 方法中调用）

---

### B-2  播放队列查看 UI

**关联问题**：PLY-05 播放队列管理  
**当前状态**：`PlayerScreen` 无「查看队列」按钮，无法展示队列列表。

**修复方案**：

1. 在 `player_screen.dart` 的 `_buildReady` 中添加「队列」图标按钮（AppBar actions 或底部行）。

2. 点击后 `showModalBottomSheet`，展示 `currentPlayQueueProvider` 中的文件列表：
   - 每行显示文件名，当前播放项高亮
   - 点击任意行：更新 `currentPlayQueueProvider` 到目标 index，触发加载播放

**涉及文件**：
- 修改：`lib/features/player/player_screen.dart`

---

### B-3  播放队列持久化（重启恢复）

**关联问题**：PLY-05 队列持久化  
**当前状态**：`currentPlayQueueProvider` 是内存 `StateProvider`，重启后丢失。`PlayQueue.toMap/fromMap` 序列化方法已存在。

**修复方案**：

1. 在 `browser_provider.dart` 或新建 `lib/features/player/queue_persistence.dart` 中：
   - 每次 `currentPlayQueueProvider` 变化时，将 `queue.toMap()` + 文件路径列表写入 `SharedPreferences`（key: `last_play_queue`）
   - 对于 `NasFile` 的重建，只持久化 `filePath`；重建时从缓存或重新 PROPFIND 获取元数据（或仅存 path+name，足够恢复播放）

2. 在 `_OnboardingPage` 或 `BrowserScreen.initState` 中读取持久化队列，恢复 `currentPlayQueueProvider`。

**注意**：文件元数据（NasFile）不完整时降级处理，以 path 构建最小化 NasFile 即可支持播放恢复。

**涉及文件**：
- 修改：`lib/features/browser/browser_provider.dart` 或新建队列持久化辅助文件
- 修改：`lib/main.dart`（启动时读取）

---

### B-4  消除目录进度加载竞争窗口

**关联问题**：BRW-04、PRG-02  
**当前状态**：`loadProgressForDirectoryProvider` 异步触发，用户快速点击文件时进度数据可能尚未就绪，导致跳过恢复对话框。

**修复方案**：

在 `browser_screen.dart` 的 `onFileTap` 回调中，先 await 进度加载完成再决策：

```dart
onFileTap: (tappedFile) async {
  // 确保当前目录进度已加载
  await ref.read(loadProgressForDirectoryProvider(currentPath).future);
  final progress = ref.read(playProgressProvider(tappedFile.path));
  // ... 后续逻辑不变
}
```

由于 `FutureProvider.family` 会缓存结果，重复 await 同一 path 不会触发重复请求。

**注意**：`onFileTap` 从同步改为 `async`，需要在调用处处理 `Future`（`// ignore: discarded_futures` 注释上移或包装）。

**涉及文件**：
- 修改：`lib/features/browser/browser_screen.dart`

---

### B-5  修复含子路径连接 URL 的音频源构建

**关联问题**：PLY-01  
**当前状态**：`AudioSourceBuilder.build` 使用 `buildUri`（忽略 base URL 的路径部分），当连接 URL 为 `http://host/dav/` 时，文件路径会覆盖 `/dav/`，导致 404。

**修复方案**：

在 `player_screen.dart` 的 `_loadAndPlay` 中，根据 connection URL 是否含非根路径决定使用哪个构建方法：

```dart
final source = activeConn.basePath != '/'
    ? AudioSourceBuilder.buildWithBasePath(
        baseUrl: activeConn.url,
        filePath: queue.current.path,
        username: activeConn.username,
        password: password,
      )
    : AudioSourceBuilder.build(
        baseUrl: activeConn.url,
        filePath: queue.current.path,
        username: activeConn.username,
        password: password,
      );
```

或统一使用 `buildWithBasePath`（其逻辑在根路径时与 `build` 等价）。

**涉及文件**：
- 修改：`lib/features/player/player_screen.dart`

---

## Batch C — P2 轻微偏差

### C-1  CON-05/CON-06 补充滑动操作

**关联问题**：CON-05 编辑连接、CON-06 删除连接  
**建议**：引入 `flutter_slidable` 包，为 `_ConnectionListView` 的每个 tile 添加右滑显示「编辑」/「删除」操作，保持三点菜单作为备用入口。或在设计评审中确认接受三点菜单方案并更新设计文档。

**涉及文件**：
- 修改：`lib/features/connection/connection_list_screen.dart`
- 修改：`pubspec.yaml`（添加 `flutter_slidable` 依赖）

---

### C-2  时间格式补齐为三段式

**关联问题**：PLY-02 时间显示格式  
**建议**：将 `player_provider.dart` 的 `formatDuration` 修改为始终输出 `HH:MM:SS` 或 `H:MM:SS` 格式：
```dart
// 修改前：不足 1 小时显示 MM:SS
// 修改后：始终显示 H:MM:SS（与设计文档 "00:00:00" 一致）
if (hours > 0) return '$hours:$mm:$ss';
return '0:$mm:$ss';   // ← 加 "0:" 前缀
```
或根据产品决策保持 `MM:SS`（有声书通常超 1 小时，差异不大）。

**涉及文件**：
- 修改：`lib/features/player/player_provider.dart:284`（`formatDuration` 函数）

---

### C-3  调速后同步 currentSpeedProvider

**关联问题**：PLY-07 播放速度  
**建议**：在 `player_screen.dart` 的 `_SpeedControl._showSpeedSelector` 的 `onTap` 回调中，调用 `player.setSpeed(speed)` 的同时更新 Provider：
```dart
onTap: () {
  player.setSpeed(speed);
  ref.read(currentSpeedProvider.notifier).state = speed;  // ← 新增
  Navigator.of(ctx).pop();
},
```

**涉及文件**：
- 修改：`lib/features/player/player_screen.dart`（`_SpeedControl` widget）

---

### C-4  表单层添加 URL 格式前置校验

**关联问题**：CON-01 URL 验证  
**建议**：在 `connection_form.dart` 的 `_validateUrl` 中添加格式校验，提供即时反馈：
```dart
String? _validateUrl(String? value) {
  if (value == null || value.trim().isEmpty) return '请输入服务器地址';
  final normalised = normaliseWebDavUrl(value.trim());
  if (!isValidWebDavUrl(normalised)) return '请输入有效的服务器地址（如 http://192.168.1.1:5005）';
  return null;
}
```

需要在 `connection_form.dart` 中 import `webdav_client.dart`。

**涉及文件**：
- 修改：`lib/features/connection/widgets/connection_form.dart`

---

## 实施顺序建议

```
A-5 (定时检查)          ← 独立，无依赖，30 分钟
A-6 (长按清除进度 UI)   ← 独立，无依赖，1 小时
A-4 (processingStream)  ← 独立，无依赖，30 分钟
A-3 (进度自动保存)      ← 独立，无依赖，1 小时
A-2 (上一首/下一首按钮) ← 独立，无依赖，1 小时
  ↓
B-4 (竞争窗口)          ← 独立，1 小时
B-5 (子路径 URL)        ← 独立，30 分钟
B-1 (切连接清缓存)      ← 独立，30 分钟
C-2 / C-3 / C-4        ← 各自独立，合计 1 小时
  ↓
A-1 (AudioHandler)      ← 最复杂，依赖 A-2/A-3/A-4/A-5 完成后合并 ≈ 1 天
  ↓
B-2 (队列查看 UI)       ← 可与 A-1 并行，1 小时
B-3 (队列持久化)        ← 建议在 A-1 后处理（与 handler 生命周期协同）
C-1 (滑动操作)          ← 最后，可选
```

A-1（AudioHandler）是整个修复中工作量最大、风险最高的任务，建议单独一个 PR，其余 A/B/C 任务可按模块分批提交。
