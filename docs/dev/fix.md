# 修复开发计划

> 分析日期：2026-05-16
> Bug 描述：跨功能集成路径分析发现9个问题——迷你栏操作绕过统一入口导致后台功能断裂、密码缺失静默失败、进度缓存过时、连接切换URL错配、速度状态不一致、异步操作无mounted保护、队列恢复连接不匹配、迷你栏缺定时显示
> 优先级分级：P0 核心功能断裂 → P1 功能异常 → P2 边界/体验缺陷

---

## 总览

| 批次 | 优先级 | 任务数 | 说明 |
|------|--------|--------|------|
| Batch D | P0 | 2 | 迷你栏操作绕过核心入口，功能体系崩塌 |
| Batch E | P1 | 3 | 进度缓存、连接切换、速度同步问题 |
| Batch F | P2 | 4 | 边界保护、连接校验、UX增强 |

---

## Bug 分析

### BUG-12 迷你栏切歌/队列选歌绕过 _loadAndPlay()，导致后台功能全部失效

**现象**：在迷你播放栏点击"下一曲"或通过队列按钮选择歌曲后，歌曲可以正常切换播放，但后续的自动下一曲、10秒自动保存进度、暂停保存进度、默认速度应用、定时"播完当前"功能全部失效，直到用户进入全屏播放页面触发 `_loadAndPlay()` 后才恢复。

**根因**：`mini_player_bar.dart` 中 `_NextButton.onPressed`（第210-228行）和 `_showQueueSheet`（第156-182行）各自独立实现了一套"停止→设置音频源→播放"的流程，直接调用 `player.stop()` + `player.setAudioSource(source)` + `player.play()`。而 `player_screen.dart:_loadAndPlay()`（第136-250行）在加载音频源之外还负责注册关键监听器和应用设置：

| _loadAndPlay() 中执行 | 迷你栏是否执行 |
|---|---|
| `_processingSubscription` 注册（驱动自动下一曲和"播完当前"） | ❌ 未执行 |
| `_autoSaveTimer` 启动（每10秒保存进度） | ❌ 未执行 |
| `_playerStateSubscription` 注册（暂停时保存进度） | ❌ 未执行 |
| `defaultSpeedProvider` 读取并 `player.setSpeed()` | ❌ 未执行 |
| `handler.setMediaItemFromPath`（更新通知栏曲目） | ❌ 未执行 |
| `queue.startPositionMs` seek | ❌ 未执行 |
| 错误处理（auth错误重试引导） | ❌ 未执行 |

**影响范围**：所有不经过全屏播放页面的切歌操作都会导致后台功能体系崩塌。用户切歌后必须进入全屏播放页面才能恢复。

---

### BUG-13 迷你栏队列选择密码不可用时静默失败

**现象**：迷你栏点击队列按钮 → 选择歌曲 → 无任何反应，歌曲不切换。

**根因**：`mini_player_bar.dart:166` `_showQueueSheet` 中的密码读取：
```dart
storage.read(key: 'connection_password_${conn.id}').then((password) async {
    if (password == null || password.isEmpty) return;  // 静默返回
```
当密码不可用时（首次启动、安全存储异常等），代码静默返回，不给用户任何反馈。

**影响范围**：用户点击队列中的歌曲后无任何反应，不明白发生了什么。

---

### BUG-14 播放后返回浏览器，同一文件进度弹窗数据过时

**现象**：用户播放一首歌几分钟后返回浏览器，再次点击同一文件，弹出的"恢复播放进度"对话框显示的是播放前的旧位置，而非最新的播放位置。

**根因**：`browser_provider.dart:_progressRegistryProvider`（第346行）在目录加载时通过 `loadProgressForDirectoryProvider` 一次性从 DB 查询并缓存进度数据。播放期间 `_autoSaveTimer` 每10秒将最新位置写入 DB，但**内存缓存不刷新**。用户返回浏览器时（Browser 页面仍在导航栈中未经重建），`directoryContentsProvider` 未被 invalidate，进度缓存保持旧值。

**影响范围**：恢复播放的进度不准，用户可能从几分钟之前的位置重新开始听。

---

### BUG-15 切换 NAS 连接后迷你栏操作使用错误的连接信息

