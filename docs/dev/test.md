# Sona 测试用例分析报告

> 基于 architecture.md（整体架构）和 state.md（状态机设计）与当前测试现状的对比分析。
> 生成日期: 2026-05-23

---

## 1. 概览

| 维度 | 数值 |
|------|------|
| 测试文件数 | 30 |
| 测试代码总行数 | ~14,800 |
| 源码文件数 | 44 |
| 已覆盖功能模块 | 7 (Connection / Browser / Player / Timer / Progress / Playlist / Settings) |

---

## 2. 各模块测试现状与缺口

### 2.1 Connection（连接管理）— 测试较完整

**已有测试**: con_01 ~ con_08（7 个文件）

- [x] 表单字段验证（空URL/用户名/密码 → 必填错误）
- [x] URL 规范化（裸IP、域名、端口补全）
- [x] 显示名称自动填充、basePath 默认值
- [x] 验证状态机（idle→loading→success/error）
- [x] 验证重复点击防重入（re-entry guard）
- [x] DAO CRUD（insert/findById/findAll/update）
- [x] setActive 事务切换（唯一活跃连接）
- [x] 启动自动验证（success/401 error）
- [x] 密码引用 key 存储（非明文）
- [x] 编辑连接（凭证变更需重验证、仅名称可直接保存）
- [x] 删除连接（级联删除进度、最后连接保护、自动激活其余连接）
- [x] 密码存储的完整生命周期（保存/更新/删除）
- [x] DDNS 域名验证
- [x] 表单 UI 测试（校验错误、loading、成功/失败提示条）
- [x] 密码可见性切换
- [x] 引导页 UI（空连接列表）
- [x] 修复模式标题（startup validation 失败重定向）

**缺失用例**:

| # | 缺失场景 | 类型 | 相关状态/架构 |
|---|---------|------|-------------|
| CON-G01 | onboarding 有连接且验证成功 → 直接 go(/browser) 完整流程 | 集成 | state.md 1.2 路由转移 |
| CON-G02 | 连接切换时清除浏览器缓存 + 清空队列的端到端验证 | 集成 | architecture.md 4.1, state.md 9.4 |
| CON-G03 | 保存时密码写入 SecureStorage 失败 → 回滚 DB 行（原子性） | 单元 | state.md 2.2 保存流程 |
| CON-G04 | 启动自动验证为 null（无活跃连接）→ 显示 ONB_CTA 引导页 | Widget | state.md 2.1 Onboarding |
| CON-G05 | 连接列表 Slidable 左滑编辑/删除的交互测试 | Widget | architecture.md 4.1 |

### 2.2 Browser（文件浏览）— 测试较完整

**已有测试**: brw_01 ~ brw_07（7 个文件）

- [x] PROPFIND XML 解析（混合目录/文件、非音频文件、空目录、特殊字符）
- [x] 音频格式识别（8 种格式 + "有声书"/"audiobook" 关键词）
- [x] 非音频文件过滤
- [x] 排序逻辑（nameAsc/nameDesc/modifiedDesc，目录始终优先）
- [x] 导航栈（push/pop/popTo/根目录防pop）
- [x] 面包屑溢出折叠计算（computeBreadcrumbLayout）
- [x] 播放队列构建（过滤目录→保留音频顺序→设置 currentIndex）
- [x] 目录缓存（首次加载、缓存复用、连接隔离、刷新清除）
- [x] 下拉刷新（缓存清除、重新请求、成功/失败处理）
- [x] 排序偏好持久化（SharedPreferences 读写）
- [x] Widget 测试（loading骨架、错误+重试、空目录、进度条显示、有声书图标）

**缺失用例**:

