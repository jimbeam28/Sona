---

## [2026-05-17 17:24] B-2 - 队列弹窗改为可滚动列表（全屏与迷你栏）

**优先级**: P1
**关联问题**: BUG-4
**状态**: ✅ 成功

### 修改文件
- `lib/features/player/widgets/queue_sheet.dart` — 新增共享队列弹窗组件，使用 `DraggableScrollableSheet + ListView.builder` 承载长队列
- `lib/features/player/player_screen.dart` — 全屏播放器改为复用共享队列弹窗，统一长列表展示行为
- `lib/features/player/widgets/mini_player_bar.dart` — 迷你播放器改为复用共享队列弹窗，保持选曲与错误提示一致
- `test/features/player/ply_08_test.dart` — 补充长队列可滚动和点选后回调索引的 widget 测试

### 验证结果
- 通过: 3 / 总计: 3（work_items 检查项）
- `flutter analyze`：0 issues
- `flutter test test/features/player/ply_08_test.dart --plain-name "QueueSheet widget"`：通过
- `flutter test`：全量通过

### 备注
- 队列弹窗不再一次性把全部条目塞进 `Column`，长列表现在可以上下滑动，且全屏播放器与迷你播放器共享同一份实现。

## [2026-05-17 17:10] B-1 - 修复自定义定时确认按钮无响应

**优先级**: P1
**关联问题**: BUG-3
**状态**: ✅ 成功

### 修改文件
- `lib/features/timer/widgets/timer_button.dart` — 将自定义定时弹窗重构为独立有状态组件，稳定管理小时/分钟与确认按钮启用态
- `test/features/timer/timer_test.dart` — 补充 0:00 禁用确认与非 0 时长确认后启动定时的 widget 测试

### 验证结果
- 通过: 3 / 总计: 3（work_items 检查项）
- `flutter analyze`：0 issues
- `flutter test test/features/timer/timer_test.dart`：通过
- `flutter test`：全量通过

### 备注
- 自定义定时不再依赖 `StatefulBuilder + 局部变量`，确认按钮读取的是组件稳定状态，避免出现“已选择时长但确认无反应”。

---

## [2026-05-17 17:04] A-2 - 重构进度恢复入口，移除 5 秒自动弹窗导航竞态

**优先级**: P0
**关联问题**: BUG-2
**状态**: ✅ 成功

### 修改文件
- `lib/features/browser/browser_screen.dart` — 点歌改为直接设置队列并顺序导航，不再逐曲弹恢复对话框
- `lib/features/progress/progress_provider.dart` — 新增最近一次播放进度 provider，供启动恢复使用
- `lib/features/player/player_provider.dart` — 新增启动恢复与进度兜底逻辑，仅在当前队列当前曲目匹配时应用最近进度
- `lib/main.dart` — 启动阶段改为触发“恢复队列 + 恢复当前曲目进度”
- `test/features/player/ply_05_test.dart` — 补充启动恢复纯逻辑测试
- `test/features/progress/prg_test.dart` — 补充最近播放记录 provider 测试

### 验证结果
- 通过: 3 / 总计: 3（work_items 检查项）
- `flutter analyze`：0 issues
- `flutter test test/features/player/ply_05_test.dart test/features/progress/prg_test.dart`：通过
- `flutter test`：全量通过

### 备注
- 启动恢复只会把“最近一次播放记录”补到当前已恢复队列的当前曲目上；若进度越界或损坏，会回退到 `0` 避免黑屏或 seek 异常。

---

## [2026-05-17 16:53] A-1 - 串行化播放器加载状态，修复‘正在加载音频’卡住

**优先级**: P0
**关联问题**: BUG-1
**状态**: ✅ 成功

### 修改文件
- `lib/features/player/player_provider.dart` — 增加串行加载门闩、统一切歌/选曲 Provider 入口、为加载结果提供显式状态
- `lib/features/player/player_screen.dart` — 增加本地加载 token 和超时处理，避免过期请求覆盖最新 UI 状态
- `lib/features/player/widgets/mini_player_bar.dart` — 迷你播放器切歌与队列选曲改走统一 Provider 入口
- `test/features/player/ply_02_test.dart` — 补充串行加载门闩的并发/淘汰逻辑测试

### 验证结果
- 通过: 4 / 总计: 4（work_items 检查项）
- `flutter analyze`：0 issues
- `flutter test test/features/player/ply_02_test.dart`：通过
- `flutter test`：全量通过

### 备注
- Provider 层采用“串行执行 + 最新请求胜出”的方式，避免共享 `AudioPlayer` 上出现并发 `stop/setAudioSource/play`。

---

## [2026-05-16 10:30] A-1 - 修复播放页面重新加载逻辑

**优先级**: P0
**关联问题**: BUG-1, BUG-10
**状态**: ✅ 成功

### 修改文件
- `lib/features/player/player_screen.dart` — 添加 `_sourceMatchesQueue()` 辅助方法，修改 `initState` postFrameCallback 增加队列匹配检测

### 验证结果
- 通过: 4 / 总计: 4
- 静态分析: No issues found
- 测试: 全部 299 tests passed

### 备注
核心修复：侧滑返回后 AudioPlayer 仍在播放旧曲目，新 PlayerScreen 跳过 _loadAndPlay() 导致切换失效。现在通过对比 AudioPlayer 当前音频源 URI 与队列曲目路径，确保不匹配时强制重新加载。

---

## [2026-05-16 12:15] D-2, E-1, E-2, E-3, F-1, F-2, F-3, F-4 — 批量完成剩余修复

**优先级**: P0~P2
**关联问题**: BUG-13~20
**状态**: ✅ 成功

### 修改文件
- `lib/features/player/player_provider.dart` — E-2: loadAndPlayProvider 连接一致性检查
- `lib/features/player/player_screen.dart` — E-1: dispose 时 invalidate progress 缓存；F-4: 速度选择器支持记忆
- `lib/features/player/widgets/mini_player_bar.dart` — D-2: 队列选歌失败 SnackBar；F-3: 迷你栏定时显示
- `lib/features/browser/browser_provider.dart` — E-2: lastQueueConnectionIdProvider；F-2: 队列恢复连接校验
- `lib/features/browser/browser_screen.dart` — E-2: 队列创建时记录连接 ID
- `lib/features/settings/settings_provider.dart` — F-4: rememberSpeed 设置
- `lib/features/settings/settings_screen.dart` — F-4: 记住播放速度开关
- `test/features/settings/settings_test.dart` — F-4: 适配新增控件

