# SET-01 — 设置页"清除目录缓存"

> dev-plan 产出：2026-07-23（dogfood 新流程首个功能，用户已 ack §1.2 并授权全链执行）

---

## §0 头部元数据

```yaml
id: SET-01
name: 设置页"清除目录缓存"
priority: P2
status: draft
created_at: 2026-07-23
last_updated: 2026-07-23
spec_anchored_files:
  - lib/features/settings/settings_screen.dart
  - lib/features/browser/browser_provider.dart
  - lib/shared/di/providers.dart
  - lib/features/browser/domain/cache_policy.dart
cross_module_impacts: [BRW]
manual_qa_required: false
```

---

## §1 用户视角（你来扫这一节就够）

### 1.0 原始需求（用户原话逐字记录）

> "还有一个问题……我希望在设计和开发的过程把 bug 数量尽可能降低"（流程重构背景）
> "可以开始。功能选清缓存按钮。直接把任务都做完吧：把 skill 重构完，把功能开发完，然后 push 到 github"（2026-07-23，用户选定本功能作为新流程 dogfood 并授权全链执行，§1.2 视为已 ack）

### 1.1 这一功能干什么（一句话）

在设置页提供"清除目录缓存"入口，一键清空文件浏览的目录缓存并反馈清除条数，清除后浏览目录重新向 NAS 拉取。

### 1.2 用户期望的场景

| ID | 你看到的样子 | 期望行为 |
|----|----|----|
| U1 | 设置页有"清除目录缓存"一项，显示当前缓存条数 | 点击后立即清除全部目录缓存，SnackBar 提示"已清除 N 条目录缓存" |
| U2 | 缓存为空时点击 | SnackBar 提示"没有可清除的缓存"，不报错 |
| U3 | 清除后回到文件浏览页打开任意目录 | 目录内容重新从 NAS 拉取（不是旧缓存） |
| U4 | 清除缓存时正在浏览的队列/连接 | 播放队列、活跃连接、导航位置均不受影响 |

访谈边界裁决（明显默认，已确认）：缓存清除是低风险操作，**不要确认弹窗**，直接执行 + SnackBar 反馈；条数指 `connectionId:path` 缓存键数量。

---

## §2 已实现的功能骨架（代码锚点）

### 2.1 文件与分层

| 层 | 文件 | 行数 | 角色 |
|---|---|---|---|
| UI | `lib/features/settings/settings_screen.dart` | 253 | 设置页：播放设置/外观/连接/关于四个 section（_SectionHeader 在 :31/:39/:45/:57） |
| Provider | `lib/features/browser/browser_provider.dart` | 204 | 目录缓存的真实运行时载体（注意：**不是** DirectoryService 内部 `_cache`，后者未接线到 provider） |
| DI 桥 | `lib/shared/di/providers.dart` | — | `clearDirectoryCacheProvider` / `directoryCacheProvider` 已在 :31-32 导出 |
| Domain | `lib/features/browser/domain/cache_policy.dart` | 102 | CachePolicy TTL/LRU 纯函数（本功能不改它） |
| 测试 | `test/features/settings/settings_test.dart` / `test/features/browser/brw_*_test.dart` | — | 既有设置与浏览器测试 |

### 2.2 关键 Provider 表

| Provider 名 | 类型 | 实现位置 | 用途 |
|---|---|---|---|
| `directoryCacheProvider` | `StateProvider<Map<String, CacheEntry<List<NasFile>>>>` | `browser_provider.dart:32` | 目录缓存本体，键格式 `connectionId:path` |
| `clearDirectoryCacheProvider` | `Provider<void Function(String? path)>` | `browser_provider.dart:35-57` | path=null 清空全部；path 非空按 `:$path` 后缀删 + invalidate 该 path 的 contents |
| `directoryContentsProvider` | `FutureProvider.family<List<NasFile>, String>` | `browser_provider.dart:61` | 目录内容加载，先查 `directoryCacheProvider` 命中再走网络 |

### 2.3 状态机图

N/A（无状态机）。

### 2.4 逆抽发现的现存缺陷（本功能顺带修）

`clearDirectoryCacheProvider` 的 **path==null 分支**（:37-39）只把 map 置空，**未 invalidate `directoryContentsProvider` family**——而 `directoryContentsProvider` 自身是 FutureProvider.family，自带异步值缓存：map 清空后已加载过的目录 family 仍持有旧列表，UI 继续显示旧数据直到 family 自然失效。path 非空分支（:49）有 invalidate，两分支行为不一致。S1 的修复点即此处。

---

