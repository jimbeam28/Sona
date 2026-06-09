# 开发计划

> 基于 state.md 状态机规格书 + refactor-plan.md 重构计划 + 代码审查发现生成。
> 更新日期: 2026-06-09

---

## 待实现 — Bug 修复（P0）

### BUG-01 `_completingProvider` 卡死导致自动切歌永久失效

**来源**：代码审查 | **优先级**：P0
**涉及文件**：`lib/features/player/player_provider.dart`
**依赖**：无
**关联缺陷**：refactor-plan.md Bug 1

**根因**：
processing-state 监听器中，当曲目完成且 afterCurrent 未触发时，如果 `currentPlayQueueProvider` 为 null，代码直接 `return`，未将 `_completingProvider` 重置为 `false`。

**代码锚点**：
- `lib/features/player/player_provider.dart:665` 当前实现
  ```dart
  if (q == null) return;  // ← _completingProvider 未重置
  ```

**修复方案**：
在 `return` 前添加 `ref.read(_completingProvider.notifier).state = false;`

**测试用例**：BUG-01-T01 ~ BUG-01-T03
- BUG-01-T01: 队列为 null 时曲目完成 → `_completingProvider` 被重置为 false
- BUG-01-T02: Bug 修复后再次曲目完成 → 自动切歌正常工作
- BUG-01-T03: afterCurrent 触发路径 → `_completingProvider` 仍被正确重置（回归）

**验收标准**：
- [ ] BUG-01-T01 ~ T03 全部通过
- [ ] `flutter test test/features/player/` 全量回归通过
- [ ] `flutter analyze` 0 issues

---

### BUG-02 播放单"取消全选"不退出选择模式

**来源**：代码审查 | **优先级**：P0
**涉及文件**：`lib/features/playlist/playlist_detail_screen.dart`
**依赖**：无
**关联缺陷**：refactor-plan.md Bug 2

**根因**：
"取消全选"按钮只调用 `setState(() => _selectedIds.clear())`，未调用 `_exitSelectionMode()`。

**代码锚点**：
- `lib/features/playlist/playlist_detail_screen.dart:300-305` 当前实现
  ```dart
  onPressed: () => setState(() => _selectedIds.clear()),
  // 缺少: _exitSelectionMode() 调用
  ```

**修复方案**：
```dart
onPressed: () => _exitSelectionMode(),
```

**测试用例**：BUG-02-T01 ~ BUG-02-T03
- BUG-02-T01: 长按进入选择 → 全选 → 取消全选 → selectionMode 恢复为 false
- BUG-02-T02: 取消全选后 AppBar 恢复为普通模式
- BUG-02-T03: 取消全选后可正常点击曲目播放（回归）

**验收标准**：
- [ ] BUG-02-T01 ~ T03 全部通过
- [ ] `flutter test test/features/playlist/` 全量回归通过
- [ ] `flutter analyze` 0 issues

---

### BUG-03 目录缓存淘汰不是 LRU

**来源**：代码审查 | **优先级**：P1
**涉及文件**：`lib/features/browser/browser_provider.dart`
**依赖**：无
**关联缺陷**：refactor-plan.md Bug 3

**根因**：
缓存淘汰按 Map 插入顺序移除最旧条目，不是按最近使用时间。重新访问旧目录不会更新其淘汰优先级。

**代码锚点**：
- `lib/features/browser/browser_provider.dart:222-234` 当前实现
  ```dart
  if (updated.length > 50) {
    final keysToRemove = updated.keys.take(updated.length - 50);
    // ← 按插入顺序淘汰，非 LRU
  }
  ```

**修复方案**：
在 `CacheEntry` 中添加 `lastAccessedAt` 字段，缓存命中时更新。淘汰时按 `lastAccessedAt` 排序，移除最久未访问的条目。

**测试用例**：BUG-03-T01 ~ BUG-03-T04
- BUG-03-T01: 50 条缓存 → 访问第 1 条 → 插入第 51 条 → 第 1 条不被淘汰
- BUG-03-T02: 50 条缓存 → 不访问第 1 条 → 插入第 51 条 → 第 1 条被淘汰
- BUG-03-T03: 缓存命中时 lastAccessedAt 更新
- BUG-03-T04: 多次访问同一旧条目 → 该条目始终不被淘汰

**验收标准**：
- [ ] BUG-03-T01 ~ T04 全部通过
- [ ] `flutter test test/features/browser/` 全量回归通过
- [ ] `flutter analyze` 0 issues

---

### BUG-04 播放单曲目排序缺少防御检查

**来源**：代码审查 | **优先级**：P2
**涉及文件**：`lib/features/playlist/playlist_provider.dart`
**依赖**：无
**关联缺陷**：refactor-plan.md Bug 4

**根因**：
`reorderPlaylistTrackProvider` 没有检查当前排序模式，仅靠 UI 层阻止调用。

**代码锚点**：
- `lib/features/playlist/playlist_provider.dart:134-142` 当前实现
  ```dart
  final reorderPlaylistTrackProvider = Provider<void Function(int, int)>((ref) {
    return (oldIndex, newIndex) {
      // 缺少: if (ref.read(trackSortProvider) != TrackSortOption.addedAsc) return;
    };
  });
  ```

**修复方案**：
在 Provider 中添加排序模式检查。

**测试用例**：BUG-04-T01 ~ BUG-04-T02
- BUG-04-T01: 非 addedAsc 排序下调用 reorder → 操作被忽略
- BUG-04-T02: addedAsc 排序下调用 reorder → 正常执行（回归）