### 验证结果
- 全部 work_items 通过
- 测试: 全部 535 tests passed

---

## [2026-05-16 12:00] D-1 - 提取统一音频加载入口

**优先级**: P0
**关联问题**: BUG-12
**状态**: ✅ 成功

### 修改文件
- `lib/features/player/player_provider.dart` — 新增 loadAndPlayProvider、skipToNextProvider、saveProgressProvider、cancelPlaybackSubscriptionsProvider 等统一入口和生命周期管理 Provider
- `lib/features/player/player_screen.dart` — _loadAndPlay() 简化为调用统一入口+UI状态管理，dispose() 使用 cancelPlaybackSubscriptionsProvider
- `lib/features/player/widgets/mini_player_bar.dart` — _NextButton 和 _showQueueSheet 委托给 loadAndPlayProvider，消除代码重复

### 验证结果
- 通过: 8 / 总计: 8
- 静态分析: No issues found
- 测试: 全部 535 tests passed

### 备注
这是最关键的架构改进。迷你栏切歌和队列选择现在通过统一的 loadAndPlayProvider 执行完整的加载流程，包括 listener 注册（自动下一曲）、auto-save 定时器、pause-save 监听器、默认速度应用和通知栏更新。解决了迷你栏操作绕过 _loadAndPlay() 导致后台功能崩塌的根因。

---

## [2026-05-16 11:15] B-6 - 播放界面重新布局 + C-1 图标统一 + C-2 触控优化

**优先级**: P1/P2
**关联问题**: BUG-9, BUG-2, BUG-8
**状态**: ✅ 成功

### 修改文件
- `lib/features/player/player_screen.dart` — B-6: 倍速/定时/模式移至进度条上方水平排列；C-1: 所有 seek 按钮统一显示图标+时间标签
- `lib/features/player/widgets/mini_player_bar.dart` — C-2: 按钮 iconSize 增大 + VisualDensity.standard

### 验证结果
- 通过: 全部
- 测试: 全部 535 tests passed

---

## [2026-05-16 11:10] B-4 - 迷你播放栏加高 + 增加音乐列表按钮

**优先级**: P1
**关联问题**: BUG-8
**状态**: ✅ 成功

### 修改文件
- `lib/features/player/widgets/mini_player_bar.dart` — 高度 56→64，添加队列列表按钮 + _showQueueSheet 函数

### 验证结果
- 通过: 4 / 总计: 4
- 测试: 全部 535 tests passed

---

## [2026-05-16 11:05] B-3 - 定时停止 UI 修改：删除 15 分钟、添加自定义时间

**优先级**: P1
**关联问题**: BUG-7
**状态**: ✅ 成功

### 修改文件
- `lib/features/timer/widgets/timer_button.dart` — 删除"15 分钟"选项，添加"自定义"选项 + 双滚轮时间选择器
- `test/features/timer/timer_test.dart` — 更新 widget 测试期望

### 验证结果
- 通过: 5 / 总计: 5
- 测试: 全部 535 tests passed

### 备注
自定义时间选择器使用 ListWheelScrollView 实现，左侧 0-23 小时，右侧 0-59 分钟。取消按钮灰色文字，确认按钮主题色。startDurationTimerProvider 已支持任意分钟数。

---

## [2026-05-16 11:00] B-2 - 移除定时停止触发后的 SnackBar + B-5 - 定时图标改为钟表

**优先级**: P1
**关联问题**: BUG-5, BUG-9
**状态**: ✅ 成功

### 修改文件
- `lib/features/player/player_screen.dart` — B-2: 删除两处 SnackBar 调用；B-5: _TimerControl 图标 Icons.hourglass_bottom → Icons.timer

### 验证结果
- 通过: 6 / 总计: 6
- 测试: 全部 535 tests passed

---

## [2026-05-16 10:55] B-1 - 定时停止显示格式改为 MM:SS

**优先级**: P1
**关联问题**: BUG-4
**状态**: ✅ 成功

### 修改文件
- `lib/core/services/timer_service.dart` — formatRemaining() 改为 MM:SS 格式
- `test/features/timer/timer_test.dart` — 更新测试期望匹配新格式

### 验证结果
- 通过: 3 / 总计: 3
- 测试: 全部 535 tests passed

---

## [2026-05-16 10:50] A-4 - 修复设置默认播放速度后新曲目不生效

**优先级**: P0
**关联问题**: BUG-10
**状态**: ✅ 成功

### 修改文件
- `lib/features/player/player_provider.dart` — setDefaultSpeedProvider 中同步更新 currentSpeedProvider
- `test/features/player/ply_07_test.dart` — 更新测试期望以匹配新行为

### 验证结果
- 通过: 4 / 总计: 4
- 静态分析: No issues found
- 测试: 全部 535 tests passed

### 备注
设置默认速度后立即同步 currentSpeedProvider，播放 UI 上的速度显示实时反映变更。AudioPlayer 的实际速度在下次 _loadAndPlay() 时应用（由 A-1 的队列匹配检测触发或选择新曲目时）。

---

## [2026-05-16 10:45] A-5 - 修复 seekStep 图标动态显示步长

**优先级**: P0
**关联问题**: BUG-2, BUG-11
**状态**: ✅ 成功

### 修改文件
- `lib/features/player/player_screen.dart` — 添加 _buildSeekButton() 方法，对 15s/60s 显示图标+时间标签；修改快退/快进按钮使用新方法

### 验证结果
- 通过: 4 / 总计: 4
- 静态分析: No issues found
- 测试: 全部 535 tests passed

### 备注
15s 和 60s 步长无对应的 Material Icon（只有 5/10/30 有带数字的图标），改为通用图标+文字标签的组合按钮。5/10/30 保持使用原生带数字 Material Icon。

---

## [2026-05-16 10:40] A-3 - 修复启动 app 后恢复的队列无音频源

**优先级**: P0
**关联问题**: BUG-6
**状态**: ✅ 成功

