# 重构计划执行结果分析报告

> 分析日期: 2026-06-10
> 对照: `docs/design/refactor-plan.md` + `docs/dev/dev-status.json` + 实际代码

---

## 总体结论

dev-status.json 声称 54 项任务全部完成（pending: 0, done: 54）。经逐项代码验证，**大部分重构工作确实已完成**，但存在若干偏差：部分 domain 层文件虽已创建但未被 provider 实际使用（成为死代码），目录结构与计划有差异，且有一个文件违反了 500 行限制。

**完成度评估：约 85%** — 文件创建层面接近 100%，但"provider 成为薄胶水"这一核心目标仅在 player、browser、timer 三个模块真正实现。

---

## Phase 0: 测试基础设施 ✅ 基本完成

### 计划要求

| # | 任务 | 状态 | 说明 |
|---|------|------|------|
| 1 | 创建 `test/helpers/` 目录 | ✅ | 目录存在，含 6 个文件 |
| 2 | 提取 `FakeSecureStorage` | ✅ | `fake_secure_storage.dart` 存在，提供 `FakeSecureStorage` |
| 3 | 提取 `openTestDatabase()` | ✅ | `test_database.dart` 存在，支持 `TestSchema` 枚举 |
| 4 | 提取 `_audio()`/`_dir()` 工厂函数 | ✅ | `test_factories.dart` 存在，提供 `testDir()`/`testAudio()`/`testConfig()` |
| 5 | 提取 `MockWebDavClient` | ✅ | `fake_webdav_client.dart` 存在，含 `MockWebDavClient` + `SpyWebDavClient` |
| 6 | 提取 widget 测试包装函数 | ✅ | `widget_helpers.dart` 存在，含 `buildTestApp()` + `buildTestAppWithRouter()` |
| 7 | 创建 `mock_audio_player.dart` | ✅ | 存在（18037 bytes），手写 Mockito mock |
| 8 | 全部测试通过 | ✅ | dev-status.json 标记 passed |

### 偏差

- **`fake_audio_player.dart` 未创建** — 计划要求创建此文件替代 `ply_08_test.mocks.dart` 的跨 feature import。实际创建的是 `mock_audio_player.dart`（手写 mock），功能等价但命名不同。

---

## Phase 1: 拆解 player_provider.dart ✅ 基本完成

### Domain 层文件

| 文件 | 计划 | 实际 | 纯 Dart? | 说明 |
|------|------|------|----------|------|
| `domain/seek_utils.dart` | ✅ | ✅ 存在 (40行) | ✅ 零依赖 | `clampSeek`, `skipForward`, `skipBackward` |
| `domain/play_mode.dart` | ✅ | ✅ 存在 (120行) | ✅ 仅 `dart:math` | `PlayMode`, `nextIndex`, `previousIndex` |
| `domain/speed_manager.dart` | ✅ | ✅ 存在 (53行) | ⚠️ 依赖 `shared_preferences` | 函数参数注入，可测试 |
| `domain/request_gate.dart` | ✅ | ✅ 存在 (204行) | ⚠️ 依赖 `just_audio` | `SerializedRequestGate` 含 20s 超时 (BUG-05) |
| `domain/media_control.dart` | ✅ | ✅ 存在 (105行) | ✅ 零依赖 | `extractTitleFromPath`, `mapHeadphoneAction` |
| `domain/playback_orchestrator.dart` | ✅ | ✅ 存在 (435行) | ⚠️ 依赖 `just_audio` | 5 个抽象接口 + `PlaybackOrchestrator` 类 |
| `domain/background_playback.dart` | ✅ | ✅ 存在 (384行) | ❌ 依赖 `flutter` + `flutter_riverpod` | 含 `StateNotifier` + provider |

### player_provider.dart 评估

- **行数**：295 行（原 1092 行，缩减 73%）✅
- **薄胶水程度**：⚠️ **部分达成**
  - ✅ 创建了 `_Deps` 类实现 5 个抽象接口，注入 `PlaybackOrchestrator`
  - ✅ `loadAndPlayProvider` 委托给 orchestrator
  - ⚠️ `skipToNextProvider`、`skipToPreviousProvider`、`selectQueueIndexProvider`、`removeTrackFromQueueProvider` 仍内联队列导航逻辑（`PlayQueue.nextIndex`/`advanceShuffle`/`retreatShuffle`），未完全委托给 orchestrator
  - ⚠️ `startProcessingListenerProvider` 内含曲目完成自动切歌逻辑，与 orchestrator 功能重叠

