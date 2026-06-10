# 开发计划

> 基于 refactor-result.md 偏差分析生成。
> 更新日期: 2026-06-10

---

## 待实现 — 偏差修复

### FIX-01 player_screen.dart 超500行限制

**来源**：refactor-result.md | **优先级**：P0
**涉及文件**：`lib/features/player/player_screen.dart`（987行 → 目标 ≤450行）
**依赖**：无

**根因**：
player_screen.dart 包含 1 个主 Widget + 7 个私有 Widget（`_NowPlayingIcon`、`_ProgressSlider`、`_PlaybackControls`、`_SpeedControl`、`_PlayModeControl`、`_QueueButton`、`_TimerControl`），全部挤在一个文件中。CI 的 500 行限制会阻止合并。

**代码锚点**：
- `player_screen.dart:35-290` — PlayerScreen 主 Widget + 状态管理（~255行）
- `player_screen.dart:496-525` — `_NowPlayingIcon`（~30行）
- `player_screen.dart:526-629` — `_ProgressSlider`（~104行）
- `player_screen.dart:630-806` — `_PlaybackControls`（~177行）
- `player_screen.dart:807-896` — `_SpeedControl`（~90行）
- `player_screen.dart:897-916` — `_PlayModeControl`（~20行）
- `player_screen.dart:917-933` — `_QueueButton`（~17行）
- `player_screen.dart:934-987` — `_TimerControl`（~54行）

**修复方案**：

将 7 个私有 Widget 提取到 `lib/features/player/widgets/` 目录：

1. **新建 `lib/features/player/widgets/now_playing_icon.dart`**
   - 移入 `_NowPlayingIcon` → 改为公开类 `NowPlayingIcon`
   - 依赖：`player_provider.dart`（读取 `currentPlayQueueProvider`）

2. **新建 `lib/features/player/widgets/progress_slider.dart`**
   - 移入 `_ProgressSlider` + `_ProgressSliderState` → `ProgressSlider`
   - 依赖：`player_provider.dart`（读取 position/duration 流）

3. **新建 `lib/features/player/widgets/playback_controls.dart`**
   - 移入 `_PlaybackControls` → `PlaybackControls`
   - 依赖：`player_provider.dart`（play/pause/skip 操作）、`seek_utils.dart`

4. **新建 `lib/features/player/widgets/speed_control.dart`**
   - 移入 `_SpeedControl` → `SpeedControl`
   - 依赖：`player_provider.dart`（speedOptions、currentSpeed）

5. **新建 `lib/features/player/widgets/play_mode_control.dart`**
   - 移入 `_PlayModeControl` → `PlayModeControl`
   - 依赖：`player_provider.dart`（playMode、nextPlayMode）

6. **新建 `lib/features/player/widgets/queue_button.dart`**
   - 移入 `_QueueButton` → `QueueButton`
   - 依赖：无（纯 UI，通过回调通知父级）

7. **新建 `lib/features/player/widgets/timer_control.dart`**
   - 移入 `_TimerControl` → `TimerControl`
   - 依赖：`timer_provider.dart`、`timer/domain/timer_service.dart`

8. **修改 `player_screen.dart`**
   - import 上述 7 个新文件
   - 替换私有 Widget 引用为公开类名
   - 预估剩余 ~300 行

**测试用例**：FIX-01-T01 ~ FIX-01-T03
- FIX-01-T01: `flutter test test/features/player/` 全量回归通过
- FIX-01-T02: `wc -l lib/features/player/player_screen.dart` ≤ 450
- FIX-01-T03: `flutter analyze` 0 issues

**验收标准**：
- [ ] player_screen.dart ≤ 450 行
- [ ] 每个新 widget 文件 ≤ 200 行
- [ ] `flutter test` 全量回归通过
- [ ] `flutter analyze` 0 issues
- [ ] CI 文件行数检查通过

---

### FIX-02 progress provider 未使用 domain service

**来源**：refactor-result.md | **优先级**：P1
**涉及文件**：
- `lib/features/progress/progress_provider.dart`（重写）
- `lib/features/progress/domain/progress_service.dart`（可能调整）
- `lib/features/progress/domain/progress_policy.dart`（确认）

**依赖**：无

