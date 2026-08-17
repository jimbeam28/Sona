# REF-10 — settings_service 顶层函数与实例方法双份实现统一（迁移测试后删顶层版）

## §0 头部元数据

```yaml
id: REF-10
name: settings_service 顶层函数与实例方法双份实现统一为实例方法单份
priority: P2
status: active
created_at: 2026-08-16
last_updated: 2026-08-16
spec_anchored_files:
  - lib/features/settings/domain/settings_service.dart
  - lib/features/settings/settings_provider.dart
  - test/features/settings/settings_test.dart
  - test/features/settings/ref_27_test.dart
  - lib/shared/di/providers.dart
cross_module_impacts: [SET]
manual_qa_required: false   # 纯 Dart 域层文件删除 + 测试迁移，不涉平台原生
```

---

## §1 用户视角

### 1.0 原始需求（用户原话逐字记录）

来源：`docs/cr/cr-20260816-0805-progress-timer-settings.md` D2（证据已修正），转 REF 需求流程：

> #### D2. `settings_service.dart` 顶层函数与类方法双份实现，顶层版本为死代码
>
> - 类型：DESIGN / 严重度：Minor / 维度：内部一致性（双重职责/死代码）
> - 证据：`lib/features/settings/domain/settings_service.dart:23-46` 顶层函数 `getThemeMode` / `setThemeMode` / `labelForThemeMode` 与 `:59-83` `SettingsService` 类实例方法同名同实现。生产代码（`settings_provider.dart:37/49/55/82/88/95`）全部走 `_service.*` 实例方法；grep 全 lib+test，顶层三个函数零调用方（settings_provider 在自身文件里另定义了同名顶层 `getThemeMode` 做 String→ThemeMode 映射，见 `settings_provider.dart:36-42`，与 settings_service 顶层版互不相干）。
> - 现象与取舍：REF-27 测试只锚定实例方法（`ref_27_test.dart:28-79`）；顶层版是 REF-27 提取时的残留，无测试无引用，且 `ref_27_test.dart:93-113` 的死符号静态断言只查 speed/step 八个符号、不查这三件。保留会让「同一语义两处实现」长期漂移（如未来改 label 只改一处）。
> - 修复建议：删除 settings_service.dart:23-46 顶层三函数；如需保留对外纯函数 API，由 settings_provider 或 shared/di 显式 re-export 实例方法路径。

**证据修正（用户裁决，覆盖 cr D2 原文"顶层三个函数零调用方"）**：`test/features/settings/settings_test.dart:529-574` REF-01-S1 组（5 个 test）经 `settings_domain` 别名（`import '...settings_service.dart' as settings_domain;` 见 settings_test.dart:20-21）**直接调用顶层函数** `settings_domain.getThemeMode(...)` / `settings_domain.setThemeMode(...)` / `settings_domain.labelForThemeMode(...)`——顶层版**非死代码**，统一方案必须先迁测试再删/统一。

### 1.1 这一功能干什么（一句话）

把 settings_service 里同一语义实现两遍的三件函数（读主题模式 / 写主题模式 / 主题模式中文标签）收敛为**实例方法单份**，先把依赖顶层版（`settings_domain` 别名调用）的测试迁移到实例方法，再删除顶层版——彻底消除"同语义双实现"的漂移面。

### 1.2 用户期望的场景

| ID | 你看到的样子 | 期望行为 |
|----|----|----|
| U1 | 在设置页切换主题（跟随系统 / 亮色 / 暗色） | 结果与修复前完全一致，主题照常持久化并在重启后保留 |
| U2 | 设置页显示主题选项的中文标签 | "跟随系统 / 亮色 / 暗色"文案逐字不变 |
| U3 | 开发侧：修改主题标签文案 | 只改一处（实例方法），不会出现改一处漏一处 |
| U4 | 跑测试 | 原引用顶层版/实例方法的测试全部照常通过 |

---

## §2 已实现的功能骨架（代码锚点）

### 2.1 文件与分层

| 层 | 文件 | 行数 | 角色 |
|---|---|---|---|
| Domain | `lib/features/settings/domain/settings_service.dart` | 97 | SettingsService 类 + 顶层三函数（双份实现主体） |
| Provider | `lib/features/settings/settings_provider.dart` | 121 | 经 `_service.*` 实例方法桥接；另有同名顶层 `getThemeMode` 做 String→ThemeMode 映射（:36-42） |
| Shared-DI | `lib/shared/di/providers.dart` | 250 | re-export settings_provider 的 getThemeMode/setThemeMode/labelForThemeMode（:186-203，ThemeMode 版） |
| 测试 | `test/features/settings/settings_test.dart` | 1323 | REF-01-S1 组（:528-575）用 `settings_domain.` 别名调顶层函数 |
| 测试 | `test/features/settings/ref_27_test.dart` | 159 | 实例方法锚定（`const service = SettingsService()`，:18） |

