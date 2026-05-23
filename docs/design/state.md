# Sona 状态机分析

> 本文档梳理 Sona 全部功能的状态机设计，包含状态枚举与转移图。
> 生成日期: 2026-05-23

---

## 目录

1. [路由状态机](#1-路由状态机)
2. [Connection — 连接管理](#2-connection--连接管理)
3. [Player — 播放器](#3-player--播放器)
4. [Timer — 定时器](#4-timer--定时器)
5. [Progress — 进度记忆](#5-progress--进度记忆)
6. [Browser — 文件浏览](#6-browser--文件浏览)
7. [Playlist — 播放单](#7-playlist--播放单)
8. [Home — 主页](#8-home--主页)
9. [跨功能状态交互](#9-跨功能状态交互)

---

## 1. 路由状态机

### 1.1 路由表

| 路径 | 页面 | 导航方式 |
|------|------|----------|
| `/onboarding` | 启动引导 | `context.go()` (初始路由) |
| `/connection` | 添加连接 | `context.push()` |
| `/connections` | 连接列表 | `context.push()` |
| `/connections/edit/:id` | 编辑连接 | `context.push()` |
| `/browser` | 主页 (Tab 导航) | `context.go()` |
| `/player` | 全屏播放器 | `context.push()` |
| `/settings` | 设置 | `context.push()` |
| `/about` | 关于 | `context.push()` |
| `/logs` (debug) | 日志查看 | `context.push()` |

关键设计：`initialRoute` 始终为 `/onboarding`，路由不做权限守卫，由 `_OnboardingPage` 自行判断跳转目标。

### 1.2 路由状态转移图

```
APP START
  │
  ▼
/onboarding ──(无连接)──▶ /connection ──(保存成功)──▶ /browser
  │                          ▲
  ├──(有连接+验证失败)─────────┘
  │
  └──(有连接+验证成功)──▶ /browser
                            │
                            ├── 点播放栏/歌曲 ──▶ /player
                            ├── 设置齿轮 ──▶ /connections ──▶ /connections/edit/:id
                            └── 设置齿轮 ──▶ /settings ──▶ /about
                                                         └── /logs (debug)
```

### 1.3 导航语义

- `context.go()` — 替换整个路由栈（`/onboarding` → `/browser` 意味着无法 back 回 onboarding）
- `context.push()` — 压入路由栈（`/browser` → `/player` 可以通过 back 返回 browser）
- `context.pop()` — 弹出当前页面

---

## 2. Connection — 连接管理

### 2.1 Onboarding 状态机

**文件**: `lib/main.dart:183-286`

```
State: ONB_LOADING
  │ (connectionListProvider 加载完成)
  ├── 无连接 ──▶ ONB_CTA
  │               │ 用户点击 "添加连接"
  │               ▼
  │             /connection (FORM_IDLE)
  │
  └── 有连接 ──▶ (startupValidationProvider 加载)
                  ├── 验证失败 ──▶ 跳转 /connection (FORM_IDLE + 橙色提示条)
                  └── 验证成功 ──▶ 跳转 /browser
```

**状态枚举**:

| 状态 | 含义 | UI |
|------|------|-----|
| `ONB_LOADING` | 读取数据库/验证连接中 | 白色全屏 + 旋转进度条 |
| `ONB_CTA` | 无连接，引导用户添加 | Scaffold + 图标 + 说明文字 + "添加连接"按钮 |
| `ONB_REDIRECT_CONNECTION` | 有连接但验证失败，跳转修复 | 瞬态 (spinner → go('/connection')) |
| `ONB_REDIRECT_BROWSER` | 连接正常，进入主页 | 瞬态 (spinner → go('/browser')) |

### 2.2 添加连接 (Add Form) 状态机

**文件**: `lib/features/connection/connection_screen.dart:19-213`

```
FORM_IDLE
  │
  ├── 用户填表，点 "测试连接" ──▶ 表单字段非法 ──▶ FORM_FIELDS_INVALID (字段级错误提示)
  │                               表单字段合法 ──▶ VALIDATING (按钮显示 "连接中...")
  │                                   │
  │                                   ├── PROPFIND 207 ──▶ VALIDATED_SUCCESS (绿色提示条, 保存按钮启用)
  │                                   └── 401/403/404/timeout/网络错误 ──▶ VALIDATED_ERROR (红色错误提示条)
  │
  └── 点 "保存" (必须 VALIDATED_SUCCESS)
        │
        ▼
      SAVING (按钮显示 "保存中...")
        │
        ├── 写入 DB + SecureStorage 成功 ──▶ SAVED_OK ──▶ go('/browser')
        └── 写入失败 ──▶ SAVED_FAILED (SnackBar 错误提示, 留在表单)
```

**保存流程详情** (`lib/features/connection/connection_provider.dart:177-221`):
1. INSERT 连接行 (密码列存临时引用 key)
2. 写入密码到 `flutter_secure_storage` (key: `connection_password_{id}`)
3. 若 SecureStorage 失败 → 回滚 DB 行 (DELETE) → 抛出异常
4. 更新行引用永久 key
5. 调用 `dao.setActive(id)` 设为活跃连接

### 2.3 连接列表状态机

**文件**: `lib/features/connection/connection_list_screen.dart:16-172`

```
LIST_LOADING ──▶ LIST_LOADED
                   │
                   ├── 点击非活跃连接 ──▶ SWITCHING
                   │                         ├── 成功 → SnackBar "已切换到 [name]"
                   │                         └── 失败 → SnackBar 错误
                   │
                   ├── 点击编辑 ──▶ push /connections/edit/:id
                   │
                   └── 点击删除
                         ├── 仅剩 1 个连接 → 警告弹窗 (不可删除)
                         └── 多于 1 个 → 确认弹窗
                                           ├── DELETE_OK → 列表更新
                                           └── DELETE_FAILED → SnackBar 错误
```

**DAO 层保证的不变性**:
- `setActive()` 用事务保证唯一活跃连接 (`is_active = 1`)
- `delete()` 抛出 `LastConnectionException` 阻止删除最后一个连接
- 删除活跃连接时自动激活另一个

### 2.4 编辑连接状态机

**文件**: `lib/features/connection/connection_edit_screen.dart:22-299`

```
EDIT_FORM_LOADED (预填字段, 密码留空可选)
  │
  ├── 仅修改名称 ──▶ EDIT_NAME_ONLY_SAVE (无需重验证)
  │
  ├── 修改凭证字段 (url/username/password/basePath)
  │     └──▶ EDIT_VALIDATION_RESET (_onFieldChanged 重置验证器)
  │           │
  │           ├── 点 "测试连接" ──▶ VALIDATING → 成功/失败
  │           └── 点 "保存" 但未重验证 ──▶ EDIT_SAVE_BLOCKED (SnackBar "请先测试连接")
  │
  └── 点 "保存" (验证通过或仅名称修改)
        ├── 成功 ──▶ EDIT_SAVE_OK → pop() 回列表
        └── 失败 ──▶ SnackBar 错误
```

`_canSave()` 逻辑: 当 `!_needsValidation()` (仅名称修改) 或 `validationSuccess` 时返回 true。

---

## 3. Player — 播放器

### 3.1 播放加载状态机 (PlayerLoadStatus)

**文件**: `lib/features/player/player_provider.dart:52-64`

```
idle ──▶ loading ──▶ ready
                 └──▶ error (可选子标记: isAuthError)
```

这是 `_PlayerScreenState` 的 UI-local 状态，不是全局 provider。

### 3.2 曲目加载状态机 (TrackLoadStatus)

**文件**: `lib/features/player/player_provider.dart:116`

```
每个 SerializedRequestGate 请求的返回结果:
  loaded     — 加载成功，且是最新请求
  failed     — 加载失败 (无队列/无连接/认证失败/网络错误/play() 超时)
  superseded — 加载完成但已被更新的请求取代，结果丢弃
```

### 3.3 播放模式 (PlayMode)

**文件**: `lib/shared/models/play_queue.dart:20-32`

| 模式 | `nextIndex()` | `previousIndex()` | 队列结束时 |
|------|---------------|-------------------|-----------|
| `sequential` | `current + 1` | `current - 1` | `nextIndex` 返回 `null`，调用方 stop+pause |
| `repeatOne` | 返回 `current` | 返回 `current` | 永不返回 null |
| `repeatAll` | `(current + 1) % length` | `(current - 1 + length) % length` | 循环，永不返回 null |
| `shuffle` | 随机选非当前索引 | 随机选非当前索引 | `length <= 1` 时返回 null |

模式切换 (`sequential → repeatOne → repeatAll → shuffle → sequential`) 仅影响下一次导航，不改变当前播放。

### 3.4 播放生命周期状态机

```
                 用户点击文件 (Browser/Playlist)
                           │
                           ▼
                   构建 PlayQueue，设置 currentPlayQueueProvider
                           │
                           ▼
                   navigate to /player
                           │
                           ▼
               ┌─ PlayerScreen.initState()
               │     ├── sourceMatchesQueue()? ──▶ reconnectPlaybackListeners (复用已加载的 source)
               │     └── 不匹配 ──▶ _loadAndPlay()
               │                      │
               │                      ▼
               │              SerializedRequestGate.schedule()
               │                1. 验证队列非空
               │                2. 验证活跃连接
               │                3. 读取 SecureStorage 密码
               │                4. 构建 AudioSource
               │                5. 注册 processingStateStream 监听器 (自动切歌)
               │                6. player.stop()
               │                7. player.setAudioSource()
               │                8. player.seek(startPositionMs) [如有]
               │                9. handler.setMediaItem() [更新通知栏]
               │               10. 应用默认速度
               │               11. player.play() [unawaited, 12s poll timeout]
               │               12. 启动自动保存定时器 (10s 间隔)
               │               13. 启动暂停保存监听器
               │                      │
               ▼                      ▼
          ┌──────────────────────────────────────┐
          │            PLAYING                    │
          │  (AudioPlayer 正在播放)               │
          └──────────────────────────────────────┘
               │           │           │
     用户点暂停 │   曲目播完 │   用户点 skip
               ▼           ▼           ▼
          PAUSED     处理状态机      skipToNext/Previous
               │        │              │
               │        ├── afterCurrent timer 触发? ──▶ pause
               │        ├── nextIndex == null? ──▶ seek(0), pause  ← 队列到头
               │        └── nextIndex 有效 ──▶ 保存进度 → 更新 index → loadAndPlay
               │
     用户点播放 │
               ▼
          PLAYING
```

### 3.5 队列移除状态机

**文件**: `lib/features/player/player_provider.dart:805-828`

```
用户从队列中移除曲目
  │
  ▼
removeTrackFromQueueProvider(index)
  │
  ├── 移除后队列为空 (length == 0)
  │     ├── player.stop()
  │     ├── currentPlayQueueProvider = null
  │     ├── handler.mediaItem = null  (清除通知栏)
  │     ├── 取消自动保存 + 暂停保存监听器
  │     └── MiniPlayerBar 隐藏 (SizedBox.shrink)
  │
  ├── 移除的是当前播放曲目
  │     └── 保存进度 → loadAndPlayProvider() (下一条顶上)
  │
  └── 移除的不是当前曲目
        └── 仅更新队列状态 (currentIndex 可能调整)
```

### 3.6 SerializedRequestGate — 请求序列化门

**文件**: `lib/features/player/player_provider.dart:145-200`

防止共享 `AudioPlayer` 上出现重叠的 `stop → setAudioSource → play` 链:

```
schedule(request):
  1. 递增 requestId
  2. 若有正在执行的请求，排队新请求，取消 (supersede) 旧的排队请求
  3. 执行完成后检查 isLatest(requestId):
     - 是最新请求 → 返回结果
     - 被取代 → 返回 onSuperseded()
  4. 处理下一个排队请求
```

所有加载路径 (loadAndPlay, skipToNext, skipToPrevious, selectQueueIndex) 都通过此门。

### 3.7 MiniPlayerBar 同步机制

**文件**: `lib/features/player/widgets/mini_player_bar.dart`

| 数据 | 来源 | 机制 |
|------|------|------|
| 可见性 | `currentPlayQueueProvider` | queue == null → `SizedBox.shrink()` |
| 曲目名 | `currentPlayQueueProvider.current.name` | 直接读取 |
| 播放/暂停 | `AudioPlayer.playerStateStream` | `StreamBuilder` 广播 |
| 进度条 | `AudioPlayer.positionStream` / `durationStream` | `StreamBuilder` 广播 |
| 定时器 | `timerStateProvider` / `formattedRemainingProvider` | 直接读取 |

同步原理：全屏播放器和 mini bar 读取**同一个** `AudioPlayer` 单例，`just_audio` 的 stream 广播到所有监听者。

### 3.8 ProcessingState 监听器生命周期

**文件**: `lib/features/player/player_provider.dart:618-649`

- PlayerScreen 初始化时注册 `processingStateStream.listen()`
- PlayerScreen dispose 时**不**取消此监听器 — 这是故意设计的，因为 auto-advance 必须从 mini bar 也能工作
- 当 PlayerScreen 重新打开且 source 匹配时，`reconnectPlaybackListenersProvider` 重新连接被取消的监听器（但 processing 监听器不需要）

---

## 4. Timer — 定时器

### 4.1 状态枚举

**文件**: `lib/core/services/timer_service.dart`

`TimerService._state: TimerState?`

| 状态 | `_state` 值 | 含义 |
|------|-------------|------|
| **idle** | `null` | 无定时器 |
| **running (duration)** | `TimerState(mode: duration, endTime: <DateTime>)` | 固定时长倒计时中 |
| **running (afterCurrent)** | `TimerState(mode: afterCurrent, endTime: null)` | 当前曲目播完即停 |
| **paused** | `TimerState(mode: paused, remainingMs: <int>)` | 已暂停，保留剩余时间 |

### 4.2 状态转移图

```
                       startDuration(min)
      ┌────────────────────────────────────────┐
      │                                         │
      ▼                                         │
   [idle] ──startDuration(min)──▶ [duration] ───┘
      │                              │    │
      │                              │    ├── checkExpired() ──▶ [idle] (返回 true)
      │                              │    ├── cancel() ──▶ [idle] (返回 true)
      │                              │    ├── pause() ──▶ [paused]
      │                              │    └── startAfterCurrent() ──▶ [afterCurrent]
      │                              │
      │   startAfterCurrent()        │
      ├──────────────────────────────▶ [afterCurrent]
      │                                   │    │
      │                                   │    ├── onTrackCompleted() ──▶ [idle] (返回 true)
      │                                   │    ├── cancel() ──▶ [idle] (返回 true)
      │                                   │    ├── pause() ──▶ [paused]
      │                                   │    └── startDuration(min) ──▶ [duration]
      │
      │   resume()                  resume()
      ├─────────────────────────────────────▶ [paused]
      │                                        │    │
      │                                        │    ├── resume() ──▶ [duration] (恢复倒计时)
      │                                        │    └── cancel() ──▶ [idle]
      │
      └── cancel() ──▶ [idle] (no-op, 返回 false)
```

关键设计：**替换语义** — 新定时器总是覆盖旧定时器；新增 **paused 状态**支持暂停/恢复。

### 4.3 时长定时器到期检测链路

```
PlayerScreen Timer.periodic (每1秒)
  → ref.read(checkTimerExpiryProvider)()
    → timerService.checkExpired()
      → 若 now >= endTime: 返回 true, 清空 _state
  → 若到期: player.pause()
```

App 从后台恢复时立即检查一次到期状态，避免后台期间到期延迟。

### 4.4 "播完当前" 到期检测链路

```
processingStateStream 发出 completed
  → startProcessingListenerProvider 回调
    → onTrackCompletedProvider()
      → timerService.onTrackCompleted()
        → 若 mode == afterCurrent: 返回 true, 清空 _state
  → 若到期: player.pause()
```

### 4.5 定时器模式

| UI 选项 | `TimerMode` | 参数 | 到期检测 |
|---------|-------------|------|---------|
| 5 分钟 | `duration` | endTime = now + 5min | `checkExpired()` |
| 10 分钟 | `duration` | endTime = now + 10min | `checkExpired()` |
| 15 分钟 | `duration` | endTime = now + 15min | `checkExpired()` |
| 自定义分钟 | `duration` | endTime = now + N min | `checkExpired()` |
| 播完当前 | `afterCurrent` | endTime = null | `onTrackCompleted()` |

---

## 5. Progress — 进度记忆

### 5.1 数据状态机

**文件**: `lib/core/database/dao/progress_dao.dart`

```
       用户开始播放文件 (position 从 0 开始)
                │
                ▼
          [no progress]
                │ positionMs 达到 5000
                ▼
          [has progress]  ←── upsert() 写入 DB
                │              (按 (connection_id, file_path) 复合键: INSERT OR REPLACE)
                │
                ├── positionMs > durationMs - 10000 ──▶ [auto-cleared] (DELETE)
                │    (durationMs <= 10000 的文件不会被自动清理)
                │
                └── 用户播完/切换到新文件 ──▶ 新文件从头开始 → [no progress]
                                             旧进度独立保留
```

### 5.2 Resume Dialog 状态机

**文件**: `lib/features/progress/progress_dialog.dart:26`

```
[no progress / dismissed] (state = null)
  │ 有进度且触发恢复
  ▼
[has progress, countdown N > 0]
  │
  ├── 用户点 "继续播放" ──▶ [resumed] (返回 true)
  ├── 用户点 "从头开始" ──▶ [dismissed] (返回 false)
  └── 倒计时归零 ──▶ [resumed] (返回 true, 自动继续)
```

### 5.3 5 个保存触发点

**文件**: `lib/features/player/player_screen.dart:291-293`

| # | 触发点 | 机制 | 位置 |
|---|--------|------|------|
| 1 | 10 秒定时 | `Timer.periodic(10s)` → `saveProgressProvider` | `player_provider.dart:672-680` |
| 2 | 暂停 | `playerStateStream` 监听 `playing: true→false` | `player_provider.dart:699-714` |
| 3 | 切歌 | `skipToNext`/`skipToPrevious`/`selectQueueIndex` 前保存 | `player_provider.dart:641,753,775,796` |
| 4 | App 后台 | `didChangeAppLifecycleState(paused)` | `player_screen.dart:95-102` |
| 5 | 页面 dispose | `dispose()` → `_saveProgressWithContainer` | `player_screen.dart:111-113` |

### 5.4 智能过滤规则

| 规则 | 阈值 | 行为 |
|------|------|------|
| 跳过短位置 | positionMs < 5000 | 不保存 (返回 false) |
| 清理已完成 | positionMs > durationMs - 10000 | 删除记录 (返回 null) |
| 保护短文件 | durationMs <= 10000 | 永不自动清理 |

---

## 6. Browser — 文件浏览

### 6.1 目录内容状态机

**文件**: `lib/features/browser/browser_screen.dart`

```
        请求目录内容 (directoryContentsProvider)
                      │
                      ▼
                 [loading] ──▶ 骨架屏 (8 行占位)
                      │
          ┌───────────┼───────────┐
          ▼           ▼           ▼
     [loaded]      [empty]     [error]
     (文件列表)    ("目录为空")  (错误信息 + 重试按钮)
          │
          用户下拉刷新 → 清除缓存 → 重新请求 → [loading]
```

### 6.2 目录导航状态机

**文件**: `lib/features/browser/browser_provider.dart:255-290`

`NavigationStackNotifier` 管理 `List<String>` 路径栈（始终以 `/` 开头）。

```
     打开 Browser
        │
        ▼
  stack = ['/']
        │
        ├── 点击目录 → push(dirPath) → stack = ['/', 'dir']
        │     │
        │     ├── 继续深入 → push(subDir) → stack = ['/', 'dir', 'dir/sub']
        │     └── 返回 (系统 back / 面包屑上级) → pop() → stack = ['/']
        │
        └── 点击面包屑 "dir" → popTo('dir') → stack = ['/', 'dir']
            点击面包屑 "/" → popTo('/') → stack = ['/']
```

**PopScope 逻辑** (`browser_screen.dart:48-53`):
- 在根目录 (`stack.length <= 1`): 允许系统 back 退出 Browser
- 在子目录: 拦截 back，改为 `pop()` 回上级目录

### 6.3 排序

| 选项 | SortOption 枚举 |
|------|-----------------|
| 名称 A-Z (默认) | `nameAsc` |
| 名称 Z-A | `nameDesc` |
| 最近修改优先 | `modifiedDesc` |

排序规则：无论何种排序，目录始终排在文件前面。

排序选项持久化到 `SharedPreferences`。

### 6.4 缓存策略

- **结构**: `Map<String, List<NasFile>>`，key 为 `"connectionId:path"`
- **容量**: 最多 50 条目，超出时移除最旧条目
- **TTL**: 5 分钟，过期自动失效
- **失效**: 下拉刷新清除匹配 key → `directoryContentsProvider` 重取
- **连接切换**: key 含 `connectionId`，切换连接不泄漏旧数据

### 6.5 构建播放队列

`onFileTap` (`browser_screen.dart:91-118`):
1. 检查 `playProgressProvider` → 有进度则弹出 resume dialog
2. 读取当前目录内容
3. 过滤音频文件 (`!f.isDirectory`)
4. 构建 `PlayQueue(files: audioFiles, currentIndex: tappedIndex, startPositionMs: resumePosition)`
5. 设置 `currentPlayQueueProvider`
6. 保存 `lastQueueConnectionIdProvider`
7. `goRouter.push('/player')`

---

## 7. Playlist — 播放单

### 7.1 播放单列表状态机

**文件**: `lib/features/playlist/playlist_list_screen.dart`

```
[loading] ── 骨架屏 (6 行)
     │
     ├──▶ [error] ── 错误信息 + 重试按钮
     ├──▶ [empty] ── 图标 + "暂无播放单，点击 + 创建"
     └──▶ [data]  ── 播放单列表 (Slidable 左滑删除)
            │
            ├── 点击播放单 ──▶ push /playlist/:id
            ├── FAB 创建   ──▶ 弹窗输入名称 → 创建 → 刷新列表
            └── 左滑删除   ──▶ 确认弹窗 → 删除 → 刷新列表
```

### 7.2 播放单详情状态机

**文件**: `lib/features/playlist/playlist_detail_screen.dart`

```
[loading] ── CircularProgressIndicator
     │
     ├──▶ [error]  ── 错误图标 + 消息 + 重试
     ├──▶ [empty]  ── "播放单是空的，点击 + 添加曲目"
     └──▶ [data]   ── 曲目列表 (ReorderableListView 拖拽排序)
            │
            ├── 点击曲目 ──▶ 检查进度 → resume dialog → 构建 PlayQueue → push('/player')
            ├── 长按曲目 ──▶ 进入 selection 模式
            │     │
            │     ├── 全选/反选
            │     └── 删除选中 ──▶ 确认弹窗 → 删除 → 刷新
            │
            ├── AppBar 编辑 ──▶ showRenameDialog → 重命名
            │
            └── FAB (+) ──▶ showAddTracksBrowser (独立浏览器底部弹窗)
                              → 用户选文件 → 确认 → addTracks()
```

### 7.3 CRUD 状态转移

```
创建: FAB → 弹窗输入名称 → createPlaylistProvider → dao.insertPlaylist() → invalidate(playlistListProvider)
删除: 左滑/确认 → deletePlaylistProvider → dao.deletePlaylist(CASCADE) → invalidate(playlistListProvider)
读取: playlistListProvider → dao.findAllPlaylists() → 排序 → AsyncValue
重命名: AppBar 编辑 → 弹窗 → updatePlaylistProvider → dao.updatePlaylist() → invalidate
添加曲目: 底部弹窗选文件 → addTracksToPlaylistProvider → dao.addTracks(去重) → invalidate(tracksProvider + listProvider)
删除曲目: selection → 确认 → removeTracksFromPlaylistProvider → dao.removeTracks() → invalidate(tracksProvider + listProvider)
排序曲目: 拖拽 → reorderPlaylistTrackProvider → dao.reorderTrack() → invalidate(tracksProvider)
导出: exportPlaylistProvider → dao.getTracks() → JSON encode → 分享/保存
导入: importPlaylistProvider → JSON decode → dao.insertPlaylist() + dao.addTracks() → invalidate
```

去重策略：`dao.addTracks()` 通过 `trackExists()` 检查 `file_path`，同名路径静默跳过。

---

## 8. Home — 主页

### 8.1 Tab 导航状态机

**文件**: `lib/features/home/home_screen.dart`

```
AppBar (动态排序菜单 + 设置齿轮)
  │
  Tab 0: "播放单"  │  Tab 1: "文件浏览器"
  PlaylistListScreen│  BrowserScreen
       │            │       │
       └────────────┴───────┘
                    │
            MiniPlayerBar (始终在 Column 底部，内容动态显示/隐藏)
```

| 状态 | 含义 |
|------|------|
| Tab 0 激活 | 显示播放单列表，AppBar 菜单为播放单排序 |
| Tab 1 激活 | 显示文件浏览器，AppBar 菜单为文件排序 |

Tab index 持久化到 `SharedPreferences`，App 重启后恢复上次选择的 Tab。

### 8.2 PopScope 行为

`home_screen.dart:40-46`: `PopScope(canPop: false)` + `onPopInvokedWithResult` 调用 `moveTaskToBack()` — 拦截 Android back 键，将 App 移到后台而非退出。

### 8.3 MiniPlayerBar 可见性

```
currentPlayQueueProvider == null || queue.length == 0
  ├── true  → SizedBox.shrink() (不可见)
  └── false → 显示迷你栏 (曲目名 + 进度条 + 定时器 + 播放/暂停)
                  │
                  ├── 点击主体 → push('/player')
                  └── 点击队列图标 → showQueueSheet
```

---

## 9. 跨功能状态交互

### 9.1 全局状态桥接

```
                    ┌──────────────────┐
                    │ currentPlayQueue │ ←── 全局单例 StateProvider
                    │ Provider         │
                    └──────┬───────────┘
                           │
          ┌────────────────┼────────────────┐
          │                │                │
    Browser.onFileTap  Playlist.onTrackTap  Startup.restore
          │                │                │
          └────────────────┼────────────────┘
                           │
                           ▼
                    PlayerScreen
                    (读取 queue → 构建 AudioSource → 播放)
                           │
                    ┌──────┴───────┐
                    │              │
              MiniPlayerBar   通知栏控件
              (读取同 queue)  (读取同 handler)
```

### 9.2 Timer → Player 触发链路

```
PlayerScreen Timer.periodic (每1秒)
  → checkTimerExpiryProvider
    → timerService.checkExpired()
      → 到期 → player.pause()

processingStateStream (completed)
  → startProcessingListenerProvider
    → timerService.onTrackCompleted()
      → afterCurrent 模式 → player.pause()
```

### 9.3 Progress → Player 恢复链路

```
App 启动
  → restoreStartupProgressProvider
    → dao.findLatest()
      → 有进度 → 构建 PlayQueue(startPositionMs: progress.positionMs)
        → currentPlayQueueProvider = queue
          → PlayerScreen 读取 .startPositionMs → player.seek()
```

### 9.4 Connection 切换影响面

```
setActiveConnection(newId)
  → invalidate: activeConnectionProvider, connectionListProvider
  → clearDirectoryCache (cache key 含 connectionId)
  → 导航栈回到 /browser

如果 queue.lastQueueConnectionId != newActiveConnection.id:
  → clearQueueOnConnectionSwitchProvider 自动清空 currentPlayQueueProvider
  → MiniPlayerBar 隐藏
```
