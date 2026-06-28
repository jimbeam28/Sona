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

## 开发流程（dev-plan / dev-exe / dev-check skill 链）

新功能与 Bug 修复通过三个 skill 串起来工作，**所有规约锚到代码不脑补**：

```
用户提需求 / 描述 bug
  → dev-plan skill
      读现有代码 → 逆抽现有行为规约 + 增量加新需求 Scenario
      输出 docs/features/{ID}.md（按 _TEMPLATE.md）
      输出更新 docs/dev/dev-status.json
      Bug 修复场景：先写失败复现测试 → 才允分析根因（硬门禁）
      向用户呈现 §1.2 用户视角 Scenario 表 + 跨模块影响 + 测试盲点 → 用户 ack
      （ack 后不自动继；用户手动启动 dev-exe）
      **铁律 4：每条 status: new Scenario 必须带否定断言**（防假阴面 bug）
  → dev-exe skill
      启动前检查 check_round：> 0 表明是 dev-check 打回的返工，
      必读 docs/dev/check_log.md 最末条作为本轮修复靶点清单
      Agent A 测试先行（只读 docs/features/{ID}.md §3/§4/§6，不读 lib/）
      Agent B 按 spec 实现（不允许违反任一 INV）
      Agent C 验证 spec 覆盖率（< 100% = FAIL）
      5 轮修复循环 + 3 轮失败 → blocked
      涉及 audio_service / AudioFocus / MethodChannel / 通知栏 → 强制 docs/dev/mqa-{ID}.md 手动 QA
      终门禁：flutter analyze 0 warnings / dart format 无变更 / 全量回归 PASS / **关键路径覆盖率 90%**
      第 8 步：标 done，**不自动继**，提示用户手动启动 dev-check
  → dev-check skill （独立评审，未参与过开发）
      7 项检查：
        1. spec vs 原需求贴合度  — 用户最初需求文字与 §1.2 对照，找 dev-plan 漏 / 脑补
        2. 实现对 spec 忠实度    — §3 每条 Scenario / §4 每个 INV 在代码中真实被实现且不可被违
        3. 回归测试充分性        — 测试是否真有断言、是否覆盖边界 / 异常
        4. 跨模块已识别不变量未破坏 — §7 列出的 cross_module_impacts 是否都有回归断言且 PASS
        5. 跨模块被漏识的破坏    — git show + grep + **跑全量 flutter test** 看是否真没被影响
        6. 基线覆盖率漂移        — 当前 lcov.info vs docs/dev/baseline-coverage.json，任一下降超容忍 FAIL
        7. 否定断言未被破坏     — §3 是否每条 status: new 真带否定断言，且测试中真有对应 expect(..., unchanged) 类断言
      **不亲手修复**——只出问题清单写入 docs/dev/check_log.md
      PASS  → 标 check_status=passed + **刷新 docs/dev/baseline-coverage.json**（基线持续上推）
      FAIL  → check_round + 1，impl_status 改回 pending，提示用户手动启动 dev-exe 重做
      3 轮上限仍 FAIL → 标 check_status=blocked_after_3_rounds，impl_status=blocked，等人工介入
```

### 关键路径覆盖率守护（新增）

- `docs/dev/baseline-coverage.json` — 基线快照，由 dev-check PASS 后刷新
- `docs/dev/scripts/coverage-check.sh` — 解析 lcov.info 与基线对比
  - `check-exe` 子命令：dev-exe 第 7 步用，守 critical_files 各 ≥ 90% / 新增 100%
  - `check-check` 子命令：dev-check 第 6 项用，against baseline 检测漂移
  - `refresh` 子命令：dev-check PASS 后刷新基线
- critical_files 默认清单 = domain 层全部 + PlayQueue 共享模型（baseline 缺时退化用）
- 漂移容忍阈值：overall 下降 >1% FAIL；critical 单文件下降 >2% FAIL

### 三 skill 的角色分工

| 维度 | dev-plan | dev-exe | dev-check |
|---|---|---|---|
| 视角 | 锚到代码逆抽 + 增量加需求 | 按 spec 实现 + 测试 | 独立评审，未参与过开发 |
| 铁律 1 | 锚到代码不脑补 | 测试 A 只读 spec 不读 lib | 不亲手修复 |
| 铁律 2 | Bug 修复先写失败复现测试 | 实现 B 不修改测试断言 | 重读原需求推回实现 |
| 铁律 3 | §1.2 必须呈现给用户审 | Spec 覆盖 < 100% 拒收 | 3 轮上限后强制 blocked |
| 铁律 4 | **每条新 Scenario 必带否定断言** | 关键路径覆盖率 ≥ 90% | **基线覆盖率漂移守护** |
| 触发 | "制定计划""分析需求" | "开始开发""实现" | "检查""审查" |