### 修改文件
- `lib/features/browser/browser_provider.dart` — restoreQueueFromPrefsProvider 中增加预加载音频源逻辑
- `lib/features/player/widgets/mini_player_bar.dart` — _PlayPauseButton 增加无源时的守卫跳转

### 验证结果
- 通过: 4 / 总计: 4
- 静态分析: No issues found
- 测试: 全部 535 tests passed

### 备注
启动时恢复的播放队列仅包含元数据，AudioPlayer 中无音频源导致点击播放无声音。修复后恢复队列时预加载音频源，迷你播放栏播放按钮在无源时引导进入播放页面触发加载。

---

## [2026-05-16 10:35] A-2 - 修复曲目播完不自动下一曲

**优先级**: P0
**关联问题**: BUG-3
**状态**: ✅ 成功

### 修改文件
- `lib/features/player/player_screen.dart` — 将 processingStateStream 监听注册移到 player.stop() 之前，确保捕获完整的 completed 事件

### 验证结果
- 通过: 3 / 总计: 3
- 静态分析: No issues found
- 测试: 全部 299 tests passed

### 备注
原代码在 await player.play() 之后才注册 processingStateStream 监听，此时 player.stop() 和 setAudioSource 已完成，可能错过 completed 状态。修复后将监听提前到 stop 之前，覆盖完整生命周期。

---

## [2026-05-12 12:00] C-1 - CON-05/CON-06 补充滑动操作

**优先级**: P2
**关联问题**: CON-05, CON-06
**状态**: ✅ 成功

### 修改文件
- `pubspec.yaml` — 添加 flutter_slidable 依赖
- `lib/features/connection/connection_list_screen.dart` — ListTile 包装 Slidable，右滑显示编辑/删除

### 验证结果
- 通过: 3 / 总计: 3（work_items 检查项）
- 静态分析通过，0 issues

### 备注
- 三点菜单保持作为备用入口
- flutter_slidable ^4.0.3，使用 ActionPane + DrawerMotion

---

## [2026-05-12 11:30] B-2 - 播放队列查看 UI

**优先级**: P1
**关联问题**: PLY-05
**状态**: ✅ 成功

### 修改文件
- `lib/features/player/player_screen.dart` — AppBar 添加队列按钮，showModalBottomSheet 展示文件列表，当前项高亮，点击切换

---

## [2026-05-12 11:30] B-3 - 播放队列持久化（重启恢复）

**优先级**: P1
**关联问题**: PLY-05
**状态**: ✅ 成功

### 修改文件
- `lib/features/browser/browser_provider.dart` — 添加 persistQueueOnChangeProvider 和 restoreQueueFromPrefsProvider
- `lib/features/browser/browser_screen.dart` — 激活队列持久化监听
- `lib/main.dart` — 启动时恢复持久化队列

### 备注
- NasFile 重建为最小化对象（仅 path + name），足够播放恢复
- 数据损坏时静默忽略

---

## [2026-05-12 11:00] A-1 - 实现 AudioHandler（后台播放 + 媒体控件）

**优先级**: P0
**关联问题**: PLY-03, PLY-04
**状态**: ✅ 成功

### 修改文件
- `lib/core/services/audio_handler.dart` — 新建 NasAudioHandler extends BaseAudioHandler，同步 player 状态到通知栏
- `lib/main.dart` — AudioService.init 初始化 handler，创建 AudioPlayer，override providers
- `android/app/src/main/AndroidManifest.xml` — 新建，添加 FOREGROUND_SERVICE 和 AudioService
- `lib/features/player/player_provider.dart` — 添加 audioHandlerProvider
- `lib/features/player/player_screen.dart` — 接入 handler：wire 回调、更新 mediaItem、dispose 清理

### 验证结果
- 通过: 5 / 总计: 5（work_items 检查项）
- 静态分析通过，零新增 error/warning

### 备注
- Handler 通过回调模式委托队列导航给 Riverpod 层，避免循环依赖
- 通知栏显示三按钮：上首、播放/暂停、下首
- 耳机按键通过系统标准 MediaSession 回调自动处理

---

## [2026-05-12 10:15] C-2 - 时间格式补齐为三段式

**优先级**: P2
**关联问题**: PLY-02
**状态**: ✅ 成功

### 修改文件
- `lib/features/player/player_provider.dart` — formatDuration 不足 1 小时时加 "0:" 前缀

---

## [2026-05-12 10:15] C-3 - 调速后同步 currentSpeedProvider

**优先级**: P2
**关联问题**: PLY-07
**状态**: ✅ 成功

### 修改文件
- `lib/features/player/player_screen.dart` — _SpeedControl 调速后同步更新 currentSpeedProvider

---

## [2026-05-12 10:15] C-4 - 表单层添加 URL 格式前置校验

**优先级**: P2
**关联问题**: CON-01
**状态**: ✅ 成功

### 修改文件
- `lib/features/connection/widgets/connection_form.dart` — _validateUrl 添加 normaliseWebDavUrl + isValidWebDavUrl 格式校验

---

## [2026-05-12 10:10] B-1 - 切换连接后清除浏览器缓存

**优先级**: P1
**关联问题**: CON-04
**状态**: ✅ 成功

### 修改文件
- `lib/features/connection/connection_list_screen.dart` — _switchConnection 切换成功后 invalidate directoryCacheProvider 和 navigationStackProvider

### 验证结果
- 通过: 3 / 总计: 3（work_items 检查项）
- 静态分析通过，0 issues

### 备注
- 避免循环依赖：清除逻辑放在 UI 层 connection_list_screen 而非 connection_provider
- navigationStackProvider 重置确保不携带旧连接路径

---

## [2026-05-12 10:05] B-5 - 修复含子路径连接 URL 的音频源构建

**优先级**: P1
**关联问题**: PLY-01
**状态**: ✅ 成功

### 修改文件
- `lib/features/player/player_screen.dart` — 将 AudioSourceBuilder.build 替换为 buildWithBasePath，统一处理根路径和子路径

### 验证结果
- 通过: 1 / 总计: 1（work_items 检查项）
- 静态分析通过，无新增 warning

### 备注
- buildWithBasePath 在根路径时与 build 等价，在含子路径时保留 base URL 的路径部分