### 2.2 关键 Provider 表

| Provider 名 | 类型 | 实现位置 | 用途 |
|---|---|---|---|
| themeModeProvider | Provider\<ThemeMode\> | settings_provider.dart:58-61 | 读取当前主题（经 getThemeMode 映射） |
| setThemeModeProvider | Provider\<void Function(ThemeMode)\> | settings_provider.dart:65-72 | 写入主题 + invalidate |
| rememberSpeedProvider | Provider\<bool\> | settings_provider.dart:86-89 | 经 `_service.getRememberSpeed`（与本次无关） |

### 2.3 状态机图

本功能无状态机，跳过。

---

## §3 行为规约（Given-When-Then）

### 3.1 现有行为（逆抽）

- **[REF-10-S1]** settings_service.dart:23-46 顶层三函数与 :59-83 实例方法字节级同实现
  ```
  Given settings_service.dart:23-46（顶层 getThemeMode/prefs null→'system' + setThemeMode/prefs?.setString + labelForThemeMode/light→亮色 dark→暗色 默认→跟随系统）
  And :59-83（SettingsService 实例方法同名同实现）
  When 对比两组实现
  Then 函数体逐行一致，仅声明位置（顶层 vs 实例）不同
  ```
  Code evidence: `lib/features/settings/domain/settings_service.dart:23-46, 59-83`

- **[REF-10-S2]** 生产代码 settings_provider 全部走实例方法 `_service.*`
  ```
  Given settings_provider.dart:36-55 getThemeMode/setThemeMode/labelForThemeMode 三个顶层映射函数
  When 追踪调用
  Then 三处均 `_service.getThemeMode/setThemeMode/labelForThemeMode(...)`（实例方法走 SettingsService 类）
  And settings_provider 自身顶层 getThemeMode 是 String→ThemeMode 映射（返回 ThemeMode），与 settings_service 顶层版（返回 String）互不相干、互不调用
  ```
  Code evidence: `lib/features/settings/settings_provider.dart:36-55`

- **[REF-10-S3]** 测试 settings_test REF-01-S1 组经 settings_domain 别名直接调用顶层函数（证据修正点）
  ```
  Given settings_test.dart:20-21 import '.../settings_service.dart' as settings_domain
  And :530 :537 :542 :547 调 settings_domain.getThemeMode(...)
  And :555 调 settings_domain.setThemeMode(...)
  And :561 :563 :565 调 settings_domain.labelForThemeMode(...)
  When 运行该组
  Then 全部通过（当前实现锚定行为）
  ```
  Code evidence: `test/features/settings/settings_test.dart:20-21, 528-575`

- **[REF-10-S4]** ref_27_test 只锚定实例方法（`const service = SettingsService()`）
  ```
  Given ref_27_test.dart:18 const service = SettingsService()
  And :28-79 全部 service.getThemeMode / service.setThemeMode / service.labelForThemeMode
  When 运行 ref_27_test
  Then 通过（实例方法行为锚定）
  ```
  Code evidence: `test/features/settings/ref_27_test.dart:18, 28-79`

### 3.2 修改方案（status: new）

设计裁决：**统一到实例方法**，删除顶层三函数。理由：
- 生产侧（settings_provider）已全部走实例方法 → 实例是生产唯一真理源；
- 顶层版仅被 settings_test REF-01-S1 组测试引用（证据修正），迁移测试后即无任何引用；
- 保留顶层版会让「同语义双实现」继续漂移（未来改 label 两处不同步）；
- 未来需对外纯函数 API 时，可经 settings_provider / shared/di 显式 re-export（现 shared/di:186-203 已 re-export settings_provider 的 ThemeMode 版，不冲突）。

**修改顺序严格：先迁移 settings_test REF-01-S1 组为实例方法调用 → 再删顶层三函数。**（先删会导致 settings_test 编译失败，dev-exe 门禁红。）

| 边界情况 | 裁决 |
|---|---|
| settings_test REF-01-S1 组用 `settings_domain.*` 调过的三件 | 迁移为 `settings_domain.SettingsService().getThemeMode(...)` 同结构实例调用（const 构造），断言相等性、null prefs、存储读写、标签映射逐字保留 |
| settings_test 其它组（REF-01-S2 起）用 settings_provider 的 getThemeMode | 不动（那是 settings_provider 顶层 String→ThemeMode 映射，非 settings_service 文件内容） |
| ref_27_test | 不动（已是实例方法锚定） |
| shared/di re-export | 不动（re-export 的是 settings_provider 的 ThemeMode 版 getThemeMode/setThemeMode/labelForThemeMode，settings_service 删除顶层版不影响） |
| settings_provider.dart 顶层同名 getThemeMode（:36-42） | 保留（职责不同，已在 S2 说明） |
| 删除后 `_themeModeKey` / `_rememberSpeedKey` 常量 | 保留（实例方法仍用） |

