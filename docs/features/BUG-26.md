# BUG-26 — state_notifier 被 domain 直接 import 但未声明于 pubspec dependencies

```yaml
id: BUG-26
name: state_notifier 传递依赖侥幸（depend_on_referenced_packages ×2）
priority: P4
status: active
created_at: 2026-08-23
last_updated: 2026-08-23
spec_anchored_files:
  - pubspec.yaml
  - lib/features/browser/domain/directory_service.dart
  - lib/features/browser/domain/navigation_stack.dart
cross_module_impacts: []
parent_feature: Browser
manual_qa_required: false
```

---

## §1 用户视角

### 1.0 原始需求（来源逐字记录）

> 来源：docs/cr/cr-20260823-1421.md F4（走查发现，复核确认仍存在，2026-08-23 分流）。
>
> "lib/features/browser/domain/directory_service.dart:5 与 navigation_stack.dart:5 直接 import package:state_notifier，但 pubspec.yaml dependencies 未声明该包（analyze depend_on_referenced_packages ×2，info 级故 cov-gate 放行）。当前编译依赖 flutter_riverpod 的传递暴露。复现路径（条件化）：riverpod 升级后不再传递导出 state_notifier → domain 两文件直接编译失败。"
> 自检答案："机械门禁以 warning 为界，info 级依赖卫生问题不在 cov-gate 判定集内。"
> 复核裁决（2026-08-23）：FRAGILE/Minor → dev-plan Bug 流程。

### 1.1 一句话

代码里直接用到的第三方包，必须在依赖清单里写明——不能靠"别的包顺便带进来了"活着。

### 1.2 用户期望的场景

| ID | 你看到的样子 | 期望行为 |
|----|----|----|
| U1 | 开发者升级 flutter_riverpod 版本 | 浏览器排序/目录导航功能照常编译运行，不因上游内部依赖变化而断裂 |

---

## §2 已实现骨架（逆抽锚点）

| 层 | 文件 | 角色 |
|---|---|---|
| Domain | lib/features/browser/domain/directory_service.dart:5 | `import 'package:state_notifier/state_notifier.dart';`（SortOptionNotifier extends StateNotifier） |
| Domain | lib/features/browser/domain/navigation_stack.dart:5 | 同上（NavigationStackNotifier extends StateNotifier） |
| Infra | pubspec.yaml dependencies 节 | 无 state_notifier 条目；state_notifier 由 flutter_riverpod 2.x 传递暴露 |
| 门禁 | analyze | depend_on_referenced_packages ×2（info 级，cov-gate 以 warning 为界放行） |
| 门禁测试 | test/core/bug_bug26_pubspec_state_notifier_test.dart | 结构断言（BUG-18-INV1 源码扫描同款先例），修复前 FAIL |

---

## §3 行为规约

### 3.1 现状锚定（逆抽）

- **[BUG-26-S0]** 依赖卫生规则：直接 import 的包必须显式声明于 pubspec 主依赖段
  Code evidence: 违例点 `directory_service.dart:5`、`navigation_stack.dart:5` + pubspec.yaml dependencies 节（无 state_notifier）

### 3.2 修复目标

- **[BUG-26-S1]** state_notifier 显式声明于主依赖（`status: new`）
  ```
  Given directory_service / navigation_stack 直接 import state_notifier
  When 解析 pubspec.yaml 的 dependencies 段（dev_dependencies 之前）
  Then 存在 state_notifier 条目且带版本约束
  否定断言:
    - 不把 import 改为绕道（不得删除两处直接 import 改用其它类型替代 StateNotifier 基类）
    - 不移动到 dev_dependencies（运行期直引语义要求主依赖段）
    - flutter_riverpod / 其它既有依赖条目零变更
  ```
  Code evidence: 修改点 `pubspec.yaml` dependencies 节（`http: ^1.2.1` 之后追加）

版本约束裁决：与仓库内 flutter_riverpod 2.6.1 解析出的传递版本对齐——`state_notifier: ^1.0.0`（riverpod 2.x 官方依赖 state_notifier ^1.0.0；宽松下限约束避免与 riverpod 锁定冲突）。若 pub get 报冲突，以 `flutter pub deps` 实际解析版本回填上界。

---

## §4 不变量

- **[BUG-26-INV1]** pubspec 主依赖段必须覆盖 lib/ 全部直接 import 的外部 package（cross-imports domain-flutter 门禁保证 domain 只可引纯 Dart 包，本条补齐其声明完整性）
  证据：pubspec.yaml dependencies 节 vs lib/ 全量 import 扫描

---

## §5 测试规约

### 5.1 现有测试清单

| 测试文件 | 覆盖 | 备注 |
|---|---|---|
| test/features/browser/ref_17_test.dart 等 | SortOptionNotifier / NavigationStack 行为 | 全绿即可（证明声明后行为零变更） |

### 5.2 测试 ID 派生清单

```
BUG-26-S1, BUG-26-INV1
```

### 5.3 测试覆盖盲点

riverpod 未来版本是否移除传递导出不可测——本修复即消除该暴露面。

### 5.4 门禁测试文件（spec-scan --gate 硬校验）

| 测试文件 | 覆盖 ID | 说明 |
|---|---|---|
| test/core/bug_bug26_pubspec_state_notifier_test.dart | BUG-26-S1 | 修复前 FAIL 已由 repro-test.sh fail 确认（2026-08-23）；修复后必须 PASS |

---

## §6 算法样例

不涉及纯函数算法，跳过。

---

## §7 跨模块影响

impact 反查（2026-08-23）：directory_service / navigation_stack ← browser_provider（re-export + 装配）、shared/di/providers.dart。

| 其它模块 | 影响点 | 影响条件 | 回归断言要求 |
|---|---|---|---|
| browser provider 层 | sortOptionProvider / navigationStackProvider 装配 | 零变化 | brw 系列测试全绿 |
| shared/di | re-export 面 | 零变化 | int_g05_routing 等全绿 |

**修改点（弱模型照单执行）**：
1. `pubspec.yaml` dependencies 节在 `http: ^1.2.1` 条目之后新增一行：
   ```yaml
   state_notifier: ^1.0.0
   ```
2. `flutter pub get` 后 `bash ../../scripts/cov-gate.sh --skip-test`：analyze 的 depend_on_referenced_packages ×2 归零，其余 0 warning。
3. 全量回归：flutter test 全绿。

---

## §8 平台特性与手动 QA

核对踩坑库：无交集（纯依赖声明）。manual_qa_required=false。

---

## §9 dev-status.json 条目对照

```json
"BUG-26": {
  "spec_file": "docs/features/BUG-26.md",
  "spec_anchored_files": [
    "pubspec.yaml",
    "lib/features/browser/domain/directory_service.dart",
    "lib/features/browser/domain/navigation_stack.dart"
  ],
  "scenarios": ["BUG-26-S1"],
  "invariants": ["BUG-26-INV1"],
  "algorithms": [],
  "manual_qa_required": false,
  "user_acceptance_text": "见 §1.2"
}
```
