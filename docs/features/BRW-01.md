# 功能详细设计文档：BRW-01 文件夹级操作（从此处播放 / 加入播放单）

```yaml
id: BRW-01
name: 文件夹级操作（递归播放与加入播放单）
priority: P1
status: active
created_at: 2026-08-23
last_updated: 2026-08-23
spec_anchored_files:
  - lib/features/browser/browser_screen.dart
  - lib/features/browser/widgets/file_list_item.dart
  - lib/features/browser/browser_provider.dart
  - lib/features/playlist/domain/playlist_service.dart
  - lib/shared/models/play_queue.dart
  - lib/core/network/webdav_client.dart
cross_module_impacts: [PLY, PRG]
manual_qa_required: false
```

---

## §1 用户视角

### 1.0 原始需求（用户原话逐字记录）

> 采纳 A 的 1~4（A4 = 文件夹级操作）。访谈裁决记录（2026-08-23）：
> "**入口**：目录行长按 → bottom sheet：「从此处播放」「加入播放单…」。与文件长按（进度恢复）互不干扰。"
> "**收集语义**：递归先序遍历，每层套用当前 SortOption，只收 isAudioFile；建队用当前 playMode。"
> "**规模保护**：扫描时 loading 弹窗（'正在扫描…'）+ 上限 500 首截断并提示；单层 PROPFIND 超时对齐 P17 分层表。"
> "**中途失败**：整体失败报错回退，不用半截结果建队。"
> 用户对"顺带把文件长按升级为统一菜单"未表态 → 按保守默认**不做**（范围控制）。

### 1.1 这一功能干什么（一句话）

在文件浏览器里长按一个文件夹，可以把整个文件夹（含所有子文件夹）的音频一次性播放或加入某个播放单。

### 1.2 用户期望的场景

| ID | 你看到的样子 | 期望行为 |
|----|----|----|
| U1 | 浏览器里长按一个文件夹 | 弹出两个选项：「从此处播放」「加入播放单…」 |
| U2 | 选「从此处播放」 | 出现"正在扫描文件夹…"提示；扫完后直接进入播放器开始播放，队列=该文件夹下所有子文件夹里的音频，顺序和平时浏览时每层看到的排序一致 |
| U3 | 文件夹很大（超过 500 首） | 只取前 500 首，提示"已截取前 500 首"，不会卡死 |
| U4 | 扫到一半网络断了 | 提示失败，不会播一半截断的列表；界面回到原样 |
| U5 | 选「加入播放单…」 | 先扫描，然后弹出播放单列表让你选；选完提示已添加 |
| U6 | 还没有任何播放单 / 想新建 | 列表里有「新建播放单」，起个名字确认后自动加入进去 |
| U7 | 文件夹里没有音频只有子目录 | 提示"该文件夹没有音频文件"，不进入播放器 |
| U8 | 长按的是文件（不是文件夹） | 和以前完全一样：有进度的弹恢复框，没进度的无反应 |

---

## §2 已实现的功能骨架（代码锚点）

### 2.1 文件与分层

| 层 | 文件 | 关键位置 | 角色 |
|---|---|---|---|
| UI | lib/features/browser/widgets/file_list_item.dart | :17-38 DirectoryListTile——仅 onTap，**无 onLongPress** | 需加长按参数 |
| UI | lib/features/browser/browser_screen.dart | :169-192 onFileTap 建队+跳转参照系（queue 构造→provider 写入→push '/player'）；:194-234 onFileLongPress 进度恢复（不可破坏）；:416-423 目录分支接线点；:395-397 _FileList 回调参数区 | 主改造面 |
| Provider | lib/features/browser/browser_provider.dart | :92-135 directoryContentsProvider（family by path）：TTL/LRU 缓存命中→否则 PROPFIND→过滤→sortFiles 排序→写缓存；抛 WebDavException 中文错误 | 逐层取数复用它（缓存+排序免费） |
| Domain(新) | lib/features/browser/domain/folder_collector.dart | 新文件 | 纯遍历逻辑 |
| PLY 域 | lib/shared/models/play_queue.dart | :55-62 构造；:114 withMode | 建队 |
| Bridge | lib/shared/di/providers.dart | :205-222 playlist export 段（addTracksToPlaylistProvider/playlistListProvider 等）；playModeProvider 经同文件桥接（browser_screen O3 注释先例） | 跨 feature 符号源 |

### 2.2 现有行为逆抽