**验收标准**：
- [ ] BUG-04-T01 ~ T02 全部通过
- [ ] `flutter test test/features/playlist/` 全量回归通过
- [ ] `flutter analyze` 0 issues

---

### BUG-05 SerializedRequestGate 卡死导致所有后续加载请求永久挂起

**来源**：用户反馈"点击音乐文件后播放页面卡在加载" + 代码审查 | **优先级**：P0
**涉及文件**：`lib/features/player/player_provider.dart`
**依赖**：无
**关联缺陷**：refactor-plan.md Bug 5

**根因**：
`SerializedRequestGate._start()` 的 `finally` 块在 `await task` 完成后才执行。但 `loadAndPlayProvider` 的 task 内部有多个 `await` 调用（`activeConnectionProvider.future`、`SecureStorage.read`、`player.setAudioSource`），任何一个挂起都会导致 `_running` 永远为 `true`，后续所有请求排队等待，永远无法执行。

屏幕侧的 `request().timeout(15s)` 只让 UI 显示 error，但 gate 内部的 `_running` 不会被重置。

**代码锚点**：
- `lib/features/player/player_provider.dart:177-199` SerializedRequestGate._start()
  ```dart
  void _start<T>(_QueuedRequest<T> request) {
    _running = true;
    unawaited(() async {
      try {
        final result = await request.task(request.requestId);  // ← 挂起时 finally 不执行
        // ...
      } finally {
        _running = false;  // ← 永远到不了这里
        // ...
      }
    }());
  }
  ```
- `lib/features/player/player_provider.dart:912` await activeConnectionProvider.future — 无超时
- `lib/features/player/player_provider.dart:928` await storage.read() — 无超时
- `lib/features/player/player_provider.dart:955` await player.setAudioSource() — 无超时

**修复方案**：
1. 在 `SerializedRequestGate._start()` 中给 task 加 20 秒超时保护
2. 在 `loadAndPlayProvider` 中给 `SecureStorage.read` 加 5 秒超时
3. 在 `loadAndPlayProvider` 中给 `activeConnectionProvider.future` 加 5 秒超时
4. 添加 gate 强制重置机制（watchdog）

**测试用例**：BUG-05-T01 ~ BUG-05-T05
- BUG-05-T01: task 内部挂起 → 20 秒后 gate 超时 → _running 重置为 false
- BUG-05-T02: gate 超时后 → 新请求可正常执行
- BUG-05-T03: SecureStorage.read 挂起 → 5 秒后超时 → 返回 null → failed
- BUG-05-T04: 正常加载 → gate 超时未触发 → 行为不变（回归）
- BUG-05-T05: 连续 3 次加载失败 → gate 每次都正确重置 → 第 4 次可成功

**验收标准**：
- [ ] BUG-05-T01 ~ T05 全部通过
- [ ] `flutter test test/features/player/` 全量回归通过
- [ ] `flutter analyze` 0 issues
- [ ] 手动验证：断网状态下点击文件 → 15 秒后显示 error → 恢复网络 → 重试成功

---

## 待实现 — 重构 Phase 0：测试基础设施

### REF-01 创建 test/helpers/ 目录结构

**来源**：重构计划 Phase 0 | **优先级**：P0
**涉及文件**：新建 `test/helpers/` 目录
**依赖**：无

**实现要点**：
- 创建 `test/helpers/` 目录
- 创建 `test/helpers/test_database.dart` — 共享数据库初始化
- 创建 `test/helpers/fake_secure_storage.dart` — 共享 FakeSecureStorage
- 创建 `test/helpers/test_factories.dart` — 共享 _audio()/_dir() 工厂
- 创建 `test/helpers/widget_helpers.dart` — 共享 widget 包装函数

**验收标准**：
- [ ] 目录结构创建完成
- [ ] 所有文件可被现有测试 import

---

### REF-02 提取 FakeSecureStorage 到共享模块

**来源**：重构计划 Phase 0 | **优先级**：P0
**涉及文件**：`test/helpers/fake_secure_storage.dart`（新建）
**依赖**：REF-01

**实现要点**：
- 从 `con_09_test.dart`、`brw_05_test.dart`、`brw_06_test.dart` 提取 FakeSecureStorage
- 合并为一个共享实现，支持 `stub()`、`read()`、`write()`、`delete()`
- 包含 `ThrowingFakeSecureStorage` 变体
- 更新 3 个源文件使用共享版本

**测试用例**：REF-02-T01
- REF-02-T01: 3 个源文件 import 共享 FakeSecureStorage 后测试全部通过

**验收标准**：
- [ ] `flutter test` 全量回归通过
- [ ] 无重复的 FakeSecureStorage 定义

---

### REF-03 提取 openTestDatabase 到共享模块

**来源**：重构计划 Phase 0 | **优先级**：P0
**涉及文件**：`test/helpers/test_database.dart`（新建）
**依赖**：REF-01

**实现要点**：
- 从 7+ 个测试文件提取 `_openTestDatabase()` 函数
- 支持 `TestSchema` 枚举：connections / progress / playlist / full
- 包含 `initSqfliteFfi()` 辅助函数
- 更新所有源文件使用共享版本

**测试用例**：REF-03-T01
- REF-03-T01: 所有使用 _openTestDatabase 的测试文件 import 共享版本后测试全部通过

**验收标准**：
- [ ] `flutter test` 全量回归通过
- [ ] 无重复的 _openTestDatabase 定义

---

