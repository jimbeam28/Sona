# 开发日志

---

## [2026-05-21] [PLY-10] - 播放单数据层（数据库 + 模型 + DAO）

**状态**: ✅ 成功

### 修改文件
- `lib/shared/models/playlist.dart` — 新建 Playlist 和 PlaylistTrack 模型
- `lib/core/database/dao/playlist_dao.dart` — 新建 PlaylistDao（CRUD + 批量操作 + 去重检查）
- `lib/core/database/database_helper.dart` — 数据库 v1→v2 迁移，新增 playlists/playlist_tracks 表，启用外键约束
- `test/features/playlist/ply_10_test.dart` — 新建测试文件

### 测试结果
- 通过: 17 / 总计: 17

---

## [2026-05-21] [PLY-11] - 播放单 Provider 层

**状态**: ✅ 成功

### 修改文件
- `lib/features/playlist/playlist_provider.dart` — 新建 Provider 层（排序枚举、数据 Provider、变更 Provider）
- `test/features/playlist/ply_11_test.dart` — 新建测试文件

### 测试结果
- 通过: 12 / 总计: 12

---

## [2026-05-21] [PLY-12] - 播放单列表页

**状态**: ✅ 成功

### 修改文件
- `lib/features/playlist/playlist_list_screen.dart` — 新建列表页（loading/error/empty 三态，FAB 创建，滑动删除）
- `lib/features/playlist/widgets/playlist_list_item.dart` — 新建列表项组件（名称 + 曲目数量）
- `test/features/playlist/ply_12_test.dart` — 新建测试文件

### 测试结果
- 通过: 8 / 总计: 8

---

## [2026-05-21] [PLY-13] - 播放单详情页 + 添加曲目弹窗

**状态**: ✅ 成功

### 修改文件
- `lib/features/playlist/playlist_detail_screen.dart` — 新建详情页（普通/选择模式 AppBar，曲目列表，点击播放，长按选择）
- `lib/features/playlist/widgets/playlist_track_item.dart` — 新建曲目项组件（文件名 + 选择状态）
- `lib/features/playlist/widgets/add_tracks_browser.dart` — 新建添加曲目弹窗（独立导航栈、目录浏览、多选确认）
- `test/features/playlist/ply_13_test.dart` — 新建测试文件

### 测试结果
- 通过: 11 / 总计: 11

---

## [2026-05-21] [PLY-09] - 播放单主入口 + Tab 导航

**状态**: ✅ 成功

### 修改文件
- `lib/features/home/home_screen.dart` — 新建主屏幕（TabController + 统一 AppBar + MiniPlayerBar）
- `lib/features/browser/browser_screen.dart` — 改造：去除 Scaffold/AppBar，仅返回 body 内容
- `lib/main.dart` — 路由：/browser → HomeScreen，新增 /playlist/:id
- `test/features/playlist/ply_09_test.dart` — 新建测试文件
- `test/features/browser/brw_01_test.dart` — 适配 BrowserScreen 改造（包裹 Scaffold）
- `test/features/browser/brw_07_test.dart` — 适配（包裹 Scaffold，移除 AppBar sort 测试）

### 测试结果
- 通过: 7 / 总计: 7

---

## [2026-05-21] [CON-08] - 连接表单支持 DDNS 域名提示

**状态**: ✅ 成功

### 修改文件
- `lib/features/connection/widgets/connection_form.dart` — 更新 hintText 和校验提示文案，增加域名示例
- `test/features/connection/con_08_test.dart` — 新建测试文件

### 测试结果
- 通过: 4 / 总计: 4





