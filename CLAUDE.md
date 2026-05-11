# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## 目录结构

```
lib/
├── core/                    # 基础设施层
│   ├── database/            # SQLite 数据库
│   │   ├── database_helper.dart    # 初始化与迁移
│   │   └── dao/                    # 数据访问对象
│   │       ├── connection_dao.dart
│   │       └── progress_dao.dart
│   ├── network/
│   │   └── webdav_client.dart       # WebDAV 客户端封装
│   └── services/
│       ├── audio_source_builder.dart # AudioSource 构建（含 Basic Auth）
│       └── timer_service.dart        # 定时停止服务
├── features/                 # 功能模块
│   ├── connection/           # 连接管理：添加/编辑/删除/验证 NAS 连接
│   ├── browser/              # 文件浏览：目录树导航、文件列表、排序
│   ├── player/               # 音频播放：流式播放、队列、后台播放、迷你播放器
│   ├── timer/                # 定时停止：固定时长/播完当前
│   ├── progress/             # 播放进度记忆与恢复
│   └── settings/             # 设置：播放速度、主题、快进步长、关于
├── shared/
│   └── models/               # 跨模块数据模型
├── main.dart                 # 应用入口 + go_router 路由配置
test/
└── features/                 # 按模块组织的测试文件
    ├── connection/con_۰*_test.dart
    ├── browser/brw_۰*_test.dart
    ├── player/ply_۰*_test.dart
    ├── timer/timer_test.dart
    ├── progress/prg_test.dart
    └── settings/settings_test.dart
docs/
├── design/                   # 设计文档
│   ├── architecture.md       # 整体架构文档
│   ├── module-*.md           # 各模块设计文档
│   └── test-design.md        # 测试用例设计文档
└── dev/                      # 开发跟踪
    ├── dev-status.json       # 功能状态跟踪
    ├── dev_log.md            # 实现日志
    ├── fix.md                # 修复计划
    ├── fix-status.json       # 修复状态跟踪
    ├── analysis.md           # 分析报告
    └── progress.md           # 开发进度
```

## 模块说明

- **Connection**: NAS 连接的 CRUD、连接验证（PROPFIND）、切换活跃连接
- **Browser**: WebDAV 目录浏览、面包屑导航、音频文件过滤、排序、缓存
- **Player**: just_audio 流式播放、audio_service 后台播放/锁屏控件、队列/模式切换、速度调节、迷你播放器
- **Timer**: 固定时长（5/10/15min）和播完当前两种定时模式
- **Progress**: 自动保存播放位置（跳过开头<5s和结尾>duration-10s）、进度恢复对话框（含5秒超时自动继续）
- **Settings**: 默认播放速度、主题切换（system/light/dark）、快进/快退步长

## 常用命令

```bash
flutter pub get          # 安装依赖
flutter run              # 运行
flutter test             # 全部测试
flutter test test/features/connection/con_01_test.dart  # 单个测试文件
flutter analyze          # 静态分析
dart format lib test     # 格式化代码
dart run build_runner build  # 代码生成（mock）
```

## 架构分层

UI Layer（Flutter Widgets）→ State Layer（Riverpod Provider）→ Service Layer → Data Layer（WebDAV / SQLite）

数据流：用户操作 → Widget → Provider → Service → Data Source → Provider 状态更新 → UI 重建

## 关键依赖

- **just_audio** — 音频播放引擎
- **audio_service** — 后台播放、锁屏/通知栏媒体控件
- **webdav_client** — WebDAV 协议客户端
- **sqflite** — 本地 SQLite 数据库
- **flutter_riverpod** — 状态管理
- **go_router** — 声明式路由
- **mockito + sqflite_common_ffi** — 测试 mock 和内存数据库

## 测试注意事项

- 测试使用 `sqflite_ffi` 内存数据库，每个用例独立 `setUp`/`tearDown`
- 时间相关测试（Timer、Progress 超时）使用 `fake_async` 模拟时间流逝
- Provider 测试使用 `ProviderContainer` + mock 依赖，不依赖 widget 树
