# REF-09 — 数据层反向依赖 feature 解耦（progress_policy 下沉 core + audio_handler 兼容层 import 裁决）

## §0 头部元数据

```yaml
id: REF-09
name: 数据层反向依赖 feature 解耦（core→feature 零依赖）
priority: P1
status: active
created_at: 2026-08-16
last_updated: 2026-08-16
spec_anchored_files:
  - lib/core/database/dao/progress_dao.dart
  - lib/features/progress/domain/progress_policy.dart
  - lib/core/services/audio_handler.dart
  - lib/features/player/domain/media_control.dart
  - .claude/plugins/sona-dev/scripts/cross-imports.sh
  - docs/dev/scripts/coverage-check.sh     # 新文件 lib/shared/media_title.dart 与 lib/core/contracts/progress_policy.dart 由 dev-exe 创建
cross_module_impacts: [PRG, PLY, Core]
manual_qa_required: true   # audio_handler（audio_service 原生层）被触碰，通知栏标题渲染需真机回归
```

---

## §1 用户视角

### 1.0 原始需求（用户原话逐字记录）

来源：`docs/cr/cr-20260816-0805-progress-timer-settings.md` D1（cr 复核分流，用户裁决"修"→ 转 REF 需求流程，无 repro 门禁要求）：

> #### D1. 数据层反向依赖 feature：`core/database/dao/progress_dao.dart` import `features/progress/domain/progress_policy.dart`
>
> - 类型：DESIGN / 严重度：Major / 维度：架构一致性
> - 证据：`lib/core/database/dao/progress_dao.dart:15`
>   ```dart
>   import '../../../features/progress/domain/progress_policy.dart'
>       as progress_policy;
>   ```
>   同类：`lib/core/services/audio_handler.dart:24` `import '../../features/player/media_control_model.dart' hide MediaAction;`
> - 现象与取舍：CLAUDE.md 分层「UI → Provider → Domain → Contract → Data」只规定 feature 依赖 core，未声明 core 不得依赖 feature，而机械门禁 `cross-imports.sh` 只查 feature→feature / domain→flutter / 敏感日志三个方向，**core→feature 方向无任何门禁覆盖**（本次手工 grep `lib/core/` 全目录仅此两处）。progress_policy 作为纯函数放在 feature domain 而数据层消费它，方向倒置：progress 模块拆分/迁移会直接破坏 core/database，且 arch-baseline.txt 空表无法登记此类债务。取舍待用户裁决：把 policy 下沉到 `core/contracts` 或 `core/database/` 同级（推荐），或接受现状并为 cross-imports.sh 补一个 core→feature 反向依赖检查方向。
> - 修复建议：移动 `progress_policy.dart` 到 core 层（core/contracts 或 core/database），DAO 与 feature 侧 import 同步改；为 cross-imports.sh 增加 core→feature 方向检查，audio_handler.dart:24 的兼容层 import 一并裁决。

用户裁决：**修**——core 层零 feature 依赖，策略函数下沉 core/contracts，为 cross-imports.sh 补 core→feature 方向检查，audio_handler 兼容层 import 一并解耦。

### 1.1 这一功能干什么（一句话）

消除数据层（core）反向依赖业务模块（feature）的两处 import，把被数据层消费的纯函数策略与标题提取函数落实到共享/契约层，并给机械门禁补上 core→feature 防回潮方向——保证未来拆分 progress 或 player 模块不会连带击穿 core/database 与 core/services。

### 1.2 用户期望的场景

| ID | 你看到的样子 | 期望行为 |
|----|----|----|
| U1 | 运行 App（播放、进度记忆、通知栏标题） | 行为与修复前完全一致：自动保存/清除播放进度、锁屏通知栏显示歌曲名等都不变 |
| U2 | 开发侧：把 progress 模块整体迁移/拆分 | 不再连带修改 core/database/dao（progress_dao 不再依赖 progress feature 的模块内部文件） |
| U3 | 开发侧：新增 core 层文件 | 机械门禁能拦住"core 又反向 import feature"的新违规 |
| U4 | 锁屏/通知栏看一眼歌曲标题 | 标题取的是文件名去扩展名，与修复前逐字符一致 |

---

## §2 已实现的功能骨架（代码锚点）

### 2.1 文件与分层

