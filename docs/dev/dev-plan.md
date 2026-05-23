# 开发计划

> 基于 state.md 状态机分析和 test.md 测试缺口分析生成。
> 来源：Sona 全功能状态机分析 + 测试覆盖率审计。

---

## 待实现 — 测试补充（P0 核心路径）

### TST-01 自动切歌流程集成测试

**来源**：测试缺口 (test.md §PLY-G01) | **优先级**：P0
**涉及文件**：`test/features/player/ply_05_test.dart`（追加）、`lib/features/player/player_provider.dart`
**依赖**：无
**关联缺口**：PLY-G01

**实现要点**：
- 覆盖 processingState=completed → nextIndex（基于 playMode）→ 构建新 AudioSource → loadAndPlay 完整链路
- 使用 mock AudioPlayer（已有 `ply_08_test.mocks.dart`），模拟 `processingStateStream` 发出 `ProcessingState.completed`
- 验证 4 种播放模式下切歌行为：sequential 队尾停播、repeatOne 同曲重放(seek 0)、repeatAll 循环到队首、shuffle 随机跳转
- 验证切歌前先保存旧曲目进度、切歌后更新 `currentPlayQueueProvider.currentIndex`
- 在现有 `ply_05_test.dart` 文件末尾追加测试 group

**测试用例**：TST-T01 ~ TST-T06
- TST-T01: sequential 模式 — 中间曲目完成 → 自动跳到下一首
- TST-T02: sequential 模式 — 最后一首完成 → 队列到头，stop+pause
- TST-T03: repeatOne 模式 — 曲目完成 → seek(0)+play 同曲重放
- TST-T04: repeatAll 模式 — 最后一首完成 → 循环到第一首
- TST-T05: shuffle 模式 — 曲目完成 → 随机跳到非当前索引
- TST-T06: 切歌前验证 `upsertProgressProvider` 被调用（保存旧曲目进度）

---

### TST-02 播放进度保存与恢复端到端链路

**来源**：测试缺口 (test.md §INT-G02) | **优先级**：P0
**涉及文件**：`test/features/progress/prg_test.dart`（追加）、`lib/features/player/player_provider.dart`、`lib/features/progress/progress_provider.dart`
**依赖**：无
**关联缺口**：INT-G02, PRG-G01, PRG-G04

**实现要点**：
- 模拟完整流程：构建 PlayQueue → 播放 → position 推进 → 10s 周期自动保存 → pause 时保存 → App 模拟重启（新 ProviderContainer）→ 读 latestPlayedProgress → 恢复队列 → seek 到保存位置
- 使用 fake_async 模拟时间流逝，验证 10s 周期定时器触发保存
- 验证 5 个保存触发点全部执行：周期保存、暂停保存、切歌保存、后台保存、dispose 保存
- 验证 upsertLatest 替换旧记录后旧 connectionId+filePath 记录确实删除
- 使用 sqflite_ffi 内存数据库，模拟跨 session 的进度持久化
- 验证重启后不自动播放（仅恢复位置，等待用户点击）

**测试用例**：TST-T07 ~ TST-T13
- TST-T07: 10s 周期保存 — fake_async 推进 30s → 3 次 upsert 调用
- TST-T08: 暂停触发保存 — playerStateStream 发出 playing: true→false
- TST-T09: 切歌前保存 — skipToNext 前调用 upsert 保存旧曲目
- TST-T10: 进入后台保存 — AppLifecycleState.paused → 保存当前进度
- TST-T11: dispose 保存 — PlayerScreen dispose → 保存当前进度
- TST-T12: 重启恢复 — 新 ProviderContainer → findLatest → 构建带 startPositionMs 的队列
- TST-T13: upsertLatest 旧记录确实被物理删除（count=1 非累积）

---

### TST-03 Timer 到期 → Player 暂停集成链路

**来源**：测试缺口 (test.md §INT-G03, TMR-G02, TMR-G04) | **优先级**：P0
**涉及文件**：`test/features/timer/timer_test.dart`（追加）、`lib/core/services/timer_service.dart`、`lib/features/timer/timer_provider.dart`
**依赖**：无
**关联缺口**：INT-G03, TMR-G02, TMR-G04

**实现要点**：
- 固定时长到期链路：启动 duration timer → fake_async 推进到 endTime → checkExpired() 返回 true → 验证 player.pause() 被调用 → timerState 清除为 null
- afterCurrent 到期链路：启动 afterCurrent → mock processingStateStream 发出 completed → onTrackCompleted() 返回 true → 验证 player.pause() 被调用
- 使用 mock AudioPlayer（MockAudioPlayer from ply_08_test.mocks.dart）
- 验证到期后 timerStateProvider 状态为 null（清除）
- 验证 checkExpired/trackCompleted 的幂等性（再次调用返回 false）

**测试用例**：TST-T14 ~ TST-T19
- TST-T14: 5min duration timer → fake_async elapse 5min → checkExpired=true → pause() 被调用
- TST-T15: duration timer 未到期 → checkExpired=false → pause() 未被调用
- TST-T16: afterCurrent timer → processingState=completed → onTrackCompleted=true → pause() 被调用
- TST-T17: afterCurrent timer → 手动切歌（skipToNext）→ onTrackCompleted 未被调用 → timer 保持 active
- TST-T18: 到期后再次 checkExpired → 返回 false（state 已清除，幂等）
- TST-T19: afterCurrent 触发后再次 onTrackCompleted → 返回 false（幂等）

---

### TST-04 播放单曲目点击完整播放流程

**来源**：测试缺口 (test.md §INT-G04, PRG-G03) | **优先级**：P0
**涉及文件**：`test/features/playlist/ply_13_test.dart`（追加）、`lib/features/playlist/playlist_detail_screen.dart`
**依赖**：TST-02（共享进度恢复测试基础设施）
**关联缺口**：INT-G04, PRG-G03

**实现要点**：
- 完整流程：点击播放单曲目 → progressForFileProvider 查询进度 → 有进度→弹恢复对话框 → 选择继续/从头 → 构建 PlayQueue(startPositionMs) → 导航 /player → 加载 AudioSource → seek 到保存位置（或从头播放）
- 使用 GoRouter mock 路由，验证导航到 /player
- 使用 sqflite_ffi 预置进度数据，验证 progressForFileProvider 返回正确 PlayProgress
- 验证 PlayQueue 携带 startPositionMs 传递到 PlayerScreen
- 无进度文件直接构建队列，不弹对话框

**测试用例**：TST-T20 ~ TST-T25
- TST-T20: 有进度的曲目点击 → 弹出恢复对话框 → 选择继续 → 构建带 startPositionMs 的队列 → 导航 /player
- TST-T21: 有进度的曲目点击 → 弹出恢复对话框 → 选择从头 → 构建不带 startPositionMs 的队列 → 导航 /player
- TST-T22: 无进度的曲目点击 → 不弹对话框 → 直接构建队列 → 导航 /player
- TST-T23: positionMs < 5000 的曲目 → threshold 检查 → 不弹对话框
- TST-T24: 恢复对话框倒计时归零 → 自动选择继续
- TST-T25: 多曲目播放单点击任意曲目 → queue.currentIndex 正确指向被点击曲目