**根因**：
`progress_provider.dart` 直接调用 `ProgressDao`，未使用已提取的 `ProgressService` 和 `progress_policy.dart`。导致：
- 业务逻辑存在两份实现（provider 内联 + domain 层独立）
- domain 层的 `ProgressService` 和 `progress_policy.dart` 是死代码
- provider 中的 `ProgressResumeState`/`ProgressResumeNotifier` 与 domain 层的 `ResumeDialogState` 重复

**代码锚点**：
- `progress_provider.dart:58-93` — `upsertProgressProvider` 直接调用 `dao.upsert()`，未通过 `ProgressService`
- `progress_provider.dart:96-121` — `clearProgressProvider` 直接调用 `dao.delete()`，未通过 `ProgressService`
- `progress_provider.dart:129-165` — `ProgressResumeState` 与 domain 层 `ResumeDialogState` 重复
- `progress_provider.dart:171-213` — `ProgressResumeNotifier` 与 domain 层 `ProgressService.tickCountdown()` 重复

**修复方案**：

1. **修改 `progress_provider.dart`**：
   - 添加 `progressServiceProvider` provider，创建 `ProgressService` 实例
   - `upsertProgressProvider` 改为委托给 `ProgressService.saveProgress()`
   - `clearProgressProvider` 改为委托给 `ProgressService.clearProgress()`
   - `progressForFileProvider` 改为委托给 `ProgressService.getProgress()`
   - 删除 `ProgressResumeState` 类（使用 domain 层的 `ResumeDialogState`）
   - 重写 `ProgressResumeNotifier` 使用 `ProgressService.showResumeDialog()` 和 `ProgressService.tickCountdown()`
   - 保留 `progressDaoProvider`（注入点，测试可覆盖）
   - 保留 `ref.invalidate()` 调用（UI 刷新属于 provider 层职责）

2. **确认 `progress_policy.dart`**：
   - `shouldSave()` 和 `shouldClear()` 已在 `ProgressDao.upsert()` 内部调用
   - 不需要在 provider 层重复调用
   - 保持现状，但确认 domain 测试覆盖了这两个函数

3. **确认 `progress_service.dart`**：
   - `saveProgress()` 已正确委托给 `ProgressDao.upsert()`
   - `showResumeDialog()` 和 `tickCountdown()` 需要被 provider 使用

**测试用例**：FIX-02-T01 ~ FIX-02-T05
- FIX-02-T01: `upsertProgressProvider` 调用 → `ProgressService.saveProgress()` 被调用（验证委托）
- FIX-02-T02: `clearProgressProvider` 调用 → `ProgressService.clearProgress()` 被调用
- FIX-02-T03: 恢复对话框 → `ProgressService.showResumeDialog()` 创建状态 → `tickCountdown()` 推进倒计时
- FIX-02-T04: 倒计时归零 → `isExpired` 为 true（回归）
- FIX-02-T05: `flutter test test/features/progress/` 全量回归通过

**验收标准**：
- [ ] `progress_provider.dart` 不再直接调用 `ProgressDao.upsert()`/`delete()`（除了注入点）
- [ ] `ProgressResumeState` 类已删除，使用 `ResumeDialogState`
- [ ] domain 层 `ProgressService` 和 `progress_policy.dart` 不再是死代码
- [ ] `flutter test` 全量回归通过
- [ ] `flutter analyze` 0 issues

---

### FIX-03 playlist provider 未使用 domain service

**来源**：refactor-result.md | **优先级**：P1
**涉及文件**：
- `lib/features/playlist/playlist_provider.dart`（重写）
- `lib/features/playlist/domain/playlist_service.dart`（确认）

**依赖**：无

**根因**：
`playlist_provider.dart` 直接调用 `PlaylistDao`，未使用已提取的 `PlaylistService`。去重逻辑和导入导出逻辑在 provider 和 domain service 中各有一份。

**代码锚点**：
- `playlist_provider.dart:77-89` — `createPlaylistProvider` 直接调用 `dao.insertPlaylist()`
- `playlist_provider.dart:108-131` — `addTracksToPlaylistProvider` 内联去重逻辑（与 `PlaylistService.addTracksToPlaylist()` 重复）
- `playlist_provider.dart:157-171` — `exportPlaylistProvider` 内联导出逻辑（与 `PlaylistService.exportPlaylist()` 重复）
- `playlist_provider.dart:174-207` — `importPlaylistProvider` 内联导入逻辑（与 `PlaylistService.importPlaylist()` 重复）

