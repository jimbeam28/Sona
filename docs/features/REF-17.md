# REF-17 — Provider 层平台包直引收敛（组合根豁免显式化 + 异常类型上提契约层）

```yaml
id: REF-17
name: Provider 层平台包直引收敛——硬约束 §0.3 组合根豁免显式化、LastConnectionException 上提、门禁盲区封堵
priority: P2
status: active
created_at: 2026-08-22
last_updated: 2026-08-22
spec_anchored_files:
  - lib/features/player/player_provider.dart
  - lib/features/connection/connection_provider.dart
  - lib/core/contracts/database_contract.dart
cross_module_impacts: [PLY, CON]
manual_qa_required: false
```

---

## §1 用户视角

### 1.0 原始需求（来源逐字记录）

> 来源：docs/cr/cr-20260822-2051.md D1（DESIGN/Major，2026-08-22 用户裁决"修"，转需求流程）。
>
> "Provider 层直引平台包——硬约束 §0.3 字面违规，机械门禁存在盲区。`lib/features/player/player_provider.dart:8` — `import 'package:just_audio/just_audio.dart';`；`lib/features/connection/connection_provider.dart:11,34-37` — flutter_secure_storage 直引（组合根适配器装配点）；`:15` 直引 DAO 实现文件（LastConnectionException 定义在 connection_dao.dart 而非 contracts，迫使跨层 import）。CLAUDE.md §0.3：'Domain/Provider 不得直接用 just_audio / audio_service / sqflite / flutter_secure_storage'；arch-baseline.txt 为空（非登记存量债）；cross-imports.sh 四检查项均不覆盖 Provider 层平台包 import——门禁盲区。"
>
> 处置裁决：修。最小路径 = 改 import 来源 + 上提 LastConnectionException 至 contracts。

### 1.2 用户期望的场景

| ID | 你看到的样子 | 期望行为 |
|----|----|----|
| U1 | 阅读架构约束文档 | 明确知道哪两处是合法的"装配点"（在那里 new 具体类是被允许的），其余位置一律走契约接口 |
| U2 | 想知道连接删除守卫异常定义在哪 | 打开契约层文件就能找到，不需要翻数据层实现文件 |
| U3 | 后续有人在 Provider 层新加一个平台包直引 | 跑架构门禁脚本立刻报错，而不是静默通过 |

---

## §2 已实现骨架（逆抽锚点）

| 层 | 文件 | 角色 |
|---|---|---|
| Contract | lib/core/contracts/audio_player_contract.dart:15 | PlayerState/ProcessingState 的合法 re-export 桥 |
| Contract | lib/core/contracts/database_contract.dart | IConnectionDao 等接口所在；LastConnectionException 目标迁入地 |
| Provider | lib/features/player/player_provider.dart:8,:53-57,:285,:317 | just_audio import：AudioPlayer 构造（组合根）+ ProcessingState 引用 |
| Provider | lib/features/connection/connection_provider.dart:11,:15,:34-55 | flutter_secure_storage import（Adapter 装配点）；DAO 实现文件 import（**修订（dev-exe round-1，2026-08-23）**：该 import 不止为捕异常 :383，还承担 :24 组合根构造 `ConnectionDao()`——S2③"删除 :15"不可整行删；落地为 `show ConnectionDao` 收窄 + 注释说明唯一用途） |
| 门禁 | .claude/plugins/sona-dev/scripts/cross-imports.sh | 四检查项不含 provider 层平台包扫描；arch-baseline.txt 为空白抑制清单 |

---

## §3 行为规约

- **[REF-17-S1]** CLAUDE.md §0.3 补组合根豁免条款 （`status: new`）
  ```
  Given 硬约束第 3 条现行文字"Domain/Provider 不得直接用 just_audio / audio_service / sqflite / flutter_secure_storage"
  When 按本 spec 修订文档
  Then 追加豁免条款，精确措辞：
    "组合根装配点豁免：audioPlayerProvider（player_provider.dart，构造 just_audio
    AudioPlayer 实例的唯一合法点）与 FlutterSecureStorageAdapter
    （connection_provider.dart，包装 flutter_secure_storage 的唯一合法点）。
    两处之外的 Domain/Provider 层类型引用一律经 core/contracts/。"
  否定断言:
    - 不得放宽对 Domain 层的既有零平台依赖要求（domain-flutter 检查语义不变）
  ```
  Code evidence: `lib/features/player/player_provider.dart:53-57`、`lib/features/connection/connection_provider.dart:34-55`
- **[REF-17-S2]** LastConnectionException 定义上提至 database_contract.dart，DAO 实现文件不再被 feature 层因异常而引用 （`status: new`）
  ```
  Given 异常类现定义于 connection_dao.dart（connection_provider.dart:15 因此直连实现文件）
  When 上提完成
  Then ① 类体移至 core/contracts/database_contract.dart；
       ② connection_dao.dart 改从 contracts 导入并保留
          `export '../../core/contracts/database_contract.dart' show LastConnectionException;`
          （既有测试经 dao 文件导入该异常，re-export 保证零改动——con_06/bug_bug10 等）；
       ③ connection_provider.dart 删除 :15 的 DAO import 行
          （异常经既有 :13 database_contract import 获得）
  否定断言:
    - 异常的运行时行为不变（type identical，catch 分支全部照旧命中）
    - connection_dao.dart 对外导出面不得缩小（re-export 兜底）
    - 不改动任何测试文件
  ```
  Code evidence: `lib/core/database/dao/connection_dao.dart:119-121`（throw 点）、`lib/features/connection/connection_provider.dart:15,:383`