---

## 待实现 — 测试补充（P1 重要功能）

### TST-05 定时器暂停/恢复功能测试

**来源**：测试缺口 (test.md §TMR-G01) | **优先级**：P1
**涉及文件**：`test/features/timer/timer_test.dart`（追加）、`lib/core/services/timer_service.dart`
**依赖**：无
**关联缺口**：TMR-G01

**实现要点**：
- 新增 paused 状态的单元测试（state.md 4.1-4.2 设计的状态转移）
- 测试 pause()：duration timer 运行中 → 暂停 → 记录 remainingMs → 状态变为 paused
- 测试 resume()：paused 状态 → 恢复 → 从 remainingMs 重新计算 endTime
- 测试 cancel() on paused → 回到 idle
- 测试 startDuration() on paused → 覆盖旧 timer → 新定时器启动
- 测试 checkExpired() on paused → 不触发到期（paused 不倒计时）
- 测试 afterCurrent → pause → resume 的转换链路
- 测试 formattedRemaining 在 paused 状态下显示正确的剩余时间

**测试用例**：TST-T26 ~ TST-T34
- TST-T26: duration timer → pause → state.mode==paused, remainingMs 不变
- TST-T27: paused → resume → 恢复倒计时，endTime 重新计算
- TST-T28: paused → cancel → state==null (idle)
- TST-T29: paused → startDuration(10) → 新 timer 覆盖 paused
- TST-T30: afterCurrent → pause → state.mode==paused
- TST-T31: paused(afterCurrent) → resume → 回到 afterCurrent
- TST-T32: paused → checkExpired → 返回 false（不触发到期）
- TST-T33: formattedRemaining 在 paused 状态下正确显示
- TST-T34: 暂停→恢复完整循环，endTime 差值正确

---

### TST-06 播放单导出/导入测试

**来源**：测试缺口 (test.md §PLS-G04, PLS-G05) | **优先级**：P1
**涉及文件**：`test/features/playlist/ply_10_test.dart`（追加）、`lib/features/playlist/playlist_provider.dart`
**依赖**：无
**关联缺口**：PLS-G04, PLS-G05, LOG-G05

**实现要点**：
- 使用 sqflite_ffi 内存数据库，创建播放单并添加曲目 → 调用 exportPlaylistProvider → 验证 JSON 结构正确
- JSON 格式：`{name, tracks: [{filePath, fileName}], exportedAt}`
- 导入：`importPlaylistProvider(jsonString)` → 创建新播放单 → 添加曲目 → 验证 DAO 数据正确
- 导入去重：同一 filePath 跳过
- 导入容错：JSON 格式错误 → 不崩溃 → 返回错误
- 导入含不存在路径的 JSON → 跳过缺失曲目

**测试用例**：TST-T35 ~ TST-T42
- TST-T35: 导出含 5 首曲目的播放单 → JSON 包含所有字段
- TST-T36: 导出空播放单 → JSON tracks 为空数组
- TST-T37: 导入有效 JSON → 新播放单创建成功 → 曲目列表正确
- TST-T38: 导入 JSON → 曲目数匹配原始播放单
- TST-T39: 重复导入同一 JSON → 创建两个独立播放单（非覆盖）
- TST-T40: 导入含已存在路径的 JSON → 去重跳过
- TST-T41: 导入格式错误的 JSON → 不崩溃 → 返回错误信息
- TST-T42: export+import round-trip → 名称和曲目完全一致

---

### TST-07 PlayerScreen 全屏播放器 Widget 测试

**来源**：测试缺口 (test.md §UI-G01, PLY-G04) | **优先级**：P1
**涉及文件**：新建 `test/features/player/ply_14_test.dart`、`lib/features/player/player_screen.dart`
**依赖**：无
**关联缺口**：UI-G01, PLY-G04

**实现要点**：
- 使用 MockAudioPlayer（ply_08_test.mocks.dart），mock 所有必要的 Stream（positionStream、durationStream、playerStateStream、speedStream）
- 验证全屏播放器页面的控件渲染：封面区域、进度条 Slider、播放/暂停按钮、上一首/下一首、快进/快退、速度按钮、播放模式按钮、定时器按钮、队列按钮
- 验证进度条 Slider 的 onChanged 和 onChangeEnd 触发 seek
- 验证速度按钮点击弹出 6 选项底部弹窗
- 验证播放模式按钮点击循环切换 4 种模式
- 验证当前曲目名和艺术家信息（从文件名提取）的显示
- 验证 AppBar 返回按钮存在

**测试用例**：TST-T43 ~ TST-T54
- TST-T43: 播放器页面渲染 → AppBar + 封面区域 + 进度条 + 控制按钮全部可见
- TST-T44: 当前曲目名显示（从 queue.current.name 读取）
- TST-T45: 播放中按钮显示 pause 图标，暂停中显示 play_arrow
- TST-T46: 上一首/下一首按钮渲染并可点击
- TST-T47: 快进/快退按钮显示当前步长标签
- TST-T48: 进度条 Slider value 与 position/duration 同步
- TST-T49: Slider onChangeEnd → player.seek() 被调用到正确位置
- TST-T50: 速度按钮点击 → 底部弹窗出现 6 个速度选项
- TST-T51: 选中速度后弹窗关闭，按钮标签更新
- TST-T52: 播放模式按钮点击 → 循环切换 4 个图标
- TST-T53: 定时器按钮渲染（沙漏图标）
- TST-T54: 队列按钮渲染 → 点击弹出 QueueSheet

---

### TST-08 BreadcrumbBar 面包屑交互测试

**来源**：测试缺口 (test.md §UI-G03, BRW-G01, BRW-G02) | **优先级**：P1
**涉及文件**：新建 `test/features/browser/brw_08_test.dart`、`lib/features/browser/widgets/breadcrumb_bar.dart`、`lib/features/browser/browser_screen.dart`
**依赖**：无
**关联缺口**：UI-G03, BRW-G01, BRW-G02

**实现要点**：
- Widget 测试：使用 ProviderScope override directoryContentsProvider，模拟多级目录导航
- 面包屑渲染：验证每个路径段显示为可点击的 Chip/Text
- 点击面包屑段 → popTo(targetPath) → 目录内容切换到目标路径
- 溢出折叠显示：窄屏幕宽度 → 中间段折叠为 "..." → 根目录和最深目录始终可见
- PopScope 返回拦截：子目录按 back → 导航栈 pop → 面包屑更新
- 根目录按 back → PopScope 允许系统返回（退出 Browser）

**测试用例**：TST-T55 ~ TST-T63
- TST-T55: 根目录渲染 → 面包屑显示 "根目录"
- TST-T56: /music/artist/album → 面包屑显示 "根目录 > music > artist > album"
- TST-T57: 点击 breadcrumb "music" → popTo(/music) → 目录切换到 /music
- TST-T58: 点击 breadcrumb "根目录" → popTo(/) → 回到根目录
- TST-T59: 窄宽度 → 中间段溢出折叠 → "根目录" 和 "album" 始终可见
- TST-T60: 子目录按系统 back → pop() → 回到上级目录
- TST-T61: 根目录按系统 back → PopScope 允许退出
- TST-T62: 面包屑段数量与 navigationStack.length 一致
- TST-T63: 快速连续点击不同面包屑 → 每次 popTo 正确

