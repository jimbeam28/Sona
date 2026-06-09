# 开发日志

---

## [2026-05-23] [PRG-01] - 进度恢复对话框接入

**状态**: ✅ 成功

### 修改文件
- `lib/features/browser/browser_screen.dart` — onFileTap 中接入进度检查 + 恢复对话框
- `lib/features/playlist/playlist_detail_screen.dart` — onTrackTap 中接入进度检查 + 恢复对话框
- `test/features/progress/prg_test.dart` — 新增 7 个测试用例 (PRG-FIX-T01~T06 + PlayQueue startPositionMs)

### 测试结果
- 通过: 621 / 总计: 621

---

## [2026-05-23] [CON-01] - 添加连接页面验证状态过期

**状态**: ✅ 成功

### 修改文件
- `lib/features/connection/connection_screen.dart` — 添加 onFieldChanged 回调，凭证变更时重置验证器
- `test/features/connection/con_01_test.dart` — 新增 3 个测试用例 (CON-FIX-T01~T03)

### 测试结果
- 通过: 624 / 总计: 624

---

## [2026-05-23] [TST-01] - 自动切歌流程集成测试

**状态**: ✅ 成功

### 修改文件
- `test/features/player/ply_05_test.dart` — 追加 TST-01 测试 group，6 个测试用例

### 测试结果
- 通过: 644 / 总计: 644

---

## [2026-05-23] [TST-02] - 播放进度保存与恢复端到端链路

**状态**: ✅ 成功

### 修改文件
- `test/features/progress/prg_test.dart` — 追加 TST-02 测试 group，7 个测试用例

### 测试结果
- 通过: 656 / 总计: 656

---

## [2026-05-24] [TST-12] - 连接切换影响面集成测试

**状态**: ✅ 成功

### 修改文件
- `test/features/connection/con_09_test.dart` — 新建，8 个测试用例

### 测试结果
- 通过: 742 / 总计: 742

---

## [2026-05-24] [TST-11] - 播放单拖拽排序与添加曲目弹窗

**状态**: ✅ 成功

### 修改文件
- `test/features/playlist/ply_13_test.dart` — 追加 TST-T80~T82 拖拽排序测试
- `test/features/playlist/ply_14_test.dart` — 新建，TST-T83~T90 添加曲目弹窗测试

### 测试结果
- 通过: 734 / 总计: 734

---

## [2026-05-24] [TST-10] - 记住播放速度开关测试

**状态**: ✅ 成功

### 修改文件
- `test/features/player/ply_07_test.dart` — 追加 TST-10 测试，8 个测试用例
- `test/features/settings/settings_test.dart` — 追加 TST-T79 widget 测试

### 测试结果
- 通过: 723 / 总计: 723

---

## [2026-05-24] [TST-09] - 目录缓存 TTL 过期与容量上限测试

**状态**: ✅ 成功

### 修改文件
- `test/features/browser/brw_05_test.dart` — 追加 TST-09 测试 group，8 个测试用例

### 测试结果
- 通过: 712 / 总计: 712

---

## [2026-05-24] [TST-08] - BreadcrumbBar 面包屑交互测试

**状态**: ✅ 成功

### 修改文件
- `test/features/browser/brw_08_test.dart` — 新建，9 个测试用例

### 测试结果
- 通过: 704 / 总计: 704

---

## [2026-05-24] [TST-07] - PlayerScreen 全屏播放器 Widget 测试

**状态**: ✅ 成功

### 修改文件
- `test/features/player/ply_14_test.dart` — 新建，12 个测试用例

### 测试结果
- 通过: 691 / 总计: 691

---

## [2026-05-24] [TST-06] - 播放单导出/导入测试

**状态**: ✅ 成功

### 修改文件
- `test/features/playlist/ply_10_test.dart` — 追加 TST-06 测试 group，8 个测试用例
- `lib/features/playlist/playlist_provider.dart` — 修复导入去重逻辑（TST-T40 暴露）

### 测试结果
- 通过: 673 / 总计: 673

---

## [2026-05-24] [TST-05] - 定时器暂停/恢复功能测试