| 层 | 文件 | 行数 | 角色 |
|---|---|---|---|
| Core-Contract | `lib/core/contracts/database_contract.dart` | — | IProgressDao 接口（progress_dao 实现，政策函数拟下沉的同目录） |
| Core-Dao | `lib/core/database/dao/progress_dao.dart` | 258 | ProgressDao：upsert/delete 委托 `progress_policy.shouldSave/shouldClear`（:251-257） |
| Core-Service | `lib/core/services/audio_handler.dart` | 346 | NasAudioHandler：通知栏标题调 `extractTitleFromPath`（:171），import 兼容层（:24） |
| Feature-Domain | `lib/features/progress/domain/progress_policy.dart` | 30 | shouldSave/shouldClear 纯函数（零 Flutter 依赖），拟迁 core/contracts |
| Feature-Domain | `lib/features/player/domain/media_control.dart` | 104 | 纯函数集：extractTitleFromPath（:78-83）等，拟只迁 extractTitleFromPath 到 shared |
| Feature-兼容层 | `lib/features/player/media_control_model.dart` | 91 | re-export domain/media_control + TrackMetadata（:16 导入，:19 export） |
| 测试 | `test/features/progress/ref_24_test.dart` | — | progress_policy 纯函数测试（:8 直接 import feature 路径） |
| 测试 | `test/features/progress/bug_bug20_repro_test.dart` | — | 动态清除窗口测试（:18 直接 import feature 路径） |
| 测试 | `test/features/player/ref_12_test.dart` | — | extractTitleFromPath/mapHeadphoneAction/formatDuration 测试 |
| 测试 | `test/features/player/ply_04_test.dart` | — | 通知栏标题/TrackMetadata 测试 |

### 2.2 关键 Provider 表

本功能不涉及 provider，跳过。

### 2.3 状态机图

本功能无状态机，跳过。

---

## §3 行为规约（Given-When-Then）

### 3.1 现有行为（逆抽）

- **[REF-09-S1]** progress_dao 版权状：core 反向 import feature（现行违规态）
  ```
  Given 当前 lib/core/database/dao/progress_dao.dart:15-16
  Then import features/progress/domain/progress_policy.dart as progress_policy
  And upsert 里 :113 调 progress_policy.shouldSave(positionMs)、:116 调 progress_policy.shouldClear(positionMs, durationMs)
  And 静态委托 :251-257 转发 shouldSave/shouldClear
  ```
  Code evidence: `lib/core/database/dao/progress_dao.dart:15-16, 113, 116, 251-257`

- **[REF-09-S2]** audio_handler 版权状：core 反向 import feature 兼容层（现行违规态）
  ```
  Given lib/core/services/audio_handler.dart:24
  Then import features/player/media_control_model.dart hide MediaAction
  And 仅 :171 用 extractTitleFromPath(filePath) 生成通知栏标题
  And MediaAction 符号与 audio_service（:143 MediaAction.seek 等）重名才 hide
  ```
  Code evidence: `lib/core/services/audio_handler.dart:24, 143, 171`

- **[REF-09-S3]** progress_policy 现有语义（迁移不改一字节行为）
  ```
  Given features/progress/domain/progress_policy.dart
  Then shouldSave(positionMs) = positionMs >= 5000（:11）
  And shouldClear(positionMs, durationMs)：durationMs==null → false；durationMs<=10000 → false；window=clamp(ceil(dur*10%),1000,10000)；positionMs > dur-window → true（:25-29）
  ```
  Code evidence: `lib/features/progress/domain/progress_policy.dart:11, 25-29`

- **[REF-09-S4]** extractTitleFromPath 现有语义（迁移不改一字节行为）
  ```
  Given features/player/domain/media_control.dart:78-83
  Then split('/').last 取最后一段；lastIndexOf('.')<=0 → 原名；否则去最后一个扩展名
  ```
  Code evidence: `lib/features/player/domain/media_control.dart:78-83`

- **[REF-09-S5]** cross-imports.sh 现有方向仅三个，core→feature 零门禁
  ```
  Given .claude/plugins/sona-dev/scripts/cross-imports.sh
  Then check_domain_flutter（:42-54）/ check_feature_isolation（:59-93，仅 features→features）/ check_secret_logs（:96-108）
  And main() all 只并这三个（:147-151）
  ```
  Code evidence: `.claude/plugins/sona-dev/scripts/cross-imports.sh:59-93, 147-151`