## §3 行为规约（Given-When-Then）

### 3.1 清除全部缓存

- **[SET-01-S1] `status: new`** 全量清除返回条数并使目录内容失效
  ```
  Given directoryCacheProvider 中有 N 条缓存（N ≥ 1），directoryContentsProvider('/a') 已加载过
  When 调用 ref.read(clearDirectoryCacheProvider)(null)
  Then 调用返回 N（int）
  And directoryCacheProvider.state 变为 {}
  And directoryContentsProvider family 全量 invalidate（下次 read 触发重新加载）
  否定断言:
    - currentPlayQueueProvider / activeConnectionProvider / navigationStackProvider 均不变
    - 不发起任何网络请求（WebDavClient.listDirectory 不被调用）
  ```
  **修改点**：`lib/features/browser/browser_provider.dart:35-57` — `clearDirectoryCacheProvider` 的类型从 `Provider<void Function(String? path)>` 改为 `Provider<int Function(String? path)>`；path==null 分支在清空 map 后追加 `ref.invalidate(directoryContentsProvider);`（invalidate 整个 family，不带参数），并在清空前用局部变量记下 `length` 作为返回值。
  Code evidence: `lib/features/browser/browser_provider.dart:35`

- **[SET-01-S2] `status: modified`** 按路径清除语义保留并返回条数
  ```
  Given 缓存含键 "1:/music" 与 "1:/audiobook"（N=2 命中同一后缀）
  When 调用 clearDirectoryCacheProvider('/music')
  Then 返回 1（仅 "1:/music" 被删）
  And "1:/audiobook" 仍在缓存中
  And directoryContentsProvider('/music') 被 invalidate
  否定断言:
    - "1:/audiobook" 的 CacheEntry 不变（value 与 createdAt 原值）
  ```
  **修改点**：同文件同 provider，path 非空分支把原 `void` 改为返回 `toRemove.length`，其余逻辑（后缀匹配 :41-44、invalidate(path) :49）不动。现有调用方 `browser_screen.dart:78` 忽略返回值，兼容。
  Code evidence: `lib/features/browser/browser_provider.dart:40-56`

- **[SET-01-S3] `status: new`** 空缓存清除
  ```
  Given directoryCacheProvider.state == {}
  When 调用 clearDirectoryCacheProvider(null)
  Then 返回 0
  And state 保持 {}
  否定断言:
    - 不抛异常
    - 不发起网络请求
  ```
  Code evidence: `lib/features/browser/browser_provider.dart:37`

### 3.2 设置页入口

- **[SET-01-S4] `status: new`** 设置页"清除目录缓存"项显示当前条数并执行清除
  ```
  Given directoryCacheProvider 有 3 条缓存
  When 构建 SettingsScreen
  Then 存在 title="清除目录缓存" 的 ListTile，subtitle 显示"当前缓存 3 条目录"
  When 点击该 ListTile
  Then SnackBar 文案为"已清除 3 条目录缓存"
  And directoryCacheProvider.state == {}
  否定断言:
    - 不弹出任何确认 Dialog（直接执行）
    - 页面不跳转（Navigator 无 push/pop）
  ```
  **修改点**：`lib/features/settings/settings_screen.dart` — 在"连接" section（:45）之后、"关于" section（:57）之前插入新 section `_SectionHeader(title: '存储')` + 私有组件 `_ClearCacheTile extends ConsumerWidget`。tile 通过 `import '../../shared/di/providers.dart';` 读取 `directoryCacheProvider`（watch 以显示条数）与 `clearDirectoryCacheProvider`（read 后调用），`ScaffoldMessenger.of(context).showSnackBar(...)` 反馈。**严禁 import `lib/features/browser/` 任何文件**（feature 隔离，只能走 DI 桥）。
  Code evidence: `lib/features/settings/settings_screen.dart:45`

- **[SET-01-S5] `status: new`** 空缓存时的反馈文案
  ```
  Given directoryCacheProvider.state == {}
  When 点击"清除目录缓存"
  Then SnackBar 文案为"没有可清除的缓存"
  否定断言:
    - directoryCacheProvider.state 保持 {}（不写入任何键）
  ```
  Code evidence: 新代码（S4 同文件）

### 3.3 现有行为逆抽（回归守护）

- **[SET-01-S6]** 目录加载缓存命中不发网络请求
  ```
  Given "1:/music" 有未过期缓存
  When read directoryContentsProvider('/music')
  Then 返回缓存列表（fromCache 语义），WebDavClient 不被调用，且该键 lastAccessedAt 被刷新
  ```
  Code evidence: `lib/features/browser/browser_provider.dart:67-75`

