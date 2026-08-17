# REF-06 — clearDirectoryCacheProvider 精确匹配（path 后缀匹配 → 连接级精确匹配）

## §0 头部元数据

```yaml
id: REF-06
name: clearDirectoryCacheProvider 连接级精确匹配（跨连接误清缓存修复）
priority: P2
status: active
created_at: 2026-08-16
last_updated: 2026-08-16
spec_anchored_files:
  - lib/features/browser/browser_provider.dart
  - lib/features/browser/browser_screen.dart
  - lib/features/settings/settings_screen.dart
cross_module_impacts: [BRW, SET, CON]   # browser 下拉刷新 / settings 清除缓存 tile / connection 切换链路（旁证不受影响）
manual_qa_required: false               # 纯 Riverpod 状态逻辑，ProviderContainer 全可测，不涉平台原生
```

---

## §1 用户视角

### 1.0 原始需求（用户原话逐字记录）

来源：`docs/cr/cr-20260816-0803-browser-home.md` D1（cr 复核分流，用户裁决"修"→ 转 REF 需求流程，无复现测试要求）：

> #### D1. clearDirectoryCacheProvider 按 path 后缀匹配，跨连接误清缓存条目
> - 类型 / 严重度 / 维度：DESIGN / Minor / 正确性
> - 证据：`lib/features/browser/browser_provider.dart:55-82`
>   ```dart
>   final suffix = ':$path';
>   final toRemove = ref
>       .read(directoryCacheProvider)
>       .keys
>       .where((k) => k.endsWith(suffix))
>       .toList();
>   ```
>   缓存 key 是 `'${conn.id}:$path'`（第 89 行），但清除按 `endsWith(':$path')` 匹配：
>   - 连接 id 1 与连接 id 11 同路径：`'1:/music'` 与 `'11:/music'` 都以 `':/music'` 结尾 → 下拉刷新连接 1 时连接 11 的同路径缓存被一并清除（key 的 id 前缀语义被绕过）；
>   - 子目录不受影响（`'1:/music/sub'` 不以 `':/music'` 结尾）——这是当前行为正确的一半。
> - 取舍分析：无正确性损失（被误清的条目只是下次多一次 PROPFIND），但"key 含连接 id 而清除逻辑忽略 id"自相矛盾，将来若引入 id 含 `:` 的格式或按连接批量清缓存会踩坑。可裁决：接受现状（影响极小）或让清除函数接收 `conn.id` 参数做精确匹配。
> - 修复建议（方向）：clearDirectoryCacheProvider 增加连接 id 维度（调用方 browser_screen 下拉刷新处可读 activeConnection），key 匹配改为 `${conn.id}:$path` 全等；或文档化说明"跨连接清除是有意的保守行为"。

用户裁决：**精确匹配**——清除函数接收连接 id，key 匹配改为 `${conn.id}:$path` 全等（不采用"文档化保守行为"选项）。

### 1.1 这一功能干什么（一句话）

下拉刷新某个文件夹时，只清除"当前连接 + 该文件夹"这一条缓存，不再误清其它连接的同名路径缓存——缓存 key 里的连接 id 从"装饰字段"变成真正参与匹配的语义。

### 1.2 用户期望的场景

| ID | 你看到的样子 | 期望行为 |
|----|----|----|
| U1 | 配了两台 NAS，都有"音乐"文件夹。在连接 1 的"音乐"里下拉刷新 | 连接 1 的目录列表重新加载；连接 2 的同名"音乐"缓存不受影响，切回连接 2 时仍是秒开（修复前：连接 2 的缓存被一并清掉，下次进入要多等一次加载） |
| U2 | 在"音乐/专辑A"子文件夹里下拉刷新 | 只重新加载当前子文件夹；"音乐"和其它子文件夹的缓存保留，点回去秒开 |
| U3 | 设置页点"清除目录缓存" | 一键清空全部缓存，弹出"已清除 N 条目录缓存"提示（行为与修复前一致） |
| U4 | 只有一台 NAS 的情况 | 行为与修复前完全一致（单连接下精确匹配与后缀匹配结果相同） |

---

## §2 已实现的功能骨架（代码锚点）

### 2.1 文件与分层

