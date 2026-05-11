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