---

### TST-09 目录缓存 TTL 过期与容量上限测试

**来源**：测试缺口 (test.md §BRW-G03, BRW-G04) | **优先级**：P1
**涉及文件**：`test/features/browser/brw_05_test.dart`（追加）、`lib/features/browser/browser_provider.dart`
**依赖**：无
**关联缺口**：BRW-G03, BRW-G04

**实现要点**：
- 缓存 TTL 过期：插入带时间戳的缓存条目 → fake_async 推进超过 TTL(5min) → 再次读取同路径 → 验证触发新的 listDirectory 请求
- 缓存未过期：插入条目 → 推进 3min → 再次读取 → 使用缓存（不触发新请求）
- 容量上限：插入 50+ 条缓存条目 → 验证最旧条目被移除 → 新条目正常写入
- 容量边界：恰好 50 条时所有条目保留 → 第 51 条触发淘汰
- 使用 _MockWebDavClient 跟踪 listDirectory 调用次数

**测试用例**：TST-T64 ~ TST-T71
- TST-T64: 缓存条目在 3min 内 → 复用缓存，无新网络请求
- TST-T65: 缓存条目超过 5min → 自动重取 → 触发新 listDirectory
- TST-T66: TTL 边界（恰好 5min）→ 根据实现（<=或<）验证行为
- TST-T67: 下拉刷新 → 清除缓存 → 无视 TTL 立即重取
- TST-T68: 容量 50 条时 → 所有条目保留
- TST-T69: 容量 51 条 → 最旧条目被移除
- TST-T70: 容量溢出后 → 新条目正常写入且可读取
- TST-T71: 被移除的条目再次访问 → 触发新网络请求

---

## 待实现 — 测试补充（P2 完善性）

### TST-10 "记住播放速度"开关测试

**来源**：测试缺口 (test.md §PLY-G08, SET-G01) | **优先级**：P2
**涉及文件**：`test/features/player/ply_07_test.dart`（追加）、`test/features/settings/settings_test.dart`（追加）
**依赖**：无
**关联缺口**：PLY-G08, SET-G01

**实现要点**：
- `rememberSpeedProvider` 默认值测试（true/false）
- 开启时：播放器中调速 → 同时更新 currentSpeed 和 defaultSpeed（持久化）
- 关闭时：播放器中调速 → 仅更新 currentSpeed，defaultSpeed 保持不变
- 切歌时：开启 → 新曲目使用上次调速后的 defaultSpeed；关闭 → 新曲目使用 Settings 中的 defaultSpeed
- `setRememberSpeedProvider` 持久化到 SharedPreferences
- Settings 页面 "记住播放速度" 开关 widget 测试

**测试用例**：TST-T72 ~ TST-T79
- TST-T72: rememberSpeed 默认为 true
- TST-T73: 开启时调速到 2.0x → defaultSpeed 同步更新为 2.0
- TST-T74: 开启时调速到 2.0x → SharedPreferences 持久化为 2.0
- TST-T75: 关闭时调速到 2.0x → defaultSpeed 保持原值不变
- TST-T76: 关闭时切歌 → 新曲目使用 Settings 中的 defaultSpeed
- TST-T77: 开启时切歌 → 新曲目使用上次播放器中的速度
- TST-T78: setRememberSpeed 持久化到 SharedPreferences
- TST-T79: Settings 页面开关 widget 渲染 → 切换后值更新

---

### TST-11 播放单拖拽排序与添加曲目弹窗

**来源**：测试缺口 (test.md §PLS-G02, PLS-G03, UI-G02) | **优先级**：P2
**涉及文件**：`test/features/playlist/ply_13_test.dart`（追加）、新建 `test/features/playlist/ply_14_test.dart`
**依赖**：无
**关联缺口**：PLS-G02, PLS-G03, UI-G02, LOG-G04

**实现要点**：
- 拖拽排序 Widget 测试：验证 ReorderableListView 渲染 → 长按拖拽 → onReorder 回调 → reorderPlaylistTrackProvider 被调用
- AddTracksBrowser Widget 测试：点击 FAB → 底部弹窗出现 → 目录浏览 → 选中文件(checkbox) → 全选/取消 → 确认添加 → addTracksToPlaylistProvider 被调用
- 独立 ProviderScope 隔离：验证 AddTracksBrowser 的导航状态不影响主页 Browser
- 去重：已存在的曲目不显示 checkbox（或标记为已添加）

**测试用例**：TST-T80 ~ TST-T90
- TST-T80: 拖拽曲目从 index 2 到 index 0 → onReorder 回调参数正确
- TST-T81: 拖拽后 track 列表顺序更新
- TST-T82: 拖拽后重新打开详情页 → 排序持久化
- TST-T83: AddTracksBrowser 弹窗出现 → 显示当前目录文件列表
- TST-T84: 选中 3 个文件 → 确认 → addTracks 被调用
- TST-T85: 全选按钮 → 所有文件被选中
- TST-T86: 取消全选 → 所有选择清除
- TST-T87: 已存在的曲目在弹窗中标记为不可选
- TST-T88: 弹窗内目录导航不污染主页 browser 导航栈
- TST-T89: 弹窗关闭 → 主页 browser 状态不变
- TST-T90: 取消弹窗 → 不添加任何曲目

---

### TST-12 连接切换影响面集成测试

**来源**：测试缺口 (test.md §INT-G01, CON-G02) | **优先级**：P2
**涉及文件**：新建 `test/features/connection/con_09_test.dart`
**依赖**：无
**关联缺口**：INT-G01, CON-G02, CON-G03

**实现要点**：
- 使用 sqflite_ffi + ProviderContainer，模拟两个连接的完整切换流程
- 步骤：连接 1 激活 → 浏览器加载缓存 → 播放队列活跃 → 切换到连接 2 → 验证缓存清除、队列清空
- 验证 `switchActiveConnectionProvider` 触发后：directoryCache 中旧连接 key 被清除、currentPlayQueueProvider 变为 null
- 验证密码写入失败时 DB 回滚的原子性
- 验证连接切换后 MiniPlayerBar 隐藏

**测试用例**：TST-T91 ~ TST-T98
- TST-T91: 切换连接 → directoryCache 中 connectionId=1 的条目被清除
- TST-T92: 切换连接 → currentPlayQueueProvider 变为 null
- TST-T93: 切换连接 → connectionId=2 的缓存不受影响（旧容器残留无关）
- TST-T94: 保存连接时 SecureStorage 写入失败 → DB 行回滚 → 连接不存在
- TST-T95: 保存连接时 DB 写入成功 + SecureStorage 成功 → 完整保存
- TST-T96: 切换后 Browser 使用新连接的 WebDAV 地址
- TST-T97: 切换后 activeConnectionProvider 返回新连接
- TST-T98: 切换后 connectionListProvider 刷新 → 新连接 isActive=true

---

### TST-13 App 生命周期完整链路测试

