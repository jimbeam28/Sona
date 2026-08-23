# 功能详细设计文档：SRCH-01 文件搜索（子树范围 · 找到即行动）

```yaml
id: SRCH-01
name: 文件搜索（当前子树 · 立即播放 / 加入下一曲）
priority: P1
status: active
created_at: 2026-08-23
last_updated: 2026-08-23
spec_anchored_files:
  - lib/features/browser/browser_screen.dart
  - lib/features/browser/widgets/breadcrumb_bar.dart
  - lib/features/browser/browser_provider.dart
  - lib/features/progress/progress_dialog.dart
  - lib/features/player/player_provider.dart
  - lib/features/player/domain/playback_orchestrator.dart
cross_module_impacts: [PLY, PRG, BRW]
manual_qa_required: false
```

---

## §1 用户视角

### 1.0 原始需求（用户原话逐字记录）

> "我想把B1、B3和B5做一下。"（B1 = 文件搜索）
> 第一版设想（已放弃）："点击搜索后，在下方显示匹配列表……切换到选中文件所在的目录中……位于屏幕的中心。"
> 定稿版："**点击搜索之后，当前页面显示所有相关的音乐。音乐右侧有立即播放、加入播放列表（下一个）。**"
> 裁决记录（2026-08-23）：
> - S-A「立即播放」= 以命中文件父目录为根跑 BRW-01 收集器建队、从命中曲开始播（单曲裸队列否决）
> - S-B「立即播放」先查进度：有 → 弹现有恢复对话框；无 → 从头播（有声书续听场景）
> - S-C 无队列时「下一首播」按钮置灰，沿用主列表同款门禁
> - 行点击 = 立即播放，右侧只留一个「下一首播」图标按钮（用户采纳推荐）
> - 维持项：子树范围 / 面包屑区放大镜入口 / 大小写不敏感子串 / debounce 实时 / 200 目录上限+可取消 / 结果按目录先序分组

### 1.1 这一功能干什么（一句话）

在文件浏览器里点放大镜，输入名字的一部分，当前文件夹（含所有子文件夹）里 matching 的音频立刻列出来，每条都能马上播或插到正在听的歌后面。

### 1.2 用户期望的场景

| ID | 你看到的样子 | 期望行为 |
|----|----|----|
| U1 | 点面包屑旁的放大镜 | 出现搜索框；再点收起 |
| U2 | 输入"晴天" | 不用按回车，稍等半秒自动开始搜；列表变成结果列表，显示"已扫 N 个目录·命中 M"；每个结果显示歌名+所在目录路径 |
| U3 | 点某条结果 | 直接开始播放：队列=它所在文件夹的全部音频，从这首开始；如果这首之前听到一半，弹熟悉的"继续播放？"对话框 |
| U4 | 点结果右侧的音符图标 | 不打断当前播放，这首歌被插到当前曲后面 |
| U5 | 没在播放时看那个图标 | 图标是灰的，点了没反应 |
| U6 | 文件夹层级很多、文件超多 | 扫到 200 个目录就停并提示"已扫描前 200 个目录"；中途随时可点取消 |
| U7 | 某个子文件夹读不出来 | 不影响整体：跳过它继续扫别的，最后提示"N 个目录无法读取" |
| U8 | 搜不到东西 | 显示"无匹配结果" |
| U9 | 收起搜索或切了连接 | 结果清空，回到普通浏览；后台没扫完的自动停掉 |

---

## §2 已实现的功能骨架（代码锚点）

### 2.1 文件与分层