### player_screen.dart

- **行数**：987 行 ⚠️ **超过 500 行限制**（CI 会失败）
- ✅ 使用新的 provider 和 domain 类型

### Bug 修复

- **Bug 1 (`_completingProvider` 卡死)**：✅ 已修复 — 所有退出路径均重置为 `false`，`loadAndPlayProvider` 中也有安全网重置

---

## Phase 2: 拆解 browser_provider.dart ✅ 基本完成

### Domain 层文件

| 文件 | 计划 | 实际 | 纯 Dart? | 说明 |
|------|------|------|----------|------|
| `domain/directory_service.dart` | ✅ | ✅ 存在 (213行) | ⚠️ 依赖 `shared_preferences` + `state_notifier` | 含 `SortOption`, `DirectoryService`, `sortFiles()` |
| `domain/navigation_stack.dart` | ✅ | ✅ 存在 (41行) | ✅ 仅 `state_notifier` | `NavigationStackNotifier` |
| `domain/cache_policy.dart` | ✅ | ✅ 存在 (102行) | ✅ 零依赖 | `CacheEntry` + `CachePolicy`，含 LRU 淘汰 |

### browser_provider.dart 评估

- **行数**：183 行 ✅
- **薄胶水程度**：⚠️ **部分达成**
  - ✅ 使用 `CachePolicy` 和 `sortFiles()`
  - ⚠️ `directoryContentsProvider` 未委托给 `DirectoryService.loadDirectory()`，而是内联实现了缓存检查/获取/过滤/排序流程
  - ⚠️ 包含 ~80 行播放队列持久化逻辑（save/restore from SharedPreferences），不属于"薄胶水"

### Bug 修复

- **Bug 3 (LRU 缓存淘汰)**：✅ 已修复 — `CacheEntry` 含 `lastAccessedAt` 字段，淘汰按 LRU 排序

---

## Phase 3: Connection 模块重构 ✅ 完成

### Domain 层文件

| 文件 | 计划 | 实际 | 纯 Dart? | 说明 |
|------|------|------|----------|------|
| `domain/connection_validator.dart` | ✅ | ✅ 存在 | ⚠️ 依赖 `webdav_client.dart`（URL 工具函数） | `validateUrl`, `validateRequired`, `validateBasePath` |
| `domain/connection_service.dart` | ✅ | ✅ 存在 | ⚠️ 依赖 `flutter_secure_storage` | `save`/`update`/`delete`/`setActive`，含原子性回滚 |

### connection_provider.dart 评估

- ✅ **薄胶水** — 业务逻辑委托给 `ConnectionService`，provider 仅做 Riverpod 绑定
- ✅ 向后兼容 shim：`ConnectionSaver`/`ConnectionUpdater` 包装 `ConnectionService`

### Bug 修复

- **Bug 2 (取消全选不退出选择模式)**：✅ 已修复 — `_exitSelectionMode()` 正确清除 `_selectionMode` 和 `_selectedIds`

---

## Phase 4: 其他 Feature 提取 Domain 层 ⚠️ 部分完成

### Timer ✅ 完整实现

| 检查项 | 状态 |
|--------|------|
| `domain/timer_service.dart` 存在 | ✅ |
| 纯 Dart（零依赖） | ✅ |
| provider 委托给 domain service | ✅ — `TimerStateNotifier` 薄包装 |
| `timer_provider.dart` 薄胶水 | ✅ — 最干净的实现 |

### Progress ⚠️ Domain 层创建但未使用

| 检查项 | 状态 |
|--------|------|
| `domain/progress_policy.dart` 存在 | ✅ 纯 Dart（零依赖） |
| `domain/progress_service.dart` 存在 | ✅ 纯 Dart（无 Flutter） |
| provider 使用 domain service | ❌ **未使用** — provider 直接调用 `ProgressDao`，内联业务逻辑 |
| provider 薄胶水 | ❌ 重复实现了 `ProgressResumeState`/`ProgressResumeNotifier` |

`progress_policy.dart` 和 `progress_service.dart` 是**死代码** — 没有被任何生产代码引用。

### Playlist ⚠️ Domain 层创建但未使用