**来源**：测试缺口 (test.md §INT-G06, TMR-G03) | **优先级**：P2
**涉及文件**：`test/features/player/ply_03_test.dart`（追加）
**依赖**：无
**关联缺口**：INT-G06, TMR-G03

**实现要点**：
- 模拟完整生命周期：前台播放 → AppLifecycleState.paused（后台）→ 验证进度保存 + 后台播放继续 → AppLifecycleState.resumed（前台）→ 验证立即检查定时器到期
- 使用 mock AudioPlayer 和 BackgroundPlaybackNotifier
- 验证后台期间 duration timer 到期 → resume 时 checkExpired 立即返回 true
- 验证音频焦点变化：transient 丢失 → 不暂停 → 恢复 → gained

**测试用例**：TST-T99 ~ TST-T106
- TST-T99: 播放中 → paused → progress 保存调用
- TST-T100: 播放中 → paused → backgroundEnabled=true → playbackState 保持 playing
- TST-T101: 播放中 → detached → playbackState 变为 stopped
- TST-T102: 后台期间 timer 到期 → resume → checkExpired=true → pause() 立即调用
- TST-T103: transient 音频焦点丢失 → 播放状态不变
- TST-T104: 永久音频焦点丢失 → 播放状态变为 paused
- TST-T105: 焦点丢失后恢复 → 保持 paused 等待用户手动播放
- TST-T106: hidden → inactive → paused → resumed 完整生命周期序列

---

### TST-14 运行日志查看器测试

**来源**：测试缺口 (test.md §SET-G02, UI-G04) | **优先级**：P2
**涉及文件**：新建 `test/features/settings/log_viewer_test.dart`、`lib/features/settings/log_viewer_screen.dart`、`lib/core/services/log_buffer.dart`
**依赖**：无
**关联缺口**：SET-G02, UI-G04

**实现要点**：
- 单元测试 LogBuffer：环形缓冲区写入、容量 1000 条、溢出时移除最旧条目
- Widget 测试 LogViewerScreen（需 kDebugMode=true 或 override）
- 验证日志列表渲染 → 最新日志在底部 → 可滚动
- 验证空日志状态显示
- 验证日志级别颜色区分（info/debug/error）

**测试用例**：TST-T107 ~ TST-T113
- TST-T107: LogBuffer 写入 1 条 → 读取包含该条
- TST-T108: LogBuffer 写入 1001 条 → 最旧 1 条被移除 → size=1000
- TST-T109: LogViewerScreen 渲染日志列表
- TST-T110: 空日志 → 显示 "暂无日志" 空状态
- TST-T111: 新日志条目追加到列表底部
- TST-T112: error 级别日志显示红色文字
- TST-T113: LogBuffer.clear() → 所有条目清除

---

### TST-15 URL编码边界与并发竞争测试

**来源**：测试缺口 (test.md §LOG-G01, LOG-G02, PLY-G12) | **优先级**：P2
**涉及文件**：`test/features/player/ply_01_test.dart`（追加）、`test/features/player/ply_02_test.dart`（追加）
**依赖**：无
**关联缺口**：LOG-G01, LOG-G02, PLY-G12

**实现要点**：
- URL 编码更多边界字符：emoji(🎵)、#、?、&、+、单引号、双引号、% 自身
- 验证 buildUri 对所有特殊字符的正确 percent-encode
- SerializedRequestGate 并发竞争：3 个并发 schedule → 验证执行顺序 → 最新请求前的旧排队请求被 supersede
- SerializedRequestGate 快速连续 schedule 50 个请求 → 只有最后一个执行，其余被 supersede
- NasFile.fromProps 缺失字段容错：null props、空字符串、缺失 resourcetype

**测试用例**：TST-T114 ~ TST-T122
- TST-T114: URL 含 emoji → 正确 UTF-8 encode
- TST-T115: URL 含 # → 编码为 %23（非 fragment）
- TST-T116: URL 含 ? → 编码为 %3F（非 query）
- TST-T117: URL 含 & / + / % → 各自正确编码
- TST-T118: 单引号/双引号 → 正确编码
- TST-T119: SerializedRequestGate 50 个请求 → 仅最后一个执行，其余 superseded
- TST-T120: SerializedRequestGate 执行中 schedule 新请求 → 排队 → 旧排队被取代
- TST-T121: NasFile.fromProps(null props) → 不崩溃 → 返回有效 NasFile
- TST-T122: NasFile.fromProps 缺失字段 → 使用默认值

---

### TST-16 各模块补充测试（一）：Connection + Browser

**来源**：测试缺口汇总 | **优先级**：P2
**涉及文件**：`test/features/connection/con_01_test.dart`（追加）、`test/features/browser/brw_04_test.dart`（追加）、`test/features/browser/brw_07_test.dart`（追加）
**依赖**：无
**关联缺口**：CON-G04, CON-G05, BRW-G05, BRW-G06, BRW-G07, LOG-G03

**实现要点**：
- CON-G04: Widget 测试 — startupValidationProvider 返回 null → 显示 ONB_CTA 引导页
- CON-G05: Widget 测试 — 连接列表 Slidable 滑动 → 显示编辑/删除按钮 → 点击编辑跳转
- BRW-G05: Widget 测试 — 长按有进度文件 → context menu 含"清除播放进度" → 点击清除 → 进度条消失
- BRW-G06: 集成测试 — onFileTap 完整流程（已在 TST-04 覆盖，此处补充 browser 侧入口逻辑）
- BRW-G07: 单元测试 — loadProgressForDirectoryProvider → batch 查询目录内文件进度 → 返回 Map<filePath, PlayProgress>

**测试用例**：TST-T123 ~ TST-T131
- TST-T123: ONB_CTA 引导页渲染 → 图标 + 标题 + 描述 + 按钮
- TST-T124: Slidable 左滑 → 编辑按钮可见 → 点击 → push /connections/edit/:id
- TST-T125: Slidable 左滑 → 删除按钮可见 → 点击 → 确认弹窗
- TST-T126: 长按音频文件（有进度）→ context menu 出现"清除播放进度"
- TST-T127: 长按音频文件（无进度）→ context menu 不含"清除播放进度"
- TST-T128: 点击"清除播放进度" → progress bar 消失 → DAO 记录删除
- TST-T129: loadProgressForDirectoryProvider → 3 个文件有进度 → 返回 3 条
- TST-T130: loadProgressForDirectoryProvider → 空目录 → 返回空 Map
- TST-T131: NasFile.fromProps(null) / 空 props → 使用默认值不崩溃

---

### TST-17 各模块补充测试（二）：Player + Progress + Settings + Home

**来源**：测试缺口汇总 | **优先级**：P2
**涉及文件**：多个测试文件追加
**依赖**：无
**关联缺口**：PLY-G02, PLY-G03, PLY-G05, PLY-G06, PLY-G09, PLY-G10, PLY-G11, PRG-G02, PLS-G01, PLS-G06, SET-G03, UI-G05, UI-G06, UI-G07