| 层 | 文件 | 行数 | 角色 |
|---|---|---|---|
| Provider | `lib/features/browser/browser_provider.dart` | 258 | `directoryCacheProvider`（45-46，StateProvider<Map<String, CacheEntry<List<NasFile>>>>）+ `clearDirectoryCacheProvider`（55-82，`Provider<int Function(String? path)>`）+ `directoryContentsProvider`（84-129，缓存 key 构造 :89） |
| UI | `lib/features/browser/browser_screen.dart` | 393 | 下拉刷新（68-74）：`ref.read(clearDirectoryCacheProvider)(currentPath)`（:71） |
| UI | `lib/features/settings/settings_screen.dart` | 259 | `_ClearCacheTile`（223-240）：`ref.read(clearDirectoryCacheProvider)(null)` 全量清除（:233） |
| Domain | `lib/features/browser/domain/cache_policy.dart` | 102 | `CacheEntry`（16-41，value/createdAt/lastAccessedAt）+ `CachePolicy`（48-101，TTL/LRU，本修改不触碰） |
| 桥接 | `lib/shared/di/providers.dart` | 250 | `clearDirectoryCacheProvider` re-export（:35），供 settings 跨 feature 使用 |
| 测试 | `test/features/browser/brw_05_test.dart` | 653 | 单参签名调用点：:221-222、:467 |
| 测试 | `test/features/browser/brw_06_test.dart` | 276 | 单参签名调用点：:124-125、:181-182、:248-249 |
| 测试 | `test/features/settings/set_01_test.dart` | 416 | 单参签名调用点：:115（null）、:148（'/music'）、:179（null） |

### 2.2 关键 Provider 表

| Provider 名 | 类型 | 实现位置 | 用途 |
|---|---|---|---|
| directoryCacheProvider | StateProvider<Map<String, CacheEntry<List<NasFile>>>> | browser_provider.dart:45-46 | 目录缓存状态 |
| clearDirectoryCacheProvider | Provider<int Function(String? path)> | browser_provider.dart:55-82 | 清除缓存：null=全清，path=按后缀匹配清 |
| directoryContentsProvider | FutureProvider.family<List<NasFile>, String> | browser_provider.dart:84-129 | 目录内容；缓存 key `'${conn.id}:$path'`（:89） |

### 2.3 状态机图

本功能无状态机（纯 Map 增删），跳过。

---

## §3 行为规约（Given-When-Then）

### 3.1 现有行为（逆抽，缺陷态）

- **[REF-06-S1]** path 非空时按 `endsWith(':$path')` 后缀匹配，跨连接误清同路径缓存
  ```
  Given directoryCacheProvider 含 key '1:/music' 与 '11:/music'（连接 id 1 与 11，同路径）
  When 调用 clearDirectoryCacheProvider('/music')
  Then suffix = ':/music'；两个 key 都以 suffix 结尾 → toRemove = ['1:/music', '11:/music']
  And 两条缓存条目都被删除（连接 11 的缓存被连接 1 的下拉刷新误清）
  And invalidate(directoryContentsProvider('/music')) 触发（:78）
  And 返回 toRemove.length == 2
  ```
  Code evidence: `lib/features/browser/browser_provider.dart:63-68`（`final suffix = ':$path';` + `.where((k) => k.endsWith(suffix))`）
  缺陷态锚定：无直接测试锚定跨连接误清（brw_05/brw_06 均只测单连接 `clearCache('/music')`，key 均为 `'1:/music'`，无 id 前缀冲突形态）——本 spec §5.3 记为盲点，由 §5.4 门禁测试补缺陷态用例。

- **[REF-06-S2]** path 为 null 时全量清除：state 置 `{}` + invalidate 整个 family + 返回清除条数
  ```
  Given directoryCacheProvider 含 N 条缓存（N ≥ 0）
  When 调用 clearDirectoryCacheProvider(null)
  Then count = N；state = {}（:59）；invalidate(directoryContentsProvider)（:60）；返回 N
  ```
  Code evidence: `lib/features/browser/browser_provider.dart:56-61`
  测试锚定：`test/features/settings/set_01_test.dart:114-121`（S2 全量清除断言）、`brw_05_test.dart:467-471`。

- **[REF-06-S3]** 子目录不被父路径清除命中（当前行为正确的一半）
  ```
  Given directoryCacheProvider 含 '1:/music' 与 '1:/music/sub'
  When 调用 clearDirectoryCacheProvider('/music')
  Then '1:/music/sub'.endsWith(':/music') == false → 子目录条目保留
  And 仅 '1:/music' 被删除
  ```
  Code evidence: `lib/features/browser/browser_provider.dart:63-68`（endsWith 语义）；cr-0803 D1 原文确认（"子目录不受影响——这是当前行为正确的一半"）
  测试锚定：无直接断言（brw_05/brw_06 的清除用例只预置单条目）——§5.3 盲点，§5.4 门禁补。

