# Browser 模块功能设计

## 1. 模块概述

Browser 模块负责展示 NAS 上的文件目录结构，支持目录导航、音频文件过滤、文件选择播放。是用户与 NAS 内容交互的主要入口。

---

## 2. 功能列表

| 功能编号 | 功能名称 | 优先级 |
|----------|----------|--------|
| BRW-01 | 目录列表加载 | P0 |
| BRW-02 | 目录导航（进入/返回） | P0 |
| BRW-03 | 音频文件过滤 | P0 |
| BRW-04 | 选择文件播放 | P0 |
| BRW-05 | 目录内容缓存 | P1 |
| BRW-06 | 下拉刷新 | P1 |
| BRW-07 | 文件排序 | P1 |

---

## 3. 功能详细设计

### BRW-01 目录列表加载

**触发时机：** 进入 Browser 页面，或导航到新目录

**加载流程：**
```
发起 WebDAV PROPFIND 请求（depth=1）
    → 解析响应，分离目录和文件
    → 过滤支持的音频格式
    → 按名称排序
    → 渲染列表
```

**支持的音频格式：** `.mp3` `.flac` `.aac` `.m4a` `.m4b` `.ogg` `.opus` `.wav`

**加载状态：**
- 加载中：显示骨架屏（Skeleton）
- 加载成功：显示文件列表
- 加载失败：显示错误提示 + 重试按钮
- 空目录：显示「此目录为空」提示

---

### BRW-02 目录导航

**进入子目录：** 点击目录项 → 加载子目录内容 → 更新面包屑导航

**返回上级：** 点击面包屑路径节点，或系统返回键

**面包屑设计：**
```
NAS根目录 / 音乐 / 周杰伦 / 十一月的萧邦
```
- 点击任意节点直接跳转到对应层级
- 超出屏幕宽度时，最左侧折叠为 `...`

**导航栈：** 使用路径栈管理，支持多级返回

---

### BRW-03 音频文件过滤

**默认行为：** 只显示目录和支持的音频文件，隐藏其他文件（图片、文档等）

**显示规则：**
- 目录：始终显示（可能包含音频）
- 音频文件：显示，带格式图标区分（音乐 vs 有声书）
- 其他文件：隐藏

**格式图标区分：**
- `.m4b` / 文件名含「有声书」「audiobook」：显示有声书图标
- 其他音频：显示音乐图标

---

### BRW-04 选择文件播放

**单文件播放：** 点击音频文件 → 将当前目录所有音频加入播放队列 → 从点击的文件开始播放 → 跳转播放器��面

**播放队列构建逻辑：**
- 将当前目录下所有音频文件按当前排序顺序加入队列
- 点击的文件作为队列起始位置

**进度恢复：** 若该文件有保存的播放进度，弹出提示：
```
「上次播放到 12:34，是否从此处继续？」
[从头播放]  [继续播放]
```

---

### BRW-05 目录内容缓存

**缓存策略：** 内存缓存，应用生命周期内有效

**缓存 key：** 连接ID + 目录路径

**缓存失效：** 下拉刷新时清除当前目录缓存

**目的：** 减少重复的 WebDAV 请求，提升导航流畅度

---

### BRW-06 下拉刷新

**触发：** 在列表顶部下拉

**行为：** 清除当前目录缓存 → 重新发起 PROPFIND 请求 → 更新列表

---

### BRW-07 文件排序

**排序选项：**
- 按名称升序（默认）
- 按名称降序
- 按修改时间降序

**持久化：** 排序偏好保存到 SharedPreferences，下次启动保持

---

## 4. 数据模型

```dart
class NasFile {
  final String name;
  final String path;
  final bool isDirectory;
  final int? size;           // 字节，目录为 null
  final DateTime? modifiedAt;
  final AudioFileType? audioType;  // music / audiobook / null（目录）
}

enum AudioFileType { music, audiobook }
```

---

## 5. Provider 设计

```dart
// 当前目录内容
@riverpod
Future<List<NasFile>> directoryContents(
  DirectoryContentsRef ref,
  String path,
);

// 当前导航路径栈
@riverpod
class NavigationStack extends _$NavigationStack {
  // state: List<String> paths
  void push(String path);
  void popTo(String path);
}

// 文件排序偏好
@riverpod
class SortPreference extends _$SortPreference {
  // state: SortOption enum
}
```

---

## 6. UI 结构

```
BrowserScreen
├── BreadcrumbBar          # 面包屑导航
├── SortButton             # 排序切换按钮
└── FileListView           # 文件列表
    ├── DirectoryItem      # 目录行
    └── AudioFileItem      # 音频文件行（含格式图标、时长）
```

---

## 7. 关键文件

| 文件 | 职责 |
|------|------|
| `lib/features/browser/browser_screen.dart` | 文件浏览主页面 |
| `lib/features/browser/browser_provider.dart` | 目录内容状态管理 |
| `lib/features/browser/widgets/breadcrumb_bar.dart` | 面包屑导航组件 |
| `lib/features/browser/widgets/file_list_item.dart` | 文件列表行组件 |
| `lib/core/network/webdav_client.dart` | WebDAV 目录列表请求 |
| `lib/shared/models/nas_file.dart` | 文件数据模型 |