**状态**: ✅ 成功

### 修改文件
- `test/features/timer/timer_test.dart` — 追加 TST-05 测试 group，9 个测试用例

### 测试结果
- 通过: 665 / 总计: 665

---

## [2026-05-24] [TST-04] - 播放单曲目点击完整播放流程

**状态**: ✅ 成功

### 修改文件
- `test/features/playlist/ply_13_test.dart` — 追加 TST-04 测试 group，6 个测试用例

### 测试结果
- 通过: 656 / 总计: 656

---

## [2026-05-24] [TST-17] - 各模块补充测试（二）：Player + Progress + Settings + Home

**状态**: ✅ 成功

### 修改文件
- `test/features/player/ply_02_test.dart` — 追加 TST-T132~T133（TrackLoadResult + PlayerLoadState）
- `test/features/player/ply_05_test.dart` — 追加 TST-T137（PlayQueue toMap/fromMap round-trip）
- `test/features/progress/prg_test.dart` — 追加 TST-T138, TST-T148（短时长进度 + startPositionMs）
- `test/features/playlist/ply_13_test.dart` — 追加 TST-T139~T140（重命名弹窗逻辑）
- `test/features/settings/settings_test.dart` — 追加 TST-T141~T143（Tab index + 设置导航）
- `test/features/home/home_screen_test.dart` — 新建，TST-T144（HomeScreen PopScope）
- `test/features/connection/con_01_test.dart` — 追加 TST-T145~T147（连接列表/编辑）

### 测试结果
- 通过: 804 / 总计: 804

---

## [2026-05-24] [TST-16] - 各模块补充测试（一）：Connection + Browser

**状态**: ✅ 成功

### 修改文件
- `test/features/connection/con_01_test.dart` — 追加 TST-T123~T125 测试（ONB_CTA + Slidable）
- `test/features/browser/brw_04_test.dart` — 追加 TST-T126~T128 测试（长按清除进度）
- `test/features/browser/brw_07_test.dart` — 追加 TST-T129~T131 测试（目录批量进度查询）

### 测试结果
- 通过: 790 / 总计: 790

---

## [2026-05-24] [TST-15] - URL编码边界与并发竞争测试

**状态**: ✅ 成功

### 修改文件
- `test/features/player/ply_01_test.dart` — 追加 TST-T114~T118 URL 编码边界字符测试
- `test/features/player/ply_02_test.dart` — 追加 TST-T119~T120 并发竞争测试 + TST-T121~T122 NasFile.fromProps 边界测试

### 测试结果
- 通过: 781 / 总计: 781

---

## [2026-05-24] [TST-14] - 运行日志查看器测试

**状态**: ✅ 成功

### 修改文件
- `test/features/settings/log_viewer_test.dart` — 新建，10 个测试用例

### 测试结果
- 通过: 770 / 总计: 770

---

## [2026-05-24] [TST-13] - App 生命周期完整链路测试

**状态**: ✅ 成功

### 修改文件
- `test/features/player/ply_03_test.dart` — 追加 TST-13 测试 group，18 个测试用例

### 测试结果
- 通过: 760 / 总计: 760

---

## [2026-05-24] [TST-03] - Timer 到期 → Player 暂停集成链路

**状态**: ✅ 成功

### 修改文件
- `test/features/timer/timer_test.dart` — 追加 TST-03 测试 group，6 个测试用例

### 测试结果
- 通过: 650 / 总计: 650


---

## [2026-06-09] [BUG-01] - _completingProvider 卡死导致自动切歌永久失效

**状态**: ✅ 成功

### 修改文件
- `lib/features/player/player_provider.dart` — 行 665: 队列为 null 时重置 _completingProvider
- `test/features/player/bug_01_test.dart` — 新建，3 个测试用例

### 测试结果
- 通过: 819 / 总计: 819

---

## [2026-06-09] [BUG-02] - 播放单取消全选不退出选择模式

**状态**: ✅ 成功

### 修改文件
- `lib/features/playlist/playlist_detail_screen.dart` — 行 308: 取消全选调用 _exitSelectionMode()
- `test/features/playlist/bug_02_test.dart` — 新建，3 个测试用例
- `test/features/playlist/ply_13_test.dart` — 更新 PLY-T79 测试以匹配修正后行为