- **[SET-01-S7]** 缓存键格式恒为 `connectionId:path`
  ```
  Given connectionId=1, path='/music'
  When 目录加载写入缓存
  Then 缓存键为 "1:/music"
  ```
  Code evidence: `lib/features/browser/browser_provider.dart:66`

---

## §4 不变量

- **[SET-01-INV1]** 清除缓存只动缓存：`clearDirectoryCacheProvider` 任何分支不得修改 currentPlayQueueProvider / activeConnectionProvider / navigationStackProvider / sortOptionProvider
  证据：`lib/features/browser/browser_provider.dart:35-57`（现状仅操作 directoryCacheProvider 与 directoryContentsProvider，改动后保持）
- **[SET-01-INV2]** 清除后无陈旧目录内容：path==null 清除后，任何 `directoryContentsProvider(p)` 的下一次读取必须触发重新加载（family 已被 invalidate）
  证据：新代码（S1 修复点）
- **[SET-01-INV3]** settings feature 不得直接 import browser feature：新增代码仅经 `shared/di/providers.dart` 引用缓存相关 provider
  证据：`lib/shared/di/providers.dart:31-32`（已导出）；`cross-imports.sh feature-isolation` 守门

---

## §5 测试规约

### 5.1 现有测试清单

| 测试文件 | 覆盖 | 备注 |
|---|---|---|
| `test/features/browser/ref_18_test.dart` | CachePolicy TTL/LRU | 纯函数层 |
| `test/features/browser/brw_*.dart` | 目录加载/导航/面包屑 | 不动 |
| `test/features/settings/settings_test.dart` | 主题/速度/快进步长设置 | 不动 |

### 5.2 测试 ID 派生清单

```
SET-01-S1 … S7        # Scenario（S1/S2/S3/S4/S5 新增，S6/S7 逆抽）
SET-01-INV1 … INV3    # 不变量
```

### 5.3 测试覆盖盲点

| 未覆盖 ID | 现状 | 补偿方式 |
|---|---|---|
| S1/S2/S3/INV1/INV2 | clearDirectoryCacheProvider 无任何直测（仅 browser_screen 刷新按钮间接用 path 分支） | 新建 `test/features/settings/set_01_test.dart` provider 层测试（ProviderContainer + fake webdav） |
| S4/S5 | 设置页无缓存相关 UI 测试 | 同文件 widget 测试段（widget_helpers pump） |

测试工具：`test/helpers/`（fake_webdav_client / widget_helpers / test_factories）；Provider 测试用 `ProviderContainer`，widget 测试用 `ProviderScope overrides`。S6 的"不发网络请求"用 fake client 的调用计数断言（否定断言落地方式）。

---

## §6 算法样例

无新增纯函数。

---

## §7 跨模块影响

`cross-imports.sh impact lib/features/browser/browser_provider.dart` 结果：引用方 = browser（15 文件）+ main.dart。settings 目前无引用（本功能经 DI 桥新增消费，不构成违规）。

| 其它 feature | 影响点 | 影响条件 | 需要补的回归断言 |
|---|---|---|---|
| BRW | `clearDirectoryCacheProvider` 签名 void→int | 返回类型变更 | `browser_screen.dart:78` 现有调用（忽略返回值）编译通过 + brw 全量测试零回归 |
| BRW | path==null 分支新增 family invalidate | 全量清除语义增强 | S6 缓存命中语义不受影响（invalidate 只影响后续读取，不改变缓存命中逻辑本身） |

---

## §8 平台特性与手动 QA

已逐条核对 `docs/dev/platform-pitfalls.md`：本功能不触及 P1-P16 任何一类（无音频/监听器/平台 channel/异步竞态——清除是同步 map 操作）。

真机风险列：

| 风险 | 近似测试方案 | 测不了 → 进 mqa-backlog |
|---|---|---|
| 清除后重新拉取慢（弱网） | fake_webdav_client 延迟注入测加载路径（既有 BRW 测试已覆盖加载路径） | 无新增真机项 |

本功能不涉及平台原生特性，全部可在 `flutter test` 中验证，无需手动 QA。`manual_qa_required: false`。

---

## §9 dev-status.json 条目对照

经 `dev-status.sh create` 创建，字段与生命周期见 `.claude/plugins/sona-dev/reference/SCHEMA.md` §1（唯一源）。

---

## changelog

- 2026-07-23: 创建 SET-01 spec（新流程 dogfood；用户原话见 §1.0，已授权全链执行） (status: new)