- **建队参照系**（browser_screen.dart:182-192）：`PlayQueue(files: audioFiles, currentIndex: startIndex, startPositionMs: startPositionMs).withMode(ref.read(playModeProvider))` → 写 currentPlayQueueProvider → 写 lastQueueConnectionIdProvider(connId) → `goRouter.push('/player')`。其中 files 为**当前目录**已排序音频（:130 区段收集），startPositionMs 来自进度恢复对话框（本功能该值恒 null）。
- **逐层排序现状**：directoryContentsProvider 返回前必经 `sortFiles(filtered, sortOption)`（browser_provider.dart:131-134 与缓存命中分支 :98-99），SortOption 经 sortOptionProvider 注入。→ 收集器拿到的每层天然是用户当前排序。
- **过滤现状**：只保留 `e.isDirectory || e.audioType != null`（:126-130）；audioType 由 NasFile.classifyPath 按扩展名判定（nas_file.dart classifyPath）。
- **超时分层**：listDirectory 内部 http 请求带超时（webdav_client.dart:220 区段），P17 表网络层 5s/30s 分层由 core 层负责——收集器自身不加超时，透传底层异常。
- **去重现状**：addTracksToPlaylist 内部去重（playlist_service.dart:74-95），重复添加同一文件静默丢弃、不报错。
- **createPlaylist 返回新 id**：playlist_service.dart:44 `Future<int> createPlaylist(String name)`；但 di 导出的 createPlaylistProvider 包装成 `Future<void>`（playlist_provider.dart:92-98）——新建即加入路径必须改用 service 直连（见 S7）。

---

## §3 行为规约（Given-When-Then）

### 3.1 Domain 层：folder_collector.dart（新文件）

```dart
const int kFolderScanMaxFiles = 500;

class FolderScanResult {
  final List<NasFile> files;   // 仅 audioType != null 的条目，先序排列
  final bool truncated;        // 达到 maxFiles 截断
  const FolderScanResult({required this.files, required this.truncated});
}

/// DFS 先序收集 rootPath 子树内全部音频文件。
/// [fetchDir] 由调用方注入（生产传 directoryContentsProvider，测试传 fake），
/// 抛出的任何异常原样向上传播——本函数不做 catch（整体失败语义归 UI 裁决）。
Future<FolderScanResult> collectFolderAudio({
  required String rootPath,
  required Future<List<NasFile>> Function(String path) fetchDir,
  int maxFiles = kFolderScanMaxFiles,
}) async {
  final collected = <NasFile>[];
  var truncated = false;
  final stack = <String>[rootPath];
  while (stack.isNotEmpty && !truncated) {
    final dir = stack.removeLast();
    final entries = await fetchDir(dir);
    final subDirs = <NasFile>[];
    for (final e in entries) {
      if (e.isDirectory) {
        subDirs.add(e);
      } else if (e.audioType != null && collected.length < maxFiles) {
        collected.add(e);
        if (collected.length == maxFiles) truncated = true;
      }
    }
    // 反向压栈保证先序（列表顺序 = 用户当前排序）
    for (final d in subDirs.reversed) {
      stack.add(d.path);
    }
  }
  return FolderScanResult(files: collected, truncated: truncated);
}
```

- **[BRW-01-S1] 先序遍历与排序保持**
  ```
  Given 树：root 含 [B.mp3, 子目录A(内含 A1.mp3), C.mp3]，各层 fetchDir 返回序即上列
  When collectFolderAudio(root)
  Then 结果序 = [B.mp3, A1.mp3, C.mp3]（本层音频在前、随后按子目录出现顺序深入）
  否定断言:
    - 目录条目不出现在结果中
    - audioType == null 的文件（非音频）不出现
    - fetchDir 的调用次序 = root → 子目录A（先序，不广度优先）
  ```
  Code evidence: 排序来源 browser_provider.dart:131-134；分类 nas_file.dart classifyPath

- **[BRW-01-S2] 截断**
  ```
  Given maxFiles=500，子树含 600 个音频
  When collectFolderAudio
  Then files.length==500 且 truncated==true，且第 500 个之后不再发起多余 fetchDir
       （截断发生在"收满即停"，允许最后一个子目录层已 fetch 但其音频不再收录）
  否定断言:
    - 不抛异常（截断是正常路径）
    - files.length 不超过 500
  ```

- **[BRW-01-S3] 错误透传**
  ```
  Given 任一层 fetchDir 抛 WebDavException('没有活跃的连接') 或网络异常
  When collectFolderAudio
  Then 异常原样向上抛，不返回部分结果
  否定断言:
    - 不 catch、不吞、不打日志（日志职责在 UI 层，catch-log 裁决 SCHEMA §5）
  ```
  Code evidence: directoryContentsProvider 抛错点 browser_provider.dart:94/:105-112/:118