| 层 | 文件 | 关键位置 | 角色 |
|---|---|---|---|
| UI | lib/features/browser/browser_screen.dart | :50-59 build 顶部 Column（BreadcrumbBar→Divider→内容区）；:139-176 onFileTap 进度查询+恢复对话框完整参照系；:177-192 建队+push 参照系；:137-138 playNextEnabled 门禁参照 | 主改造面 |
| UI | lib/features/browser/widgets/breadcrumb_bar.dart | :31-60 BreadcrumbBar 自身只渲染 chip 行（Container+LayoutBuilder），**无尾部图标位**——入口图标加在其外层 | 入口挂载点在外层包 Row |
| Provider | lib/features/browser/browser_provider.dart | :92-135 directoryContentsProvider（family）：缓存命中/PROPFIND/过滤/排序/抛 WebDavException | 逐层取数复用 |
| Domain(新) | lib/features/browser/domain/folder_searcher.dart | 新文件 | 纯遍历匹配逻辑 |
| Domain(依赖) | lib/features/browser/domain/folder_collector.dart | BRW-01 新建；collectFolderAudio(rootPath, fetchDir, maxFiles) | 立即播放建队复用 |
| PLY | lib/features/player/player_provider.dart | :428-431 insertAfterCurrentProvider | 加入下一曲 |
| PLY | lib/features/player/domain/playback_orchestrator.dart | :395-401 insertAfterCurrent 无队列返回 false | 兜底语义 |
| PRG | lib/features/progress/progress_dialog.dart | :26 showProgressResumeDialog(context, container, progress) → Future<bool?>（true=续播/false=从头并清进度/null=关闭） | S-B 复用 |

### 2.2 现有行为逆抽

- **playNextEnabled 门禁**（browser_screen.dart:137-138）：`(ref.watch(audioPlayingProvider).valueOrNull ?? false) && ref.watch(currentPlayQueueProvider) != null`。
- **进度恢复参照系**（:139-176）：conn 判空 → try { progressForFileProvider((connectionId:, filePath:)).future } catch → debugPrint 后按无进度继续；`ProgressDao.shouldSave(positionMs)` 阈值过滤（REF-19）；`showProgressResumeDialog` 返回 true→startPositionMs=progress.positionMs / false→clearProgressProvider。
- **建队参照系**（:177-192）：GoRouter.of(context) → PlayQueue(files, currentIndex, startPositionMs).withMode(playModeProvider) → 写 currentPlayQueueProvider + lastQueueConnectionIdProvider → push('/player')。
- **directoryContentsProvider 抛错面**：WebDavException（中文文案）/非 WebDavException（:105-112 BUG-10 卫生）。
- **无现成 debounce 工具**（全库 grep 仅 progress_provider Timer 用于对话框倒计时）——本功能自建 Timer debounce 于 notifier 内。

---

## §3 行为规约（Given-When-Then）

### 3.0 与 BRW-01 的语义差异声明（有意为之，防误"对齐"）

BRW-01 建队流程采用**整体失败**语义（任一层抛错即终止）。搜索是只读探索操作，丢全部命中代价过高 → 采用**逐层跳过**语义：单层 fetchDir 抛错记入 skippedCount 并继续。两处不得互相"统一"。

### 3.1 Domain 层：folder_searcher.dart（新文件）

```dart
import 'dart:async';
import '../../shared/models/nas_file.dart'; // 实际相对路径按目录结构调整

const int kSearchMaxDirs = 200;

class SearchHit {
  final NasFile file;
  final String parentDirPath;
  const SearchHit({required this.file, required this.parentDirPath});
}

/// 搜索进度事件流：命中增量推送，scan 终止时给终态事件。
sealed class SearchEvent {}
class HitFound extends SearchEvent { final SearchHit hit; HitFound(this.hit); }
class ScanProgress extends SearchEvent { final int dirsScanned; ScanProgress(this.dirsScanned); }
class ScanDone extends SearchEvent {
  final bool truncated;      // 达到 kSearchMaxDirs
  final int skippedDirs;     // 单层读取失败被跳过的目录数
  ScanDone({required this.truncated, required this.skippedDirs});
}

/// 大小写不敏感子串匹配，仅作用于文件名。
bool matchesQuery(String fileName, String query) {
  final q = query.trim().toLowerCase();
  if (q.isEmpty) return false;
  return fileName.toLowerCase().contains(q);
}

/// DFS 先序扫描 rootPath 子树，产出命中事件流。
/// 单层失败跳过不中断（见 §3.0）；[isCancelled] 每层轮询，返回 true 即停止。
Stream<SearchEvent> searchFolderSubtree({
  required String rootPath,
  required String query,
  required Future<List<NasFile>> Function(String path) fetchDir,
  bool Function()? isCancelled,
  int maxDirs = kSearchMaxDirs,
}) async* {
  var dirsScanned = 0;
  var skipped = 0;
  var truncated = false;
  final stack = <String>[rootPath];
  while (stack.isNotEmpty && !truncated) {
    if (isCancelled != null && isCancelled()) return;
    final dir = stack.removeLast();
    List<NasFile> entries;
    try {
      entries = await fetchDir(dir);
    } catch (_) {
      skipped++;
      continue;
    }
    dirsScanned++;
    final subDirs = <NasFile>[];
    for (final e in entries) {
      if (e.isDirectory) {
        subDirs.add(e);
      } else if (e.audioType != null && matchesQuery(e.name, query)) {
        yield HitFound(SearchHit(file: e, parentDirPath: dir));
      }
    }
    for (final d in subDirs.reversed) {
      stack.add(d.path);
    }
    yield ScanProgress(dirsScanned);
    if (dirsScanned >= maxDirs && stack.isNotEmpty) truncated = true;
  }
  yield ScanDone(truncated: truncated, skippedDirs: skipped);
}
```

