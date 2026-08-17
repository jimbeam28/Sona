# REF-15 — int_g06_lifecycle_test 8 处 addTearDown(() => container.dispose) 修正为实际调用

## §0 头部元数据

```yaml
id: REF-15
name: int_g06 8 处 addTearDown tear-off 坏形态修正（ProviderContainer 真正释放）
priority: P2
status: active
created_at: 2026-08-16
last_updated: 2026-08-16
spec_anchored_files:
  - test/features/coverage/int_g06_lifecycle_test.dart
cross_module_impacts: []                 # 纯测试代码修正，零 lib/ 影响
manual_qa_required: false                # 测试代码修正，不涉平台原生
```

---

## §1 用户视角

### 1.0 原始需求（用户原话逐字记录）

来源：`docs/cr/cr-20260816-0806-test-helpers.md` D3（cr 复核分流，用户裁决"修"→ 转 REF 需求流程）：

> #### D3. int_g06_lifecycle_test 全文件 8 处 `addTearDown(() => container.dispose)` 不生效，ProviderContainer 从不释放
> - 类型 / 严重度 / 维度：DESIGN / Minor / 正确性（测试资源生命周期）
> - 证据：`test/features/coverage/int_g06_lifecycle_test.dart:137,164,222,239,296,321,454,478`：
>   ```dart
>   addTearDown(() => container.dispose);   // 闭包返回 tear-off，dispose() 从未被调用
>   ```
>   对照：同仓库正确形态 `test/core/bug_13_repro_test.dart:233` / `test/features/browser/o3_create_queue_play_mode_test.dart:68` 用 `addTearDown(container.dispose)`。
> - 现象与取舍：container 持有的 provider 状态与订阅在测试结束后不清理；当前用例无周期性 timer 故不炸，但该错误形态已被复制 8 次，属可复现的坏样板；取舍点：是否顺手修正（低风险纯测试代码改动）。
> - 修复建议：改为 `addTearDown(container.dispose)`。

用户裁决：**修**——修复为实际调用（tear-off 直接传递形态）。

### 1.1 这一功能干什么（一句话）

修正 `int_g06_lifecycle_test.dart` 里 8 处"写了但不执行"的容器释放语句，让每个测试创建的内存容器在测试结束时被真正释放。

### 1.2 用户期望的场景

| ID | 你看到的样子 | 期望行为 |
|----|----|----|
| U1 | 测试跑完后查看这些用例创建的临时容器 | 容器被真正释放（状态与订阅清理），不再一直留在内存里 |
| U2 | 文件里出现"释放容器"的写法 | 写法是真正会执行的那一种（与项目其它 10 余处一致），不再有"复制了但不生效"的坏样板 |
| U3 | 这些用例测的内容 | 与修复前完全一致，一条断言都不变 |

---

## §2 已实现的功能骨架（代码锚点）

### 2.1 文件与分层

| 层 | 文件 | 行数 | 角色 |
|---|---|---|---|
| 测试 | `test/features/coverage/int_g06_lifecycle_test.dart` | 488 | INT-G06 生命周期集成测试：T01（前台恢复→定时器过期→暂停）、T02（进后台→存进度）、T03（定时器+切歌交互）；8 组用例创建 ProviderContainer 后 `addTearDown(() => container.dispose);`（137/164/222/239/296/321/454/478） |

### 2.2 关键 Provider 表

本功能不涉生产 Provider，跳过。

### 2.3 状态机图

无状态机，跳过。

---

## §3 行为规约（Given-When-Then）

### 3.1 现有行为（逆抽）

- **[REF-15-S1]** 现状：8 处坏形态 `addTearDown(() => container.dispose);` 编译通过但从不执行
  ```
  Given test/features/coverage/int_g06_lifecycle_test.dart 内 8 个用例
  When 每个用例创建 ProviderContainer（ProviderContainer(overrides: [...])）后执行 addTearDown
  Then addTearDown 收到的是闭包 `() => container.dispose`——闭包体是"返回 tear-off 表达式"，
       container.dispose 从未被调用
  And 由于 void Function() 可赋值给 addTearDown 的 AsyncCallback（FutureOr<void> Function()），
       编译不报错 → 错误形态静默通过
  And 容器持有的 provider 状态与订阅在用例结束后不清理（本文件用例无周期 timer 故测试不炸，
       坏形态被复制 8 次）
  ```
  Code evidence:
  - `test/features/coverage/int_g06_lifecycle_test.dart:137/164/222/239/296/321/454/478`（8 处 `addTearDown(() => container.dispose);`）
  - 对照正确形态：`test/core/bug_13_repro_test.dart:233/256`、`test/features/browser/o3_create_queue_play_mode_test.dart:68`、`test/features/browser/bug_bug31_repro_test.dart:99/149/179`、`test/features/browser/bug_06_repro_test.dart:178`、`test/features/browser/brw_04_test.dart:167/238`、`test/features/browser/brw_05_test.dart:55`（全部 `addTearDown(container.dispose)`，仓库编译实证 10+ 处）

