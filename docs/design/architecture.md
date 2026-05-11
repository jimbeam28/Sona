# NAS 音乐/有声书 Android APP — 整体架构文档

## 1. 项目概述

本项目是一个面向 Android 平台的音频播放器，数据来源为飞牛OS NAS，通过 WebDAV 协议访问。
核心功能包括：音乐和有声书播放、播放进度记忆、播放速度调节、定时停止。
架构设计以扩展性为核心原则，方便后续持续添加新功能。

---

## 2. 技术选型

| 技术 | 选型 | 理由 |
|------|------|------|
| 开发框架 | Flutter (Dart) | 原生 Android 性能，音频生态成熟，后续可扩展 iOS |
| NAS 接入 | WebDAV | 飞牛OS 原生支持，HTTP 协议，移动端兼容性最好，支持流式播放 |
| 状态管理 | Riverpod | 灵活、可测试，适合中等复杂度应用 |
| 本地存储 | SQLite (sqflite) | 存储播放进度、收藏、连接配置 |
| 路由 | go_router | 声明式路由，支持深链接 |
| 音频引擎 | just_audio | Flutter 生态最成熟的音频播放库 |
| 后台播放 | audio_service | 系统媒体控件、锁屏控件、通知栏集成 |

---

## 3. 整体架构

```
┌─────────────────────────────────────────────────────────┐
│                      UI Layer                           │
│  ┌──────────┐ ┌──────────┐ ┌──────────┐ ┌──────────┐  │
│  │Connection│ │ Browser  │ │  Player  │ │ Settings │  │
│  └──────────┘ └──────────┘ └──────────┘ └──────────┘  │
└─────────────────────────────────────────────────────────┘
                          │
┌─────────────────────────────────────────────────────────┐
│                   State Layer (Riverpod)                 │
│  ┌──────────────┐ ┌──────────────┐ ┌─────────────────┐ │
│  │ConnectionPvdr│ │ BrowserPvdr  │ │  PlayerProvider │ │
│  └──────────────┘ └──────────────┘ └─────────────────┘ │
└─────────────────────────────────────────────────────────┘
                          │
┌─────────────────────────────────────────────────────────┐
│                   Service Layer                         │
│  ┌──────────────┐ ┌──────────────┐ ┌─────────────────┐ │
│  │ WebDAVService│ │ AudioService │ │  TimerService   │ │
│  └──────────────┘ └──────────────┘ └─────────────────┘ │
└─────────────────────────────────────────────────────────┘
                          │
┌─────────────────────────────────────────────────────────┐
│                   Data Layer                            │
│  ┌──────────────┐ ┌──────────────┐                     │
│  │  WebDAV API  │ │  SQLite DB   │                     │
│  │  (NAS 远端)  │ │  (本地存储)  │                     │
│  └──────────────┘ └──────────────┘                     │
└─────────────────────────────────────────────────────────┘
```

---

## 4. 模块划分

### 4.1 Connection 模块
负责 NAS 连接配置的管理，包括 WebDAV 服务器地址、认证信息的录入、验证和持久化。

**文档：** [module-connection.md](./module-connection.md)

### 4.2 Browser 模块
负责 NAS 文件系统的浏览，展示目录树和音频文件列表，支持导航和文件选择。

**文档：** [module-browser.md](./module-browser.md)

### 4.3 Player 模块
核心播放模块，负责音频流式播放、播放控制、后台播放、锁屏媒体控件集成。

**文档：** [module-player.md](./module-player.md)

### 4.4 Timer 模块
定时停止功能，��持固定时长（5/10/15分钟）和播完当前音频两种模式。

**文档：** [module-timer.md](./module-timer.md)

### 4.5 Progress 模块
播放进度记忆，自动保存每个文件的播放位置，下次打开时自动续播。

**文档：** [module-progress.md](./module-progress.md)

### 4.6 Settings 模块
应用设置，包括播放速度、界面主题等用户偏好配置。

**文档：** [module-settings.md](./module-settings.md)

---

## 5. 目录结构

```
lib/
├── core/
│   ├── network/
│   │   └── webdav_client.dart       # WebDAV 客户端封装
│   ├── database/
│   │   ├── database_helper.dart     # SQLite 初始化和迁移
│   │   └── dao/                     # 数据访问对象
│   │       ├── connection_dao.dart
│   │       └── progress_dao.dart
│   └── services/
│       ├── audio_handler.dart       # audio_service 处理器
│       └── timer_service.dart       # 定时停止服务
├── features/
│   ├── connection/
│   │   ├── connection_provider.dart
│   │   ├── connection_screen.dart
│   │   └── widgets/
│   ├── browser/
│   │   ├── browser_provider.dart
│   │   ├── browser_screen.dart
│   │   └── widgets/
│   ├── player/
│   │   ├── player_provider.dart
│   │   ├── player_screen.dart
│   │   └── widgets/
│   └── settings/
│       ├── settings_provider.dart
│       └── settings_screen.dart
├── shared/
│   ├── models/
│   │   ├── nas_file.dart            # 文件/目录模型
│   │   ├── connection_config.dart   # 连接配置模型
│   │   └── play_progress.dart      # 播放进度模型
│   └── widgets/
│       └── common_widgets.dart
└── main.dart
```

---

## 6. 数据流

```
用户操作 → UI Widget → Riverpod Provider → Service → Data Source
                                                    ↓
                                              WebDAV / SQLite
                                                    ↓
                                         Provider 状态更新 → UI 重建
```

---

## 7. 关键依赖

```yaml
dependencies:
  flutter:
    sdk: flutter
  just_audio: ^0.9.40
  audio_service: ^0.18.15
  webdav_client: ^1.2.0
  sqflite: ^2.3.3
  flutter_riverpod: ^2.5.1
  riverpod_annotation: ^2.3.5
  go_router: ^14.2.0
  path_provider: ^2.1.3
  shared_preferences: ^2.2.3

dev_dependencies:
  riverpod_generator: ^2.4.0
  build_runner: ^2.4.11
  flutter_test:
    sdk: flutter
  mockito: ^5.4.4
```

---

## 8. 扩展性设计原则

1. **功能模块化**：每个功能独立为一个 feature 目录，包含自己的 Provider、Screen 和 Widget
2. **Service 层隔离**：业务逻辑在 Service 层，UI 层只通过 Provider 交互，方便替换实现
3. **数据库版本管理**：SQLite 使用版本号迁移，新功能可以安全添加新表
4. **接口抽象**：WebDAV 客户端通过抽象接口定义，方便后续支持其他协议（SMB、FTP 等）