- **[REF-10-S5]** 迁移 settings_test REF-01-S1 组：顶层函数调用 → 实例方法调用 （status: new）
  ```
  Given settings_test.dart:528-575 REF-01-S1 组 5 个 test
  When 把每个 `settings_domain.getThemeMode(...)` / `settings_domain.setThemeMode(...)` / `settings_domain.labelForThemeMode(...)`
     改为 `settings_domain.SettingsService().getThemeMode(...)`（同结构，类构造为 const）
  Then 断言零改动（prefs null → 'system'；空存 → 'system'；'dark'/'light' 存储 → 对应 String；setThemeMode 后 getString('theme_mode') == 'dark'；labelForThemeMode light/发现/暗色/跟随系统；未知/空字符串回退跟随系统）
  And 该组在顶层函数仍存在时即全绿（先迁测试，跑绿）
  否定断言:
    - 断言值/字符串字面量不得改动（'system'/'light'/'dark'/'亮色'/'暗色'/'跟随系统' 逐字保留）
    - 不新增任何 fixture / 不改变 mock 初始值（SharedPreferences.setMockInitialValues({}) 或各 test 已有行为不变）
  ```
  修改点：`test/features/settings/settings_test.dart:529-574`——每组调用前先取 `final settings_service = const settings_domain.SettingsService();`，然后替换三件调用。**dev-exe 必须在此步后先跑 `flutter test test/features/settings/settings_test.dart` 确认 PASS 再进 S6。**