- **[REF-09-S6]** coverage-check.sh DEFAULT_CRITICAL 登记了 feature 路径的 progress_policy
  ```
  Given docs/dev/scripts/coverage-check.sh:30
  Then critical 列表含 "lib/features/progress/domain/progress_policy.dart"
  ```
  Code evidence: `docs/dev/scripts/coverage-check.sh:30`（进度 policy 覆盖率必守 ≥90%，迁移后路径必须同步，否则 cov-gate 查不到新文件）

### 3.2 修改方案（status: new）

设计裁决（用户裁决"修"）：

1. **progress_policy.dart 下沉到 `lib/core/contracts/progress_policy.dart`**（与 IProgressDao 同级；决策：选 core/contracts 而非 core/database，因其本质是"何时持久化的决策契约"，属契约层语义；且用户裁决明确给 core/contracts 优先）。内容逐字节搬运（头部注释路径描述同步改写）。
2. **extractTitleFromPath 下沉到 `lib/shared/media_title.dart`**（新文件，纯函数）。决策理由：它是 path→title 的纯字符串工具，与 webdav_paths（shared 先例，progress_dao:14 也 import 它）性质一致；formatDuration/mapHeadphoneAction/HeadphoneAction/MediaAction 仍留在 player 领域（player 专属语义），不整体迁移 media_control.dart。
3. **features/player/domain/media_control.dart 改为 re-export** shared 的 extractTitleFromPath（`export '../../../shared/media_title.dart' show extractTitleFromPath;`），保证 media_control_model / ply_04_test / ref_12_test / progress_slider 等既有 feature 消费者 import 路径零改动。
4. **audio_handler.dart:24 改为直接 import shared**（`import '../../../shared/media_title.dart';`），删除 home Resolution feature 兼容层 import。
5. **cross-imports.sh 新增 `core-feature` 方向检查**（扫描 lib/core/** import 解析到 lib/features/** 即违规），并入 `all`。
6. **coverage-check.sh:30 critical 路径同步改** `lib/core/contracts/progress_policy.dart`（保持进度 policy 覆盖率守阈）。

| 边界情况 | 裁决 |
|---|---|
| media_control.dart 还导出/使用 extractTitleFromPath 的既有调用方（media_control_model:19/51、ply_04/ref_12 测试、player_provider:38 export formatDuration 不涉） | extractTitleFromPath 经 re-export 保路径不变；其余符号原样留在 media_control.dart |
| audio_handler 需要其他 media_control_model 符号？ | 不需要（S2 已证实仅 extractTitleFromPath）；`hide MediaAction` 随 import 删除一并消失 |
| progress_policy 在 test 的 import 路径（ref_24_test:8、bug_bug20_repro_test:18） | 同步改到 `core/contracts/progress_policy.dart` |
| lib 内是否还有别的 core→feature import？ | 勘察已排除（grep `import.*features/` 仅这两处）；RE-勘察在 dev-exe 实现后跑 `cross-imports.sh core-feature` 全绿确认 |
| shared/media_title.dart 是否被 feature 反复 import 违反隔离？ | 不违反——feature→shared 是被允许方向（progress_dao 已 import shared/webdav_paths） |
| 新增文件需要新增 coverage critical 登记？ | media_title.dart 建议 dev-exe 顺带补入 coverage-check.sh DEFAULT_CRITICAL（可选，不设硬性） |

- **[REF-09-S7]** progress_policy 迁至 core/contracts，DAO 委托语义逐字节不变 （status: new）
  ```
  Given lib/core/contracts/progress_policy.dart 存在，内容与旧 features 路径完全一致
  And progress_dao.dart:15-16 import 改为 core/contracts/progress_policy.dart（保留 as progress_policy）
  When dev-exe 跑 progress 现有测试全集
  Then ref_24_test 与 bug_bug20_repro_test import 路径已同步改且全绿
  And prg_test（PRG-T01~T28）/ ref_25_test 全绿
  否定断言:
    - progress_dao.dart 不得再出现 `features/progress` 字样的任何 import（grep 断言）
    - shouldSave/shouldClear 的函数体与阈值（5000 / 10000 / clamp(10000,1000)）不得改一字节
    - lib/core 下除现状外不得新增新的 core→feature import
  ```
  修改点：`lib/core/contracts/progress_policy.dart`（新增=旧文件整体搬运，头部注释路径描述改为 `lib/core/contracts/progress_policy.dart`）；`lib/core/database/dao/progress_dao.dart:15-16` import 改 `'../../contracts/progress_policy.dart'`；`lib/features/progress/domain/progress_policy.dart` 删除；`test/features/progress/ref_24_test.dart:8`、`test/features/progress/bug_bug20_repro_test.dart:18` import 改 `package:nas_audio_player/core/contracts/progress_policy.dart`；`docs/dev/scripts/coverage-check.sh:30` 路径改 `lib/core/contracts/progress_policy.dart`。

- **[REF-09-S8]** extractTitleFromPath 下沉 shared，audio_handler 直连 shared，通知栏标题逐字符不变 （status: new）
  ```
  Given lib/shared/media_title.dart 含 extractTitleFromPath（内容与 domain/media_control.dart:78-83 一致）
  And features/player/domain/media_control.dart 顶部加 export '../../../shared/media_title.dart' show extractTitleFromPath; 且删除 :78-83 本地定义
  And audio_handler.dart:24 改为 import '../../../shared/media_title.dart';
  When 通知栏标题路径 setMediaItemFromPath 被调用（BUG-04 配套 / ply_02 播放流程）
  Then title 仍为 取末段去扩展名，与迁移前逐字符一致
  否定断言:
    - lib/core/services/audio_handler.dart 不得再 import 任何 features/ 路径（grep 断言）
    - media_control_model.dart / ply_04_test / ref_12_test 的 import 与断言零改动仍全绿（re-export 保路径）
    - extractTitleFromPath 不得出现第二份实现（shared 唯一定义）
  ```
  修改点：`lib/shared/media_title.dart`（新增，函数体照抄 + 文档注释）；`lib/features/player/domain/media_control.dart`（加 export，删 :78-83 定义与小文档）；`lib/core/services/audio_handler.dart:24` import 改。

- **[REF-09-S9]** cross-imports.sh 新增 core→feature 反向检查方向 （status: new）
  ```
  Given cross-imports.sh 添加 check_core_feature()：扫描 lib/core/** 的 import 语句，解析目标路径落 lib/features/** 即 emit
  And 该检查并入 main 的 all（与 feature-isolation 同模式，Major 级）
  When dev-exe 在 REF-09 实现后运行 bash .claude/plugins/sona-dev/scripts/cross-imports.sh all
  Then 退出码 0（core-feature: clean）
  否定断言:
    - lib/core 下任何 .dart import 解析后不得落 lib/features/（新增检查生效）
    - 既有三方向（domain-flutter / feature-isolation / secret-logs）行为不变，REF-09 修改后仍全绿
  ```
  修改点：`.claude/plugins/sona-dev/scripts/cross-imports.sh` 新增 `check_core_feature()` 函数 + `case core-feature)` + 并入 `all`。实现参照 check_feature_isolation 的 import 解析逻辑（:66-82），src 扫描范围改 `lib/core/`，target 判定 `lib/features/*`。脚本自检：`check_core_feature` 空输出 echo "core-feature: clean"。

---

## §4 不变量

- **[REF-09-INV1]** lib/core/ 下任何 .dart 文件不得 import 解析到 lib/features/** 的文件
  证据：`lib/core/database/dao/progress_dao.dart:15-16`（改后）+ `lib/core/services/audio_handler.dart:24`（改后）均不再含 features 路径 + cross-imports.sh 新增检查（修改点 S9）。

- **[REF-09-INV2]** progress_policy 决策语义（shouldSave 阈值 5000、shouldClear 规则）单源常驻 core/contracts，feature 与 core 均只引用这一份
  证据：`lib/core/contracts/progress_policy.dart`（新唯一定义）；progress_dao:113/116/251-257 委托它。

- **[REF-09-INV3]** extractTitleFromPath 唯一定义在 shared，feature 侧（media_control_model / TrackMetadata.title / 通知栏）全部经 re-export 引用同一份
  证据：`lib/shared/media_title.dart`（唯一定义）；`lib/features/player/domain/media_control.dart` re-export + `media_control_model.dart:51` 复用。

---

## §5 测试规约

### 5.1 现有测试清单

| 测试文件 | 覆盖的 Scenario / INV | 备注 |
|---|---|---|
| test/features/progress/ref_24_test.dart | REF-09-S3、S7 | progress_policy 纯函数测试；import 路径需改 core/contracts，断言零改动 |
| test/features/progress/bug_bug20_repro_test.dart | REF-09-S3、S7 | import 路径需改，断言零改动 |
| test/features/player/ref_12_test.dart | REF-09-S4、S8 | extractTitleFromPath 测试；import 路径经 re-export 不变，断言零改动 |
| test/features/player/ply_04_test.dart | REF-09-S4、S8 | 通知栏标题测试；import 路径经 re-export 不变，断言零改动 |

### 5.2 测试 ID 派生清单（dev-exe 派发测试 Agent 用）

```
REF-09-S1 … S9        # Scenario（S1~S6 现状锚定，S7~S9 修改目标）
REF-09-INV1 … INV3    # 不变量
```

dev-exe 要求：S7~S9 与 INV1~INV3 由 §5.4 门禁文件覆盖；S1/S2 现状态由复测确认转化后消失（core-feature gate 全绿）；S3~S6 既有测试锚定不动。

### 5.3 测试覆盖盲点（dev-plan 写本文档时识别）

| 未覆盖 ID | 现状 | 应补偿方式 |
|---|---|---|
| REF-09-INV1（core 零 feature 依赖） | cross-imports.sh 原先不查该方向 | §5.4 门禁文件静态断言 two files 不含 features import + 全 lib/core grep |
| REF-09-INV2/INV3（单源） | 各语义已有行为测试 | §5.4 门禁文件补"唯一定义"静态断言 |

### 5.4 测试文件位置（spec-scan --gate 硬校验）

命名防撞已核：`test/core/` 现无 ref_09 前缀文件（仅 bug_13/bug_19/network/services）。新建：

`test/core/ref_09_core_feature_decouple_test.dart`（静态源扫描，模式参考 ref_27_test.dart:93-113 的 File 读源断言；纯 Dart 单测，无平台依赖）：

| 测试文件 | 覆盖 ID | 说明 |
|---|---|---|
| test/core/ref_09_core_feature_decouple_test.dart | REF-09-S7、S8、S9、INV1、INV2、INV3 | 门禁：读 progress_dao.dart / audio_handler.dart 源码断言不含 `features/` import；读 progress_policy 旧路径不存在、新路径存在；读 media_title.dart 存在且 media_control.dart 含 export 语句；读交叉目录断言唯一定义 |
| test/features/progress/ref_24_test.dart | REF-09-S3、S7 | 既有文件，import 改 core/contracts，断言保持 |
| test/features/progress/bug_bug20_repro_test.dart | REF-09-S3、S7 | 同上 |
| test/features/player/ref_12_test.dart | REF-09-S4、S8 | 既有文件，仅依赖 re-export，断言保持 |
| test/features/player/ply_04_test.dart | REF-09-S4、S8 | 既有文件，断言保持 |

---

## §6 算法样例

```
ALG [REF-09-ALG1-crossImportResolve]:
  输入: import '../../../features/progress/domain/progress_policy.dart'，源 lib/core/database/dao/progress_dao.dart
      → 期望: 解析落 lib/features/progress/domain/progress_policy.dart → core-feature 违规（S9 检查命中）
  输入: import '../../contracts/progress_policy.dart'，源 lib/core/database/dao/progress_dao.dart
      → 期望: 解析落 lib/core/contracts/progress_policy.dart → 干净           # 主流程（修复后）
  输入: import '../../../shared/media_title.dart'，源 lib/core/services/audio_handler.dart
      → 期望: 解析落 lib/shared/media_title.dart → 干净                        # 主流程（修复后）
  输入: package:flutter/... 外部包 import（lib/core/** 内）
      → 期望: 跳过（非项目内部路径）                                          # 边界
```

---

## §7 跨模块影响

用 `cross-imports.sh impact` 实测 + 手动核查引用方：

| 其它 feature / 模块 | 影响点 | 影响条件 | 需要补的回归断言 |
|---|---|---|---|
| Progress（progress_provider / progress_service / progress_dialog） | progress_service 经 IProgressDao 间接消费 policy；progress_provider 不直接 import policy | progress_policy 路径迁移 | 既有 progress 测试全集（prg/ref_24/ref_25/bug_10/bug_11/bug_13/bug_bug20/net1/test_09）全绿 |
| Player（media_control_model / ply_01~04 / ref_12_13 / progress_slider） | extractTitleFromPath 经 media_control.dart re-export，feature 消费方路径不变 | media_control.dart 加 export、删本地定义 | ply_04_test、ref_12_test 断言零改动全绿；audio_handler 通知栏标题路径经 BUG-04 配套测试/P2 锚定全绿 |
| Core（audio_handler 通知栏/锁屏标题） | audio_handler import 由 feature 兼容层改 shared 直连 | extractTitleFromPath 语义不变 | 通知栏标题渲染 MQA：真实设备锁屏/通知栏显示歌曲名（见 §8） |
| cross-imports.sh 门禁 | 新增 core-feature 方向；REF-09 实现后 all 必须 0 违规 | 全部 lib/core 不再含 features import | dev-exe 跑 `cross-imports.sh all` 退出码 0 |
| coverage-check.sh | DEFAULT_CRITICAL:30 路径改 core/contracts/progress_policy.dart | progress_policy 覆盖率仍 ≥90%（ref_24 测试未删语义） | dev-exe 跑 `coverage-check.sh check-exe` 通过 |
| docs/dev/baseline-coverage.json | critical_files 若从 DEFAULT_CRITICAL 生成则随路径同步（当前 _status=empty 基线未建立，dev-check 首轮会 refresh） | 空基线下无漂移风险 | —（下次 refresh 自动） |

---

## §8 平台特性与手动 QA

设计前已逐条核对 `docs/dev/platform-pitfalls.md`：本功能为纯 Dart 函数搬迁 + import 改向 + 门禁脚本，不涉及 P1~P17 任一播放/时序/平台行为（extractTitleFromPath 语义与调用点均为逐字符保持，audio_handler:171 调用点不改）。

**真机风险列**：

| 风险 | 近似测试方案 | 测不了 → 进 mqa-backlog |
|---|---|---|
| **audio_handler 所在文件被触碰**——通知栏/锁屏标题渲染路径若因 import 改动意外受影响（理论上 fetch_title 逐字节不变，但文件级 diff 可能引入误改） | ply_04 / ref_12 单测锚定 extractTitleFromPath 语义；audio_handler 全文件读源静态断言 import 面 | 真机项：播放一首歌锁屏/通知栏标题正确显示歌曲名（进 mqa-backlog REF-09 条目） |

涉及 `audio_handler.dart`（audio_service 原生层）→ `manual_qa_required = true`。

**MQA 追加**（dev-exe 落入 `docs/dev/mqa-backlog.md`）：
```
## REF-09 数据层反向依赖解耦（追加于 2026-08-16）
- □ 真机播放一首歌，锁屏/通知栏标题显示文件名去扩展名（extractTitleFromPath 路径回归）
- □ 播放进度 30s 后杀进程再开，恢复进度提示正常出现（progress_policy 路径回归）
```

---

## §9 dev-status.json 条目对照

```json
"REF-09": {
  "spec_file": "docs/features/REF-09.md",
  "spec_anchored_files": [
    "lib/core/database/dao/progress_dao.dart",
    "lib/features/progress/domain/progress_policy.dart",
    "lib/core/services/audio_handler.dart",
    "lib/features/player/domain/media_control.dart",
    ".claude/plugins/sona-dev/scripts/cross-imports.sh",
    "docs/dev/scripts/coverage-check.sh"
  ],
  "scenarios": ["REF-09-S1", "REF-09-S2", "REF-09-S3", "REF-09-S4", "REF-09-S5", "REF-09-S6", "REF-09-S7", "REF-09-S8", "REF-09-S9"],
  "invariants": ["REF-09-INV1", "REF-09-INV2", "REF-09-INV3"],
  "algorithms": ["REF-09-ALG1-crossImportResolve"],
  "manual_qa_required": true,
  "user_acceptance_text": "见 §1.2"
}
```