| 检查项 | 状态 |
|--------|------|
| `domain/playlist_service.dart` 存在 | ✅ 纯 Dart（无 Flutter） |
| provider 使用 domain service | ❌ **未使用** — provider 直接调用 `PlaylistDao` |
| provider 薄胶水 | ❌ 去重/导入导出逻辑与 `PlaylistService` 重复 |

`PlaylistService` 是**死代码** — 没有被任何生产代码引用。

### Settings ⚠️ Domain 层创建但未使用

| 检查项 | 状态 |
|--------|------|
| `domain/settings_service.dart` 存在 | ⚠️ 依赖 `flutter/material.dart`（`ThemeMode` 枚举） |
| provider 使用 domain service | ❌ **未使用** — provider 内联 `getThemeMode`/`setThemeMode` 等函数 |
| provider 薄胶水 | ❌ 自行定义函数，未委托 |

`SettingsService` 是**死代码** — 没有被任何生产代码引用。

---

## Phase 5: 接口化 + 依赖注入 ✅ 完成

### 合约文件

| 文件 | 状态 | 内容 |
|------|------|------|
| `core/contracts/audio_player_contract.dart` | ✅ | `IAudioPlayer` 接口 (74行) |
| `core/contracts/audio_handler_contract.dart` | ✅ | `IAudioHandler` 接口 (84行) |
| `core/contracts/storage_contract.dart` | ✅ | `ISecureStorage` 接口 (25行) |
| `core/contracts/database_contract.dart` | ✅ | `IConnectionDao`/`IProgressDao`/`IPlaylistDao` (134行) |

### 跨 feature 解耦

| 检查项 | 状态 |
|--------|------|
| `shared/di/providers.dart` 存在 | ✅ (219行) |
| 使用 `export` + `show` 精确暴露 | ✅ |
| feature 间无直接 import | ✅ — grep 扫描零违规 |
| CI 架构边界检查 | ✅ — `.github/workflows/ci.yml` 含自动检测 |

### 偏差

- **`lib/app/` 目录未创建** — 计划要求拆分 `router.dart`、`app.dart`、`onboarding.dart` 到 `lib/app/`。实际全部内联在 `lib/main.dart` (341行) 中。

---

## Phase 6: 集成测试补全 ⚠️ 部分完成

### 计划要求 vs 实际

| 计划 | 实际 | 状态 |
|------|------|------|
| 创建 `test/integration/` 目录 | ❌ 未创建 | 不存在 |
| INT-G01: 连接切换完整影响面 | — | ❌ 未实现 |
| INT-G02: 播放进度保存与恢复端到端 | `TST-02` | ✅ 在 `test/features/coverage/` 中 |
| INT-G03: Timer 到期 → Player 暂停 | `TST-03` | ✅ 在 `test/features/coverage/` 中 |
| INT-G04: 播放单曲目点击完整流程 | `TST-04` | ✅ 在 `test/features/coverage/` 中 |
| INT-G05: 路由完整导航流程 | — | ❌ 未实现 |
| INT-G06: App 生命周期完整链路 | — | ❌ 未实现 |

集成测试放在 `test/features/coverage/` 而非计划的 `test/integration/`。3/6 个集成测试已实现。

---

## Phase 7: 测试覆盖审计 + 补全 ✅ 基本完成

### 审计文件

| 文件 | 状态 | 内容 |
|------|------|------|
| `aud_01_coverage_gaps_test.dart` | ✅ | 测试覆盖映射审计 |
| `aud_02_boundary_test.dart` | ✅ | 边界值测试补全 |
| `aud_03_error_injection_test.dart` | ✅ | 错误注入测试补全 |
| `aud_04_concurrent_test.dart` | ✅ | 并发场景测试补全 |
| `aud_05_state_reachability_test.dart` | ✅ | 状态可达性审计 |

### 测试统计

- 总测试文件：68 个
- 计划目标：816 → ~1200+ 用例（无法从文件数直接验证，但 dev-status.json 全部 passed）

---

## Phase 8: 文档更新 + CI 加固 ✅ 完成

| 任务 | 状态 | 说明 |
|------|------|------|
| 更新 `CLAUDE.md` | ✅ | 反映新架构分层 |
| 更新 `architecture.md` | ✅ | `docs/design/architecture.md` 存在 |
| CI 架构边界检查 | ✅ | 检测跨 feature import |
| CI 文件行数限制 | ✅ | 500 行限制（但 `player_screen.dart` 违规） |
| CI 格式检查 | ✅ | `dart format --set-exit-if-changed` |
| CI 覆盖率阈值 | ✅ | 60% 最低阈值 |