- **[REF-15-S2]** 现状：文件内其余测试行为（T01 定时器 / T02 存进度 / T03 切歌交互）由既有断言锚定，与 teardown 形态无关
  ```
  Given 本文件 488 行、3 组 18 个用例
  When 逐用例核对
  Then 断言全部针对 TimerService / MockAudioPlayer / ProviderContainer 的读取与 verify，无一处依赖 teardown 行为
  And 当前机械验证：test/features/coverage/ 377 用例全过（cr-0806 报告）——坏形态未造成测试失败
  ```
  Code evidence: `test/features/coverage/int_g06_lifecycle_test.dart:25-203`（T01 组）/ :211-372（T02 组）/ :379-487（T03 组）

### 3.2 修改方案（status: new）

设计裁决（用户裁决"修"，cr D3 修复建议原文："改为 `addTearDown(container.dispose)`"）：

**可行性依据（铁律 6）**：
- `ProviderContainer.dispose` 签名：riverpod **2.6.1** `lib/src/framework/container.dart:625` —— `void dispose()`（同步、非 Future）。本机 pub-cache 实证（`~/.pub-cache/hosted/pub.dev/riverpod-2.6.1/lib/src/framework/container.dart:625`）。
- `addTearDown` 签名（flutter_test）：`void addTearDown(AsyncCallback callback)`，`AsyncCallback = FutureOr<void> Function()`。tear-off `container.dispose` 类型为 `void Function()`，可赋值给 `FutureOr<void> Function()`（void 在返回位置是 `FutureOr<void>` 的子类型）——赋值合法。
- 仓库编译实证：`test/core/bug_13_repro_test.dart:233/256`、`test/features/browser/o3_create_queue_play_mode_test.dart:68`、`test/features/browser/bug_bug31_repro_test.dart:99/149/179`、`test/features/browser/bug_06_repro_test.dart:178`、`test/features/browser/brw_04_test.dart:167/238`、`test/features/browser/brw_05_test.dart:55` 均以 `addTearDown(container.dispose)` 形态在 CI 全绿——同款模式现有代码在用，不需额外验证。
- 用户提示中"await 形态"（如 `addTearDown(() async => container.dispose())`）**不需要**：dispose 为同步 void，tear-off 直接传递形态即最简且与 cr 建议/仓库先例一致。**禁止**使用 `() => container.dispose`（当前坏形态）或 `() async => container.dispose`（不带括号，仍是 tear-off 不执行）。
- 修复后 teardown 语义变化：容器状态与订阅在用例结束后被释放。本文件用例无周期 timer/常驻监听（S2 逆抽证据），修复不改变任何用例的通过/失败结果——仅释放资源。

| 边界情况 | 裁决 |
|---|---|
| 8 处坏形态的替换 | 逐行替换为 `addTearDown(container.dispose);`（不带闭包、不带括号） |
| 测试断言 | **零改动**（S2 逆抽证据：断言与 teardown 形态无关） |
| 是否新增用例验证 dispose 被调 | 不新增（flutter_test 的 addTearDown 执行回调是框架语义，既有 10+ 处同形态先例已证明；且 dispose 幂等，重复执行无害） |
| 同文件其它资源 | 无其它资源需清理（文件内不创建 StreamSubscription / Timer / MethodChannel） |

- **[REF-15-S3]** 8 处坏形态逐行替换为 `addTearDown(container.dispose);` （status: new）
  ```
  Given test/features/coverage/int_g06_lifecycle_test.dart 第 137/164/222/239/296/321/454/478 行
  When dev-exe 逐行替换
  Then 每行 `addTearDown(() => container.dispose);` → `addTearDown(container.dispose);`
  And 修改后测试用例结束后 ProviderContainer.dispose 被实际调用（riverpod 2.6.1 container.dart:625，
      同步执行，释放 provider 元素与订阅）
  否定断言:
    - 不得保留任何 `addTearDown(() => container.dispose)`（不带调用括号的闭包形态）——grep 该坏形态在文件内零残留
    - 不得改成 `addTearDown(() => container.dispose())` 以外的带闭包形态（统一 tear-off 直接传递，对齐 cr 建议与仓库先例）
    - 不得改动用例内任何断言、ProviderContainer 构造、override 配置（137/164 行所属用例的 timerServiceProvider/audioPlayerProvider override、222/239/296/321 的 saveProgressProvider override、454/478 的 timerServiceProvider override 原样保留）
  ```
  Code evidence（修改点）: `test/features/coverage/int_g06_lifecycle_test.dart:137/164/222/239/296/321/454/478` 逐行。

- **[REF-15-S4]** 修改后全文件回归：18 个用例断言零改动、测试全绿 （status: new）
  ```
  Given 上述 8 处替换完成
  When flutter test test/features/coverage/int_g06_lifecycle_test.dart
  Then 18 个用例全部 PASS（T01 组 7 用例 / T02 组 7 用例 / T03 组 4 用例）
  And flutter analyze --no-fatal-infos 0 error / 0 warning（本文件无新引入 warning）
  否定断言:
    - 不得增删任何 test/group 结构、不得新增用例、不得改动任何 expect/verify 断言
    - 不得触碰 TimerService / MockAudioPlayer 被测逻辑（无任何 import 变化）
  ```
  Code evidence（修改点）: 同文件；回归命令 `flutter test test/features/coverage/int_g06_lifecycle_test.dart`。

