# 开发进度文档

## 说明

本文档将整个系统拆分为可独立实现的功能单元，按开发顺序排列。每个功能标注对应的设计文档和章节，以及依赖关系。

状态说明：`[ ]` 待开始 / `[~]` 进行中 / `[x]` 已完成

---

## 阶段一：项目基础搭建

| # | 功能 | 设计文档 | 依赖 | 状态 |
|---|------|----------|------|------|
| F-001 | Flutter 项目初始化，配置 pubspec.yaml 依赖 | [architecture.md §7](./architecture.md) | — | [ ] |
| F-002 | 配置 Android 权限和 audio_service 前台服务 | [module-player.md §3.3](./module-player.md) | F-001 | [ ] |
| F-003 | 初始化 SQLite 数据库，创建 connections 表 | [module-connection.md §3.3](./module-connection.md) | F-001 | [ ] |
| F-004 | 初始化 SQLite 数据库，创建 play_progress 表 | [module-progress.md §4](./module-progress.md) | F-003 | [ ] |
| F-005 | 配置 go_router 路由结构（Connection/Browser/Player/Settings） | [architecture.md §5](./architecture.md) | F-001 | [ ] |
| F-006 | 配置 Riverpod ProviderScope，全局状态初始化 | [architecture.md §3](./architecture.md) | F-001 | [ ] |

---

## 阶段二：Connection 模块

| # | 功能 | 设计文档 | 依赖 | 状态 |
|---|------|----------|------|------|
| F-007 | ConnectionConfig 数据模型 | [module-connection.md §4](./module-connection.md) | F-001 | [ ] |
| F-008 | ConnectionDao：增删改查实现 | [module-connection.md §3.3](./module-connection.md) | F-003, F-007 | [ ] |
| F-009 | WebDAV 客户端封装（PROPFIND 请求、Basic Auth） | [module-connection.md §3.2](./module-connection.md) | F-001 | [ ] |
| F-010 | 连接验证逻辑（CON-02） | [module-connection.md §3.2](./module-connection.md) | F-009 | [ ] |
| F-011 | 密码安全存储（flutter_secure_storage） | [module-connection.md §3.3](./module-connection.md) | F-001 | [ ] |
| F-012 | ConnectionProvider：活跃连接、连接列表状态 | [module-connection.md §5](./module-connection.md) | F-008, F-011 | [ ] |
| F-013 | 添加连接 UI（表单页面，CON-01） | [module-connection.md §3.1](./module-connection.md) | F-010, F-012 | [ ] |
| F-014 | 连接列表 UI（切换/编辑/删除，CON-04/05/06） | [module-connection.md §3.4-3.6](./module-connection.md) | F-012, F-013 | [ ] |
| F-015 | 首次启动引导（无连接时跳转添加连接页） | [module-connection.md §3.1](./module-connection.md) | F-012, F-013 | [ ] |

---

## 阶段三：Browser 模块

| # | 功能 | 设计文档 | 依赖 | 状态 |
|---|------|----------|------|------|
| F-016 | NasFile 数据模型 | [module-browser.md §4](./module-browser.md) | F-001 | [ ] |
| F-017 | WebDAV 目录列表请求和 PROPFIND 响应解析 | [module-browser.md §3.1](./module-browser.md) | F-009, F-016 | [ ] |
| F-018 | 音频文件格式过滤和类型识别（BRW-03） | [module-browser.md §3.3](./module-browser.md) | F-017 | [ ] |
| F-019 | 导航栈 Provider（BRW-02） | [module-browser.md §5](./module-browser.md) | F-006 | [ ] |
| F-020 | 目录内容 Provider（含内存缓存，BRW-05） | [module-browser.md §5](./module-browser.md) | F-017, F-019 | [ ] |
| F-021 | 文件列表 UI（目录行、音频文件行） | [module-browser.md §6](./module-browser.md) | F-020 | [ ] |
| F-022 | 面包屑导航组件（BRW-02） | [module-browser.md §3.2](./module-browser.md) | F-019, F-021 | [ ] |
| F-023 | 下拉刷新（BRW-06） | [module-browser.md §3.6](./module-browser.md) | F-020, F-021 | [ ] |
| F-024 | 文件排序功能（BRW-07） | [module-browser.md §3.7](./module-browser.md) | F-020, F-021 | [ ] |
| F-025 | 加载/错误/空状态 UI | [module-browser.md §3.1](./module-browser.md) | F-021 | [ ] |

---

## 阶段四：Player 模块核心