### 测试结果
- 通过: 822 / 总计: 822

---

## [2026-06-09] [BUG-03] - 目录缓存淘汰不是 LRU

**状态**: ✅ 成功

### 修改文件
- `lib/features/browser/browser_provider.dart` — CacheEntry 添加 lastAccessedAt，淘汰逻辑改为 LRU
- `test/features/browser/bug_03_test.dart` — 新建，4 个测试用例

### 测试结果
- 通过: 826 / 总计: 826

---

## [2026-06-09] [BUG-04] - 播放单曲目排序缺少防御检查

**状态**: ✅ 成功

### 修改文件
- `lib/features/playlist/playlist_provider.dart` — reorderPlaylistTrackProvider 添加排序模式检查
- `test/features/playlist/bug_04_test.dart` — 新建，3 个测试用例

### 测试结果
- 通过: 829 / 总计: 829

---

## [2026-06-09] [BUG-05] - SerializedRequestGate 卡死导致所有后续加载请求永久挂起

**状态**: ✅ 成功

### 修改文件
- `lib/features/player/player_provider.dart` — _start() 添加 20s 超时，loadAndPlayProvider 添加 5s 超时
- `test/features/player/bug_05_test.dart` — 新建，8 个测试用例

### 测试结果
- 通过: 837 / 总计: 837

---

## [2026-06-09] [BUG-06] - audio_handler await 无超时导致通知栏控件卡死

**状态**: ✅ 成功

### 修改文件
- `lib/core/services/audio_handler.dart` — play/pause/stop/onTaskRemoved 添加 5s 超时
- `test/features/player/bug_06_test.dart` — 新建，6 个测试用例
- `test/features/player/bug_06_test.mocks.dart` — 自动生成 mock

### 测试结果
- 通过: 843 / 总计: 843

---

## [2026-06-09] [BUG-07] - App 启动恢复队列时 setAudioSource/seek 无超时导致启动卡住

**状态**: ✅ 成功

### 修改文件
- `lib/features/browser/browser_provider.dart` — 提取 preloadAudioSource 函数，添加 10s 超时
- `test/features/browser/bug_07_test.dart` — 新建，4 个测试用例
- `test/features/browser/bug_07_test.mocks.dart` — 自动生成 mock

### 测试结果
- 通过: 847 / 总计: 847

---

## [2026-06-09] [BUG-08] - conn.id! / track.id! 空指针闪退

**状态**: ✅ 成功

### 修改文件
- `lib/features/connection/connection_list_screen.dart` — 3 处添加 null 守卫
- `lib/features/playlist/playlist_detail_screen.dart` — 2 处添加 null 守卫
- `test/features/connection/bug_08_con_test.dart` — 新建，5 个测试用例
- `test/features/playlist/bug_08_test.dart` — 新建，4 个测试用例

### 测试结果
- 通过: 856 / 总计: 856

---

## [2026-06-09] [BUG-09] - upsertProgressProvider / clearProgressProvider 无 try-catch 导致闪退

**状态**: ✅ 成功

### 修改文件
- `lib/features/progress/progress_provider.dart` — upsert/delete 添加 try-catch
- `test/features/progress/bug_09_test.dart` — 新建，4 个测试用例

### 测试结果
- 通过: 860 / 总计: 860

---

## [2026-06-09] [BUG-10] - SecureStorage 全局无超时保护

**状态**: ✅ 成功

### 修改文件
- `lib/core/services/storage_utils.dart` — 新建，safeStorageRead/Write/Delete 工具函数
- `lib/features/browser/browser_provider.dart` — 2 处调用替换
- `lib/features/player/player_screen.dart` — 1 处调用替换
- `lib/features/connection/connection_provider.dart` — 4 处调用替换
- `test/features/bug_10_test.dart` — 新建，4 个测试用例
- `test/features/browser/bug_07_test.dart` — 更新 T03 测试预期

### 测试结果
- 通过: 864 / 总计: 864

---