### REF-04 提取 _audio()/_dir() 工厂函数

**来源**：重构计划 Phase 0 | **优先级**：P0
**涉及文件**：`test/helpers/test_factories.dart`（新建）
**依赖**：REF-01

**实现要点**：
- 从 5+ 个测试文件提取 `_audio()` 和 `_dir()` 工厂函数
- 支持可选参数：size、type、audioType
- 包含 `_testConfig()` 和 `_progress()` 等常用工厂
- 更新所有源文件使用共享版本

**测试用例**：REF-04-T01
- REF-04-T01: 所有使用 _audio()/_dir() 的测试文件 import 共享版本后测试全部通过

**验收标准**：
- [ ] `flutter test` 全量回归通过
- [ ] 无重复的工厂函数定义

---

### REF-05 提取 MockWebDavClient 到共享模块

**来源**：重构计划 Phase 0 | **优先级**：P1
**涉及文件**：`test/helpers/fake_webdav_client.dart`（新建）
**依赖**：REF-01

**实现要点**：
- 从 `con_01_test.dart` 提取 MockWebDavClient
- 支持 `returnResult()` 和 `hangUntilCompleted()` 两种模式
- 支持 `listDirectory` 和 `validate` 两个方法
- 包含 `_MockWebDavClient`（brw_05_test.dart 的简单版本）

**测试用例**：REF-05-T01
- REF-05-T01: con_01_test.dart 和 brw_05_test.dart import 共享版本后测试全部通过

**验收标准**：
- [ ] `flutter test` 全量回归通过
- [ ] 无重复的 MockWebDavClient 定义

---

### REF-06 提取 MockAudioPlayer 到共享模块

**来源**：重构计划 Phase 0 | **优先级**：P0
**涉及文件**：`test/helpers/mock_audio_player.dart`（新建）
**依赖**：REF-01

**实现要点**：
- 替代 `ply_08_test.mocks.dart` 的跨 feature import
- 使用 `@GenerateMocks([AudioPlayer])` 在共享文件中生成
- 或使用手写 fake 实现（推荐，避免 build_runner 依赖）
- 更新 6 个导入 `ply_08_test.mocks.dart` 的文件

**测试用例**：REF-06-T01
- REF-06-T01: 所有导入 ply_08_test.mocks.dart 的文件改用共享版本后测试全部通过

**验收标准**：
- [ ] `flutter test` 全量回归通过
- [ ] 无跨 feature 目录的 mock import

---

### REF-07 提取 widget 测试包装函数

**来源**：重构计划 Phase 0 | **优先级**：P1
**涉及文件**：`test/helpers/widget_helpers.dart`（新建）
**依赖**：REF-01

**实现要点**：
- 提取 `_wrapMiniPlayer()`、`_wrapWithRouter()`、`wrapWithTimerProviders()` 等
- 提取 `buildTestApp()`、`makeContainer()` 等通用包装
- 支持可选的 ProviderScope overrides 参数

**测试用例**：REF-07-T01
- REF-07-T01: 使用共享包装函数的 widget 测试全部通过

**验收标准**：
- [ ] `flutter test` 全量回归通过
- [ ] 无重复的 widget 包装函数定义

---

## 待实现 — 重构 Phase 1：Player Domain 提取

### REF-08 创建 player/domain/seek_utils.dart

**来源**：重构计划 Phase 1 Day 1 | **优先级**：P0
**涉及文件**：新建 `lib/features/player/domain/seek_utils.dart`
**依赖**：无

**实现要点**：
- 从 `player_provider.dart` 提取 `clampSeek()`、`skipForward()`、`skipBackward()`
- 纯函数，零 Flutter 依赖
- 保留现有测试，更新 import 路径

**测试用例**：REF-08-T01 ~ REF-08-T03
- REF-08-T01: clampSeek 边界测试（负数、超出范围、正常值）
- REF-08-T02: skipForward 各步长测试
- REF-08-T03: skipBackward 各步长测试

**验收标准**：
- [ ] `flutter test test/features/player/` 全量回归通过
- [ ] 新文件零 Flutter 依赖

---

### REF-09 创建 player/domain/play_mode.dart

**来源**：重构计划 Phase 1 Day 1 | **优先级**：P0
**涉及文件**：新建 `lib/features/player/domain/play_mode.dart`
**依赖**：无

**实现要点**：
- 从 `player_provider.dart` 提取 `PlayMode` 枚举、`iconForPlayMode()`、`labelForPlayMode()`
- 从 `play_queue.dart` 提取 `nextIndex()`、`previousIndex()` 的纯逻辑
- 纯 Dart，零 Flutter 依赖

**测试用例**：REF-09-T01 ~ REF-09-T04
- REF-09-T01: 4 种模式的 nextIndex 行为
- REF-09-T02: 4 种模式的 previousIndex 行为
- REF-09-T03: 边界条件（空队列、单曲目、越界）
- REF-09-T04: 模式切换循环

**验收标准**：
- [ ] `flutter test test/features/player/` 全量回归通过
- [ ] 新文件零 Flutter 依赖

---

### REF-10 创建 player/domain/speed_manager.dart

**来源**：重构计划 Phase 1 Day 1 | **优先级**：P0
**涉及文件**：新建 `lib/features/player/domain/speed_manager.dart`
**依赖**：无

**实现要点**：
- 从 `player_provider.dart` 提取 `speedOptions`、`isValidSpeed()`、`getDefaultSpeed()`、`readSeekStep()`
- 纯函数，零 Flutter 依赖