**实现要点**：
- PLY-G02: 单元测试 — play() poll timeout 12s → TrackLoadResult.failed()
- PLY-G03: 单元测试 — setAudioSource 失败 → PlayerLoadState.error
- PLY-G06: Widget 测试 — QueueSheet 点击移除按钮 → 移除当前/非当前曲目 → 队列更新
- PLY-G11: 集成测试 — 队列 toMap → 新 session fromMap → 恢复不自动播放
- PRG-G02: 单元测试 — durationMs <= 10000 的文件不会被自动清理
- PLS-G01: Widget 测试 — 详情页 AppBar 编辑按钮 → 重命名弹窗 → 输入名称 → 列表更新
- PLS-G06: 单元测试 — Tab index 持久化到 SharedPreferences → 重启恢复
- SET-G03: Widget 测试 — 设置页 → 点击"管理 NAS 连接" → 导航到 /connections
- UI-G07: Widget 测试 — HomeScreen PopScope → 按 back → moveTaskToBack 被调用

**测试用例**：TST-T132 ~ TST-T148
- TST-T132: play() 12s poll timeout → TrackLoadResult.failed()
- TST-T133: setAudioSource throws → PlayerLoadState.error
- TST-T134: QueueSheet 移除当前曲目 → queue 自动切到下一首
- TST-T135: QueueSheet 移除非当前曲目 → currentIndex 调整
- TST-T136: QueueSheet 移除所有曲目 → queue=null → MiniPlayerBar 隐藏
- TST-T137: toMap/fromMap round-trip → 队列完整恢复 → 不自动播放
- TST-T138: durationMs <= 10000 的文件 → position > duration-10s → 不自动清除
- TST-T139: 重命名弹窗 → 输入"新名称" → 确认 → DAO updatePlaylist 被调用
- TST-T140: 重命名弹窗 → 空名称 → 确认按钮禁用
- TST-T141: Tab index 默认 0 → 切换到 1 → 持久化 → 新 container 读取为 1
- TST-T142: Tab index 首次启动 → 默认 0
- TST-T143: 设置页点击"管理 NAS 连接" → 导航到 /connections
- TST-T144: HomeScreen 按 back → moveTaskToBack 被调用 → 不退出 App
- TST-T145: 连接列表页渲染 → 有连接时显示连接列表
- TST-T146: 编辑连接页 → 表单预填原始数据
- TST-T147: 编辑连接页 → 修改 URL → 验证器重置为 idle
- TST-T148: 进度恢复队列 → startPositionMs 设置 → 播放器 seek 到该位置（但不自动播放）

---

## 已完成

### PRG-01 进度恢复对话框接入

**来源**：Bug 修复 | **优先级**：P0
**涉及文件**：`lib/features/progress/progress_dialog.dart`、`lib/features/browser/browser_screen.dart`、`lib/features/playlist/playlist_detail_screen.dart`
**依赖**：无
**关联 Bug**：PRG-A, BRW-A, LST-D

**实现要点**：
- `showProgressResumeDialog` 已完整实现但从未被调用，属于死代码
- 在 `browser_screen.dart:onFileTap` 构建 PlayQueue 前，查询 `playProgressProvider` 判断是否有已保存的进度
- 若有进度，弹出恢复对话框让用户选择：继续播放 / 从头开始
- 若选择继续，构建的 PlayQueue 需带 `startPositionMs`
- 同样在 `playlist_detail_screen.dart` 曲目点击处接入恢复对话框
- 对话框倒计时归零时自动选择"继续播放"

**测试用例**：PRG-FIX-T01 ~ PRG-FIX-T06
- PRG-FIX-T01: 有进度文件点击 → 弹出恢复对话框 → 选择继续 → 从保存位置播放
- PRG-FIX-T02: 有进度文件点击 → 弹出恢复对话框 → 选择从头开始 → 从头播放
- PRG-FIX-T03: 有进度文件点击 → 弹出恢复对话框 → 倒计时归零 → 自动从保存位置播放
- PRG-FIX-T04: 无进度文件点击 → 不弹对话框 → 直接从头播放
- PRG-FIX-T05: 播放单曲目点击 → 同样触发恢复对话框（如适用）
- PRG-FIX-T06: 进度 positionMs < 5000 的文件 → 不弹对话框

---

### CON-01 添加连接页面验证状态过期

**来源**：Bug 修复 | **优先级**：P0
**涉及文件**：`lib/features/connection/connection_screen.dart`、`lib/features/connection/widgets/connection_form.dart`
**依赖**：无
**关联 Bug**：CON-A

**实现要点**：
- `ConnectionScreen` 构建 `ConnectionForm` 时未传 `onFieldChanged` 回调（对比 `ConnectionEditScreen` 有此保护）
- 用户验证成功后可修改 URL/用户名/密码，保存按钮仍启用，用旧验证结果保存到错误服务器
- 修复：给 `ConnectionScreen` 的 `ConnectionForm` 传入 `onFieldChanged` 回调
- 当凭证字段（url/username/password/basePath）变更时，重置 `connectionValidatorProvider` 为 `ValidationIdle`
- 参考 `connection_edit_screen.dart:181-188` 的现成实现

**测试用例**：CON-FIX-T01 ~ CON-FIX-T04
- CON-FIX-T01: 验证成功后修改 URL → 保存按钮恢复禁用状态 → 需重新测试连接
- CON-FIX-T02: 验证成功后修改密码 → 保存按钮恢复禁用状态 → 需重新测试连接
- CON-FIX-T03: 验证成功后仅修改显示名称 → 保存按钮保持启用 → 直接保存
- CON-FIX-T04: 编辑页面凭证字段变更后 → 验证器重置（已有测试确认）

---

### CON-02 修复连接页面标题误导

**来源**：Bug 修复 | **优先级**：P1
**涉及文件**：`lib/features/connection/connection_screen.dart`
**依赖**：无
**关联 Bug**：CON-B

**实现要点**：
- `ConnectionScreen` 同时服务于"添加新连接"和"修复失败连接"两个场景（CON-T16 重定向）
- AppBar 标题始终为"添加 WebDAV 连接"，修复场景下用户看到的标题与上下文不符
- 修复：根据来源判断标题——若是 startup validation 失败重定向过来的，显示"修复 WebDAV 连接"
- 可通过路由参数传递来源标记，或在 `ConnectionScreen` 中读取 `startupValidationProvider` 状态

**测试用例**：CON-FIX-T05 ~ CON-FIX-T06
- CON-FIX-T05: 从 onboarding 正常添加连接 → 标题显示"添加 WebDAV 连接"
- CON-FIX-T06: 从 startup validation 失败重定向 → 标题显示"修复 WebDAV 连接"

---

### CON-03 LastConnectionException 未被 provider catch

**来源**：Bug 修复 | **优先级**：P1
**涉及文件**：`lib/features/connection/connection_provider.dart`
**依赖**：无
**关联 Bug**：CON-C

**实现要点**：
- `deleteConnectionProvider` 调用 `dao.delete(id)` 不 catch `LastConnectionException`
- 当前 `ConnectionListScreen` 在 UI 层做了 `totalCount <= 1` 前置检查（`connection_list_screen.dart:109`）
- 但存在竞态窗口：UI 检查通过后、DAO 执行前，连接数变为 1
- 修复：在 provider 层 catch `LastConnectionException`，转为可处理的 error state 或返回特定的失败结果
- 不依赖 UI 层的前置检查作为唯一的防护