---

## [2026-05-12 10:00] B-4 - 消除目录进度加载竞争窗口

**优先级**: P1
**关联问题**: BRW-04, PRG-02
**状态**: ✅ 成功

### 修改文件
- `lib/features/browser/browser_screen.dart` — onFileTap 改为 async，await loadProgressForDirectoryProvider.future 后再读取 playProgressProvider

### 验证结果
- 通过: 3 / 总计: 3（work_items 检查项）
- 静态分析通过，无新增 warning

### 备注
- FutureProvider.family 缓存确保重复 await 同一 path 不触发重复请求
- discarded_futures 警告通过 // ignore 注释抑制

---

## [2026-05-11 12:20] A-2 - PlayerScreen 添加上一首/下一首按钮

**优先级**: P0
**关联问题**: PLY-02
**状态**: ✅ 成功

### 修改文件
- `lib/features/player/player_screen.dart` — _PlaybackControls 布局改为五按钮，添加上一首/下一首，根据 previousIndex/nextIndex 控制 disabled 状态

### 验证结果
- 通过: 3 / 总计: 3（work_items 检查项）
- 静态分析通过，无新增 warning

### 备注
- _playPrevious/_playNext 复用 _saveProgress + 队列更新 + _loadAndPlay 模式
- 按钮 disabled 时灰色显示（color: Colors.grey）

---

## [2026-05-11 12:15] A-3 - 实现播放进度自动保存（五个触发点）

**优先级**: P0
**关联问题**: PRG-01
**状态**: ✅ 成功

### 修改文件
- `lib/features/player/player_screen.dart` — 添加五个触发点：①10s定时保存 ②暂停保存 ③切曲保存 ④后台保存 ⑤dispose保存

### 验证结果
- 通过: 5 / 总计: 5（work_items 检查项）
- 静态分析通过，无新增 warning

### 备注
- 混入 WidgetsBindingObserver 监听 AppLifecycleState.paused
- _saveProgress 包含完整的 null guard（queue/conn/id）
- 暂停检测通过 _wasPlaying 标志追踪 playing→paused 转换

---

## [2026-05-11 12:10] A-4 - TMR-02 接入 processingStateStream 触发「播完当前」

**优先级**: P0
**关联问题**: TMR-02
**状态**: ✅ 成功

### 修改文件
- `lib/features/player/player_screen.dart` — 添加 processingStateStream 监听，completed 时调用 onTrackCompletedProvider，未触发定时则自动播放下一首

### 验证结果
- 通过: 4 / 总计: 4（work_items 检查项）
- 静态分析通过，无新增 warning

### 备注
- onTrackCompletedProvider 和 _playNext 均已实现
- processingStateStream 订阅在 _loadAndPlay 末尾设置，dispose 中取消

---

## [2026-05-11 12:05] A-6 - PRG-04 添加长按清除进度 UI 入口

**优先级**: P0
**关联问题**: PRG-04
**状态**: ✅ 成功

### 修改文件
- `lib/features/browser/widgets/file_list_item.dart` — AudioFileListTile 添加 onLongPress 参数
- `lib/features/browser/browser_screen.dart` — _FileList 添加 onFileLongPress 回调，BrowserScreen 中实现长按弹出清除进度菜单

### 验证结果
- 通过: 3 / 总计: 3（work_items 检查项）
- 静态分析通过，无新增 warning

### 备注
- clearProgressProvider 已预先实现，仅需接入 UI 层
- 长按有进度的文件弹出底部菜单，显示文件名和已保存进度，确认后清除

---

## [2026-05-11 12:00] A-5 - TMR-05 添加定时到期的周期检查

**优先级**: P0
**关联问题**: TMR-05
**状态**: ✅ 成功

### 修改文件
- `lib/features/player/player_screen.dart` — 添加 Timer.periodic 每秒检查定时到期，到期后暂停播放并显示 SnackBar

### 验证结果
- 通过: 3 / 总计: 3（work_items 检查项）
- 静态分析通过，无新增 warning

### 备注
- `checkTimerExpiryProvider` 和 `TimerService.checkExpired()` 已预先实现，仅需接入调用

---

## [2026-05-10 16:11] CON-01 - 添加 WebDAV 连接

**模块**: Connection
**状态**: ✅ 成功

### 实现文件
- `lib/features/connection/connection_screen.dart` — 连接配置页面与提交流程
- `lib/features/connection/widgets/connection_form.dart` — 表单字段、校验与交互状态展示
- `lib/features/connection/connection_provider.dart` — 连接验证状态管理与保存流程
- `lib/core/network/webdav_client.dart` — WebDAV 连接验证调用与结果映射
- `lib/core/database/dao/connection_dao.dart` — 连接配置持久化访问
- `lib/shared/models/connection_config.dart` — 连接配置模型与默认值逻辑

### 测试文件
- `test/features/connection/con_01_test.dart` — 测试用例 16 个（CON-T01~T09, CON-T35~T41）

### 测试结果
- 通过: 16 / 总计: 16

### 备注
- 为完成测试运行，将 `pubspec.yaml` 中 `sqflite_ffi` 更正为 `sqflite_common_ffi`。

---

## [2026-05-10 16:20] CON-02 - 连接验证

**模块**: Connection
**状态**: ✅ 成功

### 实现文件
- `lib/features/connection/connection_provider.dart` — 添加重入保护（防重复点击）和 startupValidationProvider（启动自动验证）
- `lib/main.dart` — OnboardingPage 集成 startupValidationProvider，根据验证结果路由跳转
- `lib/features/connection/connection_screen.dart` — 显示启动验证失败的警告横幅

### 测试文件
- `test/features/connection/con_02_test.dart` — 测试用例 8 个（CON-T10 ~ CON-T17）

### 测试结果
- 通过: 8 / 总计: 8

### 备注
- F-009 和 F-010 已由 CON-01 实现，CON-02 补充了重入保护和启动自动验证逻辑
- 启动自动验证在 OnboardingPage 中触发，验证失败时重定向到连接页面供用户重新配置

---

## [2026-05-10 16:25] CON-03 - 连接配置持久化

**模块**: Connection
**状态**: ✅ 成功