## [2026-06-09] [REF-01] - 创建 test/helpers/ 目录结构

**状态**: ✅ 成功

### 修改文件
- `test/helpers/test_database.dart` — 新建占位
- `test/helpers/fake_secure_storage.dart` — 新建占位
- `test/helpers/test_factories.dart` — 新建占位
- `test/helpers/widget_helpers.dart` — 新建占位

### 测试结果
- 通过: 864 / 总计: 864

---

## [2026-06-09] [REF-02] - 提取 FakeSecureStorage 到共享模块

**状态**: ✅ 成功

### 修改文件
- `test/helpers/fake_secure_storage.dart` — 实现共享 FakeSecureStorage + ThrowingFakeSecureStorage
- `test/features/connection/con_09_test.dart` — 使用共享版本
- `test/features/browser/brw_05_test.dart` — 使用共享版本
- `test/features/browser/brw_06_test.dart` — 使用共享版本

### 测试结果
- 通过: 864 / 总计: 864

---

## [2026-06-09] [REF-03] - 提取 openTestDatabase 到共享模块

**状态**: ✅ 成功

### 修改文件
- `test/helpers/test_database.dart` — 实现共享 openTestDatabase + TestSchema 枚举
- 8 个测试文件 — 使用共享版本

### 测试结果
- 通过: 864 / 总计: 864

---

## [2026-06-09] [REF-04] - 提取 _audio()/_dir() 工厂函数

**状态**: ✅ 成功

### 修改文件
- `test/helpers/test_factories.dart` — 实现共享工厂函数 (testDir, testAudio, testConfig, testConnection, testProgress)
- 13 个测试文件 — 使用共享版本
- 11 个测试文件 — 移除不再需要的 import

### 测试结果
- 通过: 864 / 总计: 864

---

## [2026-06-09] [REF-05] - 提取 MockWebDavClient 到共享模块

**状态**: ✅ 成功

### 修改文件
- `test/helpers/fake_webdav_client.dart` — 实现共享 MockWebDavClient + SpyWebDavClient
- `test/features/connection/con_01_test.dart` — 使用共享版本
- `test/features/browser/brw_05_test.dart` — 使用共享版本

### 测试结果
- 通过: 864 / 总计: 864

---

## [2026-06-09] [REF-06] - 提取 MockAudioPlayer 到共享模块

**状态**: ✅ 成功

### 修改文件
- `test/helpers/mock_audio_player.dart` — 新建，手写 AudioPlayer mock
- 6 个测试文件 — 使用共享版本
- `test/features/player/ply_08_test.mocks.dart` — 删除

### 测试结果
- 通过: 864 / 总计: 864

---

## [2026-06-09] [REF-07] - 提取 widget 测试包装函数

**状态**: ✅ 成功

### 修改文件
- `test/helpers/widget_helpers.dart` — 实现共享 widget 包装函数 (12 个函数)
- 8 个测试文件 — 使用共享版本

### 测试结果
- 通过: 864 / 总计: 864

---

## [2026-06-09] [REF-08] - 创建 player/domain/seek_utils.dart

**状态**: ✅ 成功

### 修改文件
- `lib/features/player/domain/seek_utils.dart` — 新建，clampSeek/skipForward/skipBackward
- `lib/features/player/player_provider.dart` — 移除函数定义
- `lib/features/player/player_screen.dart` — 添加 import
- `test/features/player/ref_08_test.dart` — 新建，20 个测试用例

### 测试结果
- 通过: 884 / 总计: 884

---

## [2026-06-09] [REF-09] - 创建 player/domain/play_mode.dart

**状态**: ✅ 成功

### 修改文件
- `lib/features/player/domain/play_mode.dart` — 新建，PlayMode 枚举 + nextIndex/previousIndex
- `lib/shared/models/play_queue.dart` — 委托到新文件
- `lib/features/player/player_provider.dart` — 移除 labelForPlayMode
- `lib/features/player/player_screen.dart` — 添加 import
- `test/features/player/ref_09_test.dart` — 新建，34 个测试用例

### 测试结果
- 通过: 918 / 总计: 918

---