> 弱模型注意：`stack.removeLast()` + 子目录**反向压栈**保证先序；`dirsScanned >= maxDirs && stack.isNotEmpty` 才置 truncated（恰好扫完第 200 个且栈空属正常完成，不算截断）。

- **[SRCH-01-S1] 匹配规则**
  ```
  Given query='AB'，文件 ['ab.mp3','ABC.flac','cd.mp3','x.txt', 目录 'ab']
  When searchFolderSubtree
  Then 命中 ab.mp3 与 ABC.flac
  否定断言:
    - cd.mp3 / x.txt 不命中
    - 名为 'ab' 的目录不产生 HitFound（目录名不参与匹配）
    - 非音频（audioType==null）即使名字匹配也不命中
    - query 全空白 → matchesQuery 恒 false，零命中
  ```

- **[SRCH-01-S2] 截断**
  ```
  Given maxDirs=200，子树含 250 个可读目录（前 200 个内含命中）
  When 扫描完成
  Then 收到 ScanDone(truncated:true)，HitFound 只来自前 200 个已扫目录，
       第 201~250 个目录的 fetchDir 从未被调用
  否定断言:
    - truncated==true 时 ScanDone 前不再有任何 fetchDir 调用
    - 恰好 200 个目录全扫完且栈空 → truncated==false
  ```

- **[SRCH-01-S3] 单层失败跳过**
  ```
  Given 第 2 个目录 fetchDir 抛 WebDavException('没有活跃的连接')，其余正常含命中
  When 扫描完成
  Then ScanDone(skippedDirs:1)，其余命中全部送达，流正常 done 不 error
  否定断言:
    - 流不发出错误事件（与 BRW-01 整体失败语义相反，§3.0）
    - 失败层的命中无从谈起，但不得影响后续层计数（dirsScanned 含成功层）
  ```
  Code evidence: directoryContentsProvider 抛错面 browser_provider.dart:94/:105-112

- **[SRCH-01-S4] 取消**
  ```
  Given isCancelled 在第 k 层返回 true
  When 流终止
  Then 第 k 层起零 fetchDir 调用、零事件（含 ScanDone）——订阅方以 done 判定自然结束
  否定断言:
    - 取消后不发 ScanDone（调用方据此区分"取消"与"完成"）
  ```

### 3.2 Provider 层：browser_provider.dart 追加（同 feature 内直接追加，不经 di）

```dart
// ── SRCH-01: folder search ────────────────────────────────────────────────
class SearchSessionState {
  final bool panelOpen;        // 搜索面板是否激活
  final int dirsScanned;
  final bool running;          // 订阅未结束
  final bool truncated;
  final int skippedDirs;
  final List<SearchHit> hits;
  const SearchSessionState({
    this.panelOpen = false,
    this.dirsScanned = 0,
    this.running = false,
    this.truncated = false,
    this.skippedDirs = 0,
    this.hits = const [],
  });
  // copyWith 略——弱模型实现全部字段拷贝
}

class SearchSessionNotifier extends AutoDisposeNotifier<SearchSessionState> {
  Timer? _debounce;
  StreamSubscription<SearchEvent>? _sub;

  void openPanel() / closePanel();          // closePanel = S10 清理
  void onQueryChanged(String rawQuery);     // debounce 500ms 后 startScan
  void cancelScan();
}
final searchSessionProvider =
    AutoDisposeNotifierProvider<SearchSessionNotifier, SearchSessionState>(...);
```