**现象**：在连接A下播放音乐 → 去设置切换到连接B → 返回浏览器 → 点击迷你栏"下一曲"，歌曲切换失败或播放错误内容。

**根因**：`_NextButton.onPressed`（mini_player_bar.dart 第215行）和 `_showQueueSheet` 动态读取 `activeConnectionProvider` 获取当前活跃连接的信息：
```dart
final conn = ref.read(activeConnectionProvider).valueOrNull;  // 现在是连接B
final password = await storage.read(key: 'connection_password_${conn.id}');  // 连接B的密码
```
但 `currentPlayQueueProvider` 中的文件路径来自连接A的文件系统。最终构建的 URL 是 `连接B的地址 + 连接A的文件路径`，服务器上大概率不存在。

**影响范围**：切换连接后迷你栏的切歌功能不可用。

---

### BUG-16 设置默认播放速度后不更新当前 AudioPlayer 实际速度

**现象**：当前正在播放 1.0x，去设置将默认速度改为 1.5x，返回播放页面后速度显示仍为 1.0x（实际播放速度也是 1.0x）。只在下一次新歌加载时才生效。

**根因**：A-4 修复中 `setDefaultSpeedProvider` 同步了 `currentSpeedProvider`，但为了避免测试环境崩溃（`AudioPlayer()` 构造函数在无平台绑定环境下 assert 失败），移除了 `player.setSpeed(speed)` 的调用。这导致设置变更后，`currentSpeedProvider` 虽然更新了，但 `AudioPlayer` 的实际速度未改变。

**影响范围**：用户修改默认速度后，当前正在播放的曲目速度不变。虽设计文档规定"默认值不影响当前播放"，但用户在设置页无法直接看到效果，体验不直观。

---

### BUG-17 迷你栏异步操作缺少 mounted 保护

**现象**：迷你栏队列按钮选择歌曲时，如果密码读取过程中用户关闭了 BottomSheet，继续操作可能访问已释放的资源。

**根因**：`mini_player_bar.dart:166` 使用 `.then()` 回调处理异步密码读取：
```dart
storage.read(key: 'connection_password_${conn.id}').then((password) async {
    // 此处没有 mounted/context 有效性检查
    final player = ref.read(audioPlayerProvider);
    await player.stop();
    ...
```
如果 BottomSheet 在密码读取期间被关闭，`ref` 可能来自已销毁的 Provider 作用域。虽 Riverpod 的 `ref` 通常可安全访问，但 `context`（如果后续需要）可能已经失效。

**影响范围**：极端时序下可能出现难以复现的异常。

---

### BUG-18 启动恢复的队列使用当前连接 URL + 旧会话文件路径

**现象**：上次用连接A听 `/music/song.mp3` → 删除连接A，添加连接B → 重启app → 迷你栏显示队列但播放失败。

**根因**：A-3 修复中 `restoreQueueFromPrefsProvider` 预加载音频源时读取当前活跃连接的信息去构建 URL，但队列中的文件路径来自旧会话的连接A。如果两个连接的 WebDAV 根路径不同，URL 将指向错误位置。

**影响范围**：跨连接会话的队列恢复不可用。

---

### BUG-19 迷你栏缺少定时倒计时显示

**现象**：用户在播放页面设置了5分钟定时 → 侧滑返回浏览器 → 迷你栏上看不到剩余时间。定时器在后台继续运行，到期后音乐突然停止。

**根因**：`MiniPlayerBar.build()` 未监听 `timerStateProvider` 或 `remainingTimeProvider`，迷你栏仅显示曲目名称、进度条和播放控件。

**影响范围**：用户在浏览器页面无法感知定时器状态，定时到期时音乐突然停止。

---

### BUG-20 用户手动调速后切歌，速度重置为默认值

**现象**：在播放页面将速度调为 1.5x → 侧滑返回 → 点击新歌 → 新歌以 1.0x（默认速度）播放。

**说明**：此行为符合设计文档 SET-01 的规定（"用户在播放器中调节速度后，该次播放使用调节后的速度，但不修改默认值"）。但在实际使用中，用户可能在连续听多首歌时期望速度设置保持。这是一个 UX 设计问题而非代码缺陷。

**影响范围**：用户可能困惑为什么"调过的速度又变回去了"。

---

## Batch D — P0 严重缺陷

### D-1  提取统一音频加载入口，消除迷你栏与播放页代码重复