**修复方案**：

1. **修改 `playlist_provider.dart`**：
   - 添加 `playlistServiceProvider` provider，创建 `PlaylistService` 实例
   - `createPlaylistProvider` 委托给 `PlaylistService.createPlaylist()`
   - `deletePlaylistProvider` 委托给 `PlaylistService.deletePlaylist()`
   - `updatePlaylistProvider` 委托给 `PlaylistService.updatePlaylist()`
   - `addTracksToPlaylistProvider` 委托给 `PlaylistService.addTracksToPlaylist()`
   - `removeTracksFromPlaylistProvider` 委托给 `PlaylistService.removeTracks()`
   - `reorderPlaylistTrackProvider` 委托给 `PlaylistService.reorderTrack()`（保留排序模式检查）
   - `exportPlaylistProvider` 委托给 `PlaylistService.exportPlaylist()`
   - `importPlaylistProvider` 委托给 `PlaylistService.importPlaylist()`
   - `playlistListProvider` 委托给 `PlaylistService.findAllPlaylists()`（排序逻辑保留在 provider）
   - `playlistTracksProvider` 委托给 `PlaylistService.findTracksForPlaylist()`（排序逻辑保留在 provider）
   - 保留 `playlistDaoProvider`（注入点）
   - 保留 `ref.invalidate()` 调用
   - 保留排序枚举和比较函数（UI 层关注点）

2. **确认 `playlist_service.dart`**：
   - 所有 CRUD、去重、导入导出方法已实现
   - 无需修改

**测试用例**：FIX-03-T01 ~ FIX-03-T04
- FIX-03-T01: `createPlaylistProvider` → `PlaylistService.createPlaylist()` 被调用
- FIX-03-T02: `addTracksToPlaylistProvider` 重复曲目 → 去重生效（通过 service）
- FIX-03-T03: `exportPlaylistProvider` → JSON 格式正确（通过 service）
- FIX-03-T04: `flutter test test/features/playlist/` 全量回归通过

**验收标准**：
- [ ] `playlist_provider.dart` 不再直接调用 `PlaylistDao`（除了 `playlistDaoProvider` 注入点）
- [ ] 去重/导入导出逻辑只在 `PlaylistService` 中存在一份
- [ ] `flutter test` 全量回归通过
- [ ] `flutter analyze` 0 issues

---

### FIX-04 settings provider 未使用 domain service

**来源**：refactor-result.md | **优先级**：P1
**涉及文件**：
- `lib/features/settings/settings_provider.dart`（重写）
- `lib/features/settings/domain/settings_service.dart`（调整）

**依赖**：无

**根因**：
`settings_provider.dart` 内联定义了 `getThemeMode()`、`setThemeMode()`、`labelForThemeMode()`、`setSeekStep()`、`labelForSeekStep()`、`getRememberSpeed()` 等函数，未使用已提取的 `SettingsService`。

**代码锚点**：
- `settings_provider.dart:27-35` — `getThemeMode()` 与 `SettingsService.getThemeMode()` 重复
- `settings_provider.dart:40-42` — `setThemeMode()` 与 `SettingsService.setThemeMode()` 重复
- `settings_provider.dart:45-54` — `labelForThemeMode()` 与 `SettingsService.labelForThemeMode()` 重复
- `settings_provider.dart:89-93` — `setSeekStep()` 与 `SettingsService.setSeekStep()` 重复
- `settings_provider.dart:105-108` — `getRememberSpeed()` 未在 `SettingsService` 中

**修复方案**：

1. **修改 `settings_service.dart`**：
   - 添加 `getRememberSpeed()` / `setRememberSpeed()` 方法
   - 添加 `labelForSeekStep()` 方法（如果不存在）
   - 确认 `getThemeMode()` / `setThemeMode()` / `labelForThemeMode()` / `setSeekStep()` 已存在

