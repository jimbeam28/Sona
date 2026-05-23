# Sona — 整体架构文档

## 1. 项目概述

Sona 是一款面向 Android 平台的 NAS 音频播放器，通过 WebDAV 协议访问远程存储上的音乐和有声书文件。支持流式播放、后台播放、播放进度记忆、播放速度调节、定时停止等功能。

---

## 2. 技术选型

| 技术 | 选型 | 理由 |
|------|------|------|
| 开发框架 | Flutter (Dart) | 原生 Android 性能，音频生态成熟 |
| NAS 接入 | WebDAV (HTTP PROPFIND) | 飞牛OS 原生支持，支持流式播放 |
| 状态管理 | Riverpod | 类型安全、可测试、无代码生成 |
| 本地存储 | SQLite (sqflite) | 存储连接配置、播放进度 |
| 路由 | go_router | 声明式路由 |
| 音频引擎 | just_audio | Flutter 生态最成熟的音频播放库 |
| 后台播放 | audio_service | 系统媒体控件、锁屏控件、通知栏 |
| 安全存储 | flutter_secure_storage | 密码等敏感信息加密存储 |
| 偏好存储 | shared_preferences | 主题、播放速度、排序等用户偏好 |

---

## 3. 整体架构

```
┌──────────────────────────────────────────────────────────────────┐
│                         UI Layer                                  │
│  ┌──────────┐ ┌──────────┐ ┌──────────┐ ┌──────────┐           │
│  │Connection│ │  Home    │ │  Player  │ │ Settings │           │
│  │  Screen  │ │ TabNav   │ │  Screen  │ │  Screen  │           │
│  └──────────┘ │ Browser  │ └──────────┘ └──────────┘           │
│               │ Playlist │                                       │
│               └──────────┘                                       │
│       │            │            │            │                   │
├───────┼────────────┼────────────┼────────────┼───────────────────┤
│      State Layer (Riverpod Providers)                            │
│  ┌──────────┐ ┌──────────┐ ┌──────────┐ ┌──────────┐           │
│  │ Conn Pvdr│ │BrowserPvdr│ │PlayerPvdr│ │SettingsPv│           │
│  │ Timer Pvdr│ │ProgressPv│ │PlaylistPv│ │          │           │
│  └──────────┘ └──────────┘ └──────────┘ └──────────┘           │
│       │            │            │            │                   │
├───────┼────────────┼────────────┼────────────┼───────────────────┤
│                   Service Layer                                  │
│  ┌──────────────┐ ┌──────────────┐ ┌─────────────────┐          │
│  │WebDavClient  │ │NasAudioHandler│ │  TimerService   │          │
│  │  Interface   │ │(audio_service)│ │  (pure logic)   │          │
│  └──────────────┘ └──────────────┘ └─────────────────┘          │
│       │                                              │           │
├───────┼──────────────────────────────────────────────┤           │
│                   Data Layer                                     │
│  ┌──────────────┐ ┌──────────────┐                               │
│  │  WebDAV API  │ │  SQLite DB   │                               │
│  │  (NAS 远端)  │ │  (本地存储)  │                               │
│  └──────────────┘ └──────────────┘                               │
└──────────────────────────────────────────────────────────────────┘
```

**数据流：** 用户操作 → Widget → Riverpod Provider → Service → Data Source → Provider 状态更新 → UI 重建

---

## 4. 模块功能

### 4.1 Connection（连接管理）

负责 NAS WebDAV 连接配置的完整生命周期管理。

**数据模型：** `ConnectionConfig` — 包含 id、name、url、username、basePath、isActive、时间戳。密码存储在 flutter_secure_storage 中，数据库中仅保存引用 key。

**核心功能：**
- **添加连接** — 填写服务器地址、用户名、密码、基础路径 → 测试连接（PROPFIND 验证）→ 保存到 SQLite + 安全存储
- **编辑连接** — 修改已有连接配置，仅变更凭证相关字段时需重新验证；仅修改显示名称可直接保存
- **删除连接** — 级联删除播放进度记录和安全存储中的密码；至少保留一个连接；若删除的是活跃连接则自动激活另一个
- **连接列表** — 显示所有已保存连接，支持左滑编辑/删除，点击切换活跃连接
- **启动自动验证** — 应用启动时自动对上次活跃连接发起 PROPFIND 验证，失败则引导用户修复配置
- **连接切换** — 切换活跃连接时自动清除浏览器缓存