**关联 Bug**：BUG-12
**根因**：迷你栏的 `_NextButton` 和 `_showQueueSheet` 各自独立实现音频加载逻辑，未执行 `_loadAndPlay()` 中的关键初始化步骤。

**修复方案**：

将 `_loadAndPlay()` 中的核心逻辑提取到 `player_provider.dart` 作为一个可复用的 Provider action，让迷你栏和播放页面共享同一个入口。

```dart
// player_provider.dart 新增

/// Unified entry point for loading and playing a track from the current queue.
///
/// Must be called whenever the playback source needs to change — whether from
/// the full player screen, the mini bar next button, or the queue sheet.
/// Registers all required listeners (auto-next, timer, auto-save, pause-save)
/// and applies the default speed.
///
/// Returns the [AudioPlayer] instance after the source is loaded and playing.
final loadAndPlayProvider = Provider<Future<AudioPlayer?> Function()>((ref) {
  return () async {
    final queue = ref.read(currentPlayQueueProvider);
    if (queue == null || queue.length == 0) return null;

    try {
      final activeConn = await ref.read(activeConnectionProvider.future);
      if (activeConn == null) return null;

      final storage = ref.read(secureStorageProvider);
      final password =
          await storage.read(key: 'connection_password_${activeConn.id}');
      if (password == null || password.isEmpty) return null;

      final source = AudioSourceBuilder.buildWithBasePath(
        baseUrl: activeConn.url,
        filePath: queue.current.path,
        username: activeConn.username,
        password: password,
      );

      final player = ref.read(audioPlayerProvider);

      // Register completion listener BEFORE stop (D-1: preserve A-2 fix)
      await ref.read(cancelProcessingSubscriptionProvider)();
      ref.read(setProcessingSubscriptionProvider)(player);

      await player.stop();
      await player.setAudioSource(source);

      if (queue.startPositionMs != null) {
        await player.seek(Duration(milliseconds: queue.startPositionMs!));
      }

      // Update notification
      final handler = ref.read(audioHandlerProvider);
      handler?.setMediaItemFromPath(
        queue.current.path,
        duration: player.duration,
      );

      // Apply default speed
      final defaultSpeed = ref.read(defaultSpeedProvider);
      if (defaultSpeed != 1.0) {
        await player.setSpeed(defaultSpeed);
        ref.read(currentSpeedProvider.notifier).state = defaultSpeed;
      }

      await player.play();

      // Start auto-save timer
      ref.read(startAutoSaveTimerProvider)();

      // Start pause-save listener
      ref.read(startPauseSaveListenerProvider)(player);

      return player;
    } on WebDavException {
      return null;
    } catch (_) {
      return null;
    }
  };
});
```

**需要完成的工作：**
1. 在 `player_provider.dart` 中新增 `loadAndPlayProvider` 统一入口
2. 提取 `_processingSubscription` 管理为独立 Provider
3. 提取 `_autoSaveTimer` 管理为独立 Provider
4. 提取 `_playerStateSubscription` 管理为独立 Provider
5. 修改 `PlayerScreen._loadAndPlay()` 改为调用统一入口 + UI 状态管理
6. 修改 `mini_player_bar.dart` 的 `_NextButton` 调用统一入口
7. 修改 `mini_player_bar.dart` 的 `_showQueueSheet` 调用统一入口
8. 全量测试

**涉及文件**：
- `lib/features/player/player_provider.dart`
- `lib/features/player/player_screen.dart`
- `lib/features/player/widgets/mini_player_bar.dart`

---

### D-2  迷你栏队列选择密码不可用时显示错误提示

**关联 Bug**：BUG-13
**根因**：`_showQueueSheet` 中密码读取失败时静默返回。

**修复方案**：

在密码为空时显示 SnackBar 错误提示，并将异步操作改为 async/await 模式：

```dart
// mini_player_bar.dart _showQueueSheet 中 onTap 改为：
onTap: isCurrent
    ? null
    : () async {
        Navigator.of(ctx).pop();
        final updatedQueue = queue.withIndex(i);
        ref.read(currentPlayQueueProvider.notifier).state = updatedQueue;

        final loaded = await ref.read(loadAndPlayProvider)();
        if (loaded == null && context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('无法加载音频，请检查连接配置')),
          );
        }
      },
```

