# 开发计划

> 基于 [state.md §10 问题汇总表](state.md#10-问题汇总表) 生成。
> 来源：Sona 全功能状态机分析，发现 28 个设计/实现问题。

---

## 待实现

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

