# BUG-33 — 扫描类操作逐层放大 secure-storage 读与目录缓存冲刷（F1）

## §0 头部元数据

```yaml
id: BUG-33
name: 扫描类操作逐层放大 secure-storage 读与目录缓存冲刷
priority: P2
status: active
created_at: 2026-08-29
last_updated: 2026-08-29
spec_anchored_files:
  - lib/features/browser/browser_provider.dart
  - lib/features/browser/browser_screen.dart
  - test/features/browser/bug_33_repro_test.dart
cross_module_impacts: [BRW, SRCH, DL]   # 文件夹扫描(BRW-01)、搜索(SRCH-01)、目录下载(DL-01-S8)
parent_feature: null                     # 跨模块：根因在浏览器共享 fetchDir 接线，无单一归属
manual_qa_required: false
```

---

## §1 用户视角

### 1.0 原始需求（用户原话逐字记录）

来源：`docs/cr/cr-20260826-0027.md` F1（cr 复核分流，用户裁决 → dev-plan Bug 流程，repro 门禁已确认真实 FAIL）：

> ### F1【Minor】扫描类操作逐层放大 secure-storage 读与目录缓存冲刷
> - **条件化复现路径**：进入层级较深的目录树（≥几十个子目录）→ 长按目录「下载此文件夹」（BRW-01/DL-01-S8）或打开搜索输入关键词（SRCH-01）→ 每个未命中缓存的层经 `fetchDir = (p) => ref.read(directoryContentsProvider(p).future)` 触发 provider build：`lib/features/browser/browser_provider.dart:114-122` 对每层执行一次 `safeStorageRead`（flutter_secure_storage 平台通道调用，带 5s 超时包装）+ `:138-140` 写入 directoryCacheProvider（LRU 淘汰）。
> - **现象**：扫描延迟 = 网络 RTT × 层数 + 平台通道读 × 层数叠加；大扫描后用户原浏览路径的缓存条目被 LRU 冲掉，返回上级时重新 PROPFIND。
> - **自检答案**：fake 测试无真实平台通道开销与 LRU 容量压力——性能维度该分支零覆盖。
> - **缓解方向**：password 读取在扫描会话内 memoize，或搜索走不经缓存的轻量 fetchDir。

### 1.1 这一功能干什么（一句话）

扫描（文件夹下载 / 搜索）发起时只读一次密码、只走一次网络往返级别开销，不把用户浏览过的缓存挤掉。

### 1.2 用户期望的场景

| ID | 你看到的样子 | 期望行为 |
|----|----|----|
| U1 | 深目录树下点「下载此文件夹」或搜索 | 扫描耗时不再随目录层数线性叠加平台通道读（修复前每层一次 secure-storage 读，深树显著变慢） |
| U2 | 扫描完返回之前浏览过的上级目录 | 之前浏览过的目录仍命中缓存，不重新转圈加载（修复前扫描写入大量缓存条目，把用户浏览路径 LRU 挤掉） |
| U3 | 扫描过程中切换连接 | 行为与修复前一致（新会话用新连接，密码取新连接） |

---

## §2 已实现的功能骨架（代码锚点）

### 2.1 文件与分层

| 层 | 文件 | 关键位置 | 角色 |
|---|---|---|---|
| Provider | lib/features/browser/browser_provider.dart | :97-142 directoryContentsProvider；:396-399 search _startScan 的 fetchDir 接线 | 根因所在：每层 cache-miss 都做 safeStorageRead + 写 directoryCache |
| UI | lib/features/browser/browser_screen.dart | :1045-1048 _scanFolderWithLoading；:568-570 _collectFolder | 文件夹扫描（BRW-01 + DL-01-S8）fetchDir 接线 |
| Domain | lib/features/browser/domain/folder_collector.dart | :25 fetchDir(dir) | 纯 DFS，IO 全部注入 |
| Domain | lib/features/browser/domain/folder_searcher.dart | :69 fetchDir(dir) | 纯 DFS，IO 全部注入 |
| Contract | lib/core/network/webdav_client.dart | :159-168 listDirectory | 实际列目录网络调用 |
| Shared | lib/shared/webdav_paths.dart | :66 webDavEffectiveBaseUrl | 有效基址 |

### 2.2 关键 Provider 表

| Provider 名 | 类型 | 实现位置 | 用途 |
|---|---|---|---|
| directoryContentsProvider | FutureProvider.family<List<NasFile>, String> | browser_provider.dart:97 | 目录列表（缓存+过滤+排序） |
| directoryCacheProvider | StateProvider<Map<String, CacheEntry>> | browser_provider.dart:51 | LRU 缓存（默认 50 条，defaultMaxCacheSize） |
| searchSessionProvider | AutoDisposeNotifierProvider | browser_provider.dart:422 | 搜索会话（debounce + 订阅） |

### 2.3 状态机图

无状态机，跳过。

---

## §3 行为规约（Given-When-Then）

### 3.1 现状（逆抽）