### 实现文件
- （F-008 ConnectionDao 和 F-011 密码安全存储已由 CON-01 实现，CON-03 仅新增测试）

### 测试文件
- `test/features/connection/con_03_test.dart` — 测试用例 7 个（CON-T18 ~ CON-T24）

### 测试结果
- 通过: 7 / 总计: 7

### 备注
- 使用 sqflite_common_ffi 内存数据库进行 DAO 单元测试
- CON-T23 验证密码列存储引用 key 而非明文密码

---

## [2026-05-10 16:30] CON-04 - 切换当前连接

**模块**: Connection
**状态**: ✅ 成功

### 实现文件
- `lib/features/connection/connection_list_screen.dart` — 连接列表管理页面（新建）
- `lib/features/connection/connection_provider.dart` — 添加 switchActiveConnectionProvider
- `lib/features/connection/connection_screen.dart` — 添加管理连接入口按钮
- `lib/main.dart` — 添加 /connections 路由

### 测试文件
- `test/features/connection/con_04_test.dart` — 测试用例 3 个（CON-T25 ~ CON-T27）

### 测试结果
- 通过: 34 / 总计: 34（全部 Connection 模块测试）

### 备注
- 连接列表页面为 CON-05/CON-06 的编辑/删除功能预留了 UI 结构

---

## [2026-05-10 16:37] CON-05 - 编辑连接配置

**模块**: Connection
**状态**: ✅ 成功

### 实现文件
- `lib/features/connection/connection_edit_screen.dart` — 编辑连接页面（新建）
- `lib/features/connection/connection_provider.dart` — 添加 ConnectionUpdater
- `lib/features/connection/widgets/connection_form.dart` — 支持预填初始值和可选密码
- `lib/features/connection/connection_list_screen.dart` — 添加弹出菜单（编辑/删除）
- `lib/main.dart` — 添加 /connections/edit/:id 路由

### 测试文件
- `test/features/connection/con_05_test.dart` — 测试用例 4 个（CON-T28 ~ CON-T30 + 密码更新）

### 测试结果
- 通过: 38 / 总计: 38（全部 Connection 模块测试）

### 备注
- 修改 URL/用户名/密码/基础路径后必须重新验证才能保存
- 仅修改显示名称无需重新验证
- ConnectionForm 支持 passwordRequired=false 用于编辑模式（留空保持原密码）

---

## [2026-05-10 16:43] CON-06 - 删除连接配置

**模块**: Connection
**状态**: ✅ 成功

### 实现文件
- `lib/core/database/dao/connection_dao.dart` — 增强 delete 方法：级联删除进度、末连接保护、自动激活
- `lib/features/connection/connection_provider.dart` — 添加 deleteConnectionProvider
- `lib/features/connection/connection_list_screen.dart` — 实现删除确认对话框和保护逻辑

### 测试文件
- `test/features/connection/con_06_test.dart` — 测试用例 5 个（CON-T31 ~ CON-T34 + Provider 集成）

### 测试结果
- 通过: 43 / 总计: 43（全部 Connection 模块测试）

### 备注
- 删除连接时级联删除 play_progress 记录（try-catch 包裹，progress 表未创建也不影响）
- 只剩一个连接时抛出 LastConnectionException 阻止删除
- 删除活跃连接后自动激活剩余第一个连接

---

## [2026-05-10 16:52] BRW-01 - 目录列表加载

**模块**: Browser
**状态**: ✅ 成功

### 实现文件
- `lib/shared/models/nas_file.dart` — 文件/目录数据模型与音频类型分类（新建）
- `lib/core/network/webdav_client.dart` — 添加 listDirectory PROPFIND 方法与 XML 解析
- `lib/features/browser/browser_provider.dart` — 目录内容 Provider 与导航栈管理（新建）
- `lib/features/browser/browser_screen.dart` — 文件浏览页面：骨架屏/错误/空/列表四态（新建）
- `lib/features/browser/widgets/file_list_item.dart` — 目录行与音频文件行组件（新建）
- `lib/main.dart` — /browser 路由替换为 BrowserScreen

### 测试文件
- `test/features/browser/brw_01_test.dart` — 测试用例 13 个（BRW-T01~T09 + BRW-T43~T46）

### 测试结果
- 通过: 56 / 总计: 56（Connection 43 + Browser 13）

### 备注
- PROPFIND XML 207 响应手动解析（未引入 xml 包）
- 支持 8 种音频格式过滤和分类（music/audiobook）
- 文件名特殊字符（空格、中文、括号）正确解析

---

## [2026-05-10 16:58] BRW-02 - 目录导航（进入/返回）

**模块**: Browser
**状态**: ✅ 成功

### 实现文件
- `lib/features/browser/widgets/breadcrumb_bar.dart` — 面包屑导航栏：路径展示、溢出折叠、点击跳转（新建）
- `lib/features/browser/browser_screen.dart` — 集成 BreadcrumbBar，PopScope 拦截返回键，目录点击导航

### 测试文件
- `test/features/browser/brw_02_test.dart` — 测试用例 12 个（BRW-T10 ~ BRW-T17）

### 测试结果
- 通过: 68 / 总计: 68（Connection 43 + Browser 25）

### 备注
- computeBreadcrumbLayout 作为纯函数导出，便于单元测试
- 面包屑始终显示根目录和尽可能多的右侧段，中间段折叠为 "..."+ 弹出菜单
- NavigationStackNotifier 在 BRW-01 中已实现，BRW-02 增强了 UI 层

---

## [2026-05-10 17:03] BRW-03 - 音频文件过滤

**模块**: Browser
**状态**: ✅ 成功

### 实现文件
- `lib/features/browser/widgets/file_list_item.dart` — AudioFileListTile 添加 progressPercentage 参数和进度条渲染

### 测试文件
- `test/features/browser/brw_03_test.dart` — 测试用例 9 个（BRW-T18 ~ BRW-T22 + BRW-T47 + BRW-T49）

### 测试结果
- 通过: 77 / 总计: 77（Connection 43 + Browser 34）

### 备注
- 音频分类逻辑（classifyType）在 BRW-01 中已完整实现
- .m4b 扩展名、"有声书"/"audiobook"关键词 → audiobook ；其他 → music
- 关键词匹配不区分大小写