**测试用例**：REF-10-T01 ~ REF-10-T03
- REF-10-T01: 6 个速度选项验证
- REF-10-T02: isValidSpeed 边界测试
- REF-10-T03: getDefaultSpeed 从 SharedPreferences 读取

**验收标准**：
- [ ] `flutter test test/features/player/` 全量回归通过
- [ ] 新文件零 Flutter 依赖

---

### REF-11 创建 player/domain/request_gate.dart

**来源**：重构计划 Phase 1 Day 1 | **优先级**：P0
**涉及文件**：新建 `lib/features/player/domain/request_gate.dart`
**依赖**：无

**实现要点**：
- 从 `player_provider.dart` 提取 `SerializedRequestGate`、`PlayerLoadStatus`、`TrackLoadStatus`、`TrackLoadResult`
- 纯 Dart 类，零 Flutter 依赖

**测试用例**：REF-11-T01 ~ REF-11-T04
- REF-11-T01: 单请求正常执行
- REF-11-T02: 并发请求 → 最新请求优先
- REF-11-T03: 排队请求被取代 → 返回 superseded
- REF-11-T04: 执行完成后自动启动排队请求

**验收标准**：
- [ ] `flutter test test/features/player/` 全量回归通过
- [ ] 新文件零 Flutter 依赖

---

### REF-12 创建 player/domain/media_control.dart

**来源**：重构计划 Phase 1 Day 1 | **优先级**：P1
**涉及文件**：新建 `lib/features/player/domain/media_control.dart`
**依赖**：无

**实现要点**：
- 从 `media_control_model.dart` 移入 `extractTitleFromPath()`、`mapHeadphoneAction()`
- 从 `player_provider.dart` 提取 `formatDuration()`
- 纯函数，零 Flutter 依赖

**测试用例**：REF-12-T01 ~ REF-12-T03
- REF-12-T01: extractTitleFromPath 各种路径格式
- REF-12-T02: mapHeadphoneAction 3 种映射
- REF-12-T03: formatDuration MM:SS 和 H:MM:SS

**验收标准**：
- [ ] `flutter test test/features/player/` 全量回归通过
- [ ] 新文件零 Flutter 依赖

---

### REF-13 创建 player/domain/background_playback.dart

**来源**：重构计划 Phase 1 Day 1 | **优先级**：P1
**涉及文件**：新建 `lib/features/player/domain/background_playback.dart`（移自 `lib/features/player/background_playback.dart`）
**依赖**：无

**实现要点**：
- 移入 `BackgroundPlaybackConfig`、`BackgroundPlaybackNotifier`
- 移入 `shouldContinueInBackground()`、`computePlaybackStateAfterLifecycle()`
- 纯 Dart StateNotifier，零平台依赖

**测试用例**：REF-13-T01 ~ REF-13-T04
- REF-13-T01: 媒体控制 play/pause/stop/toggle 状态转移
- REF-13-T02: 音频焦点 gained/lost/transient 转移
- REF-13-T03: 前后台切换对播放状态的影响
- REF-13-T04: isAudioActive/showPauseAction 派生属性

**验收标准**：
- [ ] `flutter test test/features/player/` 全量回归通过
- [ ] 新文件零平台依赖

---

### REF-14 创建 player/domain/playback_orchestrator.dart

**来源**：重构计划 Phase 1 Day 2 | **优先级**：P0
**涉及文件**：新建 `lib/features/player/domain/playback_orchestrator.dart`
**依赖**：REF-08, REF-09, REF-10, REF-11, REF-13

**实现要点**：
- 核心类 `PlaybackOrchestrator`，构造函数接收依赖接口
- 方法：`loadAndPlay()`、`skipToNext()`、`skipToPrevious()`、`selectQueueIndex()`、`removeTrack()`、`saveProgress()`
- 内部管理 `RequestGate`、自动保存定时器、processing 监听器
- 所有依赖通过构造函数注入，不读取 Riverpod provider

**测试用例**：REF-14-T01 ~ REF-14-T08
- REF-14-T01: loadAndPlay 正常流程 → loaded
- REF-14-T02: loadAndPlay 无连接 → failed
- REF-14-T03: loadAndPlay 无密码 → failed
- REF-14-T04: skipToNext → 保存进度 → 更新队列 → loadAndPlay
- REF-14-T05: skipToPrevious → 保存进度 → 更新队列 → loadAndPlay
- REF-14-T06: removeTrack 空队列 → stop
- REF-14-T07: removeTrack 当前曲目 → 下一曲
- REF-14-T08: removeTrack 非当前曲目 → 仅更新队列

**验收标准**：
- [ ] 所有测试用例通过
- [ ] 新文件零 Riverpod 依赖
- [ ] 纯 Dart 可直接 test()

---

### REF-15 重写 player_provider.dart 为薄胶水

**来源**：重构计划 Phase 1 Day 3 | **优先级**：P0
**涉及文件**：`lib/features/player/player_provider.dart`（大幅重写）
**依赖**：REF-14

**实现要点**：
- 新的 provider 只包含：`playbackOrchestratorProvider`、薄包装 provider、状态暴露 provider
- 移除所有业务逻辑，仅做依赖组装
- 文件从 1092 行缩减到 ~200 行

**测试用例**：REF-15-T01
- REF-15-T01: `flutter test test/features/player/` 全量回归通过

**验收标准**：
- [ ] 文件 < 300 行
- [ ] `flutter test test/features/player/` 全量回归通过
- [ ] `flutter analyze` 0 issues