2. **修改 `settings_provider.dart`**：
   - 添加 `settingsServiceProvider` provider，创建 `SettingsService` 实例
   - `themeModeProvider` 委托给 `SettingsService.getThemeMode()`
   - `setThemeModeProvider` 委托给 `SettingsService.setThemeMode()`
   - `seekStepSettingProvider` 委托给 `SettingsService.readSeekStep()`
   - `setSeekStepSettingProvider` 委托给 `SettingsService.setSeekStep()`
   - `rememberSpeedProvider` 委托给 `SettingsService.getRememberSpeed()`
   - `setRememberSpeedProvider` 委托给 `SettingsService.setRememberSpeed()`
   - 删除内联的 `getThemeMode()`、`setThemeMode()`、`labelForThemeMode()`、`setSeekStep()`、`labelForSeekStep()`、`getRememberSpeed()` 函数
   - 保留 `sharedPreferencesProvider`（注入点）
   - 保留 `ref.invalidate()` 调用

3. **处理 `ThemeMode` 依赖**：
   - `settings_service.dart` 当前 import `flutter/material.dart` 仅用于 `ThemeMode`
   - 可接受：`ThemeMode` 是 Flutter 框架的枚举，不是 widget，不影响纯逻辑测试性
   - 或者：在 domain 层定义自己的 `AppThemeMode` 枚举，在 provider 层映射到 Flutter 的 `ThemeMode`（更干净但工程量大）
   - **建议**：保持现状，`ThemeMode` 依赖可接受

**测试用例**：FIX-04-T01 ~ FIX-04-T04
- FIX-04-T01: `themeModeProvider` 读取 → 通过 `SettingsService.getThemeMode()`
- FIX-04-T02: `setThemeModeProvider` 写入 → 通过 `SettingsService.setThemeMode()`
- FIX-04-T03: `rememberSpeedProvider` 读写 → 通过 `SettingsService`
- FIX-04-T04: `flutter test test/features/settings/` 全量回归通过

**验收标准**：
- [ ] `settings_provider.dart` 不再内联业务函数
- [ ] `SettingsService` 被 provider 实际使用
- [ ] `flutter test` 全量回归通过
- [ ] `flutter analyze` 0 issues

---

### FIX-05 player_provider 内联队列导航逻辑

**来源**：refactor-result.md | **优先级**：P1
**涉及文件**：
- `lib/features/player/player_provider.dart`（修改）
- `lib/features/player/domain/playback_orchestrator.dart`（扩展）

**依赖**：无

**根因**：
`player_provider.dart` 中的 `skipToNextProvider`、`skipToPreviousProvider`、`selectQueueIndexProvider`、`removeTrackFromQueueProvider` 内联了队列导航逻辑（`PlayQueue.nextIndex`/`advanceShuffle`/`retreatShuffle`/`withoutIndex`），未完全委托给 `PlaybackOrchestrator`。`startProcessingListenerProvider` 也内联了曲目完成自动切歌逻辑。

**代码锚点**：
- `player_provider.dart:222-235` — `skipToNextProvider` 内联 `q.advanceShuffle()` / `PlayQueue.nextIndex()`
- `player_provider.dart:237-250` — `skipToPreviousProvider` 内联 `q.retreatShuffle()` / `PlayQueue.previousIndex()`
- `player_provider.dart:252-261` — `selectQueueIndexProvider` 内联 `q.withIndex(i)`
- `player_provider.dart:263-282` — `removeTrackFromQueueProvider` 内联 `q.withoutIndex(i)` + 空队列 stop 逻辑
- `player_provider.dart:172-205` — `startProcessingListenerProvider` 内联曲目完成自动切歌

**修复方案**：

1. **扩展 `PlaybackOrchestrator`**：
   - `skipToNext()` 方法已存在 → 确认包含队列更新 + 进度保存 + loadAndPlay
   - `skipToPrevious()` 方法已存在 → 确认包含队列更新 + 进度保存 + loadAndPlay
   - `selectQueueIndex(int)` 方法已存在 → 确认包含队列更新 + loadAndPlay
   - `removeTrack(int)` 方法已存在 → 确认包含空队列 stop + 当前曲目处理
   - 添加 `handleTrackCompleted()` 方法 → 封装曲目完成后的自动切歌逻辑
   - 所有方法需要接收当前队列和播放模式作为参数（或通过接口获取）