**测试用例**：CON-FIX-T07 ~ CON-FIX-T08
- CON-FIX-T07: 删除非最后一个连接 → 正常删除 → SnackBar 提示
- CON-FIX-T08: 竞态条件下删除最后一个连接 → provider catch 异常 → 不 crash → SnackBar 错误提示

---

### CON-04 _originalConfig 双路径捕获

**来源**：Bug 修复 | **优先级**：P1
**涉及文件**：`lib/features/connection/connection_edit_screen.dart`
**依赖**：无
**关联 Bug**：CON-D

**实现要点**：
- `_originalConfig` 在 `addPostFrameCallback` 和 builder 中通过 `??=` 兜底双路径捕获
- `addPostFrameCallback` 可能在 builder 已捕获后读取到过时的 provider 数据
- 先到达者胜出，语义不清晰
- 修复：统一使用 `addPostFrameCallback` 捕获（在 first frame 后 connectionListProvider 最可靠）
- 或者改为 `initState` 中通过 `ref.read` 同步读取（如 provider 当时已就绪）

**测试用例**：CON-FIX-T09
- CON-FIX-T09: 编辑页面加载 → `_originalConfig` 正确捕获原始连接配置 → 凭证变更被准确追踪

---

### CON-05 isAttached 异常控制流

**来源**：Bug 修复 | **优先级**：P2
**涉及文件**：`lib/features/connection/widgets/connection_form.dart`
**依赖**：无
**关联 Bug**：CON-E

**实现要点**：
- `isAttached` 使用 try/catch 捕获 `LateInitializationError` 来判断 `_state` 是否已初始化
- 语义不清晰，属于反模式
- 修复：添加 `bool _isAttached = false` 标记，在 `attach()` 中设为 true，`detach()` 中设为 false

**测试用例**：CON-FIX-T10
- CON-FIX-T10: `isAttached` 在 attach 前后正确返回 false/true → 无异常抛出

---

### CON-06 name auto-fill 回调为空

**来源**：Bug 修复 | **优先级**：P2
**涉及文件**：`lib/features/connection/widgets/connection_form.dart`
**依赖**：无
**关联 Bug**：CON-F

**实现要点**：
- `_onUrlChanged()` 检查 name 是否为空，但 setState 块内为空（只有注释，没有实现）
- 实际 auto-fill 逻辑在 `_onUrlFocusLost()` 中（焦点丢失时触发）
- 如果用户输入 URL 后直接点测试/保存（不切换焦点），name 不会被自动填充
- 修复：将 auto-fill 逻辑搬入 `_onUrlChanged()` 的 setState 块中，与焦点丢失时行为一致

**测试用例**：CON-FIX-T11 ~ CON-FIX-T12
- CON-FIX-T11: 输入 URL 后直接点测试（不切换焦点）→ name 自动填充
- CON-FIX-T12: 输入 URL 后切换焦点 → name 自动填充（保持原有行为）

---

### CON-07 Onboarding 错误被静默处理

**来源**：Bug 修复 | **优先级**：P2
**涉及文件**：`lib/main.dart`
**依赖**：无
**关联 Bug**：CON-G

**实现要点**：
- `_OnboardingPage` 中 `connectionListProvider` 报错时 fallthrough 到 CTA 页面（`main.dart:194`）
- 数据库损坏、schema 不匹配等情况被静默处理，用户看到"添加第一个连接"引导
- 实际上用户已有连接，但数据库读取失败
- 修复：在 error 分支显示错误页面 + 重试按钮，而非 fallthrough 到 CTA

**测试用例**：CON-FIX-T13
- CON-FIX-T13: connectionListProvider 报错 → 显示错误页面（含重试按钮）→ 不显示 CTA

---

### PLY-01 Shuffle 模式非确定性

**来源**：Bug 修复 | **优先级**：P1
**涉及文件**：`lib/shared/models/play_queue.dart`
**依赖**：无
**关联 Bug**：PLY-A

**实现要点**：
- 当前 shuffle 每次随机选取非当前索引的曲目（`play_queue.dart:151-158`）
- 导致：点下一首再点上一首回不到原曲目、同一曲目可能短期内重复出现
- 修复：实现 Fisher-Yates shuffle 生成随机排列数组，播放时按数组顺序遍历
- 切换到 shuffle 模式时生成新排列，切换出 shuffle 后清空
- 排列数组需持久化到 SharedPreferences（与队列一起保存），保证恢复后次序一致

**测试用例**：PLY-FIX-T01 ~ PLY-FIX-T04
- PLY-FIX-T01: Shuffle 模式下跳过所有曲目 → 每首曲目恰好出现一次
- PLY-FIX-T02: Shuffle 模式下点下一首再点上一首 → 回到原曲目
- PLY-FIX-T03: 切换出 shuffle 再切回 → 生成新的随机排列
- PLY-FIX-T04: 队列只有 1 首时 shuffle → nextIndex 返回 null（仅 repeatOne/repeatAll 有效）

---

### PLY-02 Mini bar 播放按钮 idle 状态行为

**来源**：Bug 修复 | **优先级**：P1
**涉及文件**：`lib/features/player/widgets/mini_player_bar.dart`
**依赖**：无
**关联 Bug**：PLY-B

**实现要点**：
- 当前 `processingState == idle` 时，mini bar 播放按钮导航到 `/player`
- 问题：若 source 已加载但被通知栏 stop 后，state 为 idle 但 source 有效，应调用 `player.play()` 而非导航
- 修复：区分"无 source 已加载"（需导航去加载）和"source 已加载但未播放"（可直接 play）
- 可通过检查 `currentPlayQueueProvider` 和 `AudioPlayer.audioSource` 是否非空来判断

**测试用例**：PLY-FIX-T05 ~ PLY-FIX-T07
- PLY-FIX-T05: 通知栏点 stop 后 → mini bar 显示 → 点播放 → 直接播放（不导航）
- PLY-FIX-T06: 从未加载过 source → mini bar 不显示（队列为空）
- PLY-FIX-T07: 队列存在但 source 未加载 → 点播放 → 导航到 /player

---

### PLY-03 player.play() unawaited + 轮询超时

**来源**：Bug 修复 | **优先级**：P1
**涉及文件**：`lib/features/player/player_provider.dart`
**依赖**：无
**关联 Bug**：PLY-C

**实现要点**：
- `player.play()` 以 unawaited 方式调用，然后用 200ms × 40 次 = 8 秒轮询检测 `player.playing` 状态
- 这是 audio_service 平台通道竞争的 workaround（注释 A-4）
- 8 秒超时可能造成假失败报告
- 修复方案（可选其一）：
  - 增加超时时间到更保守的值
  - 改为监听 `playerStateStream` 的 `playing` 状态变化（事件驱动 + timeout 兜底）
  - 在超时后检查 `player.playing` 再做最终判断（二次确认避免假失败）

**测试用例**：PLY-FIX-T08 ~ PLY-FIX-T09
- PLY-FIX-T08: 正常播放 → play() 成功 → 无超时 → 状态为 ready
- PLY-FIX-T09: 平台通道慢 → play() 延迟成功 → 不误报失败 → 最终状态为 ready