---

### REF-16 更新 player_screen.dart 使用新 provider

**来源**：重构计划 Phase 1 Day 3 | **优先级**：P0
**涉及文件**：`lib/features/player/player_screen.dart`
**依赖**：REF-15

**实现要点**：
- 更新 import 路径
- 使用新的薄胶水 provider
- 保持 UI 行为不变

**测试用例**：REF-16-T01
- REF-16-T01: `flutter test test/features/player/` 全量回归通过

**验收标准**：
- [ ] `flutter test test/features/player/` 全量回归通过
- [ ] `flutter analyze` 0 issues

---

## 待实现 — 重构 Phase 2：Browser Domain 提取

### REF-17 创建 browser/domain/navigation_stack.dart

**来源**：重构计划 Phase 2 Day 1 | **优先级**：P0
**涉及文件**：新建 `lib/features/browser/domain/navigation_stack.dart`
**依赖**：无

**实现要点**：
- 从 `browser_provider.dart` 移入 `NavigationStackNotifier`
- 纯 Dart StateNotifier，零 Flutter 依赖

**测试用例**：REF-17-T01 ~ REF-17-T04
- REF-17-T01: push 追加路径
- REF-17-T02: pop 移除栈顶
- REF-17-T03: popTo 截断到目标
- REF-17-T04: 根目录 pop 无效

**验收标准**：
- [ ] `flutter test test/features/browser/` 全量回归通过
- [ ] 新文件零 Flutter 依赖

---

### REF-18 创建 browser/domain/cache_policy.dart

**来源**：重构计划 Phase 2 Day 1 | **优先级**：P0
**涉及文件**：新建 `lib/features/browser/domain/cache_policy.dart`
**依赖**：BUG-03

**实现要点**：
- 定义 `CacheEntry` 类（含 `lastAccessedAt` 字段）
- 实现 LRU 淘汰策略（按 lastAccessedAt 排序）
- 实现 TTL 过期检查（5 分钟）
- 纯 Dart，零 Flutter 依赖

**测试用例**：REF-18-T01 ~ REF-18-T05
- REF-18-T01: TTL 5 分钟内 → 命中
- REF-18-T02: TTL 超过 5 分钟 → 过期
- REF-18-T03: 容量 50 条 → 不淘汰
- REF-18-T04: 容量 51 条 → LRU 淘汰
- REF-18-T05: 访问旧条目 → 更新 lastAccessedAt → 不被淘汰

**验收标准**：
- [ ] `flutter test test/features/browser/` 全量回归通过
- [ ] 新文件零 Flutter 依赖

---

### REF-19 创建 browser/domain/directory_service.dart

**来源**：重构计划 Phase 2 Day 1 | **优先级**：P0
**涉及文件**：新建 `lib/features/browser/domain/directory_service.dart`
**依赖**：REF-17, REF-18

**实现要点**：
- 从 `browser_provider.dart` 移入目录加载逻辑、排序逻辑
- 接收 `IWebDavClient`、`ISecureStorage` 依赖
- 使用 `CachePolicy` 管理缓存

**测试用例**：REF-19-T01 ~ REF-19-T04
- REF-19-T01: 目录加载 → 缓存 → 排序
- REF-19-T02: 缓存命中 → 无网络请求
- REF-19-T03: 缓存过期 → 重新请求
- REF-19-T04: 排序变化 → 重新排序（无网络请求）

**验收标准**：
- [ ] `flutter test test/features/browser/` 全量回归通过
- [ ] 新文件零 Flutter 依赖

---

### REF-20 重写 browser_provider.dart 为薄胶水

**来源**：重构计划 Phase 2 Day 2 | **优先级**：P0
**涉及文件**：`lib/features/browser/browser_provider.dart`（大幅重写）
**依赖**：REF-19

**实现要点**：
- 新的 provider 只包含依赖组装和状态暴露
- 移除所有业务逻辑
- 文件从 495 行缩减到 ~150 行

**测试用例**：REF-20-T01
- REF-20-T01: `flutter test test/features/browser/` 全量回归通过

**验收标准**：
- [ ] 文件 < 200 行
- [ ] `flutter test test/features/browser/` 全量回归通过
- [ ] `flutter analyze` 0 issues

---

## 待实现 — 重构 Phase 3：Connection Domain 提取

### REF-21 创建 connection/domain/connection_validator.dart

**来源**：重构计划 Phase 3 | **优先级**：P0
**涉及文件**：新建 `lib/features/connection/domain/connection_validator.dart`
**依赖**：无

**实现要点**：
- 从 `connection_provider.dart` 和 `connection_screen.dart` 提取 URL 验证、表单校验逻辑
- 纯函数：`validateUrl()`、`validateRequired()`、`validateBasePath()`

**测试用例**：REF-21-T01 ~ REF-21-T04
- REF-21-T01: URL 验证 — 空值、格式错误、有效地址
- REF-21-T02: 用户名/密码必填验证
- REF-21-T03: basePath 默认值和格式验证
- REF-21-T04: DDNS 域名验证

**验收标准**：
- [ ] `flutter test test/features/connection/` 全量回归通过
- [ ] 新文件零 Flutter 依赖

---

### REF-22 创建 connection/domain/connection_service.dart

**来源**：重构计划 Phase 3 | **优先级**：P0
**涉及文件**：新建 `lib/features/connection/domain/connection_service.dart`
**依赖**：REF-21