2. **修改 `player_provider.dart`**：
   - `skipToNextProvider` → 委托给 `orchestrator.skipToNext()`
   - `skipToPreviousProvider` → 委托给 `orchestrator.skipToPrevious()`
   - `selectQueueIndexProvider` → 委托给 `orchestrator.selectQueueIndex(i)`
   - `removeTrackFromQueueProvider` → 委托给 `orchestrator.removeTrack(i)`
   - `startProcessingListenerProvider` → 使用 `orchestrator.handleTrackCompleted()`
   - 保留 `currentPlayQueueProvider` 的读写（状态管理属于 provider 层）

**测试用例**：FIX-05-T01 ~ FIX-05-T05
- FIX-05-T01: `skipToNextProvider` → orchestrator 被调用 → 队列更新 + loadAndPlay
- FIX-05-T02: `skipToPreviousProvider` → orchestrator 被调用
- FIX-05-T03: `removeTrackFromQueueProvider` 空队列 → orchestrator.stop()
- FIX-05-T04: 曲目完成 → `handleTrackCompleted()` 自动切歌
- FIX-05-T05: `flutter test test/features/player/` 全量回归通过

**验收标准**：
- [ ] `player_provider.dart` 中 `skipToNextProvider` 等 4 个 provider 不再内联队列逻辑
- [ ] `startProcessingListenerProvider` 不再内联自动切歌逻辑
- [ ] 队列导航逻辑只在 `PlaybackOrchestrator` 中存在一份
- [ ] `flutter test` 全量回归通过
- [ ] `flutter analyze` 0 issues

---

### FIX-06 background_playback.dart 不是纯 Dart

**来源**：refactor-result.md | **优先级**：P2
**涉及文件**：
- `lib/features/player/domain/background_playback.dart`（拆分）

**依赖**：无

**根因**：
`background_playback.dart` import `flutter/material.dart` 和 `flutter_riverpod.dart`，违反"Domain 层零 Flutter 依赖"原则。其中 `BackgroundPlaybackConfig` 纯逻辑与 `StateNotifier`/provider 耦合在同一文件中。

**代码锚点**：
- `background_playback.dart:16` — `import 'package:flutter/material.dart';`（用于 `@immutable`、`AppLifecycleState`）
- `background_playback.dart:17` — `import 'package:flutter_riverpod/flutter_riverpod.dart';`（用于 `StateNotifier`、`StateNotifierProvider`）

**修复方案**：

1. **拆分文件**：
   - **保留 `background_playback.dart`** 作为纯逻辑层：
     - `AudioFocusState`、`BackgroundPlaybackState`、`MediaControlAction` 枚举
     - `BackgroundPlaybackConfig` 值对象（移除 `@immutable` 注解或用 `dart:core` 的等价方式）
     - `shouldContinueInBackground()` 纯函数
     - `computePlaybackStateAfterLifecycle()` 纯函数
     - 用自定义枚举 `AppLifecyclePhase { resumed, inactive, paused, detached }` 替代 `AppLifecycleState`
   - **新建 `background_playback_notifier.dart`**（在 `player/` 目录，不在 `domain/`）：
     - `BackgroundPlaybackNotifier extends StateNotifier<BackgroundPlaybackConfig>`
     - `backgroundPlaybackProvider`
     - import `flutter_riverpod` 和 `background_playback.dart`

2. **处理 `@immutable` 注解**：
   - 移除 `@immutable` 注解（来自 `flutter/material.dart`）
   - 用文档注释说明该类应被视为不可变

3. **处理 `AppLifecycleState`**：
   - 在纯逻辑层定义 `AppLifecyclePhase` 枚举
   - `computePlaybackStateAfterLifecycle()` 接收 `AppLifecyclePhase` 参数
   - 在 notifier 层将 Flutter 的 `AppLifecycleState` 映射到 `AppLifecyclePhase`

**测试用例**：FIX-06-T01 ~ FIX-06-T03
- FIX-06-T01: `background_playback.dart` 零 Flutter/Riverpod import
- FIX-06-T02: `BackgroundPlaybackConfig` 状态机测试全部通过（纯 Dart）
- FIX-06-T03: `flutter test test/features/player/` 全量回归通过