### 3.2 UI 层：长按菜单与两条流程

- **[BRW-01-S4] 目录长按菜单**
  ```
  Given DirectoryListTile 增加 optional onLongPress 参数（file_list_item.dart:17-38 构造+ListTile 接线）
        _FileList 增加 onDirectoryLongPress 回调并在 :416-423 目录分支传入
  When 长按目录行
  Then showModalBottomSheet 弹出两项：Icons.play_circle_outline '从此处播放'、
       Icons.playlist_add '加入播放单…'
  否定断言:
    - 目录行 onTap 进入子目录的行为不变（:420-422）
    - AudioFileListTile 的 onLongPress（进度恢复）与 onPlayNext 一概不动（:425-436）
    - onDirectoryLongPress 为 null 时目录行无长按响应（与现状一致，测试 helper 兼容）
  ```
  Code evidence: file_list_item.dart:17-38；browser_screen.dart:416-423

- **[BRW-01-S5] 从此处播放**
  ```
  Given 用户对目录 D 选「从此处播放」
  When 流程执行
  Then ① showDialog(barrierDismissible:false) 显示 CircularProgressIndicator+'正在扫描文件夹…'
       ② await collectFolderAudio(rootPath: D.path, fetchDir: (p) => ref.read(directoryContentsProvider(p).future))
       ③ 关闭 loading 对话框（Navigator.pop，成功失败都要关）
       ④ result.files 为空 → SnackBar '该文件夹没有音频文件'，流程终止
       ⑤ 非空 → 完全复刻 onFileTap 建队形态：
          PlayQueue(files: result.files, currentIndex: 0).withMode(ref.read(playModeProvider))
          → currentPlayQueueProvider.notifier.state = queue
          → lastQueueConnectionIdProvider.notifier.state = 活跃连接 id
          → GoRouter.of(context).push('/player')
       ⑥ result.truncated == true → 追加 SnackBar '文件夹较大，已截取前 ${kFolderScanMaxFiles} 首'
  否定断言:
    - 不查询进度、不弹恢复对话框（startPositionMs 恒 null——文件夹入口从第一首开头播；
      单曲级续播仍走文件点击入口）
    - 不修改 playModeProvider（读取 only）
    - 失败路径下 currentPlayQueueProvider / lastQueueConnectionIdProvider 一个都不写（S7）
    - 不使用半截数据：任何一层抛错即整条流程终止于错误提示
  ```
  Code evidence: 建队参照 browser_screen.dart:182-192；GoRouter 获取方式 :172

- **[BRW-01-S6] 扫描失败的用户反馈**
  ```
  Given 步骤② 抛出任意异常
  When catch
  Then 先 debugPrint('[Browser] folder scan failed: $e')（catch-log 裁决，日志留痕）
  And SnackBar 固定文案 '无法读取文件夹内容，请检查连接'
       （不把 $e 直接给用户——WebDAV URL 可能含敏感信息，secret-logs 纪律同理适用于 UI 文案）
  否定断言:
    - loading 对话框在 catch 分支同样被关闭（无残留遮罩）
    - 不 push('/player')
  ```
  依据：SCHEMA §5 全局裁决（静默吞错禁止）；脱敏先例 redactUrlForLog 用法

- **[BRW-01-S7] 加入播放单——选择已有**
  ```
  Given 用户选「加入播放单…」且扫描成功非空
  When 第二个 showModalBottomSheet 渲染
  Then 列表项来自 ref.watch(playlistListProvider)（AsyncValue 三态：loading 圈/error 文案+重试/data 列表，
       空列表显示 '还没有播放单' + 新建入口仍可用）
  And 点击某播放单 → await ref.read(addTracksToPlaylistProvider)(playlist.id, scanResult.files)
      → 关闭全部面板 → SnackBar '已添加 ${scanResult.files.length} 首'
  否定断言:
    - 去重导致的实际入库数少于 N 时不额外提示（既有静默去重语义，playlist_service.dart:74-95）
    - 选择面板期间不阻塞返回键关闭（普通 bottom sheet 语义）
  ```
  Code evidence: playlistListProvider playlist_provider.dart:73-79；addTracksToPlaylistProvider :121-129（含 invalidate 双缓存）