---

## [2026-05-10 17:10] BRW-04 - 选择文件播放

**模块**: Browser
**状态**: ✅ 成功

### 实现文件
- `lib/shared/models/play_queue.dart` — 播放队列模型（新建）
- `lib/shared/models/play_progress.dart` — 播放进度模型（新建）
- `lib/features/browser/browser_provider.dart` — 添加 currentPlayQueueProvider 和 playProgressProvider
- `lib/features/browser/browser_screen.dart` — 音频文件点击：构建队列、进度恢复对话框、导航到播放器
- `lib/features/player/player_screen.dart` — 播放器占位页面（新建）
- `lib/main.dart` — 添加 /player 路由

### 测试文件
- `test/features/browser/brw_04_test.dart` — 测试用例 9 个（BRW-T23 ~ BRW-T28）

### 测试结果
- 通过: 86 / 总计: 86（Connection 43 + Browser 43）

### 备注
- PlayProgress 模型为 Progress 模块预留（formattedPosition, percentage）
- currentPlayQueueProvider 使用 StateProvider 存储队列，Player 模块可直接读取
- 进度恢复对话框支持继续播放（带入 startPositionMs）和从头播放入口

---

## [2026-05-10 17:16] BRW-05 - 目录内容缓存

**模块**: Browser
**状态**: ✅ 成功

### 实现文件
- `lib/features/browser/browser_provider.dart` — 添加 directoryCacheProvider 和 clearDirectoryCacheProvider

### 测试文件
- `test/features/browser/brw_05_test.dart` — 测试用例 5 个（BRW-T29 ~ BRW-T33）

### 测试结果
- 通过: 91 / 总计: 91（Connection 43 + Browser 48）

### 备注
- 缓存 key 为 "connectionId:path"，不同连接缓存隔离
- clearDirectoryCacheProvider 供下拉刷新（BRW-06）使用

---

## [2026-05-10 17:21] BRW-06 - 下拉刷新

**模块**: Browser
**状态**: ✅ 成功

### 实现文件
- `lib/features/browser/browser_screen.dart` — 添加 RefreshIndicator 包裹文件列表

### 测试文件
- `test/features/browser/brw_06_test.dart` — 测试用例 3 个（BRW-T34 ~ BRW-T36）

### 测试结果
- 通过: 94 / 总计: 94（Connection 43 + Browser 51）

### 备注
- 下拉刷新清除缓存并重新加载，刷新失败时保留旧列表

---

## [2026-05-10 17:27] BRW-07 - 文件排序

**模块**: Browser
**状态**: ✅ 成功

### 实现文件
- `lib/features/browser/browser_provider.dart` — 添加 SortOption 枚举、SortOptionNotifier、sortFiles 函数
- `lib/features/browser/browser_screen.dart` — 添加排序按钮和弹出菜单
- `lib/main.dart` — 初始化 SharedPreferences 注入 ProviderScope

### 测试文件
- `test/features/browser/brw_07_test.dart` — 测试用例 8 个（BRW-T37 ~ BRW-T42 + BRW-T48 + BRW-T50）

### 测试结果
- 通过: 102 / 总计: 102（Connection 43 + Browser 59）

### 备注
- 排序选项持久化到 SharedPreferences，首次启动默认名称升序
- 目录始终在文件前面，不论排序方式
- Browser 模块全部 7 个功能实现完成

---

## [2026-05-10 17:35] PLY-01 - 音频流式播放

**模块**: Player
**状态**: ✅ 成功

### 实现文件
- `lib/core/services/audio_source_builder.dart` — WebDAV 音频源构建：Basic Auth、URL 编码（新建）
- `lib/features/player/player_provider.dart` — AudioPlayer Provider + PlayerLoadState（新建）
- `lib/features/player/player_screen.dart` — 完整播放器页面：播放/暂停、进度、错误处理
- `lib/main.dart` — /player 路由更新为 PlayerScreen

### 测试文件
- `test/features/player/ply_01_test.dart` — 测试用例 29 个（PLY-T01 ~ PLY-T07 + helpers）

### 测试结果
- 通过: 131 / 总计: 131（Connection 43 + Browser 59 + Player 29）

### 备注
- AudioSource 通过 just_audio 的 AudioSource.uri 自定义 headers 实现 Basic Auth
- 路径段级别 URL 编码支持空格、中文、特殊字符
- PlayerLoadState 状态机：idle → loading → ready | error（含 auth 错误标记）

---

## [2026-05-10 17:43] PLY-02 - 基础播放控制

**模块**: Player
**状态**: ✅ 成功

### 实现文件
- `lib/features/player/player_provider.dart` — 添加 clampSeek/skipForward/skipBackward 工具函数、seekStepProvider、speedOptions
- `lib/features/player/player_screen.dart` — 进度条滑块、播放控制按钮、速度选择器、时间显示

### 测试文件
- `test/features/player/ply_02_test.dart` — 测试用例 71 个（PLY-T08 ~ PLY-T19 + PLY-T55 ~ PLY-T60）

### 测试结果
- 通过: 202 / 总计: 202（Connection 43 + Browser 59 + Player 100）

### 备注
- 快进/快退逻辑使用纯函数实现，便于单元测试
- 进度滑块处理拖动状态避免流抖动
- 速度选择器支持 6 个档位（0.5x ~ 2.0x）

---

## [2026-05-10 17:49] PLY-03 - 后台播放

**模块**: Player
**状态**: ✅ 成功

### 实现文件
- `lib/features/player/background_playback.dart` — 后台播放状态机模型（新建）
- `lib/features/player/player_provider.dart` — 添加 BackgroundPlaybackNotifier 和生命周期处理

### 测试文件
- `test/features/player/ply_03_test.dart` — 测试用例 55 个（PLY-T20 ~ PLY-T23 + 音频焦点）

### 测试结果
- 通过: 257 / 总计: 257（Connection 43 + Browser 59 + Player 155）

### 备注
- BackgroundPlaybackConfig 纯函数模型：生命周期转换、通知栏控制、音频焦点
- shouldContinueInBackground 纯净函数决定生命周期行为
- 不依赖 audio_service 原生平台支持即可完整测试逻辑层

---