**实现要点**：
- 从 `connection_provider.dart` 提取保存流程（原子性：DB + SecureStorage + 回滚）
- 提取删除流程（最后连接保护 + 自动激活）
- 提取切换流程（setActive 事务）

**测试用例**：REF-22-T01 ~ REF-22-T05
- REF-22-T01: 保存成功 → DB + SecureStorage 都写入
- REF-22-T02: SecureStorage 失败 → DB 回滚
- REF-22-T03: 删除最后连接 → LastConnectionException
- REF-22-T04: 删除活跃连接 → 自动激活另一个
- REF-22-T05: 切换连接 → 事务保证唯一活跃

**验收标准**：
- [ ] `flutter test test/features/connection/` 全量回归通过
- [ ] 新文件零 Flutter 依赖

---

### REF-23 重写 connection_provider.dart 为薄胶水

**来源**：重构计划 Phase 3 | **优先级**：P0
**涉及文件**：`lib/features/connection/connection_provider.dart`（重写）
**依赖**：REF-22

**实现要点**：
- 新的 provider 只包含依赖组装
- 移除所有业务逻辑

**测试用例**：REF-23-T01
- REF-23-T01: `flutter test test/features/connection/` 全量回归通过

**验收标准**：
- [ ] `flutter test test/features/connection/` 全量回归通过
- [ ] `flutter analyze` 0 issues

---

## 待实现 — 重构 Phase 4：其他 Feature Domain 提取

### REF-24 创建 progress/domain/progress_policy.dart

**来源**：重构计划 Phase 4 | **优先级**：P0
**涉及文件**：新建 `lib/features/progress/domain/progress_policy.dart`
**依赖**：无

**实现要点**：
- 从 `progress_dao.dart` 移出 `shouldSave()`、`shouldClear()` 静态方法
- 纯函数，零 Flutter 依赖

**测试用例**：REF-24-T01 ~ REF-24-T04
- REF-24-T01: shouldSave 边界测试（4999/5000）
- REF-24-T02: shouldClear 边界测试（durationMs-10001/durationMs-10000）
- REF-24-T03: 短文件保护（durationMs <= 10000）
- REF-24-T04: 未知时长保护（durationMs == null）

**验收标准**：
- [ ] `flutter test test/features/progress/` 全量回归通过
- [ ] 新文件零 Flutter 依赖

---

### REF-25 创建 progress/domain/progress_service.dart

**来源**：重构计划 Phase 4 | **优先级**：P1
**涉及文件**：新建 `lib/features/progress/domain/progress_service.dart`
**依赖**：REF-24

**实现要点**：
- 封装 5 个保存触发点的编排逻辑
- 封装恢复对话框的状态管理

**测试用例**：REF-25-T01 ~ REF-25-T03
- REF-25-T01: 5 个触发点分别调用 upsert
- REF-25-T02: 恢复对话框状态转移
- REF-25-T03: 倒计时归零自动选择

**验收标准**：
- [ ] `flutter test test/features/progress/` 全量回归通过

---

### REF-26 创建 playlist/domain/playlist_service.dart

**来源**：重构计划 Phase 4 | **优先级**：P1
**涉及文件**：新建 `lib/features/playlist/domain/playlist_service.dart`
**依赖**：无

**实现要点**：
- 从 `playlist_provider.dart` 提取 CRUD + 去重 + 导入导出逻辑
- 纯 Dart，通过接口访问 DAO

**测试用例**：REF-26-T01 ~ REF-26-T04
- REF-26-T01: 创建播放单
- REF-26-T02: 添加曲目去重
- REF-26-T03: 导出 JSON 格式正确
- REF-26-T04: 导入去重 + 容错

**验收标准**：
- [ ] `flutter test test/features/playlist/` 全量回归通过

---

### REF-27 创建 settings/domain/settings_service.dart

**来源**：重构计划 Phase 4 | **优先级**：P1
**涉及文件**：新建 `lib/features/settings/domain/settings_service.dart`
**依赖**：无

**实现要点**：
- 从 `settings_provider.dart` 提取主题、速度、步长的读写逻辑
- 纯 Dart，通过接口访问 SharedPreferences

**测试用例**：REF-27-T01 ~ REF-27-T03
- REF-27-T01: 主题读写持久化
- REF-27-T02: 默认速度读写
- REF-27-T03: 快进步长读写

**验收标准**：
- [ ] `flutter test test/features/settings/` 全量回归通过

---

### REF-28 移动 timer_service.dart 到 timer/domain/

**来源**：重构计划 Phase 4 | **优先级**：P1
**涉及文件**：`lib/core/services/timer_service.dart` → `lib/features/timer/domain/timer_service.dart`
**依赖**：无

**实现要点**：
- 移动文件到新位置
- 更新所有 import 路径
- timer_service.dart 已是纯逻辑，无需修改内容

**测试用例**：REF-28-T01
- REF-28-T01: `flutter test test/features/timer/` 全量回归通过

**验收标准**：
- [ ] `flutter test` 全量回归通过
- [ ] 旧位置文件已删除

---

## 待实现 — 重构 Phase 5：接口化 + 依赖注入

### REF-29 定义 core/contracts/ 接口

**来源**：重构计划 Phase 5 | **优先级**：P0
**涉及文件**：新建 4 个接口文件
**依赖**：REF-14, REF-19, REF-22

**实现要点**：
- `lib/core/contracts/audio_player_contract.dart` — IAudioPlayer 接口
- `lib/core/contracts/storage_contract.dart` — ISecureStorage 接口
- `lib/core/contracts/audio_handler_contract.dart` — IAudioHandler 接口
- `lib/core/contracts/database_contract.dart` — IConnectionDao, IProgressDao, IPlaylistDao 接口

