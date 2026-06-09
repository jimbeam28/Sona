# Sona 模块化重构计划

> 创建日期: 2026-06-09
> 基于: state.md (状态机规格书) + test.md (测试覆盖审计) + BUG.md (工程问题记录)

---

## Context

Sona 项目存在三个反复出现的工程问题：
1. Bug 修复不彻底——一个 bug 需要多次修复
2. 修改代码时为其他功能引入新 bug
3. CI 静态检查经常失败

根本原因是架构问题：`player_provider.dart` (1092 行) 混合 7+ 种职责，15 个"函数即 Provider"反模式隐藏依赖关系，跨 feature 紧耦合（player 直接 import browser/connection/progress/timer 的 provider），导致改一行牵一发动全身。

**目标**：以 `docs/design/state.md` 为行为规格书，重构为高内聚低耦合的模块化架构，每个状态转移都有对应测试守护。即使大规模重构甚至重写也无妨。

---

## 目标架构

### 核心原则

1. **Domain 层零 Flutter 依赖** — 纯 Dart 类和函数，可直接 `test()` 测试，无需 mock
2. **依赖单向流动** — Feature 依赖 Core，不互相依赖；跨 feature 依赖通过接口解耦
3. **state.md 即规格书** — 每个状态机映射为一个 domain 类/函数，每个转移映射为一个测试用例
4. **Provider 是薄胶水** — Riverpod provider 只做依赖组装，不含业务逻辑

### 目录结构

```
lib/
  core/
    contracts/                    # 抽象接口（所有 feature 共享的契约）
      audio_player_contract.dart  # IAudioPlayer 接口
      storage_contract.dart       # ISecureStorage 接口
      webdav_contract.dart        # IWebDavClient 接口（已有，需扩展）
      audio_handler_contract.dart # IAudioHandler 接口
    database/                     # SQLite 实现（保留现有）
    network/                      # WebDAV 实现（保留现有）
    services/                     # 平台服务（保留现有，提取纯逻辑）
  features/
    connection/
      domain/                     # 纯逻辑
        connection_model.dart     # ConnectionConfig（移自 shared/models）
        connection_validator.dart # URL 验证、表单校验（纯函数）
        connection_service.dart   # 保存流程（原子性：DB+SecureStorage）
      data/                       # 数据层
        connection_dao.dart       # 实现 IConnectionDao 接口
      presentation/               # UI 层
        connection_screen.dart
        connection_edit_screen.dart
        connection_list_screen.dart
        connection_provider.dart  # 薄胶水：仅组装 domain + data
        widgets/
    browser/
      domain/
        directory_service.dart    # 目录加载、缓存策略、排序（纯逻辑）
        navigation_stack.dart     # NavigationStackNotifier（移自 provider）
        cache_policy.dart         # TTL、LRU 策略（纯函数）
      data/
        webdav_repository.dart    # 调用 IWebDavClient
      presentation/
        browser_screen.dart
        browser_provider.dart     # 薄胶水
        widgets/
    player/
      domain/
        play_queue.dart           # PlayQueue 模型（移自 shared/models）
        seek_utils.dart           # clampSeek, skipForward, skipBackward
        play_mode.dart            # PlayMode 循环、图标映射
        speed_manager.dart        # 速度验证、持久化逻辑
        playback_orchestrator.dart # loadAndPlay 核心流（纯逻辑，接收依赖参数）
        request_gate.dart         # SerializedRequestGate
        background_playback.dart  # BackgroundPlaybackConfig 状态机
        media_control.dart        # 标题提取、耳机按钮映射
      data/
        audio_source_builder.dart # 保留现有
      presentation/
        player_screen.dart
        player_provider.dart      # 薄胶水
        mini_player_bar.dart
        queue_sheet.dart
    playlist/
      domain/
        playlist_service.dart     # CRUD + 去重 + 导入导出
      data/
        playlist_dao.dart         # 实现 IPlaylistDao 接口
      presentation/
        playlist_list_screen.dart
        playlist_detail_screen.dart
        playlist_provider.dart
        widgets/
    progress/
      domain/
        progress_policy.dart      # shouldSave/shouldClear（已有，移出 DAO）
        progress_service.dart     # 保存/恢复/清除逻辑
      data/
        progress_dao.dart         # 实现 IProgressDao 接口
      presentation/
        progress_dialog.dart
        progress_provider.dart
    timer/
      domain/
        timer_service.dart        # 保留现有（已是纯逻辑状态机）
      presentation/
        timer_provider.dart       # 薄胶水
        widgets/timer_button.dart
    settings/
      domain/
        settings_service.dart     # 主题、速度、步长的读写逻辑
      presentation/
        settings_screen.dart
        settings_provider.dart
  shared/
    models/                       # 纯数据类（NasFile, PlayProgress 等）
    di/
      providers.dart              # 跨 feature 的 provider 桥接（唯一允许交叉 import 的地方）
  app/
    router.dart                   # GoRouter 定义
    app.dart                      # NasAudioPlayerApp
    onboarding.dart               # _OnboardingPage
  main.dart                       # 入口
```

### 依赖关系图

```
┌─────────────────────────────────────────────────────┐
│                    Presentation Layer                │
│  (Widgets + Riverpod Providers — 薄胶水)             │
└──────────────────────┬──────────────────────────────┘
                       │ 调用
┌──────────────────────▼──────────────────────────────┐
│                    Domain Layer                      │
│  (纯 Dart: 模型 + 服务 + 策略 + 状态机)              │
│  零 Flutter 依赖，零 Riverpod 依赖                    │
└──────────────────────┬──────────────────────────────┘
                       │ 实现接口
┌──────────────────────▼──────────────────────────────┐
│                    Data Layer                        │
│  (DAO + Repository + Platform Service)               │
└──────────────────────┬──────────────────────────────┘
                       │ 依赖
┌──────────────────────▼──────────────────────────────┐
│                    Core Layer                        │
│  (Contracts + Database + Network + Services)         │
└─────────────────────────────────────────────────────┘
```

**跨 feature 解耦**：`shared/di/providers.dart` 是唯一允许 import 多个 feature 的文件。它通过 core/contracts 中的接口将各 feature 连接起来。

---

## 与 state.md 的映射关系

每个 state.md 中的状态机映射到一个 domain 类：