## [2026-06-09] [REF-10] - 创建 player/domain/speed_manager.dart

**状态**: ✅ 成功

### 修改文件
- `lib/features/player/domain/speed_manager.dart` — 新建，speedOptions/isValidSpeed/getDefaultSpeed/readSeekStep
- `lib/features/player/player_provider.dart` — 移除重复定义
- `test/features/player/ref_10_test.dart` — 新建，24 个测试用例

### 测试结果
- 通过: 942 / 总计: 942

---

## [2026-06-09] [REF-11] - 创建 player/domain/request_gate.dart

**状态**: ✅ 成功

### 修改文件
- `lib/features/player/domain/request_gate.dart` — 新建，SerializedRequestGate + 相关类型
- `lib/features/player/player_provider.dart` — 移除重复定义
- `test/features/player/ref_11_test.dart` — 新建，14 个测试用例

### 测试结果
- 通过: 956 / 总计: 956

---

## [2026-06-09] [REF-12] - 创建 player/domain/media_control.dart

**状态**: ✅ 成功

### 修改文件
- `lib/features/player/domain/media_control.dart` — 新建，extractTitleFromPath/mapHeadphoneAction/formatDuration
- `lib/features/player/media_control_model.dart` — 委托到新文件
- `lib/features/player/player_provider.dart` — 移除 formatDuration
- `test/features/player/ref_12_test.dart` — 新建，26 个测试用例

### 测试结果
- 通过: 982 / 总计: 982

---

## [2026-06-09] [REF-13] - 创建 player/domain/background_playback.dart

**状态**: ✅ 成功

### 修改文件
- `lib/features/player/domain/background_playback.dart` — 新建，BackgroundPlaybackConfig + Notifier
- `lib/features/player/background_playback.dart` — 改为 re-export
- `lib/features/player/player_provider.dart` — 移除重复定义
- `test/features/player/ref_13_test.dart` — 新建，65 个测试用例

### 测试结果
- 通过: 1047 / 总计: 1047

---

## [2026-06-09] [REF-14] - 创建 player/domain/playback_orchestrator.dart

**状态**: ✅ 成功

### 修改文件
- `lib/features/player/domain/playback_orchestrator.dart` — 新建，PlaybackOrchestrator 核心类
- `test/features/player/ref_14_test.dart` — 新建，28 个测试用例
- `test/features/player/ref_14_test.mocks.dart` — 自动生成 mock

### 测试结果
- 通过: 1075 / 总计: 1075

---

## [2026-06-09] [REF-15] - 重写 player_provider.dart 为薄胶水

**状态**: ✅ 成功

### 修改文件
- `lib/features/player/player_provider.dart` — 从 1092 行重写为 297 行
- `lib/features/player/domain/playback_orchestrator.dart` — 添加 registerListeners 参数

### 测试结果
- 通过: 1075 / 总计: 1075

---

## [2026-06-09] [REF-16] - 更新 player_screen.dart 使用新 provider

**状态**: ✅ 成功

### 修改文件
- `lib/features/player/player_screen.dart` — 简化 import 和 _saveProgressWithContainer

### 测试结果
- 通过: 1075 / 总计: 1075

---

## [2026-06-09] [REF-17] - 创建 browser/domain/navigation_stack.dart

**状态**: ✅ 成功

### 修改文件
- `lib/features/browser/domain/navigation_stack.dart` — 新建，NavigationStackNotifier
- `lib/features/browser/browser_provider.dart` — 移除内联定义
- `test/features/browser/ref_17_test.dart` — 新建，6 个测试用例

### 测试结果
- 通过: 1081 / 总计: 1081

---

## [2026-06-09] [REF-18] - 创建 browser/domain/cache_policy.dart

**状态**: ✅ 成功

### 修改文件
- `lib/features/browser/domain/cache_policy.dart` — 新建，CacheEntry + CachePolicy
- `lib/features/browser/browser_provider.dart` — 使用新文件
- 4 个测试文件 — 更新 CacheEntry 引用
- `test/features/browser/ref_18_test.dart` — 新建，5 个测试用例

### 测试结果
- 通过: 1086 / 总计: 1086