| # | 缺失场景 | 类型 | 相关状态/架构 |
|---|---------|------|-------------|
| BRW-G01 | 面包屑导航 widget 交互测试（点击层级跳转、渲染） | Widget | architecture.md 4.2 |
| BRW-G02 | PopScope 返回拦截逻辑 — 子目录拦截 back，根目录允许退出 | Widget | state.md 6.2 |
| BRW-G03 | 缓存 TTL 5分钟过期 → 自动重新请求 | 单元 | state.md 6.4 |
| BRW-G04 | 缓存容量上限 50 条 → 溢出时移除最旧条目 | 单元 | state.md 6.4 |
| BRW-G05 | 长按文件清除进度的 widget 测试（context menu → clear） | Widget | architecture.md 4.2 |
| BRW-G06 | onFileTap 完整流程 — 有进度时弹出恢复对话框 → 选择继续/从头 | 集成 | state.md 6.5 |
| BRW-G07 | loadProgressForDirectory 批量加载目录内文件进度 | 单元 | architecture.md 4.2 |

### 2.3 Player（音频播放）— 核心逻辑较完整，缺少集成和 UI 测试

**已有测试**: ply_01 ~ ply_08（8 个文件）

- [x] Basic Auth header 构建（base64、特殊字符、UTF-8）
- [x] AudioSource 构建（URI 拼接、headers、basePath 保留）
- [x] URL 编码（空格、中文、方括号、baseUrl/filePath 规范化）
- [x] 错误处理（WebDavException、PlayerLoadState、401/403）
- [x] PlayerLoadState 状态转换（idle→loading→ready→error）
- [x] SerializedRequestGate（串行执行、排队、最新请求优先）
- [x] clampSeek（有效范围、负数、超出范围）
- [x] skipForward/skipBackward（15s 默认、各步长、边界）
- [x] 速度选项（6 档、排序、验证、容差）
- [x] formatDuration（MM:SS、H:MM:SS、null 占位符）
- [x] 后台播放状态机（生命周期转换、通知控件、音频焦点）
- [x] 通知标题提取（extractTitleFromPath、多语言）
- [x] 耳机按钮映射（单击/双击/三击 → playPause/next/prev）
- [x] 封面显示逻辑（TrackMetadata、有/无封面）
- [x] 播放队列模型（构建、nextIndex/previousIndex、四种播放模式）
- [x] 队列恢复（toMap/fromMap、startPositionMs）
- [x] 启动进度恢复（applyLatestProgressToQueue、sanitizeResumePosition）
- [x] 播放模式切换（循环、图标映射、标签映射）
- [x] 速度持久化（defaultSpeed vs currentSpeed、rememberSpeed）
- [x] 迷你播放器 widget（可见性、曲目名、播放/暂停按钮、导航）
- [x] 队列弹窗（QueueSheet 滚动、点击跳转）

**缺失用例**:

| # | 缺失场景 | 类型 | 相关状态/架构 |
|---|---------|------|-------------|
| PLY-G01 | 完整自动切歌流程 — processingState=completed → nextIndex → loadAndPlay | 集成 | state.md 3.8 |
| PLY-G02 | 曲目加载超时检测（12s play() poll timeout） | 单元 | architecture.md 4.3 |
| PLY-G03 | AudioPlayer.setAudioSource 失败 → PlayerLoadState.error | 单元 | state.md 3.1 |
| PLY-G04 | 播放器全屏页面 widget 测试（控件渲染、seek 拖拽、速度弹窗） | Widget | architecture.md 4.3 |
| PLY-G05 | MiniPlayerBar 与实际播放状态同步（Stream 广播、Timer 显示） | 集成 | state.md 3.7 |
| PLY-G06 | 队列移除 widget 测试 — 移除当前曲目（切下一首）、移除非当前曲目、清空隐藏 | Widget | state.md 3.5 |
| PLY-G07 | 从播放单点击曲目 → 构建队列 → 播放的跨模块流程 | 集成 | state.md 7.2 |
| PLY-G08 | "记住播放速度" 开关 — 调速时同步更新 defaultSpeed | 单元 | architecture.md 4.3 |
| PLY-G09 | 全屏播放器与迷你播放器 Stream 同步（同一 AudioPlayer 单例） | 集成 | state.md 3.7 |
| PLY-G10 | 音频焦点电话中断 → transient 丢失→恢复的完整行为 | 集成 | state.md 3（AudioFocus） |
| PLY-G11 | 队列持久化完整流程 — serialize → restart → restore → seek（不自动播） | 集成 | state.md 3.4 |
| PLY-G12 | URL 编码更多边界（emoji、#、?、&、+、单引号） | 单元 | PLY-T07 |