**Provider 清单：**
- `activeConnectionProvider` — 当前活跃连接
- `connectionListProvider` — 所有连接列表
- `connectionValidatorProvider` — 测试连接状态机（idle → loading → success/error）
- `startupValidationProvider` — 启动时自动验证
- `switchActiveConnectionProvider` — 切换活跃连接
- `connectionSaverProvider` / `connectionUpdaterProvider` / `deleteConnectionProvider` — CRUD 操作

### 4.2 Browser（文件浏览）

负责 NAS 文件系统的目录浏览、导航和文件选择。

**数据模型：** `NasFile` — 包含 name、path、isDirectory、size、modifiedAt、audioType（music/audiobook）。支持 mp3、flac、aac、m4a、m4b、ogg、opus、wav 格式。

**核心功能：**
- **目录浏览** — 通过 PROPFIND Depth:1 列出目录内容，过滤自引用条目和非音频文件，目录始终排在最前
- **面包屑导航** — 层级路径导航，支持点击任意层级跳转；系统返回键逐级回退
- **排序** — 支持名称升序、名称降序、修改时间降序三种排序，偏好持久化到 SharedPreferences
- **目录缓存** — 已加载的目录内容缓存在内存中，下拉刷新可清除指定路径缓存；缓存上限 50 条防止内存溢出
- **点击播放** — 点击音频文件时从当前目录构建完整播放队列，自动跳转到播放页面
- **长按清除进度** — 对有播放进度的文件长按可清除已保存的进度记录

**Provider 清单：**
- `directoryContentsProvider(path)` — 指定路径的目录内容（网络请求 + 缓存）
- `navigationStackProvider` — 导航历史栈（支持 push/pop/popTo）
- `sortOptionProvider` — 当前排序选项（持久化）
- `currentPlayQueueProvider` — 当前播放队列
- `playProgressProvider(filePath)` — 单文件播放进度查询
- `loadProgressForDirectoryProvider(path)` — 批量加载目录内文件的进度信息

### 4.3 Player（音频播放）

核心播放模块，负责音频流式播放、控制、后台播放和队列管理。

**数据模型：** `PlayQueue` — 包含 files（音频文件列表）、currentIndex、startPositionMs、playMode。`PlayMode` 枚举：sequential / repeatOne / repeatAll / shuffle。

**核心功能：**
- **流式播放** — 通过 just_audio 的 `AudioSource.uri` 播放 WebDAV 音频流，URL 路径段正确编码（支持中文、空格等特殊字符），Basic Auth 凭证通过 HTTP Header 传递
- **播放控制** — 播放/暂停、进度条拖拽、快进/快退（可配置步长：10/15/30/60秒）、上一首/下一首
- **播放模式** — 顺序播放、单曲循环、列表循环、随机播放，循环切换
- **播放速度** — 0.5x / 0.75x / 1.0x / 1.25x / 1.5x / 2.0x 六档调速；支持"记住播放速度"开关
- **后台播放** — audio_service 集成，锁屏/通知栏显示媒体控件（上一首、播放/暂停、下一首），App 进入后台音频不中断
- **迷你播放器** — 浏览器页面底部的常驻迷你播放栏，显示当前播放文件名，支持播放/暂停和快速进入全屏播放页
- **队列管理** — 底部弹出队列列表，可查看完整播放列表并点击跳转到任意曲目
- **自动切歌** — 曲目播放完毕后根据播放模式自动加载下一首（afterCurrent 定时器优先生效）
- **进度自动保存** — 每 10 秒自动保存、暂停时保存、切歌时保存、App 进入后台时保存、页面销毁时保存
- **启动进度恢复** — 启动时从 SharedPreferences 恢复上次队列，并从 SQLite 恢复最近播放位置
- **加载序列化** — 通过 `SerializedRequestGate` 确保对 AudioPlayer 的并发 load 请求串行执行，最新请求优先

**Provider 清单：**
- `audioPlayerProvider` — 全局 AudioPlayer 单例
- `audioHandlerProvider` — NasAudioHandler 实例（后台播放处理器）
- `playModeProvider` — 当前播放模式
- `seekStepProvider` — 快进/快退步长
- `defaultSpeedProvider` / `currentSpeedProvider` — 默认速度 / 当前速度
- `loadAndPlayProvider` — 统一播放入口（加载音频源 + 注册所有监听器）
- `skipToNextProvider` / `skipToPreviousProvider` / `selectQueueIndexProvider` — 队列导航
- `backgroundPlaybackProvider` — 后台播放状态机

### 4.4 Timer（定时停止）

纯逻辑定时器状态机，无 Flutter 依赖。

**数据模型：** `TimerState` — 包含 mode（duration / afterCurrent）、endTime、startedAt。

