# 功能详细设计文档：MSEL-01 浏览器批量多选

```yaml
id: MSEL-01
name: 批量多选（跨目录勾选 · 加入播放单 / 以此播放）
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
cross_module_impacts: [PLY, BRW, SRCH]
manual_qa_required: false
```

---

## §1 用户视角

### 1.0 原始需求（用户原话逐字记录）

> "我想把B1、B3和B5做一下。"（B3 = 批量多选：多选文件 → 批量加入播放单/建队）
> 裁决记录（2026-08-23，全部按推荐执行）：
> - B3-1 入口 = **面包屑区显式"多选"图标按钮**（文件长按=进度恢复、目录长按=BRW-01 菜单均被占用，手势路线否决）
> - B3-2 仅音频文件可选——"整个文件夹加入"BRW-01 已覆盖，多选定位于挑散装曲目
> - B3-3 tap=勾选；跨子目录导航**累积保留**；切连接清空
> - B3-4 底部操作栏：「加入播放单」「以此播放」「全选(当前目录)/清除」
> - B3-5 顺序 = 按列表当前排序（非点选顺序）
> 补充裁决（本次 spec 定稿新增，呈现时需向用户复述确认）：
> - **退出多选模式即清空全部选择**（防幽灵选择：隐藏的跨目录选择集在正常浏览态不可见，易误触"以此播放"带出意料外曲目）
> - 跨目录顺序细则 = 组间按目录首次进入顺序、组内按该目录当前排序快照序（缓存被淘汰时回退路径字典序），详见 ALG1
> - 选择模式下文件行 tap 全部归勾选，长按与 trailing「下一首播」禁用

### 1.1 这一功能干什么（一句话）

在文件浏览器里进入多选模式后，可以跨文件夹勾选任意多首歌，然后一次性加入某个播放单，或者把这堆歌直接组成队列开播。

### 1.2 用户期望的场景

| ID | 你看到的样子 | 期望行为 |
|----|----|----|
| U1 | 点面包屑旁的多选图标 | 进入多选模式：每行音频前出现勾选框，底部浮出操作栏 |
| U2 | 点歌 | 勾上/取消；底栏计数"已选 N 首"实时变 |
| U3 | 进入子文件夹再勾几首 | 已勾的不丢；返回上级还在；底栏计数累计 |
| U4 | 底栏点"全选" | 当前目录里所有音频一次勾上 |
| U5 | 点"以此播放" | 这 N 首（按 U7 的顺序）直接成队列开播，进播放器 |
| U6 | 点"加入播放单" | 弹出熟悉的播放单选择面板（和长按文件夹加入播放单同一个），选完提示已添加 |
| U7 | 混着勾了几个目录的歌 | 播放/入单顺序稳定可预期：先勾的文件夹整体在前，同文件夹内按当时看到的排序 |
| U8 | 点 X 退出多选 | 勾选全部清空，界面恢复原样 |
| U9 | 多选模式中途切换了 NAS 连接 | 自动退出多选并清空 |

---

## §2 已实现的功能骨架（代码锚点）

### 2.1 文件与分层

| 层 | 文件 | 关键位置 | 角色 |
|---|---|---|---|
| UI | lib/features/browser/browser_screen.dart | :50-59 Column 结构（BreadcrumbBar→Divider→内容区）——入口按钮挂载点；:137-138 playNextEnabled 门禁参照；:177-192 建队参照系；:425-436 AudioFileListTile 接线点 | 主改造面 |
| UI | lib/features/browser/widgets/file_list_item.dart | :17-38 DirectoryListTile（无勾选位）；:50-135 AudioFileListTile（leading=Icon(:86)，trailing=next-play IconButton(:104-115)） | 勾选视觉注入点 |
| Provider | lib/features/browser/browser_provider.dart | :47 clearQueueOnConnectionSwitchProvider watch 先例（连接切换联动钩子挂载点）；:92-135 directoryContentsProvider（组内排序快照来源）；sortOptionProvider 注入排序 | 状态与快照 |
| PLY | lib/shared/models/play_queue.dart | :55-62 构造；:114 withMode | 以此播放建队 |
| Bridge | lib/shared/di/providers.dart | :205-222 playlist 段（playlistListProvider/addTracksToPlaylistProvider 等 + BRW-01 S9 追加的 playlistServiceProvider）；playModeProvider 经桥读取先例（browser_screen O3 注释） | 跨 feature 符号源 |
| 复用 | browser_screen 内 BRW-01 创建的播放单选择面板函数 | BRW-01 S7/S8 定义为**顶层函数** `_showPlaylistPickerSheet` | 加入播放单直接调用 |

### 2.2 现有行为逆抽