### 2.4 Timer（定时停止）— 核心逻辑完整，缺少暂停/恢复和新状态

**已有测试**: timer_test.dart（1 个文件）

- [x] 固定时长定时（5/10/15min，endTime 计算）
- [x] 模式替换（新定时器覆盖旧定时器）
- [x] "播完当前"模式（startAfterCurrent、onTrackCompleted、触发后清除）
- [x] 手动切歌不触发 afterCurrent
- [x] 倒计时格式化（MM:SS、>60s、<60s、00:00、null）
- [x] 取消定时（激活时取消→返回true、无定时时取消→幂等返回false）
- [x] 到期检测（checkExpired、afterCurrent不通过checkExpired到期）
- [x] 模式互斥切换（duration→afterCurrent、afterCurrent→duration）
- [x] Provider 层（timerStateProvider、startDuration/startAfterCurrent/cancel、timerActive/Mode）
- [x] TimerButton widget（未激活菜单、激活菜单含取消、选择定时、取消定时）
- [x] 自定义时长（确认按钮禁用逻辑、持久化上次时长、快捷项显示）

**缺失用例**:

| # | 缺失场景 | 类型 | 相关状态/架构 |
|---|---------|------|-------------|
| TMR-G01 | **暂停/恢复功能**（state.md 新增 paused 状态） | 单元 | state.md 4.1-4.2 |
| TMR-G02 | 定时到期 → player.pause() 完整触发链路（Timer.periodic → checkExpired → pause） | 集成 | state.md 4.3 |
| TMR-G03 | App 从后台恢复时立即检查到期状态 | 单元 | state.md 4.3 |
| TMR-G04 | afterCurrent 到期 → player.pause()（processingStateStream → onTrackCompleted） | 集成 | state.md 4.4 |
| TMR-G05 | 定时器激活时在播放器全屏页显示具体倒计时（非仅图标） | Widget | architecture.md 4.4 |

### 2.5 Progress（播放进度）— 测试较完整

**已有测试**: prg_test.dart（1 个文件，~1330 行）

- [x] upsert 新增/更新（UPSERT 语义）
- [x] 智能过滤 — position<5s 跳过、position>duration-10s 清除
- [x] 边界值（恰好5s保存、恰好duration-10s不清除）
- [x] 暂停/切歌/后台/关闭触发保存（DAO 层模拟）
- [x] 查询（find、按connectionId隔离、percentage）
- [x] getRecentlyPlayed（排序、limit）
- [x] findLatest（单条活跃记录迁移、upsertLatest 替换旧记录）
- [x] 恢复对话框 widget（格式化显示、继续播放/从头播放、倒计时）
- [x] 5s 倒计时自动选择继续（fake_async）
- [x] 清除进度（菜单逻辑、DAO delete、清除后UI反应）
- [x] shouldSave/shouldClear 静态方法

**缺失用例**:

| # | 缺失场景 | 类型 | 相关状态/架构 |
|---|---------|------|-------------|
| PRG-G01 | 5个保存触发点的集成验证 — Timer.periodic(10s)、暂停、切歌、后台、dispose | 集成 | state.md 5.3 |
| PRG-G02 | 短于10秒的文件不被自动清理的完整验证 | 单元 | state.md 5.1 |
| PRG-G03 | 从播放单点击曲目 → progressForFileProvider → 有进度→弹对话框 | 集成 | state.md 7.2 |
| PRG-G04 | upsertLatest 替换旧记录后旧记录确实被删除（非隐藏） | 单元 | architecture.md 4.5 |

### 2.6 Playlist（播放单）— 基础 CRUD 已覆盖，缺少部分功能

**已有测试**: ply_09 ~ ply_13（5 个文件）

