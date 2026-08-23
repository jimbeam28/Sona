# REF-19 — 进度恢复判定阈值单源化（UI 两处魔数改引 progress_policy）

```yaml
id: REF-19
name: 5 秒进度阈值魔数三处重复收敛到 shouldSave 单源
priority: P4
status: active
created_at: 2026-08-23
last_updated: 2026-08-23
spec_anchored_files:
  - lib/core/contracts/progress_policy.dart
  - lib/features/browser/browser_screen.dart
  - lib/features/playlist/playlist_detail_screen.dart
cross_module_impacts: []
parent_feature: Progress
manual_qa_required: false
```

---

## §1 用户视角

### 1.0 原始需求（来源逐字记录）

> 来源：docs/cr/cr-20260823-1421.md D1（走查 DESIGN 条目；用户裁决 2026-08-23 选定"修（转需求流程）"）。
>
> "5 秒进度阈值魔数三处重复：progress_policy.dart:13（`shouldSave => positionMs >= 5000` 单源定义）vs browser_screen.dart:142 与 playlist_detail_screen.dart:55 各自硬编码 `>= 5000`。两处 UI 判定与 policy 当前一致；若 PRG-T03 阈值将来调整，两个 UI 判定点会静默漂移，出现'对话框弹出条件 ≠ 保存条件'。"

### 1.1 一句话

"什么算看过（值得问要不要续播）"只有一条规则、一个定义处——所有问这个问题的代码都引用它。

### 1.2 用户期望的场景

| ID | 你看到的样子 | 期望行为 |
|----|----|----|
| U1 | 点开一个保存了 ≥5 秒进度的文件 | 弹出续播询问（现状不变） |
| U2 | 点开一个保存了 <5 秒进度的文件 | 直接从头播，不弹窗（现状不变） |
| U3 | 未来调整"算看过"的秒数 | 浏览器与播放单两处入口同时生效，永不分叉 |

---

## §2 已实现骨架（逆抽锚点）

| 层 | 文件 | 角色 |
|---|---|---|
| Policy | lib/core/contracts/progress_policy.dart:13 | `bool shouldSave(int positionMs) => positionMs >= 5000;`——PRG-T03 单源定义；ProgressDao.upsert 已消费（:112） |
| UI | lib/features/browser/browser_screen.dart:142 | `if (progress != null && progress.positionMs >= 5000)` ——魔数副本一（缺陷点） |
| UI | lib/features/playlist/playlist_detail_screen.dart:55 | 同式硬编码——魔数副本二（缺陷点） |

---

## §3 行为规约

### 3.1 现状锚定（逆抽）

- **[REF-19-S0]** 三处判定当前数值等价：positionMs ≥ 5000 才进入续播询问分支
  Code evidence: 上表三处 file:line

### 3.2 需求目标

- **[REF-19-S1]** UI 续播询问判定改引单源 policy 函数（`status: new`）
  ```
  Given browser / playlist_detail 两处点播入口的续播询问前置判断
  When 判定是否弹出示ProgressResumeDialog
  Then 判定表达式改为调用 ProgressDao.shouldSave(progress.positionMs)（静态转发，见 progress_dao.dart:250-251）
       且行为与现状逐字节一致（≥5000 弹、<5000 不弹）
  否定断言:
    - 不修改 progress_policy.dart 的阈值本体与函数签名
    - 不修改 ProgressResumeDialog 及其后续 resume==false 清除逻辑
    - 不引入新的 provider/状态层（仅表达式级替换）
  ```
  Code evidence: 修改点 `browser_screen.dart:142`、`playlist_detail_screen.dart:55`

边界裁决表：

| 输入 | 裁决 |
|---|---|
| positionMs == 4999 | 不弹窗（现状） |
| positionMs == 5000 | 弹窗（现状） |
| progress == null | 不弹窗（外层 null 检查保留原样） |

---

## §4 不变量

- **[REF-19-INV1]** "5 秒看过阈值"在 lib/ 内有且仅有一个数值定义点（progress_policy.dart），其余消费方一律经 shouldSave 引用
  证据：修改后 grep `>= 5000` 于 lib/ 应零命中（policy 定义行除外）

---

## §5 测试规约

### 5.1 现有测试清单

| 测试文件 | 覆盖 | 备注 |
|---|---|---|
| test/features/progress/prg_test.dart | shouldSave 边界语义 | 全绿即可（行为锚定来源） |
| test/features/browser/brw 系 / playlist 系 | 点播链路 | 全绿即可 |

### 5.2 测试 ID 派生清单

```
REF-19-S1, REF-19-INV1
```

### 5.3 测试覆盖盲点

无新增盲点——纯表达式替换，行为面被 prg_test 边界用例覆盖。

### 5.4 门禁测试文件（spec-scan --gate 硬校验）

| 测试文件 | 覆盖 ID | 说明 |
|---|---|---|
| test/features/progress/ref_19_threshold_single_source_test.dart | REF-19-S1/INV1 | 结构断言（lib/ 全量扫描 `>= 5000` 仅 policy 定义处命中）；修复前 FAIL，修复后必须 PASS |

---

## §6 算法样例

不涉及纯函数算法，跳过。

---

## §7 跨模块影响

impact 反查（2026-08-23）：两 UI 文件的调用方均经 shared/di 桥接或路由直达，无第三方复制该魔数（grep `>= 5000` 全库仅此三处 + policy）。

| 其它模块 | 影响点 | 影响条件 | 回归断言要求 |
|---|---|---|---|
| progress | policy 本体 | 零变更 | prg_test 全绿 |
| player | showProgressResumeDialog | 零变更 | ref_24/ref_25 全绿 |

**修改点（弱模型照单执行）**：
1. `lib/features/browser/browser_screen.dart:142` 改为：
   ```dart
   if (progress != null && ProgressDao.shouldSave(progress.positionMs)) {
   ```
   并补 import `'../../core/database/dao/progress_dao.dart' show ProgressDao;`
2. `lib/features/playlist/playlist_detail_screen.dart:55` 同式替换（该文件已有 progress 域 import 面，同样补 ProgressDao show import）。
3. 回归：cov-gate --skip-test + flutter test 全绿。

---

## §8 平台特性与手动 QA

核对踩坑库：无交集。纯表达式替换，manual_qa_required=false。

---

## §9 dev-status.json 条目对照

```json
"REF-19": {
  "spec_file": "docs/features/REF-19.md",
  "spec_anchored_files": [
    "lib/core/contracts/progress_policy.dart",
    "lib/features/browser/browser_screen.dart",
    "lib/features/playlist/playlist_detail_screen.dart"
  ],
  "scenarios": ["REF-19-S1"],
  "invariants": ["REF-19-INV1"],
  "algorithms": [],
  "manual_qa_required": false,
  "user_acceptance_text": "见 §1.2"
}
```