| # | 功能 | 设计文档 | 依赖 | 状态 |
|---|------|----------|------|------|
| F-026 | MediaItem 和 PlaybackState 数据模型 | [module-player.md §4](./module-player.md) | F-001 | [ ] |
| F-027 | NasAudioHandler 基础实现（just_audio + audio_service） | [module-player.md §5](./module-player.md) | F-009, F-026 | [ ] |
| F-028 | 带 Basic Auth 的 AudioSource 构建（PLY-01） | [module-player.md §3.1](./module-player.md) | F-027 | [ ] |
| F-029 | 播放/暂停/Seek 控制（PLY-02） | [module-player.md §3.2](./module-player.md) | F-027 | [ ] |
| F-030 | 播放队列管理（PLY-05） | [module-player.md §3.5](./module-player.md) | F-027 | [ ] |
| F-031 | 从 Browser 点击文件构建队列并开始播放（BRW-04） | [module-browser.md §3.4](./module-browser.md) | F-025, F-030 | [ ] |
| F-032 | 后台播放前台服务配置（PLY-03） | [module-player.md §3.3](./module-player.md) | F-027 | [ ] |
| F-033 | 锁屏/通知栏媒体控件（PLY-04） | [module-player.md §3.4](./module-player.md) | F-032 | [ ] |
| F-034 | 耳机按键支持（PLY-04） | [module-player.md §3.4](./module-player.md) | F-033 | [ ] |
| F-035 | 播放模式切换（PLY-06） | [module-player.md §3.6](./module-player.md) | F-030 | [ ] |
| F-036 | 播放速度调节（PLY-07） | [module-player.md §3.7](./module-player.md) | F-027 | [ ] |
| F-037 | PlayerProvider：播放状态管理 | [module-player.md §5](./module-player.md) | F-027 | [ ] |
| F-038 | 播放器完整页面 UI | [module-player.md §6](./module-player.md) | F-037 | [ ] |
| F-039 | 迷你播放器组件（PLY-08） | [module-player.md §3.8](./module-player.md) | F-037, F-038 | [ ] |
| F-040 | 快进/快退 15 秒按钮（PLY-02） | [module-player.md §3.2](./module-player.md) | F-029, F-038 | [ ] |

---

## 阶段五：Progress 模块

| # | 功能 | 设计文档 | 依赖 | 状态 |
|---|------|----------|------|------|
| F-041 | PlayProgress 数据模型 | [module-progress.md §5](./module-progress.md) | F-001 | [ ] |
| F-042 | ProgressDao：保存/查询/删除进度 | [module-progress.md §6](./module-progress.md) | F-004, F-041 | [ ] |
| F-043 | 自动保存进度（10秒定时 + 暂停/切换/后台触发，PRG-01） | [module-progress.md §3.1](./module-progress.md) | F-029, F-042 | [ ] |
| F-044 | 播放结束时清除进度记录（PRG-01） | [module-progress.md §3.1](./module-progress.md) | F-043 | [ ] |
| F-045 | 进度恢复确认对话框（PRG-03） | [module-progress.md §3.3](./module-progress.md) | F-031, F-042 | [ ] |
| F-046 | 文件列表进度指示器（PRG 模块集成到 Browser） | [module-progress.md §7](./module-progress.md) | F-021, F-042 | [ ] |
| F-047 | 清除单个文件进度（PRG-04） | [module-progress.md §3.4](./module-progress.md) | F-042, F-046 | [ ] |

---

## 阶段六：Timer 模块

| # | 功能 | 设计文档 | 依赖 | 状态 |
|---|------|----------|------|------|
| F-048 | SleepTimer 数据模型 | [module-timer.md §4](./module-timer.md) | F-001 | [ ] |
| F-049 | SleepTimerNotifier：固定时长定时（TMR-01） | [module-timer.md §3.1](./module-timer.md) | F-029, F-048 | [ ] |
| F-050 | SleepTimerNotifier：播完当前停止（TMR-02） | [module-timer.md §3.2](./module-timer.md) | F-027, F-048 | [ ] |
| F-051 | 取消定时（TMR-04） | [module-timer.md §3.4](./module-timer.md) | F-049 | [ ] |
| F-052 | 剩余时间倒计时 Stream（TMR-03） | [module-timer.md §3.3](./module-timer.md) | F-049 | [ ] |
| F-053 | 定时按钮 UI + 底部弹出菜单 | [module-timer.md §6](./module-timer.md) | F-049, F-050, F-051, F-052 | [ ] |

---

## 阶段七：Settings 模块

| # | 功能 | 设计文档 | 依赖 | 状态 |
|---|------|----------|------|------|
| F-054 | AppSettingsNotifier：默认播放速度（SET-01） | [module-settings.md §3.1](./module-settings.md) | F-006 | [ ] |
| F-055 | AppSettingsNotifier：快进步长（SET-04） | [module-settings.md §3.4](./module-settings.md) | F-006 | [ ] |
| F-056 | AppSettingsNotifier：主题模式（SET-03） | [module-settings.md §3.3](./module-settings.md) | F-006 | [ ] |
| F-057 | 设置页面 UI | [module-settings.md §6](./module-settings.md) | F-054, F-055, F-056 | [ ] |
| F-058 | 关于页面（SET-05） | [module-settings.md §3.5](./module-settings.md) | F-057 | [ ] |