### 3.2 修改方案（status: new）

设计裁决（用户裁决"精确匹配"）：

**签名变更**：`Provider<int Function(String? path)>` → `Provider<int Function(int? connectionId, String? path)>`。

| 边界情况 | 裁决 |
|---|---|
| path == null（全量清除） | 行为与修复前逐字节一致：清空整个 state、invalidate 整个 directoryContentsProvider family、返回清除条数。connectionId 参数被忽略（可传 null） |
| path != null 且 connectionId != null | **精确全等匹配**：key 恰为 `'$connectionId:$path'` 的条目才删除（字符串全等，不做任何前缀/后缀匹配）。命中 0 或 1 条 |
| path != null 且 connectionId == null | 降级为旧后缀匹配（`endsWith(':$path')`）——保守回退，文档化；**生产调用方不经过此形状**（browser_screen 下拉刷新仅在活跃连接存在时可渲染，settings 全量清除走 path==null 分支） |
| connectionId 为 null 时 path 同参数规则 | 与上两行一致（null connId 仅在全量清除与后缀回退两处出现） |
| invalidate(directoryContentsProvider(path)) | 保持不变（:78，path 非空分支固定执行；全量分支固定 invalidate 无参 family） |
| 返回值语义 | 不变：删除条数（全量=原条数；精确=0 或 1；后缀回退=命中条数） |

- **[REF-06-S4]** 精确匹配：清除只命中 `'$connectionId:$path'`，其它连接同路径缓存保留 （status: new）
  ```
  Given directoryCacheProvider 含 '1:/music'、'11:/music'、'1:/books'
  When 调用 clearDirectoryCacheProvider(1, '/music')
  Then 精确 key = '1:/music' → toRemove = ['1:/music']
  And '11:/music'（其它连接同路径）与 '1:/books'（其它路径）保留
  And invalidate(directoryContentsProvider('/music')) 触发；返回 1
  否定断言:
    - 其它连接的缓存条目不得被删除（'11:/music' 必须保留）
    - 同连接其它路径条目不得被删除（'1:/books' 必须保留）
    - 未命中时不发生任何 state 变更（toRemove 空 → update 不执行，见 :69-77 现有守卫）
  ```
  **修改点 1**：`lib/features/browser/browser_provider.dart:55-82` —— 签名与匹配逻辑：
  ```dart
  // 修改前（55-56 行签名 + 63-68 行匹配）:
  final clearDirectoryCacheProvider = Provider<int Function(String? path)>((ref) {
    return (String? path) {
      ...
      final suffix = ':$path';
      final toRemove = ref
          .read(directoryCacheProvider)
          .keys
          .where((k) => k.endsWith(suffix))
          .toList();
  // 修改后:
  final clearDirectoryCacheProvider =
      Provider<int Function(int? connectionId, String? path)>((ref) {
    return (int? connectionId, String? path) {
      if (path == null) {
        // 全量清除：与修复前语义一致（REF-06-S2），connectionId 忽略。
        final count = ref.read(directoryCacheProvider).length;
        ref.read(directoryCacheProvider.notifier).state = {};
        ref.invalidate(directoryContentsProvider);
        return count;
      }
      // REF-06: 连接 id 非空 → 精确全等匹配（cr-20260816-0803 D1）；
      // 连接 id 为空 → 降级旧后缀匹配（保守回退，生产调用方不走此形状）。
      final exactKey = connectionId == null ? null : '$connectionId:$path';
      final toRemove = exactKey == null
          ? ref
              .read(directoryCacheProvider)
              .keys
              .where((k) => k.endsWith(':$path'))
              .toList()
          : (ref.read(directoryCacheProvider).containsKey(exactKey)
              ? [exactKey]
              : <String>[]);
      // —— 以下 toRemove.isNotEmpty 守卫、update 删除、invalidate、return 与现状
      //    （69-80 行）逐行不变 ——
  ```