**核心功能：**
- **固定时长定时** — 5 / 10 / 15 分钟预设，以及自定义时长（记住上次自定义值）
- **播完当前停止** — 当前曲目播放完毕后自动暂停
- **倒计时显示** — 播放器页面实时显示 MM:SS 格式倒计时，激活时显示具体时间而非仅图标
- **取消定时** — 随时取消，幂等操作
- **到期自动暂停** — 定时到期后自动调用 pause()，清除定时器状态
- **模式互斥** — 启动新定时器会替换旧定时器

**Provider 清单：**
- `timerServiceProvider` — TimerService 单例
- `timerStateProvider` — 当前定时器状态
- `remainingTimeProvider` — 每秒刷新的剩余时间流
- `formattedRemainingProvider` — 格式化后的倒计时文本
- `startDurationTimerProvider` / `startAfterCurrentProvider` / `cancelTimerProvider` — 操作
- `checkTimerExpiryProvider` / `onTrackCompletedProvider` — 到期/曲终检测

### 4.5 Progress（播放进度）

播放进度的自动保存与恢复机制。

**数据模型：** `PlayProgress` — 包含 connectionId、filePath、positionMs、durationMs、lastPlayedAt。

**核心功能：**
- **自动保存** — 多个触发点：10 秒周期定时器、播放→暂停转换、切歌、App 进后台、页面销毁
- **智能过滤** — 位置 < 5 秒不保存（视为未开始）；位置 > duration - 10 秒清除记录（视为已听完）；短于 10 秒的文件不自动清除
- **单条模式** — 使用 upsertLatest 确保同时只有一条活跃进度记录，替换旧的多行历史模式
- **进度恢复** — 启动时自动查找最近播放记录，恢复队列和播放位置
- **进度查询** — 浏览器中显示文件已保存的播放进度
- **清除进度** — 长按文件可清除单个进度记录

**Provider 清单：**
- `progressDaoProvider` — ProgressDao 实例
- `upsertProgressProvider` — 保存/更新进度（含智能过滤规则）
- `clearProgressProvider` — 清除单条进度
- `recentlyPlayedProvider` — 最近播放列表
- `latestPlayedProgressProvider` — 最近一条进度记录
- `progressForFileProvider` — 查询指定文件进度

### 4.7 Playlist（播放单）

本地播放单管理，支持创建、浏览、编辑播放单和曲目。

**数据模型：** `Playlist` — 包含 id、name、trackCount、createdAt、updatedAt。`PlaylistTrack` — 包含 id、playlistId、filePath、fileName、addedAt。

**核心功能：**
- **播放单 CRUD** — 创建播放单（输入名称）、删除播放单（确认对话框，CASCADE 自动清理曲目）
- **曲目管理** — 从文件浏览器批量选取曲目添加（去重检查），长按多选批量删除
- **播放单列表** — 显示所有播放单（名称 + 曲目数），排序（创建时间/名称），Slidable 左滑露出删除按钮
- **播放单详情** — 曲目列表、排序（添加时间/文件名）、点击曲目构建播放队列并跳转到播放页
- **Tab 导航** — HomeScreen 使用 TabController 切换播放单列表和文件浏览器，迷你播放器跨 Tab 持久显示
- **添加曲目弹窗** — 独立 ProviderScope 隔离导航状态的目录浏览弹窗，支持全选/取消/确认批量添加

**Provider 清单：**
- `playlistDaoProvider` — PlaylistDao 实例
- `playlistSortProvider` / `trackSortProvider` — 排序选项（持久化）
- `playlistListProvider` — 播放单列表（排序后）
- `playlistTracksProvider(playlistId)` — 指定播放单的曲目列表
- `createPlaylistProvider` / `deletePlaylistProvider` — 播放单变更
- `addTracksToPlaylistProvider` / `removeTracksFromPlaylistProvider` — 曲目变更

应用偏好配置管理。

**核心功能：**
- **默认播放速度** — 0.5x ~ 2.0x 六档选择，新曲目自动应用
- **记住播放速度** — 开关，开启后调速也同时更新默认速度，切歌不重置
- **快进/快退步长** — 10 / 15 / 30 / 60 秒可选
- **主题模式** — 跟随系统 / 亮色 / 暗色
- **连接管理入口** — 跳转到连接列表页面
- **关于页面** — 应用信息
- **运行日志** — Debug 模式下可查看 LogBuffer 捕获的运行时日志（环形缓冲区，最多 1000 条）