| state.md 章节 | Domain 类 | 文件 | 测试文件 |
|---|---|---|---|
| 2.1 Onboarding | `ConnectionValidator.startupValidate()` | `connection/domain/connection_validator.dart` | `test/features/connection/` |
| 2.2 Add Form | `ConnectionService.saveConnection()` | `connection/domain/connection_service.dart` | 同上 |
| 2.3 Connection List | `ConnectionService.deleteConnection()` | 同上 | 同上 |
| 2.4 Edit Connection | `ConnectionService.updateConnection()` | 同上 | 同上 |
| 3.1 PlayerLoadStatus | `PlayerLoadState` (enum+class) | `player/domain/playback_orchestrator.dart` | `test/features/player/` |
| 3.2 TrackLoadStatus | `TrackLoadResult` | 同上 | 同上 |
| 3.3 PlayMode | `PlayModeManager` | `player/domain/play_mode.dart` | 同上 |
| 3.4 Play lifecycle | `PlaybackOrchestrator.loadAndPlay()` | `player/domain/playback_orchestrator.dart` | 同上 |
| 3.5 Queue removal | `PlaybackOrchestrator.removeTrack()` | 同上 | 同上 |
| 3.6 SerializedRequestGate | `RequestGate` | `player/domain/request_gate.dart` | 同上 |
| 4.1-4.4 Timer | `TimerService` (已有) | `timer/domain/timer_service.dart` | `test/features/timer/` |
| 5.1-5.4 Progress | `ProgressPolicy` + `ProgressService` | `progress/domain/` | `test/features/progress/` |
| 6.1-6.5 Browser | `DirectoryService` + `NavigationStack` | `browser/domain/` | `test/features/browser/` |
| 7.1-7.3 Playlist | `PlaylistService` | `playlist/domain/` | `test/features/playlist/` |
| 8.1-8.3 Home | (UI 层，无独立 domain) | `app/` | `test/features/home/` |
| 9.1-9.4 跨功能 | `shared/di/providers.dart` | `shared/di/` | `test/integration/` |

---

## 测试策略

### 分层测试

```
Layer 1: Domain 单元测试 (最快、最多)
  - 纯函数：直接 test()，无 mock
  - 状态机：构造初始状态 → 调用方法 → 断言新状态
  - 覆盖 state.md 中每个状态转移

Layer 2: Data 层测试 (中等)
  - DAO：sqflite_ffi 内存数据库（保留现有模式）
  - Repository：mock IWebDavClient 接口

Layer 3: Provider 测试 (较慢)
  - ProviderContainer + overrides
  - 验证 provider 正确组装 domain 层

Layer 4: Widget 测试 (最慢)
  - pumpWidget + ProviderScope overrides
  - 验证 UI 状态与 domain 状态一致

Layer 5: 集成测试 (跨 feature)
  - 在 test/integration/ 目录
  - 验证 state.md 第 9 节的跨功能交互
```

### state.md → 测试用例映射表

对于 state.md 中的**每个状态转移**，生成一个测试用例：

```
state.md 3.4 播放生命周期：
  T-3.4.1: idle → loading → ready (正常加载)
  T-3.4.2: idle → loading → error (加载失败)
  T-3.4.3: idle → loading → error(isAuthError) (认证失败)
  T-3.4.4: ready → PLAYING (player.play() 成功)
  T-3.4.5: PLAYING → PAUSED (用户暂停)
  T-3.4.6: PAUSED → PLAYING (用户恢复)
  T-3.4.7: PLAYING → 处理状态机 → nextIndex → loadAndPlay (自动切歌)
  T-3.4.8: PLAYING → 处理状态机 → nextIndex==null → 保持结束位置
  T-3.4.9: PLAYING → 用户 skip → loadAndPlay (手动切歌)
  T-3.4.10: 队列移除 → 空队列 → stop + 清空
  T-3.4.11: 队列移除 → 当前曲目 → 下一曲顶上
  T-3.4.12: 队列移除 → 非当前曲目 → 仅更新队列
```

每个转移都是一个独立的 domain 层测试，不依赖 Riverpod、不依赖 Flutter。

### 测试辅助工具

创建 `test/helpers/` 目录：

```
test/helpers/
  fake_audio_player.dart      # IAudioPlayer 的 fake 实现
  fake_secure_storage.dart    # ISecureStorage 的 fake 实现（消除 3 处重复）
  fake_webdav_client.dart     # IWebDavClient 的 fake 实现
  test_database.dart          # 内存 SQLite 初始化（消除 7+ 处重复）
  test_factories.dart         # _audio()、_dir() 工厂函数（消除 5+ 处重复）
  widget_helpers.dart         # 通用 widget 测试包装函数
```

---

## 分阶段执行计划

### Phase 0: 建立测试基础设施（1 天）

**目标**：创建共享测试工具，消除重复代码，为后续重构建立安全网。

1. 创建 `test/helpers/` 目录
2. 提取 `FakeSecureStorage`（从 3 个文件合并）
3. 提取 `openTestDatabase()`（从 7+ 个文件合并，支持 schema 变体）
4. 提取 `_audio()`、`_dir()` 工厂函数
5. 提取 `MockWebDavClient`（从 con_01_test.dart 提取为共享）
6. 提取 widget 测试包装函数
7. 创建 `test/helpers/mock_audio_player.dart`（替代 ply_08_test.mocks.dart 的跨 feature import）
8. **验证**：`flutter test` 全部 816 个用例通过

### Phase 1: 拆解 player_provider.dart — 提取 Domain 层（3 天）

**目标**：将 1092 行的上帝文件拆为独立的 domain 类，每个类可独立测试。

**Day 1**: 提取纯函数和简单模型
1. 创建 `lib/features/player/domain/seek_utils.dart`
   - 移入 `clampSeek`, `skipForward`, `skipBackward`（已有测试，直接迁移）
2. 创建 `lib/features/player/domain/play_mode.dart`
   - 移入 `PlayMode`, `iconForPlayMode`, `labelForPlayMode`, `nextPlayModeProvider` 逻辑
3. 创建 `lib/features/player/domain/speed_manager.dart`
   - 移入 `speedOptions`, `isValidSpeed`, `getDefaultSpeed`, `readSeekStep`
4. 创建 `lib/features/player/domain/request_gate.dart`
   - 移入 `SerializedRequestGate`, `PlayerLoadStatus`, `TrackLoadStatus`, `TrackLoadResult`
5. 创建 `lib/features/player/domain/media_control.dart`
   - 移入 `extractTitleFromPath`, `mapHeadphoneAction`