## [2026-05-10 17:54] PLY-04 - 锁屏/通知栏媒体控件

**模块**: Player
**状态**: ✅ 成功

### 实现文件
- `lib/features/player/media_control_model.dart` — 耳机线控映射、曲目标题提取、封面检测（新建）

### 测试文件
- `test/features/player/ply_04_test.dart` — 测试用例 35 个（PLY-T24 ~ PLY-T29 + 模型测试）

### 测试结果
- 通过: 292 / 总计: 292

### 备注
- HeadphoneAction → MediaAction 映射：单击=播放/暂停，双击=下一首，三击=上一首
- extractTitleFromPath 处理隐藏文件、双扩展名、CJK 字符等边界情况
- TrackMetadata 不可变值对象，hasId3Cover 决定通知栏显示封面或默认图标

---

## [2026-05-10 17:59] PLY-05 - 播放队列管理

**模块**: Player
**状态**: ✅ 成功

### 实现文件
- `lib/shared/models/play_queue.dart` — 增强：PlayMode 枚举、nextIndex/previousIndex 纯函数、序列化

### 测试文件
- `test/features/player/ply_05_test.dart` — 测试用例 42 个（PLY-T30 ~ PLY-T37）

### 测试结果
- 通过: 334 / 总计: 334

### 备注
- nextIndex/previousIndex 支持 seeded Random 用于确定性测试
- PlayQueue.toMap/fromMap 支持应用重启时队列恢复
- repeatOne 模式下 startPositionMs 重置为 0

---

## [2026-05-10 18:04] PLY-06 - 播放模式切换

**模块**: Player
**状态**: ✅ 成功

### 实现文件
- `lib/features/player/player_provider.dart` — 添加 playModeProvider 和 nextPlayModeProvider
- `lib/features/player/player_screen.dart` — 添加 _PlayModeControl 模式循环按钮

### 测试文件
- `test/features/player/ply_06_test.dart` — 测试用例 12 个（PLY-T38 ~ PLY-T42 + PLY-T61）

### 测试结果
- 通过: 346 / 总计: 346

### 备注
- 模式循环顺序: sequential → repeatOne → repeatAll → shuffle → sequential
- iconForPlayMode/labelForPlayMode 纯函数映射图标和中文标签

---

## [2026-05-10 18:09] PLY-07 - 播放速度调节

**模块**: Player
**状态**: ✅ 成功

### 实现文件
- `lib/features/player/player_provider.dart` — 添加 defaultSpeedProvider、setDefaultSpeedProvider、currentSpeedProvider

### 测试文件
- `test/features/player/ply_07_test.dart` — 测试用例 36 个（PLY-T43 ~ PLY-T47 + PLY-T59 ~ PLY-T60）

### 测试结果
- 通过: 382 / 总计: 382

### 备注
- currentSpeedProvider 使用 ref.read 获取默认速度，修改默认不影响当前播放
- 新容器（模拟新文件）自动获取最新默认速度
- isValidSpeed 使用 0.01 浮点容差匹配 6 个速度档位

---

## [2026-05-10 18:15] PLY-08 - 迷你播放器

**模块**: Player
**状态**: ✅ 成功

### 实现文件
- `lib/features/player/widgets/mini_player_bar.dart` — 迷你播放器条组件（新建）
- `lib/features/browser/browser_screen.dart` — 底部集成 MiniPlayerBar

### 测试文件
- `test/features/player/ply_08_test.dart` — 测试用例 19 个（PLY-T48 ~ PLY-T54）

### 测试结果
- 通过: 401 / 总计: 401
- Player 模块全部 8 个功能实现完成

### 备注
- 迷你播放器仅在播放队列非空时显示
- 点击主体区域导航到完整播放器页面
- 进度条使用 LinearProgressIndicator 2px 高度

---

## [2026-05-10 18:22] TMR-01 ~ TMR-05 - Timer 模块全部功能

**模块**: Timer
**状态**: ✅ 全部成功 (5/5)

### 实现文件
- `lib/core/services/timer_service.dart` — 纯逻辑定时状态机（新建）
- `lib/features/timer/timer_provider.dart` — Riverpod Provider 封装（新建）
- `lib/features/timer/widgets/timer_button.dart` — 定时按钮 UI 和 BottomSheet（新建）

### 测试文件
- `test/features/timer/timer_test.dart` — 测试用例 46 个（TMR-T01 ~ TMR-T29 + Widget 测试）

### 测试结果
- 通过: 447 / 总计: 447

### 备注
- 定时模式: 5/10/15 分钟固定时长 + 播完当前
- formatRemaining: >60s→X分钟, <=60s→Xs, afterCurrent→null, 无定时→null
- cancel 幂等，到期后 pause 触发，cancel 后到期不触发
- Timer 模块全部 5 个功能一次性实现完成

---

## [2026-05-10 18:29] PRG-01 ~ PRG-04 - Progress 模块全部功能

**模块**: Progress
**状态**: ✅ 全部成功 (4/4)

### 实现文件
- `lib/core/database/dao/progress_dao.dart` — DAO: upsert/shouldSave/shouldClear/级联删除（新建）
- `lib/features/progress/progress_provider.dart` — Provider: 自动保存、查询、进度恢复状态机（新建）
- `lib/features/progress/progress_dialog.dart` — 进度恢复确认对话框（5 秒倒计时）（新建）
- `lib/core/database/database_helper.dart` — 添加 play_progress 表和索引
- `lib/shared/models/play_progress.dart` — 添加 fromMap/toMap/copyWith
- `lib/features/browser/browser_provider.dart` — 批量预加载进度、进度恢复 UI 集成
- `lib/features/browser/browser_screen.dart` — 文件点击时触发进度恢复流程

### 测试文件
- `test/features/progress/prg_test.dart` — 测试用例 31 个（PRG-T01 ~ PRG-T28 + helpers）

### 测试结果
- 通过: 478 / 总计: 478

### 备注
- shouldSave: position >= 5s 才保存；shouldClear: position > duration-10s 删除（视为播完）
- 进度恢复对话框支持继续/从头播放，5 秒倒计时自动选择继续
- play_progress 表 UNIQUE(connection_id, file_path) 保证 UPSERT

---

## [2026-05-10 18:35] SET-01 ~ SET-05 - Settings 模块全部功能