- **[BUG-33-S1]** 现状：扫描每层未命中缓存 → 每层一次 secure-storage 读
  ```
  Given 深目录树（N 层全未命中缓存）
  When 搜索扫描（searchSessionProvider → searchFolderSubtree(fetchDir)）
       或文件夹扫描（_scanFolderWithLoading → collectFolderAudio(fetchDir)）
  Then fetchDir 每层触发 directoryContentsProvider build：
       :114-122 safeStorageRead（平台通道，5s 超时包装）→ N 次密码读
       :138-140 每层写 directoryCacheProvider → LRU 冲刷用户浏览路径
  ```
  Code evidence: browser_provider.dart:114-122/138-140；:399；browser_screen.dart:1047

### 3.2 修复后（`status: new`）

- **[BUG-33-S2] 扫描会话内密码读取恰一次（status: new）**

  ```
  Given 一次扫描会话（search 或 collectFolderAudio）访问同一活跃连接的多层目录
  When 会话启动
  Then 该连接密码（safeStorageRead）在整个会话内只读取一次，
       后续层复用已解析的密码直接调 webDavClient.listDirectory
  否定断言:
    - 扫描期间对同一连接不发生第二次 safeStorageRead（readCalls 不随层数增长）
    - 扫描不向 directoryCacheProvider 写入任何新条目（用户浏览路径缓存不被挤掉）
    - 目录浏览（directoryContentsProvider 常规路径）的缓存/TTL 行为零变化
  ```

  修改点（精确到函数）：

  **① browser_provider.dart 新增扫描会话 fetchDir 构造**（放 directoryContentsProvider 之后、searchSession 之前，顶层 `@visibleForTesting` 可测函数）：
  ```dart
  /// F1：扫描会话 fetchDir——密码读一次，列目录直达 webdav，不经 directoryCache。
  /// 返回 null 表示活跃连接/密码缺失（调用方按既有错误语义处理）。
  Future<Future<List<NasFile>> Function(String)?> buildScanFetchDir(
      WidgetRef ref) async {
    final conn = await ref.read(activeConnectionProvider.future);
    if (conn == null) return null;
    final pw = await safeStorageRead(ref.read(secureStorageProvider),
        key: 'connection_password_${conn.id}');
    if (pw == null || pw.isEmpty) return null;
    final client = ref.read(webDavClientProvider);
    final sort = ref.read(sortOptionProvider);
    return (path) async {
      final entries = await client.listDirectory(
          url: webDavEffectiveBaseUrl(conn.url, conn.basePath),
          username: conn.username,
          password: pw,
          path: path);
      // 复用 directoryContentsProvider 同款过滤+排序（把 :131-137 的过滤
      // 提取为顶层纯函数，两端共用，禁止第二份手抄）。
      return sortFiles(_filterDirectoryEntries(entries, path), sort);
    };
  }
  ```
  同时把 directoryContentsProvider :132-137 的过滤块提取为顶层纯函数
  `List<NasFile> _filterDirectoryEntries(List<NasFile> entries, String path)`，
  directoryContentsProvider 与 buildScanFetchDir 共用（唯一来源，防漂移）。

  **② searchSessionProvider._startScan（browser_provider.dart:396-399）**：
  ```dart
  // 现状：
  _sub = searchFolderSubtree(
    rootPath: rootPath,
    query: q,
    fetchDir: (p) => ref.read(directoryContentsProvider(p).future),
  ).listen(_onEvent);
  // 改为：
  final fetchDir = await buildScanFetchDir(ref);
  if (fetchDir == null) { /* 无活跃连接/密码 → 按现状错误落位（running 置 false + 置 query） */ return; }
  _sub = searchFolderSubtree(
    rootPath: rootPath,
    query: q,
    fetchDir: fetchDir,
  ).listen(_onEvent);
  ```

  **③ browser_screen._scanFolderWithLoading（:1045-1048）与 _collectFolder（:568-570）**：
  同样改走 `await buildScanFetchDir(ref)`；`null` → 走既有「无法读取文件夹内容」错误分支。

  Code evidence: browser_provider.dart:97-142/396-399；browser_screen.dart:1045-1058/566-572

- **[BUG-33-S3] 单层失败语义保持（status: new）**

  ```
  Given 扫描中某一层 listDirectory 抛错
  Then search 走 searchFolderSubtree 单层失败跳过（skippedDirs++，SRCH-01 §3.0 语义）
       folder 走 collectFolderAudio 整体失败上抛（BRW-01-S3 语义）
  否定断言:
    - buildScanFetchDir 不吞异常、不改两种扫描的既有成败语义
    - 不引入新的 try/catch 覆盖层
  ```

  Code evidence: folder_searcher.dart:68-73；folder_collector.dart:25

---

## §4 不变量

- **[BUG-33-INV1]** 扫描一律不经 directoryCacheProvider（读与写都不走），常规目录浏览的缓存语义不受影响。
  证据：S2 修改点③ 只改扫描 fetchDir；directoryContentsProvider 原样。
- **[BUG-33-INV2]** 扫描会话的密码读取次数 ≤ 1（同一连接）。
  证据：S2 ① buildScanFetchDir 只 safeStorageRead 一次。