**验收标准**：
- [ ] `domain/background_playback.dart` 不 import `flutter` 或 `flutter_riverpod`
- [ ] `BackgroundPlaybackNotifier` 在独立文件中
- [ ] 纯逻辑可直接 `test()` 无需 mock
- [ ] `flutter test` 全量回归通过

---

### FIX-07 缺少3个集成测试

**来源**：refactor-result.md | **优先级**：P2
**涉及文件**：`test/features/coverage/`（新建测试文件）
**依赖**：FIX-02, FIX-03, FIX-05

**根因**：
计划 6 个集成测试，实际实现 3 个（TST-02/03/04）。缺少：
- INT-G01: 连接切换完整影响面
- INT-G05: 路由完整导航流程
- INT-G06: App 生命周期完整链路

**修复方案**：

1. **新建 `test/features/coverage/int_g01_connection_switch_test.dart`**
   - 测试场景：切换连接 → 队列清空 → 缓存清空 → 新连接可浏览
   - 测试场景：切换连接 → 播放中 → 播放停止 → 新连接可播放
   - 测试场景：删除活跃连接 → 自动切换 → UI 更新

2. **新建 `test/features/coverage/int_g05_routing_test.dart`**
   - 测试场景：onboarding → 无连接 → connection 页面
   - 测试场景：onboarding → 有连接+验证成功 → browser 页面
   - 测试场景：browser → 点击文件 → player 页面
   - 测试场景：player → 返回 → browser 页面
   - 测试场景：browser → 设置 → settings 页面

3. **新建 `test/features/coverage/int_g06_lifecycle_test.dart`**
   - 测试场景：App 进入后台 → 播放继续（后台播放开启）
   - 测试场景：App 进入后台 → 播放暂停（后台播放关闭）
   - 测试场景：App 恢复前台 → 播放状态正确
   - 测试场景：App 恢复前台 → 定时器检查 → 如果过期则暂停

**测试用例**：FIX-07-T01 ~ FIX-07-T12
- FIX-07-T01 ~ T04: INT-G01 连接切换场景
- FIX-07-T05 ~ T09: INT-G05 路由导航场景
- FIX-07-T10 ~ T12: INT-G06 生命周期场景

**验收标准**：
- [ ] 3 个新测试文件创建完成
- [ ] 所有测试用例通过
- [ ] `flutter test` 全量回归通过

---

### FIX-08 lib/app/ 目录未创建

**来源**：refactor-result.md | **优先级**：P3
**涉及文件**：
- `lib/main.dart`（拆分）
- 新建 `lib/app/router.dart`
- 新建 `lib/app/app.dart`
- 新建 `lib/app/onboarding.dart`

**依赖**：无

**根因**：
计划要求将 router/app/onboarding 拆分到 `lib/app/` 目录，实际全部内联在 `main.dart` (341行)。虽然未超 500 行限制，但不符合计划的目录结构，且 `main.dart` 职责过多。

**代码锚点**：
- `main.dart:87-148` — `_router` GoRouter 定义（~62行）
- `main.dart:152-176` — `NasAudioPlayerApp` Widget（~25行）
- `main.dart:183-290` — `_OnboardingPage` Widget（~108行）
- `main.dart:1-86` — import + `main()` + ProviderScope overrides（~86行）

**修复方案**：

1. **新建 `lib/app/router.dart`**：
   - 移入 `_router` GoRouter 定义
   - 改为公开 getter `GoRouter createRouter()`
   - 包含所有路由定义

2. **新建 `lib/app/app.dart`**：
   - 移入 `NasAudioPlayerApp`
   - import `router.dart`

3. **新建 `lib/app/onboarding.dart`**：
   - 移入 `_OnboardingPage` → `OnboardingPage`

4. **修改 `lib/main.dart`**：
   - 只保留 `main()` 函数 + ProviderScope overrides
   - import `app/app.dart`
   - 预估剩余 ~100 行

**测试用例**：FIX-08-T01 ~ FIX-08-T02
- FIX-08-T01: `flutter test test/features/home/` 回归通过
- FIX-08-T02: `flutter analyze` 0 issues

**验收标准**：
- [ ] `lib/app/` 目录创建，含 3 个文件
- [ ] `main.dart` ≤ 120 行
- [ ] `flutter test` 全量回归通过
- [ ] `flutter analyze` 0 issues