6. **验证**：现有 player 测试全部通过（这些函数已有测试覆盖）

**Day 2**: 提取播放编排器
1. 创建 `lib/features/player/domain/playback_orchestrator.dart`
   - 核心：`PlaybackOrchestrator` 类
   - 构造函数接收依赖（IAudioPlayer, IAudioHandler, IWebDavClient, ISecureStorage 等接口）
   - 方法：`loadAndPlay()`, `skipToNext()`, `skipToPrevious()`, `selectQueueIndex()`, `removeTrack()`, `saveProgress()`
   - 内部管理 `RequestGate`、自动保存定时器、processing 监听器
   - **关键**：所有依赖通过构造函数注入，不读取 Riverpod provider
2. 创建 `lib/features/player/domain/background_playback.dart`
   - 移入 `BackgroundPlaybackConfig`, `BackgroundPlaybackNotifier`, `shouldContinueInBackground`, `computePlaybackStateAfterLifecycle`
3. **验证**：为 `PlaybackOrchestrator` 编写 domain 层测试
   - mock IAudioPlayer（用 FakeAudioPlayer）
   - 验证 state.md 3.4 的每个状态转移

**Day 3**: 重写 player_provider.dart 为薄胶水
1. 新的 `player_provider.dart` 只包含：
   - `playbackOrchestratorProvider` — 创建 `PlaybackOrchestrator` 实例，注入依赖
   - 薄包装 provider：`loadAndPlayProvider` → 委托给 orchestrator
   - 状态暴露 provider：`playModeProvider`, `currentSpeedProvider` 等
2. 更新 `player_screen.dart` 使用新的 provider
3. **验证**：`flutter test` 全部通过

### Phase 2: 拆解 browser_provider.dart — 提取 Domain 层（2 天）

**Day 1**: 提取 domain 逻辑
1. 创建 `lib/features/browser/domain/directory_service.dart`
   - 移入目录加载逻辑、缓存策略、排序
   - 接收 `IWebDavClient`, `ISecureStorage` 依赖
2. 创建 `lib/features/browser/domain/navigation_stack.dart`
   - 移入 `NavigationStackNotifier`（已经是纯逻辑）
3. 创建 `lib/features/browser/domain/cache_policy.dart`
   - TTL 5 分钟、LRU 50 条目（纯函数）
4. **验证**：为 domain 层编写测试（覆盖 state.md 6.1-6.5）

**Day 2**: 重写 browser_provider.dart 为薄胶水
1. **验证**：全部 browser 测试通过

### Phase 3: Connection 模块重构（1 天）

1. 创建 `lib/features/connection/domain/connection_validator.dart`
   - 移入 URL 验证、表单校验逻辑（纯函数）
2. 创建 `lib/features/connection/domain/connection_service.dart`
   - 移入保存流程（原子性：DB + SecureStorage + 回滚）
   - 移入删除流程（最后连接保护 + 自动激活）
3. **验证**：覆盖 state.md 2.1-2.4 的每个转移

### Phase 4: 其他 Feature 提取 Domain 层（2 天）

1. **Progress** — 创建 `progress/domain/progress_policy.dart` 和 `progress_service.dart`
   - 移入 `shouldSave`, `shouldClear`（已有，从 DAO 移出）
   - 移入 5 个保存触发点的编排逻辑
2. **Playlist** — 创建 `playlist/domain/playlist_service.dart`
   - 移入 CRUD + 去重 + 导入导出逻辑
3. **Settings** — 创建 `settings/domain/settings_service.dart`
   - 移入主题、速度、步长的读写逻辑
4. **Timer** — `timer_service.dart` 已是纯逻辑，仅需移动到 `timer/domain/`
5. **验证**：每个 feature 的现有测试全部通过

### Phase 5: 接口化 + 依赖注入（2 天）

**目标**：消除跨 feature 直接 import。

1. 定义 `core/contracts/` 中的接口：
   - `IAudioPlayer` — 包装 just_audio.AudioPlayer
   - `IAudioHandler` — 包装 NasAudioHandler
   - `ISecureStorage` — 包装 FlutterSecureStorage
   - `IConnectionDao`, `IProgressDao`, `IPlaylistDao` — DAO 接口
2. 更新 Data 层实现接口
3. 创建 `shared/di/providers.dart` — 唯一的跨 feature provider 桥接
4. 更新所有 feature 的 provider 文件，只依赖接口
5. **验证**：`flutter test` 全部通过

### Phase 6: 集成测试补全（2 天）

**目标**：覆盖 test.md 中标记的所有缺口。

1. 创建 `test/integration/` 目录
2. 实现 test.md 中的集成测试：
   - INT-G01: 连接切换完整影响面
   - INT-G02: 播放进度保存与恢复端到端
   - INT-G03: Timer 到期 → Player 暂停
   - INT-G04: 播放单曲目点击完整流程
   - INT-G05: 路由完整导航流程
   - INT-G06: App 生命周期完整链路
3. 实现 state.md 第 9 节的跨功能测试
4. **验证**：所有新增测试通过

### Phase 7: 测试覆盖审计 + 补全（2 天）

1. 对 state.md 的**每个状态转移**逐条审计：
   - 有对应测试？→ 标记 ✓
   - 无对应测试？→ 补写
2. 补全 test.md 中标记的所有 P0/P1 缺口
3. **验证**：测试总数从 816 增长到 ~1200+

### Phase 8: 文档更新 + CI 加固（1 天）

1. 更新 `CLAUDE.md` 反映新架构
2. 更新 `docs/design/architecture.md`
3. 更新 `docs/design/state.md`（如有行为变更）
4. CI 增加架构边界检查（禁止跨 feature 直接 import）
5. CI 增加测试覆盖率阈值

---

## 验证方案

每个 Phase 结束后：

1. `flutter test` — 全部测试通过
2. `flutter analyze` — 无错误
3. `dart format lib test` — 格式一致
4. 手动验证：构建 APK 确认可运行

最终验证：
1. state.md 中每个状态转移都有对应测试
2. test.md 中所有标记的缺口已填补
3. 无单文件超过 500 行
4. 跨 feature import 只存在于 `shared/di/providers.dart`

---

## 风险控制