- **[SRCH-01-S5] debounce 与启动**
  ```
  Given 面板打开，用户连续输入（间隔 <500ms）
  When onQueryChanged 连续触发
  Then 只有最后一次输入后的 500ms 触发一次 startScan；
       trim 后空 query → 取消进行中的扫描并回到"已打开但零结果零扫描"态
  否定断言:
    - 每次 keystroke 都立即发起新扫描（错）
    - 空 query 发起 fetchDir（错）
    - startScan 启动前必须先取消旧订阅（同一时刻至多一条活跃流）
  ```

- **[SRCH-01-S6] 事件归约**
  ```
  Given 活跃扫描流
  When HitFound / ScanProgress / ScanDone 到达
  Then hits 尾追（保序）、dirsScanned 更新、ScanDone 置 running=false 并落 truncated/skippedDirs
  否定断言:
    - running==false 后到达的事件被忽略（防御迟到事件）
    - hits 不去重不去序（收集序即展示序）
  ```

- **[SRCH-01-S7] 生命周期清理**
  ```
  Given 任一时刻发生：closePanel / cancelScan / 连接切换（watch
        clearQueueOnConnectionSwitchProvider 同款监听点，browser_screen.dart:47）
  Then _sub?.cancel() 且 _debounce?.cancel()，状态复位为 panelOpen 对应初值
  否定断言:
    - 取消后 dirsScanned/hits 残留显示（连接切换分支必须全清）
    - provider dispose（离开页面）后流仍持有回调（AutoDispose + ref.onDispose 双保险）
  ```

### 3.3 UI 层：入口、结果列表、两个动作

- **[SRCH-01-S8] 入口挂载**
  ```
  Given browser_screen.dart :56-58 现为 `const BreadcrumbBar(), const Divider(height:1),`
  When 改造
  Then BreadcrumbBar 包进 Row：`Row(children:[Expanded(child: BreadcrumbBar()),
       IconButton(Icons.search, toggle), ])`；面板开启时 Divider 下插入一行搜索框
       （TextField autofocus + 清空钮 + 收起 X）
  否定断言:
    - BreadcrumbBar 内部实现零改动（breadcrumb_bar.dart 不动）
    - 面板关闭态下主列表渲染路径与现状完全一致（INV1 回归网 brw 族不改一字全绿）
  ```

- **[SRCH-01-S9] 结果列表形态**
  ```
  Given session.panelOpen == true
  When 渲染内容区（替换 _FileList 分支）
  Then 顶部状态行：running→'已扫 N 个目录…'+取消钮；done→'命中 M'+truncated 补充
       '（已扫描前 ${kSearchMaxDirs} 个目录）'+skippedDirs>0 补充'，N 个目录无法读取'
       ；hits 空且 done→居中文案'无匹配结果'
  And 每行 ListTile：leading 音频图标（沿用 AudioFileListTile 配色规则）、title=文件名、
      subtitle=parentDirPath、trailing=单个 IconButton(Icons.queue_music)
      其 enabled = playNextEnabled 同款门禁（browser_screen.dart:137-138 表达式）
  否定断言:
    - 结果区不出现下拉刷新（RefreshIndicator 不包裹）
    - 目录条目不出现在结果中
  ```

- **[SRCH-01-S10] 行点击 = 立即播放**
  ```
  Given 用户点击命中行 hit
  When 动作执行
  Then ① 进度查询完全镜像 onFileTap :139-176（含 conn 判空、BUG-18 try/catch、
          ProgressDao.shouldSave 阈值、showProgressResumeDialog 三分支：
          true→startPositionMs / false→clearProgressProvider / null→无）
       ② await collectFolderAudio(rootPath: hit.parentDirPath,
          fetchDir: (p) => ref.read(directoryContentsProvider(p).future))
          ——整体失败语义与"从此处播放"一致
       ③ startIndex = collected.indexWhere((f) => f.path == hit.file.path)；
          <0（扫描与点击之间文件被删）→ SnackBar '该文件已不存在'，终止
       ④ 建队完全镜像 ：182-192（withMode 读 playModeProvider，写双 provider，
          push '/player'），truncated 时补 SnackBar 截断提示（沿用 BRW-01 S5⑥ 文案）
  否定断言:
    - 不修改 playModeProvider（只读）
    - ② 抛错 → debugPrint(redactUrlForLog(e)) + SnackBar '无法读取文件夹内容，请检查连接'
      + 不写队列 provider + 不 push（catch-log 裁决）
    - 每个 await 后使用 context 前检查 context.mounted（本文件已有 ignore_for_file
      use_build_context_synchronously 文件级豁免，模式照抄 :176/:213）
  ```
  Code evidence: browser_screen.dart:139-192；folder_collector（BRW-01）