- [x] HomeScreen Tab 导航（两个Tab、AppBar、MiniPlayerBar）
- [x] DAO CRUD（insertPlaylist、findAllPlaylists含trackCount、update、delete级联、addTracks、removeTracks、trackExists去重）
- [x] 模型序列化（fromMap/toMap、toNasFile、m4b→audiobook）
- [x] 数据库迁移 v1→v2
- [x] Provider 层（create、delete、addTracks去重、removeTracks）
- [x] 排序（playlistSort: nameAsc/nameDesc/createdAsc/createdDesc、trackSort: nameAsc/nameDesc/addedAsc/addedDesc）
- [x] 播放单列表 widget（空状态、FAB创建、列表项渲染、Slidable左滑删除、确认对话框、loading骨架）
- [x] 播放单详情 widget（loading、空列表、曲目列表、点击播放、长按选择、全选/取消、删除确认、selection AppBar、退出selection）

**缺失用例**:

| # | 缺失场景 | 类型 | 相关状态/架构 |
|---|---------|------|-------------|
| PLS-G01 | 播放单重命名（updatePlaylistProvider → dao.updatePlaylist → invalidate） | Widget | state.md 7.3 |
| PLS-G02 | 曲目拖拽排序（ReorderableListView drag → reorderPlaylistTrackProvider） | Widget | architecture.md 4.7, state.md 7.3 |
| PLS-G03 | 添加曲目弹窗 AddTracksBrowser（独立 ProviderScope 目录浏览、全选/取消/批量添加） | Widget | architecture.md 4.7 |
| PLS-G04 | 播放单导出（exportPlaylistProvider → JSON encode → 分享） | 单元 | state.md 7.3 |
| PLS-G05 | 播放单导入（importPlaylistProvider → JSON decode → insert + addTracks） | 单元 | state.md 7.3 |
| PLS-G06 | Tab 索引持久化（重启后恢复上次选择的 Tab） | 单元 | state.md 8.1 |

### 2.7 Settings（设置）— 较完整

**已有测试**: settings_test.dart（1 个文件）

- [x] 默认播放速度读写持久化（6 个速度全验证）
- [x] currentSpeed 变更不影响 defaultSpeed
- [x] 主题切换（system/light/dark 持久化、重启恢复）
- [x] 快进/快退步长（4 个选项持久化、无效值拒绝）
- [x] seekStepSettingProvider 同步 seekStepProvider
- [x] 设置页面 widget（4 个 Section、ListTile 副标题、对话框交互）
- [x] 关于页面（应用名、版本号、开源许可列表）
- [x] label 辅助函数

**缺失用例**:

| # | 缺失场景 | 类型 | 相关状态/架构 |
|---|---------|------|-------------|
| SET-G01 | "记住播放速度" 开关（rememberSpeedProvider / setRememberSpeedProvider） | 单元 | architecture.md 4.6 |
| SET-G02 | 运行日志查看器（LogViewerScreen、LogBuffer 环形缓冲区 1000 条） | Widget | architecture.md 4.6 |
| SET-G03 | 设置页 → 连接管理 → 连接列表 → 编辑连接的导航流程 | Widget | state.md 1.2 |

---

## 3. 跨功能集成测试缺口

| # | 缺失场景 | 涉及模块 | 说明 |
|---|---------|---------|------|
| INT-G01 | 连接切换完整影响面 | Connection + Browser + Player | 切换活跃连接 → 清除缓存 → 清空队列 → MiniPlayerBar 隐藏 |
| INT-G02 | 完整播放→进度保存→重启恢复链路 | Browser + Player + Progress | 选文件→播放→自动保存→App 被杀→重启→恢复队列+进度→用户手动播放 |
| INT-G03 | Timer 到期 → Player 暂停链路 | Timer + Player | 固定时长定时到期 → pause() → 清除 TimerState / afterCurrent 曲终 → pause() |
| INT-G04 | 从播放单曲目点击的完整流程 | Playlist + Progress + Player | 点击曲目→检查进度→弹对话框→构建PlayQueue→导航/player→加载→播放 |
| INT-G05 | 路由完整导航流程 | 全部 | Onboarding→Connection→Browser→Player→Settings→Connections→Edit |
| INT-G06 | App 生命周期完整链路 | Player + Timer + Progress | 前台播放→进入后台(保存进度+继续播放)→音频焦点变化→恢复前台 |