---

### PLY-04 连接切换后 phantom player bar

**来源**：Bug 修复 | **优先级**：P1
**涉及文件**：`lib/features/player/player_provider.dart`、`lib/features/browser/browser_provider.dart`
**依赖**：无
**关联 Bug**：PLY-D

**实现要点**：
- 队列持久化时保存了 `lastQueueConnectionId`（`browser_provider.dart:310`）
- 启动恢复时若连接不匹配，queue 保留在内存但不 pre-load AudioSource（`browser_provider.dart:365-374`）
- MiniPlayerBar 读取 `currentPlayQueueProvider` — queue 非 null → 显示，但无法播放
- 修复：在连接切换时，若 `lastQueueConnectionId != activeConnection.id`，清空 `currentPlayQueueProvider`
- 或在 mini bar 可见性判断中加入连接匹配检查

**测试用例**：PLY-FIX-T10 ~ PLY-FIX-T11
- PLY-FIX-T10: 切换连接后 → 旧队列清空 → mini bar 隐藏
- PLY-FIX-T11: 相同连接的队列恢复 → mini bar 正常显示 → 可播放

---

### PLY-05 Processing 监听器 dispose 竞态

**来源**：Bug 修复 | **优先级**：P2
**涉及文件**：`lib/features/player/player_provider.dart`
**依赖**：无
**关联 Bug**：PLY-E

**实现要点**：
- processingStateStream 监听器在 provider 容器 dispose 后可能仍触发回调
- 回调中读取 Riverpod state 会抛异常
- 修复：在监听器回调开头检查 `_isDisposed` 标志位
- 或在 provider 的 `ref.onDispose` 中取消 stream subscription

**测试用例**：PLY-FIX-T12
- PLY-FIX-T12: App 快速退出（播放中 kill）→ 不抛 StateError → 优雅退出

---

### PLY-06 BackgroundPlaybackConfig 未接入 NasAudioHandler

**来源**：Bug 修复 | **优先级**：P2
**涉及文件**：`lib/core/services/audio_handler.dart`、`lib/features/player/background_playback.dart`
**依赖**：无
**关联 Bug**：PLY-F

**实现要点**：
- `BackgroundPlaybackConfig` 状态机在 `background_playback.dart` 中完整定义，但 `NasAudioHandler` 直接读 `playerStateStream` 推送通知状态
- 应该是 `NasAudioHandler` 使用 `BackgroundPlaybackNotifier` 作为播放状态的真实来源
- 或者将 `BackgroundPlaybackConfig` 作为文档/测试用模型保留，handler 不受影响
- 决策：评估是否需要接入；如不需要，添加注释说明 handler 是运行时代码，BackgroundPlaybackConfig 是纯逻辑模型

**测试用例**：PLY-FIX-T13
- PLY-FIX-T13: 确认 handler 和 BackgroundPlaybackConfig 之间关系已明确（接入或有文档注释）

---

### TMR-01 定时器状态手动 invalidate 脆弱

**来源**：Bug 修复 | **优先级**：P1
**涉及文件**：`lib/features/timer/timer_provider.dart`
**依赖**：无
**关联 Bug**：TMR-A

**实现要点**：
- 每次 timer 操作后需手动 `ref.invalidate(timerStateProvider)`（共 5 处：`timer_provider.dart:136,153,163,179,196`）
- 新增操作容易遗漏，导致 UI 展示过期状态
- 修复：将 `timerStateProvider` 从 `StateProvider` 改为 `StateNotifierProvider` 或 `NotifierProvider`
- 所有状态变更在 Notifier 内部完成，自动通知监听者，消除手动 invalidate

**测试用例**：TMR-FIX-T01 ~ TMR-FIX-T03
- TMR-FIX-T01: 启动定时器 → UI 立即显示倒计时（无延迟）
- TMR-FIX-T02: 取消定时器 → UI 立即清除倒计时
- TMR-FIX-T03: 新增操作 → 无需手动 invalidate → UI 自动更新

---

### TMR-02 后台定时器到期检测延迟

**来源**：Bug 修复 | **优先级**：P2
**涉及文件**：`lib/features/player/player_screen.dart`
**依赖**：无
**关联 Bug**：TMR-B

**实现要点**：
- `checkExpired()` 靠 PlayerScreen 内 `Timer.periodic` 每秒轮询（`player_screen.dart:79-85`）
- App 在后台期间轮询停止，定时器到期检测推迟到 App 回到前台
- 修复：启动定时器时记录 `endTime`，在 App 回到前台（`didChangeAppLifecycleState(resumed)`）时主动检查一次
- 这样可以在 resume 时立即检测到已过期的定时器

**测试用例**：TMR-FIX-T04
- TMR-FIX-T04: 启动 1 分钟定时器 → 退到后台 → 2 分钟后回到前台 → 立即检测到到期 → 暂停播放

---

### TMR-03 定时器无暂停状态

**来源**：新功能 | **优先级**：P2
**涉及文件**：`lib/core/services/timer_service.dart`、`lib/features/timer/timer_provider.dart`
**依赖**：TMR-01

**实现要点**：
- 当前定时器只有 idle / running 两种状态，无法暂停
- 新增 `TimerMode.paused` 状态，记录剩余时间
- `pause()` 保存剩余 duration，`resume()` 从剩余时间继续倒计时
- UI 按钮：定时器运行中显示暂停按钮，暂停中显示继续/取消按钮
- 先在 TimerService 纯逻辑层实现，再接入 Provider

**测试用例**：TMR-T01 ~ TMR-T04
- TMR-T01: 启动 5 分钟定时器 → 剩余 3 分钟时暂停 → 状态为 paused → 剩余时间保持 3 分钟
- TMR-T02: 暂停后恢复 → 继续从 3 分钟倒计时
- TMR-T03: 暂停后取消 → 回到 idle
- TMR-T04: 暂停状态是纯逻辑状态 → startDuration 覆盖 paused → 新定时器启动

---

### PRG-02 进度存储单活跃记录模式

**来源**：Bug 修复 | **优先级**：P1
**涉及文件**：`lib/core/database/dao/progress_dao.dart`、`lib/features/browser/browser_provider.dart`
**依赖**：PRG-01
**关联 Bug**：PRG-B, BRW-C

**实现要点**：
- `upsertLatest()` 删除所有旧行再插入新记录（`progress_dao.dart:92-123`）
- 一次只追踪一个文件的进度，切换歌曲后旧进度永久丢失
- 这是有意的设计选择（注释 line 432），但代价显著
- 修复：改为 `(connectionId, filePath)` 复合唯一键的 UPSERT
- `_progressRegistryProvider`（`browser_provider.dart:432-451`）也需改为支持多记录查询
- Browser 文件列表中已有进度的文件可显示进度标记

**测试用例**：PRG-FIX-T01 ~ PRG-FIX-T04
- PRG-FIX-T01: 播放 A 到 30s → 切换到 B 播放到 20s → 切回 A → A 进度仍在 30s
- PRG-FIX-T02: 同一文件多次保存 → 只保留最新一条记录
- PRG-FIX-T03: 文件播完（position > duration - 10s）→ 对应文件记录清除
- PRG-FIX-T04: 浏览器文件列表 → 有进度的文件显示进度标记