- **[REF-06-S5]** 同连接子目录语义保持：清除父路径不动子目录缓存 （status: new）
  ```
  Given directoryCacheProvider 含 '1:/music'、'1:/music/sub'、'1:/music/sub/deep'
  When 调用 clearDirectoryCacheProvider(1, '/music')
  Then 精确 key = '1:/music' → 仅该条删除
  And '1:/music/sub' 与 '1:/music/sub/deep' 保留（与修复前 endsWith 行为一致，REF-06-S3 保持）
  否定断言:
    - 子目录缓存条目不得被删除（'1:/music/sub' 必须保留）
    - 不得对目录内容做任何重新拉取（不调用 webDavClientProvider.listDirectory）
  ```
  Code evidence（修改点）: 修改后 `browser_provider.dart:55-82` 精确全等匹配——字符串全等天然不做前缀匹配。

- **[REF-06-S6]** 全量清除（path == null）行为与修复前逐字节一致 （status: new）
  ```
  Given directoryCacheProvider 含 3 条缓存（跨多连接）
  When 调用 clearDirectoryCacheProvider(null, null)
  Then state = {}；invalidate(directoryContentsProvider)；返回 3
  否定断言:
    - 不得只清部分条目（必须全空，多连接条目一并清空——全量清除本就跨连接）
    - 不得改变返回值语义（返回清除条数而非 0/空）
  ```
  Code evidence（修改点）: 修改后 `browser_provider.dart:56-61`（path==null 分支原样保留）。

- **[REF-06-S7]** 连接 id 为空 + path 非空 → 旧后缀匹配回退（不抛异常） （status: new）
  ```
  Given directoryCacheProvider 含 '1:/music' 与 '11:/music'
  When 调用 clearDirectoryCacheProvider(null, '/music')
  Then 降级 endsWith(':/music') → 两条都被删除（与修复前行为一致，保守回退）
  否定断言:
    - 不得抛出任何异常（该形状是合法调用）
    - 生产调用方不得使用该形状——browser_screen 下拉刷新必须传活跃连接 id（S8），settings 全量清除走 path==null
  ```
  Code evidence（修改点）: 修改后 `browser_provider.dart` 的 `exactKey == null` 分支。

- **[REF-06-S8]** browser_screen 下拉刷新改传活跃连接 id （status: new）
  ```
  Given 活跃连接存在（id = 1），浏览器当前目录为 '/music'
  When 用户下拉刷新
  Then onRefresh 读 activeConnectionProvider.valueOrNull?.id → 1
  And 调用 clearDirectoryCacheProvider(1, '/music')
  And ref.refresh(directoryContentsProvider('/music').future) 重新拉取（:72-73 不变）
  否定断言:
    - 不得以 null 连接 id 调用清除函数（活跃连接不存在时兜底允许，但生产路径必须传 id）
    - 清除后不得残留当前连接的 '/music' 缓存条目
  ```
  **修改点 2**：`lib/features/browser/browser_screen.dart:69-74`：
  ```dart
  // 修改前（69-74 行）:
  onRefresh: () async {
    final currentPath = ref.read(navigationStackProvider).last;
    ref.read(clearDirectoryCacheProvider)(currentPath);
    final _ = await ref
        .refresh(directoryContentsProvider(currentPath).future);
  },
  // 修改后:
  onRefresh: () async {
    final currentPath = ref.read(navigationStackProvider).last;
    // REF-06: 传活跃连接 id，清除只命中本连接的缓存（cr-20260816-0803 D1）。
    final connId = ref.read(activeConnectionProvider).valueOrNull?.id;
    ref.read(clearDirectoryCacheProvider)(connId, currentPath);
    final _ = await ref
        .refresh(directoryContentsProvider(currentPath).future);
  },
  ```
  模式依据：`activeConnectionProvider` 已在 browser_screen.dart:114 以 `ref.read(activeConnectionProvider).valueOrNull` 读取（同文件既有用法，无需新 import——browser_screen.dart:22 已 import `../../shared/di/providers.dart`）。

- **[REF-06-S9]** settings 全量清除改传双参数 （status: new）
  ```
  Given 设置页缓存区含 N 条缓存
  When 用户点击"清除目录缓存"
  Then _ClearCacheTile onTap 调用 clearDirectoryCacheProvider(null, null)
  And SnackBar 文案逻辑不变（removed > 0 ? '已清除 N 条目录缓存' : '没有可清除的缓存'）
  否定断言:
    - 不得遗漏参数（新签名为双参，调用必须同步更新，否则编译错误即门禁）
    - 清除条数提示与修复前一致（全量语义不变）
  ```
  **修改点 3**：`lib/features/settings/settings_screen.dart:233`：
  ```dart
  // 修改前:
  final removed = ref.read(clearDirectoryCacheProvider)(null);
  // 修改后:
  final removed = ref.read(clearDirectoryCacheProvider)(null, null);
  ```