- **[SRCH-01-S11] 「下一首播」按钮**
  ```
  Given 结果行 trailing 按钮
  When 点击（enabled 前提下）
  Then ok = await ref.read(insertAfterCurrentProvider)(hit.file)
       ok==true → SnackBar '已加入下一曲：${hit.file.name}'（duration 2s，文案与主列表一致）
       ok==false（理论不可达，按钮已置灰；防御分支）→ SnackBar '请先开始播放后再用此功能'
  否定断言:
    - disabled 态 IconButton.onPressed 为 null（不是弹出提示）
    - 插队不改 currentPlayQueueProvider 以外的任何播放状态、不打断当前曲
      （orchestrator.insertAfterCurrent 契约 playback_orchestrator.dart:395-401）
  ```

---

## §4 不变量

- **[SRCH-01-INV1]** 面板关闭时浏览器渲染路径与现状逐字节等价。
  证据：S8 否定断言；brw_02/03/05/06 族测试不改一字全绿
- **[SRCH-01-INV2]** 搜索扫描自身只读——除 session 状态外不写任何 provider；队列写入仅发生于 S10 用户显式动作。
  证据：§3.2 归约器字段面
- **[SRCH-01-INV3]** folder_searcher 为纯 Dart（仅 dart:async），fetchDir/isCancelled 注入，零 Flutter/provider 依赖。
  证据：§3.1 签名；架构分层纪律
- **[SRCH-01-INV4]** 常量唯一来源：kSearchMaxDirs（域层）；UI 文案引用常量不手写 200。

---

## §5 测试规约

### 5.1 现有测试清单

| 测试文件 | 覆盖 | 备注 |
|---|---|---|
| test/features/browser/brw_* 族 | 导航/排序/缓存/长按既有行为 | INV1 回归网 |
| test/features/player/ply_* 族（insertAfterCurrent 相关） | 下一曲播 | S11 复用的既有契约 |
| test/features/progress/bug_bug18 族 | 进度查询裸奔加固 | S10 复用其 try/catch 形态，回归全绿即可 |

### 5.2 测试 ID 派生清单

```
SRCH-01-S1 ~ S11
SRCH-01-INV1 ~ INV4
SRCH-01-ALG1（扫描样例表）
```

### 5.3 测试覆盖盲点

| 未覆盖 ID | 现状 | 应补偿方式 |
|---|---|---|
| S9 状态行三种形态组合（truncated×skipped 四象限） | 无 | widget 测试注入终态渲染断言 |
| S10 resume==null 分支（对话框直接关闭） | 无 | mock dialog 返回 null → startPositionMs 保持 null |
| S7 连接切换清理 | 无 | notifier 级测试：触发清理回调后 state 复位且 sub.cancelled |

### 5.4 门禁测试文件位置

```
test/features/browser/srch_01_folder_search_test.dart
```
（命名核查 2026-08-23：test/features/browser/ 无 srch_ 前缀，无冲突。）

---

## §6 算法样例

```
ALG [SRCH-01-ALG1-searchFolderSubtree]:
  # 树: root=[a1.mp3, dA(aa.mp3, dC(cc.mp3)), ab.flac, dB(bb.mp3)]
  # query='b'
  步骤表:
    1 pop root → 命中 ab.flac(Hit#1)；压栈 dA,dB（先序: dA 先于 dB）
    2 pop dA → 命中 aa.mp3? 否('aa'不含'b')；cc.mp3 否；压栈 dC
    3 pop dC → cc.mp3 否
    4 pop dB → bb.mp3 命中(Hit#2)
    5 栈空 → ScanDone(truncated:false, skipped:0)
  断言: 命中序 = [ab.flac, bb.mp3]（先序分组）; fetch 序 root→dA→dC→dB   # S1
  变体: dA 抛错 → Hit=[ab.flac,bb.mp3], skipped=1                        # S3
  变体: maxDirs=2 → 扫完 dA 即 truncated=true, dB 未 fetch               # S2
```