1. **每个 Phase 独立可验证** — 不依赖后续 Phase 就能运行
2. **不改行为只改结构** — Phase 1-5 是纯重构，不修改任何业务逻辑
3. **测试先行** — Phase 0 先建立测试基础设施，后续每步都有安全网
4. **可回退** — 每个 Phase 一个 git commit，出问题可回退
5. **保留 state.md** — 作为行为规格书，任何行为变更必须先更新 state.md

---

## 关键文件清单

### 需要新建的文件（~30 个）

```
lib/features/player/domain/seek_utils.dart
lib/features/player/domain/play_mode.dart
lib/features/player/domain/speed_manager.dart
lib/features/player/domain/request_gate.dart
lib/features/player/domain/media_control.dart
lib/features/player/domain/playback_orchestrator.dart
lib/features/player/domain/background_playback.dart (移自 lib/features/player/)
lib/features/browser/domain/directory_service.dart
lib/features/browser/domain/navigation_stack.dart
lib/features/browser/domain/cache_policy.dart
lib/features/connection/domain/connection_validator.dart
lib/features/connection/domain/connection_service.dart
lib/features/progress/domain/progress_policy.dart
lib/features/progress/domain/progress_service.dart
lib/features/playlist/domain/playlist_service.dart
lib/features/settings/domain/settings_service.dart
lib/core/contracts/audio_player_contract.dart
lib/core/contracts/storage_contract.dart
lib/core/contracts/audio_handler_contract.dart
lib/core/contracts/database_contract.dart
lib/shared/di/providers.dart
lib/app/router.dart
lib/app/app.dart
lib/app/onboarding.dart
test/helpers/fake_audio_player.dart
test/helpers/fake_secure_storage.dart
test/helpers/fake_webdav_client.dart
test/helpers/test_database.dart
test/helpers/test_factories.dart
test/helpers/widget_helpers.dart
test/integration/ (多个文件)
```

### 需要修改的文件（~20 个）

```
lib/features/player/player_provider.dart    # 大幅缩减为薄胶水
lib/features/player/player_screen.dart      # 更新 provider 引用
lib/features/browser/browser_provider.dart  # 大幅缩减
lib/features/browser/browser_screen.dart    # 更新引用
lib/features/connection/connection_provider.dart
lib/features/progress/progress_provider.dart
lib/features/playlist/playlist_provider.dart
lib/features/settings/settings_provider.dart
lib/features/timer/timer_provider.dart
lib/main.dart                               # 更新 provider 覆盖
lib/core/database/dao/*.dart                # 添加接口实现
lib/core/network/webdav_client.dart         # 添加接口实现
所有 test 文件                                # 更新 import 路径
```

### 需要删除的文件

```
lib/features/player/background_playback.dart  # 移入 domain/
lib/features/player/media_control_model.dart  # 移入 domain/
lib/shared/models/play_queue.dart             # 移入 player/domain/
test/features/player/ply_08_test.mocks.dart   # 替换为手写 fake
```

---

## 已发现 Bug 清单

> 基于 state.md 规格书逐模块代码审查发现。修复时间建议在 Phase 0 或 Phase 1 中完成。

### Bug 1: `_completingProvider` 卡死导致自动切歌永久失效 🔴

**模块**：Player
**文件**：`lib/features/player/player_provider.dart`
**严重性**：高 — 影响核心播放功能

**规格要求**（state.md 3.6 曲目完成自动切歌）：
处理 `ProcessingState.completed` 时，无论走哪个分支，都必须在退出前重置防重入标记。

**实际行为**：
在 processing-state 监听器中，当曲目完成且 afterCurrent 定时器未触发时，代码进入 else 分支。如果此时队列恰好为 null（`q == null`），代码直接 `return`，**没有将 `_completingProvider` 重置为 `false`**。

**代码路径**：
```
ProcessingState.completed 触发
  → _completingProvider = true (设防重入)
  → onTrackCompletedProvider() → 未触发 (非 afterCurrent)
  → 读取 currentPlayQueueProvider → q == null
  → return  ← _completingProvider 永远为 true，未重置
```

**触发条件**：
1. 正在播放一首歌
2. 用户在曲目即将播完时清空队列（或切换连接导致队列被清空）
3. 曲目完成事件到达
4. 此后所有曲目完成事件都被 `_completingProvider == true` 静默忽略

**影响**：
- 自动切歌永久失效（直到 App 重启）
- 用户无感知——没有任何错误提示

**修复方案**：
在 `if (q == null) return;` 之前添加：
```dart
ref.read(_completingProvider.notifier).state = false;
```

**测试覆盖**：当前无测试覆盖此路径。需补充测试：队列为 null 时曲目完成 → `_completingProvider` 被重置。

---

### Bug 2: 播放单"取消全选"不退出选择模式 🔴

**模块**：Playlist
**文件**：`lib/features/playlist/playlist_detail_screen.dart`
**严重性**：中 — UI 状态不一致

**规格要求**（state.md 6.2 选择模式转移表）：
"取消全选"应清空选中集并退出选择模式，恢复普通 AppBar。

**实际行为**：
"取消全选"按钮只调用 `setState(() => _selectedIds.clear())`，**没有调用 `_exitSelectionMode()`**。结果 `_selectionMode` 仍为 `true`，但 `_selectedIds` 为空。

**代码位置**：
```dart
// "取消全选"按钮的 onPressed
onPressed: () => setState(() => _selectedIds.clear()),
// 缺少: _exitSelectionMode() 调用
```

**对比**：逐个取消选中时，当 `_selectedIds` 变为空，代码正确调用了 `_exitSelectionMode()`。但"取消全选"走的是不同的代码路径，遗漏了这个调用。

**触发条件**：
1. 长按曲目进入选择模式
2. 点击"全选"
3. 点击"取消全选"
4. UI 停留在选择模式，显示"已选 0 项"

**影响**：
- AppBar 显示选择模式（返回按钮 + "已选 0 项"）
- 用户必须手动点击关闭按钮才能退出
- 不影响数据，但体验差

**修复方案**：
```dart
// 之前
onPressed: () => setState(() => _selectedIds.clear()),
// 之后
onPressed: () => _exitSelectionMode(),
```
`_exitSelectionMode()` 内部已经会清空 `_selectedIds`。

**测试覆盖**：当前无测试覆盖"取消全选"路径。需补充测试。

---

### Bug 3: 目录缓存淘汰不是 LRU 🟡

**模块**：Browser
**文件**：`lib/features/browser/browser_provider.dart`
**严重性**：低 — 正常使用差异不大