---

## §4 不变量

- **[REF-06-INV1]** 缓存 key 恒为 `'${conn.id}:$path'` 形态，清除与写入使用同一 key 约定
  证据：`lib/features/browser/browser_provider.dart:89`（cacheKey 构造）+ 修改点 1（精确匹配 `'$connectionId:$path'` 全等）。写路径不改（:89 保持），清路径对齐该格式。

- **[REF-06-INV2]** 清除父路径永不删除其子目录缓存条目
  证据：修改后精确全等匹配（字符串全等不做前缀匹配）；修复前 endsWith 语义同样满足（:63-68）。两条路径（新旧行为）都成立。

---

## §5 测试规约

### 5.1 现有测试清单

| 测试文件 | 覆盖的 Scenario / INV | 备注 |
|---|---|---|
| test/features/browser/brw_05_test.dart:217-233（BRW-T 下拉刷新清除） | REF-06-S1（单连接形态） | 调用点 :221-222 单参签名，**必须同步改双参**；断言 `cacheAfterClear.containsKey('1:/music') == false` 修复后保持成立 |
| test/features/browser/brw_05_test.dart:463-471 | REF-06-S2 | :467 单参 → 双参（null, null） |
| test/features/browser/brw_06_test.dart:119-152（BRW-T34）、:154-208（BRW-T35）、:210-274（BRW-T36） | REF-06-S1/S2 刷新链路 | :124-125、:181-182、:248-249 单参 → 双参 |
| test/features/settings/set_01_test.dart:114-121/:147-153/:177-184 | REF-06-S2（null 全清 + '/music' 路径清） | :115（null）、:148（'/music'）、:179（null）单参 → 双参；S4 用例（:142-153）的 '/music' 断言键为 `'1:/music'`（单连接预置） |
| test/features/connection/test_02_con11_test.dart / bug_bug16_repro_test.dart / con_09_test.dart / bug_bug10_repro_test.dart | — | 切换连接清缓存走 `ref.invalidate(directoryCacheProvider)` 直清（非 clearDirectoryCacheProvider），不受签名影响 |

### 5.2 测试 ID 派生清单（dev-exe 派发测试 Agent 用）

```
REF-06-S1 … S9        # Scenario（S1~S3 现状锚定含缺陷态，S4~S9 修复目标）
REF-06-INV1 … INV2    # 不变量
REF-06-ALG1           # 算法样例（见 §6）
```

dev-exe 要求：S1（缺陷态跨连接误清）与 S3 由 §5.4 门禁文件覆盖；S2 由 set_01/brw_05 既有用例覆盖（同步改签名）；S4~S9 与 INV1/2、ALG1 由 §5.4 门禁文件覆盖。

### 5.3 测试覆盖盲点（dev-plan 写本文档时识别）

| 未覆盖 ID | 现状 | 应补偿方式 |
|---|---|---|
| REF-06-S1（跨连接误清缺陷态） | 零锚定（brw_05/brw_06 清除用例均单连接单条目） | §5.4 门禁文件先按缺陷态断言（双 key 同后缀 → 修复前全清），dev-exe 修复后该断言翻转 |
| REF-06-S3（子目录保留） | 零锚定 | §5.4 门禁文件补断言 |

### 5.4 测试文件位置（spec-scan --gate 硬校验）

新建：`test/features/browser/ref_06_cache_clear_test.dart`（ProviderContainer + 预置 directoryCacheProvider 手法同 brw_05/set_01；命名已核实与既有文件无冲突）

| 测试文件 | 覆盖 ID | 说明 |
|---|---|---|
| test/features/browser/ref_06_cache_clear_test.dart | REF-06-S1、S3、S4、S5、S6、S7、S8、REF-06-INV1、REF-06-INV2、REF-06-ALG1 | 门禁：dev-exe 修复后必须 PASS（cov-gate 内） |
| test/features/browser/brw_05_test.dart / brw_06_test.dart / test/features/settings/set_01_test.dart | REF-06-S2 | 既有用例，签名同步改双参后保持绿（回归护栏） |

---

## §6 算法样例