---

## §4 不变量

- **[REF-15-INV1]** 文件内任何 `addTearDown` 必须真实执行其参数（不得出现返回 tear-off 的闭包坏形态）
  证据：坏形态 `addTearDown(() => container.dispose)` 为唯一"编译通过但不执行"的形态（S1 逆抽证据：`void Function()` tear-off 可赋值给 `AsyncCallback`）；修复后文件内 8 处均为 `addTearDown(container.dispose)` 直接传递形态（S3），与仓库 10+ 处正确先例一致（bug_13_repro_test.dart:233 等）。
  测试断言：S3 否定断言"grep 坏形态零残留"覆盖。

---

## §5 测试规约

### 5.1 现有测试清单

| 测试文件 | 覆盖的 Scenario / INV | 备注 |
|---|---|---|
| test/features/coverage/int_g06_lifecycle_test.dart | REF-15-S1、S2、S3、S4、REF-15-INV1 | 本文件自身既是修改对象又是回归锚（18 用例断言不变） |

### 5.2 测试 ID 派生清单（dev-exe 派发测试 Agent 用）

```
REF-15-S1 … S2        # 现状逆抽（S1 坏形态锚定 / S2 断言无关性，实现前快照）
REF-15-S3 … S4        # 修改目标（S3 逐行替换 + grep 校验；S4 全文件回归）
REF-15-INV1           # 不变量（S3 否定断言实现）
```

dev-exe 要求：S3 由源码修改 + grep 残留校验实现；S4 由 `flutter test test/features/coverage/int_g06_lifecycle_test.dart` 全绿实现；S1/S2 为现状锚定不写测试。

### 5.3 测试覆盖盲点（dev-plan 写本文档时识别）

| 未覆盖 ID | 现状 | 应补偿方式 |
|---|---|---|
| 无 | — | 本条目为纯测试代码修正，行为锚定 = 文件自身 18 用例回归 + 源码级 grep 校验 |

### 5.4 测试文件位置（spec-scan --gate 硬校验）

无新建测试文件——修改对象即测试文件自身。门禁 = 既有文件存在性 + 全绿：

| 测试文件 | 覆盖 ID | 说明 |
|---|---|---|
| test/features/coverage/int_g06_lifecycle_test.dart | REF-15-S3、S4、REF-15-INV1 | 既有文件（修改对象）：修改后必须全绿（cov-gate 内）；dev-exe 另执行 `grep -rn "addTearDown(() => container.dispose)" test/features/coverage/int_g06_lifecycle_test.dart` 确认零残留（该坏形态在文件内不再出现） |

---

## §6 算法样例

无纯函数算法，跳过。

---

## §7 跨模块影响

本条目只改 `test/features/coverage/int_g06_lifecycle_test.dart` 一个文件，不触碰任何 lib/ 生产代码：

| 其它位置 | 影响点 | 影响条件 | 需要补的回归断言 |
|---|---|---|---|
| test/features/coverage/ 目录其余 15 文件 | 无（不触碰） | — | 既有用例全绿即可 |
| 同仓库其它 `addTearDown(container.dispose)` 正确形态（bug_13_repro_test.dart:233/256、o3_create_queue_play_mode_test.dart:68、bug_bug31_repro_test.dart:99/149/179、bug_06_repro_test.dart:178、brw_04_test.dart:167/238、brw_05_test.dart:55、int_g01_connection_switch_test.dart:221、int_g05_routing_test.dart:59 等） | 无（正确形态不受影响） | — | 不触碰 |
| lib/（全部生产代码） | 无 | — | flutter analyze 0 warning |

---

## §8 平台特性与手动 QA

设计前已逐条核对 `docs/dev/platform-pitfalls.md`：本条目不触及 P1~P17 任何条目（纯 flutter_test 测试代码修正，不涉 audio_service / 监听器生命周期 / Provider 生产行为 / 平台通道——ProviderContainer 释放是 riverpod 容器语义，非应用侧生命周期）。

**真机风险列**：

| 风险 | 近似测试方案 | 测不了 → 进 mqa-backlog |
|---|---|---|
| 无（改动全部在 `flutter test` 可验证范围内：文件 18 用例全绿 + grep 校验） | §5.4 回归命令 | 无 |

本功能不涉及平台原生特性，全部可在 `flutter test` 中验证 → `manual_qa_required = false`。

---

## §9 dev-status.json 条目对照

```json
"REF-15": {
  "spec_file": "docs/features/REF-15.md",
  "spec_anchored_files": [
    "test/features/coverage/int_g06_lifecycle_test.dart"
  ],
  "scenarios": ["REF-15-S3", "REF-15-S4"],
  "invariants": ["REF-15-INV1"],
  "algorithms": [],
  "manual_qa_required": false,
  "user_acceptance_text": "见 §1.2"
}
```

注：S1~S2 为现状逆抽锚定（实现前行为快照），不入 scenarios 清单。