**规格要求**（state.md 2.1 缓存策略）：
缓存容量最多 50 条目，超出时 **LRU 淘汰**（最近最少使用的先淘汰）。

**实际行为**：
淘汰逻辑按 Map 的插入顺序移除最旧条目，不是按最近使用时间。重新访问一个旧目录不会把它"提到"淘汰队列末尾。

**代码位置**：
```dart
if (updated.length > 50) {
  final keysToRemove = updated.keys.take(updated.length - 50);
  for (final key in keysToRemove) {
    updated.remove(key);
  }
}
```
`Map.keys` 的迭代顺序是插入顺序，不是访问顺序。

**触发条件**：
1. 浏览超过 50 个不同目录
2. 回到最早访问的目录（期望它被保留）
3. 该目录的缓存被淘汰（因为它在 Map 中最靠前）

**影响**：
- 用户在深层目录间反复切换时，常用目录的缓存可能被淘汰
- 每次淘汰后需要重新 PROPFIND 请求

**修复方案**：
在 `CacheEntry` 中添加 `lastAccessedAt` 字段，缓存命中时更新。淘汰时按 `lastAccessedAt` 排序，移除最久未访问的条目。

**测试覆盖**：当前有缓存测试但未覆盖 LRU 行为。需补充测试：50 条缓存 → 访问旧条目 → 淘汰时保留该条目。

---

### Bug 4: 播放单曲目排序缺少防御检查 🟡

**模块**：Playlist
**文件**：`lib/features/playlist/playlist_provider.dart`
**严重性**：低 — 当前用户不会触发（UI 已阻止）

**规格要求**（state.md 6.3 CRUD 转移表）：
曲目拖拽排序仅在排序方式为 `addedAsc` 时可用。

**实际行为**：
`reorderPlaylistTrackProvider` 没有检查当前排序模式，直接调用 `dao.reorderTrack`。排序模式的检查仅在 UI 层（`ReorderableListView` 仅在 `addedAsc` 时渲染）。

**代码位置**：
```dart
final reorderPlaylistTrackProvider = Provider<void Function(int, int)>((ref) {
  return (oldIndex, newIndex) {
    // 缺少: if (ref.read(trackSortProvider) != TrackSortOption.addedAsc) return;
    final playlistId = ref.read(_selectedPlaylistIdProvider);
    if (playlistId == null) return;
    ref.read(playlistDaoProvider).reorderTrack(playlistId, oldIndex, newIndex);
    ref.invalidate(playlistTracksProvider(playlistId));
  };
});
```

**触发条件**：
- 当前 UI 不会触发（已阻止）
- 但通过代码、测试或未来重构直接调用 Provider 时可能触发

**影响**：
- 在非 `addedAsc` 排序下调用 reorder 会破坏 `added_at` 时间戳数据
- 排序结果变得无意义

**修复方案**：
在 Provider 中添加防御检查：
```dart
if (ref.read(trackSortProvider) != TrackSortOption.addedAsc) return;
```

**测试覆盖**：需补充测试：非 addedAsc 排序下调用 reorder → 应被忽略。

---

### 规格不一致: 静态 shuffle 方法使用 Random ⚪

**模块**：Player / PlayQueue
**文件**：`lib/shared/models/play_queue.dart`
**严重性**：无运行时影响（死代码）

**规格要求**（state.md 3.3 播放模式）：
shuffle 模式应使用确定性排列（Fisher-Yates），支持前进/后退。

**实际行为**：
`PlayQueue` 有两套 shuffle 机制：
1. **实例方法**（确定性）：`advanceShuffle()` / `retreatShuffle()` 使用 Fisher-Yates 排列
2. **静态方法**（非确定性）：`nextIndex()` / `previousIndex()` 在 shuffle 模式下使用 `Random()` 随机选索引

运行时代码全部使用实例方法，静态方法的 shuffle 分支是死代码。

**影响**：
- 无运行时影响
- 但静态方法可能误导后续开发者直接调用 `PlayQueue.nextIndex(..., PlayMode.shuffle)`

**修复建议**：
在重构时统一为一套 shuffle 机制。可选方案：
- A: 静态方法的 shuffle 分支抛出 `UnsupportedError`，提示使用实例方法
- B: 静态方法也使用确定性排列（需要传入 shuffle state）
- C: 移除静态方法的 shuffle 分支

---

## 深度审查清单

> 除了上述已发现的 Bug 之外，以下维度需要系统性审查，确保功能真正完善。
> 每个维度独立可执行，建议在 Phase 7（测试覆盖审计）中完成。

### 维度 1: 测试覆盖映射 — 每个转移都有测试吗？

state.md 定义了所有状态转移，但"有规格"不等于"有测试"。需要逐条审计每个转移是否有对应测试用例。

**审计方法**：
对 state.md 中的每个转移，检查是否存在至少一个测试用例覆盖该路径。格式：

```
模块-编号: 转移描述 → 测试文件:测试用例名 | 状态
```

**Connection 模块映射表**：

| 转移 | 测试 | 状态 |
|------|------|------|
| Idle → validate() → Loading | con_01: CON-T01~T09 | ✅ |
| Loading → 成功 → Success | con_02: CON-T11~T14 | ✅ |
| Loading → 失败 → Error | con_02: CON-T15~T17 | ✅ |
| Loading → 重入防重入 | con_02: CON-T18 | ✅ |
| Success → reset() → Idle | con_01: 隐式覆盖 | ✅ |
| 字段变更 → reset → Idle | con_01: CON-T04 | ✅ |
| Success → 保存成功 → 导航 | con_01: CON-T35~T41 | ✅ |
| 保存失败 → SecureStorage 回滚 | — | ❌ 缺测试 |
| 编辑：凭证变更需重验证 | con_05: CON-T28~T30 | ✅ |
| 编辑：仅名称可直接保存 | con_05: CON-T31 | ✅ |
| 列表：切换连接 | con_04, con_09 | ✅ |
| 列表：删除最后连接被阻止 | con_06: CON-FIX-T07~T08 | ✅ |
| 列表：删除活跃连接自动激活 | con_06: CON-T34 | ✅ |
| 启动：无连接 → CTA | con_01: CON-T41 | ✅ |
| 启动：有连接+验证成功 → browser | — | ❌ 缺测试 |
| 启动：有连接+验证失败 → connection | — | ❌ 缺测试 |
| 启动：DB 错误 → 重试 | — | ❌ 缺测试 |