- **[REF-10-S6]** 删除 settings_service.dart 顶层三函数（:23-46）及相关注释 （status: new）
  ```
  Given settings_test REF-01-S1 组已全量迁移到实例方法（S5 完成且绿）
  When 从 settings_service.dart 删除 :23-46 顶层 getThemeMode / setThemeMode / labelForThemeMode 及各自 doc 注释
  Then 实例方法 :59-83 保留（生产 + ref_27_test + 新迁移测试唯一实现）
  And settings_test.dart 全文件、ref_27_test.dart 全绿
  否定断言:
    - settings_service.dart 不得再出现顶层函数形态的三件（源码 grep：`^String getThemeMode` / `^void setThemeMode` / `^String labelForThemeMode` 零命中；但实例方法 `String getThemeMode(SharedPreferences?` 等 class 内方法必须仍在）
    - ref_27_test:143-157 静态断言"settings_service 保留 getThemeMode/setThemeMode/labelForThemeMode"仍含（查的是 class 内成员）——dev-exe 按 grep 精确判定不得误删类方法
    - settings_provider.dart:36-55 零改动
    - shared/di/providers.dart:186-203 re-export 不改（settings_service 删除不影响）
  ```
  修改点：`lib/features/settings/domain/settings_service.dart`——删 :23-46（顶层函数 + 注释），文件顶部注释同步说明（如有提到顶层 API 的内容一并清理）。

---

## §4 不变量

- **[REF-10-INV1]** settings_service.dart 主题三件语义（读/写/标签）只允许存在一份实现，且为 SettingsService 实例方法
  证据：settings_service.dart:59-83（S5/S6 后唯一实现）。

- **[REF-10-INV2]** 主题存取 key 'theme_mode' / 标签映射（light→亮色、dark→暗色、其余→跟随系统）语义固定
  证据：settings_service.dart:18（`_themeModeKey = 'theme_mode'`）+ :74-83（label 映射，S6 后移动至实例方法内不变量保持）；ref_27_test:28-79 锚定。

- **[REF-10-INV3]** settings_provider 顶层 getThemeMode（String→ThemeMode 映射）与 settings_service 顶层版职责独立，删除后者不影响前者
  证据：settings_provider.dart:36-42（映射用 `ThemeMode.values...firstWhere`）+ shared/di:186-203 re-export。

---

## §5 测试规约

### 5.1 现有测试清单

| 测试文件 | 覆盖的 Scenario / INV | 备注 |
|---|---|---|
| test/features/settings/settings_test.dart:528-575 | REF-10-S3、S5、INV2 | REF-01-S1 组待迁移实例方法 |
| test/features/settings/ref_27_test.dart:18,28-79 | REF-10-S4、S6、INV1、INV2 | 实例方法锚定，不动 |
| test/features/settings/settings_test.dart（REF-01-S2 组 :581 起） | REF-10-INV3 | settings_provider ThemeMode 映射锚定，不动 |

### 5.2 测试 ID 派生清单（dev-exe 派发测试 Agent 用）

```
REF-10-S1 … S6        # Scenario（S1~S4 现状锚定，S5~S6 修改目标）
REF-10-INV1 … INV3    # 不变量
```

dev-exe 要求：S5（迁移后的 REF-01-S1 组转实例断言）与 S6（删除顶层后仍绿 + 死符号静态断言）由 §5.4 门禁文件覆盖；S1~S4 / INV1~3 由 settings_test / ref_27_test 覆盖。

### 5.3 测试覆盖盲点（dev-plan 写本文档时识别）

| 未覆盖 ID | 现状 | 应补偿方式 |
|---|---|---|
| REF-10-S6 死符号断言 | ref_27_test:93-113 只查 speed/step 八个符号，不查主题顶层三件 | §5.4 门禁文件补"顶层形态零命中 + 实例形态存在"双态断言 |

### 5.4 测试文件位置（spec-scan --gate 硬校验）

命名防撞已核：`test/features/settings/` 现有 ref_27_test / settings_test / bug_bug28 / set_01 / log_viewer，无 ref_10 前缀文件。新建：

`test/features/settings/ref_10_unify_test.dart`（静态源扫描 + 行为断言，模型 ref_27_test.dart 的 File 读源模式）：

| 测试文件 | 覆盖 ID | 说明 |
|---|---|---|
| test/features/settings/ref_10_unify_test.dart | REF-10-S5、S6、INV1、INV3 | ①读 settings_service.dart 源，断言 `String getThemeMode(SharedPreferences? prefs)`（顶层形态）与 `void setThemeMode` / `String labelForThemeMode` 各零命中；同时断言 `String getThemeMode(SharedPreferences? prefs) {` 与 `void setThemeMode` / `String labelForThemeMode` 作为 class 方法仍在（实例形态）；②断言 settings_provider.dart:36-55 三件映射仍存在 |
| test/features/settings/settings_test.dart | REF-10-S5 迁移后组、INV2 | 既有文件，REF-01-S1 组改实例方法调用，全组绿 |
| test/features/settings/ref_27_test.dart | REF-10-S4、S6、INV1、INV2 | 既有文件，断言保持 |

---

## §6 算法样例

本功能为文件的删除/测试迁移，无纯函数算法样例，跳过。

---

## §7 跨模块影响

用 `cross-imports.sh impact lib/features/settings/domain/settings_service.dart` 实测（2026-08-16）：

`target → importer_area → file:line`:
- `lib/features/settings/domain/settings_service.dart` → settings → `settings_provider.dart`

| 其它 feature | 影响点 | 影响条件 | 需要补的回归断言 |
|---|---|---|---|
| Settings（settings_provider.dart） | 经 `_service.*` 实例方法消费主题/remember-speed | settings_service 只删顶层版，实例 API 不动 | settings_test.dart 全文件绿 + ref_27_test 绿 |
| shared/di（providers.dart:186-203） | re-export settings_provider 的 getThemeMode/setThemeMode/labelForThemeMode（ThemeMode 版） | 不依赖 settings_service 顶层版 | 既有引用 shared/di 的设置测试（bug_bug28 等）绿 |
| 测试 settings_test.dart REF-01-S1 组 | 唯一引用顶层版的地方，先迁移（顺序铁律） | 顶层版删除后编译依赖消除 | S5 先绿，S6 后全绿 |

---

## §8 平台特性与手动 QA

设计前已核对 `docs/dev/platform-pitfalls.md`：本功能为纯 Dart 域层文件删除 + 测试迁移，不触及 P1~P17 任一条（不涉 audio_service / 生命周期 / Provider 状态机 / 平台通道 / 超时分层）。

**真机风险列**：无——settings_service 读写 SharedPreferences 的行为在 mock prefs 下完整可测，本修改仅删冗余实现与迁移测试，不改变任何运行时可观测行为。主题切换/持久化全部可在 `flutter test` 验证。

本功能不涉及平台原生特性，全部可在 `flutter test` 中验证 → `manual_qa_required = false`。

---

## §9 dev-status.json 条目对照

```json
"REF-10": {
  "spec_file": "docs/features/REF-10.md",
  "spec_anchored_files": [
    "lib/features/settings/domain/settings_service.dart",
    "lib/features/settings/settings_provider.dart",
    "test/features/settings/settings_test.dart",
    "test/features/settings/ref_27_test.dart",
    "lib/shared/di/providers.dart"
  ],
  "scenarios": ["REF-10-S1", "REF-10-S2", "REF-10-S3", "REF-10-S4", "REF-10-S5", "REF-10-S6"],
  "invariants": ["REF-10-INV1", "REF-10-INV2", "REF-10-INV3"],
  "algorithms": [],
  "manual_qa_required": false,
  "user_acceptance_text": "见 §1.2"
}
```