**Provider 清单：**
- `themeModeProvider` / `setThemeModeProvider` — 主题模式
- `seekStepSettingProvider` / `setSeekStepSettingProvider` — 步长设置
- `rememberSpeedProvider` / `setRememberSpeedProvider` — 记住速度开关
- `setDefaultSpeedProvider` — 默认速度设置（复用 player 模块）

---

## 5. 路由结构

| 路由 | 页面 | 说明 |
|------|------|------|
| `/onboarding` | 启动页 | 无连接时显示引导，有连接则自动跳转到 `/browser` |
| `/connection` | 添加连接 | WebDAV 连接配置表单 |
| `/connections` | 连接列表 | 管理所有已保存连接 |
| `/connections/edit/:id` | 编辑连接 | 修改已有连接配置 |
| `/browser` | 主页 Tab 导航 | HomeScreen（播放单 Tab + 文件浏览 Tab + 迷你播放器） |
| `/playlist/:id` | 播放单详情 | 曲目列表 + 添加/删除曲目 |
| `/player` | 播放器 | 全屏播放控制 |
| `/settings` | 设置 | 播放/外观/连接/关于 |
| `/about` | 关于 | 应用信息 |
| `/logs` | 运行日志 | 仅 Debug 模式可用 |

---

## 6. 目录结构

```
lib/
├── core/                           # 基础设施层
│   ├── database/
│   │   ├── database_helper.dart    # SQLite 初始化与迁移（v1→v2）
│   │   └── dao/
│   │       ├── connection_dao.dart # 连接 CRUD + 活跃切换 + 级联删除
│   │       └── progress_dao.dart   # 播放进度 UPSERT + 查询 + 智能过滤
│   ├── network/
│   │   └── webdav_client.dart      # WebDAV PROPFIND 封装（验证 + 目录列表）
│   └── services/
│       ├── audio_handler.dart      # audio_service BaseAudioHandler 实现
│       ├── audio_source_builder.dart # AudioSource 构建（Basic Auth + URL 编码）
│       ├── background_service.dart # 平台通道：moveTaskToBack（侧滑最小化）
│       ├── timer_service.dart      # 定时器纯逻辑状态机
│       └── log_buffer.dart         # 运行时日志环形缓冲区
├── features/                       # 功能模块
│   ├── home/
│   │   └── home_screen.dart             # 主页 Tab 导航（播放单 + 文件浏览）
│   ├── connection/
│   │   ├── connection_provider.dart
│   │   ├── connection_screen.dart       # 添加连接表单
│   │   ├── connection_list_screen.dart  # 连接列表（滑动操作）
│   │   ├── connection_edit_screen.dart  # 编辑连接
│   │   └── widgets/
│   │       └── connection_form.dart     # 连接表单控件
│   ├── browser/
│   │   ├── browser_provider.dart   # 目录浏览 + 导航栈 + 队列持久化
│   │   ├── browser_screen.dart     # 文件浏览页面（无 Scaffold，供 HomeScreen 嵌入）
│   │   └── widgets/
│   │       ├── breadcrumb_bar.dart  # 面包屑导航
│   │       └── file_list_item.dart  # 文件/目录列表项
│   ├── player/
│   │   ├── player_provider.dart    # 播放核心 Provider + 加载序列化
│   │   ├── player_screen.dart      # 全屏播放器 UI
│   │   ├── background_playback.dart # 后台播放状态机模型
│   │   ├── media_control_model.dart # 媒体控制模型（耳机按钮映射等）
│   │   └── widgets/
│   │       ├── mini_player_bar.dart # 迷你播放栏
│   │       └── queue_sheet.dart     # 队列弹出面板（含删除按钮）
│   ├── playlist/                   # 播放单功能
│   │   ├── playlist_provider.dart       # 播放单 Provider（排序/CRUD）
│   │   ├── playlist_list_screen.dart    # 播放单列表（Slidable 左滑删除）
│   │   ├── playlist_detail_screen.dart  # 播放单详情（曲目列表 + 多选删除）
│   │   └── widgets/
│   │       ├── playlist_list_item.dart  # 播放单列表项
│   │       ├── playlist_track_item.dart # 曲目列表项
│   │       └── add_tracks_browser.dart  # 添加曲目目录浏览弹窗
│   ├── timer/
│   │   ├── timer_provider.dart     # 定时器 Provider
│   │   └── widgets/
│   │       └── timer_button.dart   # 定时器底部弹出面板
│   ├── progress/
│   │   ├── progress_provider.dart  # 进度管理 Provider
│   │   └── progress_dialog.dart    # 进度恢复确认对话框
│   └── settings/
│       ├── settings_provider.dart  # 设置 Provider
│       ├── settings_screen.dart    # 设置页面
│       ├── about_screen.dart       # 关于页面
│       └── log_viewer_screen.dart  # 日志查看器
├── shared/
│   └── models/
│       ├── connection_config.dart  # 连接配置模型
│       ├── nas_file.dart           # 文件/目录模型
│       ├── play_progress.dart      # 播放进度模型
│       ├── play_queue.dart         # 播放队列模型（含 PlayMode 枚举 + withoutIndex）
│       ├── playlist.dart           # 播放单模型（Playlist / PlaylistTrack）
│       └── ...
└── main.dart                       # 应用入口 + ProviderScope + 路由配置
```