**Browser 模块映射表**：

| 转移 | 测试 | 状态 |
|------|------|------|
| Loading → Data | brw_01: BRW-T01~T03 | ✅ |
| Loading → Empty | brw_01: BRW-T04 | ✅ |
| Loading → Error | brw_01: BRW-T05~T06 | ✅ |
| Error → 重试 → Loading | brw_01: BRW-T46 | ✅ |
| Data → 下拉刷新 → Loading | brw_06 | ✅ |
| 排序变化 → Data(重排序) | brw_07 | ✅ |
| 缓存命中(无网络请求) | brw_05 | ✅ |
| 缓存 TTL 过期 → 重新请求 | — | ❌ 缺测试 |
| 缓存 LRU 淘汰 | — | ❌ 缺测试（且实现有 Bug 3） |
| 导航：push/pop/popTo | brw_02 | ✅ |
| 导航：根目录 pop 无效 | brw_02 | ✅ |
| 点击文件 → 构建队列 → 导航 | brw_04 | ✅ |
| 点击文件 → 有进度 → 恢复对话框 | brw_04 | ✅ |
| 长按文件 → 清除进度 | — | ❌ 缺测试 |
| 连接切换 → 清空队列 | con_09 | ✅ |
| 队列持久化 → 重启恢复 | — | ❌ 缺测试 |

**Player 模块映射表**：

| 转移 | 测试 | 状态 |
|------|------|------|
| idle → loading → ready | ply_02 | ✅ |
| idle → loading → error | ply_02 | ✅ |
| idle → loading → error(isAuth) | ply_02 | ✅ |
| loading → 超时 → error | — | ❌ 缺测试 |
| loading → 被取代 → superseded | ply_05: SerializedRequestGate | ✅ |
| error → 重试 → loading | ply_02: 隐式覆盖 | ✅ |
| ready → 队列清空 → 弹出页面 | — | ❌ 缺测试 |
| completed → afterCurrent → pause | ply_05: TST-01 | ✅ |
| completed → nextIndex → loadAndPlay | ply_05: TST-01 | ✅ |
| completed → nextIndex==null → 保持 | ply_05: TST-01 | ✅ |
| completed → q==null → Bug 1 | — | ❌ 缺测试（Bug 1） |
| skipToNext → 保存进度 → 更新队列 | ply_05 | ✅ |
| skipToPrevious → 保存进度 → 更新队列 | ply_05 | ✅ |
| selectQueueIndex → 跳转 | ply_05 | ✅ |
| removeTrack → 空队列 → stop | ply_05: PLY-T35 | ✅ |
| removeTrack → 当前曲目 → 下一曲 | ply_05: PLY-T36 | ✅ |
| removeTrack → 非当前曲目 | ply_05: PLY-T37 | ✅ |
| 后台播放：生命周期转换 | ply_03 | ✅ |
| 后台播放：音频焦点 | ply_03 | ✅ |
| 通知栏控件：play/pause/stop | ply_03 | ✅ |
| 通知栏控件：skip | ply_04 | ✅ |
| 播放模式循环 | ply_06 | ✅ |
| 速度持久化 | ply_07 | ✅ |
| 迷你播放栏可见性 | ply_08 | ✅ |
| 迷你播放栏 completed→seek+play | ply_08 | ✅ |
| 队列弹窗：点击跳转 | ply_08 | ✅ |
| 队列弹窗：移除曲目 | ply_08 | ✅ |

**Timer 模块映射表**：

| 转移 | 测试 | 状态 |
|------|------|------|
| null → startDuration → duration | timer_test: TMR-T01~T03 | ✅ |
| null → startAfterCurrent → afterCurrent | timer_test: TMR-T08 | ✅ |
| duration → startDuration → 替换 | timer_test: TMR-T04 | ✅ |
| duration → startAfterCurrent → 替换 | timer_test: TMR-T12 | ✅ |
| duration → pause → paused | timer_test: TMR-T15 | ✅ |
| paused → resume → duration | timer_test: TMR-T16 | ✅ |
| duration → checkExpired → null | timer_test: TMR-T13 | ✅ |
| afterCurrent → onTrackCompleted → null | timer_test: TMR-T09 | ✅ |
| afterCurrent → checkExpired → 无效 | timer_test: TMR-T14 | ✅ |
| 任意 → cancel → null | timer_test: TMR-T10~T11 | ✅ |
| pause 对 afterCurrent 无效 | timer_test: TMR-T17 | ✅ |
| resume 对非 paused 无效 | timer_test: TMR-T18 | ✅ |
| startDuration(负数) → 抛异常 | timer_test: TMR-T19 | ✅ |
| 定时到期 → player.pause() | — | ❌ 缺集成测试 |
| 播完当前 → player.pause() | — | ❌ 缺集成测试 |
| App 恢复 → 立即检查到期 | — | ❌ 缺测试 |

**Progress 模块映射表**：

| 转移 | 测试 | 状态 |
|------|------|------|
| NoRecord → upsert(<5s) → 跳过 | prg_test: PRG-T03 | ✅ |
| NoRecord → upsert(≥5s) → INSERT | prg_test: PRG-T01 | ✅ |
| Saved → upsert(≥5s) → UPSERT | prg_test: PRG-T02 | ✅ |
| Saved → upsert(>dur-10s) → DELETE | prg_test: PRG-T04 | ✅ |
| Saved → delete → NoRecord | prg_test: PRG-T24~T28 | ✅ |
| 短文件不自动清理(dur≤10s) | prg_test: PRG-T05 | ✅ |
| 未知时长不自动清理(dur==null) | prg_test: PRG-T06 | ✅ |
| 恢复对话框：5s 倒计时 | prg_test: PRG-T17~T23 | ✅ |
| 恢复对话框：点击继续 | prg_test: PRG-T17 | ✅ |
| 恢复对话框：点击从头 | prg_test: PRG-T18 | ✅ |
| 恢复对话框：倒计时归零自动继续 | prg_test: PRG-T20 | ✅ |
| 5 个保存触发点集成 | — | ❌ 缺集成测试 |

**Playlist 模块映射表**：