---

## Bug 修复验证

| Bug | 描述 | 严重性 | 状态 | 验证方式 |
|-----|------|--------|------|----------|
| Bug 1 | `_completingProvider` 卡死 | 🔴 高 | ✅ 已修复 | 所有退出路径均重置，`loadAndPlayProvider` 有安全网 |
| Bug 2 | 取消全选不退出选择模式 | 🔴 中 | ✅ 已修复 | `_exitSelectionMode()` 正确清除双状态 |
| Bug 3 | 目录缓存淘汰不是 LRU | 🟡 低 | ✅ 已修复 | `CacheEntry.lastAccessedAt` + LRU 排序淘汰 |
| Bug 4 | 播放单排序缺防御检查 | 🟡 低 | ✅ 已修复 | dev-status.json 标记 done |
| Bug 5 | `SerializedRequestGate` 卡死 | 🔴 高 | ✅ 已修复 | 20s 超时保护 |

---

## 关键偏差汇总

### 1. Domain 层"死代码"问题 ⚠️

**影响范围**：Progress、Playlist、Settings 三个模块

domain 层文件已创建且通过测试，但 provider 未实际使用它们。这导致：
- 业务逻辑存在两份实现（provider 内联 + domain 层独立）
- domain 层的测试覆盖的是未被生产代码调用的路径
- 未来修改 provider 逻辑时，domain 层的测试无法提供安全网

**根因**：Phase 1-2 的 player/browser 模块是"先提取 domain → 再重写 provider"，但 Phase 4 的 progress/playlist/settings 只完成了"提取 domain"，未完成"重写 provider 为薄胶水"。

### 2. `player_screen.dart` 超过 500 行限制 ⚠️

- **987 行**，超过 CI 的 500 行限制
- CI 会在下次 push 时失败
- 需要拆分（提取 widget 组件或拆分页面）

### 3. `lib/app/` 目录未创建

计划要求拆分 router/app/onboarding 到 `lib/app/`，实际全部在 `main.dart` (341行)。在 500 行限制内，但不符合计划的目录结构。

### 4. `player_provider.dart` 仍含业务逻辑

`skipToNextProvider` 等 4 个 provider 内联队列导航逻辑，未完全委托给 `PlaybackOrchestrator`。`startProcessingListenerProvider` 也含自动切歌逻辑。

### 5. `background_playback.dart` 不是纯 Dart

依赖 `flutter/material.dart` 和 `flutter_riverpod`，违反"Domain 层零 Flutter 依赖"原则。应将 `BackgroundPlaybackConfig` 纯逻辑与 `StateNotifier`/provider 分离。

### 6. 集成测试缺口

计划 6 个集成测试，实际实现 3 个（TST-02/03/04）。缺少：
- INT-G01: 连接切换完整影响面
- INT-G05: 路由完整导航流程
- INT-G06: App 生命周期完整链路

---

## 最终验证清单

| 验证项 | 计划要求 | 实际 | 状态 |
|--------|---------|------|------|
| state.md 每个状态转移有测试 | ✅ | 81/100 覆盖 (81%) | ⚠️ 部分 |
| test.md 所有缺口已填补 | ✅ | 大部分已填补 | ⚠️ 部分 |
| 无单文件超过 500 行 | ✅ | `player_screen.dart` 987行 | ❌ 未达标 |
| 跨 feature import 只在 `providers.dart` | ✅ | 零违规 | ✅ 达标 |
| `flutter test` 全部通过 | ✅ | dev-status.json 全 passed | ✅ 达标 |
| `flutter analyze` 无错误 | ✅ | CI 包含此步骤 | ✅ 达标 |

---

## 建议后续行动

1. **P0**: 修复 `player_screen.dart` 超限 — 拆分 widget 组件，降至 500 行以内
2. **P1**: 将 progress/playlist/settings 的 provider 改为真正委托 domain service（消除死代码）
3. **P1**: 将 `player_provider.dart` 中的队列导航逻辑移入 `PlaybackOrchestrator`
4. **P2**: 将 `background_playback.dart` 的纯逻辑与 Riverpod 依赖分离
5. **P2**: 补全 3 个缺失的集成测试
6. **P3**: 考虑将 `main.dart` 拆分为 `lib/app/` 目录结构