---

## 7. 数据库结构（v1 → v2）

```sql
-- 连接配置表
CREATE TABLE connections (
    id          INTEGER PRIMARY KEY AUTOINCREMENT,
    name        TEXT NOT NULL,
    url         TEXT NOT NULL,
    username    TEXT NOT NULL,
    password    TEXT NOT NULL,       -- flutter_secure_storage 引用 key
    base_path   TEXT NOT NULL DEFAULT '/',
    is_active   INTEGER NOT NULL DEFAULT 0,
    created_at  INTEGER NOT NULL,
    updated_at  INTEGER NOT NULL
);

-- 播放进度表（单条活跃记录模式）
CREATE TABLE play_progress (
    id             INTEGER PRIMARY KEY AUTOINCREMENT,
    connection_id  INTEGER NOT NULL,
    file_path      TEXT NOT NULL,
    position_ms    INTEGER NOT NULL DEFAULT 0,
    duration_ms    INTEGER,
    last_played_at INTEGER NOT NULL,
    UNIQUE(connection_id, file_path),
    FOREIGN KEY(connection_id) REFERENCES connections(id) ON DELETE CASCADE
);
CREATE INDEX idx_progress_lookup ON play_progress(connection_id, file_path);

-- v2 新增：播放单表
CREATE TABLE playlists (
    id         INTEGER PRIMARY KEY AUTOINCREMENT,
    name       TEXT NOT NULL,
    created_at INTEGER NOT NULL,
    updated_at INTEGER NOT NULL
);

-- v2 新增：播放单曲目表
CREATE TABLE playlist_tracks (
    id          INTEGER PRIMARY KEY AUTOINCREMENT,
    playlist_id INTEGER NOT NULL,
    file_path   TEXT NOT NULL,
    file_name   TEXT NOT NULL,
    added_at    INTEGER NOT NULL,
    FOREIGN KEY(playlist_id) REFERENCES playlists(id) ON DELETE CASCADE
);
CREATE INDEX idx_playlist_tracks_playlist_id ON playlist_tracks(playlist_id);
```

---

## 8. 关键依赖

```yaml
dependencies:
  just_audio: ^0.9.40           # 音频播放引擎
  audio_service: ^0.18.15       # 后台播放 / 锁屏控件
  webdav_client: ^1.2.0         # WebDAV 协议客户端
  sqflite: ^2.3.3               # SQLite 数据库
  flutter_riverpod: ^2.5.1      # 状态管理
  go_router: ^14.2.0            # 声明式路由
  shared_preferences: ^2.2.3    # 偏好存储
  flutter_secure_storage: ^9.0.0 # 安全存储（密码）
  flutter_slidable: ^4.0.3      # 滑动操作（连接列表、播放单列表）
  http: ^1.2.1                  # HTTP 客户端（WebDAV 直接调用）

dev_dependencies:
  mockito: ^5.4.4               # Mock 框架
  sqflite_common_ffi: ^2.3.3+1  # 测试用内存数据库
  fake_async: ^1.3.1            # 时间模拟
  build_runner: ^2.4.11         # 代码生成
```

---

## 9. 设计原则

1. **纯逻辑层可测试** — TimerService、PlayQueue 导航、seek 计算、进度过滤规则均为纯函数，不依赖 Flutter 或平台通道
2. **Provider 覆盖** — 基础设施（AudioPlayer、SharedPreferences、AudioHandler）通过 `ProviderScope.overrides` 注入，方便测试替换
3. **密码安全** — 明文密码仅存储在 flutter_secure_storage 中，数据库中仅保存引用 key；传输时通过 HTTPS 或 Basic Auth Header
4. **加载序列化** — 通过 `SerializedRequestGate` 确保对共享 AudioPlayer 的并发操作安全有序
5. **队列持久化** — 播放队列序列化到 SharedPreferences，App 重启后自动恢复；连接变更时保留队列但跳过预加载