**验收标准**：
- [ ] 所有接口文件创建完成
- [ ] 接口方法签名与现有实现一致

---

### REF-30 Data 层实现接口

**来源**：重构计划 Phase 5 | **优先级**：P0
**涉及文件**：`lib/core/database/dao/*.dart`、`lib/core/network/webdav_client.dart`
**依赖**：REF-29

**实现要点**：
- ConnectionDao implements IConnectionDao
- ProgressDao implements IProgressDao
- PlaylistDao implements IPlaylistDao
- WebDavClient implements IWebDavClient（已有）

**验收标准**：
- [ ] 所有 DAO 类实现对应接口
- [ ] `flutter analyze` 0 issues

---

### REF-31 创建 shared/di/providers.dart

**来源**：重构计划 Phase 5 | **优先级**：P0
**涉及文件**：新建 `lib/shared/di/providers.dart`
**依赖**：REF-30

**实现要点**：
- 唯一允许 import 多个 feature 的文件
- 通过接口将各 feature 连接起来
- 跨 feature 的 provider 桥接

**验收标准**：
- [ ] 文件创建完成
- [ ] 所有跨 feature 依赖通过此文件

---

### REF-32 更新所有 feature provider 使用接口

**来源**：重构计划 Phase 5 | **优先级**：P0
**涉及文件**：所有 feature 的 provider 文件
**依赖**：REF-31

**实现要点**：
- 更新所有 provider 文件，只依赖接口不依赖具体实现
- 消除跨 feature 直接 import

**验收标准**：
- [ ] `flutter test` 全量回归通过
- [ ] 跨 feature import 只存在于 `shared/di/providers.dart`

---

## 待实现 — 重构 Phase 6：集成测试补全

### TST-01 自动切歌流程集成测试

**来源**：测试缺口 (test.md §PLY-G01) | **优先级**：P0
**涉及文件**：`test/features/player/ply_05_test.dart`（追加）
**依赖**：无
**关联缺口**：PLY-G01

**测试用例**：TST-T01 ~ TST-T06
- TST-T01: sequential 模式 — 中间曲目完成 → 自动跳到下一首
- TST-T02: sequential 模式 — 最后一首完成 → 队列到头，stop+pause
- TST-T03: repeatOne 模式 — 曲目完成 → seek(0)+play 同曲重放
- TST-T04: repeatAll 模式 — 最后一首完成 → 循环到第一首
- TST-T05: shuffle 模式 — 曲目完成 → 随机跳到非当前索引
- TST-T06: 切歌前验证 upsertProgressProvider 被调用

**验收标准**：
- [ ] TST-T01 ~ T06 全部通过
- [ ] `flutter test` 全量回归通过

---

### TST-02 播放进度保存与恢复端到端链路

**来源**：测试缺口 (test.md §INT-G02) | **优先级**：P0
**涉及文件**：`test/features/progress/prg_test.dart`（追加）
**依赖**：无
**关联缺口**：INT-G02, PRG-G01

**测试用例**：TST-T07 ~ TST-T13
- TST-T07: 10s 周期保存 — fake_async 推进 30s → 3 次 upsert
- TST-T08: 暂停触发保存
- TST-T09: 切歌前保存
- TST-T10: 进入后台保存
- TST-T11: dispose 保存
- TST-T12: 重启恢复 → 构建带 startPositionMs 的队列
- TST-T13: upsertLatest 旧记录物理删除

**验收标准**：
- [ ] TST-T07 ~ T13 全部通过
- [ ] `flutter test` 全量回归通过

---

### TST-03 Timer 到期 → Player 暂停集成链路

**来源**：测试缺口 (test.md §INT-G03) | **优先级**：P0
**涉及文件**：`test/features/timer/timer_test.dart`（追加）
**依赖**：无
**关联缺口**：INT-G03, TMR-G02, TMR-G04

**测试用例**：TST-T14 ~ TST-T19
- TST-T14: 5min duration → 到期 → pause()
- TST-T15: duration 未到期 → 无操作
- TST-T16: afterCurrent → completed → pause()
- TST-T17: afterCurrent → 手动切歌 → timer 保持
- TST-T18: 到期后再次 checkExpired → false（幂等）
- TST-T19: afterCurrent 触发后再次 onTrackCompleted → false

**验收标准**：
- [ ] TST-T14 ~ T19 全部通过
- [ ] `flutter test` 全量回归通过

---

### TST-04 播放单曲目点击完整播放流程

**来源**：测试缺口 (test.md §INT-G04) | **优先级**：P0
**涉及文件**：`test/features/playlist/ply_13_test.dart`（追加）
**依赖**：无
**关联缺口**：INT-G04, PRG-G03

**测试用例**：TST-T20 ~ TST-T25
- TST-T20: 有进度 → 恢复对话框 → 继续 → 带 startPositionMs
- TST-T21: 有进度 → 恢复对话框 → 从头 → 不带 startPositionMs
- TST-T22: 无进度 → 直接播放
- TST-T23: positionMs < 5000 → 不弹对话框
- TST-T24: 倒计时归零 → 自动继续
- TST-T25: 多曲目点击任意曲目 → currentIndex 正确

**验收标准**：
- [ ] TST-T20 ~ T25 全部通过
- [ ] `flutter test` 全量回归通过

---