| 转移 | 测试 | 状态 |
|------|------|------|
| 创建播放单 | ply_10, ply_12 | ✅ |
| 删除播放单(CASCADE) | ply_10, ply_12 | ✅ |
| 重命名播放单 | — | ❌ 缺测试 |
| 添加曲目(去重) | ply_10, ply_11 | ✅ |
| 删除曲目 | ply_10, ply_13 | ✅ |
| 拖拽排序 | — | ❌ 缺测试 |
| 选择模式：长按进入 | ply_13 | ✅ |
| 选择模式：点击选中/取消 | ply_13 | ✅ |
| 选择模式：全选 | ply_13 | ✅ |
| 选择模式：取消全选 | — | ❌ 缺测试（且有 Bug 2） |
| 选择模式：删除选中 | ply_13 | ✅ |
| 点击曲目 → 有进度 → 恢复对话框 | ply_13 | ✅ |
| 点击曲目 → 构建队列 → 导航 | ply_13 | ✅ |
| 导入导出 | — | ❌ 缺测试 |
| Tab 索引持久化 | — | ❌ 缺测试 |

**汇总**：

| 模块 | 有测试 | 缺测试 | 覆盖率 |
|------|--------|--------|--------|
| Connection | 15 | 3 | 83% |
| Browser | 11 | 4 | 73% |
| Player | 22 | 3 | 88% |
| Timer | 13 | 3 | 81% |
| Progress | 10 | 1 | 91% |
| Playlist | 10 | 5 | 67% |
| **总计** | **81** | **19** | **81%** |

---

### 维度 2: 边界值覆盖 — 关键阈值都有测试吗？

规格书中有多个数值边界，每个边界需要"恰好在边界上"和"恰好越过边界"两个测试。

**Progress 边界**：

| 边界 | 条件 | 测试状态 |
|------|------|---------|
| positionMs = 4999 | shouldSave → false | ✅ 有测试 |
| positionMs = 5000 | shouldSave → true | ✅ 有测试 |
| positionMs = durationMs - 10001 | shouldClear → false | ✅ 有测试 |
| positionMs = durationMs - 10000 | shouldClear → false | ✅ 有测试 |
| positionMs = durationMs - 9999 | shouldClear → true | ✅ 有测试 |
| durationMs = 10000 | shouldClear → false（短文件保护） | ✅ 有测试 |
| durationMs = 10001 | shouldClear → true | ✅ 有测试 |
| durationMs = null | shouldClear → false | ✅ 有测试 |

**Browser 缓存边界**：

| 边界 | 条件 | 测试状态 |
|------|------|---------|
| 缓存 age = 4:59 | 命中 | ❌ 缺测试 |
| 缓存 age = 5:00 | 过期 | ❌ 缺测试 |
| 缓存条目 = 49 | 不淘汰 | ❌ 缺测试 |
| 缓存条目 = 50 | 不淘汰 | ❌ 缺测试 |
| 缓存条目 = 51 | 淘汰 1 条 | ❌ 缺测试 |

**Player 超时边界**：

| 边界 | 条件 | 测试状态 |
|------|------|---------|
| play() 轮询 11.8s 成功 | 返回 loaded | ❌ 缺测试 |
| play() 轮询 12.0s 未开始 | 返回 failed | ❌ 缺测试 |
| 屏幕超时 14.9s 完成 | 返回 loaded | ❌ 缺测试 |
| 屏幕超时 15.0s 未完成 | TimeoutException | ❌ 缺测试 |

**Timer 边界**：

| 边界 | 条件 | 测试状态 |
|------|------|---------|
| startDuration(0) | 立即过期 | ❌ 缺测试 |
| startDuration(-1) | 抛出 ArgumentError | ✅ 有测试 |
| remainingMs = 1ms | resume 后约 1 分钟 | ❌ 缺测试 |

**自动保存边界**：

| 边界 | 条件 | 测试状态 |
|------|------|---------|
| 自动保存间隔 = 10s | 周期性保存 | ❌ 缺测试（纯逻辑层） |
| 暂停检测：playing→paused | 保存一次 | ❌ 缺测试（纯逻辑层） |

---

### 维度 3: 错误注入 — 错误路径真的能恢复吗？

"代码能处理错误"和"用户能从错误中恢复"是两回事。需要验证每个错误路径的可恢复性。

**Connection 错误注入**：

| 场景 | 代码处理 | 用户可恢复？ | 测试状态 |
|------|---------|------------|---------|
| SecureStorage 写入失败 | ✅ 回滚 DB 行 | ✓ 重试即可 | ❌ 缺测试 |
| DB 写入失败 | ✅ 抛异常 + SnackBar | ✓ 重试即可 | ❌ 缺测试 |
| 验证时网络超时 | ✅ 返回 Error 状态 | ✓ 重试即可 | ✅ 有测试 |
| 验证时 401 | ✅ 返回 Error 状态 | ✓ 修改凭证重试 | ✅ 有测试 |

**Player 错误注入**：

| 场景 | 代码处理 | 用户可恢复？ | 测试状态 |
|------|---------|------------|---------|
| setAudioSource 失败 | ✅ 返回 failed | ✓ 重试按钮 | ❌ 缺测试 |
| play() 超时 | ✅ stop + 返回 failed | ✓ 重试按钮 | ❌ 缺测试 |
| 曲目完成时队列 null | ❌ Bug 1：卡死 | ✗ 需重启 | ❌ 缺测试 |
| 播放中连接断开 | ？ 需验证 | ？ | ❌ 缺测试 |
| 播放中密码被清除 | ？ 需验证 | ？ | ❌ 缺测试 |
| 音频焦点永久丢失 | ✅ pause | ✓ 手动恢复 | ✅ 有测试 |

**Browser 错误注入**：

| 场景 | 代码处理 | 用户可恢复？ | 测试状态 |
|------|---------|------------|---------|
| PROPFIND 网络错误 | ✅ Error 状态 + 重试 | ✓ | ✅ 有测试 |
| PROPFIND 返回空目录 | ✅ Empty 状态 | ✓ 导航返回 | ✅ 有测试 |
| 密码缺失 | ✅ 抛异常 → Error | ✓ 添加密码重试 | ❌ 缺测试 |
| 活跃连接被删除 | ✅ 连接切换清空队列 | ✓ 选择新连接 | ✅ 有测试 |

**Progress 错误注入**：

| 场景 | 代码处理 | 用户可恢复？ | 测试状态 |
|------|---------|------------|---------|
| upsert 时 DB 锁定 | ？ 需验证 | ？ | ❌ 缺测试 |
| 恢复对话框期间页面销毁 | ？ 需验证 | ？ | ❌ 缺测试 |