- **[REF-17-S3]** cross-imports.sh 新增 provider-platform 扫描项并冻结现状 （`status: new`）
  ```
  Given 四检查项不覆盖 provider 层平台包 import
  When 新增检查并入 all
  Then ① 扫描 lib/features/**/*_provider*.dart 与 *_provider.dart 同族文件的
          平台包 import 行（just_audio/audio_service/sqflite/flutter_secure_storage/dio）；
       ② 白名单按 kind+file 登记 arch-baseline.txt：
          provider-platform  lib/features/player/player_provider.dart   # 组合根 AudioPlayer 构造（S1 豁免）
          provider-platform  lib/features/connection/connection_provider.dart  # Adapter 装配点（S1 豁免）
       ③ 基线外新增违规 exit 1（复用现有抑制机制，只减不增规则不变）
  否定断言:
    - domain-flutter / feature-isolation / secret-logs / core-feature 四既有检查行为不得变化
  ```
  Code evidence: `.claude/plugins/sona-dev/scripts/cross-imports.sh`（现有四检查结构）、`docs/dev/arch-baseline.txt:4-6`（kind+file 抑制语义）

---

## §4 不变量

- **[REF-17-INV1]** 装配点之外，lib/features 下任意 provider 文件不得出现平台包直接 import；违者由 cross-imports.sh provider-platform 检查阻断
  证据：S3 白名单机制 + `docs/dev/arch-baseline.txt` 只减不增规则

---

## §5 测试规约

### 5.1 现有测试清单

| 测试文件 | 覆盖 | 备注 |
|---|---|---|
| test/features/connection/con_06_test.dart 等 | 经 dao re-export 捕获异常 | S2 落地后必须全绿（零改动验证兼容性） |

### 5.2 测试 ID 派生清单

```
REF-17-S1 … S3        # S1 为文档修订无独立测试；S2 由既有异常测试全绿锚定；S3 由脚本退出码锚定
REF-17-INV1           # dev-exe 以 cross-imports.sh all EXIT=0 锚定
```

### 5.3 测试覆盖盲点

| 未覆盖 ID | 现状 | 应补偿方式 |
|---|---|---|
| 无 | S2 兼容性由全量 con_*/bug_bug10* 回归兜底；S3 属脚本行为以退出码为证 | — |

### 5.4 测试文件位置（spec-scan --gate 硬校验）

| 测试文件 | 覆盖 ID | 说明 |
|---|---|---|
| test/features/connection/con_06_test.dart | REF-17-S2 | **dev-exe round-1 补登（2026-08-23）**：--gate 要求实体路径。本文件即 §5.1 所述"经 dao re-export 捕获异常"的既有回归锚，零改动全绿即证 S2 兼容性 |
| test/features/connection/bug_bug10_repro_test.dart | REF-17-S2 | 同上（delete 守卫路径 catch LastConnectionException 的复现测试） |

> S1（文档措辞）由 cr-dimensions.md §0.3 豁免条款承载；S3 与 INV1 由 `bash cross-imports.sh all` EXIT=0 承载——均非 dart 测试，不列入本表。

---

## §6 算法样例

不涉及纯函数算法，跳过。

---

## §7 跨模块影响

impact 反查（2026-08-22）：player_provider ← main/onboarding/home；connection_provider ← connection 三 screen + shared/di。

| 其它 feature | 影响点 | 影响条件 | 回归断言要求 |
|---|---|---|---|
| CON | delete 流程 catch LastConnectionException | S2 仅移动定义位置，type identical | con_06 / bug_bug10 全绿即证 |
| PLY | player_provider import 面 | S1/S3 不改运行时行为 | ply 全量绿 |

**dev-exe round-1 补登记（2026-08-23）**：修改点 3 原文"删除 :15 行"不可行——该 import 同时提供 :24 组合根构造所需的 ConnectionDao 具体类。落地改为 `import ... show ConnectionDao;` 收窄（异常类型不再经实现文件获得，S2 语义达成；组合根构造用途与 S1 豁免同类）。其余修改点照单执行。

**修改点（弱模型照单执行）**：
1. `lib/core/contracts/database_contract.dart` — 文件末尾追加 LastConnectionException 类定义（从 connection_dao.dart 原样搬移类声明与文档注释，const 构造保留）。
2. `lib/core/database/dao/connection_dao.dart` — 删除本地类定义；顶部加 `import '../../contracts/database_contract.dart';` 与 `export '../../contracts/database_contract.dart' show LastConnectionException;`。
3. `lib/features/connection/connection_provider.dart` — 删除 `:15` 行 `import '../../core/database/dao/connection_dao.dart';`。
4. `CLAUDE.md` §0.3 — 按 S1 措辞追加豁免条款。
5. `.claude/plugins/sona-dev/scripts/cross-imports.sh` — 新增 provider-platform 检查函数并入 all；`docs/dev/arch-baseline.txt` 按登记格式加两行白名单。
6. 全量回归：`bash cross-imports.sh all` EXIT=0 + `flutter analyze --no-fatal-infos` 0 warning + `flutter test` 全绿。

---

## §8 平台特性与手动 QA

核对踩坑库：P15（框架版本回调签名）与本 spec 无交集；不触碰任何平台通道运行时行为。

本功能不涉及平台原生特性，全部可在静态检查与 `flutter test` 中验证。

---

## §9 dev-status.json 条目对照

```json
"REF-17": {
  "spec_file": "docs/features/REF-17.md",
  "spec_anchored_files": [
    "lib/features/player/player_provider.dart",
    "lib/features/connection/connection_provider.dart",
    "lib/core/contracts/database_contract.dart"
  ],
  "scenarios": ["REF-17-S1", "REF-17-S2", "REF-17-S3"],
  "invariants": ["REF-17-INV1"],
  "algorithms": [],
  "manual_qa_required": false,
  "user_acceptance_text": "见 §1.2"
}
```