- **[BRW-01-S8] 加入播放单——新建即加入**
  ```
  Given 选择面板底部固定一项 '新建播放单'
  When 点击 → showDialog 含 TextField + 确认按钮
  Then 确认按钮在输入 trim 后为空时禁用（门禁语义同 playlist_list_screen.dart:167-168）
  And 确认 → final newId = await ref.read(playlistServiceProvider).createPlaylist(trimmedName)
      （service 直连取返回 id；di show 清单补导出 playlistServiceProvider，见 S9）
      → await ref.read(addTracksToPlaylistProvider)(newId, scanResult.files)
      → 关闭全部面板 → SnackBar '已添加 ${files.length} 首'
  否定断言:
    - 不使用 createPlaylistProvider（其包装丢 id，playlist_provider.dart:92-98）
    - 名称不做一般性 trim 存储（沿用 REF-07 裁决：仅空串校验，前后空格原样入库）
  ```
  Code evidence: playlist_service.dart:44 `Future<int> createPlaylist(String name)`

- **[BRW-01-S9] di 导出登记**
  ```
  Given lib/shared/di/providers.dart :205-222 playlist 段 show 清单
  When 补导出
  Then 追加 `playlistServiceProvider`（Infrastructure 注释组，紧邻 playlistDaoProvider）
  否定断言:
    - browser feature 对 playlist 的 import 只出现在 shared/di 一个方向
      （cross-imports.sh feature-isolation 0 新违规）
  ```
  Code evidence: playlistDaoProvider 已导出先例 providers.dart:208

---

## §4 不变量

- **[BRW-01-INV1]** 本功能零改动现有文件点击/文件长按/"下一首播"三条既有交互路径。
  证据：browser_screen.dart:128-236 tap/longpress 体不动，仅在 :395-397 参数区追加目录回调
- **[BRW-01-INV2]** collectFolderAudio 是纯遍历编排：无 Provider/http/Flutter 依赖，一切 IO 经 fetchDir 注入。
  证据：§3.1 签名；domain 层零 Flutter 纪律（CLAUDE.md 架构分层）
- **[BRW-01-INV3]** 文件夹入口产生的队列 startPositionMs 恒为 null。
  证据：S5⑤ 建队参数表
- **[BRW-01-INV4]** 收集上限常量唯一来源 `kFolderScanMaxFiles`，UI 文案引用同一常量不得手写 500。
  证据：S2/S5⑥

---

## §5 测试规约

### 5.1 现有测试清单

| 测试文件 | 覆盖 | 备注 |
|---|---|---|
| test/features/browser/brw_02_test.dart 等 brw_01~09 族 | 目录导航/排序/缓存既有行为 | INV1 回归网，不改一字全绿 |
| test/helpers/fake_webdav_client.dart | WebDAV fake | collector 测试可直接造嵌套假数据，不必动它 |

### 5.2 测试 ID 派生清单

```
BRW-01-S1 ~ S9
BRW-01-INV1 ~ INV4
BRW-01-ALG1（先序+截断样例表）
```

### 5.3 测试覆盖盲点

| 未覆盖 ID | 现状 | 应补偿方式 |
|---|---|---|
| S5⑥ 截断提示 | 无 | widget 测试：truncated=true 时 SnackBar 文案出现 |
| S7 AsyncValue error 态 | 无 | 面板渲染测试：playlistListProvider 注入 AsyncError → 显示错误+新建入口可用 |
| S3 多层混合错误位置 | 无 | fake 第 2 层抛错 → expect(throwsA) 且首层数据未泄漏到调用方 |

### 5.4 门禁测试文件位置

```
test/features/browser/brw_01_folder_actions_test.dart   # S1~S9 + INV2/3/4 + ALG1
```
（命名核查 2026-08-23：test/features/browser/ 已有 brw_01_test.dart（旧 BRW-01 号段占用），故用描述性后缀 brw_01_folder_actions_test.dart，无同名冲突。）

---

## §6 算法样例

```
ALG [BRW-01-ALG1-collectFolderAudio]:
  # DFS 先序；maxFiles 截断；fetchDir 序即调用序
  输入: root=[B.mp3, dirA(A1.mp3), C.mp3]
        → 期望: files=[B,A1,C], truncated=false, fetch 序 root→dirA     # S1
  输入: root=[dirX(X.mp3), B.mp3]
        → 期望: files=[X,B]（子目录内容先于同层后续音频——严格先序）      # 先序裁决
  输入: 600 音频扁平树, maxFiles=500
        → 期望: 前 500 个按层序, truncated=true                          # S2
  输入: root 仅含 dirEmpty(empty)
        → 期望: files=[], truncated=false                                # U7
  输入: root=[note.txt, dirA]
        → 期望: note.txt 不收录（audioType==null 过滤）                   # S1 否定面
  输入: 第 2 层 fetchDir 抛 WebDavException
        → 期望: 异常上抛, 无 FolderScanResult                            # S3
```

---

## §7 跨模块影响

