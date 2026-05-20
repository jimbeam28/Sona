# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## 项目概述

Sona — Android NAS 音频播放器，通过 WebDAV 协议流式播放远程存储上的音乐和有声书。Flutter + Riverpod + just_audio + audio_service。

## 架构分层

```
UI Layer (Flutter Widgets)
  → State Layer (Riverpod Provider)
    → Service Layer (WebDavClient / NasAudioHandler / TimerService)
      → Data Layer (WebDAV 远端 / SQLite 本地)
```

数据流：用户操作 → Widget → Provider → Service → Data Source → Provider 状态更新 → UI 重建

## 目录与模块

```
lib/
├── core/
│   ├── database/              # SQLite 初始化 + 迁移 (v1)
│   │   └── dao/               # ConnectionDao (CRUD/切换) + ProgressDao (UPSERT/智能过滤)
│   ├── network/
│   │   └── webdav_client.dart # WebDAV PROPFIND: 验证连接 + 列出目录
│   └── services/
│       ├── audio_handler.dart       # audio_service BaseAudioHandler（锁屏/通知控件）
│       ├── audio_source_builder.dart # AudioSource 构建（Basic Auth + URL 编码）
│       ├── timer_service.dart       # 定时器纯逻辑状态机（无 Flutter 依赖）
│       └── log_buffer.dart          # 运行时日志环形缓冲区（Debug 模式查看）
├── features/
│   ├── connection/            # 连接管理：添加/编辑/删除/验证 WebDAV 连接、切换活跃连接
│   ├── browser/               # 文件浏览：PROPFIND 目录列表、面包屑导航、排序(名称/时间)、缓存、点击建播放队列
│   ├── player/                # 音频播放：流式播放、队列管理、4 种播放模式、6 档速度、后台播放、迷你播放栏
│   ├── timer/                 # 定时停止：固定时长(5/10/15min+自定义)、播完当前、倒计时显示
│   ├── progress/              # 进度记忆：自动保存(5 触发点)、智能过滤(<5s 跳过, >duration-10s 清除)、恢复对话框
│   └── settings/              # 设置：默认速度、记住速度、快进步长、主题(system/light/dark)、关于、日志查看
├── shared/models/             # ConnectionConfig / NasFile / PlayProgress / PlayQueue
└── main.dart                  # 入口：ProviderScope 覆盖注入 + go_router 路由

test/features/                 # 按模块组织：connection / browser / player / timer / progress / settings
```

## 路由

| 路由 | 页面 | 说明 |
|------|------|------|
| `/onboarding` | 启动引导 | 无连接→引导添加，有连接→自动验证→进入 browser |
| `/connection` | 添加连接 | 表单→PROPFIND 验证→保存 |
| `/connections` | 连接列表 | 切换/编辑/删除 |
| `/connections/edit/:id` | 编辑连接 | 凭证变更需重验证 |
| `/browser` | 文件浏览 | 目录列表 + 面包屑 + 迷你播放栏 |
| `/player` | 播放器 | 全屏播放控制 |
| `/settings` | 设置 | 播放/外观/连接/关于 |
| `/about` | 关于 | 应用信息 |
| `/logs` | 日志 | 仅 kDebugMode |

## 数据库（SQLite v1）

- `connections` — 连接配置（password 字段存 secure_storage 引用 key）
- `play_progress` — 播放进度（单条活跃记录模式，UPSERT 语义）

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
- 纯逻辑层（TimerService、PlayQueue 导航、seek 计算、进度过滤）可直接单元测试，无 Flutter 依赖
