# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## 项目概述

Sona — Android NAS 音频播放器，通过 WebDAV 协议流式播放远程存储上的音乐和有声书。Flutter + Riverpod + just_audio + audio_service。

## 架构分层

```
UI Layer (Flutter Widgets + Riverpod Provider)
  → Domain Layer (pure-Dart services, state machines, policy functions)
    → Contract Layer (abstract interfaces: IAudioPlayer / IAudioHandler / IConnectionDao / ISecureStorage)
      → Data Layer (WebDAV 远端 / SQLite 本地 / flutter_secure_storage)
```

每个 feature 内部按 UI → Provider → Domain → Contract 分层，Domain 层零 Flutter 依赖可独立单元测试。
跨 feature 依赖通过 `shared/di/providers.dart` 桥接，禁止 feature 间直接 import。

数据流：用户操作 → Widget → Provider → Domain Service → Contract → Data Source → Provider 状态更新 → UI 重建

## 目录与模块

```
lib/
├── core/
│   ├── contracts/                   # 抽象接口层（解耦数据源实现）
│   │   ├── audio_handler_contract.dart   # IAudioHandler — audio_service 接口
│   │   ├── audio_player_contract.dart    # IAudioPlayer — just_audio 接口
│   │   ├── database_contract.dart        # IConnectionDao / IProgressDao / IPlaylistDao
│   │   └── storage_contract.dart         # ISecureStorage — flutter_secure_storage 接口
│   ├── database/                    # SQLite 初始化 + 迁移 (v1→v2)
│   │   ├── database_helper.dart         # DatabaseProvider 单例
│   │   └── dao/                         # ConnectionDao + ProgressDao + PlaylistDao
│   ├── network/
│   │   └── webdav_client.dart           # WebDAV PROPFIND: 验证连接 + 列出目录
│   └── services/
│       ├── audio_handler.dart           # audio_service BaseAudioHandler（锁屏/通知控件）
│       ├── audio_source_builder.dart    # AudioSource 构建（Basic Auth + URL 编码）
│       ├── background_service.dart      # Android moveTaskToBack MethodChannel
│       ├── storage_utils.dart           # safeStorageRead / safeStorageWrite 带超时
│       └── log_buffer.dart              # 运行时日志环形缓冲区（Debug 模式查看）
├── features/
│   ├── connection/                # 连接管理
│   │   ├── domain/
│   │   │   ├── connection_service.dart   # 纯 Dart CRUD 服务（save/update/delete/setActive）
│   │   │   └── connection_validator.dart # URL/用户名/密码/路径校验函数
│   │   ├── widgets/
│   │   │   └── connection_form.dart      # 连接表单 Widget
│   │   ├── connection_provider.dart      # Riverpod providers
│   │   ├── connection_screen.dart        # 添加连接页
│   │   ├── connection_edit_screen.dart   # 编辑连接页
│   │   └── connection_list_screen.dart   # 连接列表页
│   ├── home/                      # 主页 Tab 导航（播放单 Tab + 文件浏览 Tab + 迷你播放器）
│   │   └── home_screen.dart
│   ├── browser/                   # 文件浏览
│   │   ├── domain/
│   │   │   ├── cache_policy.dart         # TTL 过期 + LRU 淘汰策略
│   │   │   ├── directory_service.dart    # 目录加载/缓存/排序纯 Dart 服务
│   │   │   └── navigation_stack.dart     # 目录导航栈状态机
│   │   ├── widgets/
│   │   │   ├── breadcrumb_bar.dart       # 面包屑导航
│   │   │   └── file_list_item.dart       # 文件列表项
│   │   ├── browser_provider.dart
│   │   └── browser_screen.dart
│   ├── player/                    # 音频播放
│   │   ├── domain/
│   │   │   ├── playback_orchestrator.dart # 播放编排：load/skip/remove/saveProgress
│   │   │   ├── request_gate.dart          # SerializedRequestGate 序列化请求门
│   │   │   ├── play_mode.dart             # 播放模式枚举 + nextIndex/previousIndex
│   │   │   ├── seek_utils.dart            # clampSeek/skipForward/skipBackward
│   │   │   ├── speed_manager.dart         # 6 档速度管理 + SharedPreferences 读写
│   │   │   ├── background_playback.dart   # 后台播放状态机 + AudioFocusState
│   │   │   └── media_control.dart         # 耳机按键映射 + 标题提取 + 格式化时长
│   │   ├── widgets/
│   │   │   ├── mini_player_bar.dart       # 迷你播放栏
│   │   │   └── queue_sheet.dart           # 播放队列弹出面板
│   │   ├── player_provider.dart
│   │   ├── player_screen.dart
│   │   ├── background_playback.dart       # re-export domain/background_playback.dart
│   │   └── media_control_model.dart       # 媒体控件模型（兼容层）
│   ├── playlist/                  # 播放单
│   │   ├── domain/
│   │   │   └── playlist_service.dart      # CRUD + 去重 + JSON 导入导出
│   │   ├── widgets/
│   │   │   ├── add_tracks_browser.dart    # 添加曲目文件浏览器
│   │   │   ├── playlist_list_item.dart    # 播放单列表项
│   │   │   └── playlist_track_item.dart   # 曲目列表项
│   │   ├── playlist_provider.dart
│   │   ├── playlist_list_screen.dart
│   │   └── playlist_detail_screen.dart
│   ├── timer/                     # 定时停止
│   │   ├── domain/
│   │   │   └── timer_service.dart         # 定时器纯逻辑状态机（无 Flutter 依赖）
│   │   ├── widgets/
│   │   │   └── timer_button.dart          # 定时器按钮
│   │   └── timer_provider.dart
│   ├── progress/                  # 进度记忆
│   │   ├── domain/
│   │   │   ├── progress_policy.dart       # shouldSave/shouldClear 纯函数策略
│   │   │   └── progress_service.dart      # 进度持久化编排 + 恢复对话框状态机
│   │   ├── progress_provider.dart
│   │   └── progress_dialog.dart
│   └── settings/                  # 设置
│       ├── domain/
│       │   └── settings_service.dart      # 主题/速度/快进步长 SharedPreferences 读写
│       ├── settings_provider.dart
│       ├── settings_screen.dart
│       ├── about_screen.dart
│       └── log_viewer_screen.dart
├── shared/
│   ├── di/
│   │   └── providers.dart             # 跨 feature provider 桥接（REF-31），禁止 feature 间直接 import
│   └── models/
│       ├── connection_config.dart     # ConnectionConfig
│       ├── nas_file.dart              # NasFile
│       ├── play_progress.dart         # PlayProgress
│       ├── play_queue.dart            # PlayQueue
│       └── playlist.dart             # Playlist + PlaylistTrack
└── main.dart                          # 入口：ProviderScope 覆盖注入 + go_router 路由

test/
├── features/
│   ├── browser/                 # BRW-01~08, Bug-03/07, Ref-17/18/19
│   ├── connection/              # CON-01~09, Bug-08, Ref-21/22
│   ├── coverage/                # AUD-01~05 覆盖率/边界/错误注入/并发/状态可达性
│   ├── home/                    # HomeScreen 测试
│   ├── player/                  # PLY-01~08/14, Bug-01/05/06, Ref-08~14
│   ├── playlist/                # PLY-09~14, Bug-02/04/08, Ref-26
│   ├── progress/                # PRG, Bug-09, Ref-24/25
│   ├── settings/                # Ref-27, Settings, LogViewer
│   └── timer/                   # Timer 测试
└── helpers/                     # fake_secure_storage / fake_webdav_client / mock_audio_player / test_database / test_factories / widget_helpers
```