注意：此修复依赖 D-1 的统一入口 `loadAndPlayProvider`。如果 D-1 未先完成，可先添加简单的密码检查 + SnackBar。

**需要完成的工作：**
1. 将 `_showQueueSheet` 中 `.then()` 改为 `async/await`
2. 密码/加载失败时显示 SnackBar
3. 测试：清除密码后通过队列按钮选歌 → 显示错误提示

**涉及文件**：
- `lib/features/player/widgets/mini_player_bar.dart`

---

## Batch E — P1 功能异常

### E-1  播放后返回浏览器时刷新进度缓存

**关联 Bug**：BUG-14
**根因**：`_progressRegistryProvider` 在目录加载时一次性缓存，播放后的 DB 更新不反映到缓存。

**修复方案**：

在 `PlayerScreen.dispose()` 中（侧滑返回时触发），触发进度缓存刷新：

```dart
// player_screen.dart dispose() 中添加：
@override
void dispose() {
  _saveProgress();
  // Invalidate the progress cache so that the Browser shows the latest
  // position if the user taps the same file again.
  final queue = ref.read(currentPlayQueueProvider);
  if (queue != null) {
    final dir = queue.current.path;
    final parentDir = dir.substring(0, dir.lastIndexOf('/'));
    if (parentDir.isNotEmpty) {
      ref.invalidate(loadProgressForDirectoryProvider(parentDir));
    }
  }
  // ... rest of dispose
}
```

更简单的方案：在 `_saveProgress()` 执行后，直接更新 `_progressRegistryProvider` 中对应文件的缓存值，无需整目录刷新。

```dart
// browser_provider.dart 新增 provider:
final refreshProgressCacheProvider = Provider<void Function(String filePath)>((ref) {
  return (String filePath) async {
    final registry = ref.read(_progressRegistryProvider);
    if (!registry.containsKey(filePath)) return; // not in current directory

    final dao = ref.read(progressDaoProvider);
    final conn = ref.read(activeConnectionProvider).valueOrNull;
    if (conn?.id == null) return;

    try {
      final progress = await dao.find(conn.id!, filePath);
      ref.read(_progressRegistryProvider.notifier).update((state) {
        return {...state, filePath: progress};
      });
    } catch (_) {}
  };
});
```

**需要完成的工作：**
1. 新增 `refreshProgressCacheProvider` 或 dispose 时 invalidate
2. 在 `PlayerScreen._saveProgress()` 后调用缓存刷新
3. 测试：播放 3 分钟 → 返回浏览器 → 点击同一文件 → 弹窗显示最新进度

**涉及文件**：
- `lib/features/browser/browser_provider.dart`
- `lib/features/player/player_screen.dart`

---

### E-2  连接切换后保护迷你栏操作，检测 URL 不匹配

**关联 Bug**：BUG-15
**根因**：迷你栏操作动态读取当前活跃连接，但队列中的文件路径来自旧连接。

**修复方案**：

在 `_NextButton` 和 `_showQueueSheet` 的切歌逻辑中，增加连接一致性检测。如果当前活跃连接与队列中文件的来源连接不同，阻止操作并提示用户。

更实际的方案：将连接信息与队列一起持久化（当前队列只存文件路径，不存连接信息）。或者在切歌时检测文件路径在新的连接的 WebDAV 上是否存在。

最小改动方案：检测连接是否发生了切换，如果切换了就引导用户去浏览器重新选择目录。

```dart
// mini_player_bar.dart 在切歌前检查：
final conn = ref.read(activeConnectionProvider).valueOrNull;
if (conn == null) return;

// 检查：队列中的文件是否可能属于当前连接
// （简单启发式：如果连接切换过，提示用户）
final connectionId = ref.read(lastUsedConnectionIdProvider);
if (connectionId != null && connectionId != conn.id) {
  if (context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('连接已切换，请重新浏览目录选择音乐')),
    );
  }
  return;
}
```

**需要完成的工作：**
1. 新增 `lastUsedConnectionIdProvider` 记录队列创建时的连接 ID
2. 在 `browser_screen.dart:onFileTap` 创建队列时记录连接 ID
3. 迷你栏切歌前检查连接 ID 一致性
4. 测试：连接A播放 → 切换连接B → 迷你栏下一曲 → 显示提示