- **AudioFileListTile trailing 现状**（file_list_item.dart:104-115）：playNext IconButton 常驻占位（disabled 态包 GestureDetector 占位）。多选模式下该 trailing 整体替换为空（S2），退出还原。
- **DirectoryListTile 现状**（:17-38）：仅 leading folder icon + title + chevron。多选模式不渲染勾选框（B3-2 目录不可选），保持可导航。
- **连接切换联动先例**（browser_screen.dart:46-47）：`ref.watch(clearQueueOnConnectionSwitchProvider)` 在 build 中激活监听——多选清理钩子以同款方式挂载。
- **建队参照系**（:182-192）：PlayQueue(...).withMode(playModeProvider) → currentPlayQueueProvider → lastQueueConnectionIdProvider → GoRouter.of(context).push('/player')。
- **addTracksToPlaylistProvider**（playlist_provider.dart:121-129）：`(int playlistId, List<NasFile>) → Future<void>`，内部 service 去重（playlist_service.dart:74-95）+ invalidate 双缓存。
- **createPlaylist 取 id 需 service 直连**（playlist_provider.dart:92-98 包装丢 id）——新建播放单路径经 `playlistServiceProvider.createPlaylist(name)`（playlist_service.dart:44，Future<int>）。

---

## §3 行为规约（Given-When-Then）

### 3.0 新增状态（browser_provider.dart 同 feature 追加）

```dart
/// 勾选存储：目录路径 → 该目录已勾选文件集合。
/// Dart Map 字面量为插入序 LinkedHashMap：键序 = 目录首次进入顺序（ALG1 组间序）。
final multiSelectModeProvider = StateProvider<bool>((ref) => false);
// Notifier 持有 Map<String, Set<String>>（dirPath → selected filePath set）
// 与派生 count；方法 toggle(dirPath, file)/selectAllCurrent(dirPath, files)/clear()
```

- **[MSEL-01-S1] 进入/退出多选模式**
  ```
  Given browser_screen :56-58 区段 BreadcrumbBar 外层已包 Row（SRCH-01 S8 同一改造点，
        两功能共用一行 Row——实施顺序 SRCH 在前则追加 IconButton 即可）
  When 点多选图标（Icons.checklist）→ multiSelectMode=true；再点/X 钮 → false 且 clear()
  Then 进入后：AudioFileListTile 行 leading 变 Checkbox、trailing next-play 消失；
       底部浮出操作栏（S4）；底部内容区加 padding 防遮挡
  否定断言:
    - 退出后重进：选择必为空（幽灵选择禁止）
    - 退出后 AudioFileListTile 渲染与现状完全一致（INV1 回归网）
    - DirectoryListTile 在多选模式下无 Checkbox（目录不可选）、仍可点击导航
  ```
  Code evidence: file_list_item.dart:17-38/:50-135

- **[MSEL-01-S2] 勾选交互**
  ```
  Given multiSelectMode==true
  When tap 音频行
  Then 切换该 (当前目录, file.path) 的选中态；Checkbox 视觉同步；底栏计数更新
  否定断言:
    - 多选模式下 onLongPress 不触发（进度恢复 sheet 不弹）
    - onPlayNext 不触发且 trailing 不渲染
    - 同一 file.path 不会在同一目录组内重复出现
    - 不同目录出现同名文件（不同 path）各自独立计数
  ```

- **[MSEL-01-S3] 跨目录累积**
  ```
  Given dirA 勾了 A1，导航进 dirB
  When dirB 勾 B1 后返回 dirA
  Then 计数=2，A1 仍勾选；store 键序 = [dirA, dirB]（dirA 先入）
  否定断言:
    - 导航（push/pop）不清空选择
    - 返回 dirA 再勾 A2 时 dirA 组仍排在 dirB 前（键序不变，append 进既有组）
  ```

- **[MSEL-01-S4] 底部操作栏**
  ```
  Given multiSelectMode==true
  When 渲染 BottomAppBar（SafeArea 内）：'已选 N 首' + [全选] [清除] | [加入播放单] [以此播放]
  Then N==0 时「加入播放单」「以此播放」onPressed=null；「清除」清空 store 不退模式；
       「全选」= 当前目录全部音频并入当前目录组（已选的跳过，幂等）
  否定断言:
    - 操作栏不遮最后一行（列表 bottom padding == 栏高）
    - 「全选」对目录条目零效果
    - 「清除」不改变 multiSelectMode
  ```

- **[MSEL-01-S5] 以此播放**
  ```
  Given N>=1，点「以此播放」
  When 动作执行
  Then ① files = orderedSelectedFiles(store, 快照解析)（ALG1 序）
       ② PlayQueue(files: files, currentIndex: 0).withMode(ref.read(playModeProvider))
          → 写 currentPlayQueueProvider + lastQueueConnectionIdProvider（镜像 onFileTap :182-192）
       ③ push '/player'；成功后退出多选模式并 clear()
  否定断言:
    - startPositionMs 恒 null——不查进度、不弹恢复对话框（文件夹入口语义族，
      与 BRW-01 S5⑤ / SRCH-01 无关此路径，本动作是纯集合建队）
    - 不修改 playModeProvider
    - store 为空时按钮不可达（S4 disabled），若防御性触发则直接 return 不写任何 provider
  ```