## 路由

| 路由 | 页面 | 说明 |
|------|------|------|
| `/onboarding` | 启动引导 | 无连接→引导添加，有连接→自动验证→进入 browser |
| `/connection` | 添加连接 | 表单→PROPFIND 验证→保存 |
| `/connections` | 连接列表 | 切换/编辑/删除 |
| `/connections/edit/:id` | 编辑连接 | 凭证变更需重验证 |
| `/browser` | 主页 | HomeScreen（播放单 Tab + 文件浏览 Tab + 迷你播放器） |
| `/playlist/:id` | 播放单详情 | 曲目列表 + 添加/删除 |
| `/player` | 播放器 | 全屏播放控制 |
| `/settings` | 设置 | 播放/外观/连接/关于 |
| `/about` | 关于 | 应用信息 |
| `/logs` | 日志 | 仅 kDebugMode |

## 数据库（SQLite v2）

- `connections` — 连接配置（password 字段存 secure_storage 引用 key）
- `play_progress` — 播放进度（单条活跃记录模式，UPSERT 语义）
- `playlists` / `playlist_tracks` — 播放单与曲目（v2 迁移新增，CASCADE 删除）

密码明文仅存储在 `flutter_secure_storage`，key 格式：`connection_password_{id}`。

## 常用命令

```bash
flutter pub get              # 安装依赖
flutter run                  # 运行
flutter test                 # 全部测试
flutter test test/features/connection/con_01_test.dart  # 单个测试
flutter analyze              # 静态分析
dart format lib test         # 格式化
```

## 测试注意事项

- 使用 `sqflite_ffi` 内存数据库，每个用例独立 `setUp`/`tearDown`
- 时间相关测试（Timer、Progress）使用 `fake_async` 模拟时间流逝
- Provider 测试使用 `ProviderContainer` + mock 依赖，不依赖 widget 树
- 纯逻辑层（Domain 层全部 service/policy/state machine）可直接单元测试，无 Flutter 依赖
- 测试 helper 统一放 `test/helpers/`：`fake_secure_storage` / `fake_webdav_client` / `mock_audio_player` / `test_database` / `test_factories` / `widget_helpers`
- 通过 `core/contracts/` 抽象接口注入 fake 实现，避免平台 channel 依赖