**涉及文件**：
- `lib/features/browser/browser_provider.dart`
- `lib/features/browser/browser_screen.dart`
- `lib/features/player/widgets/mini_player_bar.dart`

---

### E-3  设置默认速度时同步更新 AudioPlayer 实际速度

**关联 Bug**：BUG-16
**根因**：A-4 修复中为避免测试崩溃移除了 `player.setSpeed()` 调用，导致 AudioPlayer 实际速度未更新。

**修复方案**：

在 `setDefaultSpeedProvider` 中恢复 `player.setSpeed()` 调用，使用安全的访问方式（通过 D-1 提取的 provider 间接访问，避免在测试环境中直接构造 `AudioPlayer()`）：

```dart
// player_provider.dart setDefaultSpeedProvider 修改：
final setDefaultSpeedProvider = Provider<void Function(double)>((ref) {
  return (double speed) {
    if (!isValidSpeed(speed)) return;
    final prefs = ref.read(sharedPreferencesProvider);
    prefs?.setDouble(_defaultSpeedKey, speed);
    ref.invalidate(defaultSpeedProvider);
    ref.read(currentSpeedProvider.notifier).state = speed;

    // 安全地同步 AudioPlayer 速度（通过 try-catch 处理测试环境）
    try {
      final player = ref.read(audioPlayerProvider);
      if (player.processingState != ProcessingState.idle) {
        player.setSpeed(speed);
      }
    } catch (_) {
      // 测试环境中 AudioPlayer 构造可能失败，忽略
    }
  };
});
```

**注意**：之前的 A-4 尝试过这个方案但因 `AudioPlayer()` 在测试中的平台绑定 assert 失败。可以用 `ref.exists(audioPlayerProvider)` 检查是否已创建，或使用 `ProviderSubscription` 模式来避免在未初始化时创建。

**需要完成的工作：**
1. 在 `setDefaultSpeedProvider` 中添加安全的 `player.setSpeed()` 调用
2. 确保测试环境不受影响（已创建 AudioPlayer 的测试应通过）
3. 测试：播放中改默认速度 → 当前播放速度立即变化

**涉及文件**：
- `lib/features/player/player_provider.dart`

---

## Batch F — P2 边界/体验缺陷

### F-1  迷你栏异步操作添加上下文有效性保护

**关联 Bug**：BUG-17
**根因**：`.then()` 回调中无 `mounted` 检查。

**修复方案**：

将 `_showQueueSheet` 中的 `.then()` 改为 `async/await`，并在异步操作前后检查上下文有效性。此修复与 D-2 重叠，D-2 已经将 `.then()` 改为 `await` 模式。

**需要完成的工作：**
1. 确保 `_showQueueSheet` 使用 `async/await` 而非 `.then()`（与 D-2 合并）
2. 异步操作后检查 `context.mounted` 再访问 context

**涉及文件**：
- `lib/features/player/widgets/mini_player_bar.dart`

---

### F-2  启动恢复队列时校验连接一致性

**关联 Bug**：BUG-18
**根因**：`restoreQueueFromPrefsProvider` 恢复队列时未校验文件路径是否适用于当前连接。

**修复方案**：

在恢复队列时，将队列创建时的连接 ID 一同持久化。恢复时检测：如果当前连接与旧连接不同，仅恢复队列的元数据用于显示，但不预加载音频源。

```dart
// browser_provider.dart PlayQueue.toMap() 增加 connectionId:
Map<String, dynamic> toMap() => {
    'connectionId': connectionId,
    'filePaths': files.map((f) => f.path).toList(),
    ...
};

// restoreQueueFromPrefsProvider 中：
final savedConnectionId = map['connectionId'] as int?;
final currentConn = ref.read(activeConnectionProvider).valueOrNull;
if (savedConnectionId != null && currentConn?.id != savedConnectionId) {
    // 连接已变更，不预加载音频源，仅恢复队列用于显示
    ref.read(currentPlayQueueProvider.notifier).state = PlayQueue(...);
    return; // 跳过预加载
}
```

**需要完成的工作：**
1. `PlayQueue.toMap()` 增加 `connectionId` 字段
2. `restoreQueueFromPrefsProvider` 增加连接 ID 一致性检查
3. 连接不匹配时跳过预加载但保留队列显示
4. 测试：连接A播放 → 切换连接B → 重启 → 迷你栏显示队列但提示需重新浏览