**模块**: Settings
**状态**: ✅ 全部成功 (5/5)

### 实现文件
- `lib/features/settings/settings_provider.dart` — 主题/步长/速度设置 Provider（新建）
- `lib/features/settings/settings_screen.dart` — 设置页面：播放/外观/连接/关于四分区（新建）
- `lib/features/settings/about_screen.dart` — 关于页面：应用名/版本/开源许可（新建）
- `lib/main.dart` — 添加 /settings、/about 路由，主题模式集成
- `lib/features/browser/browser_screen.dart` — AppBar 添加设置按钮
- `lib/features/player/player_provider.dart` — seekStepProvider 改为读 SharedPreferences

### 测试文件
- `test/features/settings/settings_test.dart` — 测试用例 57 个（SET-T01 ~ SET-T34 + 边界测试）

### 测试结果
- 通过: 535 / 总计: 535
- Settings 模块全部 5 个功能实现完成
- **全部 6 个模块 35 个功能实现完成**

---

## [2026-05-15 14:00] A-5 - 编辑连接 LateInitializationError 修复

**优先级**: P0
**关联问题**: BUG-3c
**状态**: ✅ 成功

### 修改文件
- `lib/features/connection/widgets/connection_form.dart` — ConnectionFormController 添加 isAttached getter，try-catch _state 访问防崩溃
- `lib/features/connection/connection_edit_screen.dart` — _needsValidation() 添加 !_formController.isAttached 守卫

### 验证结果
- 通过: 2 / 总计: 2（work_items 检查项）
- 静态分析通过，0 issues

### 备注
- 根因: _state 为 late 字段，build() 阶段的 _needsValidation() 在 initState() 之前访问导致 LateInitializationError
- isAttached 守卫确保表单未挂载时跳过字段值比较

---

## [2026-05-15 14:05] A-4 - 默认播放速度设置应用

**优先级**: P0
**关联问题**: BUG-3b
**状态**: ✅ 成功

### 修改文件
- `lib/features/player/player_screen.dart` — _loadAndPlay() 中 player.play() 前读取 defaultSpeedProvider 并应用 player.setSpeed()
- `lib/features/player/player_provider.dart` — setDefaultSpeedProvider 中同步更新 currentSpeedProvider.notifier.state

### 验证结果
- 通过: 2 / 总计: 2（work_items 检查项）
- 静态分析通过，无新增 error/warning

---

## [2026-05-15 14:08] A-2 - 迷你播放栏进入播放页面不重新加载

**优先级**: P0
**关联问题**: BUG-2a
**状态**: ✅ 成功

### 修改文件
- `lib/features/player/player_screen.dart` — initState() 中 addPostFrameCallback 添加播放状态检测，若已在播放/就绪则跳过 _loadAndPlay()

### 验证结果
- 通过: 2 / 总计: 2（work_items 检查项）
- 静态分析通过，无新增 error/warning

### 备注
- 根因: initState() 无条件调用 _loadAndPlay()，导致 player.stop() + 重新加载音频源，音乐从头播放
- 修复后: 检测到 player.playing 或 processingState==ready 时直接设置 _loadState=ready，不中断播放

---

## [2026-05-15 14:12] A-1 - 播放页面侧滑返回修复

**优先级**: P0
**关联问题**: BUG-1
**状态**: ✅ 成功

### 修改文件
- `lib/features/browser/browser_screen.dart` — 3 处 go('/player') → push('/player')
- `lib/features/player/widgets/mini_player_bar.dart` — 2 处 go('/player') → push('/player')

### 验证结果
- 通过: 2 / 总计: 2（work_items 检查项）
- 静态分析通过，无新增 error/warning

### 备注
- 根因: GoRouter.go() 替换导航栈，/player 成为唯一路由，侧滑无法回退
- 修复后: push() 叠加路由栈 /browser → /player，侧滑一次回浏览器，再侧滑退出桌面

---

## [2026-05-15 14:15] A-3 - 迷你播放栏播放按钮手势冲突修复

**优先级**: P0
**关联问题**: BUG-2b
**状态**: ✅ 成功

### 修改文件
- `lib/features/player/widgets/mini_player_bar.dart` — 移除顶层 InkWell，替换为 GestureDetector 仅包裹曲目标题区域；IconButton 保持在 GestureDetector 外部

### 验证结果
- 通过: 2 / 总计: 2（work_items 检查项）
- 静态分析通过，无新增 error/warning

### 备注
- 根因: InkWell(全区域) 与 IconButton 都注册 TapGestureRecognizer，在手势竞技场中竞争导致均无法胜出
- 修复后: GestureDetector 仅包裹标题文字，播放/暂停和下一曲按钮不再受手势竞争影响

---

## [2026-05-15 14:18] B-1 - 迷你播放栏下一曲按钮不跳转页面

**优先级**: P1
**关联问题**: BUG-2c
**状态**: ✅ 成功

### 修改文件
- `lib/features/player/widgets/mini_player_bar.dart` — _NextButton.onPressed 直接加载音频源播放下一曲，移除 GoRouter 导航跳转

### 验证结果
- 通过: 2 / 总计: 2（work_items 检查项）
- 静态分析通过，无新增 error/warning

### 备注
- 根因: _NextButton 调用 GoRouter.go('/player') 跳转页面，未直接在当前页加载下一曲
- 修复后: onPressed 直接读取连接信息和凭据，构建音频源并加载播放，留在当前页面

---

## [2026-05-15 14:22] C-1 - 快退/快进按钮图标动态显示步长

**优先级**: P2
**关联问题**: BUG-1b, BUG-3a
**状态**: ✅ 成功

### 修改文件
- `lib/features/player/player_screen.dart` — 添加 _iconForSeekBackward / _iconForSeekForward 辅助方法，替换硬编码图标为动态选择

### 验证结果
- 通过: 2 / 总计: 3（work_items 检查项，可选标签项未实现）
- 静态分析通过，无新增 error/warning

### 备注
- 5s/10s/30s 使用带数字的 Material Icon (replay_5/10/30, forward_5/10/30)
- 15s/60s 等无对应图标的步长使用通用 replay/forward 图标，tooltip 已显示步长秒数