- **[BUG-33-INV3]** 过滤+排序逻辑单一来源（_filterDirectoryEntries 纯函数），directoryContentsProvider 与扫描共用。
  证据：S2 ① 提取说明。

---

## §5 测试规约

### 5.1 现有测试清单

| 测试文件 | 覆盖 | 备注 |
|---|---|---|
| test/features/browser/bug_33_repro_test.dart | BUG-33 复现门禁（S2 主断言） | 修复前 FAIL：3 层扫描 readCalls==3 |
| test/features/browser/srch_01_folder_search_test.dart | SRCH-01 现有搜索语义 | 修复后必须全绿（S3 语义不变） |
| test/features/browser/brw_01_folder_actions_test.dart | BRW-01 文件夹扫描语义 | 修复后必须全绿 |
| test/features/downloads/dl_01_download_test.dart | DL-01-S8 目录下载 | 修复后必须全绿（S8 走 _scanFolderWithLoading） |

### 5.2 测试 ID 派生清单

```
BUG-33-S1 ~ S3
BUG-33-INV1 ~ INV3
```

### 5.3 测试覆盖盲点

| 未覆盖 ID | 现状 | 应补偿方式 |
|---|---|---|
| S2 中「扫描不写 directoryCache」否定面 | repro 只断言 readCalls | dev-exe 在 bug_33_repro_test.dart 增补：扫描前后 directoryCacheProvider 条目数不变 |
| S3 单层失败语义 | repro 未覆盖 | srch/brw 既有测试已覆盖，回归全绿即可 |

### 5.4 门禁测试文件位置

```
test/features/browser/bug_33_repro_test.dart
```
（命名核查 2026-08-29：grep test/ 无 bug_33 同名文件。）

---

## §6 算法样例

```
ALG [BUG-33-ALG1-buildScanFetchDir]:
  输入: 活跃连接 conn(id=1, url=http://nas, basePath=/)、密码 'pw'、三层树
  步骤: buildScanFetchDir → 读连接、读密码一次 → 返回 fetchDir
        扫描 '/', '/a', '/a/b' → listDirectory 三次（同 pw），safeStorageRead 仅 1 次
  断言: storage.readCalls == 1；directoryCacheProvider 扫描前后 size 不变
  异常: 无活跃连接/密码缺失 → 返回 null，调用方走错误分支
```

---

## §7 跨模块影响

| 其它 feature | 影响点 | 影响条件 | 需要补的回归断言 |
|---|---|---|---|
| BRW-01 | _scanFolderWithLoading / _collectFolder 换 fetchDir | 文件夹扫描入口 | brw_01_folder_actions_test 全绿 |
| SRCH-01 | searchSessionProvider._startScan 换 fetchDir | 搜索入口 | srch_01_folder_search_test 全绿 |
| DL-01 | DL-01-S8 目录下载走 _scanFolderWithLoading | 目录下载 | dl_01_download_test S8 组全绿 |
| BRW 缓存 | directoryContentsProvider 过滤逻辑提取为纯函数 | 常规浏览 | brw_05/brw_06 缓存族全绿（TTL/LRU 行为零变化） |

---

## §8 平台特性与手动 QA

逐条核对 docs/dev/platform-pitfalls.md：

| 踩坑条目 | 是否触及 | 处置 |
|---|---|---|
| P17 超时分层 | 是 | 扫描仍走 safeStorageRead 5s 超时包装（但整个会话只一次）；列目录无整体超时（现状保持） |
| P14 async gap | 是 | _startScan 内 `await buildScanFetchDir` 后订阅流——notifier 仍存活（AutoDispose 被监听保持），无 disposed 使用 |

**真机风险列（fake 测不到，只有真机会暴露）：**

| 风险 | 近似测试方案 | 测不了 → 进 mqa-backlog |
|---|---|---|
| 平台通道读的真实耗时占比（修复前后扫描延迟对比） | repro 断言 readCalls==1 近似 | MQA：真机深目录（30+ 层）扫描耗时对比修复前后 |

本功能不涉及平台原生特性（secure-storage 平台通道由 safeStorageRead 既有包装覆盖），核心行为全部可在 `flutter test` 中验证。manual_qa_required=false。

---

## §9 dev-status.json 条目对照

```json
"BUG-33": {
  "spec_file": "docs/features/BUG-33.md",
  "spec_anchored_files": [
    "lib/features/browser/browser_provider.dart",
    "lib/features/browser/browser_screen.dart",
    "test/features/browser/bug_33_repro_test.dart"
  ],
  "scenarios": ["BUG-33-S1","BUG-33-S2","BUG-33-S3"],
  "invariants": ["BUG-33-INV1","BUG-33-INV2","BUG-33-INV3"],
  "algorithms": ["BUG-33-ALG1-buildScanFetchDir"],
  "test_files": ["test/features/browser/bug_33_repro_test.dart"],
  "test_coverage_gaps": [],
  "cross_module_impacts": ["BRW", "SRCH", "DL"],
  "manual_qa_required": false,
  "manual_qa_file": null,
  "dependencies": [],
  "impl_status": "pending",
  "test_status": "pending",
  "check_status": "pending"
}
```