---

### PRG-03 目录缓存无 TTL

**来源**：Bug 修复 | **优先级**：P2
**涉及文件**：`lib/features/browser/browser_provider.dart`
**依赖**：无
**关联 Bug**：BRW-B

**实现要点**：
- `directoryCacheProvider` 仅 LRU 淘汰（50 条目上限），无 TTL（`browser_provider.dart:209`）
- 长时间运行 session 可能展示过期数据
- 修复：每个缓存条目附带时间戳，读取时检查年龄
- 超过合理 TTL（如 5 分钟）的条目视为过期，自动重取
- 下拉刷新时也清理过期条目

**测试用例**：BRW-FIX-T01 ~ BRW-FIX-T02
- BRW-FIX-T01: 缓存条目在 TTL 内 → 直接返回缓存 → 不发起网络请求
- BRW-FIX-T02: 缓存条目超过 TTL → 透明重取 → 用户看到最新数据

---

### PLS-01 播放单重命名

**来源**：新功能 | **优先级**：P1
**涉及文件**：`lib/features/playlist/playlist_detail_screen.dart`、`lib/features/playlist/playlist_provider.dart`、`lib/core/database/dao/playlist_dao.dart`
**依赖**：无
**关联 Bug**：LST-A

**实现要点**：
- `PlaylistDao.updatePlaylist()` 方法已存在（`playlist_dao.dart:37-42`），只需接入 UI
- 播放单详情页 AppBar 添加编辑按钮 → 弹出重命名对话框
- 调用 `updatePlaylistProvider(id, newName)` → dao.updatePlaylist() → invalidate list provider
- 播放单列表页也可通过长按 / Slidable 进入重命名

**测试用例**：PLS-T01 ~ PLS-T03
- PLS-T01: 详情页点击编辑 → 弹窗 → 输入新名称 → 保存 → 列表和详情页同步更新
- PLS-T02: 重命名为空字符串 → 验证失败 → 提示"名称不能为空"
- PLS-T03: 重命名为已存在的名称 → 允许保存（无唯一名称约束）

---

### PLS-02 播放单元数据编辑

**来源**：新功能 | **优先级**：P1
**涉及文件**：`lib/features/playlist/playlist_detail_screen.dart`、`lib/shared/models/playlist.dart`
**依赖**：无
**关联 Bug**：LST-B

**实现要点**：
- 当前播放单只有名称字段可编辑（且尚未接入 UI）
- 如需扩展字段：描述、封面图等
- 在 `playlist_detail_screen.dart` 中添加编辑入口（详情页底部或设置菜单）
- 更新 `Playlist` 模型（如需要新字段则需 DB migration）

**测试用例**：PLS-T04 ~ PLS-T05
- PLS-T04: 编辑播放单描述 → 保存 → 详情页显示新描述
- PLS-T05: 编辑后取消 → 不保存变更 → 原始数据不变

---

### PLS-03 播放单曲目拖拽排序

**来源**：新功能 | **优先级**：P2
**涉及文件**：`lib/features/playlist/playlist_detail_screen.dart`、`lib/core/database/dao/playlist_dao.dart`
**依赖**：无
**关联 Bug**：LST-C

**实现要点**：
- 当前排序仅支持 `added_at` 和名称，无手动拖拽排序
- 引入 `ReorderableListView` 替换当前 `ListView`
- 需在 `playlist_tracks` 表增加 `sort_order` 列（需 DB migration v3）
- `dao.addTracks()` 默认设置 `sort_order` 为当前最大 + 1
- 拖拽后更新受影响的曲目 `sort_order`

**测试用例**：PLS-T06 ~ PLS-T08
- PLS-T06: 拖拽曲目从位置 5 到位置 2 → 排序正确持久化 → 重新打开排序保持
- PLS-T07: 添加新曲目 → 自动排到最后
- PLS-T08: 切换到名称排序 → 拖拽排序临时禁用 → 切回手动排序恢复

---

### PLS-04 播放单曲目不检查已保存进度

**来源**：Bug 修复 | **优先级**：P2
**涉及文件**：`lib/features/playlist/playlist_detail_screen.dart`
**依赖**：PRG-01
**关联 Bug**：LST-D

**实现要点**：
- 与 PRG-01 同一修复的范围，在播放单曲目点击处接入进度恢复对话框
- 播放单详情页 `onTrackTap` 构建 PlayQueue 前查询进度
- 若有进度，弹出恢复对话框；无进度则直接从头播放

**测试用例**：PRG-FIX-T05 已覆盖（见 PRG-01）

---

### PLS-05 播放单导出/导入

**来源**：新功能 | **优先级**：P2
**涉及文件**：`lib/features/playlist/playlist_provider.dart`、`lib/shared/models/playlist.dart`
**依赖**：无
**关联 Bug**：LST-E

**实现要点**：
- 导出为 JSON 格式（含播放单元数据和曲目路径列表）
- 通过 share_plus 分享文件
- 导入：从文件选择器选取 JSON → 解析 → 创建新播放单 → 添加曲目（跳过不存在的文件路径）
- 注意跨 NAS 场景：曲目路径可能在不同连接间不可用

**测试用例**：PLS-T09 ~ PLS-T12
- PLS-T09: 导出播放单 → 生成 JSON 文件 → 通过分享发送
- PLS-T10: 导入 JSON → 创建新播放单 → 曲目列表正确
- PLS-T11: 导入含不存在路径的 JSON → 跳过缺失曲目 → 添加存在的曲目
- PLS-T12: 导入格式错误的 JSON → 错误提示 → 不崩溃

---

### HOM-01 Tab index 持久化

**来源**：Bug 修复 | **优先级**：P2
**涉及文件**：`lib/features/home/home_screen.dart`
**依赖**：无
**关联 Bug**：HOM-A

**实现要点**：
- 当前 TabBar index 不持久化，App 重启后重置为 Tab 0
- 修复：将当前 tab index 保存到 SharedPreferences
- 启动时读取，恢复到上次的 tab

**测试用例**：HOM-FIX-T01 ~ HOM-FIX-T02
- HOM-FIX-T01: 切换到 Tab 1 → 重启 App → 自动显示 Tab 1
- HOM-FIX-T02: 首次启动 → 默认显示 Tab 0

---

### HOM-02 AppBar 排序菜单交互优化

**来源**：Bug 修复 | **优先级**：P2
**涉及文件**：`lib/features/home/home_screen.dart`
**依赖**：无
**关联 Bug**：HOM-B

**实现要点**：
- 两个排序菜单（播放单排序、文件排序）共享 AppBar 空间
- 当前交互依赖 PopupMenuButton 默认行为（点击外部关闭）
- 评估是否需要改进为更明确的关闭方式
- 可选方案：选中排序项后菜单自动关闭（PopupMenuButton 默认行为已满足）

**测试用例**：HOM-FIX-T03
- HOM-FIX-T03: 选择排序项 → 菜单自动关闭 → 排序立即生效

---

## 已完成

<!-- 已完成条目按时间倒序排列，格式与待实现一致 -->