- **[MSEL-01-S6] 加入播放单**
  ```
  Given N>=1，点「加入播放单」
  When 动作执行
  Then 调用 BRW-01 定义的顶层函数 _showPlaylistPickerSheet(context, ref, files)
       （内部含：扫描无需——files 已在本地；播放单列表面板/新建面板/成功 SnackBar '已添加 N 首'
       全部复用 BRW-01 S7/S8 行为，含 createPlaylist 直连取 id 路径）
  And 成功回调后退出多选模式并 clear()；用户关闭面板未选 → 保持多选态不变
  否定断言:
    - 本功能不复制粘贴任何 picker 逻辑（单一实现点约束）
    - 关闭面板 ≠ 成功：不得误清选择
  ```
  依赖声明：BRW-01 排期在本功能之前实施；若实施顺序被打破，由实施方把 picker 提取为本文件顶层函数后再继续（门禁脚本 cross-imports 不受影响——同 feature 内引用）。

- **[MSEL-01-S7] 连接切换清理**
  ```
  Given multiSelectMode==true 或 store 非空
  When 活跃连接变更（watch clearQueueOnConnectionSwitchProvider 同款联动点，:46-47）
  Then multiSelectMode=false 且 store 清空
  否定断言:
    - 切换后残留任何勾选或模式标志
  ```

- **[MSEL-01-S8] 排序变化不影响已存选择**
  ```
  Given dirA 勾选 {A2.mp3}，用户改 SortOption 后重新进入 dirA
  When 继续「以此播放」
  Then dirA 组内序按**新的**排序快照解析（ALG1 规则 c），已选集合本身不变
  否定断言:
    - 改排序导致勾选丢失或重复
  ```

---

## §4 不变量

- **[MSEL-01-INV1]** multiSelectMode==false 时浏览器渲染与交互路径现状等价。
  证据：S1 否定面；brw 族回归网不改一字全绿
- **[MSEL-01-INV2]** 选择存储为纯 Dart `Map<String, Set<String>>`（依赖 Dart Map 插入序语言保证，见 §8-R1），零 Flutter 依赖；排序解析策略独立成可测纯函数。
- **[MSEL-01-INV3]** 队列写入唯一形态 = S5② 镜像 onFileTap 尾段；startPositionMs 恒 null。
  证据：browser_screen.dart:182-192 参照系
- **[MSEL-01-INV4]** 播放单写入只经 BRW-01 picker 单点（service 直连 createPlaylist + addTracksToPlaylistProvider），本功能零新增 playlist 符号导入。

---

## §5 测试规约

### 5.1 现有测试清单

| 测试文件 | 覆盖 | 备注 |
|---|---|---|
| test/features/browser/brw_* 族 | 导航/长按/tap 既有行为 | INV1 回归网 |
| test/features/player/o3_create_queue_play_mode_test | withMode 建队形态 | S5 同构路径已被覆盖 |
| test/helpers/widget_helpers.dart | widget 测试脚手架 | 勾选交互测试复用 |

### 5.2 测试 ID 派生清单

```
MSEL-01-S1 ~ S8
MSEL-01-INV1 ~ INV4
MSEL-01-ALG1（跨目录排序样例表）
```

### 5.3 测试覆盖盲点

| 未覆盖 ID | 现状 | 应补偿方式 |
|---|---|---|
| S6 picker 成功/关闭两分支 | 无 | mock picker 函数注入回调断言（picker 本体随 BRW-01 测） |
| S5 动作期间连接切换竞态 | 无 | notifier 级测试：建队前 connId 读到 null → 直接 return 不写 provider |
| 底栏遮挡滚动到底 | 无 | widget 测试 list bottom padding 存在性断言 |

### 5.4 门禁测试文件位置

```
test/features/browser/msel_01_multi_select_test.dart
```
（命名核查 2026-08-23：test/features/browser/ 无 msel_ 前缀，无冲突。）

---

## §6 算法样例