**dev-exe 内部 Agent C 与 dev-check 不重合**：Agent C 在 dev-exe 流程内、被 spec 框住视角，只查"每条 spec 是否被测"；dev-check 是独立视角，质疑 spec 本身对不对、实现对原需求贴不贴。二者互补不替代。

### 文件位置

- 功能详细设计模板：`docs/features/_TEMPLATE.md`
- 功能文档：`docs/features/{ID}.md`（如 `docs/features/CON-01.md`）
- 进度跟踪：`docs/dev/dev-status.json`
- 手动 QA 清单：`docs/dev/mqa-{ID}.md`（涉及平台原生时）
- Bug 复现测试：`test/features/{feature}/bug_{ID}_repro_test.dart`（修复前必须 FAIL，修复后必须 PASS）
- 评审报告：`docs/dev/check_log.md`（dev-check 写入，dev-exe 重做时读最末条作为修复靶点）
- 基线覆盖率快照：`docs/dev/baseline-coverage.json`（dev-check PASS 后刷新，对比漂移用）
- 覆盖率检查脚本：`docs/dev/scripts/coverage-check.sh`（dev-exe 第 7 步 + dev-check 第 6 项 + 刷新基线三合一）

### dev-status.json 关键字段

```json
"{ID}": {
  "spec_file":         "docs/features/{ID}.md",
  "spec_anchored_files": ["lib/.../x.dart", ...],   // 锚到代码（铁律）
  "scenarios":          ["{ID}-S1", ..., "{ID}-S{n}"],
  "invariants":         ["{ID}-INV1", ..., "{ID}-INV{n}"],
  "algorithms":         ["{ID}-ALG1", ...],
  "test_coverage_gaps": ["{ID}-S5", ...],           // dev-exe 必补
  "cross_module_impacts": ["BRW", "PRG", "PLY"],   // 跨模块影响
  "manual_qa_required": false | true,
  "manual_qa_file":     null | "docs/dev/mqa-{ID}.md",
  "user_acceptance_text": "见 docs/features/{ID}.md §1.2",
  "impl_status":    "pending" | "done" | "failed" | "blocked",
  "test_status":    "pending" | "passed",
  "check_status":   "pending" | "passed" | "round_1" | "round_2" | "round_3" | "blocked_after_3_rounds",
  "check_round":    0,                              // dev-check 打回累计次数
  "last_check_round_results": "",                   // 指向 check_log.md 最末条
  "last_checked_at": "",                            // 日期
  ...
}
```

字段生命周期（关键）：
- **dev-plan 创建**：`impl_status=test_status="pending"`，`check_status="pending"`，`check_round=0`
- **dev-exe 完成自身门禁**：`impl_status="done"`，`test_status="passed"`——**不动** check_*
- **dev-check 通过**：`check_status="passed"`，写 `last_checked_at`
- **dev-check 打回**：`check_status="round_N"`，`check_round=N`，**`impl_status` 改回 "pending"** 触发 dev-exe 重做
- **dev-exe 重做**：在第 1 步读 `check_round` 决定带 dev-check 上轮问题清单作为修复靶点
- **dev-check 3 轮上限仍 FAIL**：`check_status="blocked_after_3_rounds"`，`impl_status="blocked"`

### 渐进迁移策略

历史 `docs/design/state.md` 与 `docs/coverage-matrix.md` 等已删除——它们是与代码漂移的脑补规格，不再使用。
新功能开发流程通过 dev-plan **逆抽现实现**生成 `docs/features/{ID}.md`，仅在该功能下次要改时才写。

不在一开始就倒推全部功能文档。下次需要改 CON-04 时，dev-plan 才会逆抽并写 `docs/features/CON-04.md`。

**任何 LLM 看到代码里某行为不在 `docs/features/{ID}.md` 中**——以代码为准，文档未覆盖就是文档待补，不是代码违规。如果需要在文档补一条 Scenario/Senario，**必须**通过 dev-plan 流程增量补，**严禁**直接修改 features 文档。