## 待实现 — 重构 Phase 7：测试覆盖审计 + 补全

### AUD-01 测试覆盖映射审计

**来源**：深度审查维度 1 | **优先级**：P1
**涉及文件**：所有测试文件
**依赖**：Phase 0-6 完成

**实现要点**：
- 逐条对照 state.md 每个转移 vs 现有测试
- 生成完整覆盖矩阵
- 标记所有缺测试的转移
- 补写缺失测试

**验收标准**：
- [ ] 覆盖率从 81% 提升到 95%+
- [ ] 所有标记的缺失转移都有测试

---

### AUD-02 边界值测试补全

**来源**：深度审查维度 2 | **优先级**：P1
**涉及文件**：多个测试文件
**依赖**：无

**实现要点**：
- Browser 缓存 TTL 边界（4:59/5:00）
- Browser 缓存容量边界（49/50/51）
- Player 超时边界（12s/15s）
- Timer 边界（startDuration(0)）

**测试用例**：AUD-02-T01 ~ AUD-02-T10
- AUD-02-T01: 缓存 age=4:59 → 命中
- AUD-02-T02: 缓存 age=5:00 → 过期
- AUD-02-T03: 缓存 49 条 → 不淘汰
- AUD-02-T04: 缓存 50 条 → 不淘汰
- AUD-02-T05: 缓存 51 条 → 淘汰 1 条
- AUD-02-T06: play() 轮询 11.8s 成功 → loaded
- AUD-02-T07: play() 轮询 12.0s 未开始 → failed
- AUD-02-T08: 屏幕超时 14.9s 完成 → loaded
- AUD-02-T09: 屏幕超时 15.0s → TimeoutException
- AUD-02-T10: startDuration(0) → 立即过期

**验收标准**：
- [ ] AUD-02-T01 ~ T10 全部通过

---

### AUD-03 错误注入测试补全

**来源**：深度审查维度 3 | **优先级**：P1
**涉及文件**：多个测试文件
**依赖**：无

**实现要点**：
- SecureStorage 写入失败回滚
- setAudioSource 失败
- 播放中连接断开
- 密码缺失恢复

**测试用例**：AUD-03-T01 ~ AUD-03-T06
- AUD-03-T01: SecureStorage 写入失败 → DB 回滚
- AUD-03-T02: setAudioSource 失败 → PlayerLoadState.error
- AUD-03-T03: play() 超时 → failed + stop
- AUD-03-T04: 播放中密码被清除 → 下次加载失败 → error
- AUD-03-T05: 恢复对话框期间页面销毁 → 无崩溃
- AUD-03-T06: DB 锁定时 upsert → 不崩溃

**验收标准**：
- [ ] AUD-03-T01 ~ T06 全部通过

---

### AUD-04 并发场景测试补全

**来源**：深度审查维度 4 | **优先级**：P0
**涉及文件**：多个测试文件
**依赖**：无

**实现要点**：
- 播放中切换连接
- 删除当前曲目 + 曲目完成同时触发
- 快速进出 PlayerScreen
- 定时到期 + 曲目完成同时到达

**测试用例**：AUD-04-T01 ~ AUD-04-T06
- AUD-04-T01: 播放中切换连接 → 队列清空 + 新加载正确
- AUD-04-T02: 删除当前曲目 + completed 同时 → 无双重触发
- AUD-04-T03: 快速进出 PlayerScreen → 无内存泄漏
- AUD-04-T04: dispose 时 loadAndPlay 在飞 → token 检查丢弃结果
- AUD-04-T05: 定时到期 + completed 同时 → 无双重 pause
- AUD-04-T06: App 后台恢复 + timer 到期 + 播放恢复 → 三重事件正确处理

**验收标准**：
- [ ] AUD-04-T01 ~ T06 全部通过

---

### AUD-05 状态可达性审计

**来源**：深度审查维度 5 | **优先级**：P2
**涉及文件**：所有测试文件
**依赖**：Phase 0-6 完成

**实现要点**：
- 确认每个状态都能被到达
- 移除不可达代码
- 确认 SelectingEmpty 状态不应存在（Bug 2 相关）

**验收标准**：
- [ ] 无死状态
- [ ] 无不可达代码

---

## 待实现 — 重构 Phase 8：文档更新 + CI 加固

### DOC-01 更新 CLAUDE.md 反映新架构

**来源**：重构计划 Phase 8 | **优先级**：P1
**涉及文件**：`CLAUDE.md`
**依赖**：Phase 1-5 完成

**实现要点**：
- 更新目录结构
- 更新架构分层说明
- 更新常用命令

**验收标准**：
- [ ] CLAUDE.md 与实际代码一致

---

### DOC-02 更新 architecture.md

**来源**：重构计划 Phase 8 | **优先级**：P1
**涉及文件**：`docs/design/architecture.md`
**依赖**：Phase 1-5 完成

**实现要点**：
- 更新架构图
- 更新模块说明
- 更新设计原则

**验收标准**：
- [ ] architecture.md 与实际代码一致

---

### CI-01 CI 增加架构边界检查

**来源**：重构计划 Phase 8 | **优先级**：P1
**涉及文件**：`.github/workflows/ci.yml`
**依赖**：Phase 5 完成

**实现要点**：
- 禁止跨 feature 直接 import（shared/di/providers.dart 除外）
- 增加测试覆盖率阈值
- 增加单文件行数上限检查（500 行）

**验收标准**：
- [ ] CI 流水线通过
- [ ] 违反架构边界的代码无法合并