**涉及文件**：
- `lib/shared/models/play_queue.dart`
- `lib/features/browser/browser_provider.dart`

---

### F-3  迷你栏显示定时倒计时

**关联 Bug**：BUG-19
**根因**：`MiniPlayerBar` 未监听定时状态。

**修复方案**：

在 `MiniPlayerBar` 中添加对 `timerStateProvider` 的监听，当定时激活时在曲目标题旁边或进度条上方显示剩余时间。

```dart
// mini_player_bar.dart MiniPlayerBar.build 中添加：
final timerState = ref.watch(timerStateProvider);
final timerDisplay = timerState != null
    ? ref.watch(formattedRemainingProvider)
    : null;

// 在曲目标题行添加定时指示器：
if (timerDisplay != null || timerState?.mode == TimerMode.afterCurrent)
  Padding(
    padding: const EdgeInsets.only(right: 8),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.timer, size: 14, color: Theme.of(context).colorScheme.primary),
        const SizedBox(width: 2),
        Text(
          timerState?.mode == TimerMode.afterCurrent ? '播完停止' : (timerDisplay ?? ''),
          style: TextStyle(fontSize: 11, color: Theme.of(context).colorScheme.primary),
        ),
      ],
    ),
  ),
```

**需要完成的工作：**
1. 在 `MiniPlayerBar.build()` 中添加定时状态监听
2. 在迷你栏曲目标题行显示定时指示器
3. 测试：设置定时 → 返回浏览器 → 迷你栏显示倒计时 → 到期后消失

**涉及文件**：
- `lib/features/player/widgets/mini_player_bar.dart`

---

### F-4  播放界面调速后切歌保留当前速度（可选 UX 改进）

**关联 Bug**：BUG-20
**说明**：当前行为符合设计文档，但用户体验欠佳。作为可选改进，增加一个设置项「记住播放速度」，开启后用户在播放器中调整的速度会成为新的默认值。

**修复方案**（可选）：

```dart
// player_screen.dart _SpeedControl._showSpeedSelector 中：
onTap: () {
    player.setSpeed(speed);
    ref.read(currentSpeedProvider.notifier).state = speed;
    // 如果开启了"记住播放速度"，同步更新默认值
    final rememberSpeed = ref.read(rememberSpeedProvider);
    if (rememberSpeed) {
      ref.read(setDefaultSpeedProvider)(speed);
    }
    Navigator.of(ctx).pop();
},
```

**需要完成的工作：**
1. 新增 `rememberSpeedProvider` 设置项（SharedPreferences）
2. 在设置页面添加开关
3. 速度选择器中根据开关决定是否同步默认值
4. 测试：开启 → 调速度 → 切歌 → 新歌使用调整后的速度

**涉及文件**：
- `lib/features/player/player_provider.dart`
- `lib/features/player/player_screen.dart`
- `lib/features/settings/settings_screen.dart`
- `lib/features/settings/settings_provider.dart`

---

## 实施顺序建议

```
第 1 步: D-1 (提取统一音频加载入口)     ← 最关键的架构改进，D-2、E-3、F-1 都依赖它
第 2 步: D-1 完成后 → E-3 (速度同步)    ← D-1 提供了安全的 player 访问方式
第 3 步: D-2 (密码错误提示)              ← 依赖 D-1 的 loadAndPlayProvider
第 4 步: F-1 (mounted 保护)             ← D-2 已包含 async/await 改造，合并验证
第 5 步: E-1 (进度缓存刷新)             ← 独立
第 6 步: E-2 (连接切换保护)             ← 独立，与 F-2 相关
第 7 步: F-2 (队列恢复连接校验)         ← 独立，与 E-2 相关
第 8 步: F-3 (迷你栏定时显示)           ← 独立
第 9 步: F-4 (记住播放速度)             ← 可选，独立
```

说明：
- D-1 是最关键的修复，需要提取 `_loadAndPlay()` 为可复用 Provider，涉及文件最多
- D-2、E-3、F-1 都依赖 D-1 创建的统一入口
- E-1、E-2、F-2、F-3 为独立修复，可在 D-1 完成后并行
- F-4 为可选的 UX 改进