---

## 阶段八：测试

| # | 功能 | 设计文档 | 依赖 | 状态 |
|---|------|----------|------|------|
| F-059 | Connection 模块单元测试（CON-T01 ~ CON-T34）：表单验证、连接验证全状态、ConnectionDao CRUD、切换/编辑/删除逻辑 | [test-design.md §2.1~2.6](./test-design.md) | F-015 | [ ] |
| F-060 | Connection 模块 Widget 测试（CON-T35 ~ CON-T41）：表单 UI 交互、密码显隐、加载/成功/失败状态 | [test-design.md §2.7](./test-design.md) | F-059 | [ ] |
| F-061 | Browser 模块单元测试（BRW-T01 ~ BRW-T42）：PROPFIND 解析、格式过滤、导航栈、队列构建、缓存、下拉刷新、排序持久化 | [test-design.md §3.1~3.7](./test-design.md) | F-025 | [ ] |
| F-062 | Browser 模块 Widget 测试（BRW-T43 ~ BRW-T50）：骨架屏、空状态、进度条显示、排序菜单、图标区分 | [test-design.md §3.8](./test-design.md) | F-061 | [ ] |
| F-063 | Player 模块单元测试（PLY-T01 ~ PLY-T47）：Basic Auth、seek 边界、快进快退边界、后台播放、耳机按键、队列重启恢复、播放模式流转、速度与默认速度隔离 | [test-design.md §4.1~4.7](./test-design.md) | F-040 | [ ] |
| F-064 | Player 模块 Widget 测试（PLY-T48 ~ PLY-T61）：迷你播放器显隐/交互、播放器 UI 状态、进度条拖拽、速度菜单 | [test-design.md §4.8~4.9](./test-design.md) | F-063 | [ ] |
| F-065 | Timer 模块单元测试（TMR-T01 ~ TMR-T22）：固定时长/播完当前/取消的状态变更、倒计时边界值（60s 临界）、fake_async 验证到期触发、取消幂等性 | [test-design.md §5.1~5.5](./test-design.md) | F-053 | [ ] |
| F-066 | Timer 模块 Widget 测试（TMR-T23 ~ TMR-T29）：按钮激活/未激活状态、BottomSheet 选项数量、取消后恢复 | [test-design.md §5.6](./test-design.md) | F-065 | [ ] |
| F-067 | Progress 模块单元测试（PRG-T01 ~ PRG-T23）：UPSERT 语义、5s/末尾边界值、4 个生命周期触发点、percentage 计算（含 null duration）、最近播放列表、对话框超时 fake_async | [test-design.md §6.1~6.3](./test-design.md) | F-047 | [ ] |
| F-068 | Progress 模块 Widget 测试（PRG-T24 ~ PRG-T28）：长按菜单条件显示、清除后进度条消失 | [test-design.md §6.4](./test-design.md) | F-067 | [ ] |
| F-069 | Settings 模块单元测试（SET-T01 ~ SET-T22）：6 个速度选项持久化、步长持久化、主题三选一持久化、首次启动默认值、播放器调速不覆盖默认速度、步长联动播放器快进距离 | [test-design.md §7.1~7.4](./test-design.md) | F-058 | [ ] |
| F-070 | Settings 模块 Widget 测试（SET-T23 ~ SET-T34）：4 个 Section 渲染、ListTile 副标题、各选项对话框弹出、关于页面内容 | [test-design.md §7.5~7.6](./test-design.md) | F-069 | [ ] |
| F-071 | 集成测试（INT-T01 ~ INT-T08）：首次启动、浏览到播放、进度记忆、定时停止（固定/播完当前）、多级目录导航、后台播放控制、切换连接 | [test-design.md §8](./test-design.md) | F-060, F-062, F-064, F-066, F-068, F-070 | [ ] |

---

## 文档索引

| 文档 | 说明 |
|------|------|
| [architecture.md](./architecture.md) | 整体架构、技术选型、目录结构 |
| [module-connection.md](./module-connection.md) | Connection 模块功能设计 |
| [module-browser.md](./module-browser.md) | Browser 模块功能设计 |
| [module-player.md](./module-player.md) | Player 模块功能设计 |
| [module-timer.md](./module-timer.md) | Timer 模块功能设计 |
| [module-progress.md](./module-progress.md) | Progress 模块功能设计 |
| [module-settings.md](./module-settings.md) | Settings 模块功能设计 |
| [test-design.md](./test-design.md) | 测试用例设计 |