```
ALG [MSEL-01-ALG1-orderedSelectedFiles]:
  # 输入: store = {dirA:{a2,a1}, dirB:{b1}}（键序即插入序）
  #       dirA 当前排序快照 = [a1, a2, a3]；dirB 缓存未命中
  # 规则:
  #   a) 组间序 = store 键插入序（首次进入目录顺序）
  #   b) 组内序 = directoryContentsProvider(该目录).valueOrNull 快照中
  #      按选中 path 过滤后的相对序
  #   c) 快照不可用（null / 被 TTL/LRU 淘汰）→ 该组回退 path 字典序
  步骤:
    dirA 组: 快照命中 → 过滤得 [a1, a2]
    dirB 组: 快照 null   → 字典序 [b1]
  断言: 结果 = [a1, a2, b1]                                        # U7
  变体: store={dirB:{b1},dirA:{a1}}（先 dirB 后 dirA 进入）
        → 结果 = [b1, a1,...]（组间序跟进入顺序，不按路径名）        # b) 规则反例
  变体: dirA 快照含 a3 但未选 → a3 不出现                          # 过滤正确性
  否定断言: 任一选中 path 在结果中恰好出现一次；无选中 path 遗漏
```

---

## §7 跨模块影响

| 其它 feature | 影响点 | 影响条件 | 需要补的回归断言 |
|---|---|---|---|
| BRW | 共用 breadcrumb Row 改造点（SRCH-01 S8）与 playlist picker（BRW-01 S7/S8） | 实施顺序 BRW→SRCH→MSEL | brw_01_folder_actions 族不改一字全绿 |
| PLY | 建队写入 → persistQueueOnChange 自动持久化 → 重启恢复 | 以此播放后杀进程 | net1_legacy_queue_restore 读取路径一次全绿 |
| PLY | playModeProvider 只读消费 | shuffle 下以此播放 | o3_create_queue_play_mode_test 全绿 |
| SRCH | Row 内 IconButton 追加顺序（search 之后 checklist） | 同一改造点两次落刀 | srch_01 面板开关测试全绿即可 |
| HOME | browser_screen 结构变化 | Tab 嵌布 | home 族全绿 |

---

## §8 平台特性与手动 QA

逐条核对 docs/dev/platform-pitfalls.md：

| 踩坑条目 | 是否触及 | 处置 |
|---|---|---|
| P14 async gap | 是 | S5/S6 await 后 context.mounted 检查（文件级豁免已存在，模式照抄 ：176/:213） |
| P11 build 期改 provider | 是 | 勾选切换发生在 tap 回调；S7 联动清理在 provider 监听回调 |
| P13 defunct State | 是 | AutoDispose notifier 承载状态，无 BuildContext 长持有 |
| P10 单一写源 | 是 | 队列写入复用 currentPlayQueueProvider 单点 |

**可行性依据（铁律 6）：**

- R1 Dart `Map` 字面量与 `Map()` 默认实现为插入序 LinkedHashMap（Dart SDK 官方文档 dart:core Map "may contain fewer... insertion order"——语言保证迭代序=插入序）：仓库现有同款依赖先例——navigationStackProvider 以 List 模拟栈但 store 语义同类；本 spec 依赖的是语言级保证而非框架行为，官方引用即依据。
- R2 BottomAppBar + Scaffold bottomPadding 协调：Flutter Material 标准 API（现有代码未用过 BottomAppBar，属新 API 引入——替代方案为普通 Container 底栏 + MediaQuery padding 手算）。**裁决：不用 BottomAppBar，用普通 Container 包 SafeArea 置于 Column 尾部**（仓库现有布局语汇，无新 API），规避验证负担。

**真机风险列：**

| 风险 | 近似测试方案 | 测不了 → 进 mqa-backlog |
|---|---|---|
| 大勾选集（数百首）入单时 addTracksToPlaylist 逐条 INSERT 耗时 | 单元测 500 条耗时上限断言放宽 | 低风险，不进 backlog |

无平台原生通道改动，manual_qa_required=false。

---

## §9 dev-status.json 条目对照

```json
"MSEL-01": {
  "spec_file": "docs/features/MSEL-01.md",
  "spec_anchored_files": [
    "lib/features/browser/browser_screen.dart",
    "lib/features/browser/widgets/file_list_item.dart",
    "lib/features/browser/browser_provider.dart",
    "lib/features/playlist/domain/playlist_service.dart",
    "lib/shared/models/play_queue.dart"
  ],
  "scenarios": ["MSEL-01-S1","MSEL-01-S2","MSEL-01-S3","MSEL-01-S4","MSEL-01-S5","MSEL-01-S6","MSEL-01-S7","MSEL-01-S8"],
  "invariants": ["MSEL-01-INV1","MSEL-01-INV2","MSEL-01-INV3","MSEL-01-INV4"],
  "algorithms": ["MSEL-01-ALG1-orderedSelectedFiles"],
  "test_files": ["test/features/browser/msel_01_multi_select_test.dart"],
  "test_coverage_gaps": [],
  "cross_module_impacts": ["PLY", "BRW", "SRCH"],
  "manual_qa_required": false,
  "dependencies": ["BRW-01", "SRCH-01"],
  "impl_status": "pending",
  "test_status": "pending",
  "check_status": "pending"
}
```