| 其它 feature | 影响点 | 影响条件 | 需要补的回归断言 |
|---|---|---|---|
| PLY | 建队写入 currentPlayQueueProvider → persistQueueOnChange 自动持久化 → 重启恢复 | 从此处播放后杀进程 | 恢复队列 == 截断后的收集序（复用 net1_legacy_queue_restore_test 读取路径一次） |
| PLY | playModeProvider 只读消费（withMode），shuffle 下建队生成排列 | 当前模式 shuffle | o3_create_queue_play_mode_test 全绿即可（同构路径已被该测试覆盖） |
| PRG | 文件夹入口不查进度 → 不触发 progressForFileProvider 读路径 | 任意 | bug_bug18 族（进度读裸奔加固）不受影响，全绿即可 |
| PLY | addTracksToPlaylistProvider invalidate 双缓存 | 加入后播放单页刷新 | BUG-22 修复测试（删除后 family 缓存）不改一字全绿 |

---

## §8 平台特性与手动 QA

逐条核对 docs/dev/platform-pitfalls.md：

| 踩坑条目 | 是否触及 | 处置 |
|---|---|---|
| P17 超时分层 | 是 | 收集器不加自造超时，逐层透传 directoryContentsProvider 底层超时语义（core 层 5s/30s 分层不变）；S6 统一兜底反馈 |
| P14 async gap 竞态 | 是 | 扫描 await 期间用户可能切换活跃连接 → fetchDir 每层实时 read provider，连接切换后后续层走新连接（可接受：整体失败语义兜底 401 类错误）；spec 显式承认此窗口，不做连接快照冻结 |
| P13 setState defunct | 是 | await 后使用 context 前置 `if (!context.mounted) return`（BUG-25-S4 教训：State 级 mounted 检查，ef3d386 先例） |
| P11 build 期改 provider | 否 | 全部动作在回调内，不在 build |
| P10 单一写源 | 是 | 队列写入口复用 currentPlayQueueProvider 单点，与 onFileTap 同构 |

**可行性依据（铁律 6）：**

- R1 `context.mounted` 在 async gap 后的使用模式：仓库已有大量同款（browser_screen.dart:214 `if (progress == null || !context.mounted) return;`），属"现有代码已在用的同款模式"，不需重复验证。
- R2 FutureProvider.family 以 `.future` 作函数式逐层取数（`ref.read(directoryContentsProvider(p).future)`）：riverpod 2.x 标准 API；同文件 :120 区段已在 watch 同一 provider，read(.future) 形态在 test/helpers 与 REF-06 测试多处出现（brw_05/brw_06）。现有代码同款，无需新依据。

**真机风险列：**

| 风险 | 近似测试方案 | 测不了 → 进 mqa-backlog |
|---|---|---|
| 深层大文件夹真机扫描总耗时（多层 RTT 叠加，loading 可能数十秒） | fake 无法测真实 RTT | MQA：50 层/2000 文件 NAS 目录实测扫描时长与体验 |
| 真实 NAS 对连续快速 PROPFIND 的速率限制/连接数限制 | fake 无限速 | MQA：群晖/威联通实测是否 429/拒连 |
| 移动网络弱网下中途失败的报错时机 | 单元层已覆盖抛错路径，时序无法模拟 | 低风险，不进 backlog |

本功能不涉平台原生通道（无 audio_service/MethodChannel 改动），manual_qa_required=false。

---

## §9 dev-status.json 条目对照

```json
"BRW-01": {
  "spec_file": "docs/features/BRW-01.md",
  "spec_anchored_files": [
    "lib/features/browser/browser_screen.dart",
    "lib/features/browser/widgets/file_list_item.dart",
    "lib/features/browser/browser_provider.dart",
    "lib/features/playlist/domain/playlist_service.dart",
    "lib/shared/models/play_queue.dart",
    "lib/core/network/webdav_client.dart"
  ],
  "scenarios": ["BRW-01-S1","BRW-01-S2","BRW-01-S3","BRW-01-S4","BRW-01-S5","BRW-01-S6","BRW-01-S7","BRW-01-S8","BRW-01-S9"],
  "invariants": ["BRW-01-INV1","BRW-01-INV2","BRW-01-INV3","BRW-01-INV4"],
  "algorithms": ["BRW-01-ALG1-collectFolderAudio"],
  "test_files": ["test/features/browser/brw_01_folder_actions_test.dart"],
  "test_coverage_gaps": [],
  "cross_module_impacts": ["PLY", "PRG"],
  "manual_qa_required": false,
  "dependencies": [],
  "impl_status": "pending",
  "test_status": "pending",
  "check_status": "pending"
}
```