---

## 4. 纯逻辑层测试缺口

| # | 缺失函数/逻辑 | 文件 | 说明 |
|---|-------------|------|------|
| LOG-G01 | `AudioSourceBuilder.buildUri` 与 `buildWithBasePath` 更多边界 | audio_source_builder.dart | emoji、#、&、+、单引号等特殊字符的 URL 编码 |
| LOG-G02 | `SerializedRequestGate` 并发竞争条件 | player_provider.dart | 高频率调度下的请求顺序保证 |
| LOG-G03 | `NasFile.fromProps` 边界情况 | nas_file.dart | 缺失字段、null props、异常 XML |
| LOG-G04 | `PlaylistDao.reorderTrack` | playlist_dao.dart | 拖拽排序的数据层逻辑 |
| LOG-G05 | `exportPlaylist` / `importPlaylist` 的 JSON 序列化 | playlist_provider.dart | JSON 格式正确性、导入去重 |

---

## 5. Widget/UI 测试缺口

| # | 缺失页面/组件 | 说明 |
|---|-------------|------|
| UI-G01 | `PlayerScreen` 全屏播放器 | 控件布局、seek 拖拽交互、速度弹窗、播放模式切换 |
| UI-G02 | `AddTracksBrowser` 底部弹窗 | 目录浏览、文件选择、全选/确认 |
| UI-G03 | `BreadcrumbBar` 面包屑导航 | 渲染、点击跳转、溢出折叠显示 |
| UI-G04 | `LogViewerScreen` 日志查看器 | 日志列表、滚动、过滤 |
| UI-G05 | `ConnectionListScreen` 完整交互 | Slidable 滑动、切换确认、编辑导航 |
| UI-G06 | `ConnectionEditScreen` 编辑页 | 预填字段、凭证变更提示、保存逻辑 |
| UI-G07 | `HomeScreen` PopScope 拦截返回键 | back 键 → moveTaskToBack 非退出 |

---

## 6. 测试优先级建议

### P0（核心路径必须覆盖）

1. **PLY-G01** — 完整自动切歌流程（processingState → nextIndex → loadAndPlay）
2. **INT-G02** — 播放进度保存与恢复的端到端链路
3. **INT-G03** — Timer 到期 → Player 暂停链路
4. **INT-G04** — 播放单曲目点击的完整播放流程

### P1（重要功能缺失）

5. **TMR-G01** — 暂停/恢复功能（state.md 新增 paused 状态）
6. **PLS-G04/PLS-G05** — 播放单导出/导入
7. **UI-G01** — PlayerScreen 全屏播放器 widget 测试
8. **UI-G03** — BreadcrumbBar 面包屑交互测试
9. **BRW-G03/G04** — 缓存 TTL 过期和容量上限

### P2（完善性补充）

10. **PLY-G08** — "记住播放速度" 开关
11. **PLS-G02/G03** — 曲目拖拽排序、添加曲目弹窗
12. **UI-G02** — AddTracksBrowser widget 测试
13. **INT-G01/G06** — 连接切换影响面、App 生命周期链路
14. **SET-G02** — 运行日志查看器

---

## 7. 测试质量观察

1. **纯逻辑测试覆盖较好** — TimerService、PlayQueue 导航、seek 计算、进度过滤规则等纯函数均已有单元测试，符合 architecture.md 设计原则 1
2. **Widget 测试集中在列表页面** — PlaylistList、PlaylistDetail、MiniPlayerBar 等有 widget 测试，但全屏 PlayerScreen、BreadcrumbBar、AddTracksBrowser 等复杂 UI 组件缺少
3. **集成测试不足** — 跨模块的完整用户流程（选文件→播放→保存→恢复）缺少端到端验证
4. **Mock 策略一致** — 使用手写 mock（WebDavClient、SecureStorage、ConnectionDao、AudioPlayer），不使用 build_runner 代码生成
5. **数据库测试使用 sqflite_ffi 内存数据库** — 每个用例独立 setUp/tearDown，符合 CLAUDE.md 测试注意事项
