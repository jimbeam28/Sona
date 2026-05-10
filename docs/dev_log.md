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