---

## §7 跨模块影响

| 其它 feature | 影响点 | 影响条件 | 需要补的回归断言 |
|---|---|---|---|
| BRW | 依赖 folder_collector（BRW-01 交付物）与目录菜单无关 | SRCH 排期在 BRW 之后实施 | collectFolderAudio 单测随 BRW-01 交付，此处只消费 |
| PLY | insertAfterCurrentProvider 复用 | 每次点结果行音符图标 | ply 族 insertAfterCurrent 用例不改一字全绿 |
| PRG | showProgressResumeDialog / clearProgressProvider / ProgressDao.shouldSave 复用 | 立即播放带进度场景 | bug_bug18 族 + prg 阈值族全绿 |
| HOME | browser_screen Column 结构变化（BreadcrumbBar 包 Row） | HomeScreen Tab 嵌布 | home 族 widget 测试全绿 |

---

## §8 平台特性与手动 QA

逐条核对 docs/dev/platform-pitfalls.md：

| 踩坑条目 | 是否触及 | 处置 |
|---|---|---|
| P14 async gap | 是 | S10 显式 context.mounted 检查序列；文件级 ignore_for_file 已存在（:13-14），无需新增抑制 |
| P17 超时分层 | 是 | 逐层 fetchDir 继承 directoryContentsProvider 底层超时；搜索自身不加总时长限制（S2 截断兜底规模） |
| P11 build 期改 provider | 是 | debounce Timer 回调/startScan 均非 build 期；结果渲染纯 watch |
| P13 setState defunct | 是 | StreamSubscription 回调内更新 notifier 状态（非 BuildContext），AutoDispose 自动止损 |

**可行性依据（铁律 6）：**

- R1 `async*` 生成器 + sealed event 类 + StreamSubscription 取消语义：Dart SDK 官方语言特性（dart:async Stream generator，Dart 3 sealed class），仓库现有同款异步流消费先例——player positionStream/processingStateStream 订阅-取消模式（player_provider.dart:320 区段 listener/cancel 成对出现）。现有同款模式，免重复验证。
- R2 Timer debounce：仓库现有 Timer 使用先例 progress_provider.dart:149-181（cancel 配对管理），同款模式。

**真机风险列：**

| 风险 | 近似测试方案 | 测不了 → 进 mqa-backlog |
|---|---|---|
| 大子树真实 RTT 叠加（200 目录 × 每层数百 ms） | fake 无真实网络延迟 | MQA：真实 NAS 上 200 目录扫描耗时体验评估 |
| 扫描期间用户高速滚动结果列表的帧率 | widget 测试不测帧率 | 低风险，不进 backlog |

本功能无平台原生通道改动，manual_qa_required=false。

---

## §9 dev-status.json 条目对照

```json
"SRCH-01": {
  "spec_file": "docs/features/SRCH-01.md",
  "spec_anchored_files": [
    "lib/features/browser/browser_screen.dart",
    "lib/features/browser/widgets/breadcrumb_bar.dart",
    "lib/features/browser/browser_provider.dart",
    "lib/features/progress/progress_dialog.dart",
    "lib/features/player/player_provider.dart",
    "lib/features/player/domain/playback_orchestrator.dart"
  ],
  "scenarios": ["SRCH-01-S1","SRCH-01-S2","SRCH-01-S3","SRCH-01-S4","SRCH-01-S5","SRCH-01-S6","SRCH-01-S7","SRCH-01-S8","SRCH-01-S9","SRCH-01-S10","SRCH-01-S11"],
  "invariants": ["SRCH-01-INV1","SRCH-01-INV2","SRCH-01-INV3","SRCH-01-INV4"],
  "algorithms": ["SRCH-01-ALG1-searchFolderSubtree"],
  "test_files": ["test/features/browser/srch_01_folder_search_test.dart"],
  "test_coverage_gaps": [],
  "cross_module_impacts": ["PLY", "PRG", "BRW"],
  "manual_qa_required": false,
  "dependencies": ["BRW-01"],
  "impl_status": "pending",
  "test_status": "pending",
  "check_status": "pending"
}
```