```
ALG [REF-06-ALG1-resolveRemoveKeys]:
  输入: connectionId=1, path='/music', 缓存含 {1:/music, 11:/music, 1:/music/sub}
      → 期望: ['1:/music']（精确全等，其余保留）                        # 主流程
  输入: connectionId=null, path='/music', 缓存同上
      → 期望: ['1:/music', '11:/music']（后缀回退，保守行为）            # 边界
  输入: connectionId=1, path='/missing', 缓存含 {1:/music}
      → 期望: []（未命中，state 不变，返回 0）                          # 边界
  输入: connectionId=null, path=null, 缓存含 3 条
      → 期望: state={}, 返回 3（全量清除，connectionId 忽略）            # 主流程
  输入: connectionId=1, path='/music/sub', 缓存含 {1:/music, 1:/music/sub}
      → 期望: ['1:/music/sub']（子目录路径精确命中自身，父条目保留）      # 边界
```

---

## §7 跨模块影响

`bash cross-imports.sh impact lib/features/browser/browser_provider.dart`（2026-08-16）→ 引用方（clearDirectoryCacheProvider 的**直接调用方**以 grep 核实为 browser_screen.dart:71 与 settings_screen.dart:233 两处）：

| 其它 feature | 影响点 | 影响条件 | 需要补的回归断言 |
|---|---|---|---|
| Browser（browser_screen.dart:68-74） | 下拉刷新调用签名单参 → 双参（修改点 2） | 编译期强制（签名变更）；运行时行为：只清本连接当前路径 | brw_05/brw_06 刷新链路用例改签名后保持绿；ref_06 门禁 S8 PASS |
| Settings（settings_screen.dart:223-240） | `_ClearCacheTile` 调用签名（修改点 3） | 同上 | set_01_test 全量清除用例改签名后保持绿（S2 语义不变） |
| Connection（connection_provider.dart:322-325 resetBrowserStateOnActiveConnectionChange / connection_list_screen.dart:79-80） | 切换连接走 `ref.invalidate(directoryCacheProvider)` 直清，**不经 clearDirectoryCacheProvider** | 无（不触碰）；清除函数语义收紧不影响 invalidate 全清 | test_02_con11 / bug_bug16 / con_09 / bug_bug10 既有切换断言保持绿 |
| 桥接（shared/di/providers.dart:35） | re-export 行不变（provider 名字不变，仅内部函数签名变） | 无 | 编译 + analyze 0 warning |
| Bug-31（browserClockProvider / 缓存 TTL） | cache_policy.dart 与 TTL 逻辑零触碰 | 无 | bug_bug31_repro_test 保持绿 |
| main.dart | import browser_provider（bridge） | 无 | 编译通过 |

---

## §8 平台特性与手动 QA

设计前已逐条核对 `docs/dev/platform-pitfalls.md`：
- **P10（数据源订阅方）**：clearDirectoryCacheProvider 的全部调用方已在 §7 用 grep 核实（browser_screen:71 / settings_screen:233 两处生产调用 + 三份测试文件），签名变更不遗漏订阅方（编译期强制）。
- **P11（provider build 期禁写）**：修改不改变任何 provider 的 build 期行为（清除函数仍由用户事件/刷新回调触发，:69-77 现有 update 守卫保留）。
- 其余条目（P1~P9、P12~P17）均不触及：不涉音频/生命周期/时间运算/超时分层（TTL 逻辑零改动，P16 不适用——本修改无新增"当前时刻"需求）。

**真机风险列**：

| 风险 | 近似测试方案 | 测不了 → 进 mqa-backlog |
|---|---|---|
| 真机双连接下拉刷新交互（U1 场景端到端） | 单测在 ProviderContainer 双连接预置缓存 + 精确清除断言（S4/S5）全量覆盖逻辑面 | 无（纯状态逻辑，全部可在 `flutter test` 中验证） |

本功能不涉及平台原生特性，全部可在 `flutter test` 中验证 → `manual_qa_required = false`。

---

## §9 dev-status.json 条目对照

```json
"REF-06": {
  "spec_file": "docs/features/REF-06.md",
  "spec_anchored_files": [
    "lib/features/browser/browser_provider.dart",
    "lib/features/browser/browser_screen.dart",
    "lib/features/settings/settings_screen.dart"
  ],
  "scenarios": ["REF-06-S1", "REF-06-S2", "REF-06-S3", "REF-06-S4", "REF-06-S5", "REF-06-S6", "REF-06-S7", "REF-06-S8", "REF-06-S9"],
  "invariants": ["REF-06-INV1", "REF-06-INV2"],
  "algorithms": ["REF-06-ALG1-resolveRemoveKeys"],
  "manual_qa_required": false,
  "user_acceptance_text": "见 §1.2"
}
```