---

### 维度 4: 并发事件时序 — 竞态条件

这是最难测试但最容易出 bug 的领域。以下是需要覆盖的关键并发场景。

**Player 并发场景**：

| 场景 | 风险 | 当前覆盖 | 优先级 |
|------|------|---------|--------|
| 快速连续 skip → 多个 loadAndPlay | SerializedRequestGate 处理 | ✅ 有测试 | — |
| 播放中切换连接 → 队列清空 + 正在加载 | 时序竞争：loadAndPlay 读到旧连接 | ❌ 缺测试 | P0 |
| 播放中删除当前曲目 + 同时曲目完成 | 双重触发：removeTrack + completed | ❌ 缺测试 | P0 |
| 用户快速进出 PlayerScreen | listener 注册/取消竞争 | ❌ 缺测试 | P1 |
| dispose 时 loadAndPlay 还在飞 | token 检查应丢弃结果 | ❌ 缺测试 | P1 |
| MiniPlayerBar 的 play + PlayerScreen 的 loadAndPlay 同时触发 | 两个 loadAndPlay 并发 | ❌ 缺测试 | P1 |

**Timer 并发场景**：

| 场景 | 风险 | 当前覆盖 | 优先级 |
|------|------|---------|--------|
| 定时到期 + 曲目完成同时到达 | 双重 pause | ❌ 缺测试 | P1 |
| App 后台恢复 + 定时器到期 + 播放恢复 | 三重事件同时到达 | ❌ 缺测试 | P1 |
| 用户快速切换定时模式 | replace 语义是否正确 | ❌ 缺测试 | P2 |

**Browser 并发场景**：

| 场景 | 风险 | 当前覆盖 | 优先级 |
|------|------|---------|--------|
| 切换连接 + 目录加载中 | 旧连接的结果写入新连接的缓存 | ❌ 缺测试 | P1 |
| 快速 push/pop 目录 | 旧请求结果覆盖新目录内容 | ❌ 缺测试 | P2 |
| 下拉刷新 + 排序变化同时触发 | 缓存清除 + 重排序竞争 | ❌ 缺测试 | P2 |

**Connection 并发场景**：

| 场景 | 风险 | 当前覆盖 | 优先级 |
|------|------|---------|--------|
| 保存中用户修改字段 | _isSaving 锁应阻止 | ✅ UI 已禁用 | — |
| 验证中用户修改字段 | reset 应取消旧验证 | ❌ 缺测试 | P2 |

---

### 维度 5: 状态可达性 — 有没有死状态？

检查规格书中的每个状态是否真的能被到达，以及是否有不可达的代码路径。

**Player 状态可达性**：

| 状态 | 可达？ | 到达路径 |
|------|--------|---------|
| PlayerLoadState.idle | ✓ | PlayerScreen 初始化 |
| PlayerLoadState.loading | ✓ | initState → _loadAndPlay |
| PlayerLoadState.ready | ✓ | loadAndPlay 成功 |
| PlayerLoadState.error | ✓ | loadAndPlay 失败 |
| PlayerLoadState.error(isAuth) | ✓ | 无连接/无密码 |
| TrackLoadResult.loaded | ✓ | 正常加载成功 |
| TrackLoadResult.failed | ✓ | 各种失败路径 |
| TrackLoadResult.superseded | ？ | 需要两个并发 loadAndPlay，第一个被取代。可达但难以在正常使用中触发 |

**Timer 状态可达性**：

| 状态 | 可达？ | 到达路径 |
|------|--------|---------|
| null (inactive) | ✓ | 初始状态 / cancel / 过期 |
| duration | ✓ | startDuration |
| paused | ✓ | duration → pause |
| afterCurrent | ✓ | startAfterCurrent |

**Progress 状态可达性**：

| 状态 | 可达？ | 到达路径 |
|------|--------|---------|
| NoRecord | ✓ | 初始状态 / delete / 清除 |
| Saved | ✓ | upsert(≥5s) |
| Skipped | ✓ | upsert(<5s) — 但这是隐式状态，不持久化 |
| Cleared | ✓ | upsert(>dur-10s) — 但这是瞬态，记录已删除 |

**Browser 状态可达性**：

| 状态 | 可达？ | 到达路径 |
|------|--------|---------|
| Loading | ✓ | 导航到新目录 / 刷新 |
| Error | ✓ | 网络错误 / 无连接 / 无密码 |
| Empty | ✓ | 目录为空 |
| Data | ✓ | 正常加载 |
| AtRoot | ✓ | 初始状态 / popTo('/') |
| Nested | ✓ | push 子目录 |
| CacheMiss | ✓ | 首次访问 / TTL 过期 |
| CacheHit | ✓ | 5 分钟内重复访问 |

**Playlist 状态可达性**：

| 状态 | 可达？ | 到达路径 |
|------|--------|---------|
| Loading | ✓ | 初始加载 |
| Error | ✓ | DB 错误 |
| Empty | ✓ | 无播放单 |
| Data | ✓ | 有播放单 |
| Normal | ✓ | 初始状态 |
| Selecting | ✓ | 长按曲目 |
| SelectingEmpty | ✓ | Bug 2 路径 — 不应存在 |

---

### 审查执行计划

以上五个维度建议在 Phase 7（测试覆盖审计 + 补全）中系统性完成：

1. **维度 1（测试覆盖映射）**：生成完整映射表，标记所有缺测试的转移
2. **维度 2（边界值）**：为每个未覆盖的边界补充测试
3. **维度 3（错误注入）**：为每个未验证的错误路径补充测试
4. **维度 4（并发时序）**：为 P0/P1 并发场景补充测试
5. **维度 5（状态可达性）**：确认无死状态，移除不可达代码

**预期成果**：测试总数从 816 增长到 ~1200+，覆盖率从 81% 提升到 95%+。

---

## 当前进度

- [ ] Phase 0: 建立测试基础设施
- [ ] Phase 1: 拆解 player_provider.dart — 提取 Domain 层
- [ ] Phase 2: 拆解 browser_provider.dart — 提取 Domain 层
- [ ] Phase 3: Connection 模块重构
- [ ] Phase 4: 其他 Feature 提取 Domain 层
- [ ] Phase 5: 接口化 + 依赖注入
- [ ] Phase 6: 集成测试补全
- [ ] Phase 7: 测试覆盖审计 + 补全
- [ ] Phase 8: 文档更新 + CI 